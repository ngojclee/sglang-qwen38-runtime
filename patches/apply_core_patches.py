import re, os, torch

print("🚀 Applying Unified SGLang + Qwen 3.8 + DFlash2 Patches...")

# 1. Patch transformers configuration_qwen3_5.py
trans_qwen35 = "/usr/local/lib/python3.12/dist-packages/transformers/models/qwen3_5/configuration_qwen3_5.py"
if os.path.exists(trans_qwen35):
    with open(trans_qwen35, "r", encoding="utf-8") as f:
        code_t = f.read()

    props = """
    @property
    def full_attention_layer_ids(self):
        if hasattr(self, "layers_block_type") and self.layers_block_type:
            return [i for i, t in enumerate(self.layers_block_type) if t in ("attention", "full_attention")]
        interval = getattr(self, "full_attention_interval", 4)
        return [i for i in range(self.num_hidden_layers) if (i + 1) % interval == 0]

    @property
    def linear_attention_layer_ids(self):
        full = set(self.full_attention_layer_ids)
        return [i for i in range(self.num_hidden_layers) if i not in full]

    @property
    def mamba2_cache_params(self):
        import torch
        from sglang.srt.configs.mamba_utils import Mamba2CacheParams, Mamba2StateShape, mamba2_state_dtype
        from sglang.srt.runtime_context import get_parallel

        try:
            tp_size = get_parallel().attn_tp_size
        except Exception:
            tp_size = 1

        try:
            dtype = mamba2_state_dtype(self)
        except Exception:
            dtype = torch.bfloat16

        linear_key_head_dim = getattr(self, "linear_key_head_dim", 128)
        linear_num_key_heads = getattr(self, "linear_num_key_heads", 16)
        linear_value_head_dim = getattr(self, "linear_value_head_dim", 128)
        linear_num_value_heads = getattr(self, "linear_num_value_heads", 16)
        linear_conv_kernel_dim = getattr(self, "linear_conv_kernel_dim", 4)

        key_dim = linear_key_head_dim * linear_num_key_heads
        value_dim = linear_value_head_dim * linear_num_value_heads
        shape = Mamba2StateShape.create(
            tp_world_size=tp_size,
            intermediate_size=value_dim,
            n_groups=linear_num_key_heads,
            num_heads=linear_num_value_heads,
            head_dim=linear_value_head_dim,
            state_size=linear_key_head_dim,
            conv_kernel=linear_conv_kernel_dim,
            conv_shard_groups=[key_dim, key_dim, value_dim],
        )
        return Mamba2CacheParams(
            shape=shape, layers=self.linear_attention_layer_ids, dtype=dtype
        )
"""
    target_q = "class Qwen3_5TextConfig(PreTrainedConfig):"
    if target_q in code_t:
        if "def mamba2_cache_params" not in code_t:
            code_t = code_t.replace(target_q, target_q + props)
            with open(trans_qwen35, "w", encoding="utf-8") as f:
                f.write(code_t)
            print("✅ Patched transformers configuration_qwen3_5.py directly")

# 2. Patch memory_pool.py (_transfer_full_attention_id fallback + set_kv_buffer_prefix_valid for HybridLinearKVPool)
mem_pool_path = "/sgl-workspace/sglang/python/sglang/srt/mem_cache/memory_pool.py"
if os.path.exists(mem_pool_path):
    with open(mem_pool_path, "r", encoding="utf-8") as f:
        code_mp = f.read()

    target_err = 'raise ValueError(\n                f"{layer_id=} not in full attention layers: {self.full_attention_layer_id_mapping.keys()}"\n            )'
    repl_tf = "return layer_id % len(self.full_attention_layer_id_mapping) if self.full_attention_layer_id_mapping else 0"

    if target_err in code_mp:
        code_mp = code_mp.replace(target_err, repl_tf)

    target_hl = "    def move_kv_cache(self, tgt_loc: torch.Tensor, src_loc: torch.Tensor):\n        self.full_kv_pool.move_kv_cache(tgt_loc, src_loc)"
    prefix_valid_method = """    def set_kv_buffer_prefix_valid(
        self,
        layer: RadixAttention,
        loc_2d: torch.Tensor,
        commit_lens: torch.Tensor,
        cache_k: torch.Tensor,
        cache_v: torch.Tensor,
        k_scale: Optional[float] = None,
        v_scale: Optional[float] = None,
        **kwargs,
    ):
        layer_id = self._transfer_full_attention_id(layer.layer_id)
        return self.full_kv_pool.set_kv_buffer_prefix_valid(
            layer=layer,
            loc_2d=loc_2d,
            commit_lens=commit_lens,
            cache_k=cache_k,
            cache_v=cache_v,
            k_scale=k_scale,
            v_scale=v_scale,
            layer_id_override=layer_id,
            **kwargs,
        )

    def move_kv_cache(self, tgt_loc: torch.Tensor, src_loc: torch.Tensor):
        self.full_kv_pool.move_kv_cache(tgt_loc, src_loc)"""

    if target_hl in code_mp:
        code_mp = code_mp.replace(target_hl, prefix_valid_method, 1)

    with open(mem_pool_path, "w", encoding="utf-8") as f:
        f.write(code_mp)
    print("✅ Patched memory_pool.py (_transfer_full_attention_id + set_kv_buffer_prefix_valid for HybridLinearKVPool)")

