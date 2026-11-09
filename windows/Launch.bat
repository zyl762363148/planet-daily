@echo off
chcp 65001 >nul
cd /d "%~dp0"
set "PY="
where py >nul 2>nul && set "PY=py"
if not defined PY (where python >nul 2>nul && set "PY=python")
if defined PY (
  start "PlanetDaily Server" /min %PY% -m http.server 8765 --bind 127.0.0.1
  timeout /t 1 /nobreak >nul
  start "" http://127.0.0.1:8765/PlanetDaily.html
) else (
  start "" "PlanetDaily.html"
)
