

````markdown
# 🧠 SourceMindAI

> An AI-powered notebook and document assistant built with Flutter, FastAPI, LangGraph, Gemini, and ChromaDB.

SourceMindAI allows users to create notebooks, write notes, upload documents, and ask questions about their knowledge base. The application uses an **Agentic RAG (Retrieval-Augmented Generation)** architecture to determine whether an answer can be found in the user's uploaded sources.

If relevant information is found, SourceMindAI answers using the user's sources. If no relevant information is found, the system falls back to Gemini's general knowledge.

---

## ✨ Features

### 📚 AI-Powered Notebook

Create separate notebooks to organize your knowledge.

Each notebook can contain:

- Notes
- Uploaded PDF documents
- TXT documents
- AI-generated answers
- Summaries
- Quizzes

Each notebook has its own isolated `notebook_id`, ensuring that searches are performed within the correct knowledge base.

---

### 📝 Smart Notes

Create and save notes directly inside the application.

When a note is saved:

```text
Note
 ↓
Text Cleaning
 ↓
Chunking
 ↓
Gemini Embedding
 ↓
ChromaDB
````

Notes are automatically converted into embeddings and stored in the vector database for semantic search.

---

### 📄 PDF & TXT Upload

Upload supported documents directly into a notebook.

Supported formats:

* PDF
* TXT

The backend automatically:

1. Extracts text
2. Cleans the content
3. Splits it into chunks
4. Generates embeddings
5. Stores the chunks in ChromaDB

---

### 🔎 Semantic Search

SourceMindAI uses vector similarity search instead of relying only on keyword matching.

When a user asks a question:

```text
User Question
      ↓
Query Embedding
      ↓
ChromaDB Semantic Search
      ↓
Relevant Chunks
```

The search is scoped to the selected notebook.

---

### 🤖 Agentic RAG

The core feature of SourceMindAI is its Agentic RAG workflow.

The system first searches the user's uploaded sources.

```text
                    User Question
                         ↓
                  ChromaDB Search
                         ↓
              Relevant Context Found?
                    ↙           ↘
                  YES            NO
                   ↓              ↓
            Source-based       Gemini AI
              Answer          General Answer
```

#### When relevant information exists

The AI answers using the retrieved notebook context.

Response:

```json
{
  "source_type": "uploaded_sources",
  "has_relevant_context": true
}
```

#### When no relevant information exists

The system asks Gemini to answer using general knowledge.

Response:

```json
{
  "source_type": "general_knowledge",
  "has_relevant_context": false
}
```

This prevents the application from pretending that information came from the user's documents when it did not.

---

### 🧠 Context-Grounded Answers

When relevant source material is found, the AI is instructed to answer using the retrieved context.

This helps keep answers grounded in the user's uploaded knowledge.

Example:

```text
Uploaded Note:
"Machine Learning is a subset of Artificial Intelligence..."

Question:
"What is Machine Learning?"

↓

Answer:
"Machine Learning is a subset of Artificial Intelligence..."
```

---

### 📑 AI Notebook Summaries

SourceMindAI can generate a summary of notebook content.

The application sends a summary request through the backend agent, which retrieves relevant notebook information before generating the response.

---

### 🧪 AI-Generated Quizzes

Generate study questions from notebook content.

The quiz system is designed around:

* Multiple-choice questions
* Four answer options
* Correct answers
* Explanations
* Score tracking
* Question-by-question navigation

This makes the application useful not only for storing information but also for studying it.

---

### 🔐 Notebook Isolation

Each notebook has a unique identifier.

The backend uses:

```text
notebook_id
```

when storing and searching documents.

This means a search in one notebook does not accidentally retrieve information from another notebook.

---

### 📱 Flutter Application

The frontend is built with Flutter and provides a mobile interface for:

* Notebook management
* Notes
* Document uploads
* AI chat
* Search
* Summaries
* Quizzes

The Flutter application communicates with the backend through REST APIs.

---

# 🏗️ Architecture

```text
┌─────────────────────────────┐
│        Flutter App          │
│                             │
│  Notebooks                  │
│  Notes                      │
│  Documents                  │
│  AI Chat                    │
│  Summary                    │
│  Quiz                       │
└──────────────┬──────────────┘
               │
               │ REST API
               ▼
┌─────────────────────────────┐
│       FastAPI Backend       │
│                             │
│  /documents                 │
│  /search                    │
│  /agent/ask                 │
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│        LangGraph            │
│                             │
│  Search Notebook            │
│        ↓                    │
│  Relevant Context?          │
│      ↙       ↘              │
│    YES        NO             │
│     ↓          ↓            │
│  RAG Answer   AI Answer     │
└─────────┬───────────┬───────┘
          │           │
          ▼           ▼
   ┌────────────┐  ┌────────────┐
   │ ChromaDB   │  │   Gemini   │
   │            │  │            │
   │ Vectors    │  │ LLM        │
   │ Metadata   │  │ Generation │
   └────────────┘  └────────────┘
```

---

# 🔄 RAG Pipeline

## Document Ingestion

```text
PDF / TXT / Note
       ↓
Text Extraction
       ↓
Text Cleaning
       ↓
Chunking
       ↓
Gemini Embeddings
       ↓
ChromaDB
```

## Question Answering

```text
User Question
       ↓
Query Embedding
       ↓
ChromaDB Search
       ↓
Notebook Filtering
       ↓
Distance Threshold
       ↓
Relevant Context
       ↓
LangGraph Routing
       ↓
Gemini
       ↓
