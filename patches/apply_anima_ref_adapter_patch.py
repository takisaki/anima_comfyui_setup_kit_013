#!/usr/bin/env python3
"""给 ComfyUI-Anima-Ref-Adapter 打补丁，让 Anima LLLite 与 Ref Adapter 能同时使用。

问题：
    comfy/ldm/cosmos/predict2.py 的 MiniTrainDIT._forward 里才会
        transformer_options["model_patch_data"] = {}
        for patch in patches["post_input"]: ...
    Anima LLLite 的 cond_emb 就在 post_input 阶段算出来。
    而 Ref Adapter 的 _asym_forward / _ref_forward 整个替换了 _forward，
    这两行不会执行，于是 LLLite 的 attention patch 抛
        KeyError: 'model_patch_data'

补丁：
    新增 _run_post_input()（照抄 _forward 里的语义），
    并在 _asym_forward / _ref_forward 的 block 循环前调用。

可重复执行：检测到 _run_post_input 就直接跳过。上游更新覆盖后重跑一次即可。

用法:
    python3 apply_anima_ref_adapter_patch.py [/root/ComfyUI]
"""
import os
import sys

HELPER = '''def _run_post_input(x, x_emb, transformer_options):
    """Run the 'post_input' model patches that MiniTrainDIT._forward runs (Anima LLLite and friends)."""
    patches = transformer_options.get("patches", {})
    if "post_input" not in patches:
        return x_emb, transformer_options
    transformer_options = transformer_options.copy()
    transformer_options["model_patch_data"] = {}
    for patch in patches["post_input"]:
        out = patch({"img": x_emb, "x": x, "transformer_options": transformer_options})
        x_emb = out["img"]
    return x_emb, transformer_options


'''

ANCHOR_ASYM = "def _asym_forward(dm, x, timesteps, context, ref_kv, transformer_options):"
EDITS = [
    (
        "    xt, rope_t, emb_t, adaln_t = _frame_embed(dm, x[:, :, :1], 0, 0, 0, sigma)\n    batch = xt.shape[0]",
        "    xt, rope_t, emb_t, adaln_t = _frame_embed(dm, x[:, :, :1], 0, 0, 0, sigma)\n"
        "    xt, transformer_options = _run_post_input(x, xt, transformer_options)\n    batch = xt.shape[0]",
    ),
    (
        '    t_emb = dm.t_embedding_norm(t_emb)\n'
        '    kwargs = {"rope_emb_L_1_1_D": rope.unsqueeze(1).unsqueeze(0), "adaln_lora_B_T_3D": adaln,\n'
        '              "extra_per_block_pos_emb": extra, "transformer_options": transformer_options}',
        '    t_emb = dm.t_embedding_norm(t_emb)\n'
        "    x_emb, transformer_options = _run_post_input(x, x_emb, transformer_options)\n"
        '    kwargs = {"rope_emb_L_1_1_D": rope.unsqueeze(1).unsqueeze(0), "adaln_lora_B_T_3D": adaln,\n'
        '              "extra_per_block_pos_emb": extra, "transformer_options": transformer_options}',
    ),
    (ANCHOR_ASYM, HELPER + ANCHOR_ASYM),
]


def main() -> int:
    comfy = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("COMFY", "/root/ComfyUI")
    path = os.path.join(comfy, "custom_nodes", "ComfyUI-Anima-Ref-Adapter", "__init__.py")
    if not os.path.isfile(path):
        print("[patch] 未装 ComfyUI-Anima-Ref-Adapter，跳过")
        return 0
    with open(path, encoding="utf-8") as fh:
        src = fh.read().replace("\r\n", "\n")
    if "_run_post_input" in src:
        print("[patch] 已经打过补丁，跳过")
        return 0
    for old, new in EDITS:
        hits = src.count(old)
        if hits != 1:
            print("[patch] 锚点命中 %d 次（应为 1），上游源码可能已变更：" % hits)
            print("        " + old.splitlines()[0].strip())
            return 2
        src = src.replace(old, new, 1)
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(src)
    print("[patch] 已打补丁: " + path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
