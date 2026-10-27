# -*- coding: utf-8 -*-
"""为两台 Ubuntu 24.04 VM 生成 cloud-init 种子 ISO + VMware .vmx 配置。"""
import os
import sys

import pycdlib

ROOT = r"D:\VMs"
PASS = "Zbx_2026_Lab"

VMS = [
    dict(
        name="zbx-server",
        hostname="zbx-server",
        ip="192.168.174.10",
        prefix=24,
        gw="192.168.174.2",
        mac="00:50:56:3a:00:10",
        mem=4096,
        vcpu=2,
        iid="zbx-server-iid-01",
    ),
    dict(
        name="zbx-node1",
        hostname="zbx-node1",
        ip="192.168.174.11",
        prefix=24,
        gw="192.168.174.2",
        mac="00:50:56:3a:00:11",
        mem=2048,
        vcpu=1,
        iid="zbx-node1-iid-01",
    ),
]


def user_data(v):
    return f"""#cloud-config
preserve_hostname: false
hostname: {v['hostname']}
manage_etc_hosts: true
timezone: Asia/Shanghai

users:
  - name: zbx
    gecos: Zabbix Lab
    groups: [adm, sudo]
    shell: /bin/bash
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    lock_passwd: false
    plain_text_passwd: "{PASS}"

ssh_pwauth: true
chpasswd:
  expire: false

write_files:
  - path: /etc/apt/sources.list.d/ubuntu.sources
    permissions: '0644'
    content: |
      Types: deb
      URIs: https://mirrors.aliyun.com/ubuntu/
      Suites: noble noble-updates noble-backports noble-security
      Components: main restricted universe multiverse
      Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

package_update: false
package_upgrade: false

runcmd:
  - [ sh, -c, "echo '{v['hostname']} {v['ip']} ready' > /etc/motd.d/90-lab 2>/dev/null || true" ]

final_message: "cloud-init finished on {v['hostname']}"
"""


def meta_data(v):
    return f"""instance-id: {v['iid']}
local-hostname: {v['hostname']}
"""


def network_config(v):
    return f"""version: 2
ethernets:
  eth0:
    match:
      macaddress: "{v['mac']}"
    set-name: eth0
    dhcp4: false
    dhcp6: false
    addresses: [{v['ip']}/{v['prefix']}]
    routes:
      - to: default
        via: {v['gw']}
    nameservers:
      addresses: [{v['gw']}, 223.5.5.5]
"""


VMX = """.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "20"
displayName = "{name}"
guestOS = "ubuntu-64"
memsize = "{mem}"
numvcpus = "{vcpu}"
cpuid.coresPerSocket = "{vcpu}"

scsi0.present = "TRUE"
scsi0.virtualDev = "lsilogic"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "disk.vmdk"
scsi0:0.deviceType = "scsi-hardDisk"

sata0.present = "TRUE"
sata0:1.present = "TRUE"
sata0:1.deviceType = "cdrom-image"
sata0:1.fileName = "seed.iso"
sata0:1.startConnected = "TRUE"

ethernet0.present = "TRUE"
ethernet0.connectionType = "nat"
ethernet0.virtualDev = "e1000e"
ethernet0.addressType = "static"
ethernet0.address = "{mac}"
ethernet0.startConnected = "TRUE"

usb.present = "TRUE"
ehci.present = "TRUE"
sound.present = "FALSE"
floppy0.present = "FALSE"
tools.syncTime = "TRUE"
tools.upgrade.policy = "manual"

isolation.tools.hgfs.disable = "TRUE"
"""


def build_iso(out_path, files):
    """files: list of (真实文件名, 内容 bytes)"""
    iso = pycdlib.PyCdlib()
    iso.new(interchange_level=1, joliet=3, rock_ridge="1.09", vol_ident="CIDATA")
    for name, data in files:
        # ISO9660 level 1 只允许 8.3 名字，真实长名字由 Rock Ridge / Joliet 承载
        short = name.upper().replace("-", "_")
        short = short[:8]
        iso_path = "/%s.;1" % short
        iso.add_fp(
            __import__("io").BytesIO(data),
            len(data),
            iso_path=iso_path,
            rr_name=name,
            joliet_path="/" + name,
        )
    iso.write(out_path)
    iso.close()


def main():
    for v in VMS:
        d = os.path.join(ROOT, v["name"])
        os.makedirs(d, exist_ok=True)

        iso_path = os.path.join(d, "seed.iso")
        build_iso(
            iso_path,
            [
                ("user-data", user_data(v).encode()),
                ("meta-data", meta_data(v).encode()),
                ("network-config", network_config(v).encode()),
            ],
        )

        vmx_path = os.path.join(d, v["name"] + ".vmx")
        with open(vmx_path, "w", encoding="utf-8", newline="\n") as f:
            f.write(VMX.format(**v))

        print("built %-12s  seed.iso=%6.1f KB  %s.vmx" % (
            v["name"], os.path.getsize(iso_path) / 1024, v["name"]))

    # 校验 ISO 内容
    print("\n---- 校验 seed.iso ----")
    iso = pycdlib.PyCdlib()
    iso.open(os.path.join(ROOT, VMS[0]["name"], "seed.iso"))
    print("volume id :", iso.pvd.volume_identifier.decode().strip())
    for child in iso.list_children(iso_path="/"):
        if child is None or child.is_dir():
            continue
        n = child.rock_ridge.name().decode() if child.rock_ridge else "(no RR)"
        print("  file: %-16s size=%d" % (n, child.get_data_length()))
    iso.close()


if __name__ == "__main__":
    sys.exit(main())
