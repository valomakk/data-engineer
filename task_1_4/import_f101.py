import csv
import logging
import os
from datetime import datetime

import psycopg2

DB_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'database': 'bank_db',
    'user': 'postgres',
    'password': '123'
}

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CSV_PATH = os.path.join(BASE_DIR, 'data', 'f101_export.csv')
LOG_PATH = os.path.join(BASE_DIR, 'logs', f'import_{datetime.now().strftime("%Y%m%d_%H%M%S")}.log')

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s',
    handlers=[
        logging.FileHandler(LOG_PATH, encoding='utf-8'),
        logging.StreamHandler()
    ]
)
log = logging.getLogger(__name__)

CREATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS dm.dm_f101_round_f_v2 (
    from_date           DATE,
    to_date             DATE,
    chapter             CHAR(1),
    ledger_account      CHAR(5),
    characteristic      CHAR(1),
    balance_in_rub      NUMERIC(23,8),
    balance_in_val      NUMERIC(23,8),
    balance_in_total    NUMERIC(23,8),
    turn_deb_rub        NUMERIC(23,8),
    turn_deb_val        NUMERIC(23,8),
    turn_deb_total      NUMERIC(23,8),
    turn_cre_rub        NUMERIC(23,8),
    turn_cre_val        NUMERIC(23,8),
    turn_cre_total      NUMERIC(23,8),
    balance_out_rub     NUMERIC(23,8),
    balance_out_val     NUMERIC(23,8),
    balance_out_total   NUMERIC(23,8)
);
"""


def import_f101():
    log.info("Начало импорта CSV -> dm.dm_f101_round_f_v2")
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        log.info("Подключение к БД успешно")
        cur = conn.cursor()

        cur.execute(CREATE_TABLE_SQL)
        conn.commit()
        log.info("Таблица dm.dm_f101_round_f_v2 готова")

        with open(CSV_PATH, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            columns = reader.fieldnames
            placeholders = ', '.join(['%s'] * len(columns))
            col_names = ', '.join(columns)
            insert_sql = f"INSERT INTO dm.dm_f101_round_f_v2 ({col_names}) VALUES ({placeholders})"

            rows_loaded = 0
            for row in reader:
                values = [row[col] if row[col] != '' else None for col in columns]
                cur.execute(insert_sql, values)
                rows_loaded += 1

        conn.commit()
        log.info(f"Загружено строк: {rows_loaded}")

        cur.close()
        conn.close()
    except Exception as e:
        log.error(f"Ошибка импорта: {e}")
        raise


if __name__ == '__main__':
    import_f101()
