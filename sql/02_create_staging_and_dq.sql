/* 02 - Staging tables (everything as text) and data-quality tables.
   Staging columns are NVARCHAR on purpose: nothing is rejected at load time,
   every problem is handled - and logged - in the cleaning steps.               */
USE [$(DatabaseName)];
SET NOCOUNT ON;

DROP TABLE IF EXISTS stg.orders_raw;
CREATE TABLE stg.orders_raw (
    order_id     NVARCHAR(50),
    order_date   NVARCHAR(50),
    ship_date    NVARCHAR(50),
    customer_id  NVARCHAR(50),
    sales_rep    NVARCHAR(100),
    channel      NVARCHAR(50),
    line_no      NVARCHAR(20),
    sku          NVARCHAR(50),
    qty          NVARCHAR(50),
    unit_price   NVARCHAR(50),
    discount     NVARCHAR(20)
);

DROP TABLE IF EXISTS stg.customers_raw;
CREATE TABLE stg.customers_raw (
    customer_id    NVARCHAR(50),
    customer_name  NVARCHAR(200),
    segment        NVARCHAR(50),
    city           NVARCHAR(100),
    state          NVARCHAR(50),
    signup_date    NVARCHAR(50),
    updated_at     NVARCHAR(50)
);

DROP TABLE IF EXISTS stg.products_raw;
CREATE TABLE stg.products_raw (
    sku           NVARCHAR(50),
    product_name  NVARCHAR(200),
    category      NVARCHAR(50),
    subcategory   NVARCHAR(50),
    unit_cost     NVARCHAR(50),
    list_price    NVARCHAR(50)
);

DROP TABLE IF EXISTS stg.returns_raw;
CREATE TABLE stg.returns_raw (
    return_id     NVARCHAR(50),
    order_id      NVARCHAR(50),
    line_no       NVARCHAR(20),
    return_date   NVARCHAR(50),
    qty_returned  NVARCHAR(20),
    reason        NVARCHAR(100)
);

DROP TABLE IF EXISTS stg.sales_reps;
CREATE TABLE stg.sales_reps (
    sales_rep_id    NVARCHAR(20),
    sales_rep_name  NVARCHAR(100),
    region          NVARCHAR(20),
    hire_date       NVARCHAR(20)
);

DROP TABLE IF EXISTS stg.sales_targets;
CREATE TABLE stg.sales_targets (
    month_txt         NVARCHAR(20),
    region            NVARCHAR(20),
    target_net_sales  NVARCHAR(30)
);

/* Data-quality log: one row per issue found, with the number of rows and the fix applied */
IF OBJECT_ID(N'dq.issue_log') IS NULL
    CREATE TABLE dq.issue_log (
        log_id         INT IDENTITY(1, 1) PRIMARY KEY,
        logged_at      DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
        source_table   VARCHAR(50)   NOT NULL,
        issue          VARCHAR(200)  NOT NULL,
        rows_affected  INT           NOT NULL,
        action_taken   VARCHAR(200)  NOT NULL
    );

/* Rows that could not be fixed are kept here instead of being silently dropped */
IF OBJECT_ID(N'dq.rejected_rows') IS NULL
    CREATE TABLE dq.rejected_rows (
        reject_id     INT IDENTITY(1, 1) PRIMARY KEY,
        rejected_at   DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
        source_table  VARCHAR(50)    NOT NULL,
        source_key    NVARCHAR(100)  NULL,
        reason        VARCHAR(200)   NOT NULL,
        raw_values    NVARCHAR(1000) NULL
    );

TRUNCATE TABLE dq.issue_log;
TRUNCATE TABLE dq.rejected_rows;
GO
PRINT '02 staging and data-quality tables ready';
