-- =============================================================
-- ЗАДАЧА 1.2: Создание витрин DM и процедур расчёта
-- =============================================================

-- -----------------------------------------------------------
-- ШАГ 1: Создание схемы и таблиц витрин
-- -----------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS dm;

CREATE TABLE IF NOT EXISTS dm.dm_account_turnover_f (
    on_date         DATE,
    account_rk      NUMERIC       NOT NULL,
    credit_amount   NUMERIC(23,8),
    credit_amount_rub NUMERIC(23,8),
    debet_amount    NUMERIC(23,8),
    debet_amount_rub NUMERIC(23,8)
);

CREATE TABLE IF NOT EXISTS dm.dm_account_balance_f (
    on_date         DATE,
    account_rk      NUMERIC       NOT NULL,
    balance_out     NUMERIC(23,8),
    balance_out_rub NUMERIC(23,8)
);

-- -----------------------------------------------------------
-- ШАГ 2: Процедура расчёта оборотов
-- ds.fill_account_turnover_f(i_OnDate DATE)
--
-- Алгоритм:
--   1. Удаляем записи за дату расчёта (для идемпотентности)
--   2. FULL JOIN кредитовых и дебетовых агрегатов из ft_posting_f
--   3. Умножаем на курс из md_exchange_rate_d (если нет курса — на 1)
-- -----------------------------------------------------------

CREATE OR REPLACE PROCEDURE ds.fill_account_turnover_f(i_OnDate DATE)
LANGUAGE plpgsql
AS $$
DECLARE
    v_log_id    INTEGER;
    v_rows      INTEGER;
BEGIN
    -- Лог: старт
    INSERT INTO logs.etl_log (start_time, table_name, status)
    VALUES (NOW(), 'dm.dm_account_turnover_f', 'started')
    RETURNING log_id INTO v_log_id;

    -- Удаляем записи за дату расчёта (идемпотентность)
    DELETE FROM dm.dm_account_turnover_f WHERE on_date = i_OnDate;

    -- Вставляем агрегированные обороты
    INSERT INTO dm.dm_account_turnover_f (
        on_date,
        account_rk,
        credit_amount,
        credit_amount_rub,
        debet_amount,
        debet_amount_rub
    )
    SELECT
        i_OnDate                                            AS on_date,
        COALESCE(cr.account_rk, db.account_rk)             AS account_rk,
        COALESCE(cr.credit_amount, 0)                       AS credit_amount,
        COALESCE(cr.credit_amount, 0) * COALESCE(er.reduced_cource, 1) AS credit_amount_rub,
        COALESCE(db.debet_amount, 0)                        AS debet_amount,
        COALESCE(db.debet_amount, 0)  * COALESCE(er.reduced_cource, 1) AS debet_amount_rub
    FROM
        -- Кредитовые обороты: счёт участвует как кредитовый
        (
            SELECT credit_account_rk AS account_rk,
                   SUM(credit_amount)  AS credit_amount
            FROM ds.ft_posting_f
            WHERE oper_date = i_OnDate
            GROUP BY credit_account_rk
        ) cr
        FULL JOIN
        -- Дебетовые обороты: счёт участвует как дебетовый
        (
            SELECT debet_account_rk  AS account_rk,
                   SUM(debet_amount)  AS debet_amount
            FROM ds.ft_posting_f
            WHERE oper_date = i_OnDate
            GROUP BY debet_account_rk
        ) db ON cr.account_rk = db.account_rk
        -- Курс: берём по валюте счёта на дату расчёта
        LEFT JOIN ds.md_account_d acc
            ON acc.account_rk = COALESCE(cr.account_rk, db.account_rk)
            AND i_OnDate BETWEEN acc.data_actual_date AND acc.data_actual_end_date
        LEFT JOIN ds.md_exchange_rate_d er
            ON er.currency_rk = acc.currency_rk
            AND er.data_actual_date = i_OnDate;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    -- Лог: успех
    UPDATE logs.etl_log
    SET end_time    = NOW(),
        status      = 'success',
        rows_loaded = v_rows
    WHERE log_id = v_log_id;

EXCEPTION WHEN OTHERS THEN
    UPDATE logs.etl_log
    SET end_time      = NOW(),
        status        = 'error',
        error_message = SQLERRM
    WHERE log_id = v_log_id;
    RAISE;
END;
$$;

