-- ============================================================
-- SUPPLY CHAIN ANALYTICS - PHASE 3 & 4 (MySQL / MySQL Workbench)
-- 02_etl_load_mysql.sql
-- Loads the raw CSV into staging, then transforms/loads it
-- into the star-schema dimension and fact tables.
-- ============================================================

USE SupplyChainAnalytics;

-- ------------------------------------------------------------
-- 0. ONE-TIME SETUP (run once per MySQL Workbench session if needed)
-- LOAD DATA LOCAL INFILE requires local_infile enabled on both the
-- server and the client. In Workbench: Edit > Preferences >
-- SQL Editor > check "Enable Load Data Local Infile", then
-- reconnect. On the server side, run once (needs privileges):
--   SET GLOBAL local_infile = 1;
-- ------------------------------------------------------------

-- TRUNCATE TABLE Staging_Orders;

-- ------------------------------------------------------------
-- 1. LOAD STAGING FROM CSV
-- Update the file path below to wherever DataCoSupplyChainDataset.csv
-- sits on YOUR machine. LOCAL means the file is read from the
-- client (the computer running Workbench), which is the common
-- case for a laptop/dev setup. The file is Latin-1 encoded.
-- ------------------------------------------------------------
-- LOAD DATA LOCAL INFILE 'C:/Users/0204a/Downloads/SUPPLY CHAIN DASHBOARD/DataCoSupplyChainDataset/DataCoSupplyChainDataset.csv'
-- INTO TABLE Staging_Orders
-- CHARACTER SET latin1
-- FIELDS TERMINATED BY ','
-- LINES TERMINATED BY '\n'
-- IGNORE 1 LINES;

/* If LOAD DATA LOCAL INFILE is blocked by your MySQL setup (common
   security default), the easiest fix in Workbench is:
   Table Data Import Wizard (right-click the Staging_Orders table
   in the schema browser -> Table Data Import Wizard -> pick the CSV).
   It handles the same load without needing local_infile enabled. */


-- ------------------------------------------------------------
-- 2. DIM DATE
-- Recursive date spine covering the full order + shipping range.
-- IMPORTANT: the dataset actually runs 2015-01-01 through
-- 2018-02-06 (order dates run slightly ahead of shipping dates,
-- up to 2018-01-31) -- padded here to end of Feb 2018. Don't
-- trust a naive MIN()/MAX() on the raw text date column to check
-- this -- it sorts alphabetically, not chronologically, and will
-- understate the range.
-- MySQL's default recursion depth (1000) is too low for the
-- ~1,154 days this spine covers, so raise it for this session first.
-- ------------------------------------------------------------
-- SET SESSION cte_max_recursion_depth = 2000;

TRUNCATE TABLE DimDate;

INSERT INTO DimDate (DateKey, FullDate, Year_Num, Quarter_Num, QuarterName,
                      Month_Num, MonthName_Val, YearMonth, Day_Num,
                      Weekday_Num, WeekdayName, IsWeekend)
WITH RECURSIVE DateSpine AS (
    SELECT DATE('2015-01-01') AS FullDate
    UNION ALL
    SELECT FullDate + INTERVAL 1 DAY
    FROM DateSpine
    WHERE FullDate < '2018-02-28'
)
SELECT
    CAST(DATE_FORMAT(FullDate, '%Y%m%d') AS UNSIGNED)   AS DateKey,
    FullDate,
    YEAR(FullDate)                                       AS Year_Num,
    QUARTER(FullDate)                                     AS Quarter_Num,
    CONCAT('Q', QUARTER(FullDate))                        AS QuarterName,
    MONTH(FullDate)                                        AS Month_Num,
    MONTHNAME(FullDate)                                     AS MonthName_Val,
    DATE_FORMAT(FullDate, '%Y-%m')                           AS YearMonth,
    DAY(FullDate)                                             AS Day_Num,
    WEEKDAY(FullDate)                                          AS Weekday_Num,  -- 0=Monday..6=Sunday
    DAYNAME(FullDate)                                           AS WeekdayName,
    CASE WHEN WEEKDAY(FullDate) IN (5,6) THEN 1 ELSE 0 END        AS IsWeekend
FROM DateSpine;


-- ------------------------------------------------------------
-- 3. DIM CUSTOMER
-- One row per distinct customer (dedup with ROW_NUMBER in case
-- of repeated rows across order lines).
-- ------------------------------------------------------------
-- TRUNCATE TABLE DimCustomer;

INSERT INTO DimCustomer (CustomerId, CustomerFname, CustomerLname, CustomerSegment,
                          CustomerCity, CustomerState, CustomerCountry, CustomerZipcode)
SELECT CustomerId, CustomerFname, CustomerLname, CustomerSegment,
       CustomerCity, CustomerState, CustomerCountry, CustomerZipcode
FROM (
    SELECT s.*,
           ROW_NUMBER() OVER (PARTITION BY CustomerId ORDER BY OrderItemId) AS rn
    FROM Staging_Orders s
) dedup
WHERE rn = 1;


-- ------------------------------------------------------------
-- 4. DIM PRODUCT
-- ------------------------------------------------------------
-- TRUNCATE TABLE DimProduct;

