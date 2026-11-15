/* 09 - Data-quality report: what was found, what was done, and proof that
   no row was lost (raw rows = clean rows + rejected rows).                    */
USE [$(DatabaseName)];
SET NOCOUNT ON;

/* ---------- issues and the fix applied ---------- */
SELECT source_table, issue, rows_affected, action_taken
FROM dq.issue_log
WHERE rows_affected > 0
ORDER BY source_table, rows_affected DESC;

/* ---------- reconciliation ---------- */
WITH counts AS (
    SELECT 'orders_raw -> fact_sales' AS flow,
           (SELECT COUNT(*) FROM stg.orders_raw)                                            AS raw_rows,
           (SELECT COUNT(*) FROM dw.fact_sales)                                             AS clean_rows,
           (SELECT COUNT(*) FROM dq.rejected_rows WHERE source_table = 'orders_raw')        AS rejected_rows
    UNION ALL
    SELECT 'returns_raw -> fact_returns',
           (SELECT COUNT(*) FROM stg.returns_raw),
           (SELECT COUNT(*) FROM dw.fact_returns),
           (SELECT COUNT(*) FROM dq.rejected_rows WHERE source_table = 'returns_raw')
    UNION ALL
    SELECT 'customers_raw -> dim_customer',
           (SELECT COUNT(*) FROM stg.customers_raw),
           (SELECT COUNT(*) FROM dw.dim_customer),
           (SELECT COUNT(*) FROM stg.customers_raw) - (SELECT COUNT(DISTINCT UPPER(TRIM(customer_id))) FROM stg.customers_raw)
)
SELECT flow, raw_rows, clean_rows, rejected_rows,
       CASE WHEN raw_rows = clean_rows + rejected_rows THEN 'OK' ELSE 'CHECK' END AS reconciled
FROM counts;

/* ---------- headline numbers of the clean data ---------- */
SELECT COUNT(*)                           AS order_lines,
       COUNT(DISTINCT order_id)           AS orders,
       COUNT(DISTINCT customer_id)        AS customers,
       MIN(order_date)                    AS first_order,
       MAX(order_date)                    AS last_order,
       SUM(net_sales)                     AS net_sales,
       SUM(gross_profit)                  AS gross_profit,
       CAST(SUM(gross_profit) / SUM(net_sales) AS DECIMAL(5,4)) AS gross_margin
FROM dw.fact_sales;
GO
PRINT '09 data-quality report done';
