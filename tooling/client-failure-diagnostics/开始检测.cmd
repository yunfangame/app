@echo off
setlocal
chcp 65001 >nul
title FengWo Client Diagnostics V3
for %%F in (Collect-Client.ps1 Collect-Network.ps1 ClientDiscovery.ps1 ClientObservation.ps1 ClientProtocol.ps1 ClientReport.ps1 ClientCoreSession.cs NetworkProbe.cs HttpProbe.cs) do (
  if not exist "%~dp0%%F" (
    echo 请先解压整个 ZIP，再双击本文件。缺少文件：%%F
    pause
    exit /b 1
  )
)
echo 蜂窝客户端全面检测 V3
echo 先打开蜂窝并登录，检测期间保持客户端打开。
echo 出现“开始观察”后，请回到蜂窝点一次连接或延迟测试。
echo 检测无需输入账号或节点；约 5～15 分钟，报告默认保存在桌面。
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collect-Client.ps1" -NonInteractive
if errorlevel 1 echo 检测程序未正常完成，请把此窗口的错误截图发给客服。
pause
endlocal
