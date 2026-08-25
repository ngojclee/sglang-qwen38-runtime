# Thêm Qwen3.8-9B-Distill vào Codex model catalog

File: `C:\Users\ngocl\.codex\model_catalog.json` (array `models`)

## Block JSON cần thêm (phân biệt với Qwen3.8-27B-Uncensored)

```json
{
  "slug": "Qwen3.8-9B-Distill",
  "display_name": "Qwen3.8 9B Distill Fast",
  "description": "Qwen3.8-9B-Distill BF16 served by vLLM TP=2 through CLIProxyAPI (fast agent/scraper, 262K context).",
  "context_window": 262144,
  "max_context_window": 262144,
  "effective_context_window_percent": 95,
  "auto_compact_token_limit": 240000,
  "max_output_tokens": 32768,
  "default_reasoning_level": "medium",
  "supports_reasoning_summaries": true,
  "default_reasoning_summary": "auto",
  "input_modalities": ["text", "image"],
  "supports_parallel_tool_calls": true,
  "visibility": "list",
  "priority": 1017
}
```

> ⚠️ **VISION: CÓ** (config-level, MEASURED từ HF config: image_token_id 248056, video_token_id 248057, vision_config hidden 1152/patch16, model_type qwen3_5 — đúng Qwen3.5 vision-language). vLLM load Qwen3VL processors. **Chưa test image thật** (máy J outbid) — UNVERIFIED cho image inference; bật input_modalities image theo config.

## Đối chiếu với 27B hiện có

| Field | 27B (có sẵn) | 9B (thêm) |
|---|---|---|
| slug | `Qwen3.8-27B-Uncensored` | `Qwen3.8-9B-Distill` |
| display_name | Qwen3.8 27B Uncensored | Qwen3.8 9B Distill Fast |
| context_window | 200000 | 262144 |
| max_context_window | 262144 | 262144 |
| effective_context_window_percent | 85 | 95 |
| auto_compact_token_limit | 180000 | 240000 |
| input_modalities | text, image | text |
| priority | 1016 | 1017 |

## Ghi chú deploy

- Served model name trên vLLM = `Qwen3.8-9B-Distill` (bootstrap `MODEL_VERSION=9b`)
- CPA provider trỏ `http://vast-gateway:18000/v1` (leader) — model name truyền qua CPA đúng slug
- Chỉ dùng cho agent/scraper/coding tốc độ cao; suy luận phức tạp → vẫn dùng 27B
- REAL MAX CONTEXT đo được: ≥255,668 tokens (262,144 config)
