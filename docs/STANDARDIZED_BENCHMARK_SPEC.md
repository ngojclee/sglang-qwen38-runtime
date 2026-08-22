# 🎯 QUY TRÌNH ĐO KIỂM HIỆU NĂNG ĐỒNG NHẤT (UNIFIED BENCHMARK PROTOCOL)
### Dành cho Đội ngũ Kỹ thuật & Tái Hiện Trên Mọi Thế Hệ Máy (Máy A, B, C, D)

---

## 📌 I. MỤC TIÊU VÀ NGUYÊN TẮC
Tài liệu này chuẩn hóa **1 kịch bản đo kiểm thống nhất (Apples-to-Apples Comparison)** để so sánh hiệu năng thực tế giữa các dàn máy GPU (2× RTX 3090 vs 4× RTX 5060 Ti vs 2× RTX 5060 Ti) mà **không phụ thuộc vào cảm tính hay đo đạc rời rạc**.

### 3 Nguyên Tắc Cốt Lõi:
1. **Dùng chung 1 script Python duy nhất (`benchmark_unified.py`)**: Chạy trực tiếp qua cổng OpenAI-compatible API (`/v1/chat/completions`).
2. **Khóa cứng tham số sinh từ**: `temperature=0.0`, `chat_template_kwargs={"enable_thinking": False}` (để loại trừ độ trễ tư duy `<think>` làm sai lệch số token/giây).
3. **Chỉ đo 3 chỉ số thực chiến quan trọng nhất đối với Coding Agent**:
   - **Tốc độ sinh code (Speed - tok/s)**: Prompt cố định 768 tokens output.
   - **Thang ngưỡng Context thực tế (Context Ladder)**: Bắn các mốc `32K ➔ 64K ➔ 100K ➔ 150K ➔ 200K ➔ 262K` để tìm chính xác điểm gãy (OOM / Drop).
   - **Độ chuẩn xác gọi Tool (Tool Calling Extraction)**: Trả về JSON Function Calling hợp lệ trong 1 lượt.

---

## 🧪 II. CHI TIẾT 3 BÀI TEST CHUẨN HÓA

```text
                                       KỊCH BẢN ĐO KIỂM 3 BÀI TEST
                                                    │
             ┌──────────────────────────────────────┼──────────────────────────────────────┐
             ▼                                      ▼                                      ▼
     [TEST 1: SPEED]                       [TEST 2: CONTEXT LADDER]                 [TEST 3: TOOL CALLING]
   Viết thuật toán RB-Tree                Thang nạp ngữ cảnh tăng dần:              Gửi schema công cụ mẫu
   Max: 768 tokens, Temp: 0.0             32K ➔ 64K ➔ 100K ➔ 150K ➔ 200K ➔ 262K     Kiểm tra parse JSON tool_calls
   👉 Đo: Tokens / Giây (tok/s)          👉 Đo: PASS / FAIL & Thời gian nạp        👉 Đo: PASS trong < 1.5 giây
```

---

### 1. ⚡ TEST 1: TỐC ĐỘ SINH TỪ (SPEED & TTFT)
* **Kịch bản**: Yêu cầu mô hình viết thuật toán `Red-Black Tree` hoàn chỉnh bằng Python (insert, delete, search, inorder traversal) kèm docstring chi tiết.
* **Quy tắc đo**: Chạy **2 lần liên tiếp**, lấy kết quả lần thứ 2 (để loại trừ thời gian nạp bộ đệm JIT và khởi tạo ban đầu).
* **Công thức tính**:
  $$\text{Tốc độ (tok/s)} = \frac{\text{Tổng số Completion Tokens}}{\text{Thời gian sinh từ (giây)}}$$

---

### 2. 🧠 TEST 2: THANG NGƯỠNG CONTEXT THỰC TẾ (STEP-LADDER ESCALATION)
* **Kịch bản**: Tạo một tập dữ liệu code ngữ cảnh thực tế (mã nguồn xử lý đồ thị `compute_graph_slice`) và nhân bản theo các khối token chính xác:
  * **Mốc 1**: `32.000 tokens (32K)`
  * **Mốc 2**: `64.000 tokens (64K)`
  * **Mốc 3**: `100.000 tokens (100K)`
  * **Mốc 4**: `150.000 tokens (150K)`
  * **Mốc 5**: `200.000 tokens (200K)`
  * **Mốc 6**: `262.144 tokens (262K - Kịch Trần)`
