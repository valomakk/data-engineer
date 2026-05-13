# Задание 1.1 — Полное описание проекта

## Постановка задачи

В банке внедрили новую систему управления клиентами и обновили базу данных. Большую часть данных успешно перенесли. Однако в момент переключения возникли проблемы в ETL-процессе — данные за конец 2017 — начало 2018 года не попали в новую БД. Старую базу отключили, а необработанные данные сохранили в CSV-файлы.

Задача: загрузить эти CSV-файлы в детальный слой (DS) хранилища данных в PostgreSQL. Этот слой хранит «сырые» данные как есть — без агрегации и расчётов. Впоследствии на основе DS строятся витрины данных (DM) для отчётов.

---

## Используемые технологии

| Технология | Зачем |
|---|---|
| PostgreSQL 13 | Основная СУБД — хранение данных |
| pgAdmin | Визуальный интерфейс для работы с PostgreSQL |
| Python 3 | Написание ETL-скрипта |
| pandas | Чтение CSV-файлов, приведение типов данных |
| psycopg2 | Драйвер подключения Python к PostgreSQL |
| Docker Desktop | Запуск Apache Airflow в контейнере (Airflow не работает нативно на Windows) |
| Apache Airflow 2.8.0 | Оркестрация ETL: веб-интерфейс, граф задач, логи запусков |
| Git + GitHub | Хранение и публикация кода |

---

## Исходные данные

6 CSV-файлов в папке `file/`. У каждого файла свои особенности:

| Файл | Содержимое | Разделитель | Кодировка | Формат даты |
|---|---|---|---|---|
| ft_balance_f.csv | Остатки по счетам на дату | ; | UTF-8 | DD.MM.YYYY |
| ft_posting_f.csv | Банковские проводки (транзакции) | ; | UTF-8 | DD-MM-YYYY |
| md_account_d.csv | Справочник счетов | ; | UTF-8 | YYYY-MM-DD |
| md_currency_d.csv | Справочник валют | ; | Latin-1 | YYYY-MM-DD |
| md_exchange_rate_d.csv | Курсы валют | ; | UTF-8 | YYYY-MM-DD |
| md_ledger_account_s.csv | План счетов ЦБ РФ | ; | UTF-8-BOM | YYYY-MM-DD |

Разные форматы дат и кодировки — намеренная особенность задания, имитирующая реальные данные из разных источников. Каждый файл обрабатывается с учётом своих параметров.

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

**Схема** в PostgreSQL — это пространство имён внутри базы данных (как папка). Таблица `ds.ft_balance_f` означает: таблица `ft_balance_f` в схеме `ds`.

---

## Этап 1: Создание базы данных

В pgAdmin создана база данных `bank_db`.

---

## Этап 2: Создание схем и таблиц

В `bank_db` через Query Tool выполнен SQL-скрипт, который создаёт:
- схему `ds` с 6 таблицами
- схему `logs` с таблицей `etl_log`

### Таблицы схемы DS

**ds.ft_balance_f** — остатки по счетам на конкретную дату:
```sql
CREATE TABLE IF NOT EXISTS ds.ft_balance_f (
    on_date       DATE    NOT NULL,
    account_rk    NUMERIC NOT NULL,
    currency_rk   NUMERIC,
    balance_out   FLOAT,
    CONSTRAINT pk_ft_balance_f PRIMARY KEY (on_date, account_rk)
);
```

**ds.ft_posting_f** — банковские проводки (без первичного ключа):
```sql
CREATE TABLE IF NOT EXISTS ds.ft_posting_f (
    oper_date          DATE    NOT NULL,
    credit_account_rk  NUMERIC NOT NULL,
    debet_account_rk   NUMERIC NOT NULL,
    credit_amount      FLOAT,
    debet_amount       FLOAT
);
```

**ds.md_account_d** — справочник счетов:
```sql
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
```

**ds.md_currency_d** — справочник валют:
```sql
CREATE TABLE IF NOT EXISTS ds.md_currency_d (
    currency_rk          NUMERIC   NOT NULL,
    data_actual_date     DATE      NOT NULL,
    data_actual_end_date DATE,
    currency_code        VARCHAR(3),
    code_iso_char        VARCHAR(3),
    CONSTRAINT pk_md_currency_d PRIMARY KEY (currency_rk, data_actual_date)
);
```

