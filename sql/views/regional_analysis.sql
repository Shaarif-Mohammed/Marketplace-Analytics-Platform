-- =============================================================================
-- Marketplace Analytics Platform
-- View: warehouse.vw_regional_analysis
-- Script: regional_analysis.sql
-- Description: Geographic revenue and customer analysis at Brazilian state
--              level. Shows where customers and sellers are concentrated,
--              revenue distribution, and average order values by region.
--
-- Grain: One row per customer_state.
-- Geography: Based on customer delivery state (demand side), not seller state.
--            Seller state analysis included separately for supply-side view.
--
-- Metrics:
--   Demand side  : customer count, order count, revenue, AOV by customer state
--   Supply side  : seller count, seller revenue by seller state
--   Cross metric : avg delivery days by customer state (logistics insight)
--
-- Notes:
--   • Revenue = price + freight_value from delivered orders only
--   • States with NULL geolocation_key are still included — state comes
--     from dim_customer/dim_seller directly, not from dim_geolocation
--   • Brazil has 26 states + 1 federal district (DF) = 27 regions expected
-- =============================================================================

CREATE OR REPLACE VIEW warehouse.vw_regional_analysis AS

WITH
-- ── Demand side: customer state metrics ───────────────────────────────────────
customer_state_metrics AS (
    SELECT
        c.customer_state,
        COUNT(DISTINCT c.customer_unique_id)            AS unique_customers,
        COUNT(DISTINCT o.order_id)                      AS total_orders,
        ROUND(SUM(i.price + i.freight_value)::NUMERIC, 2)  AS total_revenue,
        ROUND(AVG(i.price + i.freight_value)::NUMERIC, 2)  AS avg_order_value,
        ROUND(SUM(i.price)::NUMERIC, 2)                 AS total_product_revenue,
        ROUND(SUM(i.freight_value)::NUMERIC, 2)         AS total_freight_revenue,
        -- Average delivery time by customer state
        ROUND(AVG(
            CASE
                WHEN o.order_delivered_customer_date IS NOT NULL
                THEN DATE_PART('day',
                    o.order_delivered_customer_date - o.order_purchase_timestamp
                )
            END
        )::NUMERIC, 1)                                  AS avg_delivery_days,
        -- On-time delivery rate by customer state
        ROUND(
            SUM(CASE
                WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date
                THEN 1 ELSE 0
            END) * 100.0
            / NULLIF(COUNT(CASE
                WHEN o.order_delivered_customer_date IS NOT NULL
                AND o.order_estimated_delivery_date IS NOT NULL
                THEN 1 END), 0)
        , 2)                                            AS on_time_rate,
        -- Average review score by customer state
        ROUND(AVG(r.review_score)::NUMERIC, 2)          AS avg_review_score
    FROM warehouse.dim_customer c
    JOIN warehouse.dim_order o
        ON c.customer_key = o.customer_key
    JOIN warehouse.fact_order_items i
        ON o.order_id = i.order_id
    LEFT JOIN warehouse.fact_reviews r
        ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_state
),

-- ── Supply side: seller state metrics ─────────────────────────────────────────
seller_state_metrics AS (
    SELECT
        s.seller_state,
        COUNT(DISTINCT s.seller_id)                     AS total_sellers,
        ROUND(SUM(i.price + i.freight_value)::NUMERIC, 2)  AS seller_total_revenue,
        COUNT(DISTINCT o.order_id)                      AS seller_total_orders
    FROM warehouse.dim_seller s
    JOIN warehouse.fact_order_items i
        ON s.seller_key = i.seller_key
    JOIN warehouse.dim_order o
        ON i.order_key = o.order_key
    WHERE o.order_status = 'delivered'
    GROUP BY s.seller_state
),

-- ── Revenue share calculation ─────────────────────────────────────────────────
total_revenue AS (
    SELECT SUM(total_revenue) AS grand_total
    FROM customer_state_metrics
)

-- ── Final output ──────────────────────────────────────────────────────────────
SELECT
    csm.customer_state                                          AS state,
    csm.unique_customers,
    csm.total_orders,
    csm.total_revenue,
    csm.avg_order_value,
    csm.total_product_revenue,
    csm.total_freight_revenue,
    -- Revenue share of national total
    ROUND(
        csm.total_revenue * 100.0 / tr.grand_total
    , 2)                                                        AS revenue_share_pct,
    -- Cumulative revenue share (for Pareto analysis)
    ROUND(
        SUM(csm.total_revenue) OVER (
            ORDER BY csm.total_revenue DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) * 100.0 / tr.grand_total
    , 2)                                                        AS cumulative_revenue_pct,
    csm.avg_delivery_days,
    csm.on_time_rate,
    csm.avg_review_score,
    -- Supply side metrics for this state
    COALESCE(ssm.total_sellers, 0)                             AS total_sellers,
    COALESCE(ssm.seller_total_revenue, 0)                      AS seller_total_revenue,
    COALESCE(ssm.seller_total_orders, 0)                       AS seller_total_orders,
    -- Demand vs supply ratio: orders per seller in state
    CASE
        WHEN COALESCE(ssm.total_sellers, 0) = 0 THEN NULL
        ELSE ROUND(csm.total_orders::NUMERIC / ssm.total_sellers, 1)
    END                                                         AS orders_per_seller
FROM customer_state_metrics csm
CROSS JOIN total_revenue tr
LEFT JOIN seller_state_metrics ssm
    ON csm.customer_state = ssm.seller_state
ORDER BY csm.total_revenue DESC;
