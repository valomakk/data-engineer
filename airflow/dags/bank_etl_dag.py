from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime
import pandas as pd
import psycopg2
import time
import os

DB_CONFIG = {
    'host': 'host.docker.internal',  # подключение к PostgreSQL на хост-машине
    'port': 5432,
    'database': 'bank_db',
    'user': 'postgres',
    'password': '123'
}

CSV_DIR = '/opt/airflow/csv_data'


def log_start(conn, table_name):
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO logs.etl_log (start_time, table_name, status) VALUES (%s, %s, 'started') RETURNING log_id",
        (datetime.now(), table_name)
    )
    log_id = cur.fetchone()[0]
    conn.commit()
    return log_id


def log_end(conn, log_id, table_name, rows, status='success', error=None):
    cur = conn.cursor()
    cur.execute(
        "UPDATE logs.etl_log SET end_time=%s, status=%s, rows_loaded=%s, error_message=%s WHERE log_id=%s",
        (datetime.now(), status, rows, error, log_id)
    )
    conn.commit()


def load_ft_balance_f():
    conn = psycopg2.connect(**DB_CONFIG)
    log_id = log_start(conn, 'ds.ft_balance_f')
    time.sleep(5)
    try:
        df = pd.read_csv(os.path.join(CSV_DIR, 'ft_balance_f.csv'), sep=';', encoding='utf-8')
        df.columns = df.columns.str.lower()
        df['on_date'] = pd.to_datetime(df['on_date'], format='%d.%m.%Y')
        cur = conn.cursor()
        for _, row in df.iterrows():
            cur.execute("""
                INSERT INTO ds.ft_balance_f (on_date, account_rk, currency_rk, balance_out)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (on_date, account_rk)
                DO UPDATE SET currency_rk=EXCLUDED.currency_rk, balance_out=EXCLUDED.balance_out
            """, (row['on_date'], row['account_rk'], row['currency_rk'], row['balance_out']))
        conn.commit()
        log_end(conn, log_id, 'ds.ft_balance_f', len(df))
    except Exception as e:
        conn.rollback()
        log_end(conn, log_id, 'ds.ft_balance_f', 0, status='error', error=str(e))
        raise
    finally:
        conn.close()


def load_ft_posting_f():
    conn = psycopg2.connect(**DB_CONFIG)
    log_id = log_start(conn, 'ds.ft_posting_f')
    time.sleep(5)
    try:
        df = pd.read_csv(os.path.join(CSV_DIR, 'ft_posting_f.csv'), sep=';', encoding='utf-8')
        df.columns = df.columns.str.lower()
        df['oper_date'] = pd.to_datetime(df['oper_date'], format='%d-%m-%Y')
        cur = conn.cursor()
        cur.execute('TRUNCATE TABLE ds.ft_posting_f')
        for _, row in df.iterrows():
            cur.execute("""
                INSERT INTO ds.ft_posting_f (oper_date, credit_account_rk, debet_account_rk, credit_amount, debet_amount)
                VALUES (%s, %s, %s, %s, %s)
            """, (row['oper_date'], row['credit_account_rk'], row['debet_account_rk'], row['credit_amount'], row['debet_amount']))
        conn.commit()
        log_end(conn, log_id, 'ds.ft_posting_f', len(df))
    except Exception as e:
        conn.rollback()
        log_end(conn, log_id, 'ds.ft_posting_f', 0, status='error', error=str(e))
        raise
    finally:
        conn.close()


def load_md_account_d():
    conn = psycopg2.connect(**DB_CONFIG)
    log_id = log_start(conn, 'ds.md_account_d')
    time.sleep(5)
    try:
        df = pd.read_csv(os.path.join(CSV_DIR, 'md_account_d.csv'), sep=';', encoding='utf-8')
        df.columns = df.columns.str.lower()
        df['data_actual_date'] = pd.to_datetime(df['data_actual_date'])
        df['data_actual_end_date'] = pd.to_datetime(df['data_actual_end_date'])
        cur = conn.cursor()
        for _, row in df.iterrows():
            cur.execute("""
                INSERT INTO ds.md_account_d
                    (data_actual_date, data_actual_end_date, account_rk, account_number, char_type, currency_rk, currency_code)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (data_actual_date, account_rk)
                DO UPDATE SET data_actual_end_date=EXCLUDED.data_actual_end_date,
                    account_number=EXCLUDED.account_number, char_type=EXCLUDED.char_type,
                    currency_rk=EXCLUDED.currency_rk, currency_code=EXCLUDED.currency_code
            """, (row['data_actual_date'], row['data_actual_end_date'], row['account_rk'],
                  row['account_number'], row['char_type'], row['currency_rk'], row['currency_code']))
        conn.commit()
        log_end(conn, log_id, 'ds.md_account_d', len(df))
    except Exception as e:
        conn.rollback()
        log_end(conn, log_id, 'ds.md_account_d', 0, status='error', error=str(e))
        raise
    finally:
        conn.close()