# 3. Patch hybrid_linear_attn_backend.py (Support draft/pure attention models without mixed_qkv in all methods)
hybrid_backend_path = "/sgl-workspace/sglang/python/sglang/srt/layers/attention/hybrid_linear_attn_backend.py"
if os.path.exists(hybrid_backend_path):
    with open(hybrid_backend_path, "r", encoding="utf-8") as f:
        code_hb = f.read()

    pat_is_full = r'def _is_full_attn\([\s\S]*?return layer_id in self\.full_attn_layers'
    repl_is_full = """def _is_full_attn(
        self, layer: Optional[RadixAttention], layer_id: Optional[int] = None, mixed_qkv: Optional[torch.Tensor] = None
    ) -> bool:
        if mixed_qkv is None:
            return True
        if layer is not None:
            layer_id = layer.layer_id
        assert layer_id is not None, "either layer or layer_id must be provided"
        return layer_id in self.full_attn_layers"""

    if "_is_full_attn" in code_hb:
        code_hb = re.sub(pat_is_full, repl_is_full, code_hb, count=1)
        code_hb = code_hb.replace(
            "self._is_full_attn(layer, kwargs.get(\"layer_id\"))",
            "self._is_full_attn(layer, kwargs.get(\"layer_id\"), mixed_qkv)"
        )
        with open(hybrid_backend_path, "w", encoding="utf-8") as f:
            f.write(code_hb)
        print("✅ Patched hybrid_linear_attn_backend.py (_is_full_attn draft fallback across all methods)")

# 4. Patch hybrid_arch.py
hybrid_arch_path = "/sgl-workspace/sglang/python/sglang/srt/configs/hybrid_arch.py"
if os.path.exists(hybrid_arch_path):
    with open(hybrid_arch_path, "r", encoding="utf-8") as f:
        code_h = f.read()

    pattern_h = r'def hybrid_gdn_config\(model_config: ModelConfig\):[\s\S]*?config = model_config\.hf_config\.get_text_config\(\)[\s\S]*?if isinstance\('
    repl_h = """def hybrid_gdn_config(model_config: ModelConfig):
    config = model_config.hf_config.get_text_config()
    if getattr(config, "model_type", "") in ("qwen3_5", "qwen3_5_text", "qwen3_next", "qwen3") or isinstance("""
    
    if "getattr(config, \"model_type\", \"\")" not in code_h:
        code_h = re.sub(pattern_h, repl_h, code_h, count=1)

    with open(hybrid_arch_path, "w", encoding="utf-8") as f:
        f.write(code_h)
    print("✅ Patched hybrid_arch.py")

# 5. Patch kv_cache_configurator.py
kv_config_path = "/sgl-workspace/sglang/python/sglang/srt/mem_cache/kv_cache_configurator.py"
if os.path.exists(kv_config_path):
    with open(kv_config_path, "r", encoding="utf-8") as f:
        code_k = f.read()

    # Guard self.server_args.max_mamba_cache_size // ratio
    target_division = "max_num_reqs, self.server_args.max_mamba_cache_size // ratio"
    repl_division = "max_num_reqs, (self.server_args.max_mamba_cache_size // ratio) if self.server_args.max_mamba_cache_size is not None else max_num_reqs"
    if target_division in code_k:
        code_k = code_k.replace(target_division, repl_division)

    with open(kv_config_path, "w", encoding="utf-8") as f:
        f.write(code_k)
    print("✅ Patched kv_cache_configurator.py")

