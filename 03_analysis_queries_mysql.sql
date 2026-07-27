-- ============================================================
-- SUPPLY CHAIN ANALYTICS - PHASE 4 (MySQL / MySQL Workbench)
-- 03_analysis_queries_mysql.sql
-- Practice queries against the star schema: GROUP BY, JOIN, CTE,
-- and window functions (MySQL 8.0+). Each answers a real business
-- question and maps directly to a dashboard visual in Phase 8.
-- ============================================================

USE SupplyChainAnalytics;

-- ------------------------------------------------------------
-- 1. TOTAL SALES BY MONTH  (GROUP BY, JOIN)
-- -> feeds the Sales Trend visual on the Executive Overview page
-- ------------------------------------------------------------
SELECT
    d.YearMonth,
    SUM(f.Sales)               AS TotalSales,
    SUM(f.OrderProfitPerOrder) AS TotalProfit,
    COUNT(DISTINCT f.OrderId)  AS OrderCount
FROM FactOrders f
JOIN DimDate d ON d.DateKey = f.OrderDateKey
GROUP BY d.YearMonth
ORDER BY d.YearMonth;


-- ------------------------------------------------------------
-- 2. LATE DELIVERIES  (GROUP BY)
-- -> feeds Late Delivery % KPI card and Delivery Status Breakdown
-- ------------------------------------------------------------
SELECT
    DeliveryStatus,
    COUNT(*)                                       AS OrderLineCount,
    SUM(IsLateDelivery)                             AS LateCount,
    SUM(IsLateDelivery) / NULLIF(COUNT(*), 0) * 100 AS LateDeliveryPct
FROM FactOrders
GROUP BY DeliveryStatus
ORDER BY OrderLineCount DESC;


-- ------------------------------------------------------------
-- 3. AVERAGE SHIPPING DAYS  (GROUP BY, JOIN)
-- -> feeds Average Delivery Days KPI and Shipping Mode Comparison
-- ------------------------------------------------------------
SELECT
    sh.ShippingMode,
    AVG(f.DaysForShippingReal)                              AS AvgActualShippingDays,
    AVG(f.DaysForShipmentScheduled)                         AS AvgScheduledShippingDays,
    AVG(f.DaysForShippingReal - f.DaysForShipmentScheduled)  AS AvgDaysOverSchedule
FROM FactOrders f
JOIN DimShipping sh ON sh.ShippingModeKey = f.ShippingModeKey
GROUP BY sh.ShippingMode
ORDER BY AvgActualShippingDays DESC;


-- ------------------------------------------------------------
-- 4. TOP CUSTOMERS  (JOIN, WINDOW FUNCTION - RANK)
-- -> feeds Top Customers visual on Customer & Product Analysis page
-- ------------------------------------------------------------
SELECT
    c.CustomerId,
    CONCAT(c.CustomerFname, ' ', c.CustomerLname) AS CustomerName,
    c.CustomerSegment,
    SUM(f.Sales)                                  AS TotalSales,
    SUM(f.OrderProfitPerOrder)                    AS TotalProfit,
    RANK() OVER (ORDER BY SUM(f.Sales) DESC)      AS SalesRank
FROM FactOrders f
JOIN DimCustomer c ON c.CustomerId = f.CustomerId
GROUP BY c.CustomerId, c.CustomerFname, c.CustomerLname, c.CustomerSegment
ORDER BY TotalSales DESC
LIMIT 20;


-- ------------------------------------------------------------
-- 5. TOP PRODUCTS  (JOIN, WINDOW FUNCTION - ROW_NUMBER)
-- -> feeds Top Products visual
-- ------------------------------------------------------------
SELECT *
FROM (
    SELECT
        p.ProductCardId,
        p.ProductName,
        p.CategoryName,
        SUM(f.Sales)                                   AS TotalSales,
        SUM(f.OrderItemQuantity)                       AS TotalUnitsSold,
        ROW_NUMBER() OVER (ORDER BY SUM(f.Sales) DESC) AS SalesRowNum
    FROM FactOrders f
    JOIN DimProduct p ON p.ProductCardId = f.ProductCardId
    GROUP BY p.ProductCardId, p.ProductName, p.CategoryName
) ranked
WHERE SalesRowNum <= 20
ORDER BY SalesRowNum;


