from __future__ import annotations

import unittest

from channel import ChannelManager


class ChannelManagerTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.manager = ChannelManager(
            config={
                "channels": [
                    {
                        "id": "terminal",
                        "enable": "true",
                        "echo_to_stdout": "false",
                    }
                ]
            }
        )

    def test_list_channels(self) -> None:
        self.assertIn("terminal", self.manager.list_channels())

    def test_push_and_receive_inbound_message(self) -> None:
        pushed = self.manager.push_inbound_message("terminal", "hello from user")
        self.assertTrue(pushed.ok)

        received = self.manager.receive_messages("terminal", limit=10)
        self.assertEqual(len(received), 1)
        self.assertEqual(received[0].content, "hello from user")
        self.assertEqual(received[0].direction, "inbound")

    def test_send_message(self) -> None:
        sent = self.manager.send_message("terminal", "hello back", sender="agent", receiver="user")
        self.assertTrue(sent.ok)

        sent_items = self.manager.list_sent_messages("terminal", limit=10)
        self.assertEqual(len(sent_items), 1)
        self.assertEqual(sent_items[0].content, "hello back")
        self.assertEqual(sent_items[0].direction, "outbound")

    def test_list_message_history(self) -> None:
        self.manager.push_inbound_message("terminal", "user one")
        self.manager.send_message("terminal", "agent one")
        history = self.manager.list_messages("terminal", limit=10)
        self.assertEqual(len(history), 2)
        self.assertEqual(history[0].content, "user one")
        self.assertEqual(history[1].content, "agent one")


if __name__ == "__main__":
    unittest.main()
