# Доставка — Проект курьерской службы

Полноценное решение для управления курьерской службой: админ-панель (FastAPI) + мобильное приложение для курьеров (Flutter/Android) с real-time уведомлениями и геолокацией.

## Стек

| Слой | Технологии |
|------|-----------|
| **Мобильное приложение** | Flutter 3.44.6 (Dart 3.12.2), Provider (state), SharedPreferences |
| **Бэкенд** | FastAPI (Python 3.9+), SQLAlchemy 2.0 async, SQLite |
| **Аутентификация** | JWT (python-jose + bcrypt), HTTPBearer |
| **Карты / Гео** | flutter_map + OpenStreetMap, Nominatim (адреса), OSRM (маршруты) |
| **Real-time** | WebSocket (web_socket_channel / FastAPI websockets) |
| **Фоновый сервис** | flutter_background_service 5.x + flutter_local_notifications 18.x |
| **Ключевые пакеты Flutter** | http, dio, geolocator, url_launcher, latlong2 |

## Структура проекта

```
G:\Projects_Python\PORTFOLIO_PROJECTS\Dostavka\
├── backend/
│   ├── app/
│   │   ├── main.py              # Entry point, lifespan, WebSocket endpoints, ProactorEventLoop (Win)
│   │   ├── config.py             # Settings (SECRET_KEY, ALGORITHM, JWT expiry)
│   │   ├── database.py           # AsyncEngine + get_db dependency
│   │   ├── models.py             # Admin, Courier, Order, CourierLocation, OrderHistory
│   │   ├── schemas.py            # Pydantic v2: Token, AdminLogin, CourierLogin, OrderCreate/Out, Stats, LocationUpdate
│   │   ├── auth.py               # hash_password, verify_password (bcrypt), create_access_token (JWT), get_current_admin, get_current_courier
│   │   ├── ws_manager.py         # WebSocketManager: admin/courier connections, broadcast helpers
│   │   └── routers/
│   │       ├── admin.py          # /api/admin/* (login, couriers CRUD, orders CRUD, stats, locations, cancel, delete)
│   │       └── courier.py        # /api/courier/* (login, available orders, take, status update, my orders, stats, location)
│   ├── alembic/                  # Миграции БД
│   ├── .venv/                    # venv
│   ├── seed.py                   # Наполнение тестовыми данными (8 заказов, 3 курьера)
│   ├── requirements.txt
│   ├── .env
│   └── dostavka.db
├── dostavka_app/
│   ├── android/app/src/main/
│   │   ├── AndroidManifest.xml   # permissions (location, foreground, notifications, boot), service + receiver
│   │   └── res/xml/network_security_config.xml  # Для HTTP в debug
│   └── lib/
│       ├── main.dart             # App entry, AuthGate (auto-routing по роли)
│       ├── models/
│       │   └── order.dart        # Order model + statusLabel getter
│       ├── services/
│       │   ├── api_service.dart          # HTTP client (baseUrl from SharedPreferences), login endpoints
│       │   ├── auth_service.dart         # ChangeNotifier: token/role/courierId, loadToken, login, logout, JWT decode
│       │   ├── admin_service.dart        # Admin API calls
│       │   ├── courier_service.dart      # Courier API calls (orders, location, stats)
│       │   ├── websocket_service.dart    # WebSocket client для фронта (admin + courier), auto-reconnect
│       │   └── foreground_service.dart   # Foreground service (уведомления + WebSocket + polling + гео)
│       ├── screens/
│       │   ├── login_screen.dart         # Роли (admin/courier), admin: username+password, courier: phone
│       │   ├── server_settings_screen.dart  # ⚙ Настройка IP:port сервера
│       │   ├── admin_home_screen.dart    # Заказы (вкладки + карта), курьеры (список + блокировка), статистика
│       │   ├── courier_home_screen.dart  # Мои заказы / Доступные / Статистика, polling каждые 10 сек
│       │   ├── courier_detail_screen.dart
│       │   ├── order_detail_screen.dart  # Детали заказа, звонок, копирование номера
│       │   └── map_screen.dart           # Карта OSM (flutter_map), маркеры, Nominatim-поиск, долгий тап
│       └── utils/
│           └── map_utils.dart
├── run_all.bat                  # Запуск бэкенда + Flutter
├── rebuild_db.bat               # Удалить БД, миграции, seed
├── check_flutter.bat
├── PROJECT_CONTEXT.md
└── README.md
```

