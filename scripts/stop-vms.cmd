@echo off
setlocal
set VR="C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe"

echo Stopping Zabbix lab VMs (graceful ACPI shutdown) ...
echo.

%VR% -T ws stop "D:\VMs\zbx-node1\zbx-node1.vmx" soft 2>nul
%VR% -T ws stop "D:\VMs\zbx-server\zbx-server.vmx" soft 2>nul

echo Done. Current state:
%VR% -T ws list
echo.
pause
