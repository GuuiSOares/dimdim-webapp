#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

trap 'echo "Erro na linha ${LINENO}. Revise a mensagem acima." >&2' ERR

[[ -f "${CONFIG_FILE}" ]] || {
  echo "Arquivo scripts/config.sh não encontrado." >&2
  exit 1
}
source "${CONFIG_FILE}"

az_with_resource_id() {
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" az "$@"
}

required=(az sqlcmd curl)
for command_name in "${required[@]}"; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    if [[ "${command_name}" == "sqlcmd" ]]; then
      echo "sqlcmd não encontrado. No Cloud Shell, instale o pacote sqlcmd conforme a documentação da Microsoft e execute novamente." >&2
      echo "O Azure CLI padrão não possui um comando confiável 'az sql db query'; este script não inventa esse fallback." >&2
    else
      echo "Comando obrigatório não encontrado: ${command_name}" >&2
    fi
    exit 1
  }
done

echo "Selecionando a assinatura obrigatória: ${AZURE_SUBSCRIPTION_NAME}"
az account set --subscription "${AZURE_SUBSCRIPTION_NAME}"
az extension add --name application-insights --upgrade --only-show-errors

account_name="$(az account show --query name -o tsv)"
subscription_id="$(az account show --query id -o tsv)"
[[ "${account_name}" == "${AZURE_SUBSCRIPTION_NAME}" ]] || {
  echo "Assinatura ativa incorreta. Esperada: ${AZURE_SUBSCRIPTION_NAME}" >&2
  exit 1
}
echo "Assinatura ativa: ${account_name}"
echo "Subscription ID: ${subscription_id:0:8}... (ocultado)"
if [[ "${CONFIRM_SUBSCRIPTION:-}" != "yes" ]]; then
  read -r -p "Continuar nesta assinatura? Digite SIM: " confirmation
  [[ "${confirmation}" == "SIM" ]] || { echo "Operação cancelada."; exit 1; }
fi

if [[ -z "${SQL_ADMIN_USER:-}" ]]; then
  read -r -p "Usuário administrador do SQL: " SQL_ADMIN_USER
fi
[[ "${SQL_ADMIN_USER}" =~ ^[A-Za-z][A-Za-z0-9_]{2,}$ ]] || {
  echo "Usuário inválido: use ao menos 3 caracteres, começando por letra (letras, números ou _)." >&2
  exit 1
}

if [[ -z "${SQL_ADMIN_PASSWORD:-}" ]]; then
  read -r -s -p "Senha do administrador SQL: " SQL_ADMIN_PASSWORD
  echo
  read -r -s -p "Confirme a senha: " password_confirmation
  echo
  [[ "${SQL_ADMIN_PASSWORD}" == "${password_confirmation}" ]] || {
    echo "As senhas não coincidem." >&2
    exit 1
  }
fi

