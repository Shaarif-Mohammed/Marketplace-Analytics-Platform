-- =============================================================================
-- Marketplace Analytics Platform
-- View: warehouse.vw_clv
-- Script: clv.sql
-- Description: Calculates historical and projected Customer Lifetime Value
--              for every customer. One row per customer_unique_id.
--
-- CLV Model: Simplified purchase-rate projection (not BG/NBD or Pareto/NBD).
--            Appropriate for a portfolio project on a 2-year dataset.
--            A full probabilistic model would require longer purchase history.
--
-- Projection logic (two paths):
--   One-time buyers  → projected_clv_12m = avg_order_value
--                      Conservative assumption: they may buy once more.
--                      CLV tier for one-time buyers reflects AOV potential,
--                      not purchase frequency — documented limitation.
--
--   Repeat buyers    → projected_clv_12m = avg_order_value
--                      × MIN(annualised_purchase_rate, 12)
--                      Actual purchase rate extrapolated to 12 months.
--                      Capped at 12 (monthly) to prevent inflation from
--                      customers who placed 2+ orders within days of each
--                      other (e.g. 2 orders / 2 days = 365 orders/year).
--                      lifespan_days floored at 1 to avoid division by zero.
--
-- CLV Tier: NTILE(3) on projected_clv_12m → High / Mid / Low
-- Joins to vw_rfm to bring in RFM segment for combined analysis.
-- Reference date: 2018-09-01 (consistent with vw_rfm)
-- =============================================================================

CREATE OR REPLACE VIEW warehouse.vw_clv AS

WITH
-- ── Step 1: Delivered orders with item-level revenue ─────────────────────────
delivered_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp,
        i.price + i.freight_value AS item_total
    FROM warehouse.dim_order o
    JOIN warehouse.dim_customer c
        ON o.customer_key = c.customer_key
    JOIN warehouse.fact_order_items i
        ON o.order_id = i.order_id
    WHERE o.order_status = 'delivered'
),

-- ── Step 2: Collapse items to order level (prevents multi-item inflation) ───
order_level AS (
    SELECT
        customer_unique_id,
        order_id,
        order_purchase_timestamp,
        SUM(item_total) AS order_total
    FROM delivered_orders
    GROUP BY customer_unique_id, order_id, order_purchase_timestamp
),

-- ── Step 3: Customer-level aggregation (order grain, not item grain) ────────
customer_metrics AS (
    SELECT
        customer_unique_id,
        COUNT(DISTINCT order_id)                AS order_count,
        ROUND(SUM(order_total)::NUMERIC, 2)     AS historical_clv,
        ROUND(AVG(order_total)::NUMERIC, 2)     AS avg_order_value,
        MIN(order_purchase_timestamp)::DATE     AS first_order_date,
        MAX(order_purchase_timestamp)::DATE     AS last_order_date,
        DATE_PART('day',
            MAX(order_purchase_timestamp) - MIN(order_purchase_timestamp)
        )::INTEGER                              AS lifespan_days,
        DATE_PART('day',
            '2018-09-01'::TIMESTAMP - MAX(order_purchase_timestamp)
        )::INTEGER                              AS days_since_last_order
    FROM order_level
    GROUP BY customer_unique_id
),

-- ── Step 4: Projected CLV calculation ────────────────────────────────────────
clv_projected AS (
    SELECT
        customer_unique_id,
        order_count,
        historical_clv,
        avg_order_value,
        first_order_date,
        last_order_date,
        lifespan_days,
        days_since_last_order,
        CASE
            WHEN order_count > 1
            THEN ROUND((lifespan_days::NUMERIC / (order_count - 1)), 1)
            ELSE NULL
        END AS avg_days_between_orders,
        -- Annualised purchase rate — capped at 12 (monthly ordering maximum)
        CASE
            WHEN order_count = 1 THEN 1.0
            ELSE LEAST(
                ROUND(
                    (order_count::NUMERIC / GREATEST(lifespan_days, 1)) * 365
                , 2),
                12.0
            )
        END AS annualised_purchase_rate,
        -- Projected CLV over next 12 months
        CASE
            WHEN order_count = 1
            THEN avg_order_value
            ELSE ROUND(
                avg_order_value * LEAST(
                    (order_count::NUMERIC / GREATEST(lifespan_days, 1)) * 365,
                    12.0
                )
            , 2)
        END AS projected_clv_12m
    FROM customer_metrics
),

-- ── Step 5: CLV tier using NTILE ─────────────────────────────────────────────
clv_tiered AS (
    SELECT
        *,
        CASE NTILE(3) OVER (ORDER BY projected_clv_12m ASC)
            WHEN 3 THEN 'High'
            WHEN 2 THEN 'Mid'
            WHEN 1 THEN 'Low'
        END AS clv_tier
    FROM clv_projected
)

-- ── Final output: join RFM segment ───────────────────────────────────────────
SELECT
    c.customer_unique_id,
    c.order_count,
    c.historical_clv,
    c.avg_order_value,
    c.projected_clv_12m,
    c.annualised_purchase_rate,
    c.clv_tier,
    r.segment                   AS rfm_segment,
    r.r_score,
    r.f_score,
    r.m_score,
    c.first_order_date,
    c.last_order_date,
    c.lifespan_days,
    c.days_since_last_order,
    c.avg_days_between_orders
FROM clv_tiered c
LEFT JOIN warehouse.vw_rfm r
    ON c.customer_unique_id = r.customer_unique_id
ORDER BY c.projected_clv_12m DESC, c.historical_clv DESC;
