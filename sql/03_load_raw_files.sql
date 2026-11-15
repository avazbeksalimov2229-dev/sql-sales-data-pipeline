/* 03 - Load the raw CSV exports into staging with BULK INSERT.
   FORMAT = 'CSV' handles quoted fields such as "Mar 14, 2025".                  */
USE [$(DatabaseName)];
SET NOCOUNT ON;

BULK INSERT stg.orders_raw    FROM '$(DataPath)\orders_raw.csv'
    WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);
BULK INSERT stg.customers_raw FROM '$(DataPath)\customers_raw.csv'
    WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);
BULK INSERT stg.products_raw  FROM '$(DataPath)\products_raw.csv'
    WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);
BULK INSERT stg.returns_raw   FROM '$(DataPath)\returns_raw.csv'
    WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);
BULK INSERT stg.sales_reps    FROM '$(DataPath)\sales_reps.csv'
    WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);
BULK INSERT stg.sales_targets FROM '$(DataPath)\sales_targets.csv'
    WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);

SELECT 'stg.orders_raw' AS staging_table, COUNT(*) AS rows_loaded FROM stg.orders_raw
UNION ALL SELECT 'stg.customers_raw', COUNT(*) FROM stg.customers_raw
UNION ALL SELECT 'stg.products_raw',  COUNT(*) FROM stg.products_raw
UNION ALL SELECT 'stg.returns_raw',   COUNT(*) FROM stg.returns_raw
UNION ALL SELECT 'stg.sales_reps',    COUNT(*) FROM stg.sales_reps
UNION ALL SELECT 'stg.sales_targets', COUNT(*) FROM stg.sales_targets;
GO
PRINT '03 raw files loaded';
