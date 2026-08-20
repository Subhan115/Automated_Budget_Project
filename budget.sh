#!/usr/bin/env bash
# budget.sh - Check for Azure CLI, ensure login, and create subscription-level budget via REST API
# Exit codes:
# 0 - success
# 1 - az not installed or login failed

# Check if 'az' is installed
if ! command -v az >/dev/null 2>&1; then
  echo "Error: Azure CLI ('az') is not installed or not in PATH."
  echo "Install it from https://aka.ms/InstallAzureCli and try again."
  exit 1
fi

# Check if user is logged in by querying the current account
if az account show >/dev/null 2>&1; then
  echo "Already logged in to Azure."
else
  echo "Not logged in to Azure. Attempting interactive login..."
  if az login; then
    echo "Login successful (interactive)."
  else
    echo "Interactive login failed or not available. Trying device-code login..."
    if az login --use-device-code; then
      echo "Login successful (device code)."
    else
      echo "Error: Unable to sign in. Please run 'az login' manually and try again."
      exit 1
    fi
  fi
fi

# Ensure we have active subscription info
echo
echo "Fetching active subscription details..."
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
SUBSCRIPTION_NAME="$(az account show --query name -o tsv)"

if [ -z "$SUBSCRIPTION_ID" ]; then
  echo "Unable to determine subscription id. Ensure you're logged in and have a subscription selected."
  exit 1
fi

echo "Active Subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
echo

# Prompt for subscription budget amount
while true; do
  read -p "Enter budget in USD for subscription '$SUBSCRIPTION_NAME' (numeric, without currency symbol): " amt
  # accept integers or decimals
  if [[ "$amt" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    break
  else
    echo "Invalid amount. Enter a positive number like 100 or 123.45"
  fi
done

# Print summary
echo
printf "%-40s %12s\n" "SUBSCRIPTION NAME" "BUDGET (USD)"
printf "%-40s %12s\n" "-----------------" "------------"
printf "%-40s %12s\n" "$SUBSCRIPTION_NAME" "$amt"

# Strict mode for safer pipeline behavior
set -euo pipefail

# Prefer environment variables if provided; fall back to interactive prompts
BUDGET_NAME=${BUDGET_NAME:-${BUDGET_NAME_ENV:-}}
CATEGORY=${CATEGORY:-${CATEGORY_ENV:-}}
START_DATE=${START_DATE:-${START_DATE_ENV:-}}
END_DATE=${END_DATE:-${END_DATE_ENV:-}}

# Interactive prompts (only if values missing)
# Budget name
if [[ -z "$BUDGET_NAME" ]]; then
  while true; do
    read -p "Enter budget name [subscription-budget]: " BUDGET_NAME
    BUDGET_NAME=${BUDGET_NAME:-subscription-budget}
    if [[ -n "$BUDGET_NAME" ]]; then break; fi
  done
fi

# Category: Cost or Usage (default Cost)
if [[ -z "$CATEGORY" ]]; then
  while true; do
    read -p "Enter budget category ('Cost' or 'Usage') [Cost]: " CATEGORY
    CATEGORY=${CATEGORY:-Cost}
    if [[ "$CATEGORY" =~ ^(Cost|Usage)$ ]]; then break; fi
    echo "Invalid category. Enter 'Cost' or 'Usage'."
  done
fi

# Date validation helper
valid_date() {
  if [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    if date -d "$1" >/dev/null 2>&1; then
      return 0
    fi
  fi
  return 1
}

# Start date (required - must be the 1st of the month)
if [[ -z "$START_DATE" ]]; then
  while true; do
    echo "Note: Azure requires budget start dates to begin on the 1st of the month (e.g., YYYY-MM-01)."
    read -p "Enter start date (YYYY-MM-01): " START_DATE
    if valid_date "$START_DATE"; then
      if [[ "$START_DATE" =~ ^[0-9]{4}-[0-9]{2}-01$ ]]; then
        break
      else
        suggested_date=$(date -d "$START_DATE" +%Y-%m-01)
        echo "Error: Start date must be the 1st of the month! Did you mean $suggested_date?"
      fi
    else
      echo "Invalid date format or value. Use YYYY-MM-01."
    fi
  done
fi

# End date (required)
if [[ -z "$END_DATE" ]]; then
  while true; do
    read -p "Enter end date (YYYY-MM-DD): " END_DATE
    if ! valid_date "$END_DATE"; then
      echo "Invalid date format or value. Use YYYY-MM-DD."
      continue
    fi
    # ensure end >= start
    s_ts=$(date -d "$START_DATE" +%s)
    e_ts=$(date -d "$END_DATE" +%s)
    if (( e_ts < s_ts )); then
      echo "End date must be after or equal to start date."
      continue
    fi
    break
  done
fi

# Sanitize budget name: replace non-alphanum characters with '-'
safe_budget_name=$(echo "$BUDGET_NAME" | sed -E 's/[^A-Za-z0-9._-]+/-/g')

# Ensure start date is normalized to the first day of the month
start_first=$(date -d "$START_DATE" +%Y-%m-01)

# Ensure end date is not before start_first
s_ts=$(date -d "$start_first" +%s)
e_ts=$(date -d "$END_DATE" +%s)
if (( e_ts < s_ts )); then
  echo "Error: End date $END_DATE is before the budget start ($start_first)."
  exit 1
fi

echo
echo "Creating budget '$safe_budget_name' for subscription '$SUBSCRIPTION_NAME' ($SUBSCRIPTION_ID) with amount ${amt} USD (Monthly), category=${CATEGORY}, start=${start_first}, end=${END_DATE}..."

# Use Azure REST API directly to avoid CLI extension schema bugs
if az rest --method put \
    --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Consumption/budgets/${safe_budget_name}?api-version=2021-10-01" \
    --body "{
      \"properties\": {
        \"category\": \"${CATEGORY}\",
        \"amount\": ${amt},
        \"timeGrain\": \"Monthly\",
        \"timePeriod\": {
          \"startDate\": \"${start_first}T00:00:00Z\",
          \"endDate\": \"${END_DATE}T00:00:00Z\"
        }
      }
    }" >/dev/null 2>&1; then
  echo "Budget created: $safe_budget_name"
else
  echo "Failed to create budget for subscription '$SUBSCRIPTION_NAME'. Showing example REST command to run manually:"
  echo "az rest --method put --url \"https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Consumption/budgets/${safe_budget_name}?api-version=2021-10-01\" --body \"{\\\"properties\\\":{\\\"category\\\":\\\"${CATEGORY}\\\",\\\"amount\\\":${amt},\\\"timeGrain\\\":\\\"Monthly\\\",\\\"timePeriod\\\":{\\\"startDate\\\":\\\"${start_first}T00:00:00Z\\\",\\\"endDate\\\":\\\"${END_DATE}T00:00:00Z\\\"}}}\""
fi

echo
# Save subscription budget metadata to .env file
ENV_FILE=".env"
printf "# Generated by budget.sh on %s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$ENV_FILE"
printf "SUBSCRIPTION_ID=%s\n" "$SUBSCRIPTION_ID" >> "$ENV_FILE"
printf "BUDGET_NAME=%s\n" "$safe_budget_name" >> "$ENV_FILE"
printf "BUDGET_AMOUNT=%s\n" "$amt" >> "$ENV_FILE"

echo "Saved subscription budget metadata to $ENV_FILE"
echo "All done."
exit 0
