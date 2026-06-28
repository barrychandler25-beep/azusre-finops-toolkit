#!/bin/bash
# =============================================================
# advisor-cost-recs.sh
# Azure FinOps Toolkit — Azure Advisor Cost Recommendations
# =============================================================
# PURPOSE:
#   Pulls all Azure Advisor cost recommendations, formatted as
#   an actionable table. High-impact items highlighted separately.
#   Advisor uses real utilisation data — these are validated wins.
#
# USAGE:
#   chmod +x advisor-cost-recs.sh
#   ./advisor-cost-recs.sh
#   ./advisor-cost-recs.sh --high-only   (high impact only)
#
# OUTPUT:
#   Formatted tables printed to terminal.
# =============================================================

set -euo pipefail

HIGH_ONLY=false
if [[ "${1:-}" == "--high-only" ]]; then
  HIGH_ONLY=true
fi

echo ""
echo "========================================"
echo " Azure Advisor — Cost Recommendations"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"
echo ""

# Check prerequisites
if ! command -v az &> /dev/null; then
  echo "ERROR: Azure CLI not installed. Run: brew install azure-cli  OR  apt install azure-cli"
  exit 1
fi

if ! az account show &> /dev/null; then
  echo "ERROR: Not logged in. Run: az login"
  exit 1
fi

SUB_NAME=$(az account show --query "name" -o tsv)
SUB_ID=$(az account show --query "id" -o tsv)
echo "Subscription: $SUB_NAME"
echo "ID:           $SUB_ID"
echo ""

if [[ "$HIGH_ONLY" == false ]]; then
  echo "--- ALL COST RECOMMENDATIONS ---"
  echo ""

  az advisor recommendation list \
    --category Cost \
    --query "sort_by([].{
      Impact:impact,
      ResourceType:resourceMetadata.resourceType,
      Recommendation:shortDescription.solution,
      AnnualSavings:extendedProperties.annualSavingsAmount,
      Currency:extendedProperties.savingsCurrency
    }, &Impact)" \
    -o table 2>/dev/null || echo "No recommendations found or insufficient permissions."

  echo ""
fi

echo "--- HIGH IMPACT ITEMS (act on these first) ---"
echo ""

HIGH_RECS=$(az advisor recommendation list \
  --category Cost \
  --query "[?impact=='High'].{
    ResourceType:resourceMetadata.resourceType,
    ResourceID:resourceMetadata.resourceId,
    Fix:shortDescription.solution,
    AnnualSavings:extendedProperties.annualSavingsAmount
  }" \
  -o json 2>/dev/null)

if [[ "$HIGH_RECS" == "[]" ]] || [[ -z "$HIGH_RECS" ]]; then
  echo "  No high-impact recommendations found."
  echo "  This is good news — or Advisor needs more utilisation data (allow 7-14 days)."
else
  echo "$HIGH_RECS" | az cli-translator 2>/dev/null || \
  echo "$HIGH_RECS" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for i, r in enumerate(data, 1):
    print(f'  [{i}] {r.get(\"ResourceType\",\"Unknown\")}')
    print(f'      Saving: {r.get(\"AnnualSavings\",\"N/A\")}')
    print(f'      Action: {r.get(\"Fix\",\"N/A\")}')
    print()
" 2>/dev/null || echo "$HIGH_RECS"
fi

echo ""
echo "========================================"
echo " FINOPS NOTE: Run this weekly. High-impact items should"
echo " be triaged with engineering within 5 business days."
echo " Track remediation rate as a FinOps KPI."
echo "========================================"
