@echo off
setlocal
set VR="C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe"

echo ============================================
echo   Start Zabbix lab VMs (background, no GUI)
echo ============================================
echo.

%VR% -T ws start "D:\VMs\zbx-server\zbx-server.vmx" nogui 2>nul
if errorlevel 1 (echo   zbx-server : already running or failed) else (echo   zbx-server : started)

%VR% -T ws start "D:\VMs\zbx-node1\zbx-node1.vmx" nogui 2>nul
if errorlevel 1 (echo   zbx-node1  : already running or failed) else (echo   zbx-node1  : started)

echo.
echo Waiting 40s for boot and sshd ...
timeout /t 40 /nobreak >nul

echo.
echo ---------- running VMs ----------
%VR% -T ws list
echo.
echo ---------- how to connect ----------
echo   ssh root@192.168.174.10     password: Zbx_2026_Lab   (zbx-server)
echo   ssh root@192.168.174.11     password: Zbx_2026_Lab   (zbx-node1)
echo   Zabbix Web : http://192.168.174.10:8080    Admin / zabbix
echo.
pause