## WebSocket-события (бэкенд → клиенты)

| Событие | Получатели | Данные |
|---------|-----------|--------|
| `order_created` | admin + все курьеры | `{id, order_number}` |
| `order_taken` | admin + курьер | `{id, courier_id, courier_name}` |
| `order_status_changed` | admin + курьер | `{id, status, courier_id}` |
| `order_cancelled` | admin + курьер (если был назначен) | `{id, order_number}` |
| `courier_created` | admin | `{id, name}` |
| `courier_status_changed` | admin | `{id, status}` |
| `order_updated` | курьер | `{id, status}` |

## Модель данных (БД)

- **Admin**: id, username, hashed_password, created_at
- **Courier**: id, name, phone (unique), status (active/blocked), created_at
- **Order**: id, order_number (unique), address, price, courier_fee, description, status (available/taken/in_transit/delivered/cancelled), recipient_phone, admin_phone, courier_id (FK → couriers), latitude, longitude, created_at, updated_at
- **CourierLocation**: id, courier_id (FK), latitude, longitude, updated_at
- **OrderHistory**: id, order_id (FK), status, changed_at

## Архитектурные решения

### Foreground service (Android) — `foreground_service.dart`
- **initialize()** — вызывается в `main()` до runApp: создаёт 2 канала уведомлений (`dostavka_service` — основной foreground, `dostavka_orders` — push-уведомления), конфигурирует `FlutterBackgroundService` с `AndroidForegroundType.dataSync | AndroidForegroundType.location`
- **start()** — вызывается из `CourierHomeScreen.initState()` (через `addPostFrameCallback`), только для role=coutier. Сохраняет token/role/courierId в SharedPreferences, затем вызывает `service.startService()`. **Критично:** `startService()` вызывается ПОСЛЕ сохранения данных — `onStart()` читает их из SharedPreferences при запуске
- **onStart()** (аннотирован `@pragma('vm:entry-point')`) — запускается в фоне:
  1. Сразу вызывает `setForegroundNotificationInfo()` — **это должно быть ПЕРВЫМ действием** (до любых async), иначе `CannotPostForegroundServiceNotificationException` на Android 14+
  2. Инициализирует `FlutterLocalNotificationsPlugin` для показа push-уведомлений
  3. Подключает WebSocket к `/ws/courier/{id}?token=...` с auto-reconnect (5 сек)
  4. Каждые 30 сек отправляет геолокацию через HTTP POST `/api/courier/location`
  5. Каждые 15 сек polling доступных заказов (запасной канал к WebSocket)

### Уведомления — двойной механизм
- **Foreground-уведомление**: `setForegroundNotificationInfo()` — постоянное (основной канал `dostavka_service`), обновляется при новых заказах, через 15 сек возвращается к "Сервис работает"
- **Push-уведомления**: `flnPlugin.show()` с `fullScreenIntent: true` и `ongoing: false` (канал `dostavka_orders`) — всплывает поверх экрана, auto-отменяется

### Агрегация уведомлений
- При первом polling-цикле все ранее неизвестные заказы считаются новыми
- Если **один** новый → уведомление "Новый заказ! №..."
- Если **несколько** → одно уведомление "N новых заказов"
- Известные заказы отслеживаются через Set<int> `knownOrderIds`

### WebSocket (фронтенд) — `websocket_service.dart`
- Используется **вместе с polling** (запасной канал)
- Auto-reconnect: 5 сек при ошибке, 3 сек при disconnect
- `messageStream` — broadcast StreamController для подписки из экранов
- Сообщения парсятся: `event` → добавляется как `type` в payload

### AuthGate (роутинг)
- `main.dart`: `AuthGate` — StatelessWidget, смотрит на `auth.isLoggedIn` и `auth.role`
- При логине `AuthService._saveSession()` вызывает `notifyListeners()` → `AuthGate.build()` срабатывает заново
- `login_screen` **не делает Navigator.pushReplacement** — AuthGate сам переключает экраны

