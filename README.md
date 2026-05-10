# YuffieRAG · 本地文档问答助手

基于 RAG（检索增强生成）的本地中文文档 Q&A 系统。上传 PDF / DOCX / TXT，即可对话提问，自动给出来源页码引用。

GitHub: https://github.com/Yuffie-Vex0f/YuffieRAG

> 本项目由 [Claude](https://claude.ai)（Anthropic）协同完成。


## 技术栈

| 层次 | 技术 |
|------|------|
| 后端框架 | Python 3.11 + FastAPI |
| RAG 框架 | LangChain 0.2 |
| 向量数据库 | ChromaDB 0.5（本地持久化） |
| Embedding | 三选一：本地 bge/Qwen3 / 阿里云 DashScope / OpenAI |
| LLM | 通义千问 qwen-turbo / OpenAI / Ollama |
| 前端 | React 18 + Vite |
| 元数据 | SQLite |
| 部署 | Docker + Docker Compose |

## 快速启动（Docker，推荐）

### 1. 克隆项目

```bash
git clone https://github.com/Yuffie-Vex0f/YuffieRAG.git
cd YuffieRAG
```

### 2. 配置环境变量

```bash
cp .env.example .env
nano .env   # 至少填入 DASHSCOPE_API_KEY
```

通义千问 API Key 申请：https://dashscope.console.aliyun.com/apiKey （有免费额度）

### 3. 启动容器

```bash
docker compose up -d
docker compose logs -f app
```

看到 `Application startup complete.` 后按 Ctrl+C 退出日志。

### 4. 下载本地 Embedding 模型（首次运行）

如果使用本地 embedding 模式（默认，不依赖外网），需要先下载模型到容器内：

```bash
# 推荐：bge-base-zh-v1.5（100MB，速度快，效果均衡）
docker compose exec app python -c "
from modelscope import snapshot_download
snapshot_download('BAAI/bge-base-zh-v1.5')
"

# 或者：Qwen3-Embedding-0.6B（600MB，效果最好但慢）
docker compose exec app python -c "
from modelscope import snapshot_download
snapshot_download('Qwen/Qwen3-Embedding-0.6B')
"
```

模型缓存到 `./model-cache/`，后续重启不需要重下。

如果使用云端 Embedding 模式（dashscope / openai），无需下载，但需要配置 .env 见下文。

### 5. 访问

浏览器打开 http://localhost:8000

## Embedding Provider 切换

本项目支持三种 Embedding 后端，在 `.env` 中切换：

### 模式 A：local（本地模型，推荐）

```bash
EMBEDDING_PROVIDER=local
EMBEDDING_MODEL=/root/.cache/modelscope/hub/models/BAAI/bge-base-zh-v1.5
```

可选模型：
- `BAAI/bge-base-zh-v1.5` —— 100MB，CPU 友好，推荐
- `BAAI/bge-large-zh-v1.5` —— 326MB，效果稍好
- `Qwen/Qwen3-Embedding-0.6B` —— 600MB，效果最好但 CPU 上慢

### 模式 B：dashscope（阿里云 API，最快）

```bash
EMBEDDING_PROVIDER=dashscope
EMBEDDING_MODEL=text-embedding-v3
```

复用 `DASHSCOPE_API_KEY`，无需另配。

### 模式 C：openai（OpenAI 或兼容 API）

```bash
EMBEDDING_PROVIDER=openai
EMBEDDING_MODEL=text-embedding-3-small
OPENAI_API_KEY=sk-xxxxx
OPENAI_BASE_URL=https://api.openai.com/v1
```

切换 provider 后需要清空向量库（不同模型维度不兼容）：

```bash
sudo rm -rf data/chroma
docker compose restart app
```

## LLM Provider 切换

在 `.env` 中设置 `LLM_PROVIDER`：

- `dashscope` —— 通义千问 qwen-turbo（推荐，国内访问稳定）
- `openai` —— OpenAI 或兼容 API
- `ollama` —— 本地模型，需先安装 [Ollama](https://ollama.ai) 并运行 `ollama pull qwen2`


## 项目结构

```
YuffieRAG/
├── backend/
│   ├── main.py              # FastAPI 入口
│   ├── config.py            # 全局配置（pydantic-settings）
│   ├── routers/
│   │   ├── upload.py        # 上传 / 列表 / 删除接口
│   │   └── ask.py           # 问答接口（SSE 流式）
│   ├── rag/
│   │   ├── parser.py        # 文档解析 + 分块
│   │   ├── retriever.py     # 向量化 + 检索（多 provider）
│   │   └── llm.py           # LLM 调用 + Prompt 构造
│   └── db/
│       └── models.py        # SQLite 文档元数据
├── frontend/
│   └── src/
│       ├── App.jsx          # 布局入口
│       ├── DocPanel.jsx     # 文档管理侧边栏
│       └── ChatPanel.jsx    # 对话面板（流式输出）
├── data/                    # 运行时数据（已 gitignore）
│   ├── uploads/             # 上传的原始文件
│   ├── chroma/              # 向量库
│   └── rag.db               # SQLite
├── model-cache/             # 本地 Embedding 模型（已 gitignore）
├── Dockerfile
├── docker-compose.yml
├── requirements.txt
├── .env.example
└── README.md
```

## API 文档

启动后访问 http://localhost:8000/docs 查看 Swagger 自动生成的 API 文档。

主要接口：

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/documents/upload` | 上传文档 |
| GET | `/api/documents/` | 文档列表 |
| DELETE | `/api/documents/{doc_id}` | 删除文档 |
| POST | `/api/ask/` | 提问（SSE 流式回答） |

## 常见问题

### 上传时 "正在解析并建立索引..." 很慢？

不同 Embedding 模型在 CPU 上速度差异巨大：

| 模型 | 100 字符短文本 | 500 字符长文本 |
|---|---|---|
| bge-base-zh-v1.5 | ~50 ms/条 | ~80 ms/条 |
| Qwen3-Embedding-0.6B | ~30 ms/条 | **~2500 ms/条** |

如果你的文档是中文教材类（每块文本较长），强烈建议用 bge 而不是 Qwen3。Qwen3 适合 GPU 环境。

### 删除文档报 ValueError？

ChromaDB 0.5+ API 改动，本项目已修复。如果是 fork 的旧版本，参考 `backend/rag/retriever.py` 的 `delete_document` 函数。

### 国内下载 HuggingFace 模型失败？

本项目使用 ModelScope 镜像下载，避开 HuggingFace。代码示例：

```python
from modelscope import snapshot_download
snapshot_download('BAAI/bge-base-zh-v1.5')
```

### 容器重建后模型丢了？

`docker-compose.yml` 已配 `./model-cache:/root/.cache` volume 持久化，不会丢。如果丢了说明你删了 host 的 `./model-cache` 目录。

## 致谢

- [LangChain](https://github.com/langchain-ai/langchain) —— RAG 框架
- [ChromaDB](https://github.com/chroma-core/chroma) —— 向量数据库
- [BAAI/bge-base-zh-v1.5](https://huggingface.co/BAAI/bge-base-zh-v1.5) —— 中文 Embedding 模型
- [Qwen Team](https://github.com/QwenLM/Qwen) —— Qwen3 Embedding & 通义千问 LLM
- [Claude](https://claude.ai)（Anthropic）—— 全程协同开发

## License

MIT