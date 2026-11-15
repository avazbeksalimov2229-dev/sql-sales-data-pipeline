/* 04 - Reference and mapping tables.
   Every inconsistent spelling found during profiling is mapped here once,
   so the cleaning logic stays simple and new variants are a one-line fix.
   Aliases are stored in UPPER CASE and matched on UPPER(TRIM(value)).          */
USE [$(DatabaseName)];
SET NOCOUNT ON;

DROP TABLE IF EXISTS ref.state_alias, ref.state, ref.channel_alias, ref.category_alias, ref.return_reason_alias;

CREATE TABLE ref.state (
    state_code  CHAR(2)     NOT NULL PRIMARY KEY,
    state_name  VARCHAR(30) NOT NULL,
    region      VARCHAR(10) NOT NULL
);
INSERT INTO ref.state (state_code, state_name, region) VALUES
 ('CA','California','West'), ('WA','Washington','West'), ('OR','Oregon','West'), ('AZ','Arizona','West'),
 ('CO','Colorado','West'), ('NV','Nevada','West'), ('UT','Utah','West'),
 ('TX','Texas','Central'), ('IL','Illinois','Central'), ('MN','Minnesota','Central'), ('MO','Missouri','Central'),
 ('OH','Ohio','Central'), ('MI','Michigan','Central'), ('WI','Wisconsin','Central'),
 ('NY','New York','East'), ('PA','Pennsylvania','East'), ('NJ','New Jersey','East'), ('MA','Massachusetts','East'),
 ('VA','Virginia','East'), ('NC','North Carolina','East'), ('MD','Maryland','East'),
 ('FL','Florida','South'), ('GA','Georgia','South'), ('TN','Tennessee','South'), ('AL','Alabama','South'),
 ('LA','Louisiana','South'), ('SC','South Carolina','South'), ('KY','Kentucky','South');

CREATE TABLE ref.state_alias (
    alias       VARCHAR(30) NOT NULL PRIMARY KEY,
    state_code  CHAR(2)     NOT NULL REFERENCES ref.state (state_code)
);
-- full names first, then the abbreviations seen in the CRM export
INSERT INTO ref.state_alias (alias, state_code)
SELECT UPPER(state_name), state_code FROM ref.state;
INSERT INTO ref.state_alias (alias, state_code) VALUES
 ('CALIF.','CA'), ('WASH.','WA'), ('ORE.','OR'), ('ARIZ.','AZ'), ('COLO.','CO'), ('NEV.','NV'),
 ('TEX.','TX'), ('ILL.','IL'), ('MINN.','MN'), ('MICH.','MI'), ('WIS.','WI'),
 ('N.Y.','NY'), ('PENN.','PA'), ('N.J.','NJ'), ('MASS.','MA'), ('VA.','VA'), ('N.C.','NC'), ('MD.','MD'),
 ('FLA.','FL'), ('GA.','GA'), ('TENN.','TN'), ('ALA.','AL'), ('S.C.','SC'), ('KY.','KY');

CREATE TABLE ref.channel_alias (
    alias    VARCHAR(30) NOT NULL PRIMARY KEY,
    channel  VARCHAR(20) NOT NULL
);
INSERT INTO ref.channel_alias (alias, channel) VALUES
 ('ONLINE','Online'), ('WEB','Online'), ('E-COMMERCE','Online'),
 ('RETAIL STORE','Retail Store'), ('RETAIL','Retail Store'), ('STORE','Retail Store'),
 ('WHOLESALE','Wholesale'), ('B2B','Wholesale');

CREATE TABLE ref.category_alias (
    alias     VARCHAR(30) NOT NULL PRIMARY KEY,
    category  VARCHAR(30) NOT NULL
);
INSERT INTO ref.category_alias (alias, category) VALUES
 ('FURNITURE','Furniture'),
 ('OFFICE SUPPLIES','Office Supplies'), ('OFFICE-SUPPLIES','Office Supplies'),
 ('TECHNOLOGY','Technology'), ('TECH','Technology'),
 ('HOME & DECOR','Home & Decor'), ('HOME AND DECOR','Home & Decor'), ('HOME&DECOR','Home & Decor');

CREATE TABLE ref.return_reason_alias (
    alias   VARCHAR(50) NOT NULL PRIMARY KEY,
    reason  VARCHAR(30) NOT NULL
);
INSERT INTO ref.return_reason_alias (alias, reason) VALUES
 ('DAMAGED IN TRANSIT','Damaged in transit'), ('DAMAGED','Damaged in transit'), ('DAMAGED - SHIPPING','Damaged in transit'),
 ('DEFECTIVE','Defective'), ('DEFECTIVE ITEM','Defective'), ('FAULTY','Defective'),
 ('WRONG ITEM','Wrong item'), ('WRONG ITEM SENT','Wrong item'),
 ('NOT AS DESCRIBED','Not as described'),
 ('CHANGED MIND','Changed mind'), ('CUSTOMER CHANGED MIND','Changed mind'), ('NO LONGER NEEDED','Changed mind');
GO
PRINT '04 reference data ready';
