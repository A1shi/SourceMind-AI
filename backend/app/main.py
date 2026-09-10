from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.documents import router as documents_router
from app.api.search import router as search_router
from app.api import agent

app = FastAPI(
    title="SourceMindAI API",
    description="Agentic RAG backend for SourceMindAI",
    version="1.0.0",
)

# Enable CORS for Flutter mobile/web client requests
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Adjust in production to restrict origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Active Routers
app.include_router(documents_router)
app.include_router(search_router)
app.include_router(agent.router)

# Note: ask_router is intentionally omitted to avoid 
# route conflicts with the main agent execution pipeline (/agent/ask)

@app.get("/")
def root():
    return {
        "message": "SourceMindAI backend is running",
        "status": "ok",
    }


@app.get("/health")
def health():
    return {
        "status": "healthy",
    }