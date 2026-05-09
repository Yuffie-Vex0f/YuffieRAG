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
