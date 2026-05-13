-- =============================================================
-- ЗАДАЧА 1.1: Создание схем и таблиц слоя DS + логирование
-- =============================================================

-- -----------------------------------------------------------
-- Схемы
-- -----------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS ds;
CREATE SCHEMA IF NOT EXISTS logs;

-- -----------------------------------------------------------
-- Таблица логов ETL
-- -----------------------------------------------------------

CREATE TABLE IF NOT EXISTS logs.etl_log (
    log_id        SERIAL PRIMARY KEY,
    start_time    TIMESTAMP,
    end_time      TIMESTAMP,
    table_name    VARCHAR(100),
    status        VARCHAR(20),
    rows_loaded   INTEGER,
    error_message TEXT
);

-- -----------------------------------------------------------
-- DS.FT_BALANCE_F — Остатки на лицевых счетах
-- -----------------------------------------------------------

CREATE TABLE IF NOT EXISTS ds.ft_balance_f (
    on_date      DATE    NOT NULL,
    account_rk   NUMERIC NOT NULL,
    currency_rk  NUMERIC,
    balance_out  FLOAT,
    PRIMARY KEY (on_date, account_rk)
);

-- -----------------------------------------------------------
-- DS.FT_POSTING_F — Проводки
-- -----------------------------------------------------------

CREATE TABLE IF NOT EXISTS ds.ft_posting_f (
    oper_date          DATE    NOT NULL,
    credit_account_rk  NUMERIC NOT NULL,
    debet_account_rk   NUMERIC NOT NULL,
    credit_amount      FLOAT,
    debet_amount       FLOAT
);

-- -----------------------------------------------------------
-- DS.MD_ACCOUNT_D — Лицевой счёт (справочник, SCD2)
-- -----------------------------------------------------------

CREATE TABLE IF NOT EXISTS ds.md_account_d (
    data_actual_date      DATE         NOT NULL,
    data_actual_end_date  DATE         NOT NULL,
    account_rk            NUMERIC      NOT NULL,
    account_number        VARCHAR(20)  NOT NULL,
    char_type             VARCHAR(1)   NOT NULL,
    currency_rk           NUMERIC      NOT NULL,
    currency_code         VARCHAR(3)   NOT NULL,
    PRIMARY KEY (data_actual_date, account_rk)
);

-- -----------------------------------------------------------
-- DS.MD_CURRENCY_D — Валюта (справочник, SCD2)
-- -----------------------------------------------------------

CREATE TABLE IF NOT EXISTS ds.md_currency_d (
    currency_rk           NUMERIC     NOT NULL,
    data_actual_date      DATE        NOT NULL,
    data_actual_end_date  DATE,
    currency_code         VARCHAR(3),
    code_iso_char         VARCHAR(3),
    PRIMARY KEY (currency_rk, data_actual_date)
);

-- -----------------------------------------------------------
-- DS.MD_EXCHANGE_RATE_D — Курсы валют (справочник, SCD2)
-- -----------------------------------------------------------

CREATE TABLE IF NOT EXISTS ds.md_exchange_rate_d (
    data_actual_date      DATE    NOT NULL,
    data_actual_end_date  DATE,
    currency_rk           NUMERIC NOT NULL,
    reduced_cource        FLOAT,
    code_iso_num          VARCHAR(3),
    PRIMARY KEY (data_actual_date, currency_rk)
);

-- -----------------------------------------------------------
-- DS.MD_LEDGER_ACCOUNT_S — Справочник балансовых счетов
-- -----------------------------------------------------------

CREATE TABLE IF NOT EXISTS ds.md_ledger_account_s (
    chapter               CHAR(1),
    chapter_name          VARCHAR(16),
    section_number        INTEGER,
    section_name          VARCHAR(22),
    subsection_name       VARCHAR(21),
    ledger1_account       INTEGER,
    ledger1_account_name  VARCHAR(47),
    ledger_account        INTEGER      NOT NULL,
    ledger_account_name   VARCHAR(153),
    characteristic        CHAR(1),
    start_date            DATE         NOT NULL,
    end_date              DATE,
    PRIMARY KEY (ledger_account, start_date)
);
