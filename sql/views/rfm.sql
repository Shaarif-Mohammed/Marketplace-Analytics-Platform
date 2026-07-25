-- =============================================================================
-- Marketplace Analytics Platform
-- View: warehouse.vw_rfm
-- Script: rfm.sql
-- Description: Calculates RFM (Recency, Frequency, Monetary) scores for every
--              customer and assigns a segment label. One row per
--              customer_unique_id — the true person identifier across orders.
--
-- Reference date: 2018-09-01 (start of month following last delivered order)
-- Scoring method: NTILE(5) per dimension → scores 1–5 (5 = best)
-- Recency note:   Lower days since last order = more recent = higher score,
--                 so recency NTILE is inverted (1 becomes 5, 5 becomes 1)
--
-- Segment logic (based on combined R+F scores):
--   Champions        : R=5, F=5
--   Loyal            : F >= 4
--   Potential Loyal  : R >= 4, F <= 2
--   Recent           : R = 5, F = 1
--   Promising        : R >= 3, F <= 2
--   Need Attention   : R >= 3, F >= 3
--   About to Sleep   : R <= 2, F <= 2
--   At Risk          : R <= 2, F >= 3
--   Cannot Lose Them : R = 1, F >= 4
--  (9 segments total — the CASE ELSE covers every remaining R/F combination
--   as 'Uncategorised', but since scores are always 1-5 across 9 named
--   conditions, this branch is a defensive fallback and should never fire)
-- =============================================================================

CREATE OR REPLACE VIEW warehouse.vw_rfm AS

WITH
-- ── Step 1: Delivered orders only ────────────────────────────────────────────
-- Exclude cancelled, unavailable, and in-progress orders.
-- Revenue = sum of price + freight per order line (total customer spend).
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

-- ── Step 2: Aggregate to customer level ───────────────────────────────────────
customer_metrics AS (
    SELECT
        customer_unique_id,
        -- Recency: days between last order and reference date
        DATE_PART('day',
            '2018-09-01'::TIMESTAMP - MAX(order_purchase_timestamp)
        )::INTEGER                          AS days_since_last_order,
        -- Frequency: number of distinct orders
        COUNT(DISTINCT order_id)            AS order_count,
        -- Monetary: total spend across all delivered orders
        ROUND(SUM(item_total)::NUMERIC, 2)  AS total_spend,
        -- Supporting metrics
        ROUND(AVG(item_total)::NUMERIC, 2)  AS avg_order_value,
        MIN(order_purchase_timestamp)::DATE AS first_order_date,
        MAX(order_purchase_timestamp)::DATE AS last_order_date
    FROM delivered_orders
    GROUP BY customer_unique_id
),

-- ── Step 3: Score each dimension 1–5 using NTILE ─────────────────────────────
-- Recency is inverted: fewer days since last order = higher score
rfm_scores AS (
    SELECT
        customer_unique_id,
        days_since_last_order,
        order_count,
        total_spend,
        avg_order_value,
        first_order_date,
        last_order_date,
        -- Recency: inverted so 5 = most recent
        6 - NTILE(5) OVER (ORDER BY days_since_last_order ASC)  AS r_score,
        -- Frequency: 5 = most frequent
        NTILE(5) OVER (ORDER BY order_count ASC)                AS f_score,
        -- Monetary: 5 = highest spend
        NTILE(5) OVER (ORDER BY total_spend ASC)                AS m_score
    FROM customer_metrics
),

-- ── Step 4: Combine scores and assign segment label ───────────────────────────
rfm_segments AS (
    SELECT
        customer_unique_id,
        days_since_last_order,
        order_count,
        total_spend,
        avg_order_value,
        first_order_date,
        last_order_date,
        r_score,
        f_score,
        m_score,
        -- Combined RFM score as a readable string e.g. '5-4-3'
        CONCAT(r_score, '-', f_score, '-', m_score) AS rfm_score,
        -- Composite numeric score (simple average, max = 5.0)
        ROUND((r_score + f_score + m_score) / 3.0, 2) AS rfm_composite,
        -- Segment label based on R and F scores
        CASE
            WHEN r_score = 5 AND f_score = 5                    THEN 'Champions'
            WHEN r_score = 1 AND f_score >= 4                   THEN 'Cannot Lose Them'
            WHEN f_score >= 4                                    THEN 'Loyal'
            WHEN r_score = 5 AND f_score = 1                    THEN 'Recent'
            WHEN r_score >= 4 AND f_score <= 2                  THEN 'Potential Loyal'
            WHEN r_score >= 3 AND f_score >= 3                  THEN 'Need Attention'
            WHEN r_score >= 3 AND f_score <= 2                  THEN 'Promising'
            WHEN r_score <= 2 AND f_score >= 3                  THEN 'At Risk'
            WHEN r_score <= 2 AND f_score <= 2                  THEN 'About to Sleep'
            ELSE                                                      'Uncategorised'
        END AS segment
    FROM rfm_scores
)

-- ── Final output ──────────────────────────────────────────────────────────────
SELECT
    customer_unique_id,
    r_score,
    f_score,
    m_score,
    rfm_score,
    rfm_composite,
    segment,
    days_since_last_order,
    order_count,
    total_spend,
    avg_order_value,
    first_order_date,
    last_order_date
FROM rfm_segments
ORDER BY rfm_composite DESC, total_spend DESC;
