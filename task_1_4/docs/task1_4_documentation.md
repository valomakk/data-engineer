# Документация: Задача 1.4 — Экспорт и импорт CSV

## Файлы

| Файл | Назначение |
|------|------------|
| `task_1_4/export_f101.py` | Выгрузка `dm.dm_f101_round_f` → CSV |
| `task_1_4/import_f101.py` | Загрузка CSV → `dm.dm_f101_round_f_v2` |
| `task_1_4/data/f101_export.csv` | Выгруженный файл (первая строка — заголовки) |
| `task_1_4/logs/` | Лог-файлы экспорта и импорта |
| `task_1_4/demo_video.txt` | Ссылка на демо-видео |

## Предусловие

Выполнены задачи 1.1, 1.2, 1.3. Таблица `dm.dm_f101_round_f` заполнена.

## Порядок выполнения

### 1. Экспорт

```bash
python task_1_4/export_f101.py
```

Скрипт:
1. Подключается к `bank_db`
2. Выполняет `SELECT * FROM dm.dm_f101_round_f`
3. Записывает результат в `task_1_4/data/f101_export.csv` (первая строка — имена колонок)
4. Логирует количество строк, путь к файлу, время

### 2. Редактирование CSV (опционально)

Открыть `data/f101_export.csv` и вручную изменить несколько значений для проверки импорта.

### 3. Импорт

```bash
python task_1_4/import_f101.py
```

Скрипт:
1. Подключается к `bank_db`
2. Создаёт таблицу `dm.dm_f101_round_f_v2` (если не существует)
3. Читает CSV построчно
4. Вставляет строки в `dm.dm_f101_round_f_v2`
5. Логирует количество загруженных строк и ошибки

### 4. Проверка результата

```sql
SELECT * FROM dm.dm_f101_round_f_v2;

SELECT COUNT(*) FROM dm.dm_f101_round_f_v2;

-- Сравнить изменённые строки с оригиналом
SELECT v2.ledger_account, v2.balance_in_rub, orig.balance_in_rub
FROM dm.dm_f101_round_f_v2 v2
JOIN dm.dm_f101_round_f orig USING (from_date, to_date, ledger_account, characteristic)
WHERE v2.balance_in_rub != orig.balance_in_rub;
```

## Логирование

Лог-файлы создаются в `task_1_4/logs/`:
- `export_YYYYMMDD_HHMMSS.log` — лог экспорта
- `import_YYYYMMDD_HHMMSS.log` — лог импорта

Формат записей:
```
2026-05-14 21:29:50,123 INFO Начало экспорта dm.dm_f101_round_f -> CSV
2026-05-14 21:29:50,156 INFO Подключение к БД успешно
2026-05-14 21:29:50,180 INFO Экспортировано строк: 18
2026-05-14 21:29:50,181 INFO Файл сохранён: .../data/f101_export.csv
```
