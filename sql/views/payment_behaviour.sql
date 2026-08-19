-- =============================================================================
-- Marketplace Analytics Platform
-- View: warehouse.vw_payment_behaviour
-- Script: payment_behaviour.sql
-- Description: Payment pattern analysis covering payment method distribution,
--              instalment behaviour, and the relationship between order value
--              and payment choice. Three grains unified via UNION ALL.
--
-- Grain: Three result sets:
--   'By Payment Type'   : one row per payment_type
--   'By Instalment Band': one row per instalment_band (grouped ranges)
--   'Cross'             : one row per payment_type × instalment_band
--                         (for heatmap in Tableau)
--
-- Metrics:
--   Volume        : order count, transaction count, revenue share
--                   (all orders — payment is recorded regardless of delivery)
--   Value         : avg order value, avg payment value, total revenue
--                   (DELIVERED ORDERS ONLY — see AUDIT FIX)
--   Instalments   : avg instalments, % single vs multi-instalment (all orders
--                   — instalment choice is valid behavioral data regardless
--                   of whether the order was later delivered)
--   Behaviour     : high-value order threshold (above/below median AOV)
--
-- Notes:
--   • fact_payments joins to dim_order via order_id (natural key — no FK)
--   • One order can have multiple payment rows (sequential payments,
--     e.g. voucher + credit card). Revenue aggregated at order level
--     to avoid double counting — payment_value used for payment analysis.
--   • payment_installments = 0 was fixed to 1 in ETL (2 rows affected)
--   • Delivered orders only for revenue metrics; all orders for payment
--     type distribution (payment is recorded regardless of delivery).

-- =============================================================================

CREATE OR REPLACE VIEW warehouse.vw_payment_behaviour AS

WITH
-- ── Step 1: Order-level item totals (no fan-out — one row per order) ────────
order_level_items AS (
    SELECT
        order_id,
        SUM(price + freight_value) AS order_item_total
    FROM warehouse.fact_order_items
    GROUP BY order_id
),

-- ── Step 2: Join payments to orders (no item join here — avoids fan-out) ────
payments_with_orders AS (
    SELECT
        fp.order_id,
        fp.payment_sequential,
        fp.payment_type,
        fp.payment_installments,
        fp.payment_value,
        o.order_status,
        o.order_purchase_timestamp,
        oli.order_item_total
    FROM warehouse.fact_payments fp
    LEFT JOIN warehouse.dim_order o
        ON fp.order_id = o.order_id
    LEFT JOIN order_level_items oli
        ON fp.order_id = oli.order_id
),

-- ── Step 3: Deduplicate to primary payment per order ──────────────────────────
-- Each order's LOWEST available sequential payment is treated as primary —
-- not hardcoded to exactly 1, since some orders' sequences start higher.
primary_payments AS (
    SELECT DISTINCT ON (order_id)
        order_id,
        payment_type,
        payment_installments,
        payment_value,
        order_status,
        order_purchase_timestamp,
        order_item_total
    FROM payments_with_orders
    ORDER BY order_id, payment_sequential ASC
),

-- ── Step 4: Instalment band classification ────────────────────────────────────
payments_banded AS (
    SELECT
        *,
        CASE
            WHEN payment_installments = 1  THEN '1 (Single)'
            WHEN payment_installments <= 3 THEN '2-3'
            WHEN payment_installments <= 6 THEN '4-6'
            WHEN payment_installments <= 12 THEN '7-12'
            ELSE '12+'
        END AS instalment_band,
        -- Order value bucket (above/below 200 BRL median)
        CASE
            WHEN order_item_total >= 200 THEN 'High Value (200+ BRL)'
            ELSE 'Standard Value (<200 BRL)'
        END AS order_value_bucket
    FROM primary_payments
),

-- ── Step 5a: Summary by payment type ─────────────────────────────────────────
by_payment_type AS (
    SELECT
        'By Payment Type'                               AS dimension,
        payment_type                                    AS dimension_value,
        NULL::TEXT                                      AS sub_dimension,
        COUNT(order_id)                                 AS order_count,
        ROUND(SUM(CASE WHEN order_status = 'delivered'
            THEN order_item_total END)::NUMERIC, 2)     AS total_payment_value,
        ROUND(AVG(CASE WHEN order_status = 'delivered'
            THEN order_item_total END)::NUMERIC, 2)     AS avg_payment_value,
        ROUND(AVG(CASE WHEN order_status = 'delivered'
            THEN order_item_total END)::NUMERIC, 2)     AS avg_order_item_total,
        ROUND(AVG(payment_installments)::NUMERIC, 2)    AS avg_instalments,
        SUM(CASE WHEN payment_installments = 1
            THEN 1 ELSE 0 END)                          AS single_instalment_orders,
        SUM(CASE WHEN payment_installments > 1
            THEN 1 ELSE 0 END)                          AS multi_instalment_orders,
        ROUND(
            SUM(CASE WHEN payment_installments = 1 THEN 1 ELSE 0 END)
            * 100.0 / COUNT(order_id)
        , 2)                                            AS pct_single_instalment,
        ROUND(
            SUM(CASE WHEN payment_installments > 6 THEN 1 ELSE 0 END)
            * 100.0 / COUNT(order_id)
        , 2)                                            AS pct_high_instalment,
        ROUND(
            COUNT(order_id) * 100.0 / SUM(COUNT(order_id)) OVER ()
        , 2)                                            AS pct_of_orders,
        ROUND(
            SUM(CASE WHEN order_status = 'delivered' THEN order_item_total END) * 100.0
            / SUM(SUM(CASE WHEN order_status = 'delivered' THEN order_item_total END)) OVER ()
        , 2)                                            AS pct_of_revenue
    FROM payments_banded
    GROUP BY payment_type
),

