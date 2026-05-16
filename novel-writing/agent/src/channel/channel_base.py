from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import asdict, dataclass, field
from time import time
from typing import Any, Dict


@dataclass
class ChannelMessage:
    channel_id: str
    direction: str
    content: str
    sender: str = ""
    receiver: str = ""
    created_at: float = field(default_factory=time)
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class ChannelResult:
    ok: bool
    channel_id: str
    content: str = ""
    error: str = ""
    data: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "ok": self.ok,
            "channel_id": self.channel_id,
            "content": self.content,
            "error": self.error,
            "data": self.data,
        }


class BaseChannel(ABC):
    channel_id: str = ""

    def __init__(self, config: Dict[str, Any] | None = None) -> None:
        self.config = config or {}

    @abstractmethod
    def send_message(self, content: str, sender: str = "", receiver: str = "", metadata: Dict[str, Any] | None = None) -> ChannelResult:
        raise NotImplementedError

    @abstractmethod
    def push_inbound_message(
        self,
        content: str,
        sender: str = "user",
        receiver: str = "",
        metadata: Dict[str, Any] | None = None,
    ) -> ChannelResult:
        raise NotImplementedError

    @abstractmethod
    def receive_messages(self, limit: int = 20) -> list[ChannelMessage]:
        raise NotImplementedError

    @abstractmethod
    def list_sent_messages(self, limit: int = 20) -> list[ChannelMessage]:
        raise NotImplementedError

    @abstractmethod
    def list_messages(self, limit: int = 100) -> list[ChannelMessage]:
        raise NotImplementedError
