#!/usr/bin/env bash

# Print list of existing Resource Groups
echo "Fetching existing Resource Groups..."
az group list --query "[].{Name:name, Location:location}" --output table
echo ""

# Prompt user for inputs
read -p "Enter Resource Group name: " RESOURCE_GROUP
read -p "Enter recipient email: " RECIPIENT_EMAIL

# Validate inputs
if [[ -z "$RESOURCE_GROUP" || -z "$RECIPIENT_EMAIL" ]]; then
  echo "Error: Both Resource Group and Email are required."
  exit 1
fi

# Fetch Resource Group location dynamically
LOCATION=$(az group show --name "$RESOURCE_GROUP" --query location --output tsv)
if [[ -z "$LOCATION" ]]; then
  echo "Error: Could not retrieve location for Resource Group '$RESOURCE_GROUP'."
  exit 1
fi

# Save selected Resource Group to .env without overwriting existing contents
ENV_FILE=".env"
touch "$ENV_FILE"

if grep -q "^LOGIC_APP_RG=" "$ENV_FILE"; then
  # Update existing LOGIC_APP_RG entry
  sed -i "s/^LOGIC_APP_RG=.*/LOGIC_APP_RG=$RESOURCE_GROUP/" "$ENV_FILE"
else
  # Append LOGIC_APP_RG if not present
  echo "LOGIC_APP_RG=$RESOURCE_GROUP" >> "$ENV_FILE"
fi

echo "[INFO] Saved LOGIC_APP_RG=$RESOURCE_GROUP to $ENV_FILE"

# Execute deployment
echo ""
echo "Deploying azuredeploy.json to '$RESOURCE_GROUP' in region '$LOCATION'..."
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file azuredeploy.json \
  --parameters recipientEmail="$RECIPIENT_EMAIL" location="$LOCATION"
