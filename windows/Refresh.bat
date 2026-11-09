@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo 正在用 data\latest.json 重新生成 PlanetDaily.html ...
py build_windows.py --local
if errorlevel 1 python build_windows.py --local
echo.
echo 完成。重新双击 Launch.bat 即可看到新数据。
pause
