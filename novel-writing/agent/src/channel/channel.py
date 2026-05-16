from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List

try:
    from .channel_base import BaseChannel, ChannelMessage, ChannelResult
    from .terminal_channel import TerminalChannel
except ImportError:  # pragma: no cover - support direct script/module execution
    from channel_base import BaseChannel, ChannelMessage, ChannelResult
    from terminal_channel import TerminalChannel


class ChannelManager:
    CHANNEL_REGISTRY = {
        "terminal": TerminalChannel,
    }

    def __init__(self, config_path: str | None = None, config: Dict[str, Any] | None = None) -> None:
        self.config_path = config_path or r"D:\agent_workspace\projects\mult_agent\config\channel.json"
        self.config = config or self._load_config(self.config_path)
        self.channels: Dict[str, BaseChannel] = {}
        self._load_channels()

    def _load_config(self, config_path: str) -> Dict[str, Any]:
        path = Path(config_path)
        if not path.exists():
            return {"channels": []}
        return json.loads(path.read_text(encoding="utf-8"))

    def _load_channels(self) -> None:
        for item in self.config.get("channels", []):
            if not isinstance(item, dict):
                continue
            channel_id = str(item.get("id", "")).strip()
            if not channel_id:
                continue
            if str(item.get("enable", "true")).lower() == "false":
                continue
            channel_class = self.CHANNEL_REGISTRY.get(channel_id)
            if channel_class is None:
                continue
            self.channels[channel_id] = channel_class(config=item)

    def list_channels(self) -> List[str]:
        return sorted(self.channels.keys())

    def get_channel(self, channel_id: str) -> BaseChannel:
        if channel_id not in self.channels:
            raise KeyError(f"channel not available: {channel_id}")
        return self.channels[channel_id]

    def send_message(
        self,
        channel_id: str,
        content: str,
        sender: str = "agent",
        receiver: str = "user",
        metadata: Dict[str, Any] | None = None,
    ) -> ChannelResult:
        channel = self.get_channel(channel_id)
        return channel.send_message(content=content, sender=sender, receiver=receiver, metadata=metadata)

    def push_inbound_message(
        self,
        channel_id: str,
        content: str,
        sender: str = "user",
        receiver: str = "agent",
        metadata: Dict[str, Any] | None = None,
    ) -> ChannelResult:
        channel = self.get_channel(channel_id)
        return channel.push_inbound_message(content=content, sender=sender, receiver=receiver, metadata=metadata)

    def receive_messages(self, channel_id: str, limit: int = 20) -> List[ChannelMessage]:
        channel = self.get_channel(channel_id)
        return channel.receive_messages(limit=limit)

    def list_sent_messages(self, channel_id: str, limit: int = 20) -> List[ChannelMessage]:
        channel = self.get_channel(channel_id)
        return channel.list_sent_messages(limit=limit)

    def list_messages(self, channel_id: str, limit: int = 100) -> List[ChannelMessage]:
        channel = self.get_channel(channel_id)
        return channel.list_messages(limit=limit)

    def clear_messages(self, channel_id: str) -> None:
        channel = self.get_channel(channel_id)
        clear = getattr(channel, "clear_messages", None)
        if clear is None:
            raise AttributeError(f"channel does not support clear_messages: {channel_id}")
        clear()