**ds.md_exchange_rate_d** — курсы валют:
```sql
CREATE TABLE IF NOT EXISTS ds.md_exchange_rate_d (
    data_actual_date     DATE     NOT NULL,
    data_actual_end_date DATE,
    currency_rk          NUMERIC  NOT NULL,
    reduced_cource       FLOAT,
    code_iso_num         VARCHAR(3),
    CONSTRAINT pk_md_exchange_rate_d PRIMARY KEY (data_actual_date, currency_rk)
);
```

**ds.md_ledger_account_s** — план счетов ЦБ (28 полей, ключевые):
```sql
CREATE TABLE IF NOT EXISTS ds.md_ledger_account_s (
    ledger_account  INTEGER NOT NULL,
    start_date      DATE    NOT NULL,
    end_date        DATE,
    chapter         CHAR(1),
    chapter_name    VARCHAR(16),
    -- ... остальные поля
    CONSTRAINT pk_md_ledger_account_s PRIMARY KEY (ledger_account, start_date)
);
```

### Таблица логов

**logs.etl_log** — фиксирует каждый запуск загрузки:
```sql
CREATE TABLE IF NOT EXISTS logs.etl_log (
    log_id        SERIAL PRIMARY KEY,
    start_time    TIMESTAMP,
    end_time      TIMESTAMP,
    table_name    VARCHAR(100),
    status        VARCHAR(20),   -- 'started', 'success', 'error'
    rows_loaded   INTEGER,
    error_message TEXT
);
```

---

## Этап 3: ETL-скрипт на Python

### Файл: `etl/load_ds.py`

Скрипт для запуска вручную через командную строку. Логика одна для всех таблиц:

```
1. Подключиться к PostgreSQL (bank_db)
2. Записать в logs.etl_log: старт (status='started')
3. Подождать 5 секунд (требование задания — видна разница start/end time)
4. Прочитать CSV-файл в pandas DataFrame
5. Привести типы данных (даты в нужный формат, строки обрезать)
6. Для каждой строки выполнить INSERT с Upsert-логикой
7. Записать в logs.etl_log: финиш (status='success', rows_loaded=N)
8. При ошибке: откатить транзакцию, записать status='error' с текстом ошибки
```

### Подключение к базе данных:

```python
DB_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'database': 'bank_db',
    'user': 'postgres',
    'password': '123'
}
```

### Стратегия загрузки: Upsert

Для таблиц с первичным ключом используется `INSERT ... ON CONFLICT DO UPDATE` — «вставить, а если уже есть — обновить»:

```sql
INSERT INTO ds.ft_balance_f (on_date, account_rk, currency_rk, balance_out)
VALUES (...)
ON CONFLICT (on_date, account_rk)
DO UPDATE SET currency_rk = EXCLUDED.currency_rk,
             balance_out  = EXCLUDED.balance_out
```

Это значит: если запись с таким `on_date + account_rk` уже есть — обновить `balance_out`. Если нет — вставить новую. Именно это позволяет запускать ETL повторно без дублирования данных.

### Стратегия загрузки ft_posting_f: TRUNCATE + INSERT

У `ft_posting_f` нет первичного ключа (одна проводка не имеет уникального идентификатора). Поэтому перед каждой загрузкой таблица полностью очищается:

```python
cur.execute('TRUNCATE TABLE ds.ft_posting_f')
# затем вставляются все строки заново
```

### Особенности обработки каждого файла

**ft_balance_f.csv** — дата в формате `DD.MM.YYYY`:
```python
df['on_date'] = pd.to_datetime(df['on_date'], format='%d.%m.%Y')
```

**ft_posting_f.csv** — дата в формате `DD-MM-YYYY` (дефис вместо точки):
```python
df['oper_date'] = pd.to_datetime(df['oper_date'], format='%d-%m-%Y')
```

