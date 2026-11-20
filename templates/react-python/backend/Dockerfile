# 后端 Dockerfile（Python FastAPI，非 root + 最小依赖）

FROM python:3.12-slim
WORKDIR /app
# 安装依赖（锁定版本）
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY app ./app
# 创建非 root 用户
RUN addgroup --system app && adduser --system --ingroup app app
USER app
EXPOSE 8000
HEALTHCHECK CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
