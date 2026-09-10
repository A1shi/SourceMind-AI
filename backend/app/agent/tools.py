from langchain_core.tools import tool
from app.rag.vector_store import search_chunks

# Distance threshold: items with distance <= MAX_DISTANCE are considered relevant matches
MAX_DISTANCE = 1.2


@tool
def search_notebook_sources(question: str, notebook_id: str) -> str:
    """Searches uploaded notebook sources for relevant context to answer the user's query."""
    results = search_chunks(query=question, notebook_id=notebook_id, top_k=3)

    if not results:
        return (
            "NO_RELEVANT_SOURCES_FOUND: Answer the user's question using general knowledge, "
            "and explicitly inform them that the answer is derived from general knowledge "
            "rather than their uploaded sources."
        )

    # Filter retrieved chunks based on distance score relevance
    valid_chunks = [
        res for res in results
        if res.get("distance") is not None and res.get("distance") <= MAX_DISTANCE
    ]

    if not valid_chunks:
        return (
            "NO_RELEVANT_SOURCES_FOUND: Answer the user's question using general knowledge, "
            "and explicitly inform them that the answer is derived from general knowledge "
            "rather than their uploaded sources."
        )

    # Format context with source metadata for precise grounding
    context_parts = []
    for index, chunk in enumerate(valid_chunks, start=1):
        content = chunk.get("content", "").strip()
        metadata = chunk.get("metadata", {})
        source_name = metadata.get("source", "Unknown Document")
        chunk_idx = metadata.get("chunk_index", 0)

        context_parts.append(
            f"[Source {index}: {source_name} (Chunk {chunk_idx})]\n{content}"
        )

    context_str = "\n\n---\n\n".join(context_parts)
    return f"RELEVANT_CONTEXT:\n{context_str}"