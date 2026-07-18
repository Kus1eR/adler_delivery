@echo off
title Доставка - Backend + Frontend + Flutter

echo ========================================
echo   ДОСТАВКА - Backend + Frontend + Flutter
echo ========================================
echo.

:: Запускаем бэкенд в отдельном окне
echo [1/3] Запуск бэкенда...
start "Backend" cmd /c "cd /d G:\Projects_Python\PORTFOLIO_PROJECTS\Dostavka\backend && .venv\Scripts\activate && uvicorn app.main:app --reload --reload-dir app --loop none --host 0.0.0.0"

echo Ждём 5 секунд пока бэкенд стартует...
ping -n 5 127.0.0.1 > nul

echo [2/3] Запуск фронтенда...
start "Dostavka Frontend" cmd /k "cd /d frontend && npm run dev"

echo [3/3] Запуск Flutter...
cd /d G:\Projects_Python\PORTFOLIO_PROJECTS\Dostavka\dostavka_app
flutter run

echo.
echo Готово!
pause
