#!/usr/bin/env python3
# P16: 10-turn tool loop cho Qwen3.8-9B-Distill (non-stream, local API)
import json, time, urllib.request

API = "http://127.0.0.1:18000/v1/chat/completions"
MODEL = "Qwen3.8-9B-Distill"

tools = [
    {"type": "function", "function": {
        "name": "get_weather", "description": "Get weather for a city",
        "parameters": {"type": "object", "properties": {"city": {"type": "string"}}, "required": ["city"]}}},
    {"type": "function", "function": {
        "name": "search_web", "description": "Search the web",
        "parameters": {"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]}}},
]

def call(messages):
    t0 = time.time()
    body = json.dumps({
        "model": MODEL, "messages": messages, "tools": tools,
        "max_tokens": 512, "temperature": 0.3, "stream": False,
        "chat_template_kwargs": {"enable_thinking": False},
    }).encode()
    req = urllib.request.Request(API, data=body, headers={"Content-Type": "application/json"})
    try:
        r = urllib.request.urlopen(req, timeout=300)
        d = json.loads(r.read())
    except urllib.error.HTTPError as e:
        return {"_http_error": e.code, "_body": e.read().decode()[:300]}, time.time()-t0
    return d, time.time()-t0

messages = [{"role": "user", "content": (
    "You are an agent. Use tools to answer. First get_weather for Hanoi, then search_web for 'Qwen3.8 release', "
    "then get_weather for Paris. Call tools one at a time and continue until done. Finally summarize.")}]

stats = {"turns": 0, "tool_calls": 0, "malformed": 0, "empty": 0, "dropped": 0, "bang5": 0,
         "invalid_json": 0, "latencies": [], "tool_rounds": 0, "total_content_tokens": 0}

for turn in range(12):
    d, lat = call(messages)
    stats["turns"] += 1
    stats["latencies"].append(lat)
    if "_http_error" in d:
        print(f"turn {turn}: HTTP ERROR {d['_http_error']} {d['_body']}")
        stats["dropped"] += 1
        break
    if "error" in d:
        print(f"turn {turn}: API error {str(d['error'])[:200]}")
        stats["dropped"] += 1
        break
    msg = d["choices"][0]["message"]
    content = msg.get("content") or ""
    tcs = msg.get("tool_calls") or []
    usage = d.get("usage", {})
    stats["total_content_tokens"] += usage.get("completion_tokens", 0)
    if "!!!!!" in content:
        stats["bang5"] += 1
    if not content.strip() and not tcs:
        stats["empty"] += 1
    if tcs:
        for tc in tcs:
            stats["tool_calls"] += 1
            fn = tc.get("function", {})
            name = fn.get("name", "")
            args_raw = fn.get("arguments", "")
            try:
                args = json.loads(args_raw)
                if not isinstance(args, dict):
                    stats["malformed"] += 1
            except Exception:
                stats["malformed"] += 1
                stats["invalid_json"] += 1
                args = {}
            # execute giả
            result = json.dumps({"ok": True, "answer": f"fake result for {name}"})
            messages.append({"role": "assistant", "content": content, "tool_calls": tcs})
            messages.append({"role": "tool", "tool_call_id": tc.get("id", f"call_{turn}"), "content": result})
        stats["tool_rounds"] += 1
        continue
    # không còn tool call → hoàn tất
    messages.append({"role": "assistant", "content": content})
    print(f"turn {turn}: DONE — {content[:120]!r}")
    break

print("=== STATS ===")
print(json.dumps(stats, indent=2))
print("avg_turn_latency %.2fs" % (sum(stats["latencies"])/len(stats["latencies"]) if stats["latencies"] else 0))
print("VERDICT:", "PASS" if (stats["malformed"] == 0 and stats["empty"] == 0 and stats["dropped"] == 0 and stats["bang5"] == 0 and stats["turns"] >= 3) else "FAIL")