### JWT / Token
- Бэкенд: `create_access_token()` — payload: `{sub, role, exp}`, алгоритм HS256
- Ответ логина: `{access_token, token_type, role, user_id}`
- Фронтенд: `auth_service.dart._saveSession()` парсит JWT (декодирует payload из base64) + использует поля из ответа API
- Токен сохраняется в SharedPreferences (`access_token`, `role`, `courier_id`)

### Нормализация телефона
- Бэкенд: `_normalize_phone()` в `routers/courier.py` — принимает +7, 8, 7, любые разделители → +7XXXXXXXXXX
- Фронтенд: валидация в `login_screen.dart` — проверка формата +7/8

### Локация курьеров
- **Фронтенд в foreground**: `onStart()` каждые 30 сек через HTTP POST
- **Фронтенд в foreground service**: `onStart()` каждые 30 сек через HTTP POST (то же самое, параллельно)
- **Фронтенд в приложении**: `Geolocator.getPositionStream()` (distanceFilter: 50м) — обновления в реальном времени
- **Бэкенд**: `POST /api/courier/location` — upsert в `courier_locations`

### Карта (админ)
- flutter_map + OpenStreetMap tiles
- Маркеры курьеров (из `GET /api/admin/couriers/locations`) + маркеры заказов
- Поиск адресов: Nominatim API с `bounded=1` + `viewbox` по координатам Сочи
- Долгий тап для установки маркера при создании заказа

## Исправленные баги

| # | Баг | Причина | Решение |
|---|-----|---------|---------|
| 1 | **Foreground service краш: `CannotPostForegroundServiceNotificationException`** | `setForegroundNotificationInfo()` вызывался ПОСЛЕ async-операций (чтение SharedPreferences) | Вызов `setForegroundNotificationInfo()` сделан ПЕРВЫМ действием в `onStart()`, до любого `await` |
| 2 | **`Dart Error: must be annotated`** на `ForegroundServiceManager.onStart()` | Для вызова из native кода нужна аннотация | Добавлен `@pragma('vm:entry-point')` на `onStart()` |
| 3 | **Курьер не получает уведомления о новых заказах** | WebSocket не подключался в foreground service | Добавлен WebSocket-клиент в `onStart()` с auto-reconnect |
| 4 | **Спам уведомлениями** при каждом polling-цикле | Не было трекинга известных заказов | Добавлен `Set<int> knownOrderIds`, агрегация в одно уведомление |
| 5 | **Push-уведомления не всплывали** | Неправильная конфигурация канала | Канал `dostavka_orders`: `importance: max`, `fullScreenIntent: true`, `ongoing: false` |
| 6 | **Ошибка 401 при опросе заказов из foreground** | Токен не сохранялся в SharedPreferences перед запуском сервиса | `start()` сохраняет токен ДО `startService()` |
| 7 | **Логин курьера: ошибка нормализации телефона** | Бэкенд сравнивал строки напрямую | Добавлена `_normalize_phone()` (регекс, выдирает цифры) |
| 8 | **Админ не видит обновлений** после отмены/удаления заказа | WebSocket-событие `order_cancelled` не отправлялось курьерам | Добавлена отправка `send_to_courier` + `broadcast_to_admins` |

## Тестовые данные

| Роль | Данные |
|------|--------|
| **Админ** | username: `admin`, password: `admin123` |
| **Курьеры** | `+79001111111`, `+79002222222`, `+79003333333` |
| **Заказы** | 8 тестовых (seed.py): 4 available, 2 taken, 2 delivered |

## Команды для запуска

```pwsh
# Бэкенд
cd backend
.venv\Scripts\activate
uvicorn app.main:app --reload --host 0.0.0.0 --loop none --reload-dir app

# Flutter (Android)
cd dostavka_app
flutter run

# Пересоздание БД
del backend\dostavka.db; cd backend; .venv\Scripts\activate; alembic upgrade head; python seed.py
```

Примечание: `--loop none` на Windows обязателен из-за ProactorEventLoop.

## GitHub

https://github.com/Kus1eR/adler_delivery

## Планы

- 🔲 Деплой на сервер (RUVDS / Timeweb)
- 🔲 iOS сборка (Codemagic)