# 6. Patch model_config.py (get_hybrid_layer_ids for Qwen 3.5 / 3.8)
model_config_path = "/sgl-workspace/sglang/python/sglang/srt/configs/model_config.py"
if os.path.exists(model_config_path):
    with open(model_config_path, "r", encoding="utf-8") as f:
        code_mc = f.read()

    qwen_hybrid_branch = """    elif any(arch in ("Qwen3_5ForCausalLM", "Qwen3_5MoeForCausalLM", "Qwen3NextForCausalLM") for arch in model_architectures) or getattr(hf_text_config, "model_type", "") in ("qwen3_5", "qwen3_5_text", "qwen3_next", "qwen3"):
        layer_types = getattr(hf_text_config, "layers_block_type", None) or getattr(hf_text_config, "layer_types", None)
        if layer_types is not None:
            swa_attention_layer_ids = [i for i, x in enumerate(layer_types) if x in ("linear_attention", "sliding_attention")]
            full_attention_layer_ids = [i for i, x in enumerate(layer_types) if x in ("attention", "full_attention")]
        else:
            interval = getattr(hf_text_config, "full_attention_interval", 4)
            swa_attention_layer_ids = [i for i in range(num_hidden_layers) if (i + 1) % interval != 0]
            full_attention_layer_ids = [i for i in range(num_hidden_layers) if (i + 1) % interval == 0]"""

    target_mc = "    if \"Llama4ForConditionalGeneration\" in model_architectures:"
    if target_mc in code_mc and "Qwen3_5ForCausalLM" not in code_mc:
        code_mc = code_mc.replace(target_mc, target_mc + "\n" + qwen_hybrid_branch, 1)
        with open(model_config_path, "w", encoding="utf-8") as f:
            f.write(code_mc)
        print("✅ Patched model_config.py (get_hybrid_layer_ids for Qwen 3.5/3.8)")

# 7. Patch compressed_tensors.py
file_path = "/sgl-workspace/sglang/python/sglang/srt/layers/quantization/compressed_tensors/compressed_tensors.py"
if os.path.exists(file_path):
    with open(file_path, "r", encoding="utf-8") as f:
        code = f.read()

    target = 'packed_modules_mapping = config.get("packed_modules_mapping", {})'
    replacement = """packed_modules_mapping = config.get("packed_modules_mapping", {})
        if not packed_modules_mapping:
            packed_modules_mapping = {
                "qkv_proj": ["q_proj", "k_proj", "v_proj"],
                "gate_up_proj": ["gate_proj", "up_proj"],
                "in_proj_qkvz": ["in_proj_qkv", "in_proj_z"],
                "in_proj_ba": ["in_proj_b", "in_proj_a"],
            }"""

    if target in code and replacement not in code:
        code = code.replace(target, replacement, 1)
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(code)
        print("✅ Patched compressed_tensors.py")

