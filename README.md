# ComfyUI 云端一键部署套件（Anima / 2080Ti 调优）

在**裸 Ubuntu GPU 实例**上从零部署 ComfyUI + Anima 工作流的一键脚本。
面向 RTX 2080Ti 11GB（Turing / sm_75），所有镜像源在运行时探测，不写死任何地址。

```bash
apt-get update && apt-get install -y unzip
rm -rf /root/kit && unzip -q cloud-kit.zip -d /root/kit
cd /root/kit && bash setup_all.sh --yes
```

脚本会自己完成：装 NVIDIA 驱动（580）→ 自动重启并续跑 → CUDA 版 PyTorch（2.9.1+cu128）
→ ComfyUI → 10 个自定义节点 → 14 GB 模型（ModelScope 加速）。全程无需人工干预。

## 仓库内容

| 文件 | 作用 |
| --- | --- |
| `setup_all.sh` | 编排器：驱动 → 01 → 02 → 03，失败自动清缓存重试 |
| `lib.sh` | 网络层：apt/pip/下载的候选源、测速选路、断点续传、状态缓存 |
| `00_preflight.sh` | 环境体检（只读，不修改系统） |
| `01_comfyui.sh` | 系统依赖 + venv + torch + ComfyUI 本体 + requirements |
| `02_nodes.sh` | 解压自定义节点、装各自依赖、铺工作流 |
| `03_models.sh` | 按 `models.tsv` 下载模型，hf-mirror / ModelScope 自动选源 |
| `install_torch.sh` | 单独装 CUDA 版 torch（多版本回退） |
| `fix_env.sh` | 急救：`doctor` / `apt` / `gpu` / `net` |
| `04_start.sh` / `05_verify.sh` | 启动 / 自检 |
| `models.tsv` | 模型清单（分档、HF 路径、ModelScope 仓库、字节数） |
| `workflows/` | 8 个 ComfyUI 工作流（Anima 出图、线稿上色、姿势控制、局部重绘、表情差分） |
| `scripts/build_pack.py` | 从本地 ComfyUI 目录打包出 `cloud-kit.zip` |

## 构建发布包

仓库里只放脚本，二进制体积的东西（ComfyUI 源码、节点包）由构建脚本从你的本地 ComfyUI 目录打包：

```bash
python3 scripts/build_pack.py --comfy /path/to/ComfyUI --out dist
# 或
./scripts/build_pack.sh /path/to/ComfyUI dist
```

产出 `dist/cloud-kit.zip`（约 76 MB），上传到服务器解压即可用。

---

## 0. 先看清楚你这台机器

| 资源 | 你的配置 | 结论 |
| --- | --- | --- |
| 显卡 | RTX 2080Ti 11GB (Turing, sm_75) | Anima 全系 / SD1.5 / SDXL 都跑得动；See-through 拆层仍不行（要 bitsandbytes + 12GB+ 且 1280px） |
| 系统盘 | 50 GB | std 档装完约 29 GB，剩 ~20 GB；再加 SDXL 底模 6.5 GB 也放得下 |
| 内存 | 48 GB | 富裕，可以放心开大分辨率 |
| 带宽 | 公网 20 Mbps | 出方向限速；**入方向（下模型）通常不限**。00 脚本会实测给你看 |

### 硬性版本要求（2026-11 实测）

| 组件 | 要求 | 原因 |
| --- | --- | --- |
| NVIDIA 驱动 | **>= 560**（脚本装 580） | PyTorch 2.9 的 wheel 是 CUDA 12.8 构建，535 带不动 |
| PyTorch | **>= 2.7**（脚本装 2.9.1 + cu128） | ComfyUI 这一版依赖的 `comfy_kitchen 0.2.41` 用了新版 `torch.library.infer_schema` 语法，2.5/2.6 会直接抛 ValueError，**ComfyUI 起不来** |
| Python | 3.10（Ubuntu 22.04 自带） | — |
| 磁盘 | >= 40 GB 可用 | 依赖 8 GB + 模型 14 GB |

