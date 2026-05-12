# Задача 1.1 — ETL загрузка CSV в PostgreSQL

## Легенда

Банк мигрировал БД. ETL-процесс сломался в конце 2017 — начале 2018.
Данные за этот период сохранили в CSV. Нужно загрузить их в детальный слой DS в PostgreSQL.

---

## Стек технологий

| Технология | Версия | Зачем |
|---|---|---|
| PostgreSQL | 13 | СУБД — хранение данных |
| pgAdmin | любая | GUI для PostgreSQL |
| Python | 3.x | ETL-скрипт |
| pandas | latest | чтение CSV, трансформация данных |
| psycopg2 | latest | драйвер подключения к PostgreSQL |
| Docker Desktop | 29.4.2 | запуск Airflow в контейнере |
| Apache Airflow | 2.8.0 | оркестрация ETL через веб-интерфейс |

---

## Архитектура хранилища

```
PostgreSQL: bank_db
├── Схема DS (Detail Store — детальный слой)
│   ├── ft_balance_f        — остатки по счетам на дату
│   ├── ft_posting_f        — проводки (транзакции)
│   ├── md_account_d        — справочник счетов
│   ├── md_currency_d       — справочник валют
│   ├── md_exchange_rate_d  — курсы валют
│   └── md_ledger_account_s — план счетов ЦБ
└── Схема LOGS
    └── etl_log             — лог запусков ETL
```

**DS** = детальный слой, сырые данные как есть из источника.  
**DM** = слой витрин, агрегированные данные для отчётов (следующие задачи).

---

## Исходные данные (CSV-файлы)

| Файл | Разделитель | Кодировка | Формат даты |
|---|---|---|---|
| ft_balance_f.csv | ; | utf-8 | DD.MM.YYYY |
| ft_posting_f.csv | ; | utf-8 | DD-MM-YYYY |
| md_account_d.csv | ; | utf-8 | YYYY-MM-DD |
| md_currency_d.csv | ; | latin-1 | YYYY-MM-DD |
| md_exchange_rate_d.csv | ; | utf-8 | YYYY-MM-DD |
| md_ledger_account_s.csv | ; | utf-8-sig (BOM) | YYYY-MM-DD |

---

## Шаг 1: Создание базы данных в pgAdmin

1. Открыть pgAdmin
2. Правая кнопка на "Databases" → Create → Database
3. Имя: `bank_db` → Save

---

## Шаг 2: Создание схем

Открыть Query Tool в `bank_db` (правая кнопка на bank_db → Query Tool).

```sql
CREATE SCHEMA IF NOT EXISTS ds;
CREATE SCHEMA IF NOT EXISTS logs;
```

**Схема** = пространство имён внутри БД, как папка. Таблица `ds.ft_balance_f` — это таблица `ft_balance_f` в схеме `ds`.

---

## Шаг 3: Создание таблиц в схеме DS

```sql
CREATE TABLE IF NOT EXISTS ds.ft_balance_f (
    on_date       DATE        NOT NULL,
    account_rk    NUMERIC     NOT NULL,
    currency_rk   NUMERIC,
    balance_out   FLOAT,
    CONSTRAINT pk_ft_balance_f PRIMARY KEY (on_date, account_rk)
);

CREATE TABLE IF NOT EXISTS ds.ft_posting_f (
    oper_date          DATE    NOT NULL,
    credit_account_rk  NUMERIC NOT NULL,
    debet_account_rk   NUMERIC NOT NULL,
    credit_amount      FLOAT,
    debet_amount       FLOAT
);

CREATE TABLE IF NOT EXISTS ds.md_account_d (
    data_actual_date     DATE        NOT NULL,
    data_actual_end_date DATE        NOT NULL,
    account_rk           NUMERIC     NOT NULL,
    account_number       VARCHAR(20) NOT NULL,
    char_type            VARCHAR(1)  NOT NULL,
    currency_rk          NUMERIC     NOT NULL,
    currency_code        VARCHAR(3)  NOT NULL,
    CONSTRAINT pk_md_account_d PRIMARY KEY (data_actual_date, account_rk)
);

CREATE TABLE IF NOT EXISTS ds.md_currency_d (
    currency_rk          NUMERIC  NOT NULL,
    data_actual_date     DATE     NOT NULL,
    data_actual_end_date DATE,
    currency_code        VARCHAR(3),
    code_iso_char        VARCHAR(3),
    CONSTRAINT pk_md_currency_d PRIMARY KEY (currency_rk, data_actual_date)
);

CREATE TABLE IF NOT EXISTS ds.md_exchange_rate_d (
    data_actual_date     DATE     NOT NULL,
    data_actual_end_date DATE,
    currency_rk          NUMERIC  NOT NULL,
    reduced_cource       FLOAT,
    code_iso_num         VARCHAR(3),
    CONSTRAINT pk_md_exchange_rate_d PRIMARY KEY (data_actual_date, currency_rk)
);

CREATE TABLE IF NOT EXISTS ds.md_ledger_account_s (
    chapter                       CHAR(1),
    chapter_name                  VARCHAR(16),
    section_number                INTEGER,
    section_name                  VARCHAR(22),
    subsection_name               VARCHAR(21),
    ledger1_account               INTEGER,
    ledger1_account_name          VARCHAR(47),
    ledger_account                INTEGER     NOT NULL,
    ledger_account_name           VARCHAR(153),
    characteristic                CHAR(1),
    is_resident                   INTEGER,
    is_reserve                    INTEGER,
    is_reserved                   INTEGER,
    is_loan                       INTEGER,
    is_reserved_assets            INTEGER,
    is_overdue                    INTEGER,
    is_interest                   INTEGER,
    pair_account                  VARCHAR(5),
    start_date                    DATE        NOT NULL,
    end_date                      DATE,
    is_rub_only                   INTEGER,
    min_term                      VARCHAR(1),
    min_term_measure              VARCHAR(1),
    max_term                      VARCHAR(1),
    max_term_measure              VARCHAR(1),
    ledger_acc_full_name_translit VARCHAR(1),
    is_revaluation                VARCHAR(1),
    is_correct                    VARCHAR(1),
    CONSTRAINT pk_md_ledger_account_s PRIMARY KEY (ledger_account, start_date)
);
```

