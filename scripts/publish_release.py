#!/usr/bin/env python3
"""Publish a GitHub release asset using the credential stored by Git Credential Manager.

Usage:
    python3 scripts/publish_release.py --repo owner/name --tag v1.0 \
        --file dist/cloud-kit.zip --name cloud-kit.zip --notes "..."

Reads the token from 'git credential fill' so no secret is stored in the repo.
"""
import argparse
import json
import mimetypes
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = "https://api.github.com"
UPLOAD = "https://uploads.github.com"


def token() -> str:
    out = subprocess.run(
        ["git", "credential", "fill"],
        input="protocol=https\nhost=github.com\n\n",
        capture_output=True, text=True,
    ).stdout
    for line in out.splitlines():
        if line.startswith("password="):
            return line.split("=", 1)[1]
    sys.exit("no github credential found; run 'git push' once to authenticate")


def request(url, tok, data=None, method="GET", headers=None, timeout=600):
    h = {"Authorization": "Bearer " + tok, "User-Agent": "publish-release"}
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, data=data, headers=h, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        body = r.read()
        return r.status, (json.loads(body) if body else {})


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--tag", required=True)
    ap.add_argument("--file", required=True)
    ap.add_argument("--name", default=None)
    ap.add_argument("--notes", default="")
    args = ap.parse_args()

    repo, tag = args.repo, args.tag
    name = args.name or os.path.basename(args.file)
    tok = token()

    # 1) 找已有 release
    rid = None
    try:
        _s, rel = request(f"{API}/repos/{repo}/releases/tags/{tag}", tok)
        rid = rel.get("id")
        print("existing release:", rid)
    except urllib.error.HTTPError as e:
        if e.code != 404:
            raise

    # 2) 没有就建
    if not rid:
        payload = json.dumps({
            "tag_name": tag, "name": tag, "body": args.notes or tag,
            "draft": False, "prerelease": False,
        }).encode()
        _s, rel = request(
            f"{API}/repos/{repo}/releases", tok, data=payload, method="POST",
            headers={"Content-Type": "application/json"},
        )
        rid = rel["id"]
        print("created release:", rid, rel.get("html_url"))

    # 3) 删掉同名旧资产
    _s, assets = request(f"{API}/repos/{repo}/releases/{rid}/assets", tok)
    for a in assets if isinstance(assets, list) else []:
        if a.get("name") == name:
            request(f"{API}/repos/{repo}/releases/{rid}/assets/{a['id']}", tok, method="DELETE")
            print("deleted old asset", name)

    # 4) 上传（3 次重试）
    size = os.path.getsize(args.file)
    print("uploading %s (%.1f MB)" % (name, size / 1e6))
    for attempt in range(1, 4):
        try:
            with open(args.file, "rb") as fh:
                data = fh.read()
            ctype = mimetypes.guess_type(name)[0] or "application/octet-stream"
            _s, res = request(
                f"{UPLOAD}/repos/{repo}/releases/{rid}/assets?name={name}",
                tok, data=data, method="POST",
                headers={"Content-Type": ctype, "Content-Length": str(size)},
            )
            print("uploaded:", res.get("browser_download_url"))
            return 0
        except Exception as exc:  # noqa: BLE001
            print("attempt %d failed: %s" % (attempt, exc))
            time.sleep(8)
    return 1


if __name__ == "__main__":
    sys.exit(main())
