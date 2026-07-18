# Доставка — Проект курьерской службы

## Стек
- **Мобильное приложение:** Flutter 3.44.6 (Dart 3.12.2)
- **Бэкенд:** FastAPI (Python 3.9+), SQLite
- **Карты:** OpenStreetMap (flutter_map), Nominatim, OSRM
- **Аутентификация:** JWT (bcrypt + python-jose)
- **Real-time:** WebSocket (web_socket_channel)
- **Фоновые уведомления:** flutter_background_service + flutter_local_notifications

## Структура
```
G:\Projects_Python\PORTFOLIO_PROJECTS\Dostavka\
├── backend/
│   ├── app/
│   │   ├── main.py          # Entry point + WebSocket
│   │   ├── config.py         # Настройки
│   │   ├── database.py       # SQLAlchemy async
│   │   ├── models.py         # Admin, Courier, Order, OrderHistory, CourierLocation
│   │   ├── schemas.py        # Pydantic v2
│   │   ├── auth.py           # JWT + bcrypt
│   │   ├── ws_manager.py     # WebSocket manager
│   │   └── routers/
│   │       ├── admin.py      # API админа
│   │       └── courier.py    # API курьера
│   ├── alembic/              # Миграции
│   ├── .venv/                # Виртуальное окружение
│   ├── requirements.txt
│   ├── .env
│   └── seed.py
├── dostavka_app/
│   └── lib/
│       ├── main.dart
│       ├── models/ (order.dart)
│       ├── services/ (api_service, auth_service, admin_service, courier_service, websocket_service, foreground_service)
│       └── screens/ (login, server_settings, admin_home, courier_home, courier_detail, order_detail, map_screen)
├── run_all.bat, rebuild_db.bat, check_flutter.bat
```

## Текущий статус

### Сделано
- ✅ FastAPI бэкенд с полным API (админ + курьер + WebSocket)
- ✅ Flutter экран входа (админ: username+password, курьер: телефон)
- ✅ Админ панель: заказы (создание, отмена, фильтр), курьеры (добавление, блокировка), статистика
- ✅ Курьер: мои заказы, доступные, статистика, детали заказа (звонок, копирование номера)
- ✅ JWT аутентификация
- ✅ WebSocket real-time обновления
- ✅ Foreground service (фоновые уведомления как в такси) — **НО КРАШИТСЯ**
- ✅ Геолокация курьеров + карта для админа (OpenStreetMap)
- ✅ Поиск адресов (Nominatim) с ограничением по Сочи
- ✅ Долгий тап для установки маркера на карте
- ✅ Отмена заказов (админ) + уведомление курьеру через WebSocket
- ✅ Настройка адреса сервера (⚙ на экране входа)
- ✅ Валидация телефона (+7 и 8)
- ✅ GitHub: https://github.com/Kus1eR/adler_delivery

### Проблемы
- ❌ **Foreground service крашится на Android 17+** — `CannotPostForegroundServiceNotificationException: Bad notification for startForeground`. Нужно исправить инициализацию уведомлений в `foreground_service.dart`.
- ❌ Также ошибка: `Dart Error: To access 'ForegroundServiceManager' from native code, it must be annotated.` Нужно добавить `@pragma('vm:entry-point')`.

### Планируется
- 🔲 Деплой на сервер (RUVDS / Timeweb)
- 🔲 iOS сборка (Codemagic)

## Тестовые данные
- **Админ:** admin / admin123
- **Курьеры:** +79001111111, +79002222222, +79003333333
- **Заказы:** 8 тестовых (4 available, 2 taken, 2 delivered)

## Команды
```bash
# Запуск бэкенда
cd G:\Projects_Python\PORTFOLIO_PROJECTS\Dostavka\backend
.venv\Scripts\activate
uvicorn app.main:app --reload --host 0.0.0.0

# Запуск Flutter
cd G:\Projects_Python\PORTFOLIO_PROJECTS\Dostavka\dostavka_app
flutter run

# Пересоздать БД
del backend\dostavka.db & cd backend & .venv\Scripts\activate & alembic upgrade head & python seed.py
```
