#!/bin/bash

#######################################
# FastAPI Service - AKS Deployment Script
# This script automates the deployment process
#######################################

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration (customize these)
RESOURCE_GROUP="${RESOURCE_GROUP:-fastapi-rg}"
LOCATION="${LOCATION:-eastus}"
ACR_NAME="${ACR_NAME:-fastapiserviceacr}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-fastapi-aks-cluster}"
IMAGE_NAME="fastapi-service"
IMAGE_TAG="${IMAGE_TAG:-latest}"
HELM_RELEASE_NAME="fastapi-release"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

print_step() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}▶ $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✔ $1${NC}"
}

print_error() {
    echo -e "${RED}✖ $1${NC}"
}

check_prerequisites() {
    print_step "Checking Prerequisites"
    
    local missing=0
    
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI (az) is not installed"
        missing=1
    else
        print_success "Azure CLI: $(az --version | head -1)"
    fi
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        missing=1
    else
        print_success "Docker: $(docker --version)"
    fi
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed"
        missing=1
    else
        print_success "kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
    fi
    
    if ! command -v helm &> /dev/null; then
        print_error "Helm is not installed"
        missing=1
    else
        print_success "Helm: $(helm version --short)"
    fi
    
    if [ $missing -eq 1 ]; then
        echo ""
        print_error "Please install missing prerequisites and try again."
        exit 1
    fi
}

azure_login() {
    print_step "Azure Login"
    
    if az account show &> /dev/null; then
        print_info "Already logged in as: $(az account show --query user.name -o tsv)"
        read -p "Do you want to continue with this account? (y/n): " choice
        if [ "$choice" != "y" ] && [ "$choice" != "Y" ]; then
            az login
        fi
    else
        az login
    fi
    
    print_success "Logged in to Azure"
    echo ""
    print_info "Current subscription: $(az account show --query name -o tsv)"
}

create_resource_group() {
    print_step "Creating Resource Group: $RESOURCE_GROUP"
    
    if az group show --name $RESOURCE_GROUP &> /dev/null; then
        print_info "Resource group '$RESOURCE_GROUP' already exists"
    else
        az group create --name $RESOURCE_GROUP --location $LOCATION
        print_success "Resource group created"
    fi
}

create_acr() {
    print_step "Creating Azure Container Registry: $ACR_NAME"
    
    if az acr show --name $ACR_NAME &> /dev/null; then
        print_info "ACR '$ACR_NAME' already exists"
    else
        az acr create \
            --resource-group $RESOURCE_GROUP \
            --name $ACR_NAME \
            --sku Basic \
            --admin-enabled true
        print_success "ACR created"
    fi
    
    export ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --query loginServer --output tsv)
    print_info "ACR Login Server: $ACR_LOGIN_SERVER"
}

build_and_push_image() {
    print_step "Building and Pushing Docker Image"
    
    cd "$PROJECT_DIR"
    
    print_info "Building Docker image..."
    docker build -t $IMAGE_NAME:$IMAGE_TAG .
    
    print_info "Tagging image for ACR..."
    docker tag $IMAGE_NAME:$IMAGE_TAG $ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG
    
    print_info "Logging into ACR..."
    az acr login --name $ACR_NAME
    
    print_info "Pushing image to ACR..."
    docker push $ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG
    
    print_success "Image pushed: $ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG"
}

create_aks() {
    print_step "Creating AKS Cluster: $AKS_CLUSTER_NAME"
    
    if az aks show --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME &> /dev/null; then
        print_info "AKS cluster '$AKS_CLUSTER_NAME' already exists"
    else
        print_info "This may take 5-10 minutes..."
        az aks create \
            --resource-group $RESOURCE_GROUP \
            --name $AKS_CLUSTER_NAME \
            --node-count 2 \
            --node-vm-size Standard_B2s \
            --enable-managed-identity \
            --generate-ssh-keys
        print_success "AKS cluster created"
    fi
    
    print_info "Getting AKS credentials..."
    az aks get-credentials \
        --resource-group $RESOURCE_GROUP \
        --name $AKS_CLUSTER_NAME \
        --overwrite-existing
    
    print_success "kubectl configured for AKS"
    
    print_info "Cluster nodes:"
    kubectl get nodes
}

