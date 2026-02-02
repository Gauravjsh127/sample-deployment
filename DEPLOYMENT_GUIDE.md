# Registry-Driven Deployment Guide
## Local Build → ACR → Argo CD Image Updater → AKS

This guide walks you through deploying applications using a **registry-driven** approach:
- Build Docker images **locally**
- Push to **Azure Container Registry (ACR)**
- **Argo CD Image Updater** automatically detects new images
- **Argo CD** deploys to **Azure Kubernetes Service (AKS)**

---

## 🎯 Pre-Configured Azure Resources

| Resource | Name | Details |
|----------|------|---------|
| **Resource Group** | `rg-sandbox-horizon` | Container for all resources |
| **Region** | `West US 2` | Azure region |
| **AKS Cluster** | `aks-sandbox-wus2` | Kubernetes cluster |
| **Container Registry** | `acrsandboxwus2` | Docker image registry |
| **ACR Login Server** | `acrsandboxwus2.azurecr.io` | URL for pushing images |
| **Image Name** | `test_app` | Repository name in ACR |

---

## ⚡ Quick Start: Push an Image (If Already Set Up)

If Argo CD and Image Updater are already configured, use this to deploy:

```bash
# 1. Login to ACR
az acr login --name acrsandboxwus2

# 2. Build image (from project directory)
docker build -t acrsandboxwus2.azurecr.io/test_app:v1.0.0 .

# 3. Push to ACR
docker push acrsandboxwus2.azurecr.io/test_app:v1.0.0

# 4. Done! Image Updater auto-deploys within 2 minutes
# Monitor with: kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater -f
```

