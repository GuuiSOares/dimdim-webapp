#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"
ARTIFACTS_DIR="${ROOT_DIR}/artifacts"
PUBLISH_DIR="${ARTIFACTS_DIR}/publish"
ZIP_PATH="${ARTIFACTS_DIR}/dimdim.zip"

trap 'echo "Falha no deploy (linha ${LINENO})." >&2' ERR

[[ -f "${CONFIG_FILE}" ]] || {
  echo "Arquivo scripts/config.sh não encontrado." >&2
  exit 1
}
source "${CONFIG_FILE}"

for command_name in az dotnet curl; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "Comando obrigatório não encontrado: ${command_name}" >&2
    exit 1
  }
done

PYTHON_BIN=""
if ! command -v zip >/dev/null 2>&1; then
  for candidate in python3 python; do
    if command -v "${candidate}" >/dev/null 2>&1 &&
       "${candidate}" -c "import zipfile" >/dev/null 2>&1; then
      PYTHON_BIN="${candidate}"
      break
    fi
  done
  [[ -n "${PYTHON_BIN}" ]] || {
    echo "Instale o comando zip ou Python 3 com o módulo zipfile." >&2
    exit 1
  }
fi

az account set --subscription "${AZURE_SUBSCRIPTION_NAME}"
active_subscription="$(az account show --query name -o tsv)"
[[ "${active_subscription}" == "${AZURE_SUBSCRIPTION_NAME}" ]] || {
  echo "Assinatura ativa incorreta. Esperada: ${AZURE_SUBSCRIPTION_NAME}" >&2
  exit 1
}
az account show --query '{subscription:name, tenant:tenantId}' -o table
az webapp show --resource-group "${RESOURCE_GROUP}" --name "${WEBAPP_NAME}" --query name -o tsv >/dev/null

rm -rf "${PUBLISH_DIR}" "${ZIP_PATH}"
mkdir -p "${PUBLISH_DIR}"

dotnet restore "${ROOT_DIR}/DimDim.sln"
dotnet publish "${ROOT_DIR}/src/DimDim.Web/DimDim.Web.csproj" \
  --configuration Release \
  --no-restore \
  --output "${PUBLISH_DIR}"

if command -v zip >/dev/null 2>&1; then
  (
    cd "${PUBLISH_DIR}"
    zip -q -r "${ZIP_PATH}" .
  )
else
  "${PYTHON_BIN}" - "${PUBLISH_DIR}" "${ZIP_PATH}" <<'PY'
from pathlib import Path
import sys
import zipfile

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in source.rglob("*"):
        if path.is_file():
            archive.write(path, path.relative_to(source))
PY
fi

az webapp deploy \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${WEBAPP_NAME}" \
  --src-path "${ZIP_PATH}" \
  --type zip \
  --clean true \
  --restart true \
  --output none

az webapp restart --resource-group "${RESOURCE_GROUP}" --name "${WEBAPP_NAME}"

health_url="https://${WEBAPP_NAME}.azurewebsites.net/health"
for attempt in {1..18}; do
  status_code="$(curl --silent --show-error --location --output /dev/null --write-out '%{http_code}' "${health_url}" || true)"
  if [[ "${status_code}" == "200" ]]; then
    echo "Deploy concluído. Health check HTTP 200."
    echo "URL: https://${WEBAPP_NAME}.azurewebsites.net"
    exit 0
  fi
  echo "Aguardando aplicação (${attempt}/18, HTTP ${status_code})..."
  sleep 10
done

echo "Deploy enviado, mas /health não retornou 200 no prazo." >&2
echo "Consulte: az webapp log tail -g ${RESOURCE_GROUP} -n ${WEBAPP_NAME}" >&2
exit 1
