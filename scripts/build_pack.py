#!/usr/bin/env python3
"""Build the deployable kit archive from a local ComfyUI installation.

Usage:
    python3 scripts/build_pack.py --comfy /path/to/ComfyUI --out dist

Produces in --out:
    comfyui.tar.gz   ComfyUI program files (no models/custom_nodes/user at top level)
    nodes.tar.gz     custom_nodes/ (no .git/__pycache__)
    cloud-kit.zip    scripts + workflows + the two tarballs
"""
import argparse
import os
import sys
import tarfile
import zipfile

# 只排除 ComfyUI 顶层的这些目录；子目录里同名的（例如 comfy/ldm/models）必须保留
TOP_SKIP = {
    "models", "custom_nodes", "output", "input", "temp", "user",
    "venv", ".venv", "dist", "cloud-kit",
}
# 任意层级都要排除
NEST_SKIP = {"__pycache__", ".git", ".github", ".pytest_cache", ".mypy_cache", "ckpts"}
SKIP_EXT = {".pyc", ".pyo", ".log", ".tar", ".gz", ".zip", ".7z", ".pt.tmp"}
SKIP_PREFIX = ("extras_", "cloud-kit")


def keep_file(name: str) -> bool:
    return (
        not name.startswith(SKIP_PREFIX)
        and os.path.splitext(name)[1].lower() not in SKIP_EXT
    )


def add_tree(tar: tarfile.TarFile, src: str, prefix: str, skip=NEST_SKIP) -> int:
    n = 0
    for dirpath, dirnames, filenames in os.walk(src):
        dirnames[:] = [d for d in dirnames if d not in skip]
        rel = os.path.relpath(dirpath, src)
        arc = prefix if rel == "." else prefix + "/" + rel.replace(os.sep, "/")
        tar.add(dirpath, arcname=arc, recursive=False)
        for fn in filenames:
            if not keep_file(fn):
                continue
            tar.add(os.path.join(dirpath, fn), arcname=arc + "/" + fn)
            n += 1
    return n


def build_comfyui(comfy: str, out: str) -> None:
    dst = os.path.join(out, "comfyui.tar.gz")
    with tarfile.open(dst, "w:gz") as tar:
        for entry in sorted(os.listdir(comfy)):
            p = os.path.join(comfy, entry)
            if entry in TOP_SKIP or not keep_file(entry):
                continue
            if os.path.isfile(p):
                tar.add(p, arcname="ComfyUI/" + entry)
            else:
                add_tree(tar, p, "ComfyUI/" + entry)
    print("comfyui.tar.gz  %.1f MB" % (os.path.getsize(dst) / 1e6))


def node_keep() -> set:
    """nodes.keep 里列出的 custom_nodes 子目录；文件不存在时返回空集合（打包全部）。"""
    path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "nodes.keep")
    if not os.path.isfile(path):
        return set()
    with open(path, encoding="utf-8") as fh:
        return {ln.strip() for ln in fh if ln.strip() and not ln.strip().startswith("#")}


def build_nodes(comfy: str, out: str) -> None:
    src = os.path.join(comfy, "custom_nodes")
    dst = os.path.join(out, "nodes.tar.gz")
    keep = node_keep()
    with tarfile.open(dst, "w:gz") as tar:
        for d in sorted(os.listdir(src)):
            p = os.path.join(src, d)
            if not os.path.isdir(p) or d in NEST_SKIP:
                continue
            if keep and d not in keep:
                continue
            add_tree(tar, p, "custom_nodes/" + d)
    print("nodes.tar.gz    %.1f MB" % (os.path.getsize(dst) / 1e6))


def build_workflows(repo: str, out: str) -> None:
    """工作流单独打成 tar：tar 原样保存文件名字节，解压端 locale 不会把中文名弄乱"""
    src = os.path.join(repo, "workflows")
    dst = os.path.join(out, "workflows.tar.gz")
    with tarfile.open(dst, "w:gz") as tar:
        for fn in sorted(os.listdir(src)):
            if fn.lower().endswith(".json"):
                tar.add(os.path.join(src, fn), arcname=fn)
    print("workflows.tar.gz %.1f MB" % (os.path.getsize(dst) / 1e6))


def build_zip(repo: str, out: str) -> None:
    dst = os.path.join(out, "cloud-kit.zip")
    include = sorted(
        f for f in os.listdir(repo)
        if f.endswith((".sh", ".py", ".bat", ".ps1")) or f in ("models.tsv", "nodes.keep", "VERSION")
    )
    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as z:
        for f in include:
            z.write(os.path.join(repo, f), f)
        z.write(os.path.join(repo, "README.md"), "README.md")
        for root, _dirs, files in os.walk(os.path.join(repo, "workflows")):
            for f in files:
                fp = os.path.join(root, f)
                z.write(fp, os.path.relpath(fp, repo).replace(os.sep, "/"))
        for sub in ("patches", "docs"):
            for root, _dirs, files in os.walk(os.path.join(repo, sub)):
                for f in files:
                    if f.endswith((".pyc", ".pyo")):
                        continue
                    fp = os.path.join(root, f)
                    z.write(fp, os.path.relpath(fp, repo).replace(os.sep, "/"))
        for tar_name in ("comfyui.tar.gz", "nodes.tar.gz", "workflows.tar.gz"):
            z.write(os.path.join(out, tar_name), tar_name)
    print("cloud-kit.zip   %.1f MB" % (os.path.getsize(dst) / 1e6))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--comfy", required=True)
    ap.add_argument("--out", default="dist")
    ap.add_argument("--skip-comfyui", action="store_true")
    args = ap.parse_args()

    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.makedirs(args.out, exist_ok=True)
    if not args.skip_comfyui:
        build_comfyui(args.comfy, args.out)
    build_nodes(args.comfy, args.out)
    build_workflows(repo, args.out)
    build_zip(repo, args.out)
    print("done ->", args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
