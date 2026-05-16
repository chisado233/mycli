import json

from llm import LLM


CONFIG_PATH = r"D:\agent_workspace\openclaw.json"
PROVIDER_NAME = "custom-aiapi-meccy-top"
MODEL_NAME = "gpt-5.4"


def main() -> None:
    client = LLM.from_openclaw_config(CONFIG_PATH)
    response = client.call_chat(
        provider=PROVIDER_NAME,
        model=MODEL_NAME,
        messages=[
            {"role": "system", "content": "You are a concise assistant."},
            {"role": "user", "content": "Reply with exactly: provider ok"},
        ],
        temperature=0.0,
        max_tokens=32,
    )
    print(json.dumps(response.to_dict(), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