def load_md_currency_d():
    conn = psycopg2.connect(**DB_CONFIG)
    log_id = log_start(conn, 'ds.md_currency_d')
    time.sleep(5)
    try:
        df = pd.read_csv(os.path.join(CSV_DIR, 'md_currency_d.csv'), sep=';', encoding='latin-1')
        df.columns = df.columns.str.lower()
        df['data_actual_date'] = pd.to_datetime(df['data_actual_date'])
        df['data_actual_end_date'] = pd.to_datetime(df['data_actual_end_date'])
        df['currency_code'] = df['currency_code'].astype(str).str[:3]
        df['code_iso_char'] = df['code_iso_char'].astype(str).str[:3]
        cur = conn.cursor()
        for _, row in df.iterrows():
            cur.execute("""
                INSERT INTO ds.md_currency_d (currency_rk, data_actual_date, data_actual_end_date, currency_code, code_iso_char)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (currency_rk, data_actual_date)
                DO UPDATE SET data_actual_end_date=EXCLUDED.data_actual_end_date,
                    currency_code=EXCLUDED.currency_code, code_iso_char=EXCLUDED.code_iso_char
            """, (row['currency_rk'], row['data_actual_date'], row['data_actual_end_date'],
                  row['currency_code'], row['code_iso_char']))
        conn.commit()
        log_end(conn, log_id, 'ds.md_currency_d', len(df))
    except Exception as e:
        conn.rollback()
        log_end(conn, log_id, 'ds.md_currency_d', 0, status='error', error=str(e))
        raise
    finally:
        conn.close()


def load_md_exchange_rate_d():
    conn = psycopg2.connect(**DB_CONFIG)
    log_id = log_start(conn, 'ds.md_exchange_rate_d')
    time.sleep(5)
    try:
        df = pd.read_csv(os.path.join(CSV_DIR, 'md_exchange_rate_d.csv'), sep=';', encoding='utf-8')
        df.columns = df.columns.str.lower()
        df['data_actual_date'] = pd.to_datetime(df['data_actual_date'])
        df['data_actual_end_date'] = pd.to_datetime(df['data_actual_end_date'])
        cur = conn.cursor()
        for _, row in df.iterrows():
            cur.execute("""
                INSERT INTO ds.md_exchange_rate_d (data_actual_date, data_actual_end_date, currency_rk, reduced_cource, code_iso_num)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (data_actual_date, currency_rk)
                DO UPDATE SET data_actual_end_date=EXCLUDED.data_actual_end_date,
                    reduced_cource=EXCLUDED.reduced_cource, code_iso_num=EXCLUDED.code_iso_num
            """, (row['data_actual_date'], row['data_actual_end_date'], row['currency_rk'],
                  row['reduced_cource'], row['code_iso_num']))
        conn.commit()
        log_end(conn, log_id, 'ds.md_exchange_rate_d', len(df))
    except Exception as e:
        conn.rollback()
        log_end(conn, log_id, 'ds.md_exchange_rate_d', 0, status='error', error=str(e))
        raise
    finally:
        conn.close()


def load_md_ledger_account_s():
    conn = psycopg2.connect(**DB_CONFIG)
    log_id = log_start(conn, 'ds.md_ledger_account_s')
    time.sleep(5)
    try:
        df = pd.read_csv(os.path.join(CSV_DIR, 'md_ledger_account_s.csv'), sep=';', encoding='utf-8-sig')
        df.columns = df.columns.str.lower()
        df['start_date'] = pd.to_datetime(df['start_date'])
        df['end_date'] = pd.to_datetime(df['end_date'])
        cur = conn.cursor()
        for _, row in df.iterrows():
            cur.execute("""
                INSERT INTO ds.md_ledger_account_s
                    (chapter, chapter_name, section_number, section_name, subsection_name,
                     ledger1_account, ledger1_account_name, ledger_account, ledger_account_name,
                     characteristic, start_date, end_date)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                ON CONFLICT (ledger_account, start_date)
                DO UPDATE SET chapter=EXCLUDED.chapter,
                    ledger_account_name=EXCLUDED.ledger_account_name, end_date=EXCLUDED.end_date
            """, (row.get('chapter'), row.get('chapter_name'), row.get('section_number'),
                  row.get('section_name'), row.get('subsection_name'), row.get('ledger1_account'),
                  row.get('ledger1_account_name'), row['ledger_account'], row.get('ledger_account_name'),
                  row.get('characteristic'), row['start_date'], row.get('end_date')))
        conn.commit()
        log_end(conn, log_id, 'ds.md_ledger_account_s', len(df))
    except Exception as e:
        conn.rollback()
        log_end(conn, log_id, 'ds.md_ledger_account_s', 0, status='error', error=str(e))
        raise
    finally:
        conn.close()


with DAG(
    dag_id='bank_ds_etl',
    start_date=datetime(2024, 1, 1),
    schedule_interval=None,  # запуск только вручную
    catchup=False,
    description='ETL: загрузка CSV банковских данных в схему DS PostgreSQL'
) as dag:

    t1 = PythonOperator(task_id='load_ft_balance_f',        python_callable=load_ft_balance_f)
    t2 = PythonOperator(task_id='load_ft_posting_f',        python_callable=load_ft_posting_f)
    t3 = PythonOperator(task_id='load_md_account_d',        python_callable=load_md_account_d)
    t4 = PythonOperator(task_id='load_md_currency_d',       python_callable=load_md_currency_d)
    t5 = PythonOperator(task_id='load_md_exchange_rate_d',  python_callable=load_md_exchange_rate_d)
    t6 = PythonOperator(task_id='load_md_ledger_account_s', python_callable=load_md_ledger_account_s)

    t1 >> t2 >> t3 >> t4 >> t5 >> t6
