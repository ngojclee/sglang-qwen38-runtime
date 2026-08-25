#!/usr/bin/env python3
# P15: quality sanity — coding, JSON extraction, reasoning, scraper-style
import json, time, urllib.request

API = "http://127.0.0.1:18000/v1/chat/completions"
MODEL = "Qwen3.8-9B-Distill"

def ask(prompt, max_tokens=400):
    body = json.dumps({
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens, "temperature": 0.2, "stream": False,
        "chat_template_kwargs": {"enable_thinking": False},
    }).encode()
    req = urllib.request.Request(API, data=body, headers={"Content-Type": "application/json"})
    t0 = time.time()
    d = json.loads(urllib.request.urlopen(req, timeout=300).read())
    return d["choices"][0]["message"].get("content") or "", time.time() - t0

tests = {
    "coding": "Write Python: parse CSV string into list of dicts, handle quoted fields. Return only code.",
    "json": "Extract JSON from: 'User John age 30 city Hanoi, order #1234 total 99.5'. Return JSON object with name, age, city, order_id, total.",
    "reasoning": "If it takes 5 machines 5 minutes to make 5 widgets, how long for 100 machines to make 100 widgets? Answer briefly.",
    "scraper": "From text: 'Product: RTX 5090, price $1999, stock 12 units'. Return a compact summary as JSON.",
}

for name, p in tests.items():
    c, lat = ask(p)
    print(f"=== {name} ({lat:.1f}s) ===")
    print(c[:400])
    print()
