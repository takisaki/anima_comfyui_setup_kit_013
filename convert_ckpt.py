# 把 ComfyUI 的 .ckpt 单文件底模转成 .safetensors（避免 pickle 风险，也省一点空间）
import os, sys

COMFY = os.environ.get("COMFY", "/root/ComfyUI")
sys.path.insert(0, COMFY)

from comfy.utils import load_torch_file
from safetensors.torch import save_file

src = os.path.join(COMFY, "models/checkpoints/sd-v1-5-inpainting.ckpt")
dst = os.path.join(COMFY, "models/checkpoints/sd-v1-5-inpainting.safetensors")

if not os.path.isfile(src):
    print("没有 .ckpt，跳过")
    sys.exit(0)

print("读取", src)
sd = load_torch_file(src)
keys = [k for k in sd if hasattr(sd[k], "shape")]
print("张量数:", len(keys))
tmp = dst + ".part"
save_file({k: sd[k] for k in keys}, tmp, metadata={"format": "pt"})
os.replace(tmp, dst)
print("写入", dst, os.path.getsize(dst) // 1000000, "MB")
