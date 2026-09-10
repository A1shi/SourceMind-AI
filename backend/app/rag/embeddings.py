import os
from typing import List
from dotenv import load_dotenv
from google import genai
from google.genai import types

load_dotenv()

API_KEY = os.getenv("GEMINI_API_KEY")

if not API_KEY:
    raise RuntimeError("GEMINI_API_KEY is not configured.")

client = genai.Client(api_key=API_KEY)

# Use text-embedding-004 as the default Gemini Developer API text embedding model
EMBEDDING_MODEL = "text-embedding-004"


def embed_document(text: str) -> List[float]:
    """Create a 768-dimensional vector embedding for a document chunk."""
    if not text or not text.strip():
        return []

    response = client.models.embed_content(
        model=EMBEDDING_MODEL,
        contents=text.strip(),
        config=types.EmbedContentConfig(
            task_type="RETRIEVAL_DOCUMENT",
            output_dimensionality=768,
        ),
    )

    if response.embeddings and len(response.embeddings) > 0:
        return response.embeddings[0].values
    return []


def embed_query(text: str) -> List[float]:
    """Create a 768-dimensional vector embedding for a user search query."""
    if not text or not text.strip():
        return []

    response = client.models.embed_content(
        model=EMBEDDING_MODEL,
        contents=text.strip(),
        config=types.EmbedContentConfig(
            task_type="RETRIEVAL_QUERY",
            output_dimensionality=768,
        ),
    )

    if response.embeddings and len(response.embeddings) > 0:
        return response.embeddings[0].values
    return []


def get_embedding(text: str) -> List[float]:
    """Alias function to generate query embeddings for search modules."""
    return embed_query(text)