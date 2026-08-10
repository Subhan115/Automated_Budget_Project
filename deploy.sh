#!/bin/bash

# ==============================================================================
# Script Name: deploy.sh
# Description: Deploys Azure Consumption Budget & Action Group guardrails.
# Author: Cloud Engineering / DevOps Automation
# ==============================================================================

set -e

# --- Colors and Helpers ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- 1. Pre-flight Check ---
log_info "Checking Azure CLI authentication..."
if ! az account show > /dev/null 2>&1; then
    log_error "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

SUBSCRIPTION_NAME=$(az account show --query "name" -o tsv)
SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
log_success "Authenticated to: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"

# --- 2. Resource Group Discovery ---
log_info "Fetching resource groups..."
mapfile -t RGS < <(az group list --query "[].name" -o tsv)

if [ ${#RGS[@]} -eq 0 ]; then
    log_error "No resource groups found in this subscription."
    exit 1
fi

echo "Available Resource Groups:"
for i in "${!RGS[@]}"; do
    printf "  %d) %s\n" "$((i+1))" "${RGS[$i]}"
done

# --- 3. Interactive Inputs ---
# Compute sensible defaults for start/end and budget name
START_DATE_DEFAULT=$(date +%Y-%m-01)
END_DATE_DEFAULT=$(date -d "$START_DATE_DEFAULT +1 month -1 day" +%Y-%m-%d)
BUDGET_NAME_DEFAULT="Budget-$(date +%Y%m)"

read -rp "Enter numbers or names of RGs to target (comma-separated, e.g., 1,3 or rg-dev,rg-prod): " RG_INPUT
read -rp "Enter Monthly Budget Amount (USD): " BUDGET_AMOUNT
read -rp "Enter Budget Name (default: $BUDGET_NAME_DEFAULT): " BUDGET_NAME_INPUT
if [ -z "$BUDGET_NAME_INPUT" ]; then
    BUDGET_NAME="$BUDGET_NAME_DEFAULT"
else
    BUDGET_NAME="$BUDGET_NAME_INPUT"
fi

# Prompt for end date with default and robust validation
while true; do
    read -rp "Enter Budget End Date (YYYY-MM-DD) [default: $END_DATE_DEFAULT]: " END_DATE_INPUT
    if [ -z "$END_DATE_INPUT" ]; then
        END_DATE="$END_DATE_DEFAULT"
        break
    fi

    # Basic YYYY-MM-DD shape check
    if ! [[ "$END_DATE_INPUT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "Invalid date format. Please use YYYY-MM-DD."
        continue
    fi

    # Use date -d to canonicalize; reject out-of-range values where canonical form differs
    PARSED_DATE=$(date -d "$END_DATE_INPUT" +%Y-%m-%d 2>/dev/null || true)
    if [ -z "$PARSED_DATE" ] || [ "$PARSED_DATE" != "$END_DATE_INPUT" ]; then
        echo "Invalid calendar date. Please enter a real date in YYYY-MM-DD."
        continue
    fi

    END_DATE="$END_DATE_INPUT"
    break
done

read -rp "Enter Threshold Percentages (comma-separated, e.g., 50,75,90,100): " THRESHOLDS
read -rp "Enter Alert Email Addresses (comma-separated): " EMAIL_INPUT

# --- 4. Parse Inputs ---
# Convert comma-separated strings to space-separated arrays
IFS=',' read -ra ADDR_EMAILS <<< "$EMAIL_INPUT"
IFS=',' read -ra THRESHOLD_LIST <<< "$THRESHOLDS"

# Convert RG selection input to array
IFS=',' read -ra SELECTED_RG_INPUT <<< "$RG_INPUT"
TARGET_RGS=()
for item in "${SELECTED_RG_INPUT[@]}"; do
    # Trim whitespace
    item=$(echo "$item" | xargs)
    if [[ "$item" =~ ^[0-9]+$ ]]; then
        TARGET_RGS+=("${RGS[$((item-1))]}")
    else
        TARGET_RGS+=("$item")
    fi
done

# --- 5. Execution ---
START_DATE="$START_DATE_DEFAULT"
ACTION_GROUP_NAME="AG-CostAlerts-$(date +%Y%m%d)"

log_info "Starting deployment..."

for RG in "${TARGET_RGS[@]}"; do
    log_info "Processing RG: $RG"

    # Create action group (or update if exists)
    # Build list of receivers for az command (use --action email NAME EMAIL per Azure CLI)
    RECEIVER_ARGS=()
    for email in "${ADDR_EMAILS[@]}"; do
        name=$(echo "$email" | cut -d'@' -f1)
        RECEIVER_ARGS+=(--action email "$name" "$email")
    done

    az monitor action-group create \
        --name "$ACTION_GROUP_NAME" \
        --resource-group "$RG" \
        --short-name "CostAlert" \
        "${RECEIVER_ARGS[@]}" > /dev/null

    ACTION_GROUP_ID=$(az monitor action-group show --name "$ACTION_GROUP_NAME" --resource-group "$RG" --query id -o tsv)

    # b. Create Consumption Budget
    log_info "  Creating Consumption Budget ($BUDGET_AMOUNT USD)..."
    
    # Use BUDGET_NAME provided earlier (or default if user accepted it)
    # Construct threshold args
    THRESHOLD_ARGS=()
    for t in "${THRESHOLD_LIST[@]}"; do
        THRESHOLD_ARGS+=(--thresholds "$t")
    done
    
    # We need to link thresholds to Action Group ID
    # Note: az consumption budget creates the budget, but linking alerts to AG requires
    # notification settings per threshold.
    # Simplified approach: create budget, then add notification.

    az consumption budget create \
        --name "$BUDGET_NAME" \
        --resource-group "$RG" \
        --amount "$BUDGET_AMOUNT" \
        --category Cost \
        --time-grain Monthly \
        --start-date "$START_DATE" \
        --end-date "$END_DATE" \
        --threshold-type Actual \
        "${THRESHOLD_ARGS[@]}" > /dev/null

    # Add notification for each threshold
    for t in "${THRESHOLD_LIST[@]}"; do
        az consumption budget notification create \
            --budget-name "$BUDGET_NAME" \
            --notification-name "Alert-$t" \
            --resource-group "$RG" \
            --threshold "$t" \
            --threshold-type Actual \
            --contact-groups "$ACTION_GROUP_ID" > /dev/null
    done

    log_success "  Finished RG: $RG"
done

log_success "Deployment Complete!"
echo "-----------------------------------"
echo "Summary:"
echo "  Target RGs: ${TARGET_RGS[*]}"
echo "  Budget: $BUDGET_AMOUNT USD/month"
echo "  Alerts: ${THRESHOLD_LIST[*]}%"
echo "  Emails: ${ADDR_EMAILS[*]}"
echo "-----------------------------------"
