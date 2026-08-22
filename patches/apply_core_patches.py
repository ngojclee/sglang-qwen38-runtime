import re, os

# 1. Patch compressed_tensors.py
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
        print("Patched compressed_tensors.py successfully!")
    else:
        print("compressed_tensors.py already patched or target not found.")

# 2. Patch qwen3_5.py
qwen35_path = "/sgl-workspace/sglang/python/sglang/srt/models/qwen3_5.py"
if os.path.exists(qwen35_path):
    with open(qwen35_path, "r", encoding="utf-8") as f:
        code2 = f.read()

    # A. ALL_DECODER_LAYER_TYPES aliases
    if '"full_attention": Qwen3_5AttentionDecoderLayer,' not in code2:
        code2 = code2.replace(
            '"linear_attention": Qwen3_5LinearDecoderLayer,',
            '"linear_attention": Qwen3_5LinearDecoderLayer,\n    "full_attention": Qwen3_5AttentionDecoderLayer,'
        )
        print("Patched qwen3_5.py ALL_DECODER_LAYER_TYPES full_attention successfully!")

    # B. get_layer prefix
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
    print("Patched qwen3_5.py get_layer via regex!")

    # C. Fix get_model_config_for_expert_location for dense models
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
    print("Patched qwen3_5.py expert location for dense models successfully!")

    # D. EntryClass registration
    if "EntryClass = [Qwen3_5MoeForConditionalGeneration, Qwen3_5ForConditionalGeneration]" in code2:
        code2 = code2.replace(
            "EntryClass = [Qwen3_5MoeForConditionalGeneration, Qwen3_5ForConditionalGeneration]",
            "EntryClass = [Qwen3_5ForCausalLM, Qwen3_5MoeForCausalLM, Qwen3_5MoeForConditionalGeneration, Qwen3_5ForConditionalGeneration]"
        )
        print("Patched qwen3_5.py EntryClass successfully!")
        
    with open(qwen35_path, "w", encoding="utf-8") as f:
        f.write(code2)

print("✅ All Core SGLang Patches Applied!")
