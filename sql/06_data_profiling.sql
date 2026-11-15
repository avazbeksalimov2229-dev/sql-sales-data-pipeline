/* 06 - Data profiling: measure every problem before fixing anything.
   Note: SQL Server ignores trailing spaces when comparing strings,
   so DATALENGTH is used to detect them.                                         */
USE [$(DatabaseName)];
SET NOCOUNT ON;

/* ---------- 1. Issue summary ---------- */
WITH o AS (
    SELECT r.*,
           etl.fn_parse_date(r.order_date) AS od,
           etl.fn_parse_date(r.ship_date)  AS sd
    FROM stg.orders_raw AS r
)
SELECT source_table, issue, rows_found
FROM (
    SELECT 'orders_raw' AS source_table, 'Exact duplicate rows' AS issue,
           (SELECT COUNT(*) FROM stg.orders_raw)
           - (SELECT COUNT(*) FROM (SELECT DISTINCT * FROM stg.orders_raw) AS d) AS rows_found
    UNION ALL
    SELECT 'orders_raw', 'Same order line exported more than once',
           COUNT(*) - COUNT(DISTINCT UPPER(TRIM(order_id)) + '|' + TRIM(line_no))
    FROM stg.orders_raw
    UNION ALL
    SELECT 'orders_raw', 'Order date not in ISO format (YYYY-MM-DD)',
           SUM(CASE WHEN order_date NOT LIKE '[12][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]' THEN 1 ELSE 0 END) FROM o
    UNION ALL
    SELECT 'orders_raw', 'Order date that cannot be parsed', SUM(CASE WHEN od IS NULL THEN 1 ELSE 0 END) FROM o
    UNION ALL
    SELECT 'orders_raw', 'Ship date earlier than order date', SUM(CASE WHEN sd < od THEN 1 ELSE 0 END) FROM o
    UNION ALL
    SELECT 'orders_raw', 'Customer ID with extra spaces or lower case',
           SUM(CASE WHEN DATALENGTH(customer_id) <> DATALENGTH(TRIM(customer_id))
                      OR customer_id COLLATE Latin1_General_CS_AS <> UPPER(customer_id) THEN 1 ELSE 0 END) FROM o
    UNION ALL
    SELECT 'orders_raw', 'SKU in lower case',
           SUM(CASE WHEN sku COLLATE Latin1_General_CS_AS <> UPPER(sku) THEN 1 ELSE 0 END) FROM o
    UNION ALL
    SELECT 'orders_raw', 'SKU not found in product master', COUNT(*)
    FROM stg.orders_raw AS r
    WHERE NOT EXISTS (SELECT 1 FROM stg.products_raw AS p WHERE UPPER(TRIM(p.sku)) = UPPER(TRIM(r.sku)))
    UNION ALL
    SELECT 'orders_raw', 'Test orders (customer TEST)', SUM(CASE WHEN UPPER(TRIM(customer_id)) = 'TEST' THEN 1 ELSE 0 END) FROM o
    UNION ALL
    SELECT 'orders_raw', 'Quantity stored as text ("12 units", padded)',
           SUM(CASE WHEN TRY_CONVERT(INT, qty) IS NULL OR DATALENGTH(qty) <> DATALENGTH(TRIM(qty)) THEN 1 ELSE 0 END) FROM o
    UNION ALL
    SELECT 'orders_raw', 'Quantity zero or negative', SUM(CASE WHEN etl.fn_parse_int(qty) <= 0 THEN 1 ELSE 0 END) FROM o
    UNION ALL
    SELECT 'orders_raw', 'Unit price missing', SUM(CASE WHEN NULLIF(TRIM(unit_price), '') IS NULL THEN 1 ELSE 0 END) FROM o
    UNION ALL
    SELECT 'orders_raw', 'Unit price formatted as currency text ($, thousands separator)',
           SUM(CASE WHEN unit_price LIKE '%[$,]%' THEN 1 ELSE 0 END) FROM o
    UNION ALL
    SELECT 'orders_raw', 'Discount written as percent ("15%")', SUM(CASE WHEN discount LIKE '%[%]' THEN 1 ELSE 0 END) FROM o
    UNION ALL
    SELECT 'orders_raw', 'Sales rep name typed instead of rep ID',
           SUM(CASE WHEN sales_rep LIKE '% %' THEN 1 ELSE 0 END) FROM o
    UNION ALL
    SELECT 'orders_raw', 'Channel spelled differently from the standard name',
           SUM(CASE WHEN channel COLLATE Latin1_General_CS_AS NOT IN ('Online', 'Retail Store', 'Wholesale') THEN 1 ELSE 0 END) FROM o
    UNION ALL
    SELECT 'customers_raw', 'Customer ID appears more than once',
           COUNT(*) - COUNT(DISTINCT UPPER(TRIM(customer_id))) FROM stg.customers_raw
    UNION ALL
    SELECT 'customers_raw', 'State not stored as a 2-letter code',
           SUM(CASE WHEN state COLLATE Latin1_General_CS_AS NOT LIKE '[A-Z][A-Z]' THEN 1 ELSE 0 END) FROM stg.customers_raw
    UNION ALL
    SELECT 'customers_raw', 'Segment missing', SUM(CASE WHEN NULLIF(TRIM(segment), '') IS NULL THEN 1 ELSE 0 END) FROM stg.customers_raw
    UNION ALL
    SELECT 'customers_raw', 'Name with leading, trailing or double spaces',
           SUM(CASE WHEN DATALENGTH(customer_name) <> DATALENGTH(TRIM(customer_name)) OR customer_name LIKE '%  %' THEN 1 ELSE 0 END)
    FROM stg.customers_raw
    UNION ALL
    SELECT 'products_raw', 'Category spelled differently from the standard name',
           SUM(CASE WHEN category COLLATE Latin1_General_CS_AS NOT IN ('Furniture', 'Office Supplies', 'Technology', 'Home & Decor') THEN 1 ELSE 0 END)
    FROM stg.products_raw
    UNION ALL
    SELECT 'products_raw', 'Unit cost missing', SUM(CASE WHEN NULLIF(TRIM(unit_cost), '') IS NULL THEN 1 ELSE 0 END) FROM stg.products_raw
    UNION ALL
    SELECT 'products_raw', 'List price stored with "$"', SUM(CASE WHEN list_price LIKE '%$%' THEN 1 ELSE 0 END) FROM stg.products_raw
    UNION ALL
    SELECT 'returns_raw', 'Return reason spelled differently from the standard list',
           SUM(CASE WHEN reason COLLATE Latin1_General_CS_AS NOT IN ('Damaged in transit', 'Defective', 'Wrong item', 'Not as described', 'Changed mind') THEN 1 ELSE 0 END)
    FROM stg.returns_raw
) AS issues
ORDER BY source_table, rows_found DESC;