-- ── Step 5b: Summary by instalment band ───────────────────────────────────────
by_instalment_band AS (
    SELECT
        'By Instalment Band'                            AS dimension,
        instalment_band                                 AS dimension_value,
        NULL::TEXT                                      AS sub_dimension,
        COUNT(order_id)                                 AS order_count,
        ROUND(SUM(CASE WHEN order_status = 'delivered'
            THEN order_item_total END)::NUMERIC, 2)     AS total_payment_value,
        ROUND(AVG(CASE WHEN order_status = 'delivered'
            THEN order_item_total END)::NUMERIC, 2)     AS avg_payment_value,
        ROUND(AVG(CASE WHEN order_status = 'delivered'
            THEN order_item_total END)::NUMERIC, 2)     AS avg_order_item_total,
        ROUND(AVG(payment_installments)::NUMERIC, 2)    AS avg_instalments,
        SUM(CASE WHEN payment_installments = 1
            THEN 1 ELSE 0 END)                          AS single_instalment_orders,
        SUM(CASE WHEN payment_installments > 1
            THEN 1 ELSE 0 END)                          AS multi_instalment_orders,
        ROUND(
            SUM(CASE WHEN payment_installments = 1 THEN 1 ELSE 0 END)
            * 100.0 / COUNT(order_id)
        , 2)                                            AS pct_single_instalment,
        ROUND(
            SUM(CASE WHEN payment_installments > 6 THEN 1 ELSE 0 END)
            * 100.0 / COUNT(order_id)
        , 2)                                            AS pct_high_instalment,
        ROUND(
            COUNT(order_id) * 100.0 / SUM(COUNT(order_id)) OVER ()
        , 2)                                            AS pct_of_orders,
        ROUND(
            SUM(CASE WHEN order_status = 'delivered' THEN order_item_total END) * 100.0
            / SUM(SUM(CASE WHEN order_status = 'delivered' THEN order_item_total END)) OVER ()
        , 2)                                            AS pct_of_revenue
    FROM payments_banded
    GROUP BY instalment_band
),

-- ── Step 5c: Cross — payment type × instalment band ───────────────────────────
cross_analysis AS (
    SELECT
        'Cross'                                         AS dimension,
        payment_type                                    AS dimension_value,
        instalment_band                                 AS sub_dimension,
        COUNT(order_id)                                 AS order_count,
        ROUND(SUM(CASE WHEN order_status = 'delivered'
            THEN order_item_total END)::NUMERIC, 2)     AS total_payment_value,
        ROUND(AVG(CASE WHEN order_status = 'delivered'
            THEN order_item_total END)::NUMERIC, 2)     AS avg_payment_value,
        ROUND(AVG(CASE WHEN order_status = 'delivered'
            THEN order_item_total END)::NUMERIC, 2)     AS avg_order_item_total,
        ROUND(AVG(payment_installments)::NUMERIC, 2)    AS avg_instalments,
        SUM(CASE WHEN payment_installments = 1
            THEN 1 ELSE 0 END)                          AS single_instalment_orders,
        SUM(CASE WHEN payment_installments > 1
            THEN 1 ELSE 0 END)                          AS multi_instalment_orders,
        ROUND(
            SUM(CASE WHEN payment_installments = 1 THEN 1 ELSE 0 END)
            * 100.0 / COUNT(order_id)
        , 2)                                            AS pct_single_instalment,
        ROUND(
            SUM(CASE WHEN payment_installments > 6 THEN 1 ELSE 0 END)
            * 100.0 / COUNT(order_id)
        , 2)                                            AS pct_high_instalment,
        ROUND(
            COUNT(order_id) * 100.0 / SUM(COUNT(order_id)) OVER ()
        , 2)                                            AS pct_of_orders,
        ROUND(
            SUM(CASE WHEN order_status = 'delivered' THEN order_item_total END) * 100.0
            / SUM(SUM(CASE WHEN order_status = 'delivered' THEN order_item_total END)) OVER ()
        , 2)                                            AS pct_of_revenue
    FROM payments_banded
    GROUP BY payment_type, instalment_band
)

-- ── Final output ──────────────────────────────────────────────────────────────
SELECT * FROM by_payment_type
UNION ALL
SELECT * FROM by_instalment_band
UNION ALL
SELECT * FROM cross_analysis
ORDER BY dimension, pct_of_orders DESC;
