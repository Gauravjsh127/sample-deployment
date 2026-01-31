# FastAPI Simple Service

A minimal FastAPI service with health check endpoint and Swagger documentation.

## Features

- Health check endpoint
- Swagger UI documentation at `/docs`
- ReDoc documentation at `/redoc`
- Docker and Docker Compose support

## API Endpoints

| Method | Endpoint  | Description              |
|--------|-----------|--------------------------|
| GET    | `/`       | Welcome message          |
| GET    | `/health` | Health check endpoint    |
| GET    | `/docs`   | Swagger UI documentation |
| GET    | `/redoc`  | ReDoc documentation      |

## Running Locally

### Option 1: Using Python directly

1. Create a virtual environment:
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

3. Run the server:
   ```bash
   uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
   ```

4. Open your browser and navigate to:
   - API: http://localhost:8000
   - Swagger Docs: http://localhost:8000/docs
   - ReDoc: http://localhost:8000/redoc

### Option 2: Using Docker

1. Build the Docker image:
   ```bash
   docker build -t fastapi-service .
   ```

2. Run the container:
   ```bash
   docker run -p 8000:8000 fastapi-service
   ```

### Option 3: Using Docker Compose (Recommended)

1. Start the service:
   ```bash
   docker-compose up --build
   ```

2. To run in detached mode:
   ```bash
   docker-compose up -d --build
   ```

3. To stop the service:
   ```bash
   docker-compose down
   ```

## Health Check

Test the health endpoint:

```bash
curl http://localhost:8000/health
```

Expected response:
```json
{
  "status": "healthy",
  "timestamp": "2024-01-29T10:30:00.000000",
  "service": "fastapi-service"
}
```

## Deploy to Azure Kubernetes Service (AKS)

### 🚀 Full CI/CD Pipeline (Recommended)

For a complete automated CI/CD setup with **GitHub Actions + Azure Container Registry + Argo CD + AKS**, see the comprehensive guide:

**[📖 DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md)**

This guide covers:
- GitHub Actions for automated builds
- Azure Container Registry for image storage
- Argo CD for GitOps-based deployments
- Helm for Kubernetes package management
- Step-by-step setup from scratch

### Quick Deploy (Automated Script)

```bash
# Make script executable
chmod +x scripts/deploy-to-aks.sh

# Run full deployment
./scripts/deploy-to-aks.sh

# Or customize with environment variables
RESOURCE_GROUP="my-rg" ACR_NAME="myacr" ./scripts/deploy-to-aks.sh
```

### Manual Deploy (Step by Step)

```bash
# 1. Set variables
export RESOURCE_GROUP="fastapi-rg"
export LOCATION="eastus"
export ACR_NAME="fastapiserviceacr"
export AKS_CLUSTER_NAME="fastapi-aks-cluster"

# 2. Login & create resources
az login
az group create --name $RESOURCE_GROUP --location $LOCATION
az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Basic --admin-enabled true
export ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --query loginServer --output tsv)

# 3. Build & push image
docker build -t fastapi-service:latest .
docker tag fastapi-service:latest $ACR_LOGIN_SERVER/fastapi-service:latest
az acr login --name $ACR_NAME
docker push $ACR_LOGIN_SERVER/fastapi-service:latest

# 4. Create AKS & deploy
az aks create --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --node-count 2 --node-vm-size Standard_B2s --enable-managed-identity --generate-ssh-keys
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME
az aks update --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --attach-acr $ACR_NAME

# 5. Deploy with Helm
helm install fastapi-release ./helm/fastapi-service --set image.repository=$ACR_LOGIN_SERVER/fastapi-service --set image.tag=latest

# 6. Get External IP
kubectl get svc -w
```

## Project Structure

```
.
├── .github/
│   └── workflows/
│       └── ci-cd.yml           # GitHub Actions CI/CD pipeline
├── app/
│   ├── __init__.py
│   └── main.py
├── helm/
│   └── fastapi-service/        # Helm chart for Kubernetes deployment
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
├── scripts/
│   └── deploy-to-aks.sh        # Automated deployment script
├── argocd-application.yaml     # Argo CD application manifest
├── Dockerfile
├── docker-compose.yml
├── requirements.txt
├── DEPLOYMENT_GUIDE.md         # Complete CI/CD setup guide
└── README.md
```