---

## Шаг 4: Создание таблицы логов

```sql
CREATE TABLE IF NOT EXISTS logs.etl_log (
    log_id        SERIAL PRIMARY KEY,
    start_time    TIMESTAMP,
    end_time      TIMESTAMP,
    table_name    VARCHAR(100),
    status        VARCHAR(20),
    rows_loaded   INTEGER,
    error_message TEXT
);
```

**Что логируется:**
- `start_time` — когда началась загрузка таблицы
- `end_time` — когда закончилась
- `table_name` — название таблицы
- `status` — `started` / `success` / `error`
- `rows_loaded` — сколько строк загружено
- `error_message` — текст ошибки если была

---

## Шаг 5: Установка Python-библиотек

```powershell
& "C:\Users\Lera\AppData\Local\Python\bin\python.exe" -m pip install pandas psycopg2-binary sqlalchemy
```

**Почему такой путь:** на машине два Python — заглушка Microsoft Store и реальный. Нужно явно указывать реальный: `C:\Users\Lera\AppData\Local\Python\bin\python.exe`

- **pandas** — читает CSV, приводит типы данных
- **psycopg2** — драйвер для подключения Python → PostgreSQL

---

## Шаг 6: ETL-скрипт

Файл: `etl/load_ds.py`

### Принцип работы скрипта

```
для каждой таблицы:
  1. Записать в logs.etl_log: старт (status='started')
  2. Подождать 5 секунд (чтобы видна разница start/end time)
  3. Прочитать CSV в pandas DataFrame
  4. Привести типы (даты, строки)
  5. Для каждой строки: INSERT ... ON CONFLICT DO UPDATE
  6. Записать в logs.etl_log: конец (status='success', rows_loaded=N)
  7. Если ошибка: записать status='error', error_message
```

### ON CONFLICT DO UPDATE (Upsert)

Это ключевой паттерн ETL — "вставить или обновить":
- Если запись с таким PK уже есть → обновить поля
- Если нет → вставить новую

```sql
INSERT INTO ds.ft_balance_f (on_date, account_rk, currency_rk, balance_out)
VALUES (...)
ON CONFLICT (on_date, account_rk)
DO UPDATE SET balance_out = EXCLUDED.balance_out
```

### ft_posting_f — особый случай

У этой таблицы нет первичного ключа. Стратегия: **TRUNCATE + INSERT**.
Перед каждой загрузкой таблица полностью очищается, затем грузится заново.

### Особенность md_currency_d

Кодировка `latin-1` (не utf-8). Поля `currency_code` и `code_iso_char` обрезаются до 3 символов — в CSV встречаются значения длиннее, чем позволяет тип `VARCHAR(3)`.

---

## Шаг 7: Запуск ETL вручную (без Airflow)

```powershell
& "C:\Users\Lera\AppData\Local\Python\bin\python.exe" "C:\Users\Lera\Documents\data engineer\etl\load_ds.py"
```

### Результат загрузки

| Таблица | Строк |
|---|---|
| ds.ft_balance_f | 114 |
| ds.ft_posting_f | 33892 |
| ds.md_account_d | 112 |
| ds.md_currency_d | 50 |
| ds.md_exchange_rate_d | 892 |
| ds.md_ledger_account_s | 18 |

---

## Шаг 8: Проверка в pgAdmin

```sql
SELECT COUNT(*) FROM ds.ft_balance_f;
SELECT * FROM logs.etl_log ORDER BY log_id;
```

---

## Шаг 9: Демонстрация Upsert (для видео)

