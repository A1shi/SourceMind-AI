import time
import logging
from langgraph.graph import StateGraph, END, START
from app.agent.state import AgentState
from app.rag.vector_store import search_chunks
from google.generativeai import GenerativeModel
import google.api_core.exceptions

# Configure logger to monitor execution times in backend logs
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("sourcemind_agent")

def search_notebook_node(state: AgentState) -> AgentState:
    start_time = time.time()
    question = state["question"]
    notebook_id = state["notebook_id"]
    
    # Retrieve filtered chunks based on threshold
    docs = search_chunks(query=question, notebook_id=notebook_id)
    
    logger.info(f"[PERFORMANCE] ChromaDB search completed in {time.time() - start_time:.2f}s")
    
    if docs:
        context_str = "\n\n".join([d["content"] for d in docs])
        state["context"] = context_str
        state["has_relevant_context"] = True
    else:
        state["context"] = ""
        state["has_relevant_context"] = False
        
    return state

def route_question(state: AgentState) -> str:
    if state.get("has_relevant_context"):
        return "notebook_answer"
    return "general_answer"

def notebook_answer_node(state: AgentState) -> AgentState:
    start_time = time.time()
    prompt = f"Answer the question using ONLY the context provided below:\n\nContext:\n{state['context']}\n\nQuestion: {state['question']}"
    
    try:
        model = GenerativeModel("gemini-2.5-flash")
        response = model.generate_content(prompt)
        state["answer"] = response.text
        state["source_type"] = "uploaded_sources"
        logger.info(f"[PERFORMANCE] Gemini notebook answer generated in {time.time() - start_time:.2f}s")
    except google.api_core.exceptions.ResourceExhausted:
        logger.warning("[QUOTA] Gemini API rate limit reached (429 ResourceExhausted). Returning direct context snippet.")
        state["answer"] = f"Gemini quota exceeded. Here is the relevant snippet found in your notebook:\n\n{state['context']}"
        state["source_type"] = "uploaded_sources"
    except Exception as e:
        logger.error(f"[ERROR] Notebook answer generation failed: {str(e)}")
        state["answer"] = f"Error processing request: {str(e)}"
        state["source_type"] = "error"
        
    return state

def general_answer_node(state: AgentState) -> AgentState:
    start_time = time.time()
    prompt = f"Notice: No relevant information was found in your uploaded documents or sources.\n\nQuestion: {state['question']}"
    
    try:
        model = GenerativeModel("gemini-2.5-flash")
        response = model.generate_content(prompt)
        state["answer"] = f"*(Note: This answer comes from general knowledge as no relevant info was found in your sources)*\n\n{response.text}"
        state["source_type"] = "general_knowledge"
        logger.info(f"[PERFORMANCE] Gemini general answer generated in {time.time() - start_time:.2f}s")
    except google.api_core.exceptions.ResourceExhausted:
        logger.warning("[QUOTA] Gemini API rate limit reached (429 ResourceExhausted).")
        state["answer"] = "The AI service is temporarily unavailable due to rate limits, and no matching context was found in your active notebook."
        state["source_type"] = "error"
    except Exception as e:
        logger.error(f"[ERROR] General answer generation failed: {str(e)}")
        state["answer"] = "Unable to process query at this time."
        state["source_type"] = "error"
        
    return state

# Graph Setup
workflow = StateGraph(AgentState)
workflow.add_node("search_notebook", search_notebook_node)
workflow.add_node("notebook_answer", notebook_answer_node)
workflow.add_node("general_answer", general_answer_node)

workflow.add_edge(START, "search_notebook")
workflow.add_conditional_edges("search_notebook", route_question)
workflow.add_edge("notebook_answer", END)
workflow.add_edge("general_answer", END)

graph = workflow.compile()