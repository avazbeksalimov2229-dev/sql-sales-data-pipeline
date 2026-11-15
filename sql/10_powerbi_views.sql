/* 10 - Reporting views for Power BI.
   Power BI connects to the rpt schema only, so the tables underneath can change
   without breaking the report.                                                 */
USE [$(DatabaseName)];
GO
IF SCHEMA_ID(N'rpt') IS NULL EXEC (N'CREATE SCHEMA rpt');
GO
CREATE OR ALTER VIEW rpt.dim_date      AS SELECT * FROM dw.dim_date;
GO
CREATE OR ALTER VIEW rpt.dim_customer  AS SELECT * FROM dw.dim_customer;
GO
CREATE OR ALTER VIEW rpt.dim_product   AS SELECT product_id, product_name, category, subcategory, unit_cost, list_price
                                          FROM dw.dim_product;
GO
CREATE OR ALTER VIEW rpt.dim_sales_rep AS SELECT * FROM dw.dim_sales_rep;
GO
CREATE OR ALTER VIEW rpt.fact_sales AS
SELECT order_id, order_line, order_date, ship_date, customer_id, product_id, sales_rep_id, channel,
       quantity, unit_price, discount_pct, gross_sales, discount_amount, net_sales, cost, gross_profit
FROM dw.fact_sales;
GO
CREATE OR ALTER VIEW rpt.fact_returns       AS SELECT * FROM dw.fact_returns;
GO
CREATE OR ALTER VIEW rpt.fact_sales_target  AS SELECT * FROM dw.fact_sales_target;
GO
PRINT '10 Power BI views ready';
