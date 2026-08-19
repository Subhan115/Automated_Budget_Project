#!/usr/bin/env bash

# budget.sh - Check for Azure CLI, ensure login, and list resource groups

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

# List resource groups for the currently selected subscription
echo
echo "Resource groups in the current subscription:"

# Load resource group names into an array
mapfile -t RG_NAMES < <(az group list --query "[].name" -o tsv)

if [ ${#RG_NAMES[@]} -eq 0 ]; then
  echo "No resource groups found in the current subscription."
  exit 0
fi

# Print numbered list
for i in "${!RG_NAMES[@]}"; do
  idx=$((i+1))
  printf "%3d) %s\n" "$idx" "${RG_NAMES[$i]}"
done

# Parse selection like: 1,3-5 or 'all'
parse_selection() {
  local input="$1"
  local -n out_arr=$2
  out_arr=()

  if [[ "$input" =~ ^[Aa][Ll][Ll]$ ]]; then
    for i in "${!RG_NAMES[@]}"; do
      out_arr+=( $((i+1)) )
    done
    return 0
  fi

  IFS=',' read -ra parts <<< "$input"
  declare -A seen=()
  for part in "${parts[@]}"; do
    part=$(echo "$part" | xargs) # trim whitespace
    if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start=${BASH_REMATCH[1]}
      end=${BASH_REMATCH[2]}
      if (( start> end )); then
        echo "Invalid range: $part"
        return 1
      fi
      for ((n=start;n<=end;n++)); do
        if (( n<1 || n> ${#RG_NAMES[@]} )); then
          echo "Selection out of range: $n"
          return 1
        fi
        seen[$n]=1
      done
    elif [[ "$part" =~ ^[0-9]+$ ]]; then
      n=$part
      if (( n<1 || n> ${#RG_NAMES[@]} )); then
        echo "Selection out of range: $n"
        return 1
      fi
      seen[$n]=1
    else
      echo "Invalid token in selection: $part"
      return 1
    fi
  done

  for k in "${!seen[@]}"; do out_arr+=("$k"); done
  # sort numeric
  IFS=$'\n' out_arr=( $(printf "%s\n" "${out_arr[@]}" | sort -n) )
  return 0
}

# Prompt user to select resource groups
while true; do
  read -p "Select resource groups by number (e.g. 1,3-5) or 'all': " selection_input
  if parse_selection "$selection_input" SELECTED; then
    break
  else
    echo "Please enter a valid selection."
  fi
done

# Prompt budgets for each selected group
declare -A BUDGETS
for sel in "${SELECTED[@]}"; do
  rg_name="${RG_NAMES[$((sel-1))]}"
  while true; do
    read -p "Enter budget in USD for '$rg_name' (numeric, without currency symbol): " amt
    # accept integers or decimals
    if [[ "$amt" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      BUDGETS["$rg_name"]="$amt"
      break
    else
      echo "Invalid amount. Enter a positive number like 100 or 123.45"
    fi
  done
done

# Print summary
echo
printf "%-40s %12s\n" "RESOURCE GROUP" "BUDGET (USD)"
printf "%-40s %12s\n" "--------------" "------------"
for rg in "${!BUDGETS[@]}"; do
  printf "%-40s %12s\n" "$rg" "${BUDGETS[$rg]}"
done

# Strict mode for safer pipeline behavior
set -euo pipefail

# Create Azure budgets for the selected resource groups

# Ensure we have subscription id
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
if [ -z "$SUBSCRIPTION_ID" ]; then
  echo "Unable to determine subscription id. Ensure you're logged in and have a subscription selected."
  exit 1
fi

# Prefer environment variables if provided; fall back to interactive prompts
BUDGET_NAME_PATTERN=${BUDGET_NAME_PATTERN:-${BUDGET_NAME_PATTERN_ENV:-}}
CATEGORY=${CATEGORY:-${CATEGORY_ENV:-}}
START_DATE=${START_DATE:-${START_DATE_ENV:-}}
END_DATE=${END_DATE:-${END_DATE_ENV:-}}

# Interactive prompts (only if values missing)
# Budget name pattern: may include '{rg}' which will be replaced by the resource group name. Example: budget-{rg}
if [[ -z "$BUDGET_NAME_PATTERN" ]]; then
  while true; do
    read -p "Enter budget name pattern (use {rg} to include resource group name) [budget-{rg}]: " BUDGET_NAME_PATTERN
    BUDGET_NAME_PATTERN=${BUDGET_NAME_PATTERN:-budget-{rg}}
    if [[ -n "$BUDGET_NAME_PATTERN" ]]; then break; fi
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

# Start date (required)
if [[ -z "$START_DATE" ]]; then
  while true; do
    read -p "Enter start date (YYYY-MM-DD): " START_DATE
    if valid_date "$START_DATE"; then break; fi
    echo "Invalid date format or value. Use YYYY-MM-DD."
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

# Normalize budget name pattern default
BUDGET_NAME_PATTERN=${BUDGET_NAME_PATTERN:-budget-{rg}}

# Ensure Consumption extension exists (required for budget commands)
if ! az consumption budget create --help >/dev/null 2>&1; then
  echo "Azure 'consumption' extension not found. Attempting to install..."
  if az extension add --name consumption >/dev/null 2>&1; then
    echo "Installed 'consumption' extension."
  else
    echo "Failed to install 'consumption' extension. Budgets cannot be created automatically."
    echo "You can install it with: az extension add --name consumption"
    echo "Or create budgets manually using 'az consumption budget create'."
    exit 1
  fi
fi

# Create budgets (Monthly) for each resource group
# Track budget names per resource group so they can be persisted to .env
declare -A BUDGET_NAMES_BY_RG=()
for rg in "${!BUDGETS[@]}"; do
  amt="${BUDGETS[$rg]}"
  # sanitize name: replace non-alphanum with '-'
  safe_rg_name=$(echo "$rg" | sed -E 's/[^A-Za-z0-9._-]+/-/g')
  # compute budget name from pattern
  budget_name=${BUDGET_NAME_PATTERN//\{rg\}/$safe_rg_name}
  # record the intended budget name (even if creation later fails)
  BUDGET_NAMES_BY_RG["$rg"]="$budget_name"

  # Ensure start date is the first day of the month (Azure requirement)
  start_first=$(date -d "$START_DATE" +%Y-%m-01)
  # Ensure end date is not before start_first
  s_ts=$(date -d "$start_first" +%s)
  e_ts=$(date -d "$END_DATE" +%s)
  if (( e_ts < s_ts )); then
    echo "End date $END_DATE is before the budget start (adjusted to first of month: $start_first). Skipping $rg."
    continue
  fi

  echo
  echo "Creating budget '$budget_name' for resource group '$rg' with amount ${amt} USD (Monthly), category=${CATEGORY}, start=${start_first}, end=${END_DATE}..."

  if az consumption budget create-with-rg \
      --budget-name "$budget_name" \
      --category "$CATEGORY" \
      --amount "$amt" \
      --time-grain "Monthly" \
      --time-period startDate=${start_first} endDate=${END_DATE} \
      --resource-group "$rg" >/dev/null 2>&1; then
    echo "Budget created: $budget_name"
  else
    echo "Failed to create budget for '$rg'. Showing example command to run manually:"
    echo "az consumption budget create-with-rg --budget-name \"$budget_name\" --category \"$CATEGORY\" --amount $amt --time-grain \"Monthly\" --time-period startDate=${start_first} endDate=${END_DATE} --resource-group \"$rg\""
  fi
done

echo
# Save selected resource groups to a .env file (comma-separated)
ENV_FILE=".env"
# Preserve the user's selection order when building the list
selected_rgs=()
for sel in "${SELECTED[@]}"; do
  selected_rgs+=("${RG_NAMES[$((sel-1))]}")
done
# Join with commas
IFS=','; joined="${selected_rgs[*]}"; unset IFS
# Build budget names list in the same order as selected_rgs
budget_names_ordered=()
for rg in "${selected_rgs[@]}"; do
  name="${BUDGET_NAMES_BY_RG[$rg]:-}"
  budget_names_ordered+=("$name")
done
IFS=','; joined_budgets="${budget_names_ordered[*]}"; unset IFS

# Write to .env (overwrite if exists)
printf "# Generated by budget.sh on %s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$ENV_FILE"
printf "RESOURCE_GROUPS=%s\n" "$joined" >> "$ENV_FILE"
printf "BUDGET_NAMES=%s\n" "$joined_budgets" >> "$ENV_FILE"

echo "Saved selected resource groups and budget names to $ENV_FILE"

echo "All done."

exit 0
