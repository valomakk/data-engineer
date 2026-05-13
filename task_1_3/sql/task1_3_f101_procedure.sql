-- =============================================================
-- ЗАДАЧА 1.3: Витрина 101 формы DM.DM_F101_ROUND_F
-- =============================================================

-- -----------------------------------------------------------
-- ШАГ 1: Создание таблицы
-- -----------------------------------------------------------

CREATE TABLE IF NOT EXISTS dm.dm_f101_round_f (
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

-- -----------------------------------------------------------
-- ШАГ 2: Процедура расчёта 101 формы
--
-- i_OnDate — первый день месяца, СЛЕДУЮЩЕГО за отчётным.
-- Пример: для отчёта за январь 2018 → передать '2018-02-01'
--
-- Отчётный период: from_date = i_OnDate - 1 месяц
--                  to_date   = i_OnDate - 1 день
-- Входящий остаток: день перед from_date (= to_date предыдущего месяца)
-- -----------------------------------------------------------

CREATE OR REPLACE PROCEDURE dm.fill_f101_round_f(i_OnDate DATE)
LANGUAGE plpgsql
AS $$
DECLARE
    v_log_id    INTEGER;
    v_rows      INTEGER;
    v_from_date DATE;
    v_to_date   DATE;
    v_bal_date  DATE;  -- дата входящего остатка (день до from_date)
BEGIN
    v_from_date := date_trunc('month', i_OnDate) - INTERVAL '1 month';
    v_to_date   := i_OnDate - INTERVAL '1 day';
    v_bal_date  := v_from_date - INTERVAL '1 day';

    -- Лог: старт
    INSERT INTO logs.etl_log (start_time, table_name, status)
    VALUES (NOW(), 'dm.dm_f101_round_f', 'started')
    RETURNING log_id INTO v_log_id;

    -- Идемпотентность: удаляем записи за отчётный период
    DELETE FROM dm.dm_f101_round_f
    WHERE from_date = v_from_date
      AND to_date   = v_to_date;

    INSERT INTO dm.dm_f101_round_f (
        from_date, to_date,
        chapter, ledger_account, characteristic,
        balance_in_rub,   balance_in_val,   balance_in_total,
        turn_deb_rub,     turn_deb_val,     turn_deb_total,
        turn_cre_rub,     turn_cre_val,     turn_cre_total,
        balance_out_rub,  balance_out_val,  balance_out_total
    )
    SELECT
        v_from_date,
        v_to_date,
        -- Глава из справочника балансовых счетов
        las.chapter,
        -- Балансовый счёт 2-го порядка = первые 5 символов номера счёта
        CAST(LEFT(acc.account_number, 5) AS CHAR(5))    AS ledger_account,
        -- Характеристика счёта (А/П)
        acc.char_type                                    AS characteristic,

        -- Входящие остатки (на v_bal_date)
        SUM(CASE WHEN acc.currency_code IN ('810','643')
                 THEN b_in.balance_out_rub ELSE 0 END)  AS balance_in_rub,
        SUM(CASE WHEN acc.currency_code NOT IN ('810','643')
                 THEN b_in.balance_out_rub ELSE 0 END)  AS balance_in_val,
        SUM(COALESCE(b_in.balance_out_rub, 0))          AS balance_in_total,

        -- Дебетовые обороты за период
        SUM(CASE WHEN acc.currency_code IN ('810','643')
                 THEN t.turn_deb ELSE 0 END)             AS turn_deb_rub,
        SUM(CASE WHEN acc.currency_code NOT IN ('810','643')
                 THEN t.turn_deb ELSE 0 END)             AS turn_deb_val,
        SUM(COALESCE(t.turn_deb, 0))                     AS turn_deb_total,

        -- Кредитовые обороты за период
        SUM(CASE WHEN acc.currency_code IN ('810','643')
                 THEN t.turn_cre ELSE 0 END)             AS turn_cre_rub,
        SUM(CASE WHEN acc.currency_code NOT IN ('810','643')
                 THEN t.turn_cre ELSE 0 END)             AS turn_cre_val,
        SUM(COALESCE(t.turn_cre, 0))                     AS turn_cre_total,

        -- Исходящие остатки (на v_to_date)
        SUM(CASE WHEN acc.currency_code IN ('810','643')
                 THEN b_out.balance_out_rub ELSE 0 END)  AS balance_out_rub,
        SUM(CASE WHEN acc.currency_code NOT IN ('810','643')
                 THEN b_out.balance_out_rub ELSE 0 END)  AS balance_out_val,
        SUM(COALESCE(b_out.balance_out_rub, 0))          AS balance_out_total

    FROM ds.md_account_d acc

    -- Справочник балансовых счетов (по первым 5 символам номера счёта)
    LEFT JOIN ds.md_ledger_account_s las
        ON las.ledger_account = CAST(LEFT(acc.account_number, 5) AS INTEGER)
        AND v_from_date BETWEEN las.start_date AND COALESCE(las.end_date, '9999-12-31')

    -- Входящий остаток: день перед началом периода
    LEFT JOIN dm.dm_account_balance_f b_in
        ON b_in.account_rk = acc.account_rk
        AND b_in.on_date = v_bal_date

    -- Обороты за период: агрегируем по счёту за все дни периода
    LEFT JOIN (
        SELECT account_rk,
               SUM(debet_amount_rub)  AS turn_deb,
               SUM(credit_amount_rub) AS turn_cre
        FROM dm.dm_account_turnover_f
        WHERE on_date BETWEEN v_from_date AND v_to_date
        GROUP BY account_rk
    ) t ON t.account_rk = acc.account_rk

    -- Исходящий остаток: последний день периода
    LEFT JOIN dm.dm_account_balance_f b_out
        ON b_out.account_rk = acc.account_rk
        AND b_out.on_date = v_to_date

    -- Только счета, действовавшие в отчётном периоде
    WHERE acc.data_actual_date <= v_to_date
      AND acc.data_actual_end_date >= v_from_date

    GROUP BY las.chapter, LEFT(acc.account_number, 5), acc.char_type;

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
-- ШАГ 3: Расчёт за январь 2018
-- Передаём 2018-02-01 (первый день февраля = отчётная дата)
-- -----------------------------------------------------------

CALL dm.fill_f101_round_f('2018-02-01');
