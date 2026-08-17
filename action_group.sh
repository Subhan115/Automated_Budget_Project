#!/usr/bin/env bash

# action_group.sh - create an Azure Monitor action group and print its resource id

set -euo pipefail

# Check Azure CLI
if ! command -v az >/dev/null 2>&1; then
  echo "Error: Azure CLI ('az') is not installed or not in PATH."
  echo "Install it from https://aka.ms/InstallAzureCli and try again."
  exit 1
fi

ENV_FILE=".env"
if [ ! -f "$ENV_FILE" ]; then
  echo "Error: $ENV_FILE not found. Please run budget.sh to generate it with RESOURCE_GROUPS."
  exit 1
fi

# Read RESOURCE_GROUPS from .env (expects comma-separated list)
if ! grep -q '^RESOURCE_GROUPS=' "$ENV_FILE"; then
  echo "Error: RESOURCE_GROUPS not set in $ENV_FILE"
  exit 1
fi
rg_line=$(grep '^RESOURCE_GROUPS=' "$ENV_FILE" | tail -n1)
rgs=${rg_line#RESOURCE_GROUPS=}
# strip surrounding quotes if any
rgs=${rgs#\"}
rgs=${rgs%\"}

# pick the first non-empty resource group from the comma-separated list
IFS=',' read -ra RG_ARRAY <<< "$rgs"
RG_SELECTED=""
for item in "${RG_ARRAY[@]}"; do
  item_trim=$(echo "$item" | xargs)
  if [ -n "$item_trim" ]; then
    RG_SELECTED="$item_trim"
    break
  fi
done

if [ -z "$RG_SELECTED" ]; then
  echo "Error: No resource group found in RESOURCE_GROUPS in $ENV_FILE"
  exit 1
fi

# Prompt for action group name
read -p "Enter action group name to create: " AG_NAME
AG_NAME=$(echo "$AG_NAME" | xargs)
if [ -z "$AG_NAME" ]; then
  echo "Error: action group name is required."
  exit 1
fi

# Prompt for email receivers (comma-separated). User chose multiple allowed.
read -p "Enter email addresses to add as email receivers (comma-separated), or leave blank to skip: " EMAIL_INPUT
EMAIL_INPUT=$(echo "$EMAIL_INPUT" | xargs)
EMAILS=()
if [ -n "$EMAIL_INPUT" ]; then
  IFS=',' read -ra raw_emails <<< "$EMAIL_INPUT"
  for e in "${raw_emails[@]}"; do
    e_trim=$(echo "$e" | xargs)
    if [ -n "$e_trim" ]; then
      EMAILS+=("$e_trim")
    fi
  done
fi

echo "Creating action group '$AG_NAME' in resource group '$RG_SELECTED'..."

# Build action args for az (multiple --action email NAME EMAIL_ADDRESS)
action_args=()
if [ ${#EMAILS[@]} -gt 0 ]; then
  idx=1
  for em in "${EMAILS[@]}"; do
    # create a simple receiver name (email-1, email-2, ...)
    recv_name="email-${idx}"
    action_args+=(--action email "$recv_name" "$em")
    idx=$((idx+1))
  done
fi

# Create the action group and return its full resource id
# Using --query id -o tsv to fetch the resource id only
if AG_ID=$(az monitor action-group create --name "$AG_NAME" --resource-group "$RG_SELECTED" "${action_args[@]}" --query id -o tsv 2>/dev/null); then
  echo "Action group created successfully."
  echo "Resource ID: $AG_ID"
  if [ ${#EMAILS[@]} -gt 0 ]; then
    echo "Added email receivers: ${EMAILS[*]}"
  fi
  exit 0
else
  echo "Failed to create action group. Attempting to run command without suppressing output to show error:"
  az monitor action-group create --name "$AG_NAME" --resource-group "$RG_SELECTED" "${action_args[@]}"
  exit 1
fi
