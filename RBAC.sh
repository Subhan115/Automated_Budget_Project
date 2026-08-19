#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=".env"
LOGIC_APP_NAME="BudgetSystem"
ROLE_NAME="Cost Management Reader"

# Step 0: Read RESOURCE_GROUPS from .env file
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: $ENV_FILE file not found!" >&2
    exit 1
fi

RESOURCE_GROUP=$(grep -E '^RESOURCE_GROUPS=' "$ENV_FILE" | cut -d '=' -f2 | tr -d '\r"')

if [ -z "$RESOURCE_GROUP" ]; then
    echo "Error: RESOURCE_GROUPS is not set in $ENV_FILE" >&2
    exit 1
fi

echo "Resource Group: $RESOURCE_GROUP"

# Step 1: Enable System-Assigned Identity on the Logic App
echo "Enabling System-Assigned Identity for Logic App '$LOGIC_APP_NAME'..."

PRINCIPAL_ID=$(az resource update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$LOGIC_APP_NAME" \
    --resource-type "Microsoft.Logic/workflows" \
    --set identity.type="SystemAssigned" \
    --query identity.principalId \
    --output tsv)

if [ -z "$PRINCIPAL_ID" ] || [ "$PRINCIPAL_ID" == "null" ]; then
    echo "Error: Failed to enable identity or retrieve Principal ID." >&2
    exit 1
fi

echo "Identity Enabled! Principal ID: $PRINCIPAL_ID"

# Step 2: Get Subscription Scope
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
SCOPE="/subscriptions/$SUBSCRIPTION_ID"

# Step 3: Wait for Entra ID propagation & assign RBAC Role
echo "Waiting 10 seconds for Entra ID to propagate..."
sleep 10

echo "Assigning '$ROLE_NAME' role at scope: $SCOPE"

az role assignment create \
    --assignee-object-id "$PRINCIPAL_ID" \
    --assignee-principal-type "ServicePrincipal" \
    --role "$ROLE_NAME" \
    --scope "$SCOPE"

echo "Success! Role successfully granted to '$LOGIC_APP_NAME'."