-- ------------------------------------------------------------
-- 6. PROFIT BY REGION  (GROUP BY, JOIN, CTE)
-- -> feeds Regional Map visual and Region Performance page
-- ------------------------------------------------------------
WITH RegionProfit AS (
    SELECT
        r.Market,
        r.OrderRegion,
        SUM(f.Sales)               AS TotalSales,
        SUM(f.OrderProfitPerOrder) AS TotalProfit,
        COUNT(DISTINCT f.OrderId)  AS OrderCount
    FROM FactOrders f
    JOIN DimRegion r ON r.RegionKey = f.RegionKey
    GROUP BY r.Market, r.OrderRegion
)
SELECT
    Market,
    OrderRegion,
    TotalSales,
    TotalProfit,
    OrderCount,
    TotalProfit / NULLIF(TotalSales, 0) * 100 AS ProfitMarginPct
FROM RegionProfit
ORDER BY TotalProfit DESC;


-- ------------------------------------------------------------
-- 7. SALES BY CATEGORY  (GROUP BY, JOIN)
-- -> feeds Category Breakdown visual
-- ------------------------------------------------------------
SELECT
    p.CategoryName,
    p.DepartmentName,
    SUM(f.Sales)               AS TotalSales,
    SUM(f.OrderProfitPerOrder) AS TotalProfit,
    SUM(f.OrderItemQuantity)   AS TotalUnitsSold
FROM FactOrders f
JOIN DimProduct p ON p.ProductCardId = f.ProductCardId
GROUP BY p.CategoryName, p.DepartmentName
ORDER BY TotalSales DESC;


-- ------------------------------------------------------------
-- 8. RUNNING SALES TOTAL  (WINDOW FUNCTION - SUM OVER, CTE)
-- -> feeds a running-total line overlay on the Sales Trend visual
-- ------------------------------------------------------------
WITH MonthlySales AS (
    SELECT
        d.YearMonth,
        SUM(f.Sales) AS MonthSales
    FROM FactOrders f
    JOIN DimDate d ON d.DateKey = f.OrderDateKey
    GROUP BY d.YearMonth
)
SELECT
    YearMonth,
    MonthSales,
    SUM(MonthSales) OVER (ORDER BY YearMonth
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningTotalSales
FROM MonthlySales
ORDER BY YearMonth;


-- ------------------------------------------------------------
-- 9. YEAR-OVER-YEAR AND MONTH-OVER-MONTH GROWTH
-- (WINDOW FUNCTION - LAG, CTE)
-- -> feeds YoY / MoM growth KPI cards
-- ------------------------------------------------------------
WITH MonthlySales AS (
    SELECT
        d.Year_Num,
        d.Month_Num,
        d.YearMonth,
        SUM(f.Sales) AS MonthSales
    FROM FactOrders f
    JOIN DimDate d ON d.DateKey = f.OrderDateKey
    GROUP BY d.Year_Num, d.Month_Num, d.YearMonth
)
SELECT
    YearMonth,
    MonthSales,
    LAG(MonthSales, 1)  OVER (ORDER BY YearMonth) AS PriorMonthSales,
    LAG(MonthSales, 12) OVER (ORDER BY YearMonth) AS SameMonthPriorYearSales,
    (MonthSales - LAG(MonthSales, 1) OVER (ORDER BY YearMonth))
        / NULLIF(LAG(MonthSales, 1) OVER (ORDER BY YearMonth), 0) * 100  AS MoMGrowthPct,
    (MonthSales - LAG(MonthSales, 12) OVER (ORDER BY YearMonth))
        / NULLIF(LAG(MonthSales, 12) OVER (ORDER BY YearMonth), 0) * 100 AS YoYGrowthPct
FROM MonthlySales
ORDER BY YearMonth;


-- ------------------------------------------------------------
-- 10. FAST-MOVING VS. SLOW-MOVING PRODUCTS
-- (CTE, WINDOW FUNCTION - NTILE)
-- -> feeds the Inventory/Operations page (Phase 8, Page 4)
-- ------------------------------------------------------------
WITH ProductVelocity AS (
    SELECT
        p.ProductCardId,
        p.ProductName,
        SUM(f.OrderItemQuantity) AS TotalUnitsSold
    FROM FactOrders f
    JOIN DimProduct p ON p.ProductCardId = f.ProductCardId
    GROUP BY p.ProductCardId, p.ProductName
)
SELECT
    ProductCardId,
    ProductName,
    TotalUnitsSold,
    NTILE(4) OVER (ORDER BY TotalUnitsSold DESC) AS VelocityQuartile,
    CASE NTILE(4) OVER (ORDER BY TotalUnitsSold DESC)
        WHEN 1 THEN 'Fast-moving'
        WHEN 4 THEN 'Slow-moving'
        ELSE 'Moderate'
    END AS VelocitySegment
FROM ProductVelocity
ORDER BY TotalUnitsSold DESC;
