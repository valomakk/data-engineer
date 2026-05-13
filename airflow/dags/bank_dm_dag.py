from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime, date, timedelta
import psycopg2

DB_CONFIG = {
    'host': 'host.docker.internal',
    'port': 5432,
    'database': 'bank_db',
    'user': 'postgres',
    'password': '123'
}

JANUARY_2018 = [date(2018, 1, d) for d in range(1, 32)]


def call_turnover(calc_date: str):
    conn = psycopg2.connect(**DB_CONFIG)
    try:
        conn.autocommit = True
        cur = conn.cursor()
        cur.execute("CALL ds.fill_account_turnover_f(%s)", (calc_date,))
    finally:
        conn.close()


def call_balance(calc_date: str):
    conn = psycopg2.connect(**DB_CONFIG)
    try:
        conn.autocommit = True
        cur = conn.cursor()
        cur.execute("CALL ds.fill_account_balance_f(%s)", (calc_date,))
    finally:
        conn.close()


with DAG(
    dag_id='bank_dm_january_2018',
    start_date=datetime(2024, 1, 1),
    schedule_interval=None,
    catchup=False,
    description='Расчёт витрин оборотов и остатков за каждый день января 2018'
) as dag:

    prev_balance_task = None

    for calc_date in JANUARY_2018:
        date_str = calc_date.isoformat()
        safe_date = date_str.replace('-', '_')

        turnover_task = PythonOperator(
            task_id=f'turnover_{safe_date}',
            python_callable=call_turnover,
            op_kwargs={'calc_date': date_str},
        )

        balance_task = PythonOperator(
            task_id=f'balance_{safe_date}',
            python_callable=call_balance,
            op_kwargs={'calc_date': date_str},
        )

        # turnover считается до balance за тот же день
        turnover_task >> balance_task

        # balance[день N] должен завершиться до turnover[день N+1]
        # чтобы цепочка остатков была последовательной
        if prev_balance_task:
            prev_balance_task >> turnover_task

        prev_balance_task = balance_task
