from __future__ import annotations

from channel import ChannelManager


def main() -> None:
    manager = ChannelManager(
        config={
            "channels": [
                {
                    "id": "terminal",
                    "enable": "true",
                }
            ]
        }
    )

    manager.push_inbound_message("terminal", "你好，这是用户发来的消息。")
    inbound_messages = manager.receive_messages("terminal")
    for item in inbound_messages:
        print(f"[inbound] {item.sender} -> {item.receiver}: {item.content}")

    manager.send_message("terminal", "收到，我已经拿到你的消息。", sender="agent", receiver="user")


if __name__ == "__main__":
    main()
