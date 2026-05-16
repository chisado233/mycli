@echo off
chcp 65001 >nul
cd /d "%~dp0\napcat"
REM Optional: pass QQ number as first argument for quick login, e.g. start-napcat-qq.bat 123456
launcher-user.bat %*
