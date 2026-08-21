-- =============================================================================
-- Marketplace Analytics Platform
-- View: warehouse.vw_retention
-- Script: cohort_retention.sql
-- Description: Monthly cohort retention analysis. Groups customers by the
--              month of their first delivered order (cohort month) and tracks
--              how many return to purchase in subsequent months.
--
-- Grain: One row per cohort_month × period_number combination.
-- Cohort: Defined by customer_unique_id's first delivered order month.
-- Period: Months elapsed since cohort month (0 = acquisition month).
-- Retention rate: Retained customers / cohort_size × 100.
--
-- Notes:
--   • Period 0 retention is always 100% by definition (cohort acquisition).
--   • Later cohorts (mid-2018) will show fewer periods — the dataset ends
--     Aug 2018 so they have not had time to return. This is expected and
--     is NOT a data quality issue — it is a right-censoring limitation.
--   • Repeat purchase rates are expected to be low (3–5%) — typical for
--     a Brazilian marketplace in growth phase.
-- =============================================================================

DROP VIEW IF EXISTS warehouse.vw_retention;

CREATE VIEW warehouse.vw_retention AS

WITH
-- ── Step 1: All delivered orders with customer and order month ────────────────
delivered_orders AS (
    SELECT
        c.customer_unique_id,
        DATE_TRUNC('month', o.order_purchase_timestamp)::DATE AS order_month
    FROM warehouse.dim_order o
    JOIN warehouse.dim_customer c
        ON o.customer_key = c.customer_key
    WHERE o.order_status = 'delivered'
),

-- ── Step 2: Identify each customer's cohort month (first order month) ─────────
customer_cohorts AS (
    SELECT
        customer_unique_id,
        MIN(order_month) AS cohort_month
    FROM delivered_orders
    GROUP BY customer_unique_id
),

-- ── Step 3: Calculate cohort size (customers acquired per month) ──────────────
cohort_sizes AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT customer_unique_id) AS cohort_size
    FROM customer_cohorts
    GROUP BY cohort_month
),

-- ── Step 4: Join orders back to cohorts and calculate period number ───────────
-- Period = months between cohort_month and the month of each subsequent order
cohort_activity AS (
    SELECT
        cc.customer_unique_id,
        cc.cohort_month,
        d.order_month,
        -- Number of months elapsed since cohort month
        (DATE_PART('year', d.order_month) - DATE_PART('year', cc.cohort_month)) * 12
        + (DATE_PART('month', d.order_month) - DATE_PART('month', cc.cohort_month))
        AS period_number
    FROM customer_cohorts cc
    JOIN delivered_orders d
        ON cc.customer_unique_id = d.customer_unique_id
),

-- ── Step 5: Count distinct retained customers per cohort × period ─────────────
retention_counts AS (
    SELECT
        cohort_month,
        period_number,
        COUNT(DISTINCT customer_unique_id) AS retained_customers
    FROM cohort_activity
    GROUP BY cohort_month, period_number
)

,
-- ── Step 6: Complete cohort × period grid (fills zero-retention gaps) ───────
-- Right-censoring preserved: only generates periods up to the dataset's last
-- observed order month, same window the original view was implicitly limited to.
dataset_bounds AS (
    SELECT MAX(order_month) AS last_order_month FROM delivered_orders
),
period_grid AS (
    SELECT
        cs.cohort_month,
        gs.period_number
    FROM cohort_sizes cs
    CROSS JOIN dataset_bounds db
    CROSS JOIN LATERAL generate_series(
        0,
        ((DATE_PART('year', db.last_order_month) - DATE_PART('year', cs.cohort_month)) * 12
        + (DATE_PART('month', db.last_order_month) - DATE_PART('month', cs.cohort_month)))::INTEGER
    ) AS gs(period_number)
)

-- ── Final output: complete grid, zero-filled where no customers returned ─────
SELECT
    g.cohort_month,
    cs.cohort_size,
    g.period_number,
    COALESCE(r.retained_customers, 0) AS retained_customers,
    ROUND(
        COALESCE(r.retained_customers, 0) * 100.0 / cs.cohort_size
    , 2) AS retention_rate_pct,
    LAG(COALESCE(r.retained_customers, 0)) OVER (
        PARTITION BY g.cohort_month
        ORDER BY g.period_number
    ) - COALESCE(r.retained_customers, 0) AS churned_from_prev_period
FROM period_grid g
JOIN cohort_sizes cs
    ON g.cohort_month = cs.cohort_month
LEFT JOIN retention_counts r
    ON g.cohort_month = r.cohort_month
    AND g.period_number = r.period_number
ORDER BY g.cohort_month, g.period_number;


