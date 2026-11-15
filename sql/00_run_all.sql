/* =============================================================================
   Harbor & Pine Supply Co. - sales data pipeline (SQL Server 2017+)
   Runs every step from raw CSV files to a clean star schema for Power BI.

   Run from the sql folder with sqlcmd (or in SSMS with Query > SQLCMD Mode):

     cd sql
     sqlcmd -S .\SQLEXPRESS -E -C -b -i 00_run_all.sql -v DataPath="C:\full\path\to\data\raw"

   DataPath is the folder that holds the raw CSV files, without a trailing
   backslash. The SQL Server service account must be able to read that folder:
   BULK INSERT reads files as the server, not as you.
   ============================================================================= */
:setvar DatabaseName PortfolioSalesPipeline
:on error exit

:r .\01_create_database.sql
:r .\02_create_staging_and_dq.sql
:r .\03_load_raw_files.sql
:r .\04_reference_data.sql
:r .\05_helper_functions.sql
:r .\06_data_profiling.sql
:r .\07_build_dimensions.sql
:r .\08_build_facts.sql
:r .\09_data_quality_report.sql
:r .\10_powerbi_views.sql

PRINT 'Pipeline finished.';
