#!/bin/bash
# 🧪 Automated Verification Script for SGLang Qwen3.8
set -e

PORT="${1:-18000}"
HOST="${2:-127.0.0.1}"
BASE_URL="http://$HOST:$PORT"

echo "========================================================="
echo "🔍 1. Checking SGLang Health & Model Catalog ($BASE_URL)"
echo "========================================================="

MODELS_RESP=$(curl -s "$BASE_URL/v1/models" || true)
if [[ -z "$MODELS_RESP" ]]; then
    echo "❌ Error: Could not connect to SGLang at $BASE_URL."
    echo "👉 Ensure SGLang is running (e.g. supervisorctl status sglang)."
    exit 1
fi

echo "📦 Active Model Catalog:"
echo "$MODELS_RESP" | grep -o '"id":"[^"]*"' || echo "$MODELS_RESP"

if [[ "$MODELS_RESP" == *"Qwen3.8-27B-Uncensored"* ]]; then
    echo "✅ Verified: Clean Model ID 'Qwen3.8-27B-Uncensored' is active!"
fi

echo "========================================================="
echo "⚡ 2. Running Live Inference & Tool Calling Benchmark"
echo "========================================================="

python3 - <<EOF
import requests, time, json

url = "$BASE_URL/v1/chat/completions"
headers = {"Content-Type": "application/json"}

# 1. Test standard chat
payload_chat = {
    "model": "Qwen3.8-27B-Uncensored",
    "messages": [{"role": "user", "content": "Viết hàm quicksort bằng Python kèm giải thích ngắn gọn."}],
    "max_tokens": 128,
    "temperature": 0.1,
    "chat_template_kwargs": {"enable_thinking": False}
}

t0 = time.time()
r_chat = requests.post(url, headers=headers, json=payload_chat)
t1 = time.time()

if r_chat.status_code == 200:
    data = r_chat.json()
    toks = data.get("usage", {}).get("completion_tokens", 0)
    elapsed = t1 - t0
    tok_s = toks / elapsed if elapsed > 0 else 0
    print(f"✅ Chat test PASSED! Generated {toks} tokens in {elapsed:.2f}s (~{tok_s:.2f} tok/s)")
    print("Content preview:", data["choices"][0]["message"]["content"][:120], "...")
else:
    print(f"❌ Chat test FAILED with status {r_chat.status_code}: {r_chat.text}")

# 2. Test Tool Calling
payload_tool = {
    "model": "Qwen3.8-27B-Uncensored",
    "messages": [{"role": "user", "content": "Kiểm tra danh sách file trong thư mục hiện tại."}],
    "tools": [{
        "type": "function",
        "function": {
            "name": "run_shell",
            "description": "Execute shell command",
            "parameters": {
                "type": "object",
                "properties": {"command": {"type": "string"}},
                "required": ["command"]
            }
        }
    }],
    "tool_choice": "auto"
}

t0 = time.time()
r_tool = requests.post(url, headers=headers, json=payload_tool)
t1 = time.time()

if r_tool.status_code == 200:
    data = r_tool.json()
    msg = data["choices"][0]["message"]
    tc = msg.get("tool_calls", [])
    if tc:
        print(f"✅ Tool calling test PASSED in {t1-t0:.2f}s! Tool call extracted: {tc[0]['function']['name']}({tc[0]['function']['arguments']})")
    else:
        print("⚠️ Warning: No tool calls extracted, model outputted content:", msg.get("content"))
else:
    print(f"❌ Tool calling test FAILED with status {r_tool.status_code}: {r_tool.text}")

print("=========================================================")
print("🎉 ALL SERVER VERIFICATION CHECKS COMPLETED!")
print("=========================================================")
EOF
