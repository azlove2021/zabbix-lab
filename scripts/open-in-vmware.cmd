@echo off
setlocal
set VE="C:\Program Files (x86)\VMware\VMware Workstation\vmware.exe"

echo Opening both VMs in VMware Workstation ...
start "" %VE% "D:\VMs\zbx-server\zbx-server.vmx"
timeout /t 4 /nobreak >nul
start "" %VE% "D:\VMs\zbx-node1\zbx-node1.vmx"
echo.
echo If a VM shows "powered off", click the green play button to boot it.
timeout /t 3 /nobreak >nul
