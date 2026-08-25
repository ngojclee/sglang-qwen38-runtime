#!/usr/bin/env python3
# Parse SSE stream from stdin + prompt_tokens from /tmp/pt_last.txt
import sys, json, time
try:
    pt = int(open('/tmp/pt_last.txt').read().strip())
except Exception:
    pt = 0
t0 = time.time()
first = None
done = None
ct = 0
reasoning = 0
for line in sys.stdin:
    line = line.strip()
    if not line.startswith('data: '):
        continue
    p = line[6:]
    if p == '[DONE]':
        done = time.time()
        break
    try:
        d = json.loads(p)
    except Exception:
        continue
    if first is None:
        first = time.time()
    delta = (d.get('choices') or [{}])[0].get('delta', {})
    c = delta.get('content')
    r = delta.get('reasoning_content')
    if isinstance(c, str) and c:
        ct += 1
    if isinstance(r, str) and r:
        reasoning += 1
tot = (done - t0) if done else (time.time() - t0)
ttft = (first - t0) if first else tot
dec_t = tot - ttft
print(f"PROMPT_TOKENS {pt} TTFT {ttft:.2f}s PREFILL_TOK_S {(pt/ttft if ttft>0.01 else 0):.0f} DEC_SEC {dec_t:.2f} CONTENT_TOKENS {ct} REASONING {reasoning} DECODE_TOK_S {(ct/dec_t if dec_t>0.01 and ct>0 else 0):.1f}")
