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
   docker build -t test_app .
   ```

2. Run the container:
   ```bash
   docker run -p 8000:8000 test_app
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
  "timestamp": "2024-01-29T10:30:00.000000+00:00",
  "service": "fastapi-service"
}
```

## Deploy to Azure Kubernetes Service (AKS)

### Pre-Configured Azure Resources

| Resource | Value |
|----------|-------|
| **Resource Group** | `rg-sandbox-horizon` |
| **Region** | `West US 2` |
| **AKS Cluster** | `aks-sandbox-wus2` |
| **Container Registry** | `acrsandboxwus2.azurecr.io` |

### 🚀 Registry-Driven Deployment (Recommended)

For the complete deployment guide with **Argo CD Image Updater**, see:

**[📖 DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md)**

This guide covers:
- Local Docker build and push to ACR
- Argo CD Image Updater for automatic deployments
- No CI/CD pipeline needed - just push and deploy!

### Quick Deploy

Once Argo CD and Image Updater are configured (see guide), deploying is simple:

```bash
# 1. Build your image
docker build -t acrsandboxwus2.azurecr.io/test_app:v1.0.0 .

# 2. Login and push to ACR
az acr login --name acrsandboxwus2
docker push acrsandboxwus2.azurecr.io/test_app:v1.0.0

# 3. Image Updater automatically detects and deploys!

# 4. Check deployment status
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater -f
```

### Manual Deploy (Without Image Updater)

```bash
# 1. Set variables
export RESOURCE_GROUP="rg-sandbox-horizon"
export ACR_NAME="acrsandboxwus2"
export AKS_CLUSTER_NAME="aks-sandbox-wus2"

# 2. Login to Azure
az login

# 3. Build & push image
docker build -t acrsandboxwus2.azurecr.io/test_app:latest .
az acr login --name acrsandboxwus2
docker push acrsandboxwus2.azurecr.io/test_app:latest

# 4. Get AKS credentials
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME

# 5. Deploy with Helm
helm install fastapi-release ./helm/fastapi-service

# 6. Get External IP
kubectl get svc -w
```

## Project Structure

```
.
├── app/
│   ├── __init__.py
│   └── main.py                 # FastAPI application
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