这三条不满足时脚本会自动处理（装驱动、重启、换 torch 版本），但**不要手动 pip install 旧版 torch**。

预期出图速度（相比你本机 CPU 的 20–40 分钟/张）：

| 模型 | 分辨率/步数 | 2080Ti 预计 |
| --- | --- | --- |
| Anima Turbo | 768² / 10 步 | 3–5 秒 |
| Anima Base | 1024² / 30 步 | 8–12 秒 |
| SD1.5 inpaint | 768² / 25 步 | 2–3 秒 |
| SDXL (WAI) | 1024² / 25 步 | 10–15 秒 |

---

## 1. 包里有什么

| 文件 | 大小 | 必需 | 说明 |
| --- | --- | --- | --- |
| `cloud-kit.zip` | ~76 MB | ✅ | 脚本 + 8 个工作流 + 节点包 + **ComfyUI 源码**（12 MB，离线安装，不依赖 GitHub） |
| `extras_optional.tar.gz` | ~2.5 GB | ⬜ | 你的 LoRA、放大模型、YOLO 检测模型（HF 上没有的私有文件） |

**为什么不上传模型**：本地 models 有 50 GB，20M 上传要 5 小时；云端从 hf-mirror 下 15 GB 通常几分钟。只传"配方"，不传"原料"。

---

## 2. 上传（在你的 Windows 上操作）

Windows 10/11 自带 `ssh` 和 `scp`。最省事：双击 `upload.bat`，按提示填 IP / 端口 / 用户名。

或者直接开 PowerShell：

```powershell
cd D:\ComfyUI\cloud-kit

# 必需件
scp cloud-kit.zip root@<服务器IP>:/root/

# 可选件（家里 LoRA 等）
scp extras_optional.tar.gz root@<服务器IP>:/root/
```

- 平台给的不是 22 端口（AutoDL 之类常见 3xxxx），加 `-P 端口号`
- 用户名不一定是 root，按平台给的改
- 大文件断了重跑即可（scp 无断点续传；想稳就 `rsync -avP`）

上传完后连上去：

```powershell
ssh root@<服务器IP>
```

---

## 3. 一键安装

```bash
apt-get update && apt-get install -y unzip
rm -rf /root/kit
cd /root
unzip -q cloud-kit.zip -d /root/kit
cd /root/kit

bash setup_all.sh --yes
```

裸机上第一条命令就够，脚本自己处理：

- 没有 `nvidia-smi` → 自动装 `nvidia-driver-535`（失败依次试 550/570/525）+ dkms + 内核头文件
- 装完驱动 → **自动重启**，并注册 systemd 续跑服务，开机后从断点继续，日志在 `/root/kit/setup.log`
- apt / pip / torch / 模型源全部运行时探测，失败自动换源
- 磁盘不足、ComfyUI 源码缺失、requirements 版本滞后，都有内置兜底

不想自动重启就加 `--no-reboot`。

它会依次跑：

| 脚本 | 干什么 | 耗时 |
| --- | --- | --- |
| `00_preflight.sh` | 查显卡/磁盘/网络/镜像站速度（只读） | 30 秒 |
| `01_comfyui.sh` | apt 依赖 + Python venv + CUDA torch 2.5.1 + ComfyUI 本体 | 8–15 分钟 |
| `02_nodes.sh` | 解压 10 个节点包 + 装各自 pip 依赖 + 拷工作流 | 5–10 分钟 |
| `03_models.sh` | 按清单下模型（默认 std 档 15.1 GB） | 5 分钟～100 分钟（看入方向带宽） |

> 装到一半断了不要紧：每个脚本都能重跑，`03_models.sh` 会断点续传。

---

## 4. 模型三档，按磁盘和时间选

```bash
TIER=core bash 03_models.sh    #  5.8 GB  Anima 全家桶（出图主力）
TIER=std  bash 03_models.sh    # 15.1 GB  再加 SD1.5 局部重绘 + ControlNet + IPAdapter（默认）
TIER=pro  bash 03_models.sh    # 19.3 GB  再加 anima-base 高质量版

bash 03_models.sh --list       # 只看清单不下载
bash 03_models.sh --check      # 只检查缺不缺
```

