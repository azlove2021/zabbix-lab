# -*- coding: utf-8 -*-
"""把 D:\\VMs 下的两台虚拟机注册进 VMware Workstation 左侧清单。"""
import os
import shutil
import time

INV = os.path.join(os.environ["APPDATA"], "VMware", "inventory.vmls")

ENTRIES = [
    dict(idx=14, itemid=14, seqid=9, name="zbx-server",
         path=r"D:\VMs\zbx-server\zbx-server.vmx",
         uuid="56 4d e8 80 86 67 ad 67-01 c4 e2 af d7 2c f7 0b"),
    dict(idx=15, itemid=15, seqid=10, name="zbx-node1",
         path=r"D:\VMs\zbx-node1\zbx-node1.vmx",
         uuid="56 4d b2 84 38 27 e7 59-17 2e 8a db 3b 72 c6 5a"),
]

BODY = (
    'vmlist{i}.config = "{path}"\n'
    'vmlist{i}.DisplayName = "{name}"\n'
    'vmlist{i}.ParentID = "0"\n'
    'vmlist{i}.ItemID = "{itemid}"\n'
    'vmlist{i}.SeqID = "{seqid}"\n'
    'vmlist{i}.IsFavorite = "FALSE"\n'
    'vmlist{i}.IsClone = "FALSE"\n'
    'vmlist{i}.CfgVersion = "8"\n'
    'vmlist{i}.State = "normal"\n'
    'vmlist{i}.UUID = "{uuid}"\n'
    'vmlist{i}.IsCfgPathNormalized = "TRUE"\n'
)

raw = open(INV, "rb").read()
if b"zbx-server.vmx" in raw:
    print("已存在 zbx-server 条目，无需重复写入")
else:
    bak = INV + ".bak-" + time.strftime("%Y%m%d-%H%M%S")
    shutil.copy2(INV, bak)
    print("backup ->", os.path.basename(bak))

    add = b""
    if not raw.endswith(b"\n"):
        add += b"\n"
    for e in ENTRIES:
        add += BODY.format(i=e["idx"], **e).encode("ascii")
    open(INV, "ab").write(add)
    print("appended %d bytes (2 entries)" % len(add))

# 回读校验
txt = open(INV, "rb").read().decode("gbk", "replace")
for e in ENTRIES:
    key = 'vmlist%d.config = "%s"' % (e["idx"], e["path"])
    print(("OK   " if key in txt else "MISS ") + key)

n = sum(1 for line in txt.splitlines() if line.startswith("vmlist") and ".config = " in line and line.split("= ", 1)[1].strip('"'))
print("清单中有效虚拟机条目数:", n)
