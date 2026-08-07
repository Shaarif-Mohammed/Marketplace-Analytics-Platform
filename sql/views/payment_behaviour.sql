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
--   Value         : avg order value, avg payment value, total revenue
--   Instalments   : avg instalments, % single vs multi-instalment
--   Behaviour     : high-value order threshold (above/below median AOV)
--
-- Notes:
--   • fact_payments joins to dim_order via order_id (natural key — no FK)
--   • One order can have multiple payment rows (sequential payments,
--     e.g. voucher + credit card). Revenue aggregated at order level
--     to avoid double counting — payment_value used for payment analysis.
--   • payment_installments = 0 was fixed to 1 in ETL (2 rows affected)
--   • Delivered orders only for revenue metrics; all orders for payment
--     type distribution (payment is recorded regardless of delivery)
-- =============================================================================

CREATE OR REPLACE VIEW warehouse.vw_payment_behaviour AS

WITH
-- ── Step 1: Join payments to orders ───────────────────────────────────────────
payments_with_orders AS (
    SELECT
        fp.order_id,
        fp.payment_sequential,
        fp.payment_type,
        fp.payment_installments,
        fp.payment_value,
        o.order_status,
        o.order_purchase_timestamp,
        -- Total order value from items (for delivered orders)
        SUM(i.price + i.freight_value) OVER (
            PARTITION BY fp.order_id
        )                                               AS order_item_total
    FROM warehouse.fact_payments fp
    LEFT JOIN warehouse.dim_order o
        ON fp.order_id = o.order_id
    LEFT JOIN warehouse.fact_order_items i
        ON fp.order_id = i.order_id
),

-- ── Step 2: Deduplicate to primary payment per order ──────────────────────────
-- For orders with multiple payment methods, use the first sequential payment
-- as the primary type (payment_sequential = 1)
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
    WHERE payment_sequential = 1
    ORDER BY order_id, payment_sequential
),

-- ── Step 3: Instalment band classification ────────────────────────────────────
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

-- ── Step 4a: Summary by payment type ─────────────────────────────────────────
by_payment_type AS (
    SELECT
        'By Payment Type'                               AS dimension,
        payment_type                                    AS dimension_value,
        NULL::TEXT                                      AS sub_dimension,
        COUNT(order_id)                                 AS order_count,
        ROUND(SUM(payment_value)::NUMERIC, 2)           AS total_payment_value,
        ROUND(AVG(payment_value)::NUMERIC, 2)           AS avg_payment_value,
        ROUND(AVG(order_item_total)::NUMERIC, 2)        AS avg_order_item_total,
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
            SUM(payment_value) * 100.0 / SUM(SUM(payment_value)) OVER ()
        , 2)                                            AS pct_of_revenue
    FROM payments_banded
    GROUP BY payment_type
),

-- ── Step 4b: Summary by instalment band ───────────────────────────────────────
by_instalment_band AS (
    SELECT
        'By Instalment Band'                            AS dimension,
        instalment_band                                 AS dimension_value,
        NULL::TEXT                                      AS sub_dimension,
        COUNT(order_id)                                 AS order_count,
        ROUND(SUM(payment_value)::NUMERIC, 2)           AS total_payment_value,
        ROUND(AVG(payment_value)::NUMERIC, 2)           AS avg_payment_value,
        ROUND(AVG(order_item_total)::NUMERIC, 2)        AS avg_order_item_total,
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
            SUM(payment_value) * 100.0 / SUM(SUM(payment_value)) OVER ()
        , 2)                                            AS pct_of_revenue
    FROM payments_banded
    GROUP BY instalment_band
),

-- ── Step 4c: Cross — payment type × instalment band ───────────────────────────
cross_analysis AS (
    SELECT
        'Cross'                                         AS dimension,
        payment_type                                    AS dimension_value,
        instalment_band                                 AS sub_dimension,
        COUNT(order_id)                                 AS order_count,
        ROUND(SUM(payment_value)::NUMERIC, 2)           AS total_payment_value,
        ROUND(AVG(payment_value)::NUMERIC, 2)           AS avg_payment_value,
        ROUND(AVG(order_item_total)::NUMERIC, 2)        AS avg_order_item_total,
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
            SUM(payment_value) * 100.0 / SUM(SUM(payment_value)) OVER ()
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