| 档 | 内容 | 能干什么 |
| --- | --- | --- |
| core | anima-turbo + qwen 文本编码器 + qwen VAE + 参考图适配器 | 文生图、参考图转表情/换角度 |
| std | + SD1.5 inpaint 底模 + openpose/lineart_anime ControlNet + IPAdapter + CLIP-Vision | 手绘局部重绘、姿势控制、线稿上色、角色一致 |
| pro | + anima-base | 高质量慢速出图 |

**SDXL 底模（WAI）HF 上没有可直连的单文件版**，要走另一条路：从你本机传上去（6.5 GB）。

```powershell
scp "D:\ComfyUI\models\checkpoints\WAI-SHUFFLE-NOOB_V-Pred-02.safetensors" ^
    root@<服务器IP>:/root/ComfyUI/models/checkpoints/
```

---

## 5. 启动与访问（重点）

### 5.1 服务器上启动

```bash
cd /root/kit
bash 04_start.sh
```

看到 `Starting server` 就是好了。默认只监听 `127.0.0.1`，**公网碰不到**，安全。

### 5.2 在本机开隧道（另开一个 PowerShell，别关）

```powershell
ssh -N -L 8188:127.0.0.1:8188 root@<服务器IP>
```

然后浏览器打开 **http://127.0.0.1:8188** —— 就和本地 ComfyUI 一模一样。

- `-N` 表示只转端口不开 shell；这条命令会一直挂着，关掉窗口就断
- 端口已被占用就先关掉本地 ComfyUI
- ComfyUI 没有登录鉴权，**强烈建议保持隧道方案**，别直接把 8188 暴露到公网

如果确实要直接公网访问（自己承担风险）：

```bash
LISTEN=0.0.0.0 bash 04_start.sh
```
再在云平台安全组放行 8188，并且最好套一层 nginx basic auth。

---

## 6. 自检

```bash
bash 05_verify.sh
```

- 第 1 段：模型是否齐全（缺哪个一目了然）
- 第 2 段：`--quick-test-for-ci` 加载全部节点，有红色 traceback 就是那个节点坏了
- 第 3 段：磁盘占用

---

## 7. 工作流对照

`02_nodes.sh` 已把 8 个工作流拷到 `ComfyUI/user/default/workflows/`，界面左上「工作流 → 打开」即可。

| 工作流 | 需要什么模型 | 档位 |
| --- | --- | --- |
| 01_线稿上色 | SD1.5 + lineart_anime ControlNet | std |
| 02_anima_turbo | Anima Turbo 三件套 | core |
| 03_姿势控制_角色一致 | SD1.5 + openpose + IPAdapter + CLIP-Vision | std |
| 04_手绘局部重绘Real | SD1.5 inpaint | std |
| 05_角色_Anima资产 | Anima Turbo + 角色节点 | core |
| 06/07_参考图转表情 | Anima + 参考图适配器 | core |
| WAI-NOOB_10MIN+ | WAI SDXL 底模 | 需手动上传 |

**有一处必须手改**：`03_models.sh` 下的 inpaint 底模会从 `.ckpt` 自动转成 `.safetensors`（工作流里写的就是这个名字）。如果转换失败，打开 04 工作流把底模下拉改选 `sd-v1-5-inpainting.ckpt` 即可。

---

## 8. 2080Ti 专属调参

### 显存
| 场景 | 显存 | 建议 |
| --- | --- | --- |
| Anima 768² | ~6 GB | 直接跑 |
| Anima 1024² | ~8 GB | 直接跑 |
| SDXL 1024² | ~9.5 GB | 直接跑；叠 ControlNet 建议 `--medvram` |
| SD1.5 768² inpaint | ~5 GB | 直接跑 |

爆显存就这么启动：

```bash
EXTRA="--medvram" bash 04_start.sh      # 仍然 OOM 就用 --lowvram
EXTRA="--reserve-vram 0.8" bash 04_start.sh
```

