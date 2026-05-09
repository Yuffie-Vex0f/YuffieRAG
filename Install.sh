#!/usr/bin/env bash
# ============================================================
# local-doc-qa 项目自安装脚本
# 用法：
#   1. 把本脚本放到一个空目录里（或你的项目根目录）
#   2. bash install.sh
#   3. 脚本会在当前目录展开完整项目结构
# ============================================================
set -e

echo "==> 正在展开项目文件到当前目录: $(pwd)"

cat > '.env.example' << '__FILE_END_MARKER__'
# LLM API 配置（三选一）
# 方式1：通义千问（推荐，有免费额度）
DASHSCOPE_API_KEY=your_dashscope_api_key_here

# 方式2：OpenAI
# OPENAI_API_KEY=your_openai_api_key_here
# OPENAI_BASE_URL=https://api.openai.com/v1

# 方式3：本地 Ollama（完全免费，需本地安装）
# OLLAMA_BASE_URL=http://localhost:11434

# LLM 提供商选择: dashscope | openai | ollama
LLM_PROVIDER=dashscope
LLM_MODEL=qwen-turbo

# Embedding 配置
# local: 本地 sentence-transformers（无需 API，首次下载模型约 400MB）
# openai: 使用 OpenAI Embedding API
EMBEDDING_PROVIDER=local
EMBEDDING_MODEL=shibing624/text2vec-base-chinese

# 数据存储路径
UPLOAD_DIR=./uploads
CHROMA_DIR=./.chroma
SQLITE_URL=sqlite+aiosqlite:///./rag.db

# 分块配置
CHUNK_SIZE=500
CHUNK_OVERLAP=50
TOP_K=5
__FILE_END_MARKER__
echo "  ✓ .env.example"

cat > '.gitignore' << '__FILE_END_MARKER__'
.env
__pycache__/
*.pyc
*.pyo
.chroma/
uploads/
rag.db
node_modules/
frontend/dist/
.DS_Store
*.egg-info/
.venv/
__FILE_END_MARKER__
echo "  ✓ .gitignore"

cat > 'Dockerfile' << '__FILE_END_MARKER__'
# =========================================================
# Stage 1: 构建前端（Vite 产出 frontend/dist）
# =========================================================
FROM node:20-alpine AS frontend-build

WORKDIR /build

# 先只拷依赖描述文件，利用 Docker 层缓存：
# 只要 package.json 没变，npm install 就走缓存
COPY frontend/package.json ./
# 如果你有 package-lock.json，把下一行注释打开
# COPY frontend/package-lock.json ./

RUN npm install

# 再拷其余前端源码，触发实际构建
COPY frontend/ ./

RUN npm run build
# 此时构建产物在 /build/dist/，里面是带 hash 的 bundle，
# index.html 已经被 Vite 改写成引用 /assets/xxx.js


# =========================================================
# Stage 2: Python 后端运行时
# =========================================================
FROM python:3.11-slim AS runtime

WORKDIR /app

