/* 11 - Business questions answered on the clean star schema.
   Run after the pipeline. Each query is independent - run them one by one.     */
USE PortfolioSalesPipeline;
SET NOCOUNT ON;

/* Q1. How are sales trending? Monthly net sales, margin, year-over-year growth and YTD */
WITH m AS (
    SELECT DATEFROMPARTS(YEAR(order_date), MONTH(order_date), 1) AS month_start,
           SUM(net_sales)    AS net_sales,
           SUM(gross_profit) AS gross_profit
    FROM dw.fact_sales
    GROUP BY DATEFROMPARTS(YEAR(order_date), MONTH(order_date), 1)
)
SELECT month_start,
       net_sales,
       CAST(gross_profit / NULLIF(net_sales, 0) AS DECIMAL(5, 3))                                   AS gross_margin,
       LAG(net_sales, 12) OVER (ORDER BY month_start)                                              AS net_sales_last_year,
       CAST(net_sales / NULLIF(LAG(net_sales, 12) OVER (ORDER BY month_start), 0) - 1 AS DECIMAL(6, 3)) AS yoy_growth,
       SUM(net_sales) OVER (PARTITION BY YEAR(month_start) ORDER BY month_start ROWS UNBOUNDED PRECEDING) AS ytd_net_sales
FROM m
ORDER BY month_start;

/* Q2. Which regions hit their targets? Attainment by quarter */
WITH actual AS (
    SELECT DATEFROMPARTS(YEAR(s.order_date), MONTH(s.order_date), 1) AS month_start, c.region, SUM(s.net_sales) AS net_sales
    FROM dw.fact_sales AS s
    JOIN dw.dim_customer AS c ON c.customer_id = s.customer_id
    GROUP BY DATEFROMPARTS(YEAR(s.order_date), MONTH(s.order_date), 1), c.region
)
SELECT CONCAT(YEAR(t.month_start), '-Q', DATEPART(QUARTER, t.month_start)) AS [quarter],
       t.region,
       SUM(a.net_sales)                                                    AS actual_net_sales,
       SUM(t.target_net_sales)                                             AS target_net_sales,
       CAST(SUM(a.net_sales) / SUM(t.target_net_sales) AS DECIMAL(5, 3))  AS attainment
FROM dw.fact_sales_target AS t
LEFT JOIN actual AS a ON a.month_start = t.month_start AND a.region = t.region
GROUP BY CONCAT(YEAR(t.month_start), '-Q', DATEPART(QUARTER, t.month_start)), t.region
ORDER BY [quarter], t.region;

/* Q3. Pareto: how many products make 80% of net sales? */
WITH p AS (
    SELECT product_id, SUM(net_sales) AS net_sales FROM dw.fact_sales GROUP BY product_id
), r AS (
    SELECT p.*,
           ROW_NUMBER() OVER (ORDER BY net_sales DESC, product_id) AS sales_rank,
           SUM(net_sales) OVER (ORDER BY net_sales DESC, product_id ROWS UNBOUNDED PRECEDING) / SUM(net_sales) OVER () AS cumulative_share,
           COUNT(*) OVER () AS product_count
    FROM p
)
SELECT MIN(sales_rank)                                            AS products_needed_for_80_pct,
       MAX(product_count)                                         AS products_sold,
       CAST(1.0 * MIN(sales_rank) / MAX(product_count) AS DECIMAL(4, 3)) AS share_of_catalog
FROM r
WHERE cumulative_share >= 0.80;

/* Q4. Top 10 products by gross profit */
SELECT TOP (10)
       p.product_name, p.category,
       SUM(s.net_sales)    AS net_sales,
       SUM(s.gross_profit) AS gross_profit,
       CAST(SUM(s.gross_profit) / SUM(s.net_sales) AS DECIMAL(5, 3)) AS gross_margin
FROM dw.fact_sales AS s
JOIN dw.dim_product AS p ON p.product_id = s.product_id
GROUP BY p.product_name, p.category
ORDER BY gross_profit DESC;

/* Q5. Are discounts destroying margin? Margin by category and discount band */
SELECT p.category,
       b.discount_band,
       COUNT(*)            AS order_lines,
       SUM(s.net_sales)    AS net_sales,
       SUM(s.gross_profit) AS gross_profit,
       CAST(SUM(s.gross_profit) / NULLIF(SUM(s.net_sales), 0) AS DECIMAL(6, 3)) AS gross_margin
FROM dw.fact_sales AS s
JOIN dw.dim_product AS p ON p.product_id = s.product_id
CROSS APPLY (SELECT CASE WHEN s.discount_pct = 0     THEN '1) none'
                         WHEN s.discount_pct <= 0.10 THEN '2) 1-10%'
                         WHEN s.discount_pct <= 0.20 THEN '3) 11-20%'
                         ELSE                             '4) over 20%' END AS discount_band) AS b
GROUP BY p.category, b.discount_band
ORDER BY p.category, b.discount_band;