**md_currency_d.csv** — кодировка `latin-1`, строки обрезаются до 3 символов:
```python
df = pd.read_csv(..., encoding='latin-1')
df['currency_code'] = df['currency_code'].astype(str).str[:3]
df['code_iso_char']  = df['code_iso_char'].astype(str).str[:3]
```
Обрезка нужна потому что в CSV встречаются значения длиннее, чем позволяет тип `VARCHAR(3)` в таблице.

**md_ledger_account_s.csv** — кодировка `utf-8-sig` (UTF-8 с BOM-маркером):
```python
df = pd.read_csv(..., encoding='utf-8-sig')
```

### Логирование

Каждая функция загрузки работает так:

```python
def load_ft_balance_f():
    conn = psycopg2.connect(**DB_CONFIG)
    log_id = log_start(conn, 'ds.ft_balance_f')   # записать старт
    time.sleep(5)                                  # пауза 5 сек
    try:
        # ... чтение CSV и загрузка ...
        log_end(conn, log_id, 'ds.ft_balance_f', len(df))  # успех
    except Exception as e:
        conn.rollback()
        log_end(conn, log_id, 'ds.ft_balance_f', 0, status='error', error=str(e))
        raise
    finally:
        conn.close()
```

### Результат загрузки (реальные данные)

| Таблица | Загружено строк |
|---|---|
| ds.ft_balance_f | 114 |
| ds.ft_posting_f | 33 892 |
| ds.md_account_d | 112 |
| ds.md_currency_d | 50 |
| ds.md_exchange_rate_d | 892 |
| ds.md_ledger_account_s | 18 |

---

## Этап 4: Оркестрация через Apache Airflow

### Зачем Airflow

Вместо запуска ETL-скрипта вручную из командной строки — управление через веб-интерфейс с:
- визуальным графом задач
- историей запусков
- логами каждой задачи
- возможностью запуска по расписанию или вручную

### Зачем Docker

Airflow не работает нативно на Windows. Docker запускает Linux-контейнер внутри Windows, где Airflow работает в штатном режиме.

### Файл: `airflow/docker-compose.yml`

Описывает 4 сервиса:
- `postgres-airflow` — PostgreSQL для внутренних нужд Airflow (не наша БД)
- `airflow-init` — инициализация БД Airflow и создание пользователя admin
- `airflow-webserver` — веб-интерфейс на порту 8080
- `airflow-scheduler` — планировщик задач

```yaml
x-airflow-common: &airflow-common
  image: apache/airflow:2.8.0
  volumes:
    - ./dags:/opt/airflow/dags          # папка с DAG-файлами
    - ../file:/opt/airflow/csv_data     # CSV-файлы доступны внутри контейнера
```

Том `../file:/opt/airflow/csv_data` подключает нашу папку с CSV-файлами внутрь контейнера — DAG читает их по пути `/opt/airflow/csv_data/`.

### Файл: `airflow/dags/bank_etl_dag.py`

DAG (Directed Acyclic Graph) — граф задач. 6 задач выполняются последовательно:

```
load_ft_balance_f → load_ft_posting_f → load_md_account_d
    → load_md_currency_d → load_md_exchange_rate_d → load_md_ledger_account_s
```

Каждая задача — это `PythonOperator`, который вызывает функцию загрузки таблицы.

Подключение к PostgreSQL из контейнера:
```python
DB_CONFIG = {
    'host': 'host.docker.internal',  # специальный адрес хост-машины из Docker
    'port': 5432,
    'database': 'bank_db',
    'user': 'postgres',
    'password': '123'
}
```

`host.docker.internal` — это зарезервированный DNS-адрес Docker, который всегда указывает на хост-машину из контейнера. Вместо `localhost` (который внутри контейнера указывает на сам контейнер).

DAG запускается только вручную (`schedule_interval=None`):
```python
with DAG(
    dag_id='bank_ds_etl',
    start_date=datetime(2024, 1, 1),
    schedule_interval=None,   # только ручной запуск
    catchup=False
) as dag:
    t1 = PythonOperator(task_id='load_ft_balance_f', python_callable=load_ft_balance_f)
    ...
    t1 >> t2 >> t3 >> t4 >> t5 >> t6
```

### Запуск Airflow