INSERT INTO DimProduct (ProductCardId, ProductName, ProductPrice, ProductStatus,
                         CategoryId, CategoryName, DepartmentId, DepartmentName)
SELECT ProductCardId, ProductName, ProductPrice, ProductStatus,
       CategoryId, CategoryName, DepartmentId, DepartmentName
FROM (
    SELECT s.*,
           ROW_NUMBER() OVER (PARTITION BY ProductCardId ORDER BY OrderItemId) AS rn
    FROM Staging_Orders s
) dedup
WHERE rn = 1;


-- ------------------------------------------------------------
-- 5. DIM REGION
-- Surrogate key per distinct Market + Region + Country + State + City.
-- ------------------------------------------------------------
-- TRUNCATE TABLE DimRegion;

INSERT INTO DimRegion (Market, OrderRegion, OrderCountry, OrderState, OrderCity)
SELECT DISTINCT Market, OrderRegion, OrderCountry, OrderState, OrderCity
FROM Staging_Orders;


-- ------------------------------------------------------------
-- 6. DIM SHIPPING
-- ------------------------------------------------------------
-- TRUNCATE TABLE DimShipping;

INSERT INTO DimShipping (ShippingMode)
SELECT DISTINCT ShippingMode
FROM Staging_Orders;

SELECT COUNT(DISTINCT Market) AS Markets,
       COUNT(DISTINCT OrderRegion) AS Regions,
       COUNT(DISTINCT OrderCountry) AS Countries,
       COUNT(DISTINCT OrderState) AS States,
       COUNT(DISTINCT OrderCity) AS Cities
FROM Staging_Orders;

-- ------------------------------------------------------------
-- 7. FACT ORDERS
-- Join staging to each dimension to resolve keys.
-- FK checks are disabled briefly around the truncate because
-- FactOrders references the dimension tables we just rebuilt.
-- ------------------------------------------------------------
-- SET FOREIGN_KEY_CHECKS = 0;
-- TRUNCATE TABLE FactOrders;
-- SET FOREIGN_KEY_CHECKS = 1;

INSERT INTO FactOrders (
    OrderItemId, OrderId, OrderDateKey, ShipDateKey, CustomerId, ProductCardId,
    RegionKey, ShippingModeKey, OrderStatus, PaymentType,
    DaysForShippingReal, DaysForShipmentScheduled, IsLateDelivery, DeliveryStatus,
    Sales, OrderItemTotal, OrderProfitPerOrder, OrderItemProfitRatio,
    OrderItemDiscount, OrderItemDiscountRate, OrderItemQuantity,
    OrderItemProductPrice, SalesPerCustomer
)
SELECT
    s.OrderItemId,
    s.OrderId,
    CAST(DATE_FORMAT(STR_TO_DATE(s.OrderDate, '%c/%e/%Y %H:%i'), '%Y%m%d') AS UNSIGNED)    AS OrderDateKey,
    CAST(DATE_FORMAT(STR_TO_DATE(s.ShippingDate, '%c/%e/%Y %H:%i'), '%Y%m%d') AS UNSIGNED) AS ShipDateKey,
    s.CustomerId,
    s.ProductCardId,
    r.RegionKey,
    sh.ShippingModeKey,
    s.OrderStatus,
    s.`Type`                                                AS PaymentType,
    s.DaysForShippingReal,
    s.DaysForShipmentScheduled,
    s.LateDeliveryRisk                                      AS IsLateDelivery,
    s.DeliveryStatus,
    s.Sales,
    s.OrderItemTotal,
    s.OrderProfitPerOrder,
    s.OrderItemProfitRatio,
    s.OrderItemDiscount,
    s.OrderItemDiscountRate,
    s.OrderItemQuantity,
    s.OrderItemProductPrice,
    s.SalesPerCustomer
FROM Staging_Orders s
JOIN DimRegion   r  ON r.Market = s.Market
                   AND r.OrderRegion = s.OrderRegion
                   AND r.OrderCountry = s.OrderCountry
                   AND r.OrderState = s.OrderState
                   AND r.OrderCity = s.OrderCity
JOIN DimShipping sh ON sh.ShippingMode = s.ShippingMode;

-- ------------------------------------------------------------
-- 8. SANITY CHECKS
-- ------------------------------------------------------------
SELECT COUNT(*) AS StagingRows FROM Staging_Orders;
SELECT COUNT(*) AS FactRows    FROM FactOrders;
SELECT COUNT(*) AS CustomerCt  FROM DimCustomer;
SELECT COUNT(*) AS ProductCt   FROM DimProduct;
SELECT COUNT(*) AS RegionCt    FROM DimRegion;
SELECT COUNT(*) AS ShippingCt  FROM DimShipping;

-- SET GLOBAL local_infile = 1;

-- SHOW VARIABLES LIKE 'local_infile';

SELECT COUNT(*) FROM DimDate;
SELECT COUNT(*) FROM DimCustomer;
SELECT COUNT(*) FROM DimProduct;
SELECT COUNT(*) FROM DimRegion;
SELECT COUNT(*) FROM DimShipping;