> **First time setup?** Follow the complete guide below starting from [Step 1](#step-1-install-required-tools).

---

## 🔄 Deployment Flow

```
┌──────────────────────────────────────────────────────────────────────────────┐
│              REGISTRY-DRIVEN DEPLOYMENT FLOW                                  │
└──────────────────────────────────────────────────────────────────────────────┘

  YOU (Local Machine)                           AZURE
   │                                              │
   │  1. docker build                             │
   │     Build your image locally                 │
   │                                              │
   │  2. docker push ─────────────────────────────│──> ACR
   │     Push to Azure Container Registry         │    (acrsandboxwus2.azurecr.io)
   │                                              │
   │                                              │
   │                     ┌────────────────────────┤
   │                     │  3. Image Updater      │
   │                     │     polls ACR          │
   │                     │     (every 2 min)      │
   │                     │                        │
   │                     ▼                        │
   │              Detects new image tag           │
   │                     │                        │
   │                     ▼                        │
   │              4. Updates Argo CD App          │
   │                     │                        │
   │                     ▼                        │
   │              5. Argo CD syncs ───────────────│──> AKS
   │                     │                        │    (aks-sandbox-wus2)
   │                     ▼                        │
   │  6. App is Live! ◄──────────────────────────-│
   │                                              │
```

**In Simple Words:**
1. You build a Docker image on your local machine
2. You push it to Azure Container Registry
3. Argo CD Image Updater detects the new image
4. Argo CD automatically deploys to AKS
5. Your app is live!

---

## 📋 Table of Contents

1. [Quick Start: Push an Image](#-quick-start-push-an-image-if-already-set-up)
2. [Prerequisites](#prerequisites)
3. [Step 1: Install Required Tools](#step-1-install-required-tools)
4. [Step 2: Connect to Azure Resources](#step-2-connect-to-azure-resources)
5. [Step 3: Install Argo CD on AKS](#step-3-install-argo-cd-on-aks)
6. [Step 4: Install Argo CD Image Updater](#step-4-install-argo-cd-image-updater)
7. [Step 5: Configure Argo CD Application](#step-5-configure-argo-cd-application)
8. [Step 6: Build and Push Image to ACR](#step-6-build-and-push-image-to-acr)
9. [Complete Image Push Workflow](#-complete-image-push-workflow-copy--paste)
10. [Deploy a New Version](#-deploy-a-new-version)
11. [Quick Reference Commands](#-quick-reference-commands)
12. [Troubleshooting](#-troubleshooting)

---

## ✅ Prerequisites

| Requirement | Description |
|-------------|-------------|
| **Azure Account** | Access to the pre-configured resources |
| **Docker** | For building images locally |
| **Your Code** | This repository cloned locally |

---

## Step 1: Install Required Tools

### 1.1 Install Azure CLI

**On macOS:**
```bash
brew install azure-cli
```

**On Windows (PowerShell as Admin):**
```powershell
winget install Microsoft.AzureCLI
```

**On Linux (Ubuntu/Debian):**
```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

**Verify:**
```bash
az --version
```

### 1.2 Install kubectl

**On macOS:**
```bash
brew install kubectl
```

**On Windows:**
```powershell
winget install Kubernetes.kubectl
```

**On Linux:**
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

**Verify:**
```bash
kubectl version --client
```

### 1.3 Install Helm

**On macOS:**
```bash
brew install helm
```

**On Windows:**
```powershell
winget install Helm.Helm
```

**On Linux:**
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

**Verify:**
```bash
helm version
```

### 1.4 Install Docker

**Download from:** https://docs.docker.com/get-docker/

---

## Step 2: Connect to Azure Resources

### 2.1 Login to Azure

```bash
az login
```

### 2.2 Set Subscription (if needed)

```bash
# List subscriptions
az account list --output table

# Set subscription
az account set --subscription "YOUR_SUBSCRIPTION_NAME_OR_ID"
```

### 2.3 Verify Resources Exist

```bash
# Set variables
RESOURCE_GROUP="rg-sandbox-horizon"
ACR_NAME="acrsandboxwus2"
AKS_CLUSTER_NAME="aks-sandbox-wus2"

# Verify resource group
az group show --name $RESOURCE_GROUP --query name

# Verify ACR
az acr show --name $ACR_NAME --query loginServer --output tsv

# Verify AKS
az aks show --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --query name
```

### 2.4 Connect AKS to ACR

```bash
az aks update \
  --resource-group rg-sandbox-horizon \
  --name aks-sandbox-wus2 \
  --attach-acr acrsandboxwus2
```

### 2.5 Get AKS Credentials

```bash
az aks get-credentials \
  --resource-group rg-sandbox-horizon \
  --name aks-sandbox-wus2
```

**Verify connection:**
```bash
kubectl get nodes
```

Or use AKS command invoke:
```bash
az aks command invoke \
  --resource-group rg-sandbox-horizon \
  --name aks-sandbox-wus2 \
  --command "kubectl get nodes"
```

---

## Step 3: Install Argo CD on AKS

### 3.1 Create Namespace

```bash
kubectl create namespace argocd
```

### 3.2 Install Argo CD

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

**Wait for pods to be ready:**
```bash
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s
```

### 3.3 Expose Argo CD UI

**Option A: LoadBalancer (Recommended)**
```bash
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# Get external IP (wait for IP to appear)
kubectl get svc argocd-server -n argocd -w
```

**Option B: Port Forward (Local access)**
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open: https://localhost:8080
```

### 3.4 Get Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo
```

**Login:**
- **Username:** `admin`
- **Password:** (output from above)

### 3.5 Install Argo CD CLI (Optional)

**On macOS:**
```bash
brew install argocd
```

**On Linux:**
```bash
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
```

**Login with CLI:**
```bash
ARGOCD_SERVER=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
argocd login $ARGOCD_SERVER --insecure
```

---

## Step 4: Install Argo CD Image Updater

Image Updater watches ACR and automatically updates deployments when new images are pushed.

### 4.1 Install via Helm

**Option A: Direct kubectl access:**
```bash
# Add Argo Helm repository
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Install Image Updater
helm install argocd-image-updater argo/argocd-image-updater \
  --namespace argocd \
  --set 'config.registries[0].name=Azure' \
  --set 'config.registries[0].prefix=acrsandboxwus2.azurecr.io' \
  --set 'config.registries[0].api_url=https://acrsandboxwus2.azurecr.io' \
  --set 'config.registries[0].default=true'
```

**Option B: Via AKS command invoke (for private clusters):**
```bash
az aks command invoke \
  --resource-group rg-sandbox-horizon \
  --name aks-sandbox-wus2 \
  --command "helm repo add argo https://argoproj.github.io/argo-helm && helm repo update && helm install argocd-image-updater argo/argocd-image-updater --namespace argocd --set config.registries[0].name=Azure --set config.registries[0].prefix=acrsandboxwus2.azurecr.io --set config.registries[0].api_url=https://acrsandboxwus2.azurecr.io --set config.registries[0].default=true"
```

**Verify installation:**
```bash
# Direct kubectl
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-image-updater

# Or via AKS command invoke
az aks command invoke \
  --resource-group rg-sandbox-horizon \
  --name aks-sandbox-wus2 \
  --command "kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-image-updater"
```

### 4.2 Configure ACR Credentials

**Option A: Direct kubectl access:**
```bash
# Get ACR password and create secret
ACR_PASSWORD=$(az acr credential show --name acrsandboxwus2 --query "passwords[0].value" -o tsv)

kubectl -n argocd create secret docker-registry acr-creds \
  --docker-server=acrsandboxwus2.azurecr.io \
  --docker-username=acrsandboxwus2 \
  --docker-password="$ACR_PASSWORD"
```

**Option B: Via AKS command invoke (for private clusters):**

> **Important:** When using `az aks command invoke`, you must get the password and create the secret in a single command chain, as variables are not preserved between invocations.

```bash
# Get ACR password and create secret in one command
ACR_PASSWORD=$(az acr credential show --name acrsandboxwus2 --query "passwords[0].value" -o tsv) && \
az aks command invoke \
  --resource-group rg-sandbox-horizon \
  --name aks-sandbox-wus2 \
  --command "kubectl -n argocd create secret docker-registry acr-creds --docker-server=acrsandboxwus2.azurecr.io --docker-username=acrsandboxwus2 --docker-password='$ACR_PASSWORD'"
```

**Verify secret was created:**
```bash
# Direct kubectl
kubectl get secret acr-creds -n argocd

# Or via AKS command invoke
az aks command invoke \
  --resource-group rg-sandbox-horizon \
  --name aks-sandbox-wus2 \
  --command "kubectl get secret acr-creds -n argocd"
```

### 4.3 Configure Registry in Image Updater

The configmap needs to include the `credentials` field to reference the ACR secret.

**Option A: Direct kubectl access:**
```bash
# View current configmap
kubectl get configmap argocd-image-updater-config -n argocd -o yaml

# Edit the configmap
kubectl edit configmap argocd-image-updater-config -n argocd
```

Add/update the `registries.conf` section:

```yaml
data:
  registries.conf: |
    registries:
    - name: Azure
      prefix: acrsandboxwus2.azurecr.io
      api_url: https://acrsandboxwus2.azurecr.io
      credentials: pullsecret:argocd/acr-creds
      default: true
```

**Option B: Via AKS command invoke (for private clusters):**

> **Note:** `kubectl edit` does not work via `az aks command invoke` because there is no interactive terminal. Use `kubectl patch` instead.

```bash
# View current configmap
az aks command invoke \
  --resource-group rg-sandbox-horizon \
  --name aks-sandbox-wus2 \
  --command "kubectl get configmap argocd-image-updater-config -n argocd -o yaml"

# Patch the configmap to add credentials
az aks command invoke \
  --resource-group rg-sandbox-horizon \
  --name aks-sandbox-wus2 \
  --command "kubectl patch configmap argocd-image-updater-config -n argocd --type merge -p '{\"data\":{\"registries.conf\":\"registries:\\n  - api_url: https://acrsandboxwus2.azurecr.io\\n    default: true\\n    name: Azure\\n    prefix: acrsandboxwus2.azurecr.io\\n    credentials: pullsecret:argocd/acr-creds\\n\"}}'"
```

**Restart Image Updater to apply changes:**

```bash
# Direct kubectl
kubectl rollout restart deployment argocd-image-updater-controller -n argocd

# Or via AKS command invoke
az aks command invoke \
  --resource-group rg-sandbox-horizon \
  --name aks-sandbox-wus2 \
  --command "kubectl rollout restart deployment argocd-image-updater-controller -n argocd"
```

**Verify the configmap was updated:**
```bash
az aks command invoke \
  --resource-group rg-sandbox-horizon \
  --name aks-sandbox-wus2 \
  --command "kubectl get configmap argocd-image-updater-config -n argocd -o jsonpath='{.data.registries\\.conf}'"
```

---

## Step 5: Configure Argo CD Application

### 5.1 Update argocd-application.yaml

Edit `argocd-application.yaml` and replace `YOUR_GITHUB_USERNAME/YOUR_REPO_NAME` with your repository:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: test-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  annotations:
    # Image Updater: Track this image
    argocd-image-updater.argoproj.io/image-list: fastapi=acrsandboxwus2.azurecr.io/test_app
    # Update strategy: Use newest image by build date
    argocd-image-updater.argoproj.io/fastapi.update-strategy: latest
    # Map to Helm values
    argocd-image-updater.argoproj.io/fastapi.helm.image-name: image.repository
    argocd-image-updater.argoproj.io/fastapi.helm.image-tag: image.tag
    # Update Argo CD directly (no Git commit needed)
    argocd-image-updater.argoproj.io/write-back-method: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME.git
    targetRevision: HEAD
    path: helm/fastapi-service
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### 5.2 Apply the Application

**Option A: Direct kubectl access:**
```bash
kubectl apply -f argocd-application.yaml
```

**Option B: Via AKS command invoke (for private clusters):**

> **Important:** When using `az aks command invoke`, you must use the `--file` parameter to upload the local YAML file to the remote command context.

```bash
az aks command invoke \
  --resource-group rg-sandbox-horizon \
  --name aks-sandbox-wus2 \
  --command "kubectl apply -f argocd-application.yaml" \
  --file argocd-application.yaml
```

### 5.3 Verify Application

```bash
# Check in Argo CD
argocd app get test-app

# Or via kubectl
kubectl get application test-app -n argocd
```

---

## Step 6: Build and Push Image to ACR

This section covers the complete process of building your Docker image and pushing it to Azure Container Registry.

### 6.1 Prerequisites Check

Before pushing, verify you have everything ready:

```bash
# 1. Check Docker is running
docker --version
docker info

# 2. Check Azure CLI is installed and logged in
az --version
az account show

# 3. Verify you can access ACR
az acr show --name acrsandboxwus2 --query loginServer --output tsv
```

### 6.2 Login to Azure (if not already)

```bash
# Login to Azure
az login

# Set subscription (if needed)
az account set --subscription "YOUR_SUBSCRIPTION_NAME_OR_ID"
```

### 6.3 Login to Azure Container Registry

```bash
# Login to ACR (required before pushing)
az acr login --name acrsandboxwus2
```

**Expected output:**
```
Login Succeeded
```

### 6.4 Build Docker Image

Navigate to the project directory (where Dockerfile is located):

```bash
# Navigate to project root
cd /path/to/test_api_server

# Build the image with version tag
docker build -t acrsandboxwus2.azurecr.io/test_app:v1.0.0 .
```

**Alternative tagging options:**

```bash
# Use timestamp for unique tags
docker build -t acrsandboxwus2.azurecr.io/test_app:$(date +%Y%m%d-%H%M%S) .

# Use git commit SHA
docker build -t acrsandboxwus2.azurecr.io/test_app:$(git rev-parse --short HEAD) .

# Build with latest tag
docker build -t acrsandboxwus2.azurecr.io/test_app:latest .
```

**Verify the image was built:**
```bash
docker images | grep test_app
```

### 6.5 Push Image to ACR

```bash
# Push the image to ACR
docker push acrsandboxwus2.azurecr.io/test_app:v1.0.0
```

**Expected output:**
```
The push refers to repository [acrsandboxwus2.azurecr.io/test_app]
abc123def456: Pushed
789ghi012jkl: Pushed
v1.0.0: digest: sha256:... size: 1234
```

### 6.6 Verify Image in ACR

```bash
# List all tags for test_app in ACR
az acr repository show-tags \
  --name acrsandboxwus2 \
  --repository test_app \
  --orderby time_desc \
  --output table
```

**Expected output:**
```
Result
--------
v1.0.0
```

### 6.7 Watch Automatic Deployment

Once the image is pushed, Argo CD Image Updater will detect it (within 2 minutes):

**Check Image Updater logs:**
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater -f
```

**You should see:**
```
level=info msg="Setting new image to acrsandboxwus2.azurecr.io/test_app:v1.0.0"
level=info msg="Successfully updated image 'fastapi' to 'acrsandboxwus2.azurecr.io/test_app:v1.0.0'"
```

### 6.8 Verify Deployment

```bash
# Check what image is running (deployment name is RELEASE-NAME-CHART-NAME)
kubectl get deployment test-app-fastapi-service -o jsonpath='{.spec.template.spec.containers[0].image}'
echo

# Check pod status
kubectl get pods -l app.kubernetes.io/name=fastapi-service

# Get app external IP
kubectl get svc

# Test the app
curl http://EXTERNAL_IP/health
```

---

## 🚀 Complete Image Push Workflow (Copy & Paste)

Here's the complete workflow to build and push an image:

```bash
# ============================================
# COMPLETE IMAGE PUSH WORKFLOW
# ============================================

# Step 1: Navigate to project directory
cd /path/to/test_api_server

# Step 2: Login to Azure (if not already)
az login

# Step 3: Login to ACR
az acr login --name acrsandboxwus2

# Step 4: Build the Docker image
docker build -t acrsandboxwus2.azurecr.io/test_app:v1.0.0 .

# Step 5: Push to ACR
docker push acrsandboxwus2.azurecr.io/test_app:v1.0.0

# Step 6: Verify image is in ACR
az acr repository show-tags --name acrsandboxwus2 --repository test_app --orderby time_desc

# Step 7: Watch deployment (Image Updater will auto-deploy)
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater -f
```

---

## 🔄 Deploy a New Version

Whenever you want to deploy changes:

```bash
# 1. Make your code changes
# 2. Build with new tag
docker build -t acrsandboxwus2.azurecr.io/test_app:v1.0.1 .

# 3. Push to ACR
az acr login --name acrsandboxwus2
docker push acrsandboxwus2.azurecr.io/test_app:v1.0.1

# 4. Image Updater automatically detects and deploys (within 2 minutes)

# 5. Monitor deployment
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater -f
```

---

## 📦 Update Strategy Options

| Strategy | Description | Best For |
|----------|-------------|----------|
| `latest` | Newest image by build date | Dev/Staging |
| `semver` | Semantic versioning (v1.2.3) | Production |
| `digest` | Track SHA digest changes | Mutable tags |
| `name` | Alphabetical sorting | Custom naming |

**Example: Use semver for production:**
```yaml
annotations:
  argocd-image-updater.argoproj.io/fastapi.update-strategy: semver
  argocd-image-updater.argoproj.io/fastapi.allow-tags: regexp:^v[0-9]+\.[0-9]+\.[0-9]+$
```

---

## 📊 Quick Reference Commands

### Build & Push
```bash
# Build image
docker build -t acrsandboxwus2.azurecr.io/test_app:TAG .

# Login to ACR
az acr login --name acrsandboxwus2

# Push image
docker push acrsandboxwus2.azurecr.io/test_app:TAG

# List images in ACR
az acr repository show-tags --name acrsandboxwus2 --repository test_app --orderby time_desc
```

### Azure
```bash
# Login
az login

# Get AKS credentials
az aks get-credentials --resource-group rg-sandbox-horizon --name aks-sandbox-wus2

# Attach ACR to AKS
az aks update --resource-group rg-sandbox-horizon --name aks-sandbox-wus2 --attach-acr acrsandboxwus2
```

### Kubernetes
```bash
# View all resources
kubectl get all

# View pods
kubectl get pods

# View services
kubectl get svc

# View logs
kubectl logs -l app.kubernetes.io/name=fastapi-service

# Describe pod
kubectl describe pod POD_NAME
```

### Argo CD
```bash
# List apps
argocd app list

# Get app details
argocd app get test-app

# Sync manually
argocd app sync test-app

# View history
argocd app history test-app
```

### Image Updater
```bash
# View logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater -f

# Force check for updates (restart the controller)
kubectl rollout restart deployment argocd-image-updater-controller -n argocd

# View config
kubectl get configmap argocd-image-updater-config -n argocd -o yaml

# View registries config specifically
kubectl get configmap argocd-image-updater-config -n argocd -o jsonpath='{.data.registries\.conf}'
```

---

## 🔧 Troubleshooting

### Image Updater not detecting new images

```bash
# Check logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater

# Common issues:
# - "unauthorized" = ACR credentials incorrect
# - "no images found" = image-list annotation wrong
```

### Pods in "ImagePullBackOff" state

```bash
# Reattach ACR to AKS
az aks update \
  --resource-group rg-sandbox-horizon \
  --name aks-sandbox-wus2 \
  --attach-acr acrsandboxwus2
```

### Can't access Argo CD UI

```bash
# Check service
kubectl get svc argocd-server -n argocd

# Use port-forward if no external IP
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### Verify ACR connection from cluster

```bash
kubectl run --rm -it test-acr --image=mcr.microsoft.com/azure-cli --restart=Never -- \
  az acr repository list --name acrsandboxwus2 --output table
```

### Force deployment update

```bash
# Restart Image Updater
kubectl rollout restart deployment argocd-image-updater-controller -n argocd

# Or sync Argo CD manually
argocd app sync test-app
```

---

## 📚 Additional Resources

- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [Argo CD Image Updater](https://argocd-image-updater.readthedocs.io/)
- [Azure Container Registry](https://docs.microsoft.com/azure/container-registry/)
- [Azure Kubernetes Service](https://docs.microsoft.com/azure/aks/)

---

## 🎉 Summary

Your deployment workflow is now:

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   docker build → docker push → Image Updater → Argo CD → AKS   │
│                                                                 │
│   [Build]        [Store]        [Detect]       [Deploy]  [Run] │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

No CI/CD pipeline needed - just build, push, and watch it deploy automatically!
