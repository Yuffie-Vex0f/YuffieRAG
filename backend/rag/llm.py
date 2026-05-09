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
