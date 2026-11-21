# 先pip install modelscope -i https://mirrors.aliyun.com/pypi/simple/
from modelscope import snapshot_download
# 尝试下载，如果仓库为空会报错
print("kaishi")
model_dir = snapshot_download('wjlcl0919/wai-Illustrious_v150')
print(f"模型已下载到: {model_dir}")
