#!/bin/bash
# P8: 200K needle LIVE + P9: REAL MAX CONTEXT (262K sát) — non-stream, check content
set -x
PORT=18000
cd /tmp

/workspace/venv/bin/python - <<'PY'
import json
from transformers import AutoTokenizer
tok = AutoTokenizer.from_pretrained('/workspace/qwen-serving/models/Qwen3.8-9B-Distill')
sentence = ("The quick brown fox jumps over the lazy dog while the moon rises over the silent mountain. "
            "Engineers carefully measure the temperature of the GPU and adjust the cooling fans to prevent throttling. "
            "The model processes long sequences with speculative decoding and hybrid attention. ")

def make(target, needle=True):
    n = target // len(tok.encode(sentence))
    parts = sentence * n
    if needle:
        mid = len(parts)//2
        parts = parts[:mid] + " The secret code is SUNSET-CODE-7781. " + parts[mid:]
    return parts

# 200K needle
p200 = make(198000, True)
pt200 = len(tok.encode(p200))
open('/tmp/p200.json','w').write(json.dumps({
    "model":"Qwen3.8-9B-Distill",
    "messages":[{"role":"user","content":p200 + "\n\nWhat is the secret code? Return the exact string."}],
    "max_tokens":128,"stream":False,
    "chat_template_kwargs":{"enable_thinking":False},
}))
print("p200 tokens", pt200)

# 261K max
p261 = make(261000, False)
pt261 = len(tok.encode(p261))
open('/tmp/p261.json','w').write(json.dumps({
    "model":"Qwen3.8-9B-Distill",
    "messages":[{"role":"user","content":p261 + "\n\nSummarize in one sentence."}],
    "max_tokens":64,"stream":False,
    "chat_template_kwargs":{"enable_thinking":False},
}))
print("p261 tokens", pt261)
PY

echo "=== 200K NEEDLE (non-stream) ==="
curl -sS -m 900 http://127.0.0.1:$PORT/v1/chat/completions -H 'Content-Type: application/json' -d @/tmp/p200.json -o /tmp/r200.json -w 'HTTP=%{http_code} time=%{time_total}\n'
python3 - <<'PY'
import json
d=json.load(open('/tmp/r200.json'))
if 'error' in d:
    print('ERROR', str(d['error'])[:300])
else:
    u=d.get('usage',{}); m=d['choices'][0]['message']
    c=m.get('content') or ''; r=m.get('reasoning') or ''
    print('prompt_tokens',u.get('prompt_tokens'),'completion',u.get('completion_tokens'),'finish',d['choices'][0].get('finish_reason'))
    print('NEEDLE_FOUND', 'SUNSET-CODE-7781' in c)
    print('BANG5', '!!!!!' in c or '!!!!!' in r)
    print('CONTENT', repr(c[:200]))
PY

echo "=== 261K MAX CONTEXT (non-stream) ==="
curl -sS -m 900 http://127.0.0.1:$PORT/v1/chat/completions -H 'Content-Type: application/json' -d @/tmp/p261.json -o /tmp/r261.json -w 'HTTP=%{http_code} time=%{time_total}\n'
python3 - <<'PY'
import json
d=json.load(open('/tmp/r261.json'))
if 'error' in d:
    print('ERROR', str(d['error'])[:300])
else:
    u=d.get('usage',{}); m=d['choices'][0]['message']
    c=m.get('content') or ''
    print('prompt_tokens',u.get('prompt_tokens'),'completion',u.get('completion_tokens'),'finish',d['choices'][0].get('finish_reason'))
    print('BANG5', '!!!!!' in c)
    print('CONTENT', repr(c[:150]))
PY
echo "=== GPU ==="
nvidia-smi --query-gpu=index,memory.used,memory.free --format=csv,noheader
