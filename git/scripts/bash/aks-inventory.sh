#!/bin/bash
# =============================================================
# aks-inventory.sh
# Azure FinOps Toolkit — AKS Cluster & Node Pool Inventory
# =============================================================
# PURPOSE:
#   Lists every AKS cluster across all accessible subscriptions
#   and shows the VM SKU of each node pool. First step in any
#   K8s right-sizing analysis.
#
# USAGE:
#   chmod +x aks-inventory.sh
#   ./aks-inventory.sh
#
# OUTPUT:
#   Table of clusters and node pools printed to terminal.
#   Redirect to file: ./aks-inventory.sh > aks-report.txt
# =============================================================

set -euo pipefail

echo ""
echo "========================================"
echo " AKS Cluster & Node Pool Cost Inventory"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"
echo ""

# Check az CLI is installed
if ! command -v az &> /dev/null; then
  echo "ERROR: Azure CLI (az) is not installed."
  echo "Install it from: https://docs.microsoft.com/cli/azure/install-azure-cli"
  exit 1
fi

# Check we're logged in
if ! az account show &> /dev/null; then
  echo "ERROR: Not logged in to Azure CLI."
  echo "Run: az login"
  exit 1
fi

CLUSTER_COUNT=0
NODEPOOL_COUNT=0

# Loop through every subscription
for SUB_ID in $(az account list --query "[].id" -o tsv 2>/dev/null); do

  az account set --subscription "$SUB_ID" 2>/dev/null
  SUB_NAME=$(az account show --query "name" -o tsv 2>/dev/null)

  echo "Subscription: $SUB_NAME ($SUB_ID)"
  echo "--------------------------------------------"

  # Get all AKS clusters in this subscription
  CLUSTERS=$(az aks list \
    --query "[].{name:name,rg:resourceGroup,location:location,k8sVersion:kubernetesVersion}" \
    -o tsv 2>/dev/null)

  if [[ -z "$CLUSTERS" ]]; then
    echo "  (no AKS clusters found)"
    echo ""
    continue
  fi

  while IFS=$'\t' read -r NAME RG LOCATION K8S_VER; do
    CLUSTER_COUNT=$((CLUSTER_COUNT + 1))
    echo ""
    echo "  Cluster:    $NAME"
    echo "  Location:   $LOCATION"
    echo "  K8s ver:    $K8S_VER"
    echo "  Resource Group: $RG"
    echo ""
    echo "  Node Pools:"

    # Get node pools for this cluster
    az aks nodepool list \
      --resource-group "$RG" \
      --cluster-name "$NAME" \
      --query "[].{Pool:name,SKU:vmSize,Count:count,Mode:mode,OsType:osType,SpotEnabled:scaleSetEvictionPolicy}" \
      -o table 2>/dev/null | sed 's/^/    /'

    NODEPOOL_COUNT=$((NODEPOOL_COUNT + $(az aks nodepool list \
      --resource-group "$RG" \
      --cluster-name "$NAME" \
      --query "length(@)" -o tsv 2>/dev/null)))

    echo ""
  done <<< "$CLUSTERS"

done

echo "========================================"
echo " Summary"
echo "========================================"
echo " Total clusters found:   $CLUSTER_COUNT"
echo " Total node pools found: $NODEPOOL_COUNT"
echo ""
echo " FINOPS NOTE: Review any node pool SKU larger than Standard_D4s_v3"
echo " for right-sizing opportunities. Check Azure Monitor for CPU/memory"
echo " utilisation before making changes."
echo "========================================"
