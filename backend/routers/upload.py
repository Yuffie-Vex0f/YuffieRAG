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
