/* 08 - Clean fact tables: sales lines, returns, targets.
   Order of work for sales lines:
     1. parse and standardise every field
     2. decide a reject reason for rows that cannot be used
     3. fix what can be fixed (swapped dates, missing price, rep names)
     4. remove duplicates on the business key (order_id + order_line)
     5. calculate the money columns                                             */
USE [$(DatabaseName)];
SET NOCOUNT ON;
SET XACT_ABORT ON;

/* ---------- 1. parse ---------- */
DROP TABLE IF EXISTS #lines;
SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL))           AS row_id,
       UPPER(TRIM(r.order_id))                              AS order_id,
       etl.fn_parse_int(r.line_no)                          AS order_line,
       etl.fn_parse_date(r.order_date)                      AS raw_order_date,
       etl.fn_parse_date(r.ship_date)                       AS raw_ship_date,
       UPPER(TRIM(r.customer_id))                           AS customer_id,
       NULLIF(TRIM(r.sales_rep), '')                        AS sales_rep_text,
       COALESCE(rid.sales_rep_id, rnm.sales_rep_id)         AS sales_rep_id,
       ch.channel,
       UPPER(TRIM(r.sku))                                   AS product_id,
       etl.fn_parse_int(r.qty)                              AS quantity,
       etl.fn_parse_money(r.unit_price)                     AS raw_unit_price,
       etl.fn_parse_discount(r.discount)                    AS discount_pct,
       p.list_price,
       p.unit_cost,
       c.customer_id                                        AS known_customer,
       CONCAT_WS('|', r.order_id, r.order_date, r.ship_date, r.customer_id, r.sales_rep, r.channel,
                 r.line_no, r.sku, r.qty, r.unit_price, r.discount) AS raw_values,
       CAST(NULL AS VARCHAR(100))                           AS reject_reason
INTO #lines
FROM stg.orders_raw AS r
LEFT JOIN ref.channel_alias  AS ch  ON ch.alias          = UPPER(TRIM(r.channel))
LEFT JOIN dw.dim_product     AS p   ON p.product_id      = UPPER(TRIM(r.sku))
LEFT JOIN dw.dim_customer    AS c   ON c.customer_id     = UPPER(TRIM(r.customer_id))
LEFT JOIN dw.dim_sales_rep   AS rid ON rid.sales_rep_id  = UPPER(TRIM(r.sales_rep))
LEFT JOIN dw.dim_sales_rep   AS rnm ON rnm.sales_rep_name = TRIM(r.sales_rep);

/* ---------- 2. reject rows that cannot be used ---------- */
UPDATE #lines
SET reject_reason = CASE
        WHEN customer_id = 'TEST' OR order_id LIKE 'SO-TEST%'     THEN 'Test order'
        WHEN raw_order_date IS NULL                               THEN 'Order date could not be parsed'
        WHEN order_line IS NULL                                   THEN 'Line number missing'
        WHEN list_price IS NULL                                   THEN 'SKU not in product master'
        WHEN known_customer IS NULL                               THEN 'Customer not in customer master'
        WHEN quantity IS NULL                                     THEN 'Quantity is not a number'
        WHEN quantity <= 0                                        THEN 'Quantity is zero or negative'
        WHEN channel IS NULL                                      THEN 'Unknown channel'
        WHEN sales_rep_text IS NOT NULL AND sales_rep_id IS NULL  THEN 'Unknown sales rep'
        WHEN discount_pct IS NULL OR discount_pct NOT BETWEEN 0 AND 0.9 THEN 'Invalid discount'
    END;

/* ---------- 3 + 4. fix and de-duplicate ---------- */
DROP TABLE IF EXISTS #clean;
SELECT l.*,
       CASE WHEN l.raw_ship_date < l.raw_order_date THEN l.raw_ship_date  ELSE l.raw_order_date END AS order_date,
       CASE WHEN l.raw_ship_date < l.raw_order_date THEN l.raw_order_date ELSE l.raw_ship_date  END AS ship_date,
       CASE WHEN l.raw_ship_date < l.raw_order_date THEN 1 ELSE 0 END                               AS is_dates_swapped,
       COALESCE(l.raw_unit_price, l.list_price)                                                     AS unit_price,
       CASE WHEN l.raw_unit_price IS NULL THEN 1 ELSE 0 END                                         AS is_price_imputed,
       ROW_NUMBER() OVER (PARTITION BY l.order_id, l.order_line ORDER BY l.row_id)                  AS copy_no
INTO #clean
FROM #lines AS l
WHERE l.reject_reason IS NULL;