-- -----------------------------------------------------------
-- ШАГ 3: Начальные остатки за 31.12.2017 из DS.FT_BALANCE_F
--
-- Заполняем DM_ACCOUNT_BALANCE_F стартовыми данными.
-- Это точка отсчёта для цепочки расчётов за январь 2018.
-- -----------------------------------------------------------

DELETE FROM dm.dm_account_balance_f WHERE on_date = '2017-12-31';

INSERT INTO dm.dm_account_balance_f (on_date, account_rk, balance_out, balance_out_rub)
SELECT
    b.on_date,
    b.account_rk,
    b.balance_out,
    b.balance_out * COALESCE(er.reduced_cource, 1) AS balance_out_rub
FROM ds.ft_balance_f b
LEFT JOIN ds.md_account_d acc
    ON acc.account_rk = b.account_rk
    AND b.on_date BETWEEN acc.data_actual_date AND acc.data_actual_end_date
LEFT JOIN ds.md_exchange_rate_d er
    ON er.currency_rk = acc.currency_rk
    AND er.data_actual_date = b.on_date
WHERE b.on_date = '2017-12-31';

-- -----------------------------------------------------------
-- ШАГ 4: Процедура расчёта остатков
-- ds.fill_account_balance_f(i_OnDate DATE)
--
-- Алгоритм:
--   1. Берём все счета, актуальные на дату расчёта
--   2. Для каждого: остаток[вчера] + обороты по алгоритму А/П
--   3. Умножаем на курс для рублёвого эквивалента
-- -----------------------------------------------------------

CREATE OR REPLACE PROCEDURE ds.fill_account_balance_f(i_OnDate DATE)
LANGUAGE plpgsql
AS $$
DECLARE
    v_log_id    INTEGER;
    v_rows      INTEGER;
BEGIN
    -- Лог: старт
    INSERT INTO logs.etl_log (start_time, table_name, status)
    VALUES (NOW(), 'dm.dm_account_balance_f', 'started')
    RETURNING log_id INTO v_log_id;

    -- Удаляем записи за дату расчёта (идемпотентность)
    DELETE FROM dm.dm_account_balance_f WHERE on_date = i_OnDate;

    INSERT INTO dm.dm_account_balance_f (on_date, account_rk, balance_out, balance_out_rub)
    SELECT
        i_OnDate AS on_date,
        acc.account_rk,
        -- Расчёт остатка в валюте счёта
        CASE acc.char_type
            WHEN 'А' THEN
                -- Активный: вчера + дебет - кредит
                COALESCE(prev.balance_out, 0)
                + COALESCE(t.debet_amount, 0)
                - COALESCE(t.credit_amount, 0)
            WHEN 'П' THEN
                -- Пассивный: вчера - дебет + кредит
                COALESCE(prev.balance_out, 0)
                - COALESCE(t.debet_amount, 0)
                + COALESCE(t.credit_amount, 0)
            ELSE
                COALESCE(prev.balance_out, 0)
        END AS balance_out,
        -- Расчёт рублёвого остатка
        CASE acc.char_type
            WHEN 'А' THEN
                COALESCE(prev.balance_out_rub, 0)
                + COALESCE(t.debet_amount_rub, 0)
                - COALESCE(t.credit_amount_rub, 0)
            WHEN 'П' THEN
                COALESCE(prev.balance_out_rub, 0)
                - COALESCE(t.debet_amount_rub, 0)
                + COALESCE(t.credit_amount_rub, 0)
            ELSE
                COALESCE(prev.balance_out_rub, 0)
        END AS balance_out_rub
    FROM
        -- Все счета, актуальные на дату расчёта
        ds.md_account_d acc
        -- Остаток за предыдущий день
        LEFT JOIN dm.dm_account_balance_f prev
            ON prev.account_rk = acc.account_rk
            AND prev.on_date = i_OnDate - INTERVAL '1 day'
        -- Обороты за текущий день (могут отсутствовать)
        LEFT JOIN dm.dm_account_turnover_f t
            ON t.account_rk = acc.account_rk
            AND t.on_date = i_OnDate
    WHERE
        i_OnDate BETWEEN acc.data_actual_date AND acc.data_actual_end_date;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    -- Лог: успех
    UPDATE logs.etl_log
    SET end_time    = NOW(),
        status      = 'success',
        rows_loaded = v_rows
    WHERE log_id = v_log_id;

EXCEPTION WHEN OTHERS THEN
    UPDATE logs.etl_log
    SET end_time      = NOW(),
        status        = 'error',
        error_message = SQLERRM
    WHERE log_id = v_log_id;
    RAISE;
END;
$$;
