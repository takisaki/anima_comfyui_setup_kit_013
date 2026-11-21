import os, subprocess, sys

KIT = os.path.dirname(os.path.abspath(__file__))
COMFY = os.environ.get("COMFY", "/root/ComfyUI")

def human(b):
    return "%.2f GB" % (b / 1e9) if b >= 1e9 else "%.0f MB" % (b / 1e6)

rows, total, have = [], 0, 0
with open(os.path.join(KIT, "models.tsv"), encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        rank, dest, name, size = parts[0], parts[1], parts[2], parts[4]
        size = int(size)
        p = os.path.join(COMFY, "models", dest, name)
        alt = os.path.join(COMFY, "models", dest, os.path.splitext(name)[0] + ".safetensors")
        got = 0
        use = None
        for c in (p, alt):
            if os.path.isfile(c):
                got = os.path.getsize(c); use = c; break
        total += size
        ok = got >= size - 2000
        if ok:
            have += size
        rows.append((rank, dest + "/" + os.path.basename(use or p), got, size, ok))

print("%-4s %-52s %-10s %s" % ("档", "文件", "大小", ""))
for rank, name, got, size, ok in rows:
    print("%-4s %-52s %-10s %s" % (rank, name, human(got) if got else "-", "OK" if ok else "缺失 " + human(size)))
print("-" * 80)
print("合计: 已就绪 %s / 清单 %s" % (human(have), human(total)))
try:
    out = subprocess.run(["df", "-h", "/root"], capture_output=True, text=True).stdout
    print(out.strip().splitlines()[-1])
except Exception:
    pass
sys.exit(0 if have >= total - 3000 else 1)
