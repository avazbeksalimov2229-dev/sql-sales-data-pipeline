/* =============================================================================
   Test: does the pipeline output match the answer key in data/expected?
   The expected files are written by scripts/generate_data.py together with the
   raw files, so this proves every planted problem was found and fixed.

     sqlcmd -S .\SQLEXPRESS -E -C -i tests\verify_against_expected.sql -v ExpectedPath="C:\full\path\to\data\expected"

   Imputed product costs are compared with a 1-cent tolerance per unit
   (rounding of the average cost ratio can differ in the last digit).
   ============================================================================= */
:setvar DatabaseName PortfolioSalesPipeline
USE [$(DatabaseName)];
SET NOCOUNT ON;
GO
IF SCHEMA_ID(N'test') IS NULL EXEC (N'CREATE SCHEMA test');
GO
DROP TABLE IF EXISTS test.fact_sales, test.fact_returns, test.dim_customer, test.dim_product, test.fact_sales_target;

CREATE TABLE test.dim_customer (customer_id VARCHAR(10), customer_name NVARCHAR(100), segment VARCHAR(20), city NVARCHAR(50),
                                state_code CHAR(2), state_name VARCHAR(30), region VARCHAR(10), signup_date DATE);
CREATE TABLE test.dim_product (product_id VARCHAR(20), product_name NVARCHAR(100), category VARCHAR(30), subcategory VARCHAR(30),
                               unit_cost DECIMAL(10,2), list_price DECIMAL(10,2), is_cost_imputed BIT);
CREATE TABLE test.fact_sales (order_id VARCHAR(20), order_line INT, order_date DATE, ship_date DATE NULL, customer_id VARCHAR(10),
                              product_id VARCHAR(20), sales_rep_id VARCHAR(10) NULL, channel VARCHAR(20), quantity INT,
                              unit_price DECIMAL(10,2), discount_pct DECIMAL(5,4), gross_sales DECIMAL(12,2),
                              discount_amount DECIMAL(12,2), net_sales DECIMAL(12,2), cost DECIMAL(12,2), gross_profit DECIMAL(12,2));
CREATE TABLE test.fact_returns (return_id VARCHAR(20), order_id VARCHAR(20), order_line INT, return_date DATE,
                                quantity_returned INT, return_reason VARCHAR(30), refund_amount DECIMAL(12,2));
CREATE TABLE test.fact_sales_target (month_start DATE, region VARCHAR(10), target_net_sales DECIMAL(14,2));

BULK INSERT test.dim_customer      FROM '$(ExpectedPath)\dim_customer.csv'      WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a');
BULK INSERT test.dim_product       FROM '$(ExpectedPath)\dim_product.csv'       WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a');
BULK INSERT test.fact_sales        FROM '$(ExpectedPath)\fact_sales.csv'        WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a');
BULK INSERT test.fact_returns      FROM '$(ExpectedPath)\fact_returns.csv'      WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a');
BULK INSERT test.fact_sales_target FROM '$(ExpectedPath)\fact_sales_target.csv' WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a');

DECLARE @results TABLE (test_name VARCHAR(80), expected_value DECIMAL(18,2), actual_value DECIMAL(18,2), result AS (CASE WHEN expected_value = actual_value THEN 'PASS' ELSE 'FAIL' END));

INSERT INTO @results (test_name, expected_value, actual_value)
SELECT 'dim_customer: row count', (SELECT COUNT(*) FROM test.dim_customer), (SELECT COUNT(*) FROM dw.dim_customer)
UNION ALL
SELECT 'dim_customer: rows that differ', 0,
       (SELECT COUNT(*) FROM (SELECT customer_id, customer_name, segment, city, state_code, state_name, region, signup_date FROM dw.dim_customer
                              EXCEPT SELECT * FROM test.dim_customer) AS d)
UNION ALL
SELECT 'dim_product: row count', (SELECT COUNT(*) FROM test.dim_product), (SELECT COUNT(*) FROM dw.dim_product)
UNION ALL
SELECT 'dim_product: rows that differ (excluding cost)', 0,
       (SELECT COUNT(*) FROM (SELECT product_id, product_name, category, subcategory, list_price, is_cost_imputed FROM dw.dim_product
                              EXCEPT SELECT product_id, product_name, category, subcategory, list_price, is_cost_imputed FROM test.dim_product) AS d)
UNION ALL
SELECT 'dim_product: unit cost off by more than 1 cent', 0,
       (SELECT COUNT(*) FROM dw.dim_product AS a JOIN test.dim_product AS e ON e.product_id = a.product_id
        WHERE ABS(a.unit_cost - e.unit_cost) > 0.01)
UNION ALL
SELECT 'fact_sales: row count', (SELECT COUNT(*) FROM test.fact_sales), (SELECT COUNT(*) FROM dw.fact_sales)
UNION ALL
SELECT 'fact_sales: rows that differ (excluding cost)', 0,
       (SELECT COUNT(*) FROM (SELECT order_id, order_line, order_date, ship_date, customer_id, product_id, sales_rep_id, channel,
                                     quantity, unit_price, discount_pct, gross_sales, discount_amount, net_sales FROM dw.fact_sales
                              EXCEPT
                              SELECT order_id, order_line, order_date, ship_date, customer_id, product_id, sales_rep_id, channel,
                                     quantity, unit_price, discount_pct, gross_sales, discount_amount, net_sales FROM test.fact_sales) AS d)
UNION ALL
SELECT 'fact_sales: cost off by more than 1 cent per unit', 0,
       (SELECT COUNT(*) FROM dw.fact_sales AS a JOIN test.fact_sales AS e ON e.order_id = a.order_id AND e.order_line = a.order_line
        WHERE ABS(a.cost - e.cost) > 0.01 * a.quantity)
UNION ALL
SELECT 'fact_sales: total net sales', (SELECT SUM(net_sales) FROM test.fact_sales), (SELECT SUM(net_sales) FROM dw.fact_sales)
UNION ALL
SELECT 'fact_returns: row count', (SELECT COUNT(*) FROM test.fact_returns), (SELECT COUNT(*) FROM dw.fact_returns)
UNION ALL
SELECT 'fact_returns: rows that differ', 0,
       (SELECT COUNT(*) FROM (SELECT return_id, order_id, order_line, return_date, quantity_returned, return_reason, refund_amount FROM dw.fact_returns
                              EXCEPT SELECT * FROM test.fact_returns) AS d)
UNION ALL
SELECT 'fact_sales_target: rows that differ', 0,
       (SELECT COUNT(*) FROM (SELECT * FROM dw.fact_sales_target EXCEPT SELECT * FROM test.fact_sales_target) AS d)
UNION ALL
SELECT 'dq: duplicate copies that disagree', 0,
       (SELECT rows_affected FROM dq.issue_log WHERE issue = 'Duplicate copies that disagree with each other');

SELECT test_name, expected_value, actual_value, result FROM @results;
SELECT CASE WHEN EXISTS (SELECT 1 FROM @results WHERE result = 'FAIL') THEN 'SOME TESTS FAILED' ELSE 'ALL TESTS PASSED' END AS summary;

DROP TABLE test.fact_sales, test.fact_returns, test.dim_customer, test.dim_product, test.fact_sales_target;
GO
