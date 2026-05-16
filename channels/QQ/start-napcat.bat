@echo off
chcp 65001 >nul
cd /d "%~dp0\napcat"
launcher-user.bat %*
