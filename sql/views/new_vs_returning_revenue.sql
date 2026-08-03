-- =============================================================================
-- Marketplace Analytics Platform
-- View: warehouse.vw_new_vs_returning_revenue
-- Script: new_vs_returning_revenue.sql
-- Description: Monthly revenue split between new and returning customers
--              in wide format (one row per month). Designed for Tableau
--              revenue trend and mix dashboards.
--
--              Complements vw_customer_health (which is long format).
--              This view pivots new/returning into separate columns for
--              easier charting and calculated field creation in Tableau.
--
-- Grain: One row per order_month.
--
-- Definitions:
--   New customer      : first ever delivered order in that month
--   Returning customer: has at least one prior delivered order before this month
--
-- Key metrics:
--   Revenue mix       : % of monthly revenue from new vs returning
--   Returning growth  : MoM change in returning customer revenue
--   Acquisition cost  : revenue generated per new customer acquired (proxy)
--
-- Notes:
--   • Based on delivered orders only
--   • customer_unique_id grain (true person, not order-scoped customer_id)
--   • Reference date consistent with vw_rfm and vw_clv (2018-09-01)
-- =============================================================================

CREATE OR REPLACE VIEW warehouse.vw_new_vs_returning_revenue AS

WITH
-- ── Step 1: All delivered orders with customer and month ──────────────────────
delivered_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        DATE_TRUNC('month', o.order_purchase_timestamp)::DATE   AS order_month,
        i.price + i.freight_value                               AS order_value
    FROM warehouse.dim_order o
    JOIN warehouse.dim_customer c
        ON o.customer_key = c.customer_key
    JOIN warehouse.fact_order_items i
        ON o.order_id = i.order_id
    WHERE o.order_status = 'delivered'
),

-- ── Step 2: First order month per customer ────────────────────────────────────
customer_first_order AS (
    SELECT
        customer_unique_id,
        MIN(order_month) AS first_order_month
    FROM delivered_orders
    GROUP BY customer_unique_id
),

-- ── Step 3: Tag each order as new or returning ────────────────────────────────
order_tagged AS (
    SELECT
        d.customer_unique_id,
        d.order_id,
        d.order_month,
        d.order_value,
        CASE
            WHEN d.order_month = f.first_order_month THEN 'new'
            ELSE 'returning'
        END AS customer_type
    FROM delivered_orders d
    JOIN customer_first_order f
        ON d.customer_unique_id = f.customer_unique_id
),

-- ── Step 4: Pivot to wide format — one row per month ─────────────────────────
monthly_pivot AS (
    SELECT
        order_month,
        -- New customer metrics
        COUNT(DISTINCT CASE WHEN customer_type = 'new'
            THEN customer_unique_id END)                        AS new_customers,
        COUNT(DISTINCT CASE WHEN customer_type = 'new'
            THEN order_id END)                                  AS new_orders,
        ROUND(COALESCE(SUM(CASE WHEN customer_type = 'new'
            THEN order_value END), 0)::NUMERIC, 2)             AS new_revenue,
        -- Returning customer metrics
        COUNT(DISTINCT CASE WHEN customer_type = 'returning'
            THEN customer_unique_id END)                        AS returning_customers,
        COUNT(DISTINCT CASE WHEN customer_type = 'returning'
            THEN order_id END)                                  AS returning_orders,
        ROUND(COALESCE(SUM(CASE WHEN customer_type = 'returning'
            THEN order_value END), 0)::NUMERIC, 2)             AS returning_revenue,
        -- Totals
        COUNT(DISTINCT customer_unique_id)                      AS total_customers,
        COUNT(DISTINCT order_id)                                AS total_orders,
        ROUND(SUM(order_value)::NUMERIC, 2)                    AS total_revenue
    FROM order_tagged
    GROUP BY order_month
)

-- ── Final output ──────────────────────────────────────────────────────────────
SELECT
    order_month,
    -- Customer counts
    new_customers,
    returning_customers,
    total_customers,
    -- Order counts
    new_orders,
    returning_orders,
    total_orders,
    -- Revenue
    new_revenue,
    returning_revenue,
    total_revenue,
    -- Revenue mix percentages
    ROUND(new_revenue * 100.0 / NULLIF(total_revenue, 0), 2)       AS new_revenue_pct,
    ROUND(returning_revenue * 100.0 / NULLIF(total_revenue, 0), 2) AS returning_revenue_pct,
    -- Average order value by type
    ROUND(new_revenue / NULLIF(new_orders, 0), 2)                  AS new_avg_order_value,
    ROUND(returning_revenue / NULLIF(returning_orders, 0), 2)      AS returning_avg_order_value,
    -- Revenue per new customer acquired (acquisition efficiency proxy)
    ROUND(new_revenue / NULLIF(new_customers, 0), 2)               AS revenue_per_new_customer,
    -- MoM change in returning revenue (key retention growth metric)
    LAG(returning_revenue) OVER (ORDER BY order_month)             AS prev_month_returning_revenue,
    ROUND(
        (returning_revenue - LAG(returning_revenue) OVER (ORDER BY order_month))
        * 100.0 / NULLIF(LAG(returning_revenue) OVER (ORDER BY order_month), 0)
    , 2)                                                            AS returning_revenue_mom_growth_pct,
    -- MoM change in total revenue
    LAG(total_revenue) OVER (ORDER BY order_month)                 AS prev_month_total_revenue,
    ROUND(
        (total_revenue - LAG(total_revenue) OVER (ORDER BY order_month))
        * 100.0 / NULLIF(LAG(total_revenue) OVER (ORDER BY order_month), 0)
    , 2)                                                            AS total_revenue_mom_growth_pct,
    -- Cumulative returning revenue share trend (3-month rolling avg to smooth noise)
    ROUND(AVG(returning_revenue * 100.0 / NULLIF(total_revenue, 0))
        OVER (ORDER BY order_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
    , 2)                                                            AS returning_pct_3m_rolling_avg
FROM monthly_pivot
ORDER BY order_month;
