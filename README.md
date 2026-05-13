# Проект: Банковское хранилище данных

ETL-пайплайн для загрузки банковских данных в PostgreSQL и расчёта аналитических витрин.

## Структура проекта

```
data-engineer/
├── task_1_1/               # Задача 1.1: Загрузка данных в слой DS
│   ├── sql/
│   │   └── task1_1_ds_tables.sql       # DDL схем и таблиц DS + logs
│   ├── load_ds.py                      # ETL-скрипт загрузки CSV → PostgreSQL
│   └── docs/
│       ├── task1_1_assignment.md
│       ├── task1_1_documentation.md
│       └── task1_1_full_description.md
│
├── task_1_2/               # Задача 1.2: Витрины оборотов и остатков
│   ├── sql/
│   │   └── task1_2_dm_tables_and_procedures.sql
│   └── docs/
│       ├── task1_2_assignment.md
│       ├── task1_2_documentation.md
│       └── task1_2_explanation.md
│
├── task_1_3/               # Задача 1.3: Витрина 101 формы
│   ├── sql/
│   │   └── task1_3_f101_procedure.sql
│   └── docs/
│       ├── task1_3_assignment.md
│       ├── task1_3_documentation.md
│       └── task1_3_explanation.md
│
├── airflow/
│   ├── dags/
│   │   ├── bank_etl_dag.py             # DAG загрузки CSV в DS (задача 1.1)
│   │   └── bank_dm_dag.py              # DAG расчёта витрин за январь 2018 (задача 1.2)
│   └── docker-compose.yml             # Запуск Airflow в Docker
│
└── file/                   # Исходные CSV и структура таблиц
```

## Архитектура

```
CSV файлы
    ↓
DS (Detail Source) — сырые данные
    ↓
DM (Data Mart) — аналитические витрины
```

### Слой DS

| Таблица | Описание |
|---------|----------|
| ds.ft_balance_f | Остатки на лицевых счетах |
| ds.ft_posting_f | Проводки |
| ds.md_account_d | Справочник лицевых счетов |
| ds.md_currency_d | Справочник валют |
| ds.md_exchange_rate_d | Курсы валют |
| ds.md_ledger_account_s | Справочник балансовых счетов |

### Слой DM

| Таблица | Описание |
|---------|----------|
| dm.dm_account_turnover_f | Обороты по лицевым счетам за день |
| dm.dm_account_balance_f | Остатки по лицевым счетам за день |
| dm.dm_f101_round_f | 101 форма (остатки и обороты по балансовым счетам за месяц) |

### Логирование

Все ETL-операции и процедуры пишут в `logs.etl_log`:
- Время старта и окончания расчёта
- Название витрины
- Статус (started / success / error)
- Количество загруженных строк
- Текст ошибки (при наличии)

## Запуск

### 1. Создать схемы и таблицы DS

```sql
-- Выполнить в pgAdmin:
task_1_1/sql/task1_1_ds_tables.sql
```

### 2. Загрузить данные в DS через Airflow

```bash
cd airflow
docker-compose up -d
# Открыть http://localhost:8080
# Запустить DAG: bank_ds_etl
```

### 3. Создать витрины и процедуры

```sql
-- Выполнить в pgAdmin:
task_1_2/sql/task1_2_dm_tables_and_procedures.sql
```

### 4. Рассчитать витрины за январь 2018

```bash
# Запустить DAG в Airflow:
bank_dm_january_2018
```

### 5. Рассчитать 101 форму

```sql
-- Выполнить в pgAdmin:
task_1_3/sql/task1_3_f101_procedure.sql
```

## Технологии

- **PostgreSQL** — база данных
- **Apache Airflow** — оркестрация ETL
- **Python** (pandas, psycopg2) — загрузка CSV
- **Docker** — запуск Airflow
