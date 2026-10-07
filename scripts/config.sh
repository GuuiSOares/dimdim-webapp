#!/usr/bin/env bash

RM="rm562673"
LOCATION="spaincentral"
AZURE_SUBSCRIPTION_NAME="Geovanne"

UNIQUE_SUFFIX="${RM//[^a-zA-Z0-9]/}"

RESOURCE_GROUP="rg-dimdim-${RM}"
LOG_ANALYTICS_WORKSPACE="log-dimdim-${RM}"
APP_INSIGHTS_NAME="appi-dimdim-${RM}"
APP_SERVICE_PLAN="plan-dimdim-${RM}"
WEBAPP_NAME="app-dimdim-${UNIQUE_SUFFIX}"
KEY_VAULT_NAME="kvdimdim${UNIQUE_SUFFIX:0:13}ap"
SQL_SERVER_NAME="sql-dimdim-${UNIQUE_SUFFIX}-spc"
SQL_DATABASE_NAME="sqldb-dimdim"

CURRENT_IP=""
