import unittest

from agent import agent


class AgentTestCase(unittest.TestCase):
    def test_agent_system_prompt_exists(self) -> None:
        runner = agent()
        prompt = runner.get_system_prompt()
        self.assertTrue(prompt.strip())
        self.assertIn("Agent Identity", prompt)

    def test_agent_loop_one_round(self) -> None:
        runner = agent()
        result = runner.agent_loop("请用一句话介绍你自己。")
        self.assertTrue(result["ok"])
        self.assertTrue(result["final_response"].strip())


if __name__ == "__main__":
    unittest.main()
