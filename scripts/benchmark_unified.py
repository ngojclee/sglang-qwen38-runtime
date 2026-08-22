#!/usr/bin/env python3
"""
=============================================================================
🚀 BỘ QUY CHUẨN ĐO KIỂM HIỆU NĂNG ĐỒNG NHẤT (UNIFIED BENCHMARK PROTOCOL)
Dành cho SGLang / vLLM trên tất cả các thế hệ máy: Máy A, B, C, D
=============================================================================
Cách sử dụng:
  python3 benchmark_unified.py --url http://127.0.0.1:18000/v1 --model Qwen3.8-27B-Uncensored
"""

import argparse
import json
import time
import requests
import sys

def run_test_1_speed(base_url, model_name, runs=2):
    print("\n" + "="*70)
    print("⚡ TEST 1: TỐC ĐỘ SINH TỪ (SPEED & FIRST TOKEN LATENCY)")
    print("="*70)
    print(f"👉 Target Endpoint: {base_url}/chat/completions")
    print(f"👉 Model ID:       {model_name}")
    print(f"👉 Số lần chạy:    {runs} lần (lấy kết quả lần 2 để loại trừ JIT warmup)")

    payload = {
        "model": model_name,
        "messages": [
            {
                "role": "user",
                "content": (
                    "Hãy viết một chương trình Python hoàn chỉnh cài đặt thuật toán Red-Black Tree "
                    "gồm các hàm insert, delete, search, inorder traversal. "
                    "Kèm docstring giải thích chi tiết từng hàm."
                )
            }
        ],
        "max_tokens": 768,
        "temperature": 0.0,
        "chat_template_kwargs": {"enable_thinking": False}
    }

    results = []
    for i in range(1, runs + 1):
        print(f"\n--- Lần chạy {i}/{runs} ---")
        t0 = time.time()
        try:
            resp = requests.post(f"{base_url}/chat/completions", json=payload, timeout=120)
            t1 = time.time()
            if resp.status_code == 200:
                data = resp.json()
                usage = data.get("usage", {})
                completion_tokens = usage.get("completion_tokens", 0)
                prompt_tokens = usage.get("prompt_tokens", 0)
                elapsed = t1 - t0
                tok_s = completion_tokens / elapsed if elapsed > 0 else 0
                results.append((tok_s, elapsed, completion_tokens))
                print(f"✅ Thành công!")
                print(f"   • Thời gian tạo:     {elapsed:.2f} giây")
                print(f"   • Số token sinh ra:  {completion_tokens} tokens")
                print(f"   • Tốc độ sinh từ:    {tok_s:.2f} tokens/giây 🚀")
            else:
                print(f"❌ Lỗi HTTP {resp.status_code}: {resp.text}")
                return None
        except Exception as e:
            print(f"❌ Ngoại lệ kết nối: {e}")
            return None

    final_tok_s, final_time, final_tokens = results[-1]
    print(f"\n🏆 KẾT QUẢ TEST 1 CHÍNH THỨC: {final_tok_s:.2f} tok/s (Thời gian: {final_time:.2f}s, Tokens: {final_tokens})")
    return final_tok_s

