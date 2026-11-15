/* 01 - Database and schemas
   stg  raw text, loaded exactly as exported
   ref  lookup and mapping tables
   etl  helper functions used while cleaning
   dw   clean star schema (the output)
   dq   data-quality log and rejected rows                                        */
SET NOCOUNT ON;

IF DB_ID(N'$(DatabaseName)') IS NULL
    EXEC (N'CREATE DATABASE [$(DatabaseName)]');
GO
USE [$(DatabaseName)];
GO
IF SCHEMA_ID(N'stg') IS NULL EXEC (N'CREATE SCHEMA stg');
IF SCHEMA_ID(N'ref') IS NULL EXEC (N'CREATE SCHEMA ref');
IF SCHEMA_ID(N'etl') IS NULL EXEC (N'CREATE SCHEMA etl');
IF SCHEMA_ID(N'dw')  IS NULL EXEC (N'CREATE SCHEMA dw');
IF SCHEMA_ID(N'dq')  IS NULL EXEC (N'CREATE SCHEMA dq');
GO
PRINT '01 database and schemas ready';
