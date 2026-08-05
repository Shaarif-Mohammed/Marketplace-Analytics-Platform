-- =============================================================================
-- Marketplace Analytics Platform
-- View: warehouse.vw_delivery_experience
-- Script: delivery_experience.sql
-- Description: Delivery performance analysis linking delivery speed and
--              on-time rate to customer review scores. Covers three grains:
--              overall summary, by customer state, and by delivery status
--              (on-time vs late) with associated review score impact.
--
-- Grain: Three result sets unified via UNION ALL:
--        - 'Overall'       : one row — national delivery summary
--        - 'By State'      : one row per customer_state
--        - 'On-time vs Late': two rows — on-time and late delivery comparison
--
-- Metrics:
--   Delivery time    : avg, min, max, median days from purchase to delivery
--   On-time rate     : % delivered on or before estimated delivery date
--   Early delivery   : % delivered more than 2 days before estimated date
--   Late delivery    : % delivered after estimated date
--   Review impact    : avg review score for on-time vs late deliveries
--   Early buffer     : avg days between actual and estimated delivery (negative = early)
--
-- Notes:
--   • Delivered orders only with non-null delivery dates
--   • Calculated at order level (not item level) to avoid multi-item inflation
--   • Median approximated using PERCENTILE_CONT(0.5)
--   • Review score joined via order_id (natural key)
-- =============================================================================

CREATE OR REPLACE VIEW warehouse.vw_delivery_experience AS

WITH
-- ── Step 1: Order-level delivery metrics (deduplicated to avoid item fan-out) ──
order_delivery AS (
    SELECT DISTINCT
        o.order_id,
        c.customer_state,
        o.order_purchase_timestamp,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        -- Actual delivery days
        DATE_PART('day',
            o.order_delivered_customer_date - o.order_purchase_timestamp
        )                                               AS delivery_days,
        -- Days vs estimate (negative = delivered early, positive = delivered late)
        DATE_PART('day',
            o.order_delivered_customer_date - o.order_estimated_delivery_date
        )                                               AS days_vs_estimate,
        -- On-time flag
        CASE
            WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date
            THEN 'On-Time'
            ELSE 'Late'
        END                                             AS delivery_status,
        -- Early flag (delivered 2+ days before estimate)
        CASE
            WHEN o.order_delivered_customer_date <=
                 o.order_estimated_delivery_date - INTERVAL '2 days'
            THEN TRUE ELSE FALSE
        END                                             AS is_early
    FROM warehouse.dim_order o
    JOIN warehouse.dim_customer c
        ON o.customer_key = c.customer_key
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
),

-- ── Step 2: Join review scores at order level ─────────────────────────────────
order_delivery_reviews AS (
    SELECT
        od.*,
        AVG(r.review_score) AS review_score   -- avg handles rare multi-review orders
    FROM order_delivery od
    LEFT JOIN warehouse.fact_reviews r
        ON od.order_id = r.order_id
    GROUP BY
        od.order_id, od.customer_state, od.order_purchase_timestamp,
        od.order_delivered_customer_date, od.order_estimated_delivery_date,
        od.delivery_days, od.days_vs_estimate, od.delivery_status, od.is_early
),

-- ── Step 3a: Overall national summary ────────────────────────────────────────
overall_summary AS (
    SELECT
        'Overall'                                       AS dimension,
        'National'                                      AS dimension_value,
        COUNT(*)                                        AS total_orders,
        ROUND(AVG(delivery_days)::NUMERIC, 1)           AS avg_delivery_days,
        ROUND(MIN(delivery_days)::NUMERIC, 1)           AS min_delivery_days,
        ROUND(MAX(delivery_days)::NUMERIC, 1)           AS max_delivery_days,
        ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP
            (ORDER BY delivery_days)::NUMERIC, 1)       AS median_delivery_days,
        ROUND(
            SUM(CASE WHEN delivery_status = 'On-Time' THEN 1 ELSE 0 END)
            * 100.0 / COUNT(*)
        , 2)                                            AS on_time_rate,
        ROUND(
            SUM(CASE WHEN is_early THEN 1 ELSE 0 END)
            * 100.0 / COUNT(*)
        , 2)                                            AS early_delivery_rate,
        ROUND(
            SUM(CASE WHEN delivery_status = 'Late' THEN 1 ELSE 0 END)
            * 100.0 / COUNT(*)
        , 2)                                            AS late_delivery_rate,
        ROUND(AVG(days_vs_estimate)::NUMERIC, 1)        AS avg_days_vs_estimate,
        ROUND(AVG(review_score)::NUMERIC, 2)            AS avg_review_score,
        ROUND(AVG(CASE WHEN delivery_status = 'On-Time'
            THEN review_score END)::NUMERIC, 2)         AS avg_review_on_time,
        ROUND(AVG(CASE WHEN delivery_status = 'Late'
            THEN review_score END)::NUMERIC, 2)         AS avg_review_late
    FROM order_delivery_reviews
),

