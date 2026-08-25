#!/usr/bin/env python3
# Parse SSE stream from stdin: TTFT / decode / prefill metrics
import sys, json, time
t0 = time.time()
first = None
done = None
ct = 0
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
    ch = (d.get('choices') or [{}])[0].get('delta', {}).get('content')
    if isinstance(ch, str) and ch:
        ct += 1
tot = (done - t0) if done else (time.time() - t0)
ttft = (first - t0) if first else tot
dec_t = tot - ttft
print('TTFT %.3f' % ttft, 'DEC_SEC %.3f' % dec_t, 'CONTENT_TOKENS %d' % ct)
if dec_t > 0.01 and ct > 0:
    print('DECODE_TOK_S %.1f' % (ct / dec_t))
if ttft > 0.01:
    print('PREFILL_TOK_S %.1f' % (8000 / ttft))
