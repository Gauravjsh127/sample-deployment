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

# 2. Get the next version number automatically
# This fetches the latest version from ACR and increments the patch number
LATEST_VERSION=$(az acr repository show-tags --name acrsandboxwus2 --repository test_app --orderby time_desc --output tsv 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
if [ -z "$LATEST_VERSION" ]; then
  NEW_VERSION="v1.0.0"
else
  # Parse version and increment patch number
  MAJOR=$(echo $LATEST_VERSION | sed 's/v//' | cut -d. -f1)
  MINOR=$(echo $LATEST_VERSION | sed 's/v//' | cut -d. -f2)
  PATCH=$(echo $LATEST_VERSION | sed 's/v//' | cut -d. -f3)
  NEW_VERSION="v${MAJOR}.${MINOR}.$((PATCH + 1))"
fi
echo "Building version: $NEW_VERSION (previous: ${LATEST_VERSION:-none})"

# 3. Build image (from project directory)
# ⚠️ Apple Silicon (M1/M2/M3) users MUST use --platform linux/amd64
docker build --platform linux/amd64 -t acrsandboxwus2.azurecr.io/test_app:$NEW_VERSION .

# 4. Push to ACR
docker push acrsandboxwus2.azurecr.io/test_app:$NEW_VERSION

# 5. Verify the push
echo "✅ Pushed: acrsandboxwus2.azurecr.io/test_app:$NEW_VERSION"
az acr repository show-tags --name acrsandboxwus2 --repository test_app --orderby time_desc --output table | head -5

# 6. Done! Image Updater auto-deploys within 2 minutes
# Monitor with: kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater -f
```

### One-Liner Version (Copy & Paste Ready)

```bash
# Complete one-liner: Login, auto-version, build, push
az acr login --name acrsandboxwus2 && \
LATEST=$(az acr repository show-tags --name acrsandboxwus2 --repository test_app --orderby time_desc -o tsv 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1) && \
NEW_VERSION=${LATEST:+v$(echo $LATEST | sed 's/v//' | awk -F. '{print $1"."$2"."$3+1}')} && \
NEW_VERSION=${NEW_VERSION:-v1.0.0} && \
echo "🚀 Building $NEW_VERSION" && \
docker build --platform linux/amd64 -t acrsandboxwus2.azurecr.io/test_app:$NEW_VERSION . && \
docker push acrsandboxwus2.azurecr.io/test_app:$NEW_VERSION && \
echo "✅ Deployed! ArgoCD will sync within 2 minutes"
```

> **First time setup?** Follow the complete guide below starting from [Step 1](#step-1-install-required-tools).
> 
> **Note:** ArgoCD Image Updater uses `semver` strategy, so it always deploys the **highest** semantic version (e.g., v1.0.5 > v1.0.4). Each push must use a higher version number.

---

## 🛠️ Using the Deploy Script (Recommended)

For the easiest deployment experience, use the included deploy script:

```bash
# Navigate to project directory
cd /path/to/test_api_server

# Deploy with auto-incrementing patch version (v1.0.0 → v1.0.1 → v1.0.2)
./scripts/deploy.sh

# Or specify version increment type:
./scripts/deploy.sh --patch   # v1.0.5 → v1.0.6 (default)
./scripts/deploy.sh --minor   # v1.0.5 → v1.1.0
./scripts/deploy.sh --major   # v1.0.5 → v2.0.0
```

The script automatically:
1. ✅ Logs into ACR
2. ✅ Fetches the latest version from ACR
3. ✅ Increments the version number
4. ✅ Builds with correct platform (linux/amd64)
5. ✅ Pushes to ACR
6. ✅ Shows you how to monitor the deployment

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
2. [Using the Deploy Script](#️-using-the-deploy-script-recommended)
3. [Prerequisites](#prerequisites)
4. [Step 1: Install Required Tools](#step-1-install-required-tools)
5. [Step 2: Connect to Azure Resources](#step-2-connect-to-azure-resources)
6. [Step 3: Install Argo CD on AKS](#step-3-install-argo-cd-on-aks)
7. [Step 4: Install Argo CD Image Updater](#step-4-install-argo-cd-image-updater)
8. [Step 5: Configure Argo CD Application](#step-5-configure-argo-cd-application)
9. [Step 6: Build and Push Image to ACR](#step-6-build-and-push-image-to-acr)
10. [Complete Image Push Workflow](#-complete-image-push-workflow-copy--paste)
11. [Deploy a New Version](#-deploy-a-new-version)
12. [Quick Reference Commands](#-quick-reference-commands)

---

## ✅ Prerequisites

| Requirement | Description |
|-------------|-------------|
| **Azure Account** | Access to the pre-configured resources |
| **Docker** | For building images locally |
| **Your Code** | This repository cloned locally |

---

## Step 1: Install Required Tools (macOS)

### 1.1 Install Azure CLI

```bash
brew install azure-cli
```

**Verify:**
```bash
az --version
```

### 1.2 Install kubectl

```bash
brew install kubectl
```

**Verify:**
```bash
kubectl version --client
```

### 1.3 Install Helm

```bash
brew install helm
```

**Verify:**
```bash
helm version
```

### 1.4 Install Docker

```bash
brew install --cask docker
```

Then open Docker Desktop from Applications.

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

```bash
brew install argocd
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
    # Update strategy: Use semver for proper version ordering (v1.0.0, v1.0.1, etc.)
    argocd-image-updater.argoproj.io/fastapi.update-strategy: semver
    # Only consider tags matching semver pattern (v1.0.0, v2.1.3, etc.)
    argocd-image-updater.argoproj.io/fastapi.allow-tags: regexp:^v[0-9]+\.[0-9]+\.[0-9]+$
    # Map to Helm values
    argocd-image-updater.argoproj.io/fastapi.helm.image-name: image.repository
    argocd-image-updater.argoproj.io/fastapi.helm.image-tag: image.tag
    # Update Argo CD directly (no Git commit needed)
    argocd-image-updater.argoproj.io/write-back-method: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/Gauravjsh127/sample-deployment.git
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
```

> ⚠️ **IMPORTANT: Apple Silicon (M1/M2/M3) Users**
>
> AKS runs on AMD64 (x86_64) architecture. You **MUST** specify the target platform or you'll get `exec format error` when pods try to start.

```bash
# Build for AMD64 architecture (required for AKS)
docker build --platform linux/amd64 -t acrsandboxwus2.azurecr.io/test_app:v1.0.0 .
```

**Alternative tagging options:**

```bash
# Use timestamp for unique tags
docker build --platform linux/amd64 -t acrsandboxwus2.azurecr.io/test_app:$(date +%Y%m%d-%H%M%S) .

# Use git commit SHA
docker build --platform linux/amd64 -t acrsandboxwus2.azurecr.io/test_app:$(git rev-parse --short HEAD) .

# Build with latest tag
docker build --platform linux/amd64 -t acrsandboxwus2.azurecr.io/test_app:latest .
```

**Verify the image was built:**
```bash
docker images | grep test_app
```

**Verify image architecture:**
```bash
docker inspect acrsandboxwus2.azurecr.io/test_app:v1.0.0 | grep Architecture
# Should output: "Architecture": "amd64"
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

**Option A: Direct kubectl access:**
```bash
# Step 1: Check if ArgoCD application exists and is synced
kubectl get application test-app -n argocd

# Step 2: Check ArgoCD app sync status
kubectl get application test-app -n argocd -o jsonpath='{.status.sync.status}'

# Step 3: List all deployments to find the correct name
kubectl get deployments

# Step 4: Check what image is running (deployment name is RELEASE-NAME-CHART-NAME)
kubectl get deployment test-app-fastapi-service -o jsonpath='{.spec.template.spec.containers[0].image}'

# Step 5: Check pod status
kubectl get pods -l app.kubernetes.io/name=fastapi-service

# Step 6: Get app external IP
kubectl get svc

# Step 7: Test the app (replace EXTERNAL_IP with actual IP)
curl http://EXTERNAL_IP/health
```

**Option B: Via AKS command invoke (for private clusters):**

> **Important:** Run each command separately. Do NOT combine commands with comments on the same line.

```bash
# Step 1: Check if ArgoCD application exists
az aks command invoke \
  --resource-group rg-sandbox-horizon \
  --name aks-sandbox-wus2 \
  --command "kubectl get application test-app -n argocd"
```

```bash
# Step 2: Check ArgoCD app sync status
az aks command invoke \
  --resource-group rg-sandbox-horizon \
  --name aks-sandbox-wus2 \
  --command "kubectl get application test-app -n argocd -o jsonpath='{.status.sync.status}'"
```

```bash
# Step 3: List all deployments in default namespace
az aks command invoke \
  --resource-group rg-sandbox-horizon \
  --name aks-sandbox-wus2 \
  --command "kubectl get deployments"
```

```bash
# Step 4: Check what image is running
az aks command invoke \
  --resource-group rg-sandbox-horizon \
  --name aks-sandbox-wus2 \
  --command "kubectl get deployment test-app-fastapi-service -o jsonpath='{.spec.template.spec.containers[0].image}'"
```

```bash
# Step 5: Check pod status
az aks command invoke \
  --resource-group rg-sandbox-horizon \
  --name aks-sandbox-wus2 \
  --command "kubectl get pods -l app.kubernetes.io/name=fastapi-service"
```

```bash
# Step 6: Get services and external IP
az aks command invoke \
  --resource-group rg-sandbox-horizon \
  --name aks-sandbox-wus2 \
  --command "kubectl get svc"
```

```bash
# Step 7: Test the app from inside the cluster
az aks command invoke \
  --resource-group rg-sandbox-horizon \
  --name aks-sandbox-wus2 \
  --command "kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -- curl -s http://test-app-fastapi-service/health"
```

---

## 🚀 Complete Image Push Workflow (Copy & Paste)

Here's the complete workflow to build and push an image with **automatic versioning**:

```bash
# ============================================
# COMPLETE IMAGE PUSH WORKFLOW (AUTO-VERSION)
# ============================================

# Step 1: Navigate to project directory
cd /path/to/test_api_server

# Step 2: Login to Azure (if not already)
az login

# Step 3: Login to ACR
az acr login --name acrsandboxwus2

# Step 4: Get next version automatically
LATEST_VERSION=$(az acr repository show-tags --name acrsandboxwus2 --repository test_app --orderby time_desc --output tsv 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
if [ -z "$LATEST_VERSION" ]; then
  NEW_VERSION="v1.0.0"
else
  MAJOR=$(echo $LATEST_VERSION | sed 's/v//' | cut -d. -f1)
  MINOR=$(echo $LATEST_VERSION | sed 's/v//' | cut -d. -f2)
  PATCH=$(echo $LATEST_VERSION | sed 's/v//' | cut -d. -f3)
  NEW_VERSION="v${MAJOR}.${MINOR}.$((PATCH + 1))"
fi
echo "📦 Building: $NEW_VERSION (previous: ${LATEST_VERSION:-none})"

# Step 5: Build the Docker image
# ⚠️ Apple Silicon (M1/M2/M3) users MUST use --platform linux/amd64
docker build --platform linux/amd64 -t acrsandboxwus2.azurecr.io/test_app:$NEW_VERSION .

# Step 6: Push to ACR
docker push acrsandboxwus2.azurecr.io/test_app:$NEW_VERSION

# Step 7: Verify image is in ACR
echo "✅ Successfully pushed: $NEW_VERSION"
az acr repository show-tags --name acrsandboxwus2 --repository test_app --orderby time_desc --output table | head -5

# Step 8: Watch deployment (Image Updater will auto-deploy within 2 min)
echo "⏳ Waiting for ArgoCD Image Updater to detect and deploy..."
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater -f
```

### Version Progression Example

Each time you run the workflow, versions increment automatically:
- First push: `v1.0.0`
- Second push: `v1.0.1`  
- Third push: `v1.0.2`
- ... and so on

ArgoCD Image Updater always selects the **highest** semantic version.

---

## 🔄 Deploy a New Version

Whenever you want to deploy changes:

```bash
# 1. Make your code changes

# 2. Login to ACR
az acr login --name acrsandboxwus2

# 3. Auto-generate next version
LATEST=$(az acr repository show-tags --name acrsandboxwus2 --repository test_app --orderby time_desc -o tsv 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
if [ -z "$LATEST" ]; then
  NEW_VERSION="v1.0.0"
else
  NEW_VERSION="v$(echo $LATEST | sed 's/v//' | awk -F. '{print $1"."$2"."$3+1}')"
fi
echo "📦 Current: ${LATEST:-none} → New: $NEW_VERSION"

# 4. Build with auto-generated tag
# ⚠️ Apple Silicon (M1/M2/M3) users MUST use --platform linux/amd64
docker build --platform linux/amd64 -t acrsandboxwus2.azurecr.io/test_app:$NEW_VERSION .

# 5. Push to ACR
docker push acrsandboxwus2.azurecr.io/test_app:$NEW_VERSION

# 6. Image Updater automatically detects and deploys (within 2 minutes)
echo "✅ Pushed $NEW_VERSION - ArgoCD will sync automatically"

# 7. Monitor deployment
az aks command invoke \
  --resource-group rg-sandbox-horizon \
  --name aks-sandbox-wus2 \
  --command "kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater --tail=20"
```

### Quick Deploy One-Liner

After making code changes, just run:

```bash
az acr login --name acrsandboxwus2 && \
NEW_VERSION="v$(az acr repository show-tags --name acrsandboxwus2 --repository test_app --orderby time_desc -o tsv 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 | sed 's/v//' | awk -F. '{print $1"."$2"."$3+1}')" && \
NEW_VERSION=${NEW_VERSION:-v1.0.0} && \
docker build --platform linux/amd64 -t acrsandboxwus2.azurecr.io/test_app:$NEW_VERSION . && \
docker push acrsandboxwus2.azurecr.io/test_app:$NEW_VERSION && \
echo "✅ Deployed $NEW_VERSION"
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

### Build & Push (Auto-Version)
```bash
# Login to ACR
az acr login --name acrsandboxwus2

# Get next version
NEW_VERSION="v$(az acr repository show-tags --name acrsandboxwus2 --repository test_app --orderby time_desc -o tsv 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 | sed 's/v//' | awk -F. '{print $1"."$2"."$3+1}')"
NEW_VERSION=${NEW_VERSION:-v1.0.0}

# Build image (use --platform linux/amd64 on Apple Silicon Macs)
docker build --platform linux/amd64 -t acrsandboxwus2.azurecr.io/test_app:$NEW_VERSION .

# Push image
docker push acrsandboxwus2.azurecr.io/test_app:$NEW_VERSION

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
