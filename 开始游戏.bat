@echo off
chcp 65001 >nul
cd /d "%~dp0server"
start /b node server.js >nul 2>&1
timeout /t 2 /nobreak >nul
start http://localhost:8080