### bf16 坑（Turing 没有原生 bf16）
Anima 权重是 bf16。2080Ti 上一般能跑，但如果出现**纯黑图 / NaN / dtype 报错**：

```bash
EXTRA="--force-fp16" bash 04_start.sh
```

### 速度
2080Ti 有 Tensor Core，fp16 正常。不要在 ComfyUI 启动参数里加 `--cpu`（那是你本地那套用的）。

---

## 9. 磁盘预算（50 GB 系统盘）

| 项目 | 占用 |
| --- | --- |
| Ubuntu + apt 依赖 | ~3 GB |
| venv（CUDA torch + 依赖） | ~8 GB |
| ComfyUI 本体 + 前端 | ~1 GB |
| 节点 + 依赖 | ~2 GB |
| 模型 core / std / pro | 5.8 / 15.1 / 19.3 GB |
| output + 临时 | 2–3 GB |

std 档约 **29 GB**，剩 20 GB 左右，够放 SDXL 底模。空间不够时：

```bash
pip cache purge; rm -rf /root/.cache
du -sh /root/ComfyUI/models/*        # 找大头
find /root/ComfyUI/output -type f -mtime +7 -delete   # 清老图
```

---

## 10. 常见问题

**① `nvidia-smi` 找不到**
驱动没装或选的不是 GPU 机型。Ubuntu 上装驱动需要重启，直接换镜像重开机器快得多。

**② pip 卡住不动**
默认走阿里云。换源：`PIP_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple bash 01_comfyui.sh`（清华有时 403，不行就换 `https://mirrors.cloud.tencent.com/pypi/simple`）。

**③ ComfyUI 源码下载失败**
`01_comfyui.sh` 会依次试 codeload / ghfast / gh-proxy。全失败就本机下 `https://github.com/comfyanonymous/ComfyUI/archive/refs/heads/master.zip`，scp 到 `/root/comfy.zip` 再重跑脚本。

**④ 下载模型 404**
改镜像：`HF_BASE=https://huggingface.co bash 03_models.sh`（境外机器用这个更快）。

**⑤ 节点加载报错**
`bash 05_verify.sh` 看是哪个包。常见是缺少系统库：`apt-get install -y libgl1 libglib2.0-0`。

**⑥ 模型下拉里没有新模型**
浏览器强刷（Ctrl+F5），或者看文件名是否和清单一致（大小写敏感）。

**⑦ 页面打开很慢**
20M 出方向带宽的锅。图片预览会慢，但作图本身不受影响。可以把预览方式设成 `--preview-method none`。

**⑧ 关机后数据还在吗**
按量计费的机器，关机一般不收计算费，但**系统盘通常继续收存储费**。确认一下平台的关机策略；想长期省事可以做个"自定义镜像"，下次开机直接恢复环境。

---

## 11. 目录对照（本机 → 云端）

| 本机 | 云端 |
| --- | --- |
| `D:\ComfyUI\models\` | `/root/ComfyUI/models/` |
| `D:\ComfyUI\custom_nodes\` | `/root/ComfyUI/custom_nodes/`（包里已带） |
| `D:\ComfyUI\user\default\workflows\` | `/root/ComfyUI/user/default/workflows/`（包里已带） |
| `D:\ComfyUI\启动ComfyUI.bat` | `bash /root/kit/04_start.sh` |
| `D:\ComfyUI\output\` | `/root/ComfyUI/output/`（取图：`scp -r root@IP:/root/ComfyUI/output ./out`） |

---

## 12. 环境问题速查（实测遇到的）

**① `apt-get update` 卡住 / 403**
默认的 `archive.ubuntu.com` 很慢；`https://mirrors.aliyun.com` 在部分云上被拦返回 403。跑：

脚本里**没有写死任何镜像地址**。`lib.sh` 每次运行时会探测 7 个 apt 源（阿里云 http/https、华为云、腾讯云、中科大、官方、清华），选最快的写进 `sources.list`，`apt-get update` 失败就自动换下一个，成功的记住到 `.state.env`。

手动触发一次（一般不需要）：

```bash
bash fix_env.sh apt
```

