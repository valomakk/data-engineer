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
LOG_PATH = os.path.join(BASE_DIR, 'logs', f'export_{datetime.now().strftime("%Y%m%d_%H%M%S")}.log')

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s',
    handlers=[
        logging.FileHandler(LOG_PATH, encoding='utf-8'),
        logging.StreamHandler()
    ]
)
log = logging.getLogger(__name__)


def export_f101():
    log.info("Начало экспорта dm.dm_f101_round_f -> CSV")
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        log.info("Подключение к БД успешно")
        cur = conn.cursor()

        cur.execute("SELECT * FROM dm.dm_f101_round_f")
        rows = cur.fetchall()
        columns = [desc[0] for desc in cur.description]

        os.makedirs(os.path.dirname(CSV_PATH), exist_ok=True)
        with open(CSV_PATH, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(columns)
            writer.writerows(rows)

        log.info(f"Экспортировано строк: {len(rows)}")
        log.info(f"Файл сохранён: {CSV_PATH}")

        cur.close()
        conn.close()
    except Exception as e:
        log.error(f"Ошибка экспорта: {e}")
        raise


if __name__ == '__main__':
    export_f101()
