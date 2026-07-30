-- =============================================================================
-- Marketplace Analytics Platform
-- View: warehouse.vw_customer_health
-- Script: customer_health.sql
-- Description: Each customer's current activity status — Active, Dormant,
--              or Lost — based on days since their last delivered order.
--
-- Grain: One row per customer_unique_id (with at least one delivered order).
--
-- Definitions (unchanged from the original version):
--   Active : last delivered order within the last 6 months
--            (evaluated at dataset end date 2018-09-01, i.e. on/after 2018-03-01)
--   Dormant: last delivered order 6-12 months ago (on/after 2017-09-01)
--   Lost   : last delivered order more than 12 months ago
--
-- Change log (Phase 4): the original version of this view computed this
-- exact customer_status classification internally (in a customer_status
-- CTE) but never selected it in the final output — the final SELECT only
-- returned a monthly New-vs-Returning trend, leaving the status logic
-- dead code. This version:
--   (1) Surfaces the status classification as the view's actual output,
--       restructured to customer-grain rather than a pre-aggregated
--       snapshot, so it can relate to vw_rfm/vw_clv on customer_unique_id
--       like the rest of the customer-analytics views.
--   (2) Drops the monthly New-vs-Returning trend entirely — it duplicated
--       vw_new_vs_returning_revenue's logic and definitions almost
--       exactly (same delivered-orders base, same New/Returning rule,
--       just long-format here vs. that view's wide, Tableau-oriented
--       format). Removed per the redundant-data-elsewhere rule, not
--       because the finding itself was wrong.
--
-- Notes:
--   • Based on delivered orders only
--   • customer_unique_id is the person-level identifier (not customer_id)
--   • Does not duplicate order_count / days_since_last_order — those
--     already exist on vw_rfm; join there if needed rather than
--     recomputing, consistent with how vw_first_purchase_category_repeat
--     and vw_late_delivery_repeat_cohort are built.
-- =============================================================================

DROP VIEW IF EXISTS warehouse.vw_customer_health;

CREATE VIEW warehouse.vw_customer_health AS

WITH
-- ── Step 1: Last delivered order month per customer ──────────────────────────
delivered_orders AS (
    SELECT
        c.customer_unique_id,
        DATE_TRUNC('month', o.order_purchase_timestamp)::DATE   AS order_month
    FROM warehouse.dim_order o
    JOIN warehouse.dim_customer c
        ON o.customer_key = c.customer_key
    WHERE o.order_status = 'delivered'
),

-- ── Step 2: Status classification at dataset end (2018-09-01) ────────────────
customer_status AS (
    SELECT
        customer_unique_id,
        MAX(order_month)    AS last_order_month,
        CASE
            WHEN MAX(order_month) >= '2018-03-01' THEN 'Active'
            WHEN MAX(order_month) >= '2017-09-01' THEN 'Dormant'
            ELSE 'Lost'
        END AS customer_status
    FROM delivered_orders
    GROUP BY customer_unique_id
)

-- ── Final output ─────────────────────────────────────────────────────────────
SELECT
    customer_unique_id,
    last_order_month,
    customer_status
FROM customer_status
ORDER BY customer_status, last_order_month DESC;