-- ── Step 3b: By customer state ────────────────────────────────────────────────
state_summary AS (
    SELECT
        'By State'                                      AS dimension,
        customer_state                                  AS dimension_value,
        COUNT(*)                                        AS total_orders,
        ROUND(AVG(delivery_days)::NUMERIC, 1)           AS avg_delivery_days,
        ROUND(MIN(delivery_days)::NUMERIC, 1)           AS min_delivery_days,
        ROUND(MAX(delivery_days)::NUMERIC, 1)           AS max_delivery_days,
        ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP
            (ORDER BY delivery_days)::NUMERIC, 1)       AS median_delivery_days,
        ROUND(
            SUM(CASE WHEN delivery_status = 'On-Time' THEN 1 ELSE 0 END)
            * 100.0 / COUNT(*)
        , 2)                                            AS on_time_rate,
        ROUND(
            SUM(CASE WHEN is_early THEN 1 ELSE 0 END)
            * 100.0 / COUNT(*)
        , 2)                                            AS early_delivery_rate,
        ROUND(
            SUM(CASE WHEN delivery_status = 'Late' THEN 1 ELSE 0 END)
            * 100.0 / COUNT(*)
        , 2)                                            AS late_delivery_rate,
        ROUND(AVG(days_vs_estimate)::NUMERIC, 1)        AS avg_days_vs_estimate,
        ROUND(AVG(review_score)::NUMERIC, 2)            AS avg_review_score,
        ROUND(AVG(CASE WHEN delivery_status = 'On-Time'
            THEN review_score END)::NUMERIC, 2)         AS avg_review_on_time,
        ROUND(AVG(CASE WHEN delivery_status = 'Late'
            THEN review_score END)::NUMERIC, 2)         AS avg_review_late
    FROM order_delivery_reviews
    GROUP BY customer_state
),

-- ── Step 3c: On-time vs late comparison ───────────────────────────────────────
status_summary AS (
    SELECT
        'On-time vs Late'                               AS dimension,
        delivery_status                                 AS dimension_value,
        COUNT(*)                                        AS total_orders,
        ROUND(AVG(delivery_days)::NUMERIC, 1)           AS avg_delivery_days,
        ROUND(MIN(delivery_days)::NUMERIC, 1)           AS min_delivery_days,
        ROUND(MAX(delivery_days)::NUMERIC, 1)           AS max_delivery_days,
        ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP
            (ORDER BY delivery_days)::NUMERIC, 1)       AS median_delivery_days,
        ROUND(
            SUM(CASE WHEN delivery_status = 'On-Time' THEN 1 ELSE 0 END)
            * 100.0 / COUNT(*)
        , 2)                                            AS on_time_rate,
        ROUND(
            SUM(CASE WHEN is_early THEN 1 ELSE 0 END)
            * 100.0 / COUNT(*)
        , 2)                                            AS early_delivery_rate,
        ROUND(
            SUM(CASE WHEN delivery_status = 'Late' THEN 1 ELSE 0 END)
            * 100.0 / COUNT(*)
        , 2)                                            AS late_delivery_rate,
        ROUND(AVG(days_vs_estimate)::NUMERIC, 1)        AS avg_days_vs_estimate,
        ROUND(AVG(review_score)::NUMERIC, 2)            AS avg_review_score,
        ROUND(AVG(CASE WHEN delivery_status = 'On-Time'
            THEN review_score END)::NUMERIC, 2)         AS avg_review_on_time,
        ROUND(AVG(CASE WHEN delivery_status = 'Late'
            THEN review_score END)::NUMERIC, 2)         AS avg_review_late
    FROM order_delivery_reviews
    GROUP BY delivery_status
)

-- ── Final output: union all three grains ──────────────────────────────────────
SELECT * FROM overall_summary
UNION ALL
SELECT * FROM state_summary
UNION ALL
SELECT * FROM status_summary
ORDER BY dimension, total_orders DESC;
