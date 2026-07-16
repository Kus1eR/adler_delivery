@echo off
title Доставка - Пересоздать БД
echo ===================================
echo   Пересоздание базы данных
echo ===================================
echo.
cd /d G:\Projects_Python\PORTFOLIO_PROJECTS\Dostavka\backend
if exist dostavka.db (
    echo Удаляю старую БД...
    del /f /q dostavka.db
)
echo Активирую venv...
call .venv\Scripts\activate.bat
echo Запускаю миграции...
alembic upgrade head
echo Заполняю тестовыми данными...
python seed.py
echo.
echo Готово!
pause
