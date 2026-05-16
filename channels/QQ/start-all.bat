@echo off
chcp 65001 >nul
cd /d "%~dp0"
start "QQ Bridge" cmd /k start-bridge.bat
start "NapCat" cmd /k start-napcat.bat %*
