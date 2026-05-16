from __future__ import annotations

from collections import deque
from typing import Any, Deque, Dict, List

try:
    from .channel_base import BaseChannel, ChannelMessage, ChannelResult
except ImportError:  # pragma: no cover - support direct script/module execution
    from channel_base import BaseChannel, ChannelMessage, ChannelResult


class TerminalChannel(BaseChannel):
    channel_id = "terminal"

    def __init__(self, config: Dict[str, Any] | None = None) -> None:
        super().__init__(config=config)
        self._inbox: Deque[ChannelMessage] = deque()
        self._sent: Deque[ChannelMessage] = deque()
        self._history: Deque[ChannelMessage] = deque()
        self.echo_to_stdout = str(self.config.get("echo_to_stdout", "true")).lower() != "false"

    def send_message(
        self,
        content: str,
        sender: str = "agent",
        receiver: str = "user",
        metadata: Dict[str, Any] | None = None,
    ) -> ChannelResult:
        message = ChannelMessage(
            channel_id=self.channel_id,
            direction="outbound",
            content=str(content),
            sender=sender,
            receiver=receiver,
            metadata=metadata or {},
        )
        self._sent.append(message)
        self._history.append(message)
        if self.echo_to_stdout:
            print(message.content)
        return ChannelResult(
            ok=True,
            channel_id=self.channel_id,
            content=message.content,
            data={"message": message.to_dict()},
        )

    def push_inbound_message(
        self,
        content: str,
        sender: str = "user",
        receiver: str = "agent",
        metadata: Dict[str, Any] | None = None,
    ) -> ChannelResult:
        message = ChannelMessage(
            channel_id=self.channel_id,
            direction="inbound",
            content=str(content),
            sender=sender,
            receiver=receiver,
            metadata=metadata or {},
        )
        self._inbox.append(message)
        self._history.append(message)
        return ChannelResult(
            ok=True,
            channel_id=self.channel_id,
            content=message.content,
            data={"message": message.to_dict()},
        )

    def receive_messages(self, limit: int = 20) -> List[ChannelMessage]:
        items: List[ChannelMessage] = []
        max_items = max(0, int(limit))
        while self._inbox and len(items) < max_items:
            items.append(self._inbox.popleft())
        return items

    def list_sent_messages(self, limit: int = 20) -> List[ChannelMessage]:
        if limit <= 0:
            return []
        return list(self._sent)[-limit:]

    def list_messages(self, limit: int = 100) -> List[ChannelMessage]:
        if limit <= 0:
            return []
        return list(self._history)[-limit:]

    def clear_messages(self) -> None:
        self._inbox.clear()
        self._sent.clear()
        self._history.clear()
