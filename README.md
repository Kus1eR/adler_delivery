# Доставка

Курьерская служба — мобильное приложение на Flutter + FastAPI.

## Структура проекта

- `backend/` — FastAPI сервер (Python)
- `dostavka_app/` — Flutter мобильное приложение

## Быстрый старт

### Бэкенд

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
alembic upgrade head
python seed.py
uvicorn app.main:app --reload --host 0.0.0.0
```

### Flutter

```bash
cd dostavka_app
flutter pub get
flutter run
```

## Возможности

- 📱 Приложение для курьеров и администраторов
- 🗺 Интерактивная карта с маршрутами (OpenStreetMap)
- 📦 Управление заказами
- 📊 Статистика доставок
