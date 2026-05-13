# Документация: Задача 1.2 — Технические детали

## Архитектура решения

```
DS (исходные данные)          DM (витрины)
──────────────────────        ──────────────────────────────
FT_POSTING_F                  
  └─► fill_account_turnover_f ──► DM_ACCOUNT_TURNOVER_F
                                          │
FT_BALANCE_F (31.12.2017)                 │
  └─► начальные остатки ────► DM_ACCOUNT_BALANCE_F
                                          ▲
MD_ACCOUNT_D                              │
  └─► fill_account_balance_f ────────────┘
```

## Файлы

| Файл | Назначение |
|------|------------|
| `etl/task1_2_dm_tables_and_procedures.sql` | DDL таблиц + процедуры + стартовые остатки |
| `airflow/dags/bank_dm_dag.py` | DAG расчёта за январь 2018 |

## Порядок выполнения

### 1. Выполнить SQL-скрипт в pgAdmin

Открыть `etl/task1_2_dm_tables_and_procedures.sql` и выполнить целиком.

Скрипт выполняет:
1. Создаёт таблицы `dm.dm_account_turnover_f` и `dm.dm_account_balance_f`
2. Создаёт процедуру `ds.fill_account_turnover_f`
3. Загружает начальные остатки за 31.12.2017
4. Создаёт процедуру `ds.fill_account_balance_f`

### 2. Запустить DAG в Airflow

- Открыть Airflow UI: http://localhost:8080
- Найти DAG `bank_dm_january_2018`
- Нажать Trigger DAG

DAG последовательно для каждого дня января:
1. Вызывает `ds.fill_account_turnover_f(дата)`
2. Вызывает `ds.fill_account_balance_f(дата)`

### 3. Проверить результаты

```sql
-- Обороты: количество записей по дням
SELECT on_date, COUNT(*) FROM dm.dm_account_turnover_f
GROUP BY on_date ORDER BY on_date;

-- Остатки: количество записей по дням
SELECT on_date, COUNT(*) FROM dm.dm_account_balance_f
GROUP BY on_date ORDER BY on_date;

-- Логи выполнения
SELECT * FROM logs.etl_log
WHERE table_name IN ('dm.dm_account_turnover_f', 'dm.dm_account_balance_f')
ORDER BY start_time DESC LIMIT 20;
```

## Идемпотентность

Обе процедуры в начале удаляют записи за дату расчёта:
```sql
DELETE FROM dm.dm_account_turnover_f WHERE on_date = i_OnDate;
```
Это позволяет перезапускать расчёт за любой день без дублей.

## Логика курса валют

Курс берётся из `ds.md_exchange_rate_d` по полю `data_actual_date = i_OnDate`.
Если курс не найден — коэффициент равен 1 (сумма в рублях = сумма в валюте).

Связь: `md_account_d.currency_rk` → `md_exchange_rate_d.currency_rk`
