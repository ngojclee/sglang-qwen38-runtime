# ========================================================
# SGLang Qwen3.8 Optimized Runtime for NVIDIA RTX 3090 / 4090
# Base: SGLang v0.5.16 + Hybrid GDN Triton Patch + DFlash2 Fix
# ========================================================

FROM lmsysorg/sglang:v0.5.16.post1-cu124

LABEL maintainer="ngojclee"
LABEL description="Production SGLang runtime with official GDN unpack patch and DFlash2 speculative decoding for Qwen3.8-27B"

WORKDIR /sgl-workspace

# Copy patch file
COPY patches/sglang_qwen38_working.patch /tmp/sglang_qwen38_working.patch

# Apply patch to SGLang repository / python library
RUN if [ -d "/sgl-workspace/sglang" ]; then \
        cd /sgl-workspace/sglang && git apply /tmp/sglang_qwen38_working.patch || patch -p1 < /tmp/sglang_qwen38_working.patch ; \
    else \
        SITE_PKG=$(python3 -c "import sglang, os; print(os.path.dirname(os.path.dirname(sglang.__file__)))") && \
        cd "$SITE_PKG" && patch -p4 < /tmp/sglang_qwen38_working.patch ; \
    fi && rm /tmp/sglang_qwen38_working.patch

# Copy configuration profiles and scripts
COPY configs/ /etc/sglang/configs/
COPY scripts/ /opt/sglang-scripts/
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /opt/sglang-scripts/*.sh /usr/local/bin/entrypoint.sh

ENV PYTHONUNBUFFERED=1
ENV NCCL_P2P_DISABLE=1
ENV NCCL_IB_DISABLE=1

EXPOSE 18000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["--config", "/etc/sglang/configs/sglang_dflash2_fast.conf"]
