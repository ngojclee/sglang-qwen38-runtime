#!/usr/bin/env python3
# P17: concurrency 2/3/4 short-context agent workload
import json, time, urllib.request, concurrent.futures

API = "http://127.0.0.1:18000/v1/chat/completions"
MODEL = "Qwen3.8-9B-Distill"

payload_base = {
    "model": MODEL,
    "messages": [{"role": "user", "content": "Write a Python function for merging two sorted lists, with comments and type hints."}],
    "max_tokens": 200,
    "temperature": 0.3,
    "stream": False,
    "chat_template_kwargs": {"enable_thinking": False},
}

def one(i):
    body = json.dumps(payload_base).encode()
    req = urllib.request.Request(API, data=body, headers={"Content-Type": "application/json"})
    t0 = time.time()
    d = json.loads(urllib.request.urlopen(req, timeout=300).read())
    lat = time.time() - t0
    ct = d.get("usage", {}).get("completion_tokens", 0)
    return lat, ct

for n in (2, 3, 4):
    t0 = time.time()
    with concurrent.futures.ThreadPoolExecutor(max_workers=n) as ex:
        results = list(ex.map(one, range(n)))
    wall = time.time() - t0
    lats = [r[0] for r in results]
    cts = [r[1] for r in results]
    agg = sum(cts) / wall
    print(f"N={n}: wall {wall:.2f}s agg_decode {agg:.1f} tok/s | per-req lat {[f'{x:.2f}' for x in lats]} | completion {cts}")

# 2x100K long concurrent
def long_one(i):
    from transformers import AutoTokenizer
    tok = AutoTokenizer.from_pretrained('/workspace/qwen-serving/models/Qwen3.8-9B-Distill')
    sentence = ("The quick brown fox jumps over the lazy dog while the moon rises over the silent mountain. "
                "Engineers carefully measure the temperature of the GPU and adjust the cooling fans to prevent throttling. ")
    prompt = sentence * (100000 // len(tok.encode(sentence)))
    body = json.dumps({
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt + "\n\nOne sentence summary."}],
        "max_tokens": 32, "stream": False,
        "chat_template_kwargs": {"enable_thinking": False},
    }).encode()
    req = urllib.request.Request(API, data=body, headers={"Content-Type": "application/json"})
    t0 = time.time()
    d = json.loads(urllib.request.urlopen(req, timeout=600).read())
    return time.time() - t0, d.get("usage", {}).get("prompt_tokens", 0), d.get("usage", {}).get("completion_tokens", 0)

t0 = time.time()
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
    r2 = list(ex.map(long_one, range(2)))
wall = time.time() - t0
print("2x100K: wall %.1fs" % wall)
for r in r2:
    print("  lat %.1fs prompt %d comp %d" % r)
