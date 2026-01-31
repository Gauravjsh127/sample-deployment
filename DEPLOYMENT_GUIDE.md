# Complete CI/CD Deployment Guide
## GitHub Actions + Azure Container Registry + Argo CD + AKS

This guide will walk you through setting up a complete CI/CD pipeline from scratch. We'll use:
- **GitHub Actions** - To build and push Docker images automatically
- **Azure Container Registry (ACR)** - To store Docker images
- **Azure Kubernetes Service (AKS)** - To run your application
- **Argo CD** - To automatically deploy changes to Kubernetes
- **Helm** - To manage Kubernetes deployments

---

## 📋 Table of Contents

1. [Understanding the CI/CD Flow](#understanding-the-cicd-flow)
2. [Prerequisites](#prerequisites)
3. [Step 1: Install Required Tools](#step-1-install-required-tools)
4. [Step 2: Create Azure Resources](#step-2-create-azure-resources)
5. [Step 3: Configure GitHub Repository](#step-3-configure-github-repository)
6. [Step 4: Set Up GitHub Actions CI Pipeline](#step-4-set-up-github-actions-ci-pipeline)
7. [Step 5: Install Argo CD on AKS](#step-5-install-argo-cd-on-aks)
8. [Step 6: Configure Argo CD to Deploy Your App](#step-6-configure-argo-cd-to-deploy-your-app)
9. [Step 7: Test the Complete Pipeline](#step-7-test-the-complete-pipeline)
10. [Troubleshooting](#troubleshooting)

---

## 🔄 Understanding the CI/CD Flow

Before we start, let's understand what happens when you push code:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CI/CD PIPELINE FLOW                                │
└─────────────────────────────────────────────────────────────────────────────┘

  YOU                    GITHUB                    AZURE                    
   │                        │                         │                      
   │  1. Push Code          │                         │                      
   │ ──────────────────────>│                         │                      
   │                        │                         │                      
   │                        │  2. GitHub Actions      │                      
   │                        │     - Build Docker      │                      
   │                        │     - Run Tests         │                      
   │                        │     - Push to ACR ─────>│ Azure Container      
   │                        │                         │ Registry (ACR)       
   │                        │                         │                      
   │                        │  3. Update Helm         │                      
   │                        │     values (image tag)  │                      
   │                        │                         │                      
   │                        │                         │                      
   │                   ARGO CD (running in AKS)       │                      
   │                        │                         │                      
   │                        │  4. Argo CD detects     │                      
   │                        │     changes in Git      │                      
   │                        │                         │                      
   │                        │  5. Argo CD pulls new   │                      
   │                        │     image from ACR <────│                      
   │                        │                         │                      
   │                        │  6. Deploys to AKS ────>│ Azure Kubernetes     
   │                        │                         │ Service (AKS)        
   │                        │                         │                      
   │  7. App is Live!       │                         │                      
   │ <──────────────────────────────────────────────────                     
   │                        │                         │                      
```

**In Simple Words:**
1. You push code to GitHub
2. GitHub Actions automatically builds a Docker image and pushes it to Azure Container Registry
3. GitHub Actions updates the Helm chart with the new image tag
4. Argo CD (watching your Git repository) detects the change
5. Argo CD pulls the new image from ACR and deploys it to AKS
6. Your updated app is now live!

---

## ✅ Prerequisites

Before starting, you need:

| Requirement | Description | How to Get It |
|-------------|-------------|---------------|
| **Azure Account** | Free account works | [Sign up here](https://azure.microsoft.com/free/) |
| **GitHub Account** | Where your code lives | [Sign up here](https://github.com/) |
| **Your Code on GitHub** | Repository with this project | Push your code to GitHub |

---

## Step 1: Install Required Tools

### 1.1 Install Azure CLI

Azure CLI lets you control Azure from your terminal.

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

**Verify installation:**
```bash
az --version
```

### 1.2 Install kubectl

kubectl lets you control Kubernetes clusters.

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

**Verify installation:**
```bash
kubectl version --client
```

### 1.3 Install Helm

Helm is a package manager for Kubernetes.

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

**Verify installation:**
```bash
helm version
```

### 1.4 Install Docker (for local testing)

**Download from:** https://docs.docker.com/get-docker/

---

## Step 2: Create Azure Resources

### 2.1 Login to Azure

```bash
az login
```
This opens a browser window. Sign in with your Azure account.

### 2.2 Set Your Subscription (if you have multiple)

```bash
# List all subscriptions
az account list --output table

# Set the subscription you want to use
az account set --subscription "YOUR_SUBSCRIPTION_NAME_OR_ID"
```

### 2.3 Create a Resource Group

A Resource Group is like a folder that holds all your Azure resources.

```bash
# Choose a name and location
RESOURCE_GROUP="fastapi-cicd-rg"
LOCATION="eastus"

# Create the resource group
az group create --name $RESOURCE_GROUP --location $LOCATION
```

**Expected Output:**
```json
{
  "id": "/subscriptions/.../resourceGroups/fastapi-cicd-rg",
  "location": "eastus",
  "name": "fastapi-cicd-rg",
  "properties": {
    "provisioningState": "Succeeded"
  }
}
```

### 2.4 Create Azure Container Registry (ACR)

ACR stores your Docker images (like Docker Hub but in Azure).

```bash
# Choose a unique name (only lowercase letters and numbers, 5-50 characters)
ACR_NAME="fastapiserviceacr$(date +%s | tail -c 6)"

# Create ACR
az acr create \
  --resource-group $RESOURCE_GROUP \
  --name $ACR_NAME \
  --sku Basic \
  --admin-enabled true

# Get the ACR login server URL (you'll need this later)
ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --query loginServer --output tsv)
echo "Your ACR Login Server: $ACR_LOGIN_SERVER"
```

**Save this value!** It looks like: `fastapiserviceacr12345.azurecr.io`

### 2.5 Create Azure Kubernetes Service (AKS)

AKS is where your application will run.

```bash
AKS_CLUSTER_NAME="fastapi-aks-cluster"

# Create AKS cluster (this takes 5-10 minutes)
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --node-count 2 \
  --node-vm-size Standard_B2s \
  --enable-managed-identity \
  --generate-ssh-keys

echo "AKS cluster creation started. This takes about 5-10 minutes..."
```

**What each option means:**
- `--node-count 2`: Creates 2 virtual machines (nodes) to run your containers
- `--node-vm-size Standard_B2s`: Uses a small, cost-effective VM size
- `--enable-managed-identity`: Allows AKS to securely access other Azure resources
- `--generate-ssh-keys`: Creates SSH keys for node access

### 2.6 Connect AKS to ACR

Allow AKS to pull images from your container registry:

```bash
az aks update \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --attach-acr $ACR_NAME
```

### 2.7 Get AKS Credentials

Download the credentials to control your AKS cluster:

```bash
az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME
```

**Verify connection:**
```bash
kubectl get nodes
```

**Expected Output:**
```
NAME                                STATUS   ROLES   AGE   VERSION
aks-nodepool1-12345678-vmss000000   Ready    agent   5m    v1.28.0
aks-nodepool1-12345678-vmss000001   Ready    agent   5m    v1.28.0
```

---

## Step 3: Configure GitHub Repository

### 3.1 Create a Service Principal for GitHub

GitHub needs permission to push images to ACR. We create a "Service Principal" (like a service account):

```bash
# Get your subscription ID
SUBSCRIPTION_ID=$(az account show --query id --output tsv)

# Create service principal with ACR push permissions
SP_OUTPUT=$(az ad sp create-for-rbac \
  --name "github-actions-acr-sp" \
  --role AcrPush \
  --scopes /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerRegistry/registries/$ACR_NAME \
  --sdk-auth)

echo "$SP_OUTPUT"
```

**⚠️ IMPORTANT: Save this entire JSON output!** You'll need it for GitHub secrets.

The output looks like:
```json
{
  "clientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "clientSecret": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "subscriptionId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  ...
}
```

### 3.2 Add Secrets to GitHub

1. Go to your GitHub repository
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret** and add these secrets:

| Secret Name | Value |
|-------------|-------|
| `AZURE_CREDENTIALS` | The entire JSON output from step 3.1 |
| `ACR_LOGIN_SERVER` | Your ACR login server (e.g., `fastapiserviceacr12345.azurecr.io`) |
| `ACR_USERNAME` | Get with: `az acr credential show --name $ACR_NAME --query username -o tsv` |
| `ACR_PASSWORD` | Get with: `az acr credential show --name $ACR_NAME --query passwords[0].value -o tsv` |

**To get ACR credentials:**
```bash
# Get ACR username
az acr credential show --name $ACR_NAME --query username -o tsv

# Get ACR password
az acr credential show --name $ACR_NAME --query passwords[0].value -o tsv
```

---

## Step 4: Set Up GitHub Actions CI Pipeline

### 4.1 Create the GitHub Actions Workflow

Create a new file in your repository: `.github/workflows/ci-cd.yml`

```yaml
name: CI/CD Pipeline

on:
  push:
    branches:
      - main
      - master
  pull_request:
    branches:
      - main
      - master

env:
  IMAGE_NAME: fastapi-service

jobs:
  # ==========================================
  # JOB 1: Build, Test, and Push Docker Image
  # ==========================================
  build-and-push:
    name: Build and Push to ACR
    runs-on: ubuntu-latest
    
    outputs:
      image_tag: ${{ steps.meta.outputs.version }}
    
    steps:
      # Step 1: Get the code
      - name: Checkout code
        uses: actions/checkout@v4

      # Step 2: Set up Docker Buildx (for better builds)
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      # Step 3: Login to Azure Container Registry
      - name: Login to ACR
        uses: docker/login-action@v3
        with:
          registry: ${{ secrets.ACR_LOGIN_SERVER }}
          username: ${{ secrets.ACR_USERNAME }}
          password: ${{ secrets.ACR_PASSWORD }}

      # Step 4: Generate image tags
      - name: Generate Docker metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ secrets.ACR_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}
          tags: |
            type=sha,prefix=
            type=raw,value=latest,enable={{is_default_branch}}
            type=ref,event=branch
            type=ref,event=pr

      # Step 5: Build and push image
      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      # Step 6: Print image info
      - name: Print image tags
        run: |
          echo "Image pushed with tags:"
          echo "${{ steps.meta.outputs.tags }}"

  # ==========================================
  # JOB 2: Update Helm Chart with New Image Tag
  # ==========================================
  update-helm-values:
    name: Update Helm Values
    runs-on: ubuntu-latest
    needs: build-and-push
    if: github.event_name != 'pull_request'
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Update Helm values.yaml with new image tag
        run: |
          # Get the short SHA
          SHORT_SHA=$(echo ${{ github.sha }} | cut -c1-7)
          
          # Update the image repository and tag in values.yaml
          sed -i "s|repository:.*|repository: ${{ secrets.ACR_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}|g" helm/fastapi-service/values.yaml
          sed -i "s|tag:.*|tag: \"${SHORT_SHA}\"|g" helm/fastapi-service/values.yaml
          
          # Show the changes
          echo "Updated values.yaml:"
          cat helm/fastapi-service/values.yaml

      - name: Commit and push changes
        run: |
          git config --local user.email "github-actions[bot]@users.noreply.github.com"
          git config --local user.name "github-actions[bot]"
          git add helm/fastapi-service/values.yaml
          git diff --staged --quiet || git commit -m "Update image tag to ${{ github.sha }}"
          git push
```

### 4.2 What This Workflow Does

1. **Triggers**: Runs on every push to `main` or `master` branch
2. **Build and Push Job**:
   - Checks out your code
   - Logs into Azure Container Registry
   - Builds the Docker image
   - Pushes it to ACR with tags based on the commit SHA
3. **Update Helm Values Job**:
   - Updates `helm/fastapi-service/values.yaml` with the new image tag
   - Commits and pushes the change
   - This triggers Argo CD to deploy the new version!

### 4.3 Push the Workflow to GitHub

```bash
# Create the directory
mkdir -p .github/workflows

# Create the file (copy the content from above)
# Then commit and push
git add .github/workflows/ci-cd.yml
git commit -m "Add CI/CD pipeline"
git push
```

---

## Step 5: Install Argo CD on AKS

### 5.1 Create Argo CD Namespace

```bash
kubectl create namespace argocd
```

### 5.2 Install Argo CD

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

**Wait for all pods to be ready (takes 2-3 minutes):**
```bash
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s
```

### 5.3 Access Argo CD UI

**Option A: Using LoadBalancer (Recommended for testing)**

```bash
# Change the argocd-server service to LoadBalancer
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# Get the external IP (wait until EXTERNAL-IP shows an IP, not <pending>)
kubectl get svc argocd-server -n argocd -w
```

**Option B: Using Port Forward (Quick local access)**

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
Then open: https://localhost:8080

### 5.4 Get Argo CD Admin Password

```bash
# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo  # Add newline for readability
```

**Login credentials:**
- **Username**: `admin`
- **Password**: (the output from above command)

### 5.5 Install Argo CD CLI (Optional but Useful)

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
# Get the external IP
ARGOCD_SERVER=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Login (use --insecure because we don't have TLS set up yet)
argocd login $ARGOCD_SERVER --insecure

# When prompted, enter:
# Username: admin
# Password: (the password from step 5.4)
```

---

## Step 6: Configure Argo CD to Deploy Your App

### 6.1 Create an Argo CD Application

You can do this via the UI or CLI. Here's both methods:

#### Method A: Using the Argo CD UI

1. Open Argo CD UI in your browser
2. Click **+ NEW APP**
3. Fill in the form:

| Field | Value |
|-------|-------|
| **Application Name** | `fastapi-service` |
| **Project** | `default` |
| **Sync Policy** | `Automatic` |
| **Repository URL** | `https://github.com/YOUR_USERNAME/YOUR_REPO.git` |
| **Path** | `helm/fastapi-service` |
| **Cluster URL** | `https://kubernetes.default.svc` |
| **Namespace** | `default` |

4. Click **CREATE**

#### Method B: Using a YAML File (Recommended)

Create a file called `argocd-application.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: fastapi-service
  namespace: argocd
spec:
  project: default
  
  source:
    # Replace with your GitHub repository URL
    repoURL: https://github.com/YOUR_USERNAME/YOUR_REPO.git
    targetRevision: HEAD
    path: helm/fastapi-service
    
    # Helm-specific configuration
    helm:
      valueFiles:
        - values.yaml
  
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  
  syncPolicy:
    automated:
      prune: true      # Delete resources that are no longer in Git
      selfHeal: true   # Automatically fix drift
    syncOptions:
      - CreateNamespace=true
```

**Apply it:**
```bash
kubectl apply -f argocd-application.yaml
```

### 6.2 Verify Application is Syncing

Check in the Argo CD UI or use CLI:

```bash
argocd app get fastapi-service
```

**Expected output:**
```
Name:               fastapi-service
Project:            default
Server:             https://kubernetes.default.svc
Namespace:          default
URL:                https://argocd.example.com/applications/fastapi-service
Repo:               https://github.com/YOUR_USERNAME/YOUR_REPO.git
Target:             HEAD
Path:               helm/fastapi-service
SyncWindow:         Sync Allowed
Sync Policy:        Automated (Prune)
Sync Status:        Synced to HEAD (abc1234)
Health Status:      Healthy
```

### 6.3 Check Your Application is Running

```bash
# See all resources deployed
kubectl get all -l app.kubernetes.io/name=fastapi-service

# Get the external IP of your app
kubectl get svc
```

**Access your app:**
- API: `http://EXTERNAL_IP/`
- Health: `http://EXTERNAL_IP/health`
- Docs: `http://EXTERNAL_IP/docs`

---

## Step 7: Test the Complete Pipeline

Let's make a change and watch the entire pipeline work!

### 7.1 Make a Code Change

Edit `app/main.py` and change the welcome message:

```python
@app.get("/")
async def root():
    return {"message": "Hello from CI/CD Pipeline! 🚀"}
```

### 7.2 Commit and Push

```bash
git add app/main.py
git commit -m "Update welcome message"
git push
```

### 7.3 Watch the Pipeline

1. **GitHub Actions**: 
   - Go to your GitHub repo → **Actions** tab
   - Watch the workflow run (takes 2-3 minutes)
   
2. **Argo CD**:
   - Open Argo CD UI
   - Watch the `fastapi-service` app sync
   - It will show "Syncing" then "Healthy"

3. **Verify the Change**:
   ```bash
   curl http://EXTERNAL_IP/
   # Should show: {"message":"Hello from CI/CD Pipeline! 🚀"}
   ```

---

## 🎉 Congratulations!

You now have a fully automated CI/CD pipeline:

```
┌──────────────────────────────────────────────────────────────────┐
│                    YOUR CI/CD PIPELINE                            │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  git push ──> GitHub Actions ──> ACR ──> Argo CD ──> AKS ──> 🌐 │
│                                                                   │
│  [Code]      [Build/Test]     [Store]   [Deploy]   [Run]   [Live]│
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

---

## 📊 Quick Reference: Commands Cheat Sheet

### Azure Commands
```bash
# Login to Azure
az login

# List resources
az group list --output table
az acr list --output table
az aks list --output table

# Get AKS credentials
az aks get-credentials --resource-group RESOURCE_GROUP --name CLUSTER_NAME
```

### Kubernetes Commands
```bash
# View all resources
kubectl get all

# View pods
kubectl get pods

# View services and get external IP
kubectl get svc

# View logs
kubectl logs -l app.kubernetes.io/name=fastapi-service

# Describe pod (for debugging)
kubectl describe pod POD_NAME
```

### Argo CD Commands
```bash
# List apps
argocd app list

# Get app details
argocd app get fastapi-service

# Sync app manually
argocd app sync fastapi-service

# View app history
argocd app history fastapi-service
```

### Helm Commands
```bash
# List releases
helm list

# View release status
helm status fastapi-release

# Upgrade release
helm upgrade fastapi-release ./helm/fastapi-service

# Rollback to previous version
helm rollback fastapi-release 1
```

---

## 🔧 Troubleshooting

### Problem: GitHub Actions fails to push to ACR

**Solution:** Check your secrets are correct:
```bash
# Verify ACR credentials work locally
docker login YOUR_ACR_LOGIN_SERVER
# Enter the username and password from secrets
```

### Problem: Argo CD shows "Unknown" health status

**Solution:** Wait a few minutes, or sync manually:
```bash
argocd app sync fastapi-service
```

### Problem: App pods are in "ImagePullBackOff" state

**Solution:** AKS might not have permission to pull from ACR:
```bash
# Reattach ACR to AKS
az aks update \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --attach-acr $ACR_NAME
```

### Problem: Can't access Argo CD UI

**Solution:** Ensure LoadBalancer has an IP:
```bash
kubectl get svc argocd-server -n argocd
# If EXTERNAL-IP is <pending>, wait or use port-forward:
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### Problem: Changes not deploying automatically

**Solution:** Check if Argo CD sync is enabled:
```bash
argocd app get fastapi-service
# Look for "Sync Policy: Automated"

# If not automated, enable it:
argocd app set fastapi-service --sync-policy automated
```

---

## 🧹 Cleanup (Delete All Resources)

When you're done, delete everything to avoid charges:

```bash
# Delete the entire resource group (this deletes everything inside it)
az group delete --name $RESOURCE_GROUP --yes --no-wait

# Delete the service principal
az ad sp delete --id $(az ad sp list --display-name "github-actions-acr-sp" --query [0].appId -o tsv)
```

---

## 📚 Additional Resources

- [Azure Kubernetes Service Documentation](https://docs.microsoft.com/azure/aks/)
- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [Helm Documentation](https://helm.sh/docs/)
- [GitHub Actions Documentation](https://docs.github.com/actions)

---

## 💡 Next Steps

Once your basic pipeline is working, consider:

1. **Add staging environment**: Deploy to staging first, then production
2. **Add Slack/Teams notifications**: Get notified on deployments
3. **Add monitoring**: Use Azure Monitor or Prometheus/Grafana
4. **Add secrets management**: Use Azure Key Vault
5. **Add HTTPS/TLS**: Configure ingress with Let's Encrypt certificates

