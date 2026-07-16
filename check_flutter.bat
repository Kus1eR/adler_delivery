@echo off
title Доставка - Проверка Flutter
echo ===================================
echo   Проверка Flutter
echo ===================================
echo.
cd /d G:\Projects_Python\PORTFOLIO_PROJECTS\Dostavka\dostavka_app
flutter pub get
flutter analyze
echo.
echo Готово!
pause
