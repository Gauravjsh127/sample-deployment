#!/bin/bash
#
# Deploy Script - Auto-versioning Docker Build & Push to ACR
# Usage: ./scripts/deploy.sh [--major | --minor | --patch]
#
# Options:
#   --major  Increment major version (e.g., v1.0.5 → v2.0.0)
#   --minor  Increment minor version (e.g., v1.0.5 → v1.1.0)
#   --patch  Increment patch version (default, e.g., v1.0.5 → v1.0.6)
#
# Examples:
#   ./scripts/deploy.sh           # Increments patch: v1.0.0 → v1.0.1
#   ./scripts/deploy.sh --minor   # Increments minor: v1.0.5 → v1.1.0
#   ./scripts/deploy.sh --major   # Increments major: v1.5.3 → v2.0.0
#

set -e

# Configuration
ACR_NAME="acrsandboxwus2"
ACR_SERVER="${ACR_NAME}.azurecr.io"
IMAGE_NAME="test_app"
FULL_IMAGE="${ACR_SERVER}/${IMAGE_NAME}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
INCREMENT_TYPE="patch"
if [[ "$1" == "--major" ]]; then
    INCREMENT_TYPE="major"
elif [[ "$1" == "--minor" ]]; then
    INCREMENT_TYPE="minor"
elif [[ "$1" == "--patch" ]]; then
    INCREMENT_TYPE="patch"
elif [[ -n "$1" ]]; then
    echo -e "${RED}Unknown option: $1${NC}"
    echo "Usage: ./scripts/deploy.sh [--major | --minor | --patch]"
    exit 1
fi

echo -e "${BLUE}🚀 Starting deployment process...${NC}"
echo ""

# Step 1: Check if we're in the right directory
if [[ ! -f "Dockerfile" ]]; then
    echo -e "${RED}❌ Error: Dockerfile not found. Please run from project root directory.${NC}"
    exit 1
fi

# Step 2: Login to ACR
echo -e "${YELLOW}📦 Logging into Azure Container Registry...${NC}"
az acr login --name $ACR_NAME

# Step 3: Get the latest version from ACR
echo -e "${YELLOW}🔍 Checking latest version in ACR...${NC}"
LATEST_VERSION=$(az acr repository show-tags --name $ACR_NAME --repository $IMAGE_NAME --orderby time_desc --output tsv 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || echo "")

if [[ -z "$LATEST_VERSION" ]]; then
    echo -e "   No existing versions found. Starting at v1.0.0"
    MAJOR=1
    MINOR=0
    PATCH=0
else
    echo -e "   Latest version: ${GREEN}$LATEST_VERSION${NC}"
    # Parse the version
    MAJOR=$(echo $LATEST_VERSION | sed 's/v//' | cut -d. -f1)
    MINOR=$(echo $LATEST_VERSION | sed 's/v//' | cut -d. -f2)
    PATCH=$(echo $LATEST_VERSION | sed 's/v//' | cut -d. -f3)
    
    # Increment based on type
    case $INCREMENT_TYPE in
        major)
            MAJOR=$((MAJOR + 1))
            MINOR=0
            PATCH=0
            ;;
        minor)
            MINOR=$((MINOR + 1))
            PATCH=0
            ;;
        patch)
            PATCH=$((PATCH + 1))
            ;;
    esac
fi

NEW_VERSION="v${MAJOR}.${MINOR}.${PATCH}"
echo -e "   New version: ${GREEN}$NEW_VERSION${NC} (${INCREMENT_TYPE} increment)"
echo ""

# Step 4: Build the Docker image
echo -e "${YELLOW}🔨 Building Docker image...${NC}"
echo -e "   Image: ${FULL_IMAGE}:${NEW_VERSION}"
echo -e "   Platform: linux/amd64 (for AKS compatibility)"
echo ""

docker build --platform linux/amd64 -t "${FULL_IMAGE}:${NEW_VERSION}" .

echo ""
echo -e "${GREEN}✅ Build complete!${NC}"
echo ""

# Step 5: Push to ACR
echo -e "${YELLOW}📤 Pushing to Azure Container Registry...${NC}"
docker push "${FULL_IMAGE}:${NEW_VERSION}"

echo ""
echo -e "${GREEN}✅ Push complete!${NC}"
echo ""

# Step 6: Verify and show results
echo -e "${YELLOW}📋 Verifying push...${NC}"
echo -e "   Recent versions in ACR:"
az acr repository show-tags --name $ACR_NAME --repository $IMAGE_NAME --orderby time_desc --output table | head -6

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ DEPLOYMENT COMPLETE${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "   📦 Image: ${BLUE}${FULL_IMAGE}:${NEW_VERSION}${NC}"
echo -e "   ⏳ ArgoCD Image Updater will detect and deploy within 2 minutes"
echo ""
echo -e "${YELLOW}Monitor deployment with:${NC}"
echo -e "   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater -f"
echo ""
echo -e "${YELLOW}Or via AKS command invoke:${NC}"
echo -e "   az aks command invoke --resource-group rg-sandbox-horizon --name aks-sandbox-wus2 --command \"kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater --tail=30\""
echo ""