# 系统依赖（编译某些 Python 包要用到）
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc libffi-dev \
    && rm -rf /var/lib/apt/lists/*

# 先装 Python 依赖（同样利用缓存）
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 拷后端代码
COPY backend/ ./backend/

# 关键一步：把 stage 1 构建好的 dist 拷到 backend/main.py 期望的位置
# main.py 里读的是 Path("frontend/dist")，所以这里就放在 /app/frontend/dist
COPY --from=frontend-build /build/dist ./frontend/dist

EXPOSE 8000

CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8000"]
__FILE_END_MARKER__
echo "  ✓ Dockerfile"

cat > 'README.md' << '__FILE_END_MARKER__'
# 本地文档问答助手

基于 RAG（检索增强生成）的本地文档 Q&A 系统。上传 PDF / DOCX / TXT，即可对话提问。

## 技术栈

| 层次 | 技术 |
|------|------|
| 后端框架 | Python 3.11 + FastAPI |
| RAG 框架 | LangChain |
| 向量数据库 | ChromaDB（本地） |
| Embedding | text2vec-base-chinese（本地）或 OpenAI |
| LLM | 通义千问 / OpenAI / Ollama |
| 前端 | React 18 + Vite |
| 元数据存储 | SQLite |

## 快速启动

### 方式一：本地开发（推荐调试用）

```bash
# 1. 复制环境变量
cp .env.example .env
# 编辑 .env，填入你的 API Key

# 2. 安装后端依赖
pip install -r requirements.txt

# 3. 启动后端
uvicorn backend.main:app --reload --port 8000

# 4. 新开终端，启动前端
cd frontend
npm install
npm run dev
# 浏览器访问 http://localhost:5173
```

### 方式二：Docker 一键启动

```bash
cp .env.example .env
# 编辑 .env 填入 API Key

docker compose up --build
# 浏览器访问 http://localhost:5173
```

## 项目结构

```
rag-doc-qa/
├── backend/
│   ├── main.py              # FastAPI 入口
│   ├── config.py            # 全局配置
│   ├── routers/
│   │   ├── upload.py        # 上传 & 文档管理接口
│   │   └── ask.py           # 问答接口（SSE 流式）
│   ├── rag/
│   │   ├── parser.py        # 文档解析 + 分块
│   │   ├── retriever.py     # 向量化 + 检索
│   │   └── llm.py           # LLM 调用 + Prompt 构造
│   └── db/
│       └── models.py        # SQLite 数据模型
├── frontend/
│   └── src/
│       ├── App.jsx           # 布局入口
│       ├── DocPanel.jsx      # 文档管理侧边栏
│       └── ChatPanel.jsx     # 对话面板（流式输出）
├── requirements.txt
├── docker-compose.yml
├── .env.example
└── README.md
```

## LLM 配置说明

在 `.env` 中设置 `LLM_PROVIDER`：

- `dashscope`：通义千问，注册阿里云获取 API Key（有免费额度）
- `openai`：OpenAI 或兼容 API
- `ollama`：本地模型，需先安装 [Ollama](https://ollama.ai) 并运行 `ollama pull qwen2`

## API 文档

启动后访问 http://localhost:8000/docs 查看 Swagger 文档。
__FILE_END_MARKER__
echo "  ✓ README.md"

mkdir -p "backend"
cat > 'backend/config.py' << '__FILE_END_MARKER__'
from pydantic_settings import BaseSettings
from pathlib import Path


class Settings(BaseSettings):
    dashscope_api_key: str = ""
    openai_api_key: str = ""
    openai_base_url: str = "https://api.openai.com/v1"
    ollama_base_url: str = "http://localhost:11434"

    llm_provider: str = "dashscope"
    llm_model: str = "qwen-turbo"

    embedding_provider: str = "local"
    embedding_model: str = "shibing624/text2vec-base-chinese"

    upload_dir: str = "./uploads"
    chroma_dir: str = "./.chroma"
    sqlite_url: str = "sqlite+aiosqlite:///./rag.db"

    chunk_size: int = 500
    chunk_overlap: int = 50
    top_k: int = 5

    class Config:
        env_file = ".env"
        extra = "ignore"

    def ensure_dirs(self):
        Path(self.upload_dir).mkdir(parents=True, exist_ok=True)
        Path(self.chroma_dir).mkdir(parents=True, exist_ok=True)


settings = Settings()
settings.ensure_dirs()
__FILE_END_MARKER__
echo "  ✓ backend/config.py"

mkdir -p "backend/db"
cat > 'backend/db/models.py' << '__FILE_END_MARKER__'
from sqlalchemy import Column, String, Integer, DateTime, Text, func
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import declarative_base, sessionmaker
from backend.config import settings

engine = create_async_engine(settings.sqlite_url, echo=False)
AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
Base = declarative_base()


class Document(Base):
    __tablename__ = "documents"
    id = Column(String, primary_key=True)          # uuid
    filename = Column(String, nullable=False)
    original_name = Column(String, nullable=False)
    file_type = Column(String, nullable=False)      # pdf | txt | docx
    chunk_count = Column(Integer, default=0)
    created_at = Column(DateTime, default=func.now())


class ChatHistory(Base):
    __tablename__ = "chat_history"
    id = Column(Integer, primary_key=True, autoincrement=True)
    session_id = Column(String, nullable=False, index=True)
    doc_id = Column(String, nullable=True)          # 关联文档（可为空=跨文档）
    role = Column(String, nullable=False)            # user | assistant
    content = Column(Text, nullable=False)
    sources = Column(Text, nullable=True)            # JSON 字符串：来源片段
    created_at = Column(DateTime, default=func.now())


async def init_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def get_db():
    async with AsyncSessionLocal() as session:
        yield session
__FILE_END_MARKER__
echo "  ✓ backend/db/models.py"

mkdir -p "backend"
cat > 'backend/main.py' << '__FILE_END_MARKER__'
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pathlib import Path

from backend.db.models import init_db
from backend.routers.upload import router as upload_router
from backend.routers.ask import router as ask_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield


app = FastAPI(
    title="本地文档问答助手",
    description="基于 RAG 的本地文档 Q&A 系统",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(upload_router)
app.include_router(ask_router)

# 如果 frontend/dist 存在，托管前端静态文件
dist_path = Path("frontend/dist")
if dist_path.exists():
    app.mount("/", StaticFiles(directory=str(dist_path), html=True), name="frontend")


@app.get("/health")
async def health():
    return {"status": "ok"}
__FILE_END_MARKER__
echo "  ✓ backend/main.py"

mkdir -p "backend/rag"
cat > 'backend/rag/llm.py' << '__FILE_END_MARKER__'
from functools import lru_cache
from typing import List, AsyncIterator
from langchain.schema import Document
from backend.config import settings


@lru_cache(maxsize=1)
def get_llm():
    """单例：根据配置加载对应的 LLM"""
    provider = settings.llm_provider

    if provider == "dashscope":
        from langchain_community.llms import Tongyi
        return Tongyi(
            model_name=settings.llm_model,
            dashscope_api_key=settings.dashscope_api_key,
            streaming=True,
        )
    elif provider == "openai":
        from langchain_openai import ChatOpenAI
        return ChatOpenAI(
            model=settings.llm_model,
            openai_api_key=settings.openai_api_key,
            base_url=settings.openai_base_url,
            streaming=True,
        )
    elif provider == "ollama":
        from langchain_community.llms import Ollama
        return Ollama(
            model=settings.llm_model,
            base_url=settings.ollama_base_url,
        )
    else:
        raise ValueError(f"未知的 LLM 提供商: {provider}")


def build_prompt(question: str, contexts: List[Document], history: List[dict]) -> str:
    """拼接 Prompt：历史对话 + 检索到的上下文 + 问题"""
    context_text = "\n\n---\n\n".join(
        f"[来源：第{doc.metadata.get('page', '?')}页]\n{doc.page_content}"
        for doc in contexts
    )

    history_text = ""
    for msg in history[-6:]:  # 最多保留最近 3 轮
        role = "用户" if msg["role"] == "user" else "助手"
        history_text += f"{role}：{msg['content']}\n"

    prompt = f"""你是一个专业的文档问答助手。请仅根据下方【参考文档】中的内容回答用户问题。
如果文档中没有相关信息，请明确说"文档中未找到相关信息"，不要编造内容。
回答时请注明信息来源（第几页）。

【参考文档】
{context_text}

【历史对话】
{history_text}
【当前问题】
用户：{question}

助手："""
    return prompt


async def generate_stream(prompt: str) -> AsyncIterator[str]:
    """流式生成回答"""
    llm = get_llm()
    async for chunk in llm.astream(prompt):
        if hasattr(chunk, "content"):
            yield chunk.content
        else:
            yield str(chunk)
__FILE_END_MARKER__
echo "  ✓ backend/rag/llm.py"

mkdir -p "backend/rag"
cat > 'backend/rag/parser.py' << '__FILE_END_MARKER__'
from pathlib import Path
from typing import List
from langchain.schema import Document
from langchain.text_splitter import RecursiveCharacterTextSplitter
from backend.config import settings


def parse_file(file_path: str) -> List[Document]:
    """解析文件，返回 LangChain Document 列表"""
    path = Path(file_path)
    suffix = path.suffix.lower()

    if suffix == ".pdf":
        return _parse_pdf(file_path)
    elif suffix == ".docx":
        return _parse_docx(file_path)
    elif suffix == ".txt":
        return _parse_txt(file_path)
    else:
        raise ValueError(f"不支持的文件类型: {suffix}")


def _parse_pdf(file_path: str) -> List[Document]:
    import fitz  # PyMuPDF
    docs = []
    pdf = fitz.open(file_path)
    for page_num, page in enumerate(pdf):
        text = page.get_text("text").strip()
        if text:
            docs.append(Document(
                page_content=text,
                metadata={"source": file_path, "page": page_num + 1}
            ))
    pdf.close()
    return docs


def _parse_docx(file_path: str) -> List[Document]:
    from docx import Document as DocxDocument
    doc = DocxDocument(file_path)
    full_text = "\n".join(p.text for p in doc.paragraphs if p.text.strip())
    return [Document(page_content=full_text, metadata={"source": file_path, "page": 1})]


def _parse_txt(file_path: str) -> List[Document]:
    text = Path(file_path).read_text(encoding="utf-8", errors="ignore")
    return [Document(page_content=text, metadata={"source": file_path, "page": 1})]


def split_documents(docs: List[Document]) -> List[Document]:
    """将文档切分为小块"""
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=settings.chunk_size,
        chunk_overlap=settings.chunk_overlap,
        separators=["\n\n", "\n", "。", "！", "？", ".", "!", "?", " ", ""],
    )
    return splitter.split_documents(docs)
__FILE_END_MARKER__
echo "  ✓ backend/rag/parser.py"

mkdir -p "backend/rag"
cat > 'backend/rag/retriever.py' << '__FILE_END_MARKER__'
from functools import lru_cache
from typing import List
from langchain.schema import Document
from langchain_community.vectorstores import Chroma
from backend.config import settings


@lru_cache(maxsize=1)
def get_embeddings():
    """单例：加载 Embedding 模型（本地或 API）"""
    if settings.embedding_provider == "local":
        from langchain_community.embeddings import HuggingFaceEmbeddings
        return HuggingFaceEmbeddings(
            model_name=settings.embedding_model,
            model_kwargs={"device": "cpu"},
            encode_kwargs={"normalize_embeddings": True},
        )
    else:
        from langchain_openai import OpenAIEmbeddings
        return OpenAIEmbeddings(
            model="text-embedding-3-small",
            openai_api_key=settings.openai_api_key,
            base_url=settings.openai_base_url,
        )


def get_vectorstore(collection_name: str = "default") -> Chroma:
    """获取 ChromaDB 集合"""
    return Chroma(
        collection_name=collection_name,
        embedding_function=get_embeddings(),
        persist_directory=settings.chroma_dir,
    )


def add_documents(chunks: List[Document], doc_id: str) -> int:
    """将分块写入向量库，返回写入数量"""
    for chunk in chunks:
        chunk.metadata["doc_id"] = doc_id

    vectorstore = get_vectorstore()
    vectorstore.add_documents(chunks)
    return len(chunks)


def retrieve(query: str, doc_id: str = None) -> List[Document]:
    """语义检索，可选限定某篇文档"""
    vectorstore = get_vectorstore()
    filter_dict = {"doc_id": doc_id} if doc_id else None
    results = vectorstore.similarity_search(
        query,
        k=settings.top_k,
        filter=filter_dict,
    )
    return results


def delete_document(doc_id: str):
    """从向量库删除指定文档的所有分块"""
    vectorstore = get_vectorstore()
    vectorstore.delete(where={"doc_id": doc_id})
__FILE_END_MARKER__
echo "  ✓ backend/rag/retriever.py"

mkdir -p "backend/routers"
cat > 'backend/routers/ask.py' << '__FILE_END_MARKER__'
import json
import uuid
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from typing import Optional

from backend.db.models import ChatHistory, get_db
from backend.rag.retriever import retrieve
from backend.rag.llm import build_prompt, generate_stream

router = APIRouter(prefix="/api/ask", tags=["ask"])


class AskRequest(BaseModel):
    question: str
    doc_id: Optional[str] = None       # 不传则跨所有文档检索
    session_id: Optional[str] = None   # 不传则新建会话


@router.post("/")
async def ask(req: AskRequest, db: AsyncSession = Depends(get_db)):
    """流式问答接口（SSE）"""
    if not req.question.strip():
        raise HTTPException(400, "问题不能为空")

    session_id = req.session_id or str(uuid.uuid4())

    # 获取历史对话
    result = await db.execute(
        select(ChatHistory)
        .where(ChatHistory.session_id == session_id)
        .order_by(ChatHistory.created_at.desc())
        .limit(10)
    )
    history_rows = list(reversed(result.scalars().all()))
    history = [{"role": r.role, "content": r.content} for r in history_rows]

    # 检索上下文
    contexts = retrieve(req.question, doc_id=req.doc_id)
    sources = [
        {
            "page": doc.metadata.get("page", "?"),
            "text": doc.page_content[:120] + "...",
        }
        for doc in contexts
    ]

    # 构造 Prompt
    prompt = build_prompt(req.question, contexts, history)

    # 保存用户消息
    user_msg = ChatHistory(
        session_id=session_id,
        doc_id=req.doc_id,
        role="user",
        content=req.question,
    )
    db.add(user_msg)
    await db.commit()

    async def event_stream():
        full_answer = ""
        # 先发 session_id 和 sources
        yield f"data: {json.dumps({'type': 'meta', 'session_id': session_id, 'sources': sources}, ensure_ascii=False)}\n\n"

        async for token in generate_stream(prompt):
            full_answer += token
            yield f"data: {json.dumps({'type': 'token', 'text': token}, ensure_ascii=False)}\n\n"

        yield f"data: {json.dumps({'type': 'done'})}\n\n"

        # 保存助手消息
        async with db.begin():
            db.add(ChatHistory(
                session_id=session_id,
                doc_id=req.doc_id,
                role="assistant",
                content=full_answer,
                sources=json.dumps(sources, ensure_ascii=False),
            ))

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


@router.get("/history/{session_id}")
async def get_history(session_id: str, db: AsyncSession = Depends(get_db)):
    """获取会话历史"""
    result = await db.execute(
        select(ChatHistory)
        .where(ChatHistory.session_id == session_id)
        .order_by(ChatHistory.created_at)
    )
    rows = result.scalars().all()
    return [
        {
            "role": r.role,
            "content": r.content,
            "sources": json.loads(r.sources) if r.sources else [],
            "created_at": r.created_at.isoformat() if r.created_at else None,
        }
        for r in rows
    ]
__FILE_END_MARKER__
echo "  ✓ backend/routers/ask.py"

mkdir -p "backend/routers"
cat > 'backend/routers/upload.py' << '__FILE_END_MARKER__'
import uuid
import shutil
from pathlib import Path
from fastapi import APIRouter, UploadFile, File, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete

from backend.db.models import Document, get_db
from backend.rag.parser import parse_file, split_documents
from backend.rag.retriever import add_documents, delete_document
from backend.config import settings

router = APIRouter(prefix="/api/documents", tags=["documents"])

ALLOWED_TYPES = {
    "application/pdf": ".pdf",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": ".docx",
    "text/plain": ".txt",
}


@router.post("/upload")
async def upload_document(
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
):
    """上传并索引文档"""
    # 校验类型
    content_type = file.content_type or ""
    suffix = ALLOWED_TYPES.get(content_type)
    if not suffix:
        # 兜底：从文件名判断
        name_suffix = Path(file.filename).suffix.lower()
        if name_suffix in (".pdf", ".txt", ".docx"):
            suffix = name_suffix
        else:
            raise HTTPException(400, "仅支持 PDF、DOCX、TXT 格式")

    doc_id = str(uuid.uuid4())
    save_name = f"{doc_id}{suffix}"
    save_path = Path(settings.upload_dir) / save_name

    # 保存文件
    with save_path.open("wb") as f:
        shutil.copyfileobj(file.file, f)

    # 解析 + 分块 + 向量化
    try:
        raw_docs = parse_file(str(save_path))
        chunks = split_documents(raw_docs)
        chunk_count = add_documents(chunks, doc_id)
    except Exception as e:
        save_path.unlink(missing_ok=True)
        raise HTTPException(500, f"文档处理失败：{e}")

    # 写入元数据
    doc = Document(
        id=doc_id,
        filename=save_name,
        original_name=file.filename,
        file_type=suffix.lstrip("."),
        chunk_count=chunk_count,
    )
    db.add(doc)
    await db.commit()

    return {
        "doc_id": doc_id,
        "original_name": file.filename,
        "chunk_count": chunk_count,
    }


@router.get("/")
async def list_documents(db: AsyncSession = Depends(get_db)):
    """获取文档列表"""
    result = await db.execute(select(Document).order_by(Document.created_at.desc()))
    docs = result.scalars().all()
    return [
        {
            "doc_id": d.id,
            "original_name": d.original_name,
            "file_type": d.file_type,
            "chunk_count": d.chunk_count,
            "created_at": d.created_at.isoformat() if d.created_at else None,
        }
        for d in docs
    ]


@router.delete("/{doc_id}")
async def remove_document(doc_id: str, db: AsyncSession = Depends(get_db)):
    """删除文档及其向量索引"""
    result = await db.execute(select(Document).where(Document.id == doc_id))
    doc = result.scalar_one_or_none()
    if not doc:
        raise HTTPException(404, "文档不存在")

    # 删除文件
    file_path = Path(settings.upload_dir) / doc.filename
    file_path.unlink(missing_ok=True)

    # 删除向量
    delete_document(doc_id)

    # 删除元数据
    await db.execute(delete(Document).where(Document.id == doc_id))
    await db.commit()
    return {"message": "删除成功"}
__FILE_END_MARKER__
echo "  ✓ backend/routers/upload.py"

cat > 'docker-compose.yml' << '__FILE_END_MARKER__'
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile     # 用上面的统一 Dockerfile
    container_name: local-doc-qa
    ports:
      - "8000:8000"
    volumes:
      # 持久化数据（不要挂 frontend/，避免覆盖镜像里构建好的 dist）
      - ./uploads:/app/uploads
      - ./.chroma:/app/.chroma
      - ./rag.db:/app/rag.db
    env_file:
      - .env
    restart: unless-stopped
__FILE_END_MARKER__
echo "  ✓ docker-compose.yml"

mkdir -p "frontend"
cat > 'frontend/index.html' << '__FILE_END_MARKER__'
<!DOCTYPE html>
<html lang="zh-CN">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>文档问答助手</title>
    <style>
      :root {
        /* —— 字体栈 ——
           西文优先 Inter / SF / Segoe，中文优先苹方 / 鸿蒙 / 微软雅黑，
           等宽数字走 SF Mono / JetBrains Mono / Menlo */
        --font-sans:
          -apple-system, BlinkMacSystemFont,
          "Inter", "Segoe UI", Roboto,
          "PingFang SC", "HarmonyOS Sans SC", "Microsoft YaHei",
          "Hiragino Sans GB", "Source Han Sans SC", "Noto Sans CJK SC",
          sans-serif;
        --font-mono:
          "SF Mono", "JetBrains Mono", "Fira Code", "Menlo",
          Consolas, "Liberation Mono", monospace;

        /* —— 文本配色（提高对比度，原 #888/#999/#bbb 偏灰）—— */
        --text-primary: #1a1a1f;
        --text-secondary: #5a5a66;
        --text-tertiary: #8a8a96;
        --text-placeholder: #b5b5c0;

        /* —— 主色（保留原配色基调）—— */
        --accent: #5b50d6;
        --accent-soft: #f1efff;
        --accent-border: #c7c2f5;

        --border: #e8e8ec;
        --border-soft: #f0f0f3;
        --bg: #f7f7fa;
        --bg-elevated: #ffffff;
      }

      *, *::before, *::after {
        box-sizing: border-box;
        margin: 0;
        padding: 0;
      }

      html { font-size: 16px; }

      body {
        font-family: var(--font-sans);
        font-size: 14px;
        line-height: 1.6;
        color: var(--text-primary);
        background: var(--bg);

        /* 字体平滑：HiDPI 屏幕下细化字形 */
        -webkit-font-smoothing: antialiased;
        -moz-osx-font-smoothing: grayscale;
        text-rendering: optimizeLegibility;

        /* 中英文混排时给汉字留一点呼吸感 */
        letter-spacing: 0.01em;

        /* 启用常用 OpenType 特性：kerning、连字、上下文替换 */
        font-feature-settings: "kern" 1, "liga" 1, "calt" 1;
      }

      /* —— 数字等宽：用于徽章、页码、计数 —— */
      .tnum {
        font-feature-settings: "tnum" 1;
        font-variant-numeric: tabular-nums;
      }

      /* —— 文本选区：用主题色而非默认蓝 —— */
      ::selection {
        background: var(--accent-soft);
        color: var(--accent);
      }

      /* —— 自定义滚动条：纤细、安静 —— */
      ::-webkit-scrollbar { width: 8px; height: 8px; }
      ::-webkit-scrollbar-track { background: transparent; }
      ::-webkit-scrollbar-thumb {
        background: rgba(0, 0, 0, 0.12);
        border-radius: 4px;
      }
      ::-webkit-scrollbar-thumb:hover { background: rgba(0, 0, 0, 0.22); }
      * {
        scrollbar-width: thin;
        scrollbar-color: rgba(0, 0, 0, 0.12) transparent;
      }

      /* —— 表单控件继承字体（原 textarea 走浏览器默认字）—— */
      button, input, textarea {
        font-family: inherit;
        font-feature-settings: inherit;
        letter-spacing: inherit;
        color: inherit;
      }

      ::placeholder {
        color: var(--text-placeholder);
        opacity: 1;
      }

      /* —— 多行省略工具类 —— */
      .clamp-2 {
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }

      /* —— 长 URL / 英文长串自动断行 —— */
      .wrap-anywhere {
        overflow-wrap: anywhere;
        word-break: break-word;
      }
    </style>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
