# -*- coding: utf-8 -*-
"""重新生成 .vmx（补上 PCIe 根桥定义）并清理运行期残留。"""
import glob
import os
import shutil

ROOT = r"D:\VMs"

VMS = [
    dict(name="zbx-server", mem=4096, vcpu=2, mac="00:50:56:3a:00:10"),
    dict(name="zbx-node1", mem=2048, vcpu=1, mac="00:50:56:3a:00:11"),
]

VMX = """.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "20"
displayName = "{name}"
guestOS = "ubuntu-64"
memsize = "{mem}"
numvcpus = "{vcpu}"
cpuid.coresPerSocket = "{vcpu}"

pciBridge0.present = "TRUE"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge4.functions = "8"
pciBridge5.present = "TRUE"
pciBridge5.virtualDev = "pcieRootPort"
pciBridge5.functions = "8"
pciBridge6.present = "TRUE"
pciBridge6.virtualDev = "pcieRootPort"
pciBridge6.functions = "8"
pciBridge7.present = "TRUE"
pciBridge7.virtualDev = "pcieRootPort"
pciBridge7.functions = "8"

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

for v in VMS:
    d = os.path.join(ROOT, v["name"])
    vmx = os.path.join(d, v["name"] + ".vmx")
    with open(vmx, "w", encoding="utf-8", newline="\n") as f:
        f.write(VMX.format(**v))
    print("rewrote", vmx)

    for pat in ["*.vmem", "*.vmem.lck", "*.vmdk.lck", "*.dmp", "*.scoreboard", "*.vmsd", "vmware.log"]:
        for p in glob.glob(os.path.join(d, pat)):
            try:
                if os.path.isdir(p):
                    shutil.rmtree(p, ignore_errors=True)
                else:
                    os.remove(p)
            except Exception as e:
                print("  failed to remove", p, e)
    print("  cleaned runtime files")
