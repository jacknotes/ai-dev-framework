"""FastAPI 应用入口。"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .routers import greeting

app = FastAPI(title="React + Python 示例 API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(greeting.router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
