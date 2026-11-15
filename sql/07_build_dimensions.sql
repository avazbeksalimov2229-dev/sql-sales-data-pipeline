/* 07 - Clean dimension tables: date, customer, product, sales rep.            */
USE [$(DatabaseName)];
SET NOCOUNT ON;
SET XACT_ABORT ON;

-- facts reference the dimensions, so they are dropped first
DROP TABLE IF EXISTS dw.fact_returns, dw.fact_sales, dw.fact_sales_target;
DROP TABLE IF EXISTS dw.dim_customer, dw.dim_product, dw.dim_sales_rep, dw.dim_date;

/* ---------- dim_date: one row per day, language-independent names ---------- */
CREATE TABLE dw.dim_date (
    date_key       INT          NOT NULL PRIMARY KEY,   -- 20250314
    [date]         DATE         NOT NULL UNIQUE,
    [year]         SMALLINT     NOT NULL,
    [quarter]      TINYINT      NOT NULL,
    quarter_label  CHAR(7)      NOT NULL,                -- 2025-Q1
    [month]        TINYINT      NOT NULL,
    month_name     VARCHAR(10)  NOT NULL,
    month_short    CHAR(3)      NOT NULL,
    year_month     CHAR(7)      NOT NULL,                -- 2025-03
    month_start    DATE         NOT NULL,
    iso_week       TINYINT      NOT NULL,
    day_of_week    TINYINT      NOT NULL,                -- 1 = Monday
    day_name       VARCHAR(10)  NOT NULL,
    is_weekend     BIT          NOT NULL
);

WITH n AS (
    SELECT TOP (DATEDIFF(DAY, '2024-01-01', '2026-12-31') + 1)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
    FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b
), d AS (
    SELECT DATEADD(DAY, i, CAST('2024-01-01' AS DATE)) AS dt FROM n
), x AS (
    SELECT dt, MONTH(dt) AS m, DATEDIFF(DAY, '1900-01-01', dt) % 7 + 1 AS dow FROM d   -- 1900-01-01 was a Monday
)
INSERT INTO dw.dim_date
SELECT YEAR(dt) * 10000 + m * 100 + DAY(dt),
       dt,
       YEAR(dt),
       DATEPART(QUARTER, dt),
       CONCAT(YEAR(dt), '-Q', DATEPART(QUARTER, dt)),
       m,
       CHOOSE(m, 'January', 'February', 'March', 'April', 'May', 'June', 'July',
                 'August', 'September', 'October', 'November', 'December'),
       CHOOSE(m, 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'),
       CONVERT(CHAR(7), dt, 126),
       DATEFROMPARTS(YEAR(dt), m, 1),
       DATEPART(ISO_WEEK, dt),
       dow,
       CHOOSE(dow, 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'),
       CASE WHEN dow >= 6 THEN 1 ELSE 0 END
FROM x;

/* ---------- dim_sales_rep: the HR list is already clean ---------- */
CREATE TABLE dw.dim_sales_rep (
    sales_rep_id    VARCHAR(10)   NOT NULL PRIMARY KEY,
    sales_rep_name  NVARCHAR(100) NOT NULL UNIQUE,
    region          VARCHAR(10)   NOT NULL,
    hire_date       DATE          NOT NULL
);
INSERT INTO dw.dim_sales_rep
SELECT UPPER(TRIM(sales_rep_id)), TRIM(sales_rep_name), TRIM(region), etl.fn_parse_date(hire_date)
FROM stg.sales_reps;

/* ---------- dim_customer ---------- */
CREATE TABLE dw.dim_customer (
    customer_id    VARCHAR(10)   NOT NULL PRIMARY KEY,
    customer_name  NVARCHAR(100) NOT NULL,
    segment        VARCHAR(20)   NOT NULL,
    city           NVARCHAR(50)  NOT NULL,
    state_code     CHAR(2)       NOT NULL,
    state_name     VARCHAR(30)   NOT NULL,
    region         VARCHAR(10)   NOT NULL,
    signup_date    DATE          NOT NULL
);

DROP TABLE IF EXISTS #customers;
SELECT UPPER(TRIM(c.customer_id))                                  AS customer_id,
       TRIM(REPLACE(c.customer_name, '  ', ' '))                   AS customer_name,
       COALESCE(NULLIF(TRIM(c.segment), ''), 'Unknown')            AS segment,
       TRIM(c.city)                                                AS city,
       COALESCE(s.state_code, a.state_code)                        AS state_code,
       etl.fn_parse_date(c.signup_date)                            AS signup_date,
       ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(c.customer_id))
                          ORDER BY TRY_CONVERT(DATETIME2(0), c.updated_at, 120) DESC) AS version_rank,
       c.state                                                     AS raw_state,
       CONCAT_WS('|', c.customer_id, c.customer_name, c.segment, c.city, c.state, c.signup_date, c.updated_at) AS raw_values
