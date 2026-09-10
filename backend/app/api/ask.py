import os
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from dotenv import load_dotenv
from google import genai

from app.rag.vector_store import search_chunks

load_dotenv()

router = APIRouter(
    prefix="/ask",
    tags=["RAG"],
)

API_KEY = os.getenv("GEMINI_API_KEY")

if not API_KEY:
    raise RuntimeError("GEMINI_API_KEY is not configured.")

client = genai.Client(api_key=API_KEY)

MODEL = "gemini-2.5-flash"

# Adjust distance threshold according to your distance metric.
# For L2/Euclidean distance in ChromaDB, lower values mean closer matches.
# Items with distance <= MAX_DISTANCE are considered relevant.
MAX_DISTANCE = 1.2


class AskRequest(BaseModel):
    question: str
    notebook_id: str
    top_k: int = 3


@router.post("")
def ask_question(request: AskRequest):
    question = request.question.strip()
    notebook_id = request.notebook_id.strip()

    if not question:
        raise HTTPException(
            status_code=400,
            detail="Question cannot be empty.",
        )

    if not notebook_id:
        raise HTTPException(
            status_code=400,
            detail="Notebook ID cannot be empty.",
        )

    # 1. Retrieve relevant chunks directly from ChromaDB
    results = search_chunks(
        query=question,
        notebook_id=notebook_id,
        top_k=request.top_k,
    )

    # 2. Filter retrieved chunks based on distance score relevance
    valid_results = [
        item for item in results 
        if item.get("distance") is not None and item.get("distance") <= MAX_DISTANCE
    ] if results else []

    # 3. Choose path: Grounded Source Mode vs General Knowledge Fallback Mode
    if valid_results:
        context_parts = []
        sources = []

        for index, item in enumerate(valid_results, start=1):
            content = item.get("content", "")
            metadata = item.get("metadata", {})
            source = metadata.get("source", "Unknown source")
            chunk_index = metadata.get("chunk_index", 0)

            context_parts.append(
                f"[Source {index}: {source}, chunk {chunk_index}]\n{content}"
            )

            sources.append({
                "source": source,
                "chunk_index": chunk_index,
                "distance": item.get("distance"),
            })

        context = "\n\n".join(context_parts)

        prompt = f"""
You are SourceMindAI.

Answer the user's question using ONLY the provided context below.

Rules:
- Rely strictly on the context provided.
- Do not make up information that isn't supported by the context.
- Keep the answer helpful and clear.

USER QUESTION:
{question}

RETRIEVED CONTEXT:
{context}
"""
        source_type = "uploaded_sources"
    else:
        # Fallback path when no relevant document chunks exist
        prompt = f"""
You are SourceMindAI.

The user asked a question, but no relevant information was found in their uploaded documents or sources.

Rules:
- Answer the user's question accurately using your general knowledge.
- Begin your response with a brief notice stating that the answer comes from general knowledge because it was not found in their uploaded sources.

USER QUESTION:
{question}
"""
        sources = []
        source_type = "general_knowledge"

    # 4. Generate answer using Gemini
    try:
        response = client.models.generate_content(
            model=MODEL,
            contents=prompt,
        )
        answer = response.text or "I could not generate an answer."
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Error generating answer from LLM: {str(e)}",
        )

    # 5. Return structured response including source indicator
    return {
        "question": question,
        "answer": answer,
        "source_type": source_type,
        "sources": sources,
    }