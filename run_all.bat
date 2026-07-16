@echo off
title Доставка - Backend + Flutter

echo ========================================
echo   ДОСТАВКА - Backend + Flutter
echo ========================================
echo.

:: Запускаем бэкенд в отдельном окне
echo [1/2] Запуск бэкенда...
start "Backend" cmd /c "cd /d G:\Projects_Python\PORTFOLIO_PROJECTS\Dostavka\backend && .venv\Scripts\activate && uvicorn app.main:app --reload --host 0.0.0.0"

echo Ждём 5 секунд пока бэкенд стартует...
ping -n 5 127.0.0.1 > nul

echo [2/2] Запуск Flutter...
cd /d G:\Projects_Python\PORTFOLIO_PROJECTS\Dostavka\dostavka_app
flutter run

echo.
echo Готово!
pause
