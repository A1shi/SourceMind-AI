import os
import re
import tempfile

from fastapi import APIRouter, File, HTTPException, UploadFile
from pydantic import BaseModel

from app.rag.ingestion import extract_text, clean_text, chunk_text
from app.rag.embeddings import embed_document
from app.rag.vector_store import add_chunks

router = APIRouter(prefix="/documents", tags=["Documents"])


class NoteRequest(BaseModel):
    title: str
    content: str
    notebook_id: str


@router.post("/upload")
async def upload_document(
    notebook_id: str,
    file: UploadFile = File(...),
):
    """
    Upload a PDF or TXT document and process it into chunks.
    """

    if not file.filename:
        raise HTTPException(
            status_code=400,
            detail="No file selected.",
        )

    extension = os.path.splitext(file.filename)[1].lower()

    if extension not in [".pdf", ".txt"]:
        raise HTTPException(
            status_code=400,
            detail="Only PDF and TXT files are supported.",
        )

    try:
        file_bytes = await file.read()

        with tempfile.NamedTemporaryFile(
            delete=False,
            suffix=extension,
        ) as temp_file:
            temp_file.write(file_bytes)
            temp_path = temp_file.name

        try:
            text = extract_text(temp_path)
            text = clean_text(text)

            if not text:
                raise HTTPException(
                    status_code=400,
                    detail="Could not extract any text from the document.",
                )

            chunks = chunk_text(text)
            if not chunks:
                raise HTTPException(
                    status_code=400,
                    detail="No usable text chunks were created.",
                )

            embeddings = [
                embed_document(chunk)
                for chunk in chunks
            ]

            add_chunks(
                chunks=chunks,
                embeddings=embeddings,
                source_name=file.filename,
                notebook_id=notebook_id,
            )

            return {
                "notebook_id": notebook_id,
                "filename": file.filename,
                "characters": len(text),
                "chunks": len(chunks),
                "embedded": len(embeddings),
                "message": "Document indexed successfully.",
                "preview": chunks[:2],
            }

        finally:
            if os.path.exists(temp_path):
                os.remove(temp_path)

    except HTTPException:
        raise

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Document processing failed: {str(e)}",
        )


@router.post("/notes")
async def save_note(payload: NoteRequest):
    """
    Process and index user-created textual notes into ChromaDB.
    """
    if not payload.content.strip() or not payload.notebook_id.strip():
        raise HTTPException(
            status_code=400,
            detail="Content and notebook_id cannot be empty.",
        )

    try:
        cleaned_text = clean_text(payload.content)
        chunks = chunk_text(cleaned_text)

        if not chunks:
            raise HTTPException(
                status_code=400,
                detail="Note content was empty or unparseable.",
            )

        embeddings = [embed_document(chunk) for chunk in chunks]
        
        # Sanitize title to create a clean identifier for ChromaDB metadata
        sanitized_title = re.sub(r'[^\w\s-]', '', payload.title.strip()).replace(' ', '_')
        source_name = f"Note: {payload.title.strip()}" if payload.title.strip() else f"note_{sanitized_title}"

        add_chunks(
            chunks=chunks,
            embeddings=embeddings,
            source_name=source_name,
            notebook_id=payload.notebook_id,
        )

        return {
            "notebook_id": payload.notebook_id,
            "title": payload.title,
            "chunks": len(chunks),
            "embedded": len(embeddings),
            "message": "Note indexed successfully.",
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Note processing failed: {str(e)}",
        )