# 8. Patch qwen3_5.py (Full CausalLM with LMHead & LogitsProcessor)
qwen35_path = "/sgl-workspace/sglang/python/sglang/srt/models/qwen3_5.py"
if os.path.exists(qwen35_path):
    with open(qwen35_path, "r", encoding="utf-8") as f:
        code2 = f.read()

    # A. Imports
    if "from sglang.srt.layers.logits_processor import LogitsProcessor" not in code2:
        code2 = "from sglang.srt.layers.logits_processor import LogitsProcessor\nfrom sglang.srt.layers.vocab_parallel_embedding import ParallelLMHead\n" + code2

    # B. ALL_DECODER_LAYER_TYPES aliases
    if '"full_attention": Qwen3_5AttentionDecoderLayer,' not in code2:
        code2 = code2.replace(
            '"linear_attention": Qwen3_5LinearDecoderLayer,',
            '"linear_attention": Qwen3_5LinearDecoderLayer,\n    "full_attention": Qwen3_5AttentionDecoderLayer,'
        )

    # C. get_layer prefix
    pattern = r'def get_layer\(idx: int, prefix: str\):[\s\S]*?return layer_class\('
    new_sub = """def get_layer(idx: int, prefix: str):
            layer_types_list = getattr(config, "layers_block_type", None) or getattr(config, "layer_types", None)
            if layer_types_list is not None:
                layer_type = layer_types_list[idx]
            else:
                layer_type = "attention" if (idx + 1) % config.full_attention_interval == 0 else "linear_attention"
            layer_class = ALL_DECODER_LAYER_TYPES[layer_type]
            if layer_type in ("attention", "full_attention"):
                prefix = add_prefix("self_attn", prefix)
            else:
                prefix = add_prefix("linear_attn", prefix)
            return layer_class("""
    code2 = re.sub(pattern, new_sub, code2, count=1)

    # D. Init LM Head and LogitsProcessor in Qwen3_5ForCausalLM
    target_norm = """        # Final normalization
        if self.pp_group.is_last_rank:
            self.norm = GemmaRMSNorm(config.hidden_size, eps=config.rms_norm_eps)
        else:
            self.norm = PPMissingLayer()

        self.layers_to_capture = []"""

    repl_norm = """        # Final normalization
        if self.pp_group.is_last_rank:
            self.norm = GemmaRMSNorm(config.hidden_size, eps=config.rms_norm_eps)
            if self.pp_group.world_size == 1 and getattr(config, "tie_word_embeddings", False):
                self.lm_head = self.embed_tokens
            else:
                self.lm_head = ParallelLMHead(
                    config.vocab_size,
                    config.hidden_size,
                    quant_config=quant_config,
                    prefix=add_prefix("lm_head", prefix),
                )
        else:
            self.norm = PPMissingLayer()
            self.lm_head = PPMissingLayer()

        self.logits_processor = LogitsProcessor(config)
        self.capture_aux_hidden_states = False
        self.layers_to_capture = []"""

    if target_norm in code2:
        code2 = code2.replace(target_norm, repl_norm, 1)

    # E. Update set_dflash_layers_to_capture
    target_dflash_cap = """    def set_dflash_layers_to_capture(self, layers_to_capture: list[int]):
        self.layers_to_capture = layers_to_capture
        for layer_id in self.layers_to_capture:
            setattr(self.layers[layer_id], "_is_layer_to_capture", True)"""

    repl_dflash_cap = """    def set_dflash_layers_to_capture(self, layers_to_capture: list[int]):
        self.capture_aux_hidden_states = True
        self.layers_to_capture = layers_to_capture
        for layer_id in self.layers_to_capture:
            setattr(self.layers[layer_id], "_is_layer_to_capture", True)"""

    if target_dflash_cap in code2:
        code2 = code2.replace(target_dflash_cap, repl_dflash_cap, 1)

    # F. Update Qwen3_5ForCausalLM.forward return to use LogitsProcessor
    target_forward_end = """        if len(aux_hidden_states) == 0:
            return hidden_states

        return hidden_states, aux_hidden_states"""

    repl_forward_end = """        aux_states = aux_hidden_states if (getattr(self, "capture_aux_hidden_states", False) and len(aux_hidden_states) > 0) else None

        if not self.pp_group.is_last_rank:
            return hidden_states

        return self.logits_processor(
            input_ids,
            hidden_states,
            self.lm_head,
            forward_batch,
            aux_states,
        )"""

    if target_forward_end in code2:
        code2 = code2.replace(target_forward_end, repl_forward_end, 1)

    # G. Fix get_model_config_for_expert_location for dense models
    pattern_expert = r'@classmethod\s+def get_model_config_for_expert_location\(cls, config\):[\s\S]*?return ModelConfigForExpertLocation\([\s\S]*?\)'
    sub_expert = """@classmethod
    def get_model_config_for_expert_location(cls, config):
        if not getattr(config, "num_experts", None):
            return None
        return ModelConfigForExpertLocation(
            num_layers=config.num_hidden_layers,
            num_logical_experts=config.num_experts,
            num_groups=None,
        )"""
    code2 = re.sub(pattern_expert, sub_expert, code2, count=1)

    # H. EntryClass registration
    if "EntryClass = [Qwen3_5MoeForConditionalGeneration, Qwen3_5ForConditionalGeneration]" in code2:
        code2 = code2.replace(
            "EntryClass = [Qwen3_5MoeForConditionalGeneration, Qwen3_5ForConditionalGeneration]",
            "EntryClass = [Qwen3_5ForCausalLM, Qwen3_5MoeForCausalLM, Qwen3_5MoeForConditionalGeneration, Qwen3_5ForConditionalGeneration]"
        )
        
    with open(qwen35_path, "w", encoding="utf-8") as f:
        f.write(code2)
    print("✅ Patched qwen3_5.py (Full CausalLM with LMHead & LogitsProcessor)")

