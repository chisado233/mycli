import unittest

from llm import LLM


class LLMTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.llm = LLM()

    def test_list_providers(self) -> None:
        self.assertIn("mock", self.llm.list_providers())

    def test_load_provider_configs_from_openclaw(self) -> None:
        provider_configs = LLM.load_provider_configs_from_openclaw(r"D:\agent_workspace\openclaw.json")
        self.assertIn("custom-aiapi-meccy-top", provider_configs)
        self.assertEqual(provider_configs["custom-aiapi-meccy-top"]["type"], "openai_compatible")
        self.assertEqual(provider_configs["custom-aiapi-meccy-top"]["api_base"], "https://aiapi.meccy.top/v1")

    def test_mock_text_response(self) -> None:
        response = self.llm.call_chat(
            provider="mock",
            model="mock-model",
            messages=[
                {"role": "system", "content": "You are a test assistant."},
                {"role": "user", "content": "hello"},
            ],
        )
        self.assertTrue(response.ok)
        self.assertEqual(response.message.role, "assistant")
        self.assertIn("[mock:mock-model]", response.message.content)

    def test_mock_tool_call_response(self) -> None:
        response = self.llm.call_chat(
            provider="mock",
            model="mock-model",
            messages=[
                {"role": "user", "content": "please [call_tool:read]"},
            ],
            tools=[
                {
                    "name": "read",
                    "description": "Read file contents",
                    "parameters": {"type": "object", "properties": {"path": {"type": "string"}}},
                }
            ],
        )
        self.assertTrue(response.ok)
        self.assertEqual(response.finish_reason, "tool_calls")
        self.assertEqual(response.message.tool_calls[0].name, "read")

    def test_unknown_provider(self) -> None:
        response = self.llm.call_chat(
            provider="missing-provider",
            model="whatever",
            messages=[{"role": "user", "content": "hello"}],
        )
        self.assertFalse(response.ok)
        self.assertIn("provider not registered", response.error)

    def test_print_llm_demo(self) -> None:
        text_response = self.llm.call_chat(
            provider="mock",
            model="mock-model",
            messages=[
                {"role": "system", "content": "You are a coding agent."},
                {"role": "user", "content": "Summarize the current task."},
            ],
        )
        tool_response = self.llm.call_chat(
            provider="mock",
            model="mock-model",
            messages=[
                {"role": "user", "content": "please [call_tool:read]"},
            ],
            tools=[
                {
                    "name": "read",
                    "description": "Read file contents",
                    "parameters": {"type": "object", "properties": {"path": {"type": "string"}}},
                }
            ],
        )

        print("\n=== LLM TEXT RESPONSE START ===")
        print(text_response.to_dict())
        print("=== LLM TEXT RESPONSE END ===")

        print("\n=== LLM TOOL RESPONSE START ===")
        print(tool_response.to_dict())
        print("=== LLM TOOL RESPONSE END ===\n")

        self.assertTrue(text_response.ok)
        self.assertTrue(tool_response.ok)


if __name__ == "__main__":
    unittest.main()
