#!/bin/bash
set -e
az extension add --name logic

# 1. Load and parse variables from .env file
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
else
  echo "Error: .env file not found."
  exit 1
fi

# Clean up variables
RESOURCE_GROUP=$(echo "$RESOURCE_GROUPS" | tr -d '}\r ')
ACTION_GROUP_ID=$(echo "$ACTION_GROUP_IDS" | tr -d '}\r ')

# Extract Action Group Name
ACTION_GROUP_NAME=$(basename "$ACTION_GROUP_ID")
LOGIC_APP_NAME="BudgetSystem"

echo "Target Resource Group : $RESOURCE_GROUP"
echo "Target Action Group   : $ACTION_GROUP_NAME"
echo "Target Logic App      : $LOGIC_APP_NAME"

# Get Subscription ID
SUB_ID=$(az account show --query id -o tsv)

# 2. Retrieve the Webhook URL dynamically
echo "Fetching Webhook URL from $LOGIC_APP_NAME..."

TRIGGER_NAME=$(az rest \
  --method get \
  --uri "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Logic/workflows/${LOGIC_APP_NAME}/triggers?api-version=2019-05-01" \
  --query "value[0].name" -o tsv)

WEBHOOK_URL=$(az rest \
  --method post \
  --uri "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Logic/workflows/${LOGIC_APP_NAME}/triggers/${TRIGGER_NAME}/listCallbackUrl?api-version=2019-05-01" \
  --query "value" -o tsv)

if [ -z "$WEBHOOK_URL" ]; then
  echo "Error: Could not retrieve Webhook URL."
  exit 1
fi

# 3. Add the Webhook receiver using formatted JSON array
echo "Attaching Webhook receiver to Action Group ($ACTION_GROUP_NAME)..."

az monitor action-group create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ACTION_GROUP_NAME" \
  --short-name "CostAlerts" \
  --webhook-receivers "[{\"name\":\"LogicAppReceiver\",\"serviceUri\":\"${WEBHOOK_URL}\"}]"

echo -e "\nDone! Webhook successfully linked to $ACTION_GROUP_NAME."
