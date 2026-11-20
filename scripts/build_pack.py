#!/usr/bin/env python3
"""Build the deployable kit archive from a local ComfyUI installation.

Usage:
    python3 scripts/build_pack.py --comfy /path/to/ComfyUI --out dist

Produces in --out:
    comfyui.tar.gz   ComfyUI program files (no models/nodes/venv/user)
    nodes.tar.gz     custom_nodes/ (no .git/__pycache__)
    cloud-kit.zip    scripts + workflows + the two tarballs

The zip is what you upload to the GPU instance.
"""
import argparse
import os
import sys
import tarfile
import zipfile

COMFY_SKIP = {
    "models", "custom_nodes", "output", "input", "temp", "user", "venv", ".venv",
    "cloud-kit", "dist", "__pycache__", ".git", ".github", "tests", "tests-unit",
}
# 这些是构建产物/打包文件，不属于 ComfyUI 程序本体
SKIP_EXT = {".pyc", ".pyo", ".log", ".tar", ".gz", ".zip", ".7z"}
SKIP_PREFIX = ("extras_", "cloud-kit")


def keep(name: str) -> bool:
    return (
        name not in COMFY_SKIP
        and not name.startswith(SKIP_PREFIX)
        and os.path.splitext(name)[1].lower() not in SKIP_EXT
    )


def add_tree(tar: tarfile.TarFile, src: str, prefix: str, skip=COMFY_SKIP) -> int:
    n = 0
    for dirpath, dirnames, filenames in os.walk(src):
        dirnames[:] = [d for d in dirnames if keep(d) and d not in skip]
        rel = os.path.relpath(dirpath, src)
        arc = prefix if rel == "." else prefix + "/" + rel.replace(os.sep, "/")
        tar.add(dirpath, arcname=arc, recursive=False)
        for fn in filenames:
            if not keep(fn):
                continue
            tar.add(os.path.join(dirpath, fn), arcname=arc + "/" + fn)
            n += 1
    return n


def build_comfyui(comfy: str, out: str) -> None:
    dst = os.path.join(out, "comfyui.tar.gz")
    with tarfile.open(dst, "w:gz") as tar:
        for entry in sorted(os.listdir(comfy)):
            p = os.path.join(comfy, entry)
            if not keep(entry):
                continue
            if os.path.isfile(p):
                tar.add(p, arcname="ComfyUI/" + entry)
            else:
                add_tree(tar, p, "ComfyUI/" + entry)
    print("comfyui.tar.gz  %.1f MB" % (os.path.getsize(dst) / 1e6))


def build_nodes(comfy: str, out: str) -> None:
    src = os.path.join(comfy, "custom_nodes")
    dst = os.path.join(out, "nodes.tar.gz")
    with tarfile.open(dst, "w:gz") as tar:
        for d in sorted(os.listdir(src)):
            p = os.path.join(src, d)
            if os.path.isdir(p) and keep(d):
                add_tree(tar, p, "custom_nodes/" + d)
    print("nodes.tar.gz    %.1f MB" % (os.path.getsize(dst) / 1e6))


def build_zip(repo: str, out: str) -> None:
    dst = os.path.join(out, "cloud-kit.zip")
    include = sorted(
        f for f in os.listdir(repo)
        if f.endswith((".sh", ".py", ".bat", ".ps1")) or f in ("models.tsv", "VERSION")
    )
    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as z:
        for f in include:
            z.write(os.path.join(repo, f), f)
        z.write(os.path.join(repo, "README.md"), "README.md")
        for root, _dirs, files in os.walk(os.path.join(repo, "workflows")):
            for f in files:
                fp = os.path.join(root, f)
                z.write(fp, os.path.relpath(fp, repo).replace(os.sep, "/"))
        for tar_name in ("comfyui.tar.gz", "nodes.tar.gz"):
            z.write(os.path.join(out, tar_name), tar_name)
    print("cloud-kit.zip   %.1f MB" % (os.path.getsize(dst) / 1e6))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--comfy", required=True, help="path to a local ComfyUI checkout")
    ap.add_argument("--out", default="dist")
    ap.add_argument("--skip-comfyui", action="store_true", help="reuse existing comfyui.tar.gz")
    args = ap.parse_args()

    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.makedirs(args.out, exist_ok=True)

    if not args.skip_comfyui:
        build_comfyui(args.comfy, args.out)
    build_nodes(args.comfy, args.out)
    build_zip(repo, args.out)
    print("done ->", args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
