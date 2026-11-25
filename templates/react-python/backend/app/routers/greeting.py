"""问候接口路由。"""
from datetime import UTC, datetime

from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter(prefix="/api/v1", tags=["greeting"])


class Greeting(BaseModel):
    message: str
    time: str


@router.get("/greeting", response_model=Greeting)
def get_greeting() -> Greeting:
    return Greeting(
        message="Hello from Python backend",
        time=datetime.now(UTC).isoformat(),
    )
