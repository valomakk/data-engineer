# Документация: Задача 1.3 — Техническое описание

## Файлы

| Файл | Назначение |
|------|------------|
| `task_1_3/sql/task1_3_f101_procedure.sql` | DDL таблицы + процедура + запуск расчёта |

## Порядок выполнения

### Предусловие

Должны быть выполнены задачи 1.1 и 1.2:
- Схемы `ds`, `dm`, `logs` созданы
- Витрины `dm.dm_account_turnover_f` и `dm.dm_account_balance_f` заполнены за январь 2018
- Остатки за 31.12.2017 загружены в `dm.dm_account_balance_f`

### Запуск

Открыть `task_1_3/sql/task1_3_f101_procedure.sql` в pgAdmin и выполнить целиком.

Скрипт:
1. Создаёт таблицу `dm.dm_f101_round_f`
2. Создаёт процедуру `dm.fill_f101_round_f`
3. Запускает расчёт за январь 2018: `CALL dm.fill_f101_round_f('2018-02-01')`

### Проверка результата

```sql
SELECT * FROM dm.dm_f101_round_f LIMIT 20;

SELECT COUNT(*) FROM dm.dm_f101_round_f;

SELECT * FROM logs.etl_log
WHERE table_name = 'dm.dm_f101_round_f'
ORDER BY start_time DESC LIMIT 5;
```

## Идемпотентность

В начале процедура удаляет записи за отчётный период:
```sql
DELETE FROM dm.dm_f101_round_f WHERE from_date = v_from_date AND to_date = v_to_date;
```
Можно запускать повторно без дублей.
