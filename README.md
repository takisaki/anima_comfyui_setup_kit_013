# anima_comfyui_setup_kit

[![ci](https://github.com/takisaki/anima_comfyui_setup_kit_013/actions/workflows/ci.yml/badge.svg)](https://github.com/takisaki/anima_comfyui_setup_kit_013/actions/workflows/ci.yml)

在**裸 Ubuntu GPU 实例**上一键部署 ComfyUI + Anima 出图工作流，面向 RTX 2080Ti 11GB（Turing / sm_75）。

一条命令完成：装显卡驱动 → 自动重启续跑 → CUDA 版 PyTorch → ComfyUI → 10 个自定义节点 → 14 GB 模型。

## 特性

- **零交互**：`bash setup_all.sh --yes` 之后不需要任何人工操作，驱动装完自动重启并续跑
- **不写死镜像**：apt / pip / PyTorch / 模型源全部运行时探测测速，失败自动切换并缓存结果
- **可重入**：任何一步中断后重跑都会跳过已完成部分，模型下载支持断点续传
- **版本受控**：驱动、torch、comfy_kitchen 的兼容关系固定在文档里，避免“装上了但起不来”
- **可验证**：`05_verify.sh` 一次性检查模型完整性、节点导入、磁盘占用

## 系统要求

| 项目 | 要求 |
| --- | --- |
| 系统 | Ubuntu 22.04（jammy），root 权限 |
| 显卡 | NVIDIA，显存 ≥ 11 GB（已在 2080Ti 验证） |
| 驱动 | ≥ 560（脚本自动安装 580） |
| 磁盘 | ≥ 40 GB 可用 |
| 内存 | ≥ 16 GB（建议 32 GB 以上） |
| 网络 | 能访问国内镜像站（apt / PyPI / ModelScope） |

> 版本组合的因果关系见 [版本兼容性](#版本兼容性)。

## 快速开始

```bash
# 1) 取部署包（GitHub 直连在国内云经常不通，优先用代理）
apt-get update && apt-get install -y unzip
rm -f /root/cloud-kit.zip
U=https://github.com/takisaki/anima_comfyui_setup_kit_013/releases/latest/download/cloud-kit.zip
for p in https://ghfast.top/ https://gh-proxy.com/ https://ghproxy.net/; do
  curl -fL -C - --connect-timeout 10 --speed-limit 2048 --speed-time 30 --max-time 900 \
       -o /root/cloud-kit.zip "${p}${U}" && break
done
```
```bash
# 2) 解压到 /root/kit
rm -rf /root/kit && unzip -q /root/cloud-kit.zip -d /root/kit
```
```bash
# 3) 安装
cd /root/kit && bash setup_all.sh --yes
```
```bash
# 4) 如果驱动之前未装需要重启系统，等待重启后重连，查看日志跟踪后台安装进度
tail -f /root/kit/setup.log
```
代理都不通时，在**本机**下载 `cloud-kit.zip` 再上传：

```powershell
# Windows PowerShell
scp D:\你的路径\cloud-kit.zip -p 你的端口 root@服务器IP地址:/root/
```

### 部署完成后

```bash
# 服务器：前台启动（默认，连接一断服务就停）
cd /root/kit && bash 04_start.sh
```

这是**预期行为**：SSH 断开 → 服务退出。想让服务脱离终端常驻，才用 `--daemon`：

```bash
bash 04_start.sh --daemon    # 后台常驻 + 开机自启
bash 04_start.sh --stop      # 停止并取消自启
bash 04_start.sh --status    # 状态
bash 04_start.sh --logs      # 日志
```

> 断网（不是正常断开）时，服务是否退出取决于 sshd 多久发现对端消失，默认可能要等很久。
> 想让它几十秒内就停，配一次 `ClientAliveInterval`，见 [docs/guide.md](docs/guide.md) 4.5 节。

```powershell
# 本机：开 SSH 隧道（窗口别关）
ssh -N -L 8188:127.0.0.1:8188 -p 你的端口 root@服务器IP地址
```

本机浏览器打开 http://127.0.0.1:8188 。ComfyUI 无鉴权，所以走隧道而不是直接开端口。

出图前自检：

```bash
cd /root/kit && bash 05_verify.sh
```

完整步骤、每个阶段耗时、目录约定见 **[docs/guide.md](docs/guide.md)**。

## 配置

全部通过环境变量覆盖，不需要改脚本：

| 变量 | 默认 | 作用 |
| --- | --- | --- |
| `TIER` | `std` | 模型档位：`core` 5.8 GB / `std` 15.1 GB / `pro` 19.3 GB |
| `SOURCE` | `auto` | 模型源：`auto` 测速选择 / `hf` hf-mirror / `ms` ModelScope |
| `HF_BASE` | `https://hf-mirror.com` | HF 镜像地址 |
| `EXTRA` | 空 | 启动附加参数，如 `--medvram`、`--force-fp16` |
| `LISTEN` | `127.0.0.1` | 监听地址，`0.0.0.0` 才可公网直连 |
| `PORT` | `8188` | 端口 |
| `KEEP_CKPT` | `0` | 设 `1` 保留转换前的 `.ckpt` |

示例：

```bash
TIER=core bash 03_models.sh        # 只装最小集
SOURCE=ms bash 03_models.sh        # 强制走 ModelScope
EXTRA="--medvram" bash 04_start.sh # 显存不够时
```

## 项目结构

```
.
├── setup_all.sh          # 编排器：驱动 → 01 → 02 → 03
├── lib.sh                # 网络层：候选源、测速、断点续传、状态缓存
├── 00_preflight.sh       # 环境体检（只读）
├── 01_comfyui.sh         # 系统依赖 + venv + torch + ComfyUI
├── 02_nodes.sh           # 节点 + 依赖 + 工作流
├── 03_models.sh          # 模型下载
├── 04_start.sh           # 启动
├── 05_verify.sh          # 自检
├── install_torch.sh      # 单独安装 / 重装 CUDA torch
├── fix_env.sh            # 急救：doctor / apt / gpu / net
├── get_kit.sh            # 带镜像回退的部署包下载器
├── models.tsv            # 模型清单（分档 / HF 路径 / ModelScope 仓库 / 字节数）
├── check_models.py       # 清单校验
├── convert_ckpt.py       # .ckpt → .safetensors
├── workflows/            # 8 个 ComfyUI 工作流
├── scripts/
│   ├── build_pack.py     # 打包发布件
│   └── publish_release.py# 发布到 GitHub Release
└── docs/guide.md         # 详细部署指南
```

## 开发与发布

```bash
# 语法检查（CI 也会跑）
for f in *.sh scripts/*.sh; do bash -n "$f"; done

# 打包（需要本地一份 ComfyUI 目录）
python3 scripts/build_pack.py --comfy /path/to/ComfyUI --out dist

# 发布新版本（读 Git Credential Manager 里的凭据，不存明文 token）
python3 scripts/publish_release.py --repo takisaki/anima_comfyui_setup_kit_013 \
  --tag v1.1 --file dist/cloud-kit.zip --name cloud-kit.zip --notes "变更说明"
```

CI（`.github/workflows/ci.yml`）：`bash -n` 全量脚本 + `py_compile` + shellcheck error 级别。

## 版本兼容性

| 组件 | 版本 | 原因 |
| --- | --- | --- |
| NVIDIA 驱动 | 580（≥ 560） | PyTorch 2.9 wheel 是 CUDA 12.8 构建 |
| PyTorch | 2.9.1 + cu128 | `comfy_kitchen 0.2.41` 需要 `infer_schema` 支持 `list[int]`，该特性 2.7 起才有 |
| comfy_kitchen | 0.2.41 | ComfyUI 硬依赖；导入失败会连带 `comfy.utils` 崩掉 |
| Python | 3.10 | Ubuntu 22.04 自带 |

排查顺序：`nvidia-smi` → `python -c "import torch;print(torch.cuda.is_available())"` → `python -c "import comfy_kitchen"`。

## 故障排查

| 现象 | 处理 |
| --- | --- |
| `apt-get update` 卡住 / 403 | 脚本会自动换源；手动 `bash fix_env.sh apt` |
| 没有 `nvidia-smi` | `bash fix_env.sh gpu` 后 `reboot` |
| pip 超时 | 脚本自动换源；`bash fix_env.sh net` 看各站速度 |
| 下载卡在 0 B/s | 已内置 10 KB/s 熔断，会自动换源；仍失败见 guide 的方式 B |
| ComfyUI 起不来 | 先确认驱动、torch、comfy_kitchen 三者版本 |

更多见 [docs/guide.md](docs/guide.md) 的 A10 / A12 两节。

## 已知限制

- See-through 拆层不可用：需 `bitsandbytes` + ≥12 GB 显存 + 1280px 输入
- fp8/fp4 加速关闭：`comfy_kitchen` 的 CUDA 后端要求 CUDA 13+，本环境 12.8 会自动降级到 eager
- 工作流 `WAI-NOOB_10MIN+` 需要 SDXL 底模，公开源无可直连版本，需自行提供

## 许可

本仓库未声明开源许可。随包下载的模型与权重（Anima、ControlNet、IP-Adapter 等）各自遵循其原始许可，
其中 Anima 及其参考图适配器为 **非商用** 许可，商用前请核对各模型仓库的 LICENSE。
