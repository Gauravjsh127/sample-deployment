from fastapi import FastAPI
from pydantic import BaseModel
from datetime import datetime, timezone

app = FastAPI(
    title="Simple FastAPI Service",
    description="A minimal FastAPI service with health check endpoint",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)


class HealthResponse(BaseModel):
    status: str
    timestamp: str
    service: str


@app.get("/health", response_model=HealthResponse, tags=["Health"])
async def health_check():
    """
    Health check endpoint to verify the service is running.
    
    Returns:
        HealthResponse: Status of the service with timestamp
    """
    return HealthResponse(
        status="healthy",
        timestamp=datetime.now(timezone.utc).isoformat(),
        service="fastapi-service"
    )


@app.get("/", tags=["Root"])
async def root():
    """
    Root endpoint with welcome message.
    """
    return {"message": "Welcome to FastAPI Service", "docs": "/docs"}

