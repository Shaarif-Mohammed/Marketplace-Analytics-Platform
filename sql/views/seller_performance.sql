-- =============================================================================
-- Marketplace Analytics Platform
-- View: warehouse.vw_seller_performance
-- Script: seller_performance.sql
-- Description: Comprehensive seller scorecard. One row per seller with
--              revenue, volume, review, and delivery performance metrics.
--              Includes a composite performance score and tier ranking.
--
-- Metrics:
--   Revenue       : total revenue (price + freight) from delivered orders
--   Volume        : total orders and items sold
--   Review        : average review score, % 5-star, % 1-star
--   Delivery      : on-time delivery rate, avg days to deliver
--   Cancellation  : cancellation rate across all orders
--
-- Performance score: weighted composite (0-100)
--   40% avg_review_score   (normalised to 0-100)
--   30% on_time_rate       (already 0-100)
--   20% revenue rank       (NTILE normalised to 0-100)
--   10% cancellation       (inverted: 100 - cancellation_rate)
--
-- Performance tier: based on composite score
--   Elite      : score >= 80
--   Strong     : score >= 60
--   Average    : score >= 40
--   Needs Work : score < 40
--
-- Minimum threshold: sellers with fewer than 5 orders excluded from
-- performance scoring — included in view as 'Insufficient Data'.
--
-- Fix note: on_time_rate calculated at ORDER level (not item level) to
-- prevent inflation from multi-item orders being counted multiple times.
-- Deduplication done in order_level_delivery CTE before aggregation.
-- This remains correct and unchanged in this version — verified
-- independently rather than assumed. See AUDIT FIX below for issues
-- found elsewhere in the same view that this note didn't cover.
-- =============================================================================

CREATE OR REPLACE VIEW warehouse.vw_seller_performance AS

WITH
-- ── Step 1: All order-seller combinations (item level) ────────────────────────
all_items AS (
    SELECT
        s.seller_id,
        o.order_id,
        o.order_status,
        o.order_purchase_timestamp,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        i.price,
        i.freight_value
    FROM warehouse.fact_order_items i
    JOIN warehouse.dim_order o
        ON i.order_key = o.order_key
    JOIN warehouse.dim_seller s
        ON i.seller_key = s.seller_key
),

-- ── Step 1b: True delivered order count per seller (no date filter) ─────────
true_delivered_orders AS (
    SELECT
        seller_id,
        COUNT(DISTINCT order_id) AS delivered_orders
    FROM all_items
    WHERE order_status = 'delivered'
    GROUP BY seller_id
),

-- ── Step 1c: Order-level revenue for a correct avg_order_value ──────────────
order_level_revenue AS (
    SELECT
        seller_id,
        order_id,
        SUM(price + freight_value) AS order_total
    FROM all_items
    WHERE order_status = 'delivered'
    GROUP BY seller_id, order_id
),

-- ── Step 2: Deduplicate to order level for delivery metrics ───────────────────
-- One row per seller × order to prevent multi-item orders inflating on_time_rate
order_level_delivery AS (
    SELECT DISTINCT
        seller_id,
        order_id,
        order_purchase_timestamp,
        order_delivered_customer_date,
        order_estimated_delivery_date
    FROM all_items
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date IS NOT NULL
      AND order_estimated_delivery_date IS NOT NULL
),

-- ── Step 3: Delivery timing metrics per seller (dates required, by design) ──
delivered_metrics AS (
    SELECT
        seller_id,
        ROUND(AVG(
            DATE_PART('day',
                order_delivered_customer_date - order_purchase_timestamp
            )
        )::NUMERIC, 1)                          AS avg_delivery_days,
        ROUND(
            SUM(CASE
                WHEN order_delivered_customer_date <= order_estimated_delivery_date
                THEN 1 ELSE 0
            END) * 100.0 / COUNT(order_id)
        , 2)                                    AS on_time_rate
    FROM order_level_delivery
    GROUP BY seller_id
),

-- ── Step 4: Revenue at item level for totals, order level for the average ───
revenue_item_totals AS (
    SELECT
        seller_id,
        ROUND(SUM(price + freight_value)::NUMERIC, 2)   AS total_revenue,
        ROUND(SUM(price)::NUMERIC, 2)                   AS total_product_revenue,
        ROUND(SUM(freight_value)::NUMERIC, 2)           AS total_freight_revenue
    FROM all_items
    WHERE order_status = 'delivered'
    GROUP BY seller_id
),
revenue_order_avg AS (
    SELECT
        seller_id,
        ROUND(AVG(order_total)::NUMERIC, 2) AS avg_order_value
    FROM order_level_revenue
    GROUP BY seller_id
),
revenue_metrics AS (
    SELECT
        rit.seller_id,
        rit.total_revenue,
        rit.total_product_revenue,
        rit.total_freight_revenue,
        roa.avg_order_value
    FROM revenue_item_totals rit
    LEFT JOIN revenue_order_avg roa
        ON rit.seller_id = roa.seller_id
),

