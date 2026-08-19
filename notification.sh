#!/bin/bash

set -e

# Load variables from .env file
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
else
  echo "Error: .env file not found!"
  exit 1
fi

# Map variables directly from .env
RESOURCE_GROUP="${RESOURCE_GROUPS}"
BUDGET_NAME="${BUDGET_NAMES}"
ACTION_GROUP_ID="${ACTION_GROUP_IDS}"

# Verify required variables are loaded
if [ -z "$RESOURCE_GROUP" ] || [ -z "$BUDGET_NAME" ] || [ -z "$ACTION_GROUP_ID" ]; then
  echo "Error: One or more required environment variables are empty."
  exit 1
fi

# Retrieve current Subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Prompt user for alert threshold
read -p "Enter threshold percentage (e.g., 80): " THRESHOLD

API_URL="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Consumption/budgets/${BUDGET_NAME}?api-version=2021-10-01"

echo "1. Fetching existing budget from Azure..."
BUDGET_JSON=$(az rest --method get --url "$API_URL")

echo "2. Injecting Action Group into notifications payload..."
UPDATED_BODY=$(python3 -c '
import sys, json

budget = json.loads(sys.stdin.read())
action_group_id = sys.argv[1]
threshold = float(sys.argv[2])

if "properties" not in budget:
    budget["properties"] = {}

if "notifications" not in budget["properties"] or budget["properties"]["notifications"] is None:
    budget["properties"]["notifications"] = {}

budget["properties"]["notifications"]["Default_Action_Group_Alert"] = {
    "enabled": True,
    "operator": "GreaterThanOrEqualTo",
    "threshold": threshold,
    "thresholdType": "Actual",
    "contactGroups": [action_group_id]
}

print(json.dumps(budget))
' "$ACTION_GROUP_ID" "$THRESHOLD" <<< "$BUDGET_JSON")

echo "3. Updating budget via REST PUT..."
az rest \
  --method put \
  --url "$API_URL" \
  --headers "Content-Type=application/json" \
  --body "$UPDATED_BODY"

echo "Budget successfully updated via REST API!"