if (( ${#SQL_ADMIN_PASSWORD} < 12 )) ||
   [[ ! "${SQL_ADMIN_PASSWORD}" =~ [A-Z] ]] ||
   [[ ! "${SQL_ADMIN_PASSWORD}" =~ [a-z] ]] ||
   [[ ! "${SQL_ADMIN_PASSWORD}" =~ [0-9] ]] ||
   [[ "${SQL_ADMIN_PASSWORD}" =~ ^[[:alnum:]]+$ ]]; then
  echo "Use ao menos 12 caracteres, com maiúscula, minúscula, número e símbolo." >&2
  exit 1
fi

providers=(
  Microsoft.Web
  Microsoft.Sql
  Microsoft.KeyVault
  Microsoft.Insights
  Microsoft.OperationalInsights
)
for provider in "${providers[@]}"; do
  az provider register --namespace "${provider}" --output none
done
for provider in "${providers[@]}"; do
  for attempt in {1..24}; do
    state="$(az provider show --namespace "${provider}" --query registrationState -o tsv)"
    [[ "${state}" == "Registered" ]] && break
    (( attempt == 24 )) && { echo "Provider ${provider} não foi registrado a tempo." >&2; exit 1; }
    sleep 5
  done
done

if ! az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
  az group create --name "${RESOURCE_GROUP}" --location "${LOCATION}" --output none
else
  echo "Resource Group ${RESOURCE_GROUP} já existe; reutilizando-o."
fi

if ! az monitor log-analytics workspace show --resource-group "${RESOURCE_GROUP}" --workspace-name "${LOG_ANALYTICS_WORKSPACE}" >/dev/null 2>&1; then
  az monitor log-analytics workspace create \
    --resource-group "${RESOURCE_GROUP}" \
    --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
    --location "${LOCATION}" \
    --output none
fi
workspace_id="$(az monitor log-analytics workspace show \
  --resource-group "${RESOURCE_GROUP}" \
  --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
  --query id -o tsv)"

if ! az monitor app-insights component show --resource-group "${RESOURCE_GROUP}" --app "${APP_INSIGHTS_NAME}" >/dev/null 2>&1; then
  az_with_resource_id monitor app-insights component create \
    --resource-group "${RESOURCE_GROUP}" \
    --app "${APP_INSIGHTS_NAME}" \
    --location "${LOCATION}" \
    --workspace "${workspace_id}" \
    --application-type web \
    --output none
fi
appinsights_connection_string="$(az monitor app-insights component show \
  --resource-group "${RESOURCE_GROUP}" \
  --app "${APP_INSIGHTS_NAME}" \
  --query connectionString -o tsv)"

if ! az keyvault show --resource-group "${RESOURCE_GROUP}" --name "${KEY_VAULT_NAME}" >/dev/null 2>&1; then
  az keyvault create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${KEY_VAULT_NAME}" \
    --location "${LOCATION}" \
    --enable-rbac-authorization false \
    --output none
fi

rbac_enabled="$(az keyvault show \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${KEY_VAULT_NAME}" \
  --query properties.enableRbacAuthorization -o tsv)"
if [[ "${rbac_enabled,,}" == "true" ]]; then
  echo "Key Vault ${KEY_VAULT_NAME} usa RBAC e não pode ser administrado por esta conta." >&2
  echo "Altere KEY_VAULT_NAME em scripts/config.sh para um nome global novo." >&2
  exit 1
fi

signed_in_user_id="$(az ad signed-in-user show --query id -o tsv)"
az keyvault set-policy \
  --name "${KEY_VAULT_NAME}" \
  --object-id "${signed_in_user_id}" \
  --secret-permissions get list set \
  --output none

if ! az sql server show --resource-group "${RESOURCE_GROUP}" --name "${SQL_SERVER_NAME}" >/dev/null 2>&1; then
  az sql server create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${SQL_SERVER_NAME}" \
    --location "${LOCATION}" \
    --admin-user "${SQL_ADMIN_USER}" \
    --admin-password "${SQL_ADMIN_PASSWORD}" \
    --output none
else
  echo "Servidor SQL existente; use a senha correspondente para aplicar o DDL."
fi
az sql server update \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${SQL_SERVER_NAME}" \
  --minimal-tls-version 1.2 \
  --output none

if ! az sql db show --resource-group "${RESOURCE_GROUP}" --server "${SQL_SERVER_NAME}" --name "${SQL_DATABASE_NAME}" >/dev/null 2>&1; then
  az sql db create \
    --resource-group "${RESOURCE_GROUP}" \
    --server "${SQL_SERVER_NAME}" \
    --name "${SQL_DATABASE_NAME}" \
    --service-objective Basic \
    --backup-storage-redundancy Local \
    --output none
fi

az sql server firewall-rule create \
  --resource-group "${RESOURCE_GROUP}" \
  --server "${SQL_SERVER_NAME}" \
  --name AllowAzureServices \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0 \
  --output none

if [[ -z "${CURRENT_IP:-}" ]]; then
  CURRENT_IP="$(curl -fsS https://api.ipify.org || true)"
fi
echo "IP liberado no firewall do SQL: ${CURRENT_IP:-nenhum}"

if [[ -n "${CURRENT_IP:-}" ]]; then
  valid_ip=true
  IFS='.' read -r -a ip_parts <<< "${CURRENT_IP}"
  [[ ${#ip_parts[@]} -eq 4 ]] || valid_ip=false
  for octet in "${ip_parts[@]}"; do
    [[ "${octet}" =~ ^[0-9]{1,3}$ ]] && (( 10#${octet} <= 255 )) || valid_ip=false
  done
  [[ "${valid_ip}" == true ]] || {
    echo "CURRENT_IP deve conter um único IPv4 válido." >&2
    exit 1
  }
  az sql server firewall-rule create \
    --resource-group "${RESOURCE_GROUP}" \
    --server "${SQL_SERVER_NAME}" \
    --name AllowCurrentIp \
    --start-ip-address "${CURRENT_IP}" \
    --end-ip-address "${CURRENT_IP}" \
    --output none
fi

if ! az appservice plan show --resource-group "${RESOURCE_GROUP}" --name "${APP_SERVICE_PLAN}" >/dev/null 2>&1; then
  az appservice plan create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${APP_SERVICE_PLAN}" \
    --location "${LOCATION}" \
    --is-linux \
    --sku F1 \
    --output none
fi

if ! az webapp show --resource-group "${RESOURCE_GROUP}" --name "${WEBAPP_NAME}" >/dev/null 2>&1; then
  az webapp create \
    --resource-group "${RESOURCE_GROUP}" \
    --plan "${APP_SERVICE_PLAN}" \
    --name "${WEBAPP_NAME}" \
    --runtime "DOTNETCORE:8.0" \
    --output none
fi

principal_id="$(az webapp identity assign \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${WEBAPP_NAME}" \
  --query principalId -o tsv)"

az keyvault set-policy \
  --name "${KEY_VAULT_NAME}" \
  --object-id "${principal_id}" \
  --secret-permissions get \
  --output none

escaped_sql_password="${SQL_ADMIN_PASSWORD//\"/\"\"}"
sql_connection_string="Server=tcp:${SQL_SERVER_NAME}.database.windows.net,1433;Initial Catalog=${SQL_DATABASE_NAME};Persist Security Info=False;User ID=${SQL_ADMIN_USER};Password=\"${escaped_sql_password}\";MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
secret_set=false
for attempt in {1..12}; do
  if az keyvault secret set \
      --vault-name "${KEY_VAULT_NAME}" \
      --name DefaultConnection \
      --value "${sql_connection_string}" \
      --output none 2>/dev/null; then
    secret_set=true
    break
  fi
  sleep 5
done
unset escaped_sql_password sql_connection_string
[[ "${secret_set}" == true ]] || { echo "A política de acesso do Key Vault não propagou a tempo. Execute novamente em alguns minutos." >&2; exit 1; }

secret_uri="https://${KEY_VAULT_NAME}.vault.azure.net/secrets/DefaultConnection/"
az webapp config connection-string set \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${WEBAPP_NAME}" \
  --connection-string-type SQLAzure \
  --settings "DefaultConnection=@Microsoft.KeyVault(SecretUri=${secret_uri})" \
  --output none

az webapp config appsettings set \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${WEBAPP_NAME}" \
  --settings \
    "APPLICATIONINSIGHTS_CONNECTION_STRING=${appinsights_connection_string}" \
    "ApplicationInsightsAgent_EXTENSION_VERSION=~3" \
    "ASPNETCORE_ENVIRONMENT=Production" \
  --output none

az webapp update \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${WEBAPP_NAME}" \
  --https-only true \
  --output none
az webapp config set \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${WEBAPP_NAME}" \
  --ftps-state Disabled \
  --min-tls-version 1.2 \
  --linux-fx-version "DOTNETCORE|8.0" \
  --generic-configurations '{"healthCheckPath":"/health"}' \
  --output none

export SQLCMDPASSWORD="${SQL_ADMIN_PASSWORD}"
sqlcmd \
  -S "tcp:${SQL_SERVER_NAME}.database.windows.net,1433" \
  -d "${SQL_DATABASE_NAME}" \
  -U "${SQL_ADMIN_USER}" \
  -f 65001 \
  -i "${ROOT_DIR}/scripts/ddl.sql" \
  -b
unset SQLCMDPASSWORD SQL_ADMIN_PASSWORD SQL_ADMIN_USER

echo "Infraestrutura pronta."
echo "Aplicação: https://${WEBAPP_NAME}.azurewebsites.net"