```powershell
cd "C:\Users\Lera\Documents\data engineer\airflow"
docker compose up -d airflow-webserver airflow-scheduler
```

Открыть http://localhost:8080 → логин `admin`, пароль `admin` → найти DAG `bank_ds_etl` → нажать ▶ Trigger DAG.

---

## Этап 5: Публикация на GitHub

### Репозиторий

Код опубликован по адресу: **https://github.com/valomakk/data-engineer**

### Структура репозитория

```
data-engineer/
├── file/                        # исходные CSV-файлы
│   ├── ft_balance_f.csv
│   ├── ft_posting_f.csv
│   ├── md_account_d.csv
│   ├── md_currency_d.csv
│   ├── md_exchange_rate_d.csv
│   └── md_ledger_account_s.csv
├── etl/
│   └── load_ds.py               # ETL-скрипт для запуска вручную
├── airflow/
│   ├── docker-compose.yml       # конфигурация Docker для Airflow
│   └── dags/
│       └── bank_etl_dag.py      # DAG (граф задач) для Airflow
├── docs/
│   ├── task1_1_assignment.md    # условие задания
│   └── task1_1_documentation.md # техническая документация
└── .gitignore                   # исключения: логи Docker, кэш Python
```

### Почему нужен .gitignore

Docker создаёт символические ссылки (symlinks) в папке `airflow/logs/`. Git на Windows не умеет с ними работать и выдаёт ошибку при попытке добавить файлы. Решение — исключить эту папку из репозитория:

```
airflow/logs/
airflow/plugins/
__pycache__/
*.pyc
.env
```

---

## Демонстрация Upsert (режим «Запись или замена»)

### Что такое Upsert

Upsert = UPDATE + INSERT. При повторном запуске ETL данные не дублируются — существующие записи обновляются, новые добавляются. Это реализовано через `ON CONFLICT DO UPDATE`.

### Демонстрация на примере ft_balance_f

**Шаг 1.** В pgAdmin выполнить:
```sql
TRUNCATE TABLE ds.ft_balance_f;
SELECT COUNT(*) FROM ds.ft_balance_f;  -- результат: 0
```

**Шаг 2.** Запустить ETL (через Airflow или `load_ds.py`).

**Шаг 3.** Проверить:
```sql
SELECT COUNT(*) FROM ds.ft_balance_f;  -- результат: 114
SELECT account_rk, balance_out FROM ds.ft_balance_f LIMIT 5;
```

**Шаг 4.** Запомнить `balance_out` для любого `account_rk`. Открыть `file/ft_balance_f.csv`, найти эту строку, изменить значение `balance_out` на `999999`, сохранить.

**Шаг 5.** Запустить ETL снова.

**Шаг 6.** Проверить — значение обновилось:
```sql
SELECT account_rk, balance_out FROM ds.ft_balance_f
WHERE account_rk = <нужный_rk>;
-- balance_out = 999999
```

Это подтверждает работу Upsert: старая запись не удалилась и не задублировалась — поле обновилось.

---

## Проверка логов

После каждого запуска ETL в `logs.etl_log` появляются записи:

```sql
SELECT * FROM logs.etl_log ORDER BY log_id;
```

| log_id | table_name | status | rows_loaded | start_time | end_time |
|---|---|---|---|---|---|
| 1 | ds.ft_balance_f | success | 114 | 2024-... | 2024-... |
| 2 | ds.ft_posting_f | success | 33892 | 2024-... | 2024-... |
| ... | ... | ... | ... | ... | ... |

---

## Итог

| Что сделано | Результат |
|---|---|
| Создана БД bank_db с схемами DS и LOGS | ✓ |
| Созданы 6 таблиц DS + таблица логов | ✓ |
| Написан ETL-скрипт на Python | ✓ |
| Все 6 CSV загружены в PostgreSQL | ✓ (33 896 + 1 078 строк) |
| Реализован Upsert (ON CONFLICT DO UPDATE) | ✓ |
| ft_posting_f загружается через TRUNCATE | ✓ |
| Логирование в logs.etl_log | ✓ |
| Airflow DAG с 6 задачами запущен в Docker | ✓ |
| Код опубликован на GitHub | ✓ |
