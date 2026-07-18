# Доставка

Курьерская служба — мобильное приложение на Flutter + FastAPI, с веб-панелью администратора.

## Структура проекта

- `backend/` — FastAPI сервер (Python)
- `dostavka_app/` — Flutter мобильное приложение
- `frontend/` — Web Admin Panel (React + TypeScript + Vite)

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

### Web Admin Panel

```bash
cd frontend
npm install
npm run dev
```

Открыть в браузере: http://localhost:5173

**Технологии:** React 19, TypeScript, Vite, Tailwind CSS 4, shadcn/ui, Leaflet (карты), TanStack Query, Zustand, JWT-авторизация, WebSocket (реальное время).

### Flutter

```bash
cd dostavka_app
flutter pub get
flutter run
```

### Запуск всего сразу

```bash
run_all.bat
```

Запускает 3 сервиса в отдельных окнах: бэкенд, фронтенд (web admin), Flutter.

## Возможности

- 📱 Приложение для курьеров и администраторов
- 🖥 **Web Admin Panel** — панель администратора с 4 вкладками:
  - **Заказы** — создание, удаление, отмена, фильтрация по статусу
  - **Курьеры** — добавление курьеров, переключение статуса (онлайн/офлайн)
  - **Статистика** — сводка по заказам, курьерам, доходам
  - **Карта** — отслеживание курьеров в реальном времени через WebSocket
- 🔐 JWT-авторизация (единое API с мобильным приложением)
- 🗺 Интерактивная карта с маршрутами (OpenStreetMap / Leaflet)
- 📦 Управление заказами
- 📊 Статистика доставок