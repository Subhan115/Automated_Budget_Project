#!/usr/bin/env bash
# RBAC.sh - Enable Managed Identity on Logic App and grant Cost Management Reader role
set -euo pipefail

ENV_FILE=".env"
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: $ENV_FILE file not found!" >&2
    exit 1
fi

# Load variables from .env
export $(grep -v '^#' "$ENV_FILE" | xargs)

# Step 0: Read Logic App Resource Group from .env
LOGIC_APP_RG="${LOGIC_APP_RG:-${LOGIC_APP_RESOURCE_GROUP:-Guardrail-RG}}"
if [ -z "$LOGIC_APP_RG" ]; then
    echo "Error: LOGIC_APP_RG is not set in $ENV_FILE" >&2
    exit 1
fi

SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
ROLE_NAME="Cost Management Reader"

echo "Logic App Resource Group : $LOGIC_APP_RG"

# Auto-detect Logic App workflow name if not set
LOGIC_APP_NAME=$(az rest --method get \
  --uri "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${LOGIC_APP_RG}/providers/Microsoft.Logic/workflows?api-version=2019-05-01" \
  --query "value[0].name" -o tsv 2>/dev/null || true)

LOGIC_APP_NAME="${LOGIC_APP_NAME:-BudgetSystem}"
echo "Target Logic App         : $LOGIC_APP_NAME"

# Step 1: Enable System-Assigned Identity on the Logic App
echo "Enabling System-Assigned Identity for Logic App '$LOGIC_APP_NAME'..."
PRINCIPAL_ID=$(az resource update \
    --resource-group "$LOGIC_APP_RG" \
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

# Step 2: Define Subscription Scope
SCOPE="/subscriptions/$SUBSCRIPTION_ID"

# Step 3: Assign RBAC Role with retry logic for Entra ID propagation
echo "Assigning '$ROLE_NAME' role at scope: $SCOPE"
echo "Waiting for Entra ID propagation..."

max_retries=6
counter=0
until az role assignment create \
    --assignee-object-id "$PRINCIPAL_ID" \
    --assignee-principal-type "ServicePrincipal" \
    --role "$ROLE_NAME" \
    --scope "$SCOPE" 2>/dev/null; do
    
    counter=$((counter+1))
    if [ $counter -ge $max_retries ]; then
        echo "Error: Failed to assign role after $max_retries attempts. Please try running the assignment manually." >&2
        exit 1
    fi
    echo "Principal not fully propagated yet... retrying in 20s ($counter/$max_retries)"
    sleep 20
done

echo "Success! Role '$ROLE_NAME' successfully granted to '$LOGIC_APP_NAME'."