def run_test_2_context_ladder(base_url, model_name):
    print("\n" + "="*70)
    print("🧠 TEST 2: THANG NGƯỠNG CONTEXT THỰC TẾ (STEP-LADDER ESCALATION)")
    print("="*70)
    print("Mục tiêu: Gửi các khối context tăng dần để xác định chính xác điểm chạm trần VRAM.")
    
    # 1 đoạn văn bản mẫu chuẩn (~200 tokens)
    seed_block = (
        "def compute_graph_slice(nodes, edges, max_depth=5, prune_unreachable=True):\n"
        "    visited = set()\n"
        "    subgraph = {'nodes': [], 'edges': []}\n"
        "    queue = [(node_id, 0) for node_id in nodes]\n"
        "    while queue:\n"
        "        current, depth = queue.pop(0)\n"
        "        if depth > max_depth or current in visited:\n"
        "            continue\n"
        "        visited.add(current)\n"
        "        subgraph['nodes'].append(current)\n"
        "        for neighbor, weight in edges.get(current, []):\n"
        "            subgraph['edges'].append((current, neighbor, weight))\n"
        "            if neighbor not in visited:\n"
        "                queue.append((neighbor, depth + 1))\n"
        "    return subgraph\n\n"
    )

    ladder_steps = [
        ("Tier 1 (32K Tokens)", 160),    # ~32k tokens
        ("Tier 2 (64K Tokens)", 320),    # ~64k tokens
        ("Tier 3 (100K Tokens)", 500),   # ~100k tokens
        ("Tier 4 (150K Tokens)", 750),   # ~150k tokens
        ("Tier 5 (200K Tokens)", 1000),  # ~200k tokens
        ("Tier 6 (262K Tokens)", 1310),  # ~262k tokens
    ]

    report = []
    for name, repeat_count in ladder_steps:
        context_body = seed_block * repeat_count
        prompt_text = (
            f"Dưới đây là một phần mã nguồn của hệ thống:\n\n{context_body}\n\n"
            "Câu hỏi kiểm tra: Hãy tóm tắt chức năng của hàm compute_graph_slice trên trong 2 dòng ngắn gọn."
        )

        payload = {
            "model": model_name,
            "messages": [{"role": "user", "content": prompt_text}],
            "max_tokens": 64,
            "temperature": 0.0,
            "chat_template_kwargs": {"enable_thinking": False}
        }

        print(f"\n👉 Đang kiểm tra: {name} (khoảng {repeat_count * 200:,} tokens)...")
        t0 = time.time()
        try:
            resp = requests.post(f"{base_url}/chat/completions", json=payload, timeout=300)
            t1 = time.time()
            if resp.status_code == 200:
                data = resp.json()
                prompt_tokens = data.get("usage", {}).get("prompt_tokens", 0)
                elapsed = t1 - t0
                ans = data["choices"][0]["message"]["content"].strip().replace("\n", " ")[:80]
                print(f"   ✅ PASS! (Prompt thực tế: {prompt_tokens:,} tokens | Nạp trong: {elapsed:.2f}s)")
                print(f"   💬 Phản hồi: {ans}...")
                report.append((name, prompt_tokens, "✅ PASS", f"{elapsed:.2f}s"))
            else:
                print(f"   ❌ FAIL! (HTTP {resp.status_code}: {resp.text[:150]})")
                report.append((name, "-", f"❌ FAIL ({resp.status_code})", "-"))
                print("   ⚠️ Đã chạm trần bộ nhớ hoặc timeout! Dừng thang đo.")
                break
        except Exception as e:
            print(f"   ❌ EXCEPTION / DROP: {e}")
            report.append((name, "-", "❌ DROP / OOM", "-"))
            break

    print("\n" + "="*70)
    print("📊 BẢNG TỔNG KẾT TEST 2 (CONTEXT THỰC TẾ):")
    print(f"{'Mốc Kiểm Thử':<25} | {'Tokens Thực':<15} | {'Trạng Thái':<15} | {'Thời Gian Nạp':<15}")
    print("-" * 75)
    for step, toks, status, duration in report:
        print(f"{step:<25} | {str(toks):<15} | {status:<15} | {duration:<15}")
    print("="*70)

def run_test_3_tool_calling(base_url, model_name):
    print("\n" + "="*70)
    print("🛠️ TEST 3: GỌI HÀM & CÔNG CỤ (TOOL CALLING & SCHEMA EXTRACTION)")
    print("="*70)

    payload = {
        "model": model_name,
        "messages": [
            {"role": "user", "content": "Tìm tất cả các file có đuôi .py trong thư mục /sgl-workspace."}
        ],
        "tools": [
            {
                "type": "function",
                "function": {
                    "name": "find_files",
                    "description": "Tìm kiếm file theo đường dẫn và phần mở rộng",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "directory": {"type": "string", "description": "Thư mục cần tìm"},
                            "extension": {"type": "string", "description": "Đuôi file, ví dụ .py, .md"}
                        },
                        "required": ["directory", "extension"]
                    }
                }
            }
        ],
        "tool_choice": "auto"
    }

    t0 = time.time()
    resp = requests.post(f"{base_url}/chat/completions", json=payload, timeout=60)
    t1 = time.time()

    if resp.status_code == 200:
        data = resp.json()
        msg = data["choices"][0]["message"]
        tc = msg.get("tool_calls", [])
        if tc and tc[0]["function"]["name"] == "find_files":
            print(f"✅ PASS! Tool Calling hợp lệ trong {t1 - t0:.2f}s!")
            print(f"   • Function:  {tc[0]['function']['name']}")
            print(f"   • Arguments: {tc[0]['function']['arguments']}")
            return True
        else:
            print("⚠️ Warning: Không bóc tách được tool_calls, nội dung trả về:", msg.get("content"))
            return False
    else:
        print(f"❌ Lỗi HTTP {resp.status_code}: {resp.text}")
        return False

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Unified LLM Benchmark Protocol")
    parser.add_argument("--url", default="http://127.0.0.1:18000/v1", help="API Base URL")
    parser.add_argument("--model", default="Qwen3.8-27B-Uncensored", help="Model Name")
    args = parser.parse_args()

    print("==================================================================")
    print("🚀 BẮT ĐẦU CHƯƠNG TRÌNH ĐO KIỂM HIỆU NĂNG ĐỒNG NHẤT")
    print(f"URL:   {args.url}")
    print(f"Model: {args.model}")
    print("==================================================================")

    run_test_1_speed(args.url, args.model)
    run_test_2_context_ladder(args.url, args.model)
    run_test_3_tool_calling(args.url, args.model)
