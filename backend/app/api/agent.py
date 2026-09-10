from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from app.agent.graph import graph

router = APIRouter(prefix="/agent", tags=["Agent"])


class AskRequest(BaseModel):
    question: str
    notebook_id: str


@router.post("/ask")
async def ask_agent(payload: AskRequest):
    """
    Main entry point for Flutter client to ask questions isolated to a notebook_id.
    """
    if not payload.question.strip() or not payload.notebook_id.strip():
        raise HTTPException(
            status_code=400,
            detail="question and notebook_id cannot be empty.",
        )

    initial_state = {
        "question": payload.question,
        "notebook_id": payload.notebook_id,
        "context": "",
        "has_relevant_context": False,
        "answer": "",
        "source_type": "general_knowledge",
    }

    try:
        result = graph.invoke(initial_state)
        return {
            "answer": result.get("answer", "No answer generated."),
            "source_type": result.get("source_type", "general_knowledge"),
            "has_relevant_context": result.get("has_relevant_context", False),
        }
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Agent execution failed: {str(e)}",
        )