* **Câu hỏi kiểm tra cuối prompt**: *"Hãy tóm tắt chức năng của hàm compute_graph_slice trên trong 2 dòng ngắn gọn."*
* **Tiêu chuẩn đánh giá**:
  * **`PASS`**: Server nạp thành công, trả về HTTP `200 OK` kèm câu tóm tắt chính xác.
  * **`FAIL / OOM`**: Server báo lỗi `HTTP 500`, hoặc log ghi `KV cache pool is full. Retract requests`, hoặc rớt kết nối socket.

---

### 3. 🛠️ TEST 3: GỌI HÀM & CÔNG CỤ (TOOL CALLING PARSER)
* **Kịch bản**: Gửi câu lệnh *"Tìm tất cả các file có đuôi .py trong thư mục /sgl-workspace"* kèm theo schema tool chuẩn `find_files`.
* **Tiêu chuẩn đánh giá**:
  * **`PASS`**: Parser `qwen3_coder` bóc tách được trường `tool_calls: [{"function": {"name": "find_files", "arguments": "..."}}]`.
  * **`FAIL`**: Trả về `tool_calls: []` hoặc để lộ thẻ XML thô `<tool_call>` ra trường `content`.

---

## 🚀 III. HƯỚNG DẪN CHẠY 1 DÒNG LỆNH TRÊN MÁY BẤT KỲ

Dev chỉ cần tải script `benchmark_unified.py` về máy chủ và chạy:

```bash
# Cài đặt thư viện requests nếu chưa có
pip install requests

# Chạy toàn bộ 3 bài test
python3 scripts/benchmark_unified.py \
  --url http://127.0.0.1:18000/v1 \
  --model Qwen3.8-27B-Uncensored
```

---

## 📋 IV. BẢNG MẪU BÁO CÁO KẾT QUẢ ĐỒNG NHẤT

Khi đo kiểm xong trên bất kỳ cấu hình nào (Máy A, B, C, D hoặc bật/tắt DFlash2), dev chỉ cần điền kết quả vào bảng mẫu sau:

| Máy & Cấu hình | Test 1: Tốc độ Solo | Test 2: Mốc 32K | Test 2: Mốc 64K | Test 2: Mốc 100K | Test 2: Mốc 150K | Test 2: Mốc 262K | Test 3: Tool Call |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Máy D (2× 3090) + DFlash2 ON** | **91.53 tok/s** | ✅ PASS | ✅ PASS | ❌ FAIL (OOM 75K) | ❌ FAIL | ❌ FAIL | ✅ PASS (0.79s) |
| **Máy D (2× 3090) + DFlash2 OFF** | **52.62 tok/s** | ✅ PASS | ✅ PASS | ✅ PASS | ✅ PASS (HiCache) | ✅ PASS (262K) | ✅ PASS (1.05s) |
| **Máy C (4× 5060Ti) + DFlash2 ON** | 🏆 **77.81 tok/s** | ✅ PASS (2.14s) | ✅ PASS (4.12s) | ✅ PASS (6.35s) | ✅ PASS (9.48s) | ✅ PASS (16.92s) | 🏆 ✅ PASS (0.81s) |
| **Máy C (4× 5060Ti) + DFlash2 OFF**| **40.46 tok/s** | ✅ PASS (1.95s) | ✅ PASS (3.82s) | ✅ PASS (5.92s) | ✅ PASS (8.84s) | ✅ PASS (15.42s) | ✅ PASS (1.08s) |
| **Máy B (2× 5060Ti) + DFlash2 ON** | **74.96 tok/s** | ✅ PASS | ❌ FAIL (40.9K) | ❌ FAIL | ❌ FAIL | ❌ FAIL | ✅ PASS (0.85s) |
| **Máy A (2× 5060Ti - vLLM)** | **35.00 tok/s** | ✅ PASS | ✅ PASS | ⚠️ Drop Socket | ❌ FAIL | ❌ FAIL | ⚠️ JSON format |
