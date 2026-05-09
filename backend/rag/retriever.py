from functools import lru_cache
from typing import List
from langchain.schema import Document
from langchain_community.vectorstores import Chroma
from backend.config import settings


@lru_cache(maxsize=1)
def get_embeddings():
    """单例：根据配置加载 Embedding 模型
    
    EMBEDDING_PROVIDER 取值：
      - local: 本地 sentence-transformers（HuggingFace 模型，如 bge / Qwen3）
      - dashscope: 阿里云 DashScope Embedding API（需要 DASHSCOPE_API_KEY）
      - openai: OpenAI Embedding API（需要 OPENAI_API_KEY）
    """
    provider = settings.embedding_provider

    if provider == "local":
        from langchain_community.embeddings import HuggingFaceEmbeddings
        return HuggingFaceEmbeddings(
            model_name=settings.embedding_model,
            model_kwargs={"device": "cpu"},
            encode_kwargs={
                "normalize_embeddings": True,
                "batch_size": 32,
            },
        )

    elif provider == "dashscope":
        from langchain_community.embeddings import DashScopeEmbeddings
        return DashScopeEmbeddings(
            model=settings.embedding_model,  # 例如 "text-embedding-v3"
            dashscope_api_key=settings.dashscope_api_key,
        )

    elif provider == "openai":
        from langchain_openai import OpenAIEmbeddings
        return OpenAIEmbeddings(
            model=settings.embedding_model,  # 例如 "text-embedding-3-small"
            openai_api_key=settings.openai_api_key,
            base_url=settings.openai_base_url,
        )

    else:
        raise ValueError(
            f"不支持的 embedding_provider: {provider}。"
            f"可选值: local | dashscope | openai"
        )


def get_vectorstore(collection_name: str = "default") -> Chroma:
    """获取 ChromaDB 集合（显式关闭 telemetry 提升性能）"""
    import chromadb
    from chromadb.config import Settings as ChromaSettings

    client = chromadb.PersistentClient(
        path=settings.chroma_dir,
        settings=ChromaSettings(anonymized_telemetry=False),
    )

    return Chroma(
        client=client,
        collection_name=collection_name,
        embedding_function=get_embeddings(),
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
    # 新版 chromadb 不再支持直接 where 删除，需要先查到 ids 再删
    collection = vectorstore._collection
    results = collection.get(where={"doc_id": doc_id})
    ids = results.get("ids", [])
    if ids:
        collection.delete(ids=ids)
