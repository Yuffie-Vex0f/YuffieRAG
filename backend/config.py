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
