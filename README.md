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
