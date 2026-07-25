# Доставка

> Локальная платформа управления курьерской службой: FastAPI API, web-панель администратора и Flutter-приложение для курьеров и администраторов.

![Python 3.9+](https://img.shields.io/badge/Python-3.9%2B-3776AB?logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-API-009688?logo=fastapi&logoColor=white)
![React 19](https://img.shields.io/badge/React-19-61DAFB?logo=react&logoColor=111827)
![Flutter 3.44](https://img.shields.io/badge/Flutter-3.44-02569B?logo=flutter&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Android-5F6368)

`Доставка` объединяет жизненный цикл заказа, работу нескольких администраторов, курьерскую геолокацию и уведомления в одном локально запускаемом проекте. Web-панель ориентирована на диспетчера, а Flutter-клиент автоматически открывает интерфейс администратора или курьера по роли пользователя.

## Содержание

- [Возможности](#возможности)
- [Архитектура](#архитектура)
- [Технологии](#технологии)
- [Быстрый старт](#быстрый-старт)
- [Настройка карт](#настройка-карт)
- [API и WebSocket](#api-и-websocket)
- [Структура проекта](#структура-проекта)
- [Проверки](#проверки)
- [Ограничения и production checklist](#ограничения-и-production-checklist)

## Возможности

### Web Admin

- Создание, поиск, фильтрация и серверная пагинация заказов по 1-100 записей на страницу.
- Редактирование заказа, отмена с обязательной причиной и soft delete без физического удаления строки.
- CSV-экспорт текущей выборки с UTF-8 BOM, лимитом 10 000 строк и защитой от formula injection.
- Создание и блокировка курьеров, просмотр статистики и текущих координат.
- Управление дополнительными администраторами из аккаунта суперадминистратора.
- Защита от отключения собственного аккаунта и последнего активного суперадминистратора.
- Светлая и тёмная темы, адаптивная навигация, обновления через WebSocket.
- Карта OpenStreetMap/Leaflet по умолчанию; опциональный Yandex Maps JS API с автоматическим возвратом на OSM при ошибке загрузки.

### Flutter: курьер и администратор

- Вход администратора по логину и паролю, вход курьера по нормализованному телефону и паролю.
- Автоматический выбор интерфейса по JWT-роли и настройка адреса backend-сервера.
- Администратор: заказы с пагинацией, курьеры, статистика и карта OSM.
- Курьер: доступные и назначенные заказы, независимое ведение нескольких активных заказов, статистика заработка.
- Звонок получателю, копирование телефона, открытие адреса во внешних Яндекс Картах.
- Android foreground service с WebSocket, геолокацией и локальными уведомлениями.
- Агрегация нескольких новых заказов в одно уведомление.
- Адаптивный polling: 90 секунд при активном WebSocket и 15 секунд без соединения.
- Передача геопозиции не чаще раза в 60 секунд и только после перемещения минимум на 50 метров.
- Ограниченная offline queue для безопасных переходов статуса и последней геопозиции; повторы используют backoff, очередь ограничена и разделена по курьерам.
- Взятие заказа намеренно не ставится в offline queue: операция требует сети, чтобы сохранить атомарность.

### Backend и безопасность

- JWT-аутентификация с ролями `admin` и `courier`; активность администратора и блокировка курьера проверяются на защищённых запросах и WebSocket-подключениях.
- Пароли администраторов и курьеров хешируются bcrypt; пароль курьера обязателен при создании и входе.
- Rate limit `5/minute` на admin/courier login и `10/hour` на создание администратора.
- Атомарное взятие заказа через условный `UPDATE`: при гонке один запрос получает `200`, второй `409`.
- Контролируемые переходы статусов, история изменений, причина отмены и soft delete.
- Одна актуальная запись `CourierLocation` на курьера через unique constraint и dialect-specific upsert для SQLite/PostgreSQL.
- Preferred versioned REST API `/api/v1`; legacy routes сохранены только как deprecated-compatible aliases.
- Один courier WebSocket owner в Android foreground service и один location owner там же; UI курьера не создаёт дублирующее соединение и не отправляет координаты самостоятельно.

## Архитектура

```text
┌──────────────────────┐      HTTP / WebSocket      ┌──────────────────────┐
│ React Web Admin      │◄──────────────────────────►│ FastAPI              │
│ orders / map / stats │                            │ auth / orders / geo  │
└──────────────────────┘                            │ WebSocket manager    │
                                                    └──────────┬───────────┘
┌──────────────────────┐      HTTP / WebSocket                 │
│ Flutter Android      │◄──────────────────────────────────────┤
│ admin + courier UI   │                                       │
│ foreground service  │                            ┌───────────▼──────────┐
│ offline queue        │                            │ SQLAlchemy + Alembic │
└──────────────────────┘                            │ SQLite local         │
                                                    │ PostgreSQL drivers   │
                                                    └──────────────────────┘
```

Backend хранит пользователей, заказы, историю статусов и последнюю геопозицию курьера. REST отвечает за команды и выборки; WebSocket сообщает клиентам о создании, взятии, изменении и отмене заказов. Flutter foreground service остаётся единственным владельцем courier WebSocket и фоновой отправки координат.

## Технологии

| Слой | Стек |
| --- | --- |
| Backend | Python 3.9+, FastAPI, SQLAlchemy 2 async, Pydantic Settings, Alembic, python-jose, bcrypt, SlowAPI |
| База данных | SQLite + aiosqlite для local/demo; зависимости asyncpg и psycopg подготовлены для PostgreSQL |
| Web Admin | React 19, TypeScript, Vite 8, Tailwind CSS 4, TanStack Query, Zustand, React Hook Form, Zod |
| Web-карты | Leaflet/OpenStreetMap; опционально Yandex Maps JS API 2.1 |
| Flutter | Flutter 3.44.6, Dart 3.12.2, Provider, Dio/http, SharedPreferences |
| Mobile geo/realtime | flutter_map, OpenStreetMap, Geolocator, web_socket_channel, flutter_background_service, flutter_local_notifications |

## Быстрый старт

### Предварительные требования

- Windows 10/11.
- Python 3.9 или новее.
- Node.js с npm. Текущий frontend проверен на Node.js 24 и npm 11.
- Flutter 3.44.x с Dart 3.12.x.
- Android SDK, эмулятор или Android-устройство для мобильного клиента.

### 1. Backend

Из корня репозитория:

```bat
cd backend
python -m venv .venv
.venv\Scripts\activate
python -m pip install -r requirements.txt
copy .env.example .env
```

Откройте созданный `backend/.env` и замените шаблонное значение `SECRET_KEY` на собственную длинную случайную строку. Реальный ключ нельзя коммитить или публиковать.

Пример генерации локального ключа средствами Python:

```bat
python -c "import secrets; print(secrets.token_urlsafe(48))"
```

Примените миграции и создайте demo-данные:

```bat
alembic upgrade head
python seed.py
```

Запустите API:

```bat
uvicorn app.main:app --reload --reload-dir app --loop none --host 0.0.0.0
```

- API: <http://localhost:8000>
- OpenAPI: <http://localhost:8000/docs>

На Windows проект использует `WindowsProactorEventLoopPolicy`; `run_all.bat` и рекомендуемая команда явно передают Uvicorn `--loop none`.

### 2. Web Admin

В новом терминале из корня репозитория:

```bat
cd frontend
npm install
npm run dev
```

Панель доступна по адресу <http://localhost:5173>. Vite proxy направляет `/api` и `/ws` на backend по адресу `http://localhost:8000`.

### 3. Flutter

В новом терминале:

```bat
cd dostavka_app
flutter pub get
flutter run
```

На экране настроек приложения укажите адрес backend, доступный с устройства. Для Android Emulator обычно используется `http://10.0.2.2:8000`; физическому устройству нужен LAN-адрес компьютера, например `http://192.168.1.10:8000`.

### Demo-аккаунты

После `python seed.py` доступны публичные учётные данные только для local/demo:

| Роль | Логин | Пароль |
| --- | --- | --- |
| Суперадминистратор | `admin` | `admin123` |
| Курьер 1 | `+79001111111` | `courier123` |
| Курьер 2 | `+79002222222` | `courier123` |
| Курьер 3 | `+79003333333` | `courier123` |

Не используйте эти пароли в production. Перед публикацией сервиса удалите demo-данные и смените все учётные данные.

### Запуск всех компонентов

После установки зависимостей, создания `backend/.env`, применения миграций и seed можно запустить:

```bat
run_all.bat
```

Скрипт проверяет наличие `backend/.env`, открывает backend и web admin в отдельных окнах и запускает `flutter run` в текущем окне.

## Настройка карт

### Web Admin

OpenStreetMap/Leaflet используется по умолчанию и не требует API-ключа. Для Yandex Maps JS API:

```bat
cd frontend
copy .env.example .env.local
```

Настройте `frontend/.env.local`:

```dotenv
VITE_MAP_PROVIDER=yandex
VITE_YANDEX_MAPS_API_KEY=your_yandex_maps_js_api_key
```

Ключ создаётся в [Кабинете разработчика Яндекса](https://developer.tech.yandex.ru/keys/) для JavaScript API и должен быть ограничен разрешёнными доменами. Если provider не задан, ключ отсутствует или Yandex API не загрузился, панель показывает OSM и уведомление о fallback.

### Flutter

Flutter использует `flutter_map` и OpenStreetMap. Адрес открывается во внешнем приложении или web-версии Яндекс Карт без API-ключа. Нативный Yandex MapKit пока не подключён.

## API и WebSocket

Новые клиенты должны использовать `/api/v1`:

| Назначение | Preferred | Legacy alias |
| --- | --- | --- |
| Admin REST | `/api/v1/admin/*` | `/api/admin/*` |
| Courier REST | `/api/v1/courier/*` | `/api/courier/*` |

Legacy-маршруты совместимы, но зарегистрированы как deprecated. Основные endpoint-группы:

- Admin: login/me, admins, couriers, orders, CSV export, stats, courier locations.
- Courier: login, available/my orders, atomic take, status transitions, stats, location.

WebSocket endpoints:

- `/ws/admin`
- `/ws/courier/{courier_id}`

JWT передаётся как WebSocket subprotocol, а не query-параметр:

```javascript
const socket = new WebSocket('ws://localhost:8000/ws/admin', [accessToken])
```

Backend проверяет подпись JWT, роль, ID пользователя и его активный статус, затем принимает соединение с тем же subprotocol. Courier endpoint дополнительно требует совпадения `sub` токена с `{courier_id}`.

## Структура проекта

```text
Dostavka/
├── backend/
│   ├── app/
│   │   ├── routers/            # Admin и courier REST API
│   │   ├── services/           # Переходы статусов заказов
│   │   ├── auth.py             # JWT, bcrypt, role dependencies
│   │   ├── models.py           # SQLAlchemy models
│   │   ├── schemas.py          # Pydantic schemas
│   │   ├── ws_manager.py       # WebSocket connections/events
│   │   └── main.py             # FastAPI app и WebSocket endpoints
│   ├── alembic/                # Миграции БД
│   ├── test_*.py               # Runnable backend regression checks
│   ├── .env.example
│   ├── requirements.txt
│   └── seed.py
├── frontend/
│   ├── src/api/                # HTTP-клиенты `/api/v1`
│   ├── src/components/         # Таблицы, формы, карта, layout
│   ├── src/hooks/              # Admin WebSocket hook
│   ├── src/pages/              # Orders, couriers, map, stats, admins
│   └── package.json
├── dostavka_app/
│   ├── lib/screens/            # Admin/courier UI, login, map, settings
│   ├── lib/services/           # API, auth, WebSocket, foreground, queue
│   ├── lib/models/
│   ├── lib/utils/
│   └── test/
├── PROJECT_CONTEXT.md          # Расширенный технический контекст
├── rebuild_db.bat              # Пересоздание local SQLite DB
└── run_all.bat                 # Backend + web + Flutter
```

## Проверки

Команды запускаются отдельно в соответствующих каталогах.

### Backend

Backend использует самостоятельные assert-based regression scripts, а не pytest suite:

```powershell
cd backend
$tests = @(
  'test_config_security.py',
  'test_courier_password_auth.py',
  'test_rate_limit.py',
  'test_stage3_orders.py',
  'test_stage4_order_update.py',
  'test_stage5_2_admins_csv.py',
  'test_stage5_3_location.py',
  'test_stage7_1_multi_order.py',
  'test_websocket_subprotocol.py'
)
foreach ($test in $tests) { .\.venv\Scripts\python.exe $test; if ($LASTEXITCODE) { exit $LASTEXITCODE } }
alembic heads
alembic current
```

### Web Admin

```bat
cd frontend
npm run lint
npm run build
```

### Flutter

```bat
cd dostavka_app
flutter analyze
flutter test
```

Фактический результат на текущем commit `eb66d55417400a39b5c85d564ac8d5fe70336cad`:

| Проверка | Результат |
| --- | --- |
| Backend regression scripts | 9 из 9 завершились успешно |
| Alembic | `f5a9c81d2047` является единственной head и текущей ревизией local DB |
| Frontend `npm run lint` | 0 warnings, 0 errors |
| Frontend `npm run build` | TypeScript и Vite build успешны |
| Flutter `flutter analyze` | No issues found |
| Flutter `flutter test` | 12 tests passed |

В репозитории нет настроенного CI workflow, поэтому результаты выше относятся к локальному запуску, а не к автоматическим GitHub Actions checks. Процент покрытия не измеряется.

## Ограничения и production checklist

Проект предназначен для портфолио и локального запуска. Перед production нужны отдельные работы:

- [ ] Выполнить live integration test на PostgreSQL и использовать PostgreSQL вместо SQLite при масштабировании.
- [ ] Провести Android device E2E для логина, foreground service, геолокации, offline queue и уведомлений.
- [ ] Настроить HTTPS и release network security config без debug HTTP-разрешений.
- [ ] Добавить явный production CORS allowlist; сейчас CORS middleware не настроен.
- [ ] Вынести WebSocket state/pub-sub в Redis перед запуском нескольких backend workers.
- [ ] Настроить резервное копирование и проверяемое восстановление БД.
- [ ] Добавить monitoring, error tracking и structured logging.
- [ ] Реализовать refresh/revocation для JWT и пересмотреть хранение web-токена.
- [ ] Реализовать нативную фоновую работу и проверить жизненный цикл приложения на iOS.
- [ ] Оценить и при необходимости подключить Yandex MapKit для мобильных клиентов.
- [ ] Добавить route batching и оптимизацию порядка точек для нескольких заказов.

Docker, публичный deployment URL и CI/CD намеренно не заявлены: их нет в текущем репозитории.