-- duplicates must be true copies; if two copies disagree we want to know
DECLARE @conflicts INT = (
    SELECT COUNT(*) FROM (
        SELECT order_id, order_line
        FROM #clean
        GROUP BY order_id, order_line
        HAVING COUNT(DISTINCT CONCAT_WS('|', order_date, ship_date, customer_id, sales_rep_id, channel,
                                        product_id, quantity, unit_price, discount_pct)) > 1
    ) AS x);

INSERT INTO dq.rejected_rows (source_table, source_key, reason, raw_values)
SELECT 'orders_raw', CONCAT(order_id, '/', order_line), reject_reason, raw_values
FROM #lines WHERE reject_reason IS NOT NULL
UNION ALL
SELECT 'orders_raw', CONCAT(order_id, '/', order_line), 'Duplicate order line', raw_values
FROM #clean WHERE copy_no > 1;

/* ---------- 5. load the fact table ---------- */
CREATE TABLE dw.fact_sales (
    order_id          VARCHAR(20)   NOT NULL,
    order_line        INT           NOT NULL,
    order_date        DATE          NOT NULL,
    ship_date         DATE          NULL,
    customer_id       VARCHAR(10)   NOT NULL REFERENCES dw.dim_customer (customer_id),
    product_id        VARCHAR(20)   NOT NULL REFERENCES dw.dim_product (product_id),
    sales_rep_id      VARCHAR(10)   NULL     REFERENCES dw.dim_sales_rep (sales_rep_id),
    channel           VARCHAR(20)   NOT NULL,
    quantity          INT           NOT NULL CHECK (quantity > 0),
    unit_price        DECIMAL(10,2) NOT NULL,
    discount_pct      DECIMAL(5,4)  NOT NULL,
    gross_sales       DECIMAL(12,2) NOT NULL,
    discount_amount   DECIMAL(12,2) NOT NULL,
    net_sales         DECIMAL(12,2) NOT NULL,
    cost              DECIMAL(12,2) NOT NULL,
    gross_profit      DECIMAL(12,2) NOT NULL,
    is_price_imputed  BIT           NOT NULL,
    is_dates_swapped  BIT           NOT NULL,
    CONSTRAINT PK_fact_sales PRIMARY KEY (order_id, order_line)
);

INSERT INTO dw.fact_sales
SELECT order_id, order_line, order_date, ship_date, customer_id, product_id, sales_rep_id, channel,
       quantity, unit_price, discount_pct,
       g.gross_sales,
       g.gross_sales - n.net_sales,
       n.net_sales,
       k.cost,
       n.net_sales - k.cost,
       is_price_imputed, is_dates_swapped
FROM #clean
CROSS APPLY (SELECT CAST(ROUND(quantity * unit_price, 2) AS DECIMAL(12,2)) AS gross_sales) AS g
CROSS APPLY (SELECT CAST(ROUND(quantity * unit_price * (1 - discount_pct), 2) AS DECIMAL(12,2)) AS net_sales) AS n
CROSS APPLY (SELECT CAST(ROUND(quantity * unit_cost, 2) AS DECIMAL(12,2)) AS cost) AS k
WHERE copy_no = 1;

INSERT INTO dq.issue_log (source_table, issue, rows_affected, action_taken)
SELECT 'orders_raw', 'Same order line exported more than once', SUM(CASE WHEN copy_no > 1 THEN 1 ELSE 0 END),
       'Kept one copy per order_id + order_line' FROM #clean
UNION ALL SELECT 'orders_raw', 'Duplicate copies that disagree with each other', @conflicts,
       'Checked only - 0 means every duplicate was an exact copy'
UNION ALL SELECT 'orders_raw', 'Ship date earlier than order date', SUM(CAST(is_dates_swapped AS INT)),
       'Dates were swapped by the operator - swapped back' FROM dw.fact_sales
UNION ALL SELECT 'orders_raw', 'Unit price missing', SUM(CAST(is_price_imputed AS INT)),
       'Filled with the list price from dim_product (flagged is_price_imputed)' FROM dw.fact_sales
UNION ALL SELECT 'orders_raw', 'Sales rep name typed instead of ID',
       SUM(CASE WHEN sales_rep_text <> sales_rep_id THEN 1 ELSE 0 END), 'Mapped name to sales_rep_id'
       FROM #clean WHERE copy_no = 1
UNION ALL SELECT 'orders_raw', 'Channel spelled differently',
       (SELECT COUNT(*) FROM stg.orders_raw WHERE channel COLLATE Latin1_General_CS_AS NOT IN ('Online', 'Retail Store', 'Wholesale')),
       'Mapped with ref.channel_alias'
