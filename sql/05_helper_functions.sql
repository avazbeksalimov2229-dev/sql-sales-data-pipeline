/* 05 - Helper functions for parsing messy text.
   They return NULL instead of failing, so bad values can be found and logged.  */
USE [$(DatabaseName)];
GO

/* Dates arrive in four formats:
     2025-03-14            ISO
     2025-03-14 10:22:05   ISO with time
     03/14/2025            US (MM/DD/YYYY)
     Mar 14, 2025          month name - parsed by hand so it does not depend on the server language */
CREATE OR ALTER FUNCTION etl.fn_parse_date (@txt NVARCHAR(50))
RETURNS DATE
AS
BEGIN
    DECLARE @v NVARCHAR(50) = LTRIM(RTRIM(@txt));
    RETURN CASE
        WHEN @v LIKE '[12][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]%'
            THEN TRY_CONVERT(DATE, LEFT(@v, 10), 23)
        WHEN @v LIKE '[01][0-9]/[0-3][0-9]/[12][0-9][0-9][0-9]'
            THEN TRY_CONVERT(DATE, @v, 101)
        WHEN @v LIKE '[A-Z][a-z][a-z] [0-3][0-9], [12][0-9][0-9][0-9]'
             AND CHARINDEX(LEFT(@v, 3), 'JanFebMarAprMayJunJulAugSepOctNovDec') > 0
            THEN DATEFROMPARTS(CAST(RIGHT(@v, 4) AS INT),
                               (CHARINDEX(LEFT(@v, 3), 'JanFebMarAprMayJunJulAugSepOctNovDec') + 2) / 3,
                               CAST(SUBSTRING(@v, 5, 2) AS INT))
    END;
END;
GO

/* Money: "129.99", "$129.99", "$1,299.00", " 129.99 " -> 129.99 */
CREATE OR ALTER FUNCTION etl.fn_parse_money (@txt NVARCHAR(50))
RETURNS DECIMAL(12, 2)
AS
BEGIN
    RETURN TRY_CONVERT(DECIMAL(12, 2),
                       NULLIF(REPLACE(REPLACE(REPLACE(@txt, '$', ''), ',', ''), ' ', ''), ''));
END;
GO

/* Discount: "0.15", "15%", "0%", "" -> 0.1500 (empty means no discount) */
CREATE OR ALTER FUNCTION etl.fn_parse_discount (@txt NVARCHAR(20))
RETURNS DECIMAL(5, 4)
AS
BEGIN
    DECLARE @v NVARCHAR(20) = NULLIF(LTRIM(RTRIM(@txt)), '');
    RETURN CASE
        WHEN @v IS NULL       THEN 0
        WHEN @v LIKE '%[%]'   THEN TRY_CONVERT(DECIMAL(7, 4), REPLACE(@v, '%', '')) / 100
        ELSE                       TRY_CONVERT(DECIMAL(7, 4), @v)
    END;
END;
GO

/* Quantity: "12", " 12 ", "12 units" -> 12 */
CREATE OR ALTER FUNCTION etl.fn_parse_int (@txt NVARCHAR(50))
RETURNS INT
AS
BEGIN
    RETURN TRY_CONVERT(INT, LTRIM(RTRIM(REPLACE(@txt, 'units', ''))));
END;
GO
PRINT '05 helper functions ready';
