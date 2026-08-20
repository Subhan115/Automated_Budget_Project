#!/usr/bin/env bash
# Logic_App_URL.sh - Link Logic App Webhook across different Resource Groups
set -euo pipefail

ENV_FILE=".env"
if [ -f "$ENV_FILE" ]; then
  export $(grep -v '^#' "$ENV_FILE" | xargs)
else
  echo "Error: $ENV_FILE not found. Please run budget.sh and action_group.sh first."
  exit 1
fi

# 1. Action Group RG (Strictly read from ACTION_GROUP_RG in .env)
ACTION_GROUP_RG="${ACTION_GROUP_RG:-}"
if [ -z "$ACTION_GROUP_RG" ]; then
  echo "Error: ACTION_GROUP_RG is missing from $ENV_FILE"
  exit 1
fi

# 2. Logic App RG (Strictly read from LOGIC_APP_RG or LOGIC_APP_RESOURCE_GROUP in .env)
LOGIC_APP_RG="${LOGIC_APP_RG:-${LOGIC_APP_RESOURCE_GROUP:-}}"
if [ -z "$LOGIC_APP_RG" ]; then
  echo "Error: LOGIC_APP_RG (or LOGIC_APP_RESOURCE_GROUP) is missing from $ENV_FILE"
  exit 1
fi

ACTION_GROUP_ID="${ACTION_GROUP_ID:-${ACTION_GROUP_IDS:-}}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"

if [ -z "$ACTION_GROUP_ID" ]; then
  echo "Error: ACTION_GROUP_ID not set in $ENV_FILE"
  exit 1
fi

ACTION_GROUP_NAME=$(basename "$ACTION_GROUP_ID")

echo "Action Group RG   : $ACTION_GROUP_RG"
echo "Action Group Name : $ACTION_GROUP_NAME"
echo "Logic App RG      : $LOGIC_APP_RG"

# Detect Logic App inside LOGIC_APP_RG
echo "Searching for Logic App in $LOGIC_APP_RG..."
LOGIC_APP_NAME=$(az rest --method get \
  --uri "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${LOGIC_APP_RG}/providers/Microsoft.Logic/workflows?api-version=2019-05-01" \
  --query "value[0].name" -o tsv 2>/dev/null || true)

LOGIC_APP_NAME="${LOGIC_APP_NAME:-BudgetSystem}"
echo "Target Logic App  : $LOGIC_APP_NAME"

# Fetch trigger name from Logic App
echo "Fetching Webhook URL from $LOGIC_APP_NAME..."
TRIGGER_NAME=$(az rest \
  --method get \
  --uri "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${LOGIC_APP_RG}/providers/Microsoft.Logic/workflows/${LOGIC_APP_NAME}/triggers?api-version=2019-05-01" \
  --query "value[0].name" -o tsv)

if [ -z "$TRIGGER_NAME" ]; then
  echo "Error: Could not find any trigger in Logic App '$LOGIC_APP_NAME' in resource group '$LOGIC_APP_RG'."
  exit 1
fi

# Generate Callback URL
WEBHOOK_URL=$(az rest \
  --method post \
  --uri "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${LOGIC_APP_RG}/providers/Microsoft.Logic/workflows/${LOGIC_APP_NAME}/triggers/${TRIGGER_NAME}/listCallbackUrl?api-version=2019-05-01" \
  --query "value" -o tsv)

if [ -z "$WEBHOOK_URL" ]; then
  echo "Error: Could not retrieve Webhook URL."
  exit 1
fi

# Attach Webhook receiver to Action Group in ACTION_GROUP_RG
echo "Attaching Webhook receiver to Action Group ($ACTION_GROUP_NAME) in $ACTION_GROUP_RG..."
az monitor action-group create \
  --resource-group "$ACTION_GROUP_RG" \
  --name "$ACTION_GROUP_NAME" \
  --short-name "CostAlerts" \
  --webhook-receivers "[{\"name\":\"LogicAppReceiver\",\"serviceUri\":\"${WEBHOOK_URL}\"}]"

echo -e "\nDone! Webhook successfully linked to $ACTION_GROUP_NAME."