attach_acr_to_aks() {
    print_step "Attaching ACR to AKS"
    
    az aks update \
        --resource-group $RESOURCE_GROUP \
        --name $AKS_CLUSTER_NAME \
        --attach-acr $ACR_NAME
    
    print_success "ACR attached to AKS"
}

deploy_with_helm() {
    print_step "Deploying with Helm"
    
    cd "$PROJECT_DIR"
    
    # Check if release exists
    if helm status $HELM_RELEASE_NAME &> /dev/null; then
        print_info "Upgrading existing Helm release..."
        helm upgrade $HELM_RELEASE_NAME ./helm/fastapi-service \
            --set image.repository=$ACR_LOGIN_SERVER/$IMAGE_NAME \
            --set image.tag=$IMAGE_TAG
    else
        print_info "Installing new Helm release..."
        helm install $HELM_RELEASE_NAME ./helm/fastapi-service \
            --set image.repository=$ACR_LOGIN_SERVER/$IMAGE_NAME \
            --set image.tag=$IMAGE_TAG
    fi
    
    print_success "Helm deployment completed"
}

wait_for_external_ip() {
    print_step "Waiting for External IP"
    
    print_info "Waiting for LoadBalancer to assign external IP (this may take 1-2 minutes)..."
    
    local attempts=0
    local max_attempts=30
    local external_ip=""
    
    while [ $attempts -lt $max_attempts ]; do
        external_ip=$(kubectl get svc ${HELM_RELEASE_NAME}-fastapi-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        
        if [ -n "$external_ip" ] && [ "$external_ip" != "null" ]; then
            break
        fi
        
        echo -n "."
        sleep 5
        attempts=$((attempts + 1))
    done
    
    echo ""
    
    if [ -z "$external_ip" ] || [ "$external_ip" == "null" ]; then
        print_error "Timed out waiting for external IP"
        print_info "Check service status with: kubectl get svc"
        exit 1
    fi
    
    print_success "External IP assigned: $external_ip"
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}                    🚀 DEPLOYMENT SUCCESSFUL! 🚀                         ${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${YELLOW}API Endpoint:${NC}  http://$external_ip/"
    echo -e "  ${YELLOW}Health Check:${NC}  http://$external_ip/health"
    echo -e "  ${YELLOW}Swagger Docs:${NC}  http://$external_ip/docs"
    echo -e "  ${YELLOW}ReDoc:${NC}         http://$external_ip/redoc"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Test the endpoint
    echo ""
    print_info "Testing API..."
    curl -s http://$external_ip/health | jq . 2>/dev/null || curl -s http://$external_ip/health
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --all           Run complete deployment (default)"
    echo "  --build-only    Only build and push Docker image"
    echo "  --deploy-only   Only deploy to existing AKS cluster"
    echo "  --help          Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP      Azure resource group name (default: fastapi-rg)"
    echo "  LOCATION            Azure region (default: eastus)"
    echo "  ACR_NAME            Azure Container Registry name (default: fastapiserviceacr)"
    echo "  AKS_CLUSTER_NAME    AKS cluster name (default: fastapi-aks-cluster)"
    echo "  IMAGE_TAG           Docker image tag (default: latest)"
}

main() {
    case "${1:-all}" in
        --all|all)
            check_prerequisites
            azure_login
            create_resource_group
            create_acr
            build_and_push_image
            create_aks
            attach_acr_to_aks
            deploy_with_helm
            wait_for_external_ip
            ;;
        --build-only)
            check_prerequisites
            azure_login
            create_acr
            build_and_push_image
            ;;
        --deploy-only)
            check_prerequisites
            export ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --query loginServer --output tsv)
            deploy_with_helm
            wait_for_external_ip
            ;;
        --help|-h)
            show_usage
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"