**② `nvidia-smi` 不存在**
说明没装驱动（镜像自带的是裸 Ubuntu）。确认显卡在：

```bash
lspci | grep -i nvidia     # 应显示 TU102 [GeForce RTX 2080 Ti]
bash fix_env.sh gpu        # 装 dkms + 头文件 + nvidia-driver-535
reboot
```

**③ hf-mirror 能打开网页但文件下载 0 B/s**
这台机器访问 hf-mirror 的对象存储被卡。`03_models.sh` 已改成**自动测速**在 hf-mirror 和 ModelScope 之间选，也可以强制：

```bash
SOURCE=ms bash 03_models.sh    # 只用 ModelScope（国内云最稳）
SOURCE=hf bash 03_models.sh
```

**③.5 pip 报 TimeoutError: The read operation timed out**
默认源 pypi.org 从这台机器读不动。跑：

不需要手动处理。`lib.sh` 的 `pip_run` 会按顺序尝试 6 个 pip 源（华为云、阿里云 http、腾讯云、中科大、清华、官方），某个源装不上就换下一个，两秒内完成判断。

注意：脚本**不会**用 `PIP_INDEX_URL` 环境变量覆盖配置——那是之前踩过的坑。

**④ 有两个文件只有 hf-mirror 有**

`03_models.sh` 会先自己去下；如果 hf-mirror 在这台机器上不通（实测出现过 0 B/s），才会提示你从本机上传。

| 文件 | 本地路径 | 大小 |
| --- | --- | --- |
| `anima_ref_adapter_v2_r64.safetensors` | `models\loras\` | 176 MB |
| `control_v11p_sd15s2_lineart_anime_fp16.safetensors` | `models\controlnet\` | 690 MB |

```powershell
scp "D:\ComfyUI\models\loras\anima_ref_adapter_v2_r64.safetensors" root@<IP>:/root/upload/
scp "D:\ComfyUI\models\controlnet\control_v11p_sd15s2_lineart_anime_fp16.safetensors" root@<IP>:/root/upload/
```

装完后放到位：

```bash
cp /root/upload/*.safetensors /root/ComfyUI/models/loras/ 2>/dev/null
cp /root/upload/control_v11p_sd15s2_lineart_anime_fp16.safetensors /root/ComfyUI/models/controlnet/
```

---

## 13. 后续更新

```bash
cd /root/ComfyUI && git pull     # 若是 zip 装的，重下 master.zip 覆盖程序文件
# 别覆盖 models/ 和 custom_nodes/
cd /root/kit && bash 03_models.sh --check
```

在云端装了新的自定义节点后，想同步回本地：`scp -r root@IP:/root/ComfyUI/custom_nodes/<包名> D:\ComfyUI\custom_nodes\`
## 14. 版本兼容性说明

这套脚本的版本组合是经过实测确定的，**随意升级会导致 ComfyUI 起不来**：

| 组件 | 版本 | 说明 |
| --- | --- | --- |
| NVIDIA 驱动 | 580（>= 560） | PyTorch 2.9 的 wheel 是 CUDA 12.8 构建 |
| PyTorch | 2.9.1 + cu128 | `comfy_kitchen 0.2.41` 要求 `torch.library.infer_schema` 支持 `list[int]`，该特性 2.7 才有 |
| comfy_kitchen | 0.2.41 | ComfyUI 的硬依赖，导入失败会连带 `comfy.utils` 全挂 |

排查顺序：`nvidia-smi` → `python -c "import torch;print(torch.cuda.is_available())"` → `python -c "import comfy_kitchen"`。

## 15. 已知限制

- See-through 拆层不可用：需要 `bitsandbytes` + 12GB 以上显存 + 1280px 输入，11GB 的 2080Ti 跑不动
- fp8/fp4 加速关闭：`comfy_kitchen` 的 CUDA 后端要求 CUDA 13+，本环境是 12.8，会自动降级到 eager 实现（不影响出图）
- 工作流 `WAI-NOOB_10MIN+` 需要 SDXL 底模，HF/ModelScope 无可直连版本，需自行上传