# 9. Patch compressed_tensors_wNa16.py (Marlin repack pad for linear attention 48 dim)
wNa16_path = "/sgl-workspace/sglang/python/sglang/srt/layers/quantization/compressed_tensors/schemes/compressed_tensors_wNa16.py"
if os.path.exists(wNa16_path):
    with open(wNa16_path, "r", encoding="utf-8") as f:
        code3 = f.read()

    old_part = """        def transform_w_q(x):
            assert isinstance(x, BasevLLMParameter)
            permute_param_layout_(x, input_dim=0, output_dim=1, packed_dim=0)
            x.data = gptq_marlin_repack(
                x.data.contiguous(),
                perm=layer.g_idx_sort_indices,
                size_k=c.partition_weight_shape[0],
                size_n=c.partition_weight_shape[1],
                num_bits=c.weight_type.size_bits,
            )
            return x

        def transform_w_s(x):
            assert isinstance(x, BasevLLMParameter)
            permute_param_layout_(x, input_dim=0, output_dim=1)
            x.data = marlin_permute_scales(
                x.data.contiguous(),
                size_k=c.partition_weight_shape[0],
                size_n=c.partition_weight_shape[1],
                group_size=c.group_size,
            )
            return x"""

    new_part = """        size_k = c.partition_weight_shape[0]
        size_n = c.partition_weight_shape[1]
        pad_n = (64 - (size_n % 64)) % 64
        size_n_padded = size_n + pad_n
        self.pad_n = pad_n
        self.orig_size_n = size_n
        self.size_n_padded = size_n_padded

        def transform_w_q(x):
            assert isinstance(x, BasevLLMParameter)
            permute_param_layout_(x, input_dim=0, output_dim=1, packed_dim=0)
            data = x.data
            if pad_n > 0:
                data = torch.nn.functional.pad(data, (0, pad_n), value=0)
            x.data = gptq_marlin_repack(
                data.contiguous(),
                perm=layer.g_idx_sort_indices,
                size_k=size_k,
                size_n=size_n_padded,
                num_bits=c.weight_type.size_bits,
            )
            return x

        def transform_w_s(x):
            assert isinstance(x, BasevLLMParameter)
            permute_param_layout_(x, input_dim=0, output_dim=1)
            data = x.data
            if pad_n > 0:
                data = torch.nn.functional.pad(data, (0, pad_n), value=1.0)
            x.data = marlin_permute_scales(
                data.contiguous(),
                size_k=size_k,
                size_n=size_n_padded,
                group_size=c.group_size,
            )
            return x"""

    if old_part in code3:
        code3 = code3.replace(old_part, new_part, 1)

    old_apply = """        return apply_gptq_marlin_linear(
            input=x,
            weight=w_q,
            weight_scale=w_s,
            weight_zp=w_zp,  # type: ignore
            g_idx=w_gidx,  # type: ignore
            g_idx_sort_indices=layer.g_idx_sort_indices,
            workspace=self.workspace,
            wtype=c.weight_type,
            input_size_per_partition=c.partition_weight_shape[0],
            output_size_per_partition=c.partition_weight_shape[1],
            is_k_full=self.is_k_full,
            bias=bias,
        )"""

    new_apply = """        pad_n = getattr(self, "pad_n", 0)
        size_n_padded = getattr(self, "size_n_padded", c.partition_weight_shape[1])
        orig_size_n = getattr(self, "orig_size_n", c.partition_weight_shape[1])

        out = apply_gptq_marlin_linear(
            input=x,
            weight=w_q,
            weight_scale=w_s,
            weight_zp=w_zp,  # type: ignore
            g_idx=w_gidx,  # type: ignore
            g_idx_sort_indices=layer.g_idx_sort_indices,
            workspace=self.workspace,
            wtype=c.weight_type,
            input_size_per_partition=c.partition_weight_shape[0],
            output_size_per_partition=size_n_padded,
            is_k_full=self.is_k_full,
            bias=None if pad_n > 0 else bias,
        )
        if pad_n > 0:
            out = out[..., :orig_size_n]
            if bias is not None:
                out.add_(bias)
        return out"""

    if old_apply in code3:
        code3 = code3.replace(old_apply, new_apply, 1)

    with open(wNa16_path, "w", encoding="utf-8") as f:
        f.write(code3)
    print("✅ Patched compressed_tensors_wNa16.py")

# 10. Patch dflash.py (DFlash2DraftModel class registration)
dflash_path = "/sgl-workspace/sglang/python/sglang/srt/models/dflash.py"
if os.path.exists(dflash_path):
    with open(dflash_path, "r", encoding="utf-8") as f:
        code4 = f.read()

    if "class DFlash2DraftModel" not in code4:
        code4 = code4.replace(
            "EntryClass = [DFlashDraftModel, DFlashLagunaForCausalLM]",
            "class DFlash2DraftModel(DFlashDraftModel):\n    pass\n\n\nEntryClass = [DFlashDraftModel, DFlash2DraftModel, DFlashLagunaForCausalLM]"
        )
        with open(dflash_path, "w", encoding="utf-8") as f:
            f.write(code4)
        print("✅ Patched dflash.py (DFlash2DraftModel)")

print("✨ All Unified SGLang Patches Applied Successfully!")