/* Q6. Do new customers come back? Monthly cohorts and retention */
WITH first_order AS (
    SELECT customer_id, MIN(order_date) AS first_date FROM dw.fact_sales GROUP BY customer_id
), activity AS (
    SELECT DISTINCT s.customer_id,
           DATEFROMPARTS(YEAR(f.first_date), MONTH(f.first_date), 1)                   AS cohort_month,
           DATEDIFF(MONTH, DATEFROMPARTS(YEAR(f.first_date), MONTH(f.first_date), 1), s.order_date) AS months_after
    FROM dw.fact_sales AS s
    JOIN first_order AS f ON f.customer_id = s.customer_id
)
SELECT cohort_month,
       COUNT(DISTINCT customer_id) AS new_customers,
       CAST(100.0 * COUNT(DISTINCT CASE WHEN months_after BETWEEN 1 AND 3  THEN customer_id END) / COUNT(DISTINCT customer_id) AS DECIMAL(5, 1)) AS pct_back_within_3m,
       CAST(100.0 * COUNT(DISTINCT CASE WHEN months_after BETWEEN 1 AND 6  THEN customer_id END) / COUNT(DISTINCT customer_id) AS DECIMAL(5, 1)) AS pct_back_within_6m,
       CAST(100.0 * COUNT(DISTINCT CASE WHEN months_after BETWEEN 1 AND 12 THEN customer_id END) / COUNT(DISTINCT customer_id) AS DECIMAL(5, 1)) AS pct_back_within_12m
FROM activity
GROUP BY cohort_month
ORDER BY cohort_month;

/* Q7. RFM segmentation: who are the best customers, and who is slipping away? */
DECLARE @as_of DATE = (SELECT DATEADD(DAY, 1, MAX(order_date)) FROM dw.fact_sales);
WITH c AS (
    SELECT customer_id,
           DATEDIFF(DAY, MAX(order_date), @as_of) AS recency_days,
           COUNT(DISTINCT order_id)               AS frequency,
           SUM(net_sales)                         AS monetary
    FROM dw.fact_sales
    GROUP BY customer_id
), scored AS (
    SELECT c.*,
           NTILE(5) OVER (ORDER BY recency_days DESC) AS r,
           NTILE(5) OVER (ORDER BY frequency)         AS f,
           NTILE(5) OVER (ORDER BY monetary)          AS m
    FROM c
)
SELECT seg.rfm_segment,
       COUNT(*)                                   AS customers,
       SUM(monetary)                              AS net_sales,
       CAST(AVG(1.0 * recency_days) AS DECIMAL(6, 0)) AS avg_days_since_last_order,
       CAST(AVG(1.0 * frequency) AS DECIMAL(5, 1))    AS avg_orders
FROM scored
CROSS APPLY (SELECT CASE WHEN r >= 4 AND f >= 4 THEN 'Champions'
                         WHEN r >= 3 AND f >= 3 THEN 'Loyal'
                         WHEN r >= 4 AND f <= 2 THEN 'New / promising'
                         WHEN r <= 2 AND f >= 3 THEN 'At risk'
                         WHEN r <= 2 AND f <= 2 THEN 'Lost'
                         ELSE 'Needs attention' END AS rfm_segment) AS seg
GROUP BY seg.rfm_segment
ORDER BY net_sales DESC;

/* Q8. Which products come back most, and why? Return rate by subcategory */
WITH sold AS (
    SELECT p.subcategory, COUNT(*) AS lines_sold
    FROM dw.fact_sales AS s JOIN dw.dim_product AS p ON p.product_id = s.product_id
    GROUP BY p.subcategory
), ret AS (
    SELECT p.subcategory, r.return_reason, COUNT(*) AS lines_returned
    FROM dw.fact_returns AS r
    JOIN dw.fact_sales  AS s ON s.order_id = r.order_id AND s.order_line = r.order_line
    JOIN dw.dim_product AS p ON p.product_id = s.product_id
    GROUP BY p.subcategory, r.return_reason
), ranked AS (
    SELECT ret.*,
           ROW_NUMBER() OVER (PARTITION BY subcategory ORDER BY lines_returned DESC, return_reason) AS rn,
           SUM(lines_returned) OVER (PARTITION BY subcategory) AS total_returned
    FROM ret
)
SELECT s.subcategory,
       s.lines_sold,
       k.total_returned                                                         AS lines_returned,
       CAST(1.0 * k.total_returned / s.lines_sold AS DECIMAL(5, 3))             AS return_rate,
       k.return_reason                                                          AS top_reason,
       CAST(1.0 * k.lines_returned / k.total_returned AS DECIMAL(4, 2))         AS top_reason_share
FROM sold AS s
JOIN ranked AS k ON k.subcategory = s.subcategory AND k.rn = 1
ORDER BY return_rate DESC;

/* Q9. Sales team: ranking and share within each region, per year (wholesale orders) */
SELECT YEAR(s.order_date) AS [year],
       r.region,
       r.sales_rep_name,
       COUNT(DISTINCT s.order_id) AS orders,
       SUM(s.net_sales)           AS net_sales,
       RANK() OVER (PARTITION BY YEAR(s.order_date), r.region ORDER BY SUM(s.net_sales) DESC) AS rank_in_region,
       CAST(SUM(s.net_sales) / SUM(SUM(s.net_sales)) OVER (PARTITION BY YEAR(s.order_date), r.region) AS DECIMAL(4, 3)) AS share_of_region
FROM dw.fact_sales AS s
JOIN dw.dim_sales_rep AS r ON r.sales_rep_id = s.sales_rep_id
GROUP BY YEAR(s.order_date), r.region, r.sales_rep_name
ORDER BY [year], r.region, rank_in_region;

/* Q10. Channel mix and average order value by year */
SELECT YEAR(order_date) AS [year],
       channel,
       COUNT(DISTINCT order_id) AS orders,
       SUM(net_sales)           AS net_sales,
       CAST(SUM(net_sales) / SUM(SUM(net_sales)) OVER (PARTITION BY YEAR(order_date)) AS DECIMAL(4, 3)) AS share_of_year,
       CAST(SUM(net_sales) / COUNT(DISTINCT order_id) AS DECIMAL(10, 2))                              AS avg_order_value
FROM dw.fact_sales
GROUP BY YEAR(order_date), channel
ORDER BY [year], net_sales DESC;
