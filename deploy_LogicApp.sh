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

# Execute deployment
echo ""
echo "Deploying azuredeploy.json to '$RESOURCE_GROUP'..."

az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file azuredeploy.json \
  --parameters recipientEmail="$RECIPIENT_EMAIL"
