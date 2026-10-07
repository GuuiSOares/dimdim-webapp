#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

[[ -f "${CONFIG_FILE}" ]] || {
  echo "Arquivo scripts/config.sh não encontrado." >&2
  exit 1
}
source "${CONFIG_FILE}"

az account set --subscription "${AZURE_SUBSCRIPTION_NAME}"
active_subscription="$(az account show --query name -o tsv)"
[[ "${active_subscription}" == "${AZURE_SUBSCRIPTION_NAME}" ]] || {
  echo "Assinatura ativa incorreta. Esperada: ${AZURE_SUBSCRIPTION_NAME}" >&2
  exit 1
}

echo "ATENÇÃO: esta ação exclui permanentemente todos os recursos do grupo:"
echo "  ${RESOURCE_GROUP}"
read -r -p "Para confirmar, digite exatamente o nome do Resource Group: " confirmation

if [[ "${confirmation}" != "${RESOURCE_GROUP}" ]]; then
  echo "Nome diferente. Nenhum recurso foi excluído."
  exit 1
fi

az account show --query '{assinatura:name, estado:state}' -o table
read -r -p "Última confirmação. Digite EXCLUIR: " final_confirmation
[[ "${final_confirmation}" == "EXCLUIR" ]] || {
  echo "Operação cancelada."
  exit 1
}

key_vaults="$(az keyvault list \
  --resource-group "${RESOURCE_GROUP}" \
  --query '[].[name,location]' -o tsv)"

az group delete --name "${RESOURCE_GROUP}" --yes

while IFS=$'\t' read -r vault_name vault_location; do
  [[ -n "${vault_name}" ]] || continue
  purged=false
  for attempt in {1..12}; do
    if az keyvault purge \
      --name "${vault_name}" \
      --location "${vault_location}" \
      --no-wait >/dev/null 2>&1; then
      purged=true
      break
    fi
    sleep 5
  done
  if [[ "${purged}" != true ]]; then
    echo "Aviso: não foi possível purgar o Key Vault ${vault_name}." >&2
    echo "Use um UNIQUE_SUFFIX diferente antes do próximo provisionamento." >&2
  fi
done <<< "${key_vaults}"

echo "Limpeza concluída."
