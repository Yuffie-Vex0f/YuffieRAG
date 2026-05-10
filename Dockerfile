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
RUN npm config set registry https://registry.npmmirror.com
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
RUN pip install --no-cache-dir --timeout 600 -r requirements.txt \
    -i https://pypi.tuna.tsinghua.edu.cn/simple \
    --extra-index-url https://mirrors.aliyun.com/pypi/simple/
# 拷后端代码
COPY backend/ ./backend/

# 关键一步：把 stage 1 构建好的 dist 拷到 backend/main.py 期望的位置
# main.py 里读的是 Path("frontend/dist")，所以这里就放在 /app/frontend/dist
COPY --from=frontend-build /build/dist ./frontend/dist

EXPOSE 8000

CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8000"]
