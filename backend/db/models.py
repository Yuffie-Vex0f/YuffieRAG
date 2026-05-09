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
