-- ============================================================
-- SUPPLY CHAIN ANALYTICS - PHASE 3 & 4 (MySQL / MySQL Workbench)
-- 01_schema_mysql.sql
-- Creates the database, a staging table matching the raw CSV,
-- the star-schema dimension tables, and the fact table.
-- Tested against MySQL 8.0 syntax (required for window functions
-- and recursive CTEs used later in 02 and 03).
-- ============================================================

CREATE DATABASE IF NOT EXISTS SupplyChainAnalytics
    CHARACTER SET utf8mb4;

USE SupplyChainAnalytics;

-- ------------------------------------------------------------
-- 1. STAGING TABLE
-- Mirrors the DataCo Smart Supply Chain CSV exactly (53 columns).
-- Load the raw file here first; nothing is transformed yet.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS Staging_Orders;

CREATE TABLE Staging_Orders (
    `Type`                      VARCHAR(20),
    DaysForShippingReal         INT,
    DaysForShipmentScheduled    INT,
    BenefitPerOrder             DECIMAL(12,2),
    SalesPerCustomer            DECIMAL(12,2),
    DeliveryStatus              VARCHAR(30),
    LateDeliveryRisk            TINYINT,
    CategoryId                  INT,
    CategoryName                VARCHAR(100),
    CustomerCity                VARCHAR(100),
    CustomerCountry             VARCHAR(100),
    CustomerEmail               VARCHAR(100),
    CustomerFname               VARCHAR(100),
    CustomerId                  INT,
    CustomerLname               VARCHAR(100),
    CustomerPassword            VARCHAR(100),
    CustomerSegment             VARCHAR(30),
    CustomerState               VARCHAR(50),
    CustomerStreet              VARCHAR(150),
    CustomerZipcode             VARCHAR(20),
    DepartmentId                INT,
    DepartmentName              VARCHAR(100),
    Latitude                    DECIMAL(9,6),
    Longitude                   DECIMAL(9,6),
    Market                      VARCHAR(50),
    OrderCity                   VARCHAR(100),
    OrderCountry                VARCHAR(100),
    OrderCustomerId             INT,
    OrderDate                   VARCHAR(30),   -- raw text; source format is M/D/YYYY H:MM, not ISO -- converted with STR_TO_DATE in 02_etl_load_mysql.sql
    OrderId                     INT,
    OrderItemCardprodId         INT,
    OrderItemDiscount           DECIMAL(12,2),
    OrderItemDiscountRate       DECIMAL(6,4),
    OrderItemId                 INT,
    OrderItemProductPrice       DECIMAL(12,2),
    OrderItemProfitRatio        DECIMAL(8,4),
    OrderItemQuantity           INT,
    Sales                       DECIMAL(12,2),
    OrderItemTotal              DECIMAL(12,2),
    OrderProfitPerOrder         DECIMAL(12,2),
    OrderRegion                 VARCHAR(50),
    OrderState                  VARCHAR(50),
    OrderStatus                 VARCHAR(30),
    OrderZipcode                VARCHAR(20),
    ProductCardId               INT,
    ProductCategoryId           INT,
    ProductDescription          VARCHAR(500),  -- 100% null in source; kept for staging parity
    ProductImage                VARCHAR(300),
    ProductName                 VARCHAR(200),
    ProductPrice                DECIMAL(12,2),
    ProductStatus               TINYINT,
    ShippingDate                VARCHAR(30),   -- raw text; same M/D/YYYY H:MM format as OrderDate
    ShippingMode                VARCHAR(30)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
-- 2. DIMENSION TABLES
-- ------------------------------------------------------------

-- Dim Date: pre-built date spine, populated in 02_etl_load_mysql.sql
DROP TABLE IF EXISTS DimDate;
CREATE TABLE DimDate (
    DateKey       INT          NOT NULL PRIMARY KEY,   -- yyyymmdd
    FullDate      DATE         NOT NULL,
    Year_Num      SMALLINT     NOT NULL,
    Quarter_Num   TINYINT      NOT NULL,
    QuarterName   VARCHAR(2)   NOT NULL,                -- Q1..Q4
    Month_Num     TINYINT      NOT NULL,
    MonthName_Val VARCHAR(10)  NOT NULL,
    YearMonth     CHAR(7)      NOT NULL,                -- yyyy-mm, handy for trend axes
    Day_Num       TINYINT      NOT NULL,
    Weekday_Num   TINYINT      NOT NULL,                -- 0 = Monday .. 6 = Sunday (MySQL WEEKDAY())
    WeekdayName   VARCHAR(10)  NOT NULL,
    IsWeekend     TINYINT(1)   NOT NULL
) ENGINE=InnoDB;

DROP TABLE IF EXISTS DimCustomer;
CREATE TABLE DimCustomer (
    CustomerId      INT          NOT NULL PRIMARY KEY,
    CustomerFname   VARCHAR(100),
    CustomerLname   VARCHAR(100),
    CustomerSegment VARCHAR(30),
    CustomerCity    VARCHAR(100),
    CustomerState   VARCHAR(50),
    CustomerCountry VARCHAR(100),
    CustomerZipcode VARCHAR(20)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS DimProduct;
CREATE TABLE DimProduct (
    ProductCardId  INT          NOT NULL PRIMARY KEY,
    ProductName    VARCHAR(200),
    ProductPrice   DECIMAL(12,2),
    ProductStatus  TINYINT,
    CategoryId     INT,
    CategoryName   VARCHAR(100),
    DepartmentId   INT,
    DepartmentName VARCHAR(100)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS DimRegion;
CREATE TABLE DimRegion (
    RegionKey     INT AUTO_INCREMENT PRIMARY KEY,
    Market        VARCHAR(50),
    OrderRegion   VARCHAR(50),
    OrderCountry  VARCHAR(100),
    OrderState    VARCHAR(50),
    OrderCity     VARCHAR(100)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS DimShipping;
CREATE TABLE DimShipping (
    ShippingModeKey INT AUTO_INCREMENT PRIMARY KEY,
    ShippingMode    VARCHAR(30) NOT NULL UNIQUE
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 3. FACT TABLE
-- Grain: one row per order line item (OrderItemId).
-- ------------------------------------------------------------
DROP TABLE IF EXISTS FactOrders;
CREATE TABLE FactOrders (
    OrderItemId              INT NOT NULL PRIMARY KEY,   -- degenerate dimension: line-item grain
    OrderId                  INT NOT NULL,                -- degenerate dimension: groups line items into an order
    OrderDateKey             INT NOT NULL,
    ShipDateKey              INT NOT NULL,
    CustomerId               INT NOT NULL,
    ProductCardId            INT NOT NULL,
    RegionKey                INT NOT NULL,
    ShippingModeKey          INT NOT NULL,

    OrderStatus              VARCHAR(30),
    PaymentType              VARCHAR(20),

    DaysForShippingReal      INT,
    DaysForShipmentScheduled INT,
    DeliveryDays             INT GENERATED ALWAYS AS (DaysForShippingReal) VIRTUAL,
    IsLateDelivery           TINYINT,                     -- copy of Late_delivery_risk (0/1)
    DeliveryStatus           VARCHAR(30),

    Sales                    DECIMAL(12,2),
    OrderItemTotal           DECIMAL(12,2),
    OrderProfitPerOrder      DECIMAL(12,2),
    OrderItemProfitRatio     DECIMAL(8,4),
    OrderItemDiscount        DECIMAL(12,2),
    OrderItemDiscountRate    DECIMAL(6,4),
    OrderItemQuantity        INT,
    OrderItemProductPrice    DECIMAL(12,2),
    SalesPerCustomer         DECIMAL(12,2),

    CONSTRAINT fk_fact_orderdate FOREIGN KEY (OrderDateKey)    REFERENCES DimDate(DateKey),
    CONSTRAINT fk_fact_shipdate  FOREIGN KEY (ShipDateKey)     REFERENCES DimDate(DateKey),
    CONSTRAINT fk_fact_customer  FOREIGN KEY (CustomerId)      REFERENCES DimCustomer(CustomerId),
    CONSTRAINT fk_fact_product   FOREIGN KEY (ProductCardId)   REFERENCES DimProduct(ProductCardId),
    CONSTRAINT fk_fact_region    FOREIGN KEY (RegionKey)       REFERENCES DimRegion(RegionKey),
    CONSTRAINT fk_fact_shipping  FOREIGN KEY (ShippingModeKey) REFERENCES DimShipping(ShippingModeKey),

    INDEX ix_fact_orderdate (OrderDateKey),
    INDEX ix_fact_customer  (CustomerId),
    INDEX ix_fact_product   (ProductCardId),
    INDEX ix_fact_region    (RegionKey)
) ENGINE=InnoDB;