1. Очистить таблицу: `TRUNCATE TABLE ds.ft_balance_f CASCADE;`
2. Запустить ETL — проверить COUNT = 114
3. Запомнить `balance_out` у конкретного `account_rk`:
   ```sql
   SELECT account_rk, balance_out FROM ds.ft_balance_f WHERE account_rk = 36237725;
   ```
4. Открыть `file/ft_balance_f.csv`, изменить значение у этой строки
5. Запустить ETL снова
6. Проверить — значение обновилось

---

## Шаг 10: Оркестрация через Apache Airflow (Docker)

### Что такое Airflow

Airflow — планировщик ETL-задач. Вместо запуска скрипта вручную из PowerShell — запуск через веб-интерфейс с графом задач, логами и расписанием.

### Основные понятия

| Термин | Что это |
|---|---|
| DAG | Directed Acyclic Graph — граф задач с порядком выполнения |
| Task | Одна задача внутри DAG (загрузить одну таблицу) |
| PythonOperator | Тип задачи — запустить Python-функцию |
| Run | Один конкретный запуск DAG |

### Почему Docker

Airflow не работает нативно на Windows. Docker запускает Linux-контейнер внутри Windows где Airflow работает нормально.

### Структура файлов Airflow

```
airflow/
├── docker-compose.yml   — описание контейнеров
├── dags/
│   └── bank_etl_dag.py  — DAG с нашим ETL
├── logs/                — логи Airflow (создаётся автоматически)
└── plugins/             — расширения (пустая папка)
```

### Установка и запуск

**Предварительно:** установить Docker Desktop, обновить WSL:
```powershell
wsl --update
```

**1. Инициализация (один раз):**
```powershell
cd "C:\Users\Lera\Documents\data engineer\airflow"
docker compose down
docker compose up airflow-init
```
Ждать сообщения: `User "admin" created with role "Admin"`

**2. Запуск сервисов:**
```powershell
docker compose up -d airflow-webserver airflow-scheduler
```

**3. Открыть веб-интерфейс:**
Браузер → http://localhost:8080  
Логин: `admin`, пароль: `admin`

**4. Остановка:**
```powershell
docker compose down
```

### Граф DAG (bank_ds_etl)

```
load_ft_balance_f
       ↓
load_ft_posting_f
       ↓
load_md_account_d
       ↓
load_md_currency_d
       ↓
load_md_exchange_rate_d
       ↓
load_md_ledger_account_s
```

### Запуск DAG вручную через веб-интерфейс

1. Открыть http://localhost:8080
2. Найти DAG `bank_ds_etl`
3. Включить переключатель (toggle) слева от названия
4. Нажать кнопку ▶ (Trigger DAG)
5. Наблюдать выполнение в разделе Graph или Grid

### Подключение DAG к PostgreSQL на хост-машине

В DAG используется `host.docker.internal` вместо `localhost` — это специальный адрес Docker для доступа к хост-машине из контейнера.

```python
DB_CONFIG = {
    'host': 'host.docker.internal',  # хост-машина из контейнера
    'port': 5432,
    'database': 'bank_db',
    'user': 'postgres',
    'password': '123'
}
```

---

## Структура проекта

```
data engineer/
├── file/                            # исходные CSV-файлы
│   ├── ft_balance_f.csv
│   ├── ft_posting_f.csv
│   ├── md_account_d.csv
│   ├── md_currency_d.csv
│   ├── md_exchange_rate_d.csv
│   └── md_ledger_account_s.csv
├── etl/
│   └── load_ds.py                   # ETL-скрипт (запуск вручную)
├── airflow/
│   ├── docker-compose.yml           # конфигурация Docker
│   └── dags/
│       └── bank_etl_dag.py          # DAG для Airflow
└── docs/
    └── task1_1_documentation.md     # этот файл
```

---

## Первичные ключи таблиц

| Таблица | Первичный ключ | Стратегия загрузки |
|---|---|---|
| ds.ft_balance_f | on_date + account_rk | Upsert (INSERT ON CONFLICT) |
| ds.ft_posting_f | нет | TRUNCATE + INSERT |
| ds.md_account_d | data_actual_date + account_rk | Upsert |
| ds.md_currency_d | currency_rk + data_actual_date | Upsert |
| ds.md_exchange_rate_d | data_actual_date + currency_rk | Upsert |
| ds.md_ledger_account_s | ledger_account + start_date | Upsert |

---

## Требования к демонстрации (чеклист)

- [ ] Опубликовать код на GitHub
- [ ] Записать видео с экрана
- [ ] В видео: показать пустую таблицу → запустить ETL → показать данные
- [ ] В видео: изменить balance_out в CSV → запустить ETL → показать обновление
- [ ] В видео: показать и объяснить скрипт / DAG
- [ ] Загрузить видео на облако (Google Drive / Яндекс.Диск)
- [ ] Добавить файл `video_link.txt` со ссылкой в репозиторий
