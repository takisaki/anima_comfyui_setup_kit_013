# 把 .ckpt 底模转成 .safetensors（避免 pickle 风险，也省一点空间）
# 当前模型清单里没有 .ckpt，正常部署用不到；留着方便以后加自己的底模。
# 用法: python convert_ckpt.py <输入.ckpt> [输出.safetensors]
import os, sys

if len(sys.argv) < 2:
    print("用法: python convert_ckpt.py <输入.ckpt> [输出.safetensors]")
    sys.exit(1)

COMFY = os.environ.get("COMFY", "/root/ComfyUI")
sys.path.insert(0, COMFY)

from comfy.utils import load_torch_file
from safetensors.torch import save_file

src = sys.argv[1]
dst = sys.argv[2] if len(sys.argv) > 2 else os.path.splitext(src)[0] + ".safetensors"

if not os.path.isfile(src):
    print("找不到", src)
    sys.exit(1)

print("读取", src)
sd = load_torch_file(src)
keys = [k for k in sd if hasattr(sd[k], "shape")]
print("张量数:", len(keys))
tmp = dst + ".part"
save_file({k: sd[k] for k in keys}, tmp, metadata={"format": "pt"})
os.replace(tmp, dst)
print("写入", dst, os.path.getsize(dst) // 1000000, "MB")