INTO #customers
FROM stg.customers_raw AS c
LEFT JOIN ref.state       AS s ON s.state_code = UPPER(TRIM(c.state))
LEFT JOIN ref.state_alias AS a ON a.alias      = UPPER(TRIM(c.state));

INSERT INTO dq.rejected_rows (source_table, source_key, reason, raw_values)
SELECT 'customers_raw', customer_id,
       CASE WHEN state_code IS NULL THEN 'State could not be mapped' ELSE 'Signup date could not be parsed' END,
       raw_values
FROM #customers
WHERE version_rank = 1 AND (state_code IS NULL OR signup_date IS NULL);

INSERT INTO dw.dim_customer
SELECT c.customer_id, c.customer_name, c.segment, c.city, c.state_code, st.state_name, st.region, c.signup_date
FROM #customers AS c
JOIN ref.state AS st ON st.state_code = c.state_code
WHERE c.version_rank = 1 AND c.signup_date IS NOT NULL;

INSERT INTO dq.issue_log (source_table, issue, rows_affected, action_taken)
SELECT 'customers_raw', 'Older versions of the same customer', SUM(CASE WHEN version_rank > 1 THEN 1 ELSE 0 END),
       'Kept the most recent row by updated_at' FROM #customers
UNION ALL
SELECT 'customers_raw', 'State written as a name or abbreviation',
       SUM(CASE WHEN version_rank = 1 AND raw_state COLLATE Latin1_General_CS_AS <> state_code THEN 1 ELSE 0 END),
       'Mapped to the 2-letter code with ref.state_alias' FROM #customers
UNION ALL
SELECT 'customers_raw', 'Segment missing', SUM(CASE WHEN version_rank = 1 AND segment = 'Unknown' THEN 1 ELSE 0 END),
       'Set to Unknown (not guessed)' FROM #customers;

/* ---------- dim_product ---------- */
CREATE TABLE dw.dim_product (
    product_id       VARCHAR(20)   NOT NULL PRIMARY KEY,
    product_name     NVARCHAR(100) NOT NULL,
    category         VARCHAR(30)   NOT NULL,
    subcategory      VARCHAR(30)   NOT NULL,
    unit_cost        DECIMAL(10,2) NOT NULL,
    list_price       DECIMAL(10,2) NOT NULL,
    is_cost_imputed  BIT           NOT NULL
);

WITH src AS (
    SELECT UPPER(TRIM(p.sku))                  AS product_id,
           TRIM(p.product_name)                AS product_name,
           ca.category,
           TRIM(p.subcategory)                 AS subcategory,
           etl.fn_parse_money(p.unit_cost)     AS unit_cost,
           etl.fn_parse_money(p.list_price)    AS list_price
    FROM stg.products_raw AS p
    LEFT JOIN ref.category_alias AS ca ON ca.alias = UPPER(TRIM(p.category))
), ratio AS (
    -- typical cost / price ratio of the subcategory, used when the cost is missing
    SELECT subcategory, AVG(unit_cost / list_price) AS avg_cost_ratio
    FROM src
    WHERE unit_cost IS NOT NULL
    GROUP BY subcategory
)
INSERT INTO dw.dim_product
SELECT s.product_id, s.product_name, s.category, s.subcategory,
       COALESCE(s.unit_cost, CAST(ROUND(s.list_price * r.avg_cost_ratio, 2) AS DECIMAL(10,2))),
       s.list_price,
       CASE WHEN s.unit_cost IS NULL THEN 1 ELSE 0 END
FROM src AS s
LEFT JOIN ratio AS r ON r.subcategory = s.subcategory;

INSERT INTO dq.issue_log (source_table, issue, rows_affected, action_taken)
SELECT 'products_raw', 'Category spelled differently',
       SUM(CASE WHEN category COLLATE Latin1_General_CS_AS NOT IN ('Furniture', 'Office Supplies', 'Technology', 'Home & Decor') THEN 1 ELSE 0 END),
       'Mapped with ref.category_alias' FROM stg.products_raw
UNION ALL
SELECT 'products_raw', 'Unit cost missing', SUM(CAST(is_cost_imputed AS INT)),
       'Imputed: list price x average cost ratio of the subcategory (flagged is_cost_imputed)' FROM dw.dim_product;
GO
PRINT '07 dimensions built';