__FILE_END_MARKER__
echo "  ✓ frontend/index.html"

mkdir -p "frontend"
cat > 'frontend/package.json' << '__FILE_END_MARKER__'
{
  "name": "rag-doc-qa-frontend",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^18.3.1",
    "react-dom": "^18.3.1"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.3.1",
    "vite": "^5.3.1"
  }
}
__FILE_END_MARKER__
echo "  ✓ frontend/package.json"

mkdir -p "frontend/src"
cat > 'frontend/src/App.jsx' << '__FILE_END_MARKER__'
import { useState, useEffect } from 'react'
import DocPanel from './DocPanel.jsx'
import ChatPanel from './ChatPanel.jsx'

const s = {
  app: { display: 'flex', height: '100vh', overflow: 'hidden' },
  sidebar: {
    width: 280,
    borderRight: '1px solid var(--border)',
    background: 'var(--bg-elevated)',
    display: 'flex', flexDirection: 'column', flexShrink: 0,
  },
  sidebarHeader: {
    padding: '18px 20px 14px',
    borderBottom: '1px solid var(--border-soft)',
    fontSize: 13,
    fontWeight: 600,
    letterSpacing: '0.04em',
    textTransform: 'uppercase',
    color: 'var(--text-tertiary)',
  },
  main: { flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' },
  mainHeader: {
    padding: '14px 24px',
    borderBottom: '1px solid var(--border)',
    background: 'var(--bg-elevated)',
    display: 'flex', flexDirection: 'column', gap: 2,
    minHeight: 60,
    justifyContent: 'center',
  },
  title: {
    fontSize: 15,
    fontWeight: 600,
    color: 'var(--text-primary)',
    lineHeight: 1.4,
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  subtitle: {
    fontSize: 12,
    color: 'var(--text-tertiary)',
    lineHeight: 1.4,
  },
}

export default function App() {
  const [docs, setDocs] = useState([])
  const [selectedDocId, setSelectedDocId] = useState(null)

  const fetchDocs = async () => {
    const res = await fetch('/api/documents/')
    if (res.ok) setDocs(await res.json())
  }

  useEffect(() => { fetchDocs() }, [])

  const currentDoc = docs.find(d => d.doc_id === selectedDocId)

  return (
    <div style={s.app}>
      <aside style={s.sidebar}>
        <div style={s.sidebarHeader}>文档库</div>
        <DocPanel
          docs={docs}
          selectedDocId={selectedDocId}
          onSelect={setSelectedDocId}
          onRefresh={fetchDocs}
        />
      </aside>
      <main style={s.main}>
        <div style={s.mainHeader}>
          <div style={s.title} title={currentDoc?.original_name}>
            {currentDoc ? currentDoc.original_name : '全文档问答'}
          </div>
          <div style={s.subtitle}>
            {currentDoc
              ? <>仅在该文档范围内检索 · <span className="tnum">{currentDoc.chunk_count}</span> 个文本块</>
              : '在所有已上传的文档中检索作答'}
          </div>
        </div>
        <ChatPanel docId={selectedDocId} key={selectedDocId ?? 'all'} />
      </main>
    </div>
  )
}
__FILE_END_MARKER__
echo "  ✓ frontend/src/App.jsx"

mkdir -p "frontend/src"
cat > 'frontend/src/ChatPanel.jsx' << '__FILE_END_MARKER__'
import { useState, useRef, useEffect } from 'react'

const s = {
  wrap: { flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' },
  messages: {
    flex: 1, overflow: 'auto',
    padding: '24px 28px',
    display: 'flex', flexDirection: 'column', gap: 20,
  },
  msgBlock: (role) => ({
    display: 'flex', flexDirection: 'column',
    alignItems: role === 'user' ? 'flex-end' : 'flex-start',
    gap: 6,
    maxWidth: '75%',
    alignSelf: role === 'user' ? 'flex-end' : 'flex-start',
  }),
  bubble: (role) => ({
    padding: '12px 16px',
    borderRadius: role === 'user' ? '14px 14px 4px 14px' : '14px 14px 14px 4px',
    fontSize: 14,
    /* 中文气泡用 1.75 行高，更松弛、更易读 */
    lineHeight: 1.75,
    /* 保留换行；长 URL/英文长串自动断行，避免撑破气泡 */
    whiteSpace: 'pre-wrap',
    overflowWrap: 'anywhere',
    wordBreak: 'break-word',
    background: role === 'user' ? 'var(--accent)' : 'var(--bg-elevated)',
    color: role === 'user' ? '#fff' : 'var(--text-primary)',
    border: role === 'user' ? 'none' : '1px solid var(--border)',
    boxShadow: role === 'assistant' ? '0 1px 2px rgba(0,0,0,0.02)' : 'none',
  }),
  caret: {
    display: 'inline-block',
    width: 2, height: '1em',
    background: 'currentColor',
    verticalAlign: '-2px',
    marginLeft: 1,
    animation: 'blink 1s steps(2, start) infinite',
  },
  sourcesWrap: {
    width: '100%',
    marginTop: 4,
    display: 'flex', flexDirection: 'column', gap: 6,
  },
  sourcesLabel: {
    fontSize: 11,
    fontWeight: 600,
    letterSpacing: '0.06em',
    textTransform: 'uppercase',
    color: 'var(--text-tertiary)',
  },
  srcItem: {
    background: 'var(--bg-elevated)',
    border: '1px solid var(--border)',
    borderRadius: 8,
    padding: '8px 12px',
    display: 'flex', flexDirection: 'column', gap: 4,
  },
  srcMeta: {
    fontSize: 11,
    fontWeight: 600,
    color: 'var(--accent)',
    letterSpacing: '0.02em',
  },
  srcText: {
    fontSize: 12.5,
    lineHeight: 1.65,
    color: 'var(--text-secondary)',
  },
  inputRow: {
    padding: '14px 20px 18px',
    borderTop: '1px solid var(--border)',
    background: 'var(--bg-elevated)',
    display: 'flex', gap: 10, alignItems: 'flex-end',
  },
  input: {
    flex: 1,
    padding: '10px 14px',
    border: '1px solid var(--border)',
    borderRadius: 10,
    fontSize: 14,
    lineHeight: 1.6,
    outline: 'none',
    resize: 'none',
    background: 'var(--bg)',
    transition: 'border-color 0.15s, background 0.15s',
  },
  btn: (disabled) => ({
    padding: '10px 22px',
    borderRadius: 10,
    border: 'none',
    background: disabled ? '#d8d8de' : 'var(--accent)',
    color: '#fff',
    cursor: disabled ? 'not-allowed' : 'pointer',
    fontSize: 14,
    fontWeight: 600,
    letterSpacing: '0.02em',
    transition: 'background 0.15s, transform 0.05s',
    flexShrink: 0,
    height: 'fit-content',
  }),
  hint: {
    fontSize: 11,
    color: 'var(--text-tertiary)',
    padding: '0 20px 10px',
    background: 'var(--bg-elevated)',
  },
  empty: {
    flex: 1, display: 'flex', flexDirection: 'column',
    alignItems: 'center', justifyContent: 'center',
    color: 'var(--text-tertiary)',
    gap: 8,
  },
  emptyTitle: { fontSize: 15, color: 'var(--text-secondary)', fontWeight: 500 },
  emptySub: { fontSize: 13, color: 'var(--text-tertiary)' },
}

export default function ChatPanel({ docId }) {
  const [messages, setMessages] = useState([])
  const [input, setInput] = useState('')
  const [loading, setLoading] = useState(false)
  const [sessionId, setSessionId] = useState(null)
  const [focused, setFocused] = useState(false)
  const bottomRef = useRef()

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  const send = async () => {
    const q = input.trim()
    if (!q || loading) return
    setInput('')
    setLoading(true)

    setMessages(prev => [...prev, { role: 'user', content: q }])
    setMessages(prev => [...prev, { role: 'assistant', content: '', sources: [], streaming: true }])

    try {
      const res = await fetch('/api/ask/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ question: q, doc_id: docId, session_id: sessionId }),
      })

      const reader = res.body.getReader()
      const decoder = new TextDecoder()
      let buffer = ''

      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        buffer += decoder.decode(value, { stream: true })
        const lines = buffer.split('\n\n')
        buffer = lines.pop()

        for (const line of lines) {
          if (!line.startsWith('data: ')) continue
          const data = JSON.parse(line.slice(6))
          if (data.type === 'meta') {
            if (data.session_id) setSessionId(data.session_id)
            setMessages(prev => {
              const next = [...prev]
              next[next.length - 1] = { ...next[next.length - 1], sources: data.sources }
              return next
            })
          } else if (data.type === 'token') {
            setMessages(prev => {
              const next = [...prev]
              next[next.length - 1] = {
                ...next[next.length - 1],
                content: next[next.length - 1].content + data.text,
              }
              return next
            })
          } else if (data.type === 'done') {
            setMessages(prev => {
              const next = [...prev]
              next[next.length - 1] = { ...next[next.length - 1], streaming: false }
              return next
            })
          }
        }
      }
    } catch (err) {
      setMessages(prev => {
        const next = [...prev]
        next[next.length - 1] = { role: 'assistant', content: `请求失败：${err.message}`, sources: [] }
        return next
      })
    } finally {
      setLoading(false)
    }
  }

  const focusedInputStyle = focused
    ? { ...s.input, borderColor: 'var(--accent-border)', background: '#fff',
        boxShadow: '0 0 0 3px var(--accent-soft)' }
    : s.input

  return (
    <div style={s.wrap}>
      <style>{`@keyframes blink { 50% { opacity: 0; } }`}</style>

      {messages.length === 0
        ? (
          <div style={s.empty}>
            <div style={s.emptyTitle}>开始与你的文档对话</div>
            <div style={s.emptySub}>上传文档后，在下方输入问题</div>
          </div>
        )
        : (
          <div style={s.messages}>
            {messages.map((msg, i) => (
              <div key={i} style={s.msgBlock(msg.role)}>
                <div style={s.bubble(msg.role)}>
                  {msg.content}
                  {msg.streaming && <span style={s.caret} />}
                </div>
                {msg.role === 'assistant' && msg.sources?.length > 0 && (
                  <div style={s.sourcesWrap}>
                    <div style={s.sourcesLabel}>
                      来源参考 · <span className="tnum">{msg.sources.length}</span> 段
                    </div>
                    {msg.sources.map((src, j) => (
                      <div key={j} style={s.srcItem}>
                        <div style={s.srcMeta} className="tnum">第 {src.page} 页</div>
                        <div style={s.srcText} className="clamp-2">{src.text}</div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            ))}
            <div ref={bottomRef} />
          </div>
        )
      }
      <div style={s.inputRow}>
        <textarea
          style={focusedInputStyle}
          rows={2}
          placeholder="输入问题，按 Ctrl + Enter 发送…"
          value={input}
          onChange={e => setInput(e.target.value)}
          onFocus={() => setFocused(true)}
          onBlur={() => setFocused(false)}
          onKeyDown={e => { if (e.key === 'Enter' && e.ctrlKey) send() }}
        />
        <button style={s.btn(loading || !input.trim())}
                onClick={send}
                disabled={loading || !input.trim()}>
          {loading ? '思考中…' : '发送'}
        </button>
      </div>
    </div>
  )
}
__FILE_END_MARKER__
echo "  ✓ frontend/src/ChatPanel.jsx"

mkdir -p "frontend/src"
cat > 'frontend/src/DocPanel.jsx' << '__FILE_END_MARKER__'
import { useRef, useState } from 'react'

const s = {
  wrap: { flex: 1, overflow: 'auto', padding: 12 },
  upload: {
    width: '100%',
    padding: '10px 0',
    border: '1px dashed #d0d0d8',
    borderRadius: 8,
    background: 'transparent',
    cursor: 'pointer',
    fontSize: 13,
    fontWeight: 500,
    color: 'var(--text-secondary)',
    marginBottom: 12,
    transition: 'border-color 0.15s, color 0.15s',
  },
  item: (active) => ({
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    padding: '8px 10px',
    borderRadius: 8,
    cursor: 'pointer',
    marginBottom: 4,
    background: active ? 'var(--accent-soft)' : 'transparent',
    border: active ? '1px solid var(--accent-border)' : '1px solid transparent',
    transition: 'background 0.12s',
  }),
  name: {
    flex: 1,
    minWidth: 0,                     // 关键：让 flex 子项可以正常 ellipsis
    fontSize: 13,
    lineHeight: 1.5,
    color: 'var(--text-primary)',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  badge: {
    fontSize: 11,
    fontWeight: 500,
    color: 'var(--text-tertiary)',
    flexShrink: 0,
    padding: '2px 6px',
    background: 'var(--border-soft)',
    borderRadius: 4,
  },
  del: {
    background: 'none',
    border: 'none',
    cursor: 'pointer',
    color: '#cfcfd6',
    fontSize: 16,
    lineHeight: 1,
    padding: 2,
    flexShrink: 0,
  },
  allBtn: (active) => ({
    width: '100%',
    textAlign: 'left',
    padding: '9px 10px',
    borderRadius: 8,
    cursor: 'pointer',
    marginBottom: 8,
    background: active ? 'var(--accent-soft)' : '#eeeef2',
    border: active ? '1px solid var(--accent-border)' : '1px solid transparent',
    fontSize: 13,
    fontWeight: 600,
    color: active ? 'var(--accent)' : 'var(--text-primary)',
    letterSpacing: '0.01em',
  }),
  uploading: {
    fontSize: 12,
    color: 'var(--text-secondary)',
    textAlign: 'center',
    padding: 8,
    lineHeight: 1.5,
  },
  empty: {
    fontSize: 12,
    color: 'var(--text-tertiary)',
    textAlign: 'center',
    marginTop: 24,
    lineHeight: 1.6,
  },
}

export default function DocPanel({ docs, selectedDocId, onSelect, onRefresh }) {
  const inputRef = useRef()
  const [uploading, setUploading] = useState(false)

  const handleUpload = async (e) => {
    const file = e.target.files?.[0]
    if (!file) return
    setUploading(true)
    const form = new FormData()
    form.append('file', file)
    try {
      const res = await fetch('/api/documents/upload', { method: 'POST', body: form })
      if (!res.ok) {
        const err = await res.json()
        alert(err.detail || '上传失败')
      } else {
        await onRefresh()
      }
    } finally {
      setUploading(false)
      e.target.value = ''
    }
  }

  const handleDelete = async (e, docId) => {
    e.stopPropagation()
    if (!confirm('确认删除该文档？')) return
    await fetch(`/api/documents/${docId}`, { method: 'DELETE' })
    await onRefresh()
    if (selectedDocId === docId) onSelect(null)
  }

  return (
    <div style={s.wrap}>
      <input ref={inputRef} type="file" accept=".pdf,.txt,.docx"
             style={{ display: 'none' }} onChange={handleUpload} />
      <button style={s.upload} onClick={() => inputRef.current.click()}>
        + 上传文档 · PDF / DOCX / TXT
      </button>
      {uploading && <p style={s.uploading}>正在解析并建立索引…</p>}

      <button style={s.allBtn(!selectedDocId)} onClick={() => onSelect(null)}>
        全文档问答
      </button>

      {docs.map(doc => (
        <div key={doc.doc_id} style={s.item(selectedDocId === doc.doc_id)}
             onClick={() => onSelect(doc.doc_id)}>
          <span style={s.name} title={doc.original_name}>{doc.original_name}</span>
          <span style={s.badge} className="tnum">{doc.chunk_count}</span>
          <button style={s.del} onClick={(e) => handleDelete(e, doc.doc_id)}
                  title="删除文档">×</button>
        </div>
      ))}

      {docs.length === 0 && !uploading && (
        <p style={s.empty}>暂无文档<br />请先上传一个文件</p>
      )}
    </div>
  )
}
__FILE_END_MARKER__
echo "  ✓ frontend/src/DocPanel.jsx"

mkdir -p "frontend/src"
cat > 'frontend/src/main.jsx' << '__FILE_END_MARKER__'
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.jsx'

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
)
__FILE_END_MARKER__
echo "  ✓ frontend/src/main.jsx"

mkdir -p "frontend"
cat > 'frontend/vite.config.js' << '__FILE_END_MARKER__'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': 'http://localhost:8000',
    },
  },
})
__FILE_END_MARKER__
echo "  ✓ frontend/vite.config.js"

cat > 'requirements.txt' << '__FILE_END_MARKER__'
fastapi==0.111.0
uvicorn[standard]==0.29.0
python-multipart==0.0.9
langchain==0.2.6
langchain-community==0.2.6
langchain-openai==0.1.14
chromadb==0.5.3
pymupdf==1.24.5
python-docx==1.1.2
sentence-transformers==3.0.1
openai==1.35.3
sqlalchemy==2.0.31
aiosqlite==0.20.0
python-dotenv==1.0.1
httpx==0.27.0
__FILE_END_MARKER__
echo "  ✓ requirements.txt"


echo ""
echo "==> 全部 21 个文件展开完成"
echo ""
echo "下一步："
echo "  1. cp .env.example .env    # 创建 .env 并填入 API key"
echo "  2. vim .env                # 至少配置 DASHSCOPE_API_KEY 或 OPENAI_API_KEY"
echo "  3. docker compose build --no-cache"
echo "  4. docker compose up -d"
echo "  5. docker compose logs -f"
