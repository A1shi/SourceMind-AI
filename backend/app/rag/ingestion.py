import os
import re
from typing import List
from pypdf import PdfReader

from app.rag.embeddings import embed_document
from app.rag.vector_store import collection


def extract_text(file_path: str) -> str:
    """Extract text from PDF or TXT files."""
    ext = os.path.splitext(file_path)[1].lower()

    if ext == ".pdf":
        reader = PdfReader(file_path)
        text = ""
        for page in reader.pages:
            extracted = page.extract_text()
            if extracted:
                text += extracted + "\n"
        return text

    elif ext == ".txt":
        with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
            return f.read()

    return ""


def clean_text(text: str) -> str:
    """Clean excess whitespace, newlines, and non-printable characters."""
    if not text:
        return ""
    # Collapse multiple whitespaces and newlines into single space
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def chunk_text(text: str, chunk_size: int = 500, overlap: int = 50) -> List[str]:
    """
    Split text into chunks with word boundary preservation and overlap.
    """
    if not text or not text.strip():
        return []

    words = text.split(" ")
    chunks = []
    current_chunk = []
    current_length = 0

    for word in words:
        current_chunk.append(word)
        current_length += len(word) + 1

        if current_length >= chunk_size:
            chunks.append(" ".join(current_chunk))
            
            # Retain overlapping words for the next chunk context
            overlap_words = []
            overlap_len = 0
            for w in reversed(current_chunk):
                if overlap_len + len(w) + 1 <= overlap:
                    overlap_words.insert(0, w)
                    overlap_len += len(w) + 1
                else:
                    break
            current_chunk = overlap_words
            current_length = overlap_len

    if current_chunk:
        chunks.append(" ".join(current_chunk))

    return chunks


def process_and_store_text(text: str, source_name: str, notebook_id: str, chunk_size: int = 500) -> None:
    """
    Clean, chunk, embed, and store textual notes or documents directly into ChromaDB.
    """
    cleaned = clean_text(text)
    chunks = chunk_text(cleaned, chunk_size=chunk_size)

    if not chunks:
        return

    documents = []
    embeddings = []
    metadatas = []
    ids = []

    # Clean source_name for safe ID string creation
    safe_source = re.sub(r"[^\w\s-]", "", source_name).replace(" ", "_")

    for index, chunk in enumerate(chunks):
        # Use embed_document for indexing content
        embedding = embed_document(chunk)
        
        # Guard against empty embeddings
        if not embedding:
            continue

        chunk_id = f"{notebook_id}_{safe_source}_{index}"

        documents.append(chunk)
        embeddings.append(embedding)
        metadatas.append({
            "source": source_name,
            "chunk_index": index,
            "notebook_id": notebook_id,
            "type": "note" if source_name.lower().startswith("note") else "document"
        })
        ids.append(chunk_id)

    if ids:
        collection.add(
            documents=documents,
            embeddings=embeddings,
            metadatas=metadatas,
            ids=ids
        )