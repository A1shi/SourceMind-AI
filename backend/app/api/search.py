from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.rag.vector_store import search_chunks


router = APIRouter(
    prefix="/search",
    tags=["Search"],
)

# Distance threshold: items with distance <= MAX_DISTANCE are considered relevant matches
MAX_DISTANCE = 1.2


class SearchRequest(BaseModel):
    query: str
    notebook_id: str
    top_k: int = 4


@router.post("")
def search(request: SearchRequest):
    query = request.query.strip()
    notebook_id = request.notebook_id.strip()

    if not query:
        raise HTTPException(
            status_code=400,
            detail="Search query cannot be empty.",
        )

    if not notebook_id:
        raise HTTPException(
            status_code=400,
            detail="Notebook ID cannot be empty.",
        )

    # Directly pass raw query string and notebook_id to ChromaDB vector search
    results = search_chunks(
        query=query,
        notebook_id=notebook_id,
        top_k=request.top_k,
    )

    matches = []
    if results:
        for item in results:
            dist = item.get("distance")
            
            # Filter out chunks that exceed the maximum distance threshold
            if dist is not None and dist <= MAX_DISTANCE:
                metadata = item.get("metadata", {})
                matches.append(
                    {
                        "text": item.get("content"),
                        "source": metadata.get("source", "Unknown Source"),
                        "chunk_index": metadata.get("chunk_index", 0),
                        "distance": dist,
                    }
                )

    return {
        "query": query,
        "notebook_id": notebook_id,
        "has_matches": len(matches) > 0,
        "total_results": len(matches),
        "results": matches,
    }