-- ── Step 5: Total order volume per seller (all statuses) ─────────────────────
total_volume AS (
    SELECT
        seller_id,
        COUNT(DISTINCT order_id)    AS total_orders,
        COUNT(*)                    AS total_items_sold,
        ROUND(
            COUNT(DISTINCT CASE WHEN order_status = 'canceled' THEN order_id END)
            * 100.0 / COUNT(DISTINCT order_id)
        , 2)                        AS cancellation_rate
    FROM all_items
    GROUP BY seller_id
),

-- ── Step 6: Reviews deduplicated to order grain before joining (no fan-out) ─
review_dedup AS (
    SELECT order_id, AVG(review_score) AS order_review_score
    FROM warehouse.fact_reviews
    GROUP BY order_id
),
seller_order_pairs AS (
    SELECT DISTINCT seller_id, order_id
    FROM all_items
),
review_metrics AS (
    SELECT
        sop.seller_id,
        COUNT(DISTINCT sop.order_id) FILTER (WHERE rd.order_review_score IS NOT NULL) AS total_reviews,
        ROUND(AVG(rd.order_review_score)::NUMERIC, 2)         AS avg_review_score,
        ROUND(
            SUM(CASE WHEN rd.order_review_score = 5 THEN 1 ELSE 0 END) * 100.0
            / NULLIF(COUNT(DISTINCT sop.order_id) FILTER (WHERE rd.order_review_score IS NOT NULL), 0)
        , 2)                                                  AS pct_5_star,
        ROUND(
            SUM(CASE WHEN rd.order_review_score = 1 THEN 1 ELSE 0 END) * 100.0
            / NULLIF(COUNT(DISTINCT sop.order_id) FILTER (WHERE rd.order_review_score IS NOT NULL), 0)
        , 2)                                                  AS pct_1_star
    FROM seller_order_pairs sop
    LEFT JOIN review_dedup rd
        ON sop.order_id = rd.order_id
    GROUP BY sop.seller_id
),

-- ── Step 7: Combine all metrics ───────────────────────────────────────────────
combined AS (
    SELECT
        s.seller_id,
        s.seller_city,
        s.seller_state,
        COALESCE(tv.total_orders, 0)                            AS total_orders,
        COALESCE(tv.total_items_sold, 0)                        AS total_items_sold,
        COALESCE(tv.cancellation_rate, 0)                       AS cancellation_rate,
        COALESCE(tdo.delivered_orders, 0)                       AS delivered_orders,
        COALESCE(rm2.total_revenue, 0)                          AS total_revenue,
        COALESCE(rm2.avg_order_value, 0)                        AS avg_order_value,
        COALESCE(rm2.total_product_revenue, 0)                  AS total_product_revenue,
        COALESCE(rm2.total_freight_revenue, 0)                  AS total_freight_revenue,
        COALESCE(dm.avg_delivery_days, 0)                       AS avg_delivery_days,
        COALESCE(dm.on_time_rate, 0)                            AS on_time_rate,
        COALESCE(rm.total_reviews, 0)                           AS total_reviews,
        COALESCE(rm.avg_review_score, 0)                        AS avg_review_score,
        COALESCE(rm.pct_5_star, 0)                              AS pct_5_star,
        COALESCE(rm.pct_1_star, 0)                              AS pct_1_star
    FROM warehouse.dim_seller s
    LEFT JOIN total_volume tv          ON s.seller_id = tv.seller_id
    LEFT JOIN true_delivered_orders tdo ON s.seller_id = tdo.seller_id
    LEFT JOIN delivered_metrics dm     ON s.seller_id = dm.seller_id
    LEFT JOIN revenue_metrics rm2      ON s.seller_id = rm2.seller_id
    LEFT JOIN review_metrics rm        ON s.seller_id = rm.seller_id
),

-- ── Step 8: Revenue percentile (0-100) ───────────────────────────────────────
revenue_ranked AS (
    SELECT
        *,
        ROUND(
            (NTILE(100) OVER (ORDER BY total_revenue ASC))::NUMERIC
        , 2) AS revenue_percentile
    FROM combined
),

-- ── Step 9: Composite performance score ──────────────────────────────────────
scored AS (
    SELECT
        *,
        CASE
            WHEN total_orders < 5 THEN NULL
            ELSE ROUND(
                (avg_review_score / 5.0 * 100 * 0.40)
                + (on_time_rate * 0.30)
                + (revenue_percentile * 0.20)
                + ((100 - cancellation_rate) * 0.10)
            , 2)
        END AS performance_score
    FROM revenue_ranked
)

-- ── Final output ──────────────────────────────────────────────────────────────
SELECT
    seller_id,
    seller_city,
    seller_state,
    total_orders,
    total_items_sold,
    delivered_orders,
    total_revenue,
    avg_order_value,
    total_product_revenue,
    total_freight_revenue,
    avg_delivery_days,
    on_time_rate,
    cancellation_rate,
    total_reviews,
    avg_review_score,
    pct_5_star,
    pct_1_star,
    revenue_percentile,
    performance_score,
    CASE
        WHEN total_orders < 5        THEN 'Insufficient Data'
        WHEN performance_score >= 80 THEN 'Elite'
        WHEN performance_score >= 60 THEN 'Strong'
        WHEN performance_score >= 40 THEN 'Average'
        ELSE                              'Needs Work'
    END AS performance_tier
FROM scored
ORDER BY performance_score DESC NULLS LAST, total_revenue DESC;