UNION ALL SELECT 'orders_raw', reject_reason, COUNT(*), 'Rejected - kept in dq.rejected_rows'
       FROM #lines WHERE reject_reason IS NOT NULL GROUP BY reject_reason;

/* ---------- returns ---------- */
CREATE TABLE dw.fact_returns (
    return_id          VARCHAR(20)   NOT NULL PRIMARY KEY,
    order_id           VARCHAR(20)   NOT NULL,
    order_line         INT           NOT NULL,
    return_date        DATE          NOT NULL,
    quantity_returned  INT           NOT NULL,
    return_reason      VARCHAR(30)   NOT NULL,
    refund_amount      DECIMAL(12,2) NOT NULL,
    CONSTRAINT FK_returns_sales FOREIGN KEY (order_id, order_line) REFERENCES dw.fact_sales (order_id, order_line)
);

DROP TABLE IF EXISTS #returns;
SELECT UPPER(TRIM(r.return_id))           AS return_id,
       UPPER(TRIM(r.order_id))            AS order_id,
       etl.fn_parse_int(r.line_no)        AS order_line,
       etl.fn_parse_date(r.return_date)   AS return_date,
       etl.fn_parse_int(r.qty_returned)   AS quantity_returned,
       a.reason                           AS return_reason,
       s.quantity                         AS quantity_sold,
       s.net_sales,
       CONCAT_WS('|', r.return_id, r.order_id, r.line_no, r.return_date, r.qty_returned, r.reason) AS raw_values,
       CASE
           WHEN s.order_id IS NULL                      THEN 'Order line not found in sales'
           WHEN etl.fn_parse_date(r.return_date) IS NULL THEN 'Return date could not be parsed'
           WHEN a.reason IS NULL                         THEN 'Unknown return reason'
           WHEN etl.fn_parse_int(r.qty_returned) IS NULL
             OR etl.fn_parse_int(r.qty_returned) <= 0    THEN 'Invalid returned quantity'
           WHEN etl.fn_parse_int(r.qty_returned) > s.quantity THEN 'More units returned than sold'
       END AS reject_reason
INTO #returns
FROM stg.returns_raw AS r
LEFT JOIN ref.return_reason_alias AS a ON a.alias = UPPER(TRIM(r.reason))
LEFT JOIN dw.fact_sales AS s
       ON s.order_id = UPPER(TRIM(r.order_id)) AND s.order_line = etl.fn_parse_int(r.line_no);

INSERT INTO dw.fact_returns
SELECT return_id, order_id, order_line, return_date, quantity_returned, return_reason,
       CAST(ROUND(net_sales * quantity_returned / quantity_sold, 2) AS DECIMAL(12,2))
FROM #returns
WHERE reject_reason IS NULL;

INSERT INTO dq.rejected_rows (source_table, source_key, reason, raw_values)
SELECT 'returns_raw', return_id, reject_reason, raw_values FROM #returns WHERE reject_reason IS NOT NULL;

INSERT INTO dq.issue_log (source_table, issue, rows_affected, action_taken)
SELECT 'returns_raw', 'Return reason spelled differently',
       (SELECT COUNT(*) FROM stg.returns_raw
        WHERE reason COLLATE Latin1_General_CS_AS NOT IN ('Damaged in transit', 'Defective', 'Wrong item', 'Not as described', 'Changed mind')),
       'Mapped with ref.return_reason_alias'
UNION ALL
SELECT 'returns_raw', reject_reason, COUNT(*), 'Rejected - kept in dq.rejected_rows'
FROM #returns WHERE reject_reason IS NOT NULL GROUP BY reject_reason;

/* ---------- targets ---------- */
CREATE TABLE dw.fact_sales_target (
    month_start       DATE          NOT NULL,
    region            VARCHAR(10)   NOT NULL,
    target_net_sales  DECIMAL(14,2) NOT NULL,
    CONSTRAINT PK_fact_sales_target PRIMARY KEY (month_start, region)
);
INSERT INTO dw.fact_sales_target
SELECT DATEFROMPARTS(CAST(LEFT(month_txt, 4) AS INT), CAST(RIGHT(month_txt, 2) AS INT), 1),
       TRIM(region),
       etl.fn_parse_money(target_net_sales)
FROM stg.sales_targets
WHERE TRIM(region) IN (SELECT DISTINCT region FROM ref.state);
GO
PRINT '08 facts built';
