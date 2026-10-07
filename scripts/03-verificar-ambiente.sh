#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

[[ -f "${CONFIG_FILE}" ]] || {
  echo "Arquivo scripts/config.sh não encontrado." >&2
  exit 1
}
source "${CONFIG_FILE}"

az_with_resource_id() {
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" az "$@"
}

for command_name in az curl; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "Comando obrigatório não encontrado: ${command_name}" >&2
    exit 1
  }
done
az account set --subscription "${AZURE_SUBSCRIPTION_NAME}"
active_subscription="$(az account show --query name -o tsv)"
[[ "${active_subscription}" == "${AZURE_SUBSCRIPTION_NAME}" ]] || {
  echo "Assinatura ativa incorreta. Esperada: ${AZURE_SUBSCRIPTION_NAME}" >&2
  exit 1
}
az extension show --name application-insights >/dev/null 2>&1 || {
  echo "Extensão application-insights ausente. Execute primeiro scripts/01-provisionar-infra.sh." >&2
  exit 1
}

echo "=== Conta e assinatura ativas ==="
subscription_name="$(az account show --query name -o tsv)"
subscription_id="$(az account show --query id -o tsv)"
echo "Assinatura: ${subscription_name}"
echo "ID: ${subscription_id:0:8}... (ocultado)"

echo "=== Recursos do grupo ==="
az resource list --resource-group "${RESOURCE_GROUP}" \
  --query '[].{nome:name, tipo:type, localizacao:location}' -o table

echo "=== Web App ==="
az webapp show --resource-group "${RESOURCE_GROUP}" --name "${WEBAPP_NAME}" \
  --query '{nome:name, estado:state, host:defaultHostName, httpsOnly:httpsOnly, identidade:identity.type}' -o table
echo "URL: https://${WEBAPP_NAME}.azurewebsites.net"
curl --silent --show-error --location --output /dev/null --write-out 'Health HTTP %{http_code}\n' \
  "https://${WEBAPP_NAME}.azurewebsites.net/health"

echo "=== Application Insights (sem connection string) ==="
az monitor app-insights component show \
  --resource-group "${RESOURCE_GROUP}" \
  --app "${APP_INSIGHTS_NAME}" \
  --query '{nome:name, tipo:applicationType, workspace:workspaceResourceId, estado:provisioningState}' -o table

echo "=== Requisições recentes no Application Insights ==="
az monitor app-insights query \
  --resource-group "${RESOURCE_GROUP}" \
  --app "${APP_INSIGHTS_NAME}" \
  --analytics-query \
    "requests | where timestamp > ago(30m) | summarize total=count(), falhas=countif(success == false), duracaoMediaMs=avg(duration) by bin(timestamp, 5m) | order by timestamp desc" \
  -o table

echo "=== Dependências SQL recentes ==="
az monitor app-insights query \
  --resource-group "${RESOURCE_GROUP}" \
  --app "${APP_INSIGHTS_NAME}" \
  --analytics-query \
    "dependencies | where timestamp > ago(30m) and type has 'SQL' | project timestamp, name, target, success, duration | order by timestamp desc | take 20" \
  -o table

echo "=== Azure SQL ==="
az sql server show --resource-group "${RESOURCE_GROUP}" --name "${SQL_SERVER_NAME}" \
  --query '{servidor:name, fqdn:fullyQualifiedDomainName, estado:state, versao:minimalTlsVersion}' -o table
az sql db show --resource-group "${RESOURCE_GROUP}" --server "${SQL_SERVER_NAME}" --name "${SQL_DATABASE_NAME}" \
  --query '{banco:name, status:status, tier:currentServiceObjectiveName, redundancia:requestedBackupStorageRedundancy}' -o table

sql_database_id="$(az sql db show \
  --resource-group "${RESOURCE_GROUP}" \
  --server "${SQL_SERVER_NAME}" \
  --name "${SQL_DATABASE_NAME}" \
  --query id -o tsv)"
az_with_resource_id monitor metrics list \
  --resource "${sql_database_id}" \
  --metric cpu_percent,dtu_consumption_percent,storage_percent \
  --interval PT5M \
  --aggregation Average \
  --query 'value[].{metrica:name.localizedValue, media:data[-1].average}' -o table

command -v sqlcmd >/dev/null 2>&1 || {
  echo "Comando obrigatório não encontrado: sqlcmd" >&2
  exit 1
}

if [[ -z "${SQL_ADMIN_USER:-}" ]]; then
  SQL_ADMIN_USER="$(az sql server show --resource-group "${RESOURCE_GROUP}" --name "${SQL_SERVER_NAME}" \
    --query administratorLogin -o tsv)"
fi
if [[ -z "${SQL_ADMIN_PASSWORD:-}" ]]; then
  read -r -s -p "Senha SQL (não será exibida): " SQL_ADMIN_PASSWORD
  echo
fi
export SQLCMDPASSWORD="${SQL_ADMIN_PASSWORD}"

echo "=== Registros de conta ==="
sqlcmd -S "tcp:${SQL_SERVER_NAME}.database.windows.net,1433" \
  -d "${SQL_DATABASE_NAME}" -U "${SQL_ADMIN_USER}" \
  -f 65001 \
  -Q "SET NOCOUNT ON; SELECT id, nome, instituicao, tipo, saldo_inicial FROM dbo.conta ORDER BY id;" -b

echo "=== Registros de transacao ==="
sqlcmd -S "tcp:${SQL_SERVER_NAME}.database.windows.net,1433" \
  -d "${SQL_DATABASE_NAME}" -U "${SQL_ADMIN_USER}" \
  -f 65001 \
  -Q "SET NOCOUNT ON; SELECT id, descricao, valor, tipo, data, conta_id FROM dbo.transacao ORDER BY id;" -b

unset SQLCMDPASSWORD SQL_ADMIN_PASSWORD
echo "Verificação concluída."