/* ---------- 2. Distinct spellings that need a mapping table ---------- */
SELECT 'channel' AS field, channel AS raw_value, COUNT(*) AS rows_found
FROM stg.orders_raw GROUP BY channel
UNION ALL
SELECT 'category', category, COUNT(*) FROM stg.products_raw GROUP BY category
UNION ALL
SELECT 'return reason', reason, COUNT(*) FROM stg.returns_raw GROUP BY reason
ORDER BY field, rows_found DESC;

/* ---------- 3. Date formats found in the order export ---------- */
SELECT date_format, COUNT(*) AS rows_found
FROM (
    SELECT CASE
        WHEN order_date LIKE '[12][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]'        THEN 'YYYY-MM-DD'
        WHEN order_date LIKE '[12][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9] %'      THEN 'YYYY-MM-DD hh:mm:ss'
        WHEN order_date LIKE '[01][0-9]/[0-3][0-9]/[12][0-9][0-9][0-9]'        THEN 'MM/DD/YYYY'
        WHEN order_date LIKE '[A-Z][a-z][a-z] [0-3][0-9], [12][0-9][0-9][0-9]' THEN 'Mon DD, YYYY'
        ELSE 'other'
    END AS date_format
    FROM stg.orders_raw
) AS f
GROUP BY date_format
ORDER BY rows_found DESC;
GO
PRINT '06 profiling done';
