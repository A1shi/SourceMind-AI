import re
from typing import List, Dict, Any
import chromadb
from app.rag.embeddings import embed_query

# Initialize Persistent ChromaDB client
client = chromadb.PersistentClient(path="./chroma_db")

# Explicitly configure collection to use Cosine Distance
collection = client.get_or_create_collection(
    name="sourcemind_collection",
    metadata={"hnsw:space": "cosine"}
)

# Cosine distance threshold: 0.0 = exact match, 0.45-0.50 = good conceptual match
DISTANCE_THRESHOLD = 0.50


def add_chunks(
    chunks: List[str],
    embeddings: List[List[float]],
    source_name: str,
    notebook_id: str,
) -> None:
    """
    Inserts or updates chunked text, embeddings, and metadata into ChromaDB.
    """
    documents = []
    ids = []
    metadatas = []

    # Clean source_name for safe ID formatting
    safe_source = re.sub(r"[^\w\s-]", "", source_name).replace(" ", "_")

    for index, (chunk, embedding) in enumerate(zip(chunks, embeddings)):
        chunk_id = f"{notebook_id}_{safe_source}_{index}"
        documents.append(chunk)
        ids.append(chunk_id)
        metadatas.append(
            {
                "source": source_name,
                "chunk_index": index,
                "notebook_id": notebook_id,
            }
        )

    # Use upsert to safely insert or update existing IDs without throwing duplicate errors
    collection.upsert(
        ids=ids,
        embeddings=embeddings,
        documents=documents,
        metadatas=metadatas,
    )


def search_chunks(query: str, notebook_id: str, top_k: int = 4) -> List[Dict[str, Any]]:
    """
    Queries ChromaDB filtered by notebook_id and distance threshold.
    """
    if not query.strip():
        return []

    query_embedding = embed_query(query)

    if not query_embedding:
        return []

    results = collection.query(
        query_embeddings=[query_embedding],
        n_results=top_k,
        where={"notebook_id": notebook_id},
    )

    relevant_docs = []
    if results and results.get("documents") and len(results["documents"][0]) > 0:
        documents = results["documents"][0]
        metadatas = results["metadatas"][0]
        distances = results["distances"][0]

        for doc, meta, dist in zip(documents, metadatas, distances):
            if dist <= DISTANCE_THRESHOLD:
                relevant_docs.append(
                    {
                        "content": doc,
                        "metadata": meta,
                        "distance": dist,
                    }
                )

    return relevant_docs