Answer
```

---

# 🛠️ Tech Stack

## Frontend

* Flutter
* Dart
* Material UI
* HTTP REST API
* Shared Preferences
* File Picker
* Syncfusion PDF

## Backend

* Python
* FastAPI
* Pydantic
* Uvicorn
* Python-dotenv

## AI / LLM

* Google Gemini
* Gemini 2.5 Flash
* Gemini Embeddings
* LangGraph
* LangChain

## Vector Database

* ChromaDB
* Cosine similarity
* Metadata filtering
* Notebook-scoped retrieval

## Document Processing

* PyPDF
* Text chunking
* Text cleaning

---

# 📂 Project Structure

```text
SourceMind-AI/
│
├── backend/
│   │
│   ├── app/
│   │   ├── api/
│   │   │   ├── agent.py
│   │   │   ├── documents.py
│   │   │   └── search.py
│   │   │
│   │   ├── agent/
│   │   │   ├── graph.py
│   │   │   └── state.py
│   │   │
│   │   ├── rag/
│   │   │   ├── embeddings.py
│   │   │   ├── ingestion.py
│   │   │   └── vector_store.py
│   │   │
│   │   └── main.py
│   │
│   ├── requirements.txt
│   └── .env
│
├── lib/
│   ├── main.dart
│   │
│   └── services/
│       └── api_services.dart
│
├── android/
├── ios/
├── web/
├── pubspec.yaml
└── README.md
```

---

# 🔌 API Endpoints

## Health Check

```http
GET /health
```

Response:

```json
{
  "status": "healthy"
}
```

---

## Save Note

```http
POST /documents/notes
```

Example:

```json
{
  "title": "AI Notes",
  "content": "Machine Learning is a subset of Artificial Intelligence.",
  "notebook_id": "test_notebook"
}
```

---

## Upload Document

```http
POST /documents/upload
```

Supported:

```text
PDF
TXT
```

---

## Search Notebook

```http
POST /search
```

Example:

```json
{
  "query": "What is machine learning?",
  "notebook_id": "test_notebook",
  "top_k": 4
}
```

---

## Ask AI Agent

```http
POST /agent/ask
```

Example:

```json
{
  "question": "What is machine learning?",
  "notebook_id": "test_notebook"
}
```

Possible response:

```json
{
  "answer": "Machine Learning is a subset of Artificial Intelligence...",
  "source_type": "uploaded_sources",
  "has_relevant_context": true
}
```

Or when no relevant source exists:

```json
{
  "answer": "The capital of France is Paris.",
  "source_type": "general_knowledge",
  "has_relevant_context": false
}
```

---

# ⚙️ Backend Setup

## 1. Clone the repository

```bash
git clone https://github.com/A1shi/SourceMind-AI.git
cd SourceMind-AI
```

---

## 2. Create a Python virtual environment

```bash
python -m venv .venv
```

Activate it on Windows:

```powershell
.\.venv\Scripts\Activate.ps1
```

---

## 3. Install dependencies

```bash
pip install -r backend/requirements.txt
```

---

## 4. Configure environment variables

Create:

```text
backend/.env
```

Add:

```env
GEMINI_API_KEY=your_gemini_api_key
```

---

## 5. Start FastAPI

From the `backend` directory:

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Backend:

```text
http://127.0.0.1:8000
```

Health check:

```text
http://127.0.0.1:8000/health
```

---

# 📱 Flutter Setup

Install Flutter dependencies:

```bash
flutter pub get
```

Run the application:

```bash
flutter run
```

For a physical Android device, make sure the phone and development computer are connected to the same network and configure the backend URL in:

```text
lib/services/api_services.dart
```

Example:

```dart
static String get baseUrl {
  return "http://YOUR_COMPUTER_IP:8000";
}
```

---

# 🧪 Testing

The RAG pipeline can be tested using the FastAPI Swagger interface:

```text
http://127.0.0.1:8000/docs
```

### Source-based test

Add:

```text
Machine Learning is a subset of Artificial Intelligence.
```

Then ask:

```text
What is Machine Learning?
```

Expected:

```json
{
  "source_type": "uploaded_sources",
  "has_relevant_context": true
}
```

### General knowledge test

Ask:

```text
What is the capital of France?
```

If the notebook does not contain relevant information, expected:

```json
{
  "source_type": "general_knowledge",
  "has_relevant_context": false
}
```

---

# 🔒 Security

The Gemini API key is kept on the backend rather than inside the Flutter application.

```text
Flutter
   ↓
FastAPI
   ↓
Gemini API
```

The Flutter application does not directly communicate with Gemini.

---

# 🚀 Future Improvements

Potential improvements include:

* Streaming AI responses
* Conversation history
* More document formats
* Better source citations
* Page-level PDF citations
* Advanced reranking
* Hybrid keyword + vector search
* User authentication
* Cloud-hosted vector database
* Persistent cloud storage
* Multi-user notebooks
* More advanced agent tools
* Production deployment

---

# 🎯 Project Goal

SourceMindAI is designed to combine **personal knowledge management with AI-powered retrieval and reasoning**.

Instead of simply sending every question directly to an LLM, the application first checks the user's own knowledge base and uses that information when available.

This creates a workflow where:

```text
Your Knowledge
      +
Semantic Search
      +
Agentic RAG
      +
Generative AI
      =
SourceMindAI
```

---

# 👩‍💻 Author

**Aashi Gupta**

Built with Flutter, Python, FastAPI, LangGraph, ChromaDB, and Google Gemini.

---

## ⭐ If you find this project useful

Consider giving the repository a ⭐ on GitHub.

```
clearly exposes your **RAG pipeline, vector database, LangGraph workflow, APIs, document ingestion, and fallback architecture**.
```
