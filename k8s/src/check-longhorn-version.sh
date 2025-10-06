#!/usr/bin/env bash

# Longhorn Version Management Script
# This script helps you safely upgrade Longhorn by checking current version and suggesting next steps

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Longhorn Version Management${NC}"
echo "================================"

# Load environment variables
set -o allexport
source ../../.env
set +o allexport

# Define the safe upgrade path
declare -a UPGRADE_PATH=("1.5.4" "1.6.4" "1.7.3" "1.8.2" "1.9.2" "1.10.0")

echo -e "\n${YELLOW}Current Configuration:${NC}"
echo "Chart Version in .env: ${LONGHORN_CHART_VERSION}"

# Check current deployed version
if command -v kubectl &> /dev/null; then
    export KUBECONFIG=$(pwd)/kubeconfig.yml

    if kubectl get namespace longhorn-system &> /dev/null; then
        CURRENT_VERSION=$(kubectl get settings -n longhorn-system current-longhorn-version -o jsonpath='{.value}' 2>/dev/null || echo "Unknown")
        echo "Currently Deployed: ${CURRENT_VERSION}"

        # Check if cluster is accessible
        if [[ "$CURRENT_VERSION" != "Unknown" ]]; then
            echo -e "\n${GREEN}✓ Cluster is accessible${NC}"
        else
            echo -e "\n${YELLOW}⚠ Could not determine deployed version${NC}"
        fi
    else
        echo -e "\n${YELLOW}⚠ Longhorn not deployed or cluster not accessible${NC}"
    fi
else
    echo -e "\n${YELLOW}⚠ kubectl not available${NC}"
fi

echo -e "\n${YELLOW}Safe Upgrade Path:${NC}"
for i in "${!UPGRADE_PATH[@]}"; do
    version="${UPGRADE_PATH[$i]}"
    if [[ "$version" == "$LONGHORN_CHART_VERSION" ]]; then
        echo -e "  ${GREEN}→ $version (CURRENT)${NC}"
    else
        echo "  → $version"
    fi
done

# Suggest next version
current_index=-1
for i in "${!UPGRADE_PATH[@]}"; do
    if [[ "${UPGRADE_PATH[$i]}" == "$LONGHORN_CHART_VERSION" ]]; then
        current_index=$i
        break
    fi
done

if [[ $current_index -ge 0 ]] && [[ $current_index -lt $((${#UPGRADE_PATH[@]} - 1)) ]]; then
    next_version="${UPGRADE_PATH[$((current_index + 1))]}"
    echo -e "\n${GREEN}Next Safe Upgrade:${NC}"
    echo -e "  Update LONGHORN_CHART_VERSION in .env to: ${GREEN}$next_version${NC}"
    echo -e "  Then run: ${BLUE}./deploy-from-local.sh${NC}"
elif [[ $current_index -eq $((${#UPGRADE_PATH[@]} - 1)) ]]; then
    echo -e "\n${GREEN}✓ You're on the latest supported version!${NC}"
else
    echo -e "\n${RED}⚠ Current version not in safe upgrade path${NC}"
    echo "  Consider setting LONGHORN_CHART_VERSION to a version from the upgrade path"
fi

echo -e "\n${YELLOW}Tips:${NC}"
echo "• Always backup your data before upgrading"
echo "• Test upgrades in a non-production environment first"
echo "• Never skip versions - follow the upgrade path"
echo "• Monitor cluster health after each upgrade"