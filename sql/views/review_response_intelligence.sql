-- =============================================================================
-- Marketplace Analytics Platform
-- View: warehouse.vw_review_response_intelligence
-- Script: review_response_intelligence.sql
-- Description: Review score distribution, response time analysis, and
--              category-level review intelligence. Answers three questions:
--              1. What does the score distribution look like overall?
--              2. Does Olist respond faster to negative reviews?
--              3. Which categories and sellers have the worst review profiles?
--
-- Grain: Four result sets unified via UNION ALL:
--   'Score Distribution' : one row per review_score (1-5)
--   'Response Time'      : one row per review_score — avg response time
--   'By Category'        : one row per product category
--   'By Score Band'      : Positive (4-5) vs Negative (1-2) vs Neutral (3)
--
-- Metrics:
--   Distribution  : count, % of total, cumulative %
--   Response time : avg hours between review creation and answer timestamp
--   Category      : avg score, % 1-star, % 5-star, total reviews
--   Score band    : grouped positive/neutral/negative analysis
--   Every dimension also reports reviews_with_comment/pct_with_comment and
--   reviews_with_response/pct_with_response, computed identically across
--   all four blocks — see AUDIT FIX note below.
--
-- Notes:
--   • review_comment_title and review_comment_message are stored but not
--     analysed here — NLP/sentiment reserved for future AI-layer project
--   • Response time = review_answer_timestamp - review_creation_date
--   • Some reviews have no answer timestamp — excluded from response time avg
--   • review_id grain used (not order_id) to avoid fan-out from
--     multi-item orders. COUNT(DISTINCT review_id) throughout.
--   • ROUND() requires ::NUMERIC cast — DATE_PART returns double precision
--     which is not supported by Postgres ROUND(double precision, integer)
--   • When an order spans multiple product categories, the review is
--     attributed to the category of that order's highest-value item
--     (price + freight_value)
-- =============================================================================

DROP VIEW IF EXISTS warehouse.vw_review_response_intelligence;

CREATE VIEW warehouse.vw_review_response_intelligence AS

WITH
-- ── Step 1: Base review data with category and item value ────────────────────
review_base AS (
    SELECT
        r.review_id,
        r.order_id,
        r.review_score,
        r.review_creation_date,
        r.review_answer_timestamp,
        -- Response time in hours — cast to NUMERIC for ROUND compatibility
        CASE
            WHEN r.review_answer_timestamp IS NOT NULL
            THEN ROUND(
                (DATE_PART('epoch',
                    r.review_answer_timestamp - r.review_creation_date
                ) / 3600.0)::NUMERIC
            , 1)
            ELSE NULL
        END                                             AS response_hours,
        -- Score band
        CASE
            WHEN r.review_score >= 4 THEN 'Positive (4-5)'
            WHEN r.review_score = 3  THEN 'Neutral (3)'
            ELSE                          'Negative (1-2)'
        END                                             AS score_band,
        -- Has comment
        CASE WHEN r.review_comment_message IS NOT NULL
            THEN TRUE ELSE FALSE
        END                                             AS has_comment,
        COALESCE(p.product_category_name_english, 'uncategorised') AS category,
        -- Item value, used only to pick the "primary" category when an
        -- order spans multiple categories (see Step 2)
        i.price + i.freight_value                       AS item_revenue
    FROM warehouse.fact_reviews r
    LEFT JOIN warehouse.fact_order_items i
        ON r.order_id = i.order_id
    LEFT JOIN warehouse.dim_product p
        ON i.product_key = p.product_key
),

-- ── Step 2: Deduplicate reviews (one row per review_id) ───────────────────────
-- Multi-item orders can produce duplicate review rows after joining to items.
-- Tie-break: keep the category of the order's highest-value item, not an
-- arbitrary alphabetical pick.
review_deduped AS (
    SELECT DISTINCT ON (review_id)
        review_id,
        order_id,
        review_score,
        review_creation_date,
        review_answer_timestamp,
        response_hours,
        score_band,
        has_comment,
        category
    FROM review_base
    ORDER BY review_id, item_revenue DESC NULLS LAST
),

-- ── Step 3a: Score distribution ───────────────────────────────────────────────
score_distribution AS (
    SELECT
        'Score Distribution'                            AS dimension,
        review_score::TEXT                              AS dimension_value,
        NULL::TEXT                                      AS sub_dimension,
        COUNT(DISTINCT review_id)                       AS review_count,
        ROUND(
            COUNT(DISTINCT review_id) * 100.0
            / SUM(COUNT(DISTINCT review_id)) OVER ()
        , 2)                                            AS pct_of_total,
        ROUND(
            SUM(COUNT(DISTINCT review_id)) OVER (
                ORDER BY review_score DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) * 100.0 / SUM(COUNT(DISTINCT review_id)) OVER ()
        , 2)                                            AS cumulative_pct,
        ROUND(AVG(response_hours)::NUMERIC, 1)         AS avg_response_hours,
        SUM(CASE WHEN has_comment THEN 1 ELSE 0 END)   AS reviews_with_comment,
        ROUND(
            SUM(CASE WHEN has_comment THEN 1 ELSE 0 END) * 100.0
            / COUNT(DISTINCT review_id)
        , 2)                                            AS pct_with_comment,
        COUNT(CASE WHEN response_hours IS NOT NULL
            THEN 1 END)                                 AS reviews_with_response,
        ROUND(
            COUNT(CASE WHEN response_hours IS NOT NULL THEN 1 END) * 100.0
            / COUNT(DISTINCT review_id)
        , 2)                                            AS pct_with_response,
        NULL::NUMERIC                                   AS avg_review_score,
        NULL::NUMERIC                                   AS pct_5_star,
        NULL::NUMERIC                                   AS pct_1_star
    FROM review_deduped
    GROUP BY review_score
),

-- ── Step 3b: Response time by score ──────────────────────────────────────────
response_time AS (
    SELECT
        'Response Time'                                 AS dimension,
        review_score::TEXT                              AS dimension_value,
        NULL::TEXT                                      AS sub_dimension,
        COUNT(DISTINCT review_id)                       AS review_count,
        NULL::NUMERIC                                   AS pct_of_total,
        NULL::NUMERIC                                   AS cumulative_pct,
        ROUND(AVG(response_hours)::NUMERIC, 1)         AS avg_response_hours,
        SUM(CASE WHEN has_comment THEN 1 ELSE 0 END)   AS reviews_with_comment,
        ROUND(
            SUM(CASE WHEN has_comment THEN 1 ELSE 0 END) * 100.0
            / COUNT(DISTINCT review_id)
        , 2)                                            AS pct_with_comment,
        COUNT(CASE WHEN response_hours IS NOT NULL
            THEN 1 END)                                 AS reviews_with_response,
        ROUND(
            COUNT(CASE WHEN response_hours IS NOT NULL THEN 1 END) * 100.0
            / COUNT(DISTINCT review_id)
        , 2)                                            AS pct_with_response,
        NULL::NUMERIC                                   AS avg_review_score,
        NULL::NUMERIC                                   AS pct_5_star,
        NULL::NUMERIC                                   AS pct_1_star
    FROM review_deduped
    GROUP BY review_score
),

-- ── Step 3c: Score band summary ───────────────────────────────────────────────
score_band_summary AS (
    SELECT
        'By Score Band'                                 AS dimension,
        score_band                                      AS dimension_value,
        NULL::TEXT                                      AS sub_dimension,
        COUNT(DISTINCT review_id)                       AS review_count,
        ROUND(
            COUNT(DISTINCT review_id) * 100.0
            / SUM(COUNT(DISTINCT review_id)) OVER ()
        , 2)                                            AS pct_of_total,
        NULL::NUMERIC                                   AS cumulative_pct,
        ROUND(AVG(response_hours)::NUMERIC, 1)         AS avg_response_hours,
        SUM(CASE WHEN has_comment THEN 1 ELSE 0 END)   AS reviews_with_comment,
        ROUND(
            SUM(CASE WHEN has_comment THEN 1 ELSE 0 END) * 100.0
            / COUNT(DISTINCT review_id)
        , 2)                                            AS pct_with_comment,
        COUNT(CASE WHEN response_hours IS NOT NULL
            THEN 1 END)                                 AS reviews_with_response,
        ROUND(
            COUNT(CASE WHEN response_hours IS NOT NULL THEN 1 END) * 100.0
            / COUNT(DISTINCT review_id)
        , 2)                                            AS pct_with_response,
        ROUND(AVG(review_score::NUMERIC), 2)           AS avg_review_score,
        NULL::NUMERIC                                   AS pct_5_star,
        NULL::NUMERIC                                   AS pct_1_star
    FROM review_deduped
    GROUP BY score_band
),

-- ── Step 3d: By product category ─────────────────────────────────────────────
by_category AS (
    SELECT
        'By Category'                                   AS dimension,
        category                                        AS dimension_value,
        NULL::TEXT                                      AS sub_dimension,
        COUNT(DISTINCT review_id)                       AS review_count,
        NULL::NUMERIC                                   AS pct_of_total,
        NULL::NUMERIC                                   AS cumulative_pct,
        ROUND(AVG(response_hours)::NUMERIC, 1)         AS avg_response_hours,
        SUM(CASE WHEN has_comment THEN 1 ELSE 0 END)   AS reviews_with_comment,
        ROUND(
            SUM(CASE WHEN has_comment THEN 1 ELSE 0 END) * 100.0
            / COUNT(DISTINCT review_id)
        , 2)                                            AS pct_with_comment,
        COUNT(CASE WHEN response_hours IS NOT NULL
            THEN 1 END)                                 AS reviews_with_response,
        ROUND(
            COUNT(CASE WHEN response_hours IS NOT NULL THEN 1 END) * 100.0
            / COUNT(DISTINCT review_id)
        , 2)                                            AS pct_with_response,
        ROUND(AVG(review_score::NUMERIC), 2)           AS avg_review_score,
        ROUND(
            SUM(CASE WHEN review_score = 5 THEN 1 ELSE 0 END) * 100.0
            / COUNT(DISTINCT review_id)
        , 2)                                            AS pct_5_star,
        ROUND(
            SUM(CASE WHEN review_score = 1 THEN 1 ELSE 0 END) * 100.0
            / COUNT(DISTINCT review_id)
        , 2)                                            AS pct_1_star
    FROM review_deduped
    GROUP BY category
)

-- ── Final output ──────────────────────────────────────────────────────────────
SELECT * FROM score_distribution
UNION ALL
SELECT * FROM response_time
UNION ALL
SELECT * FROM score_band_summary
UNION ALL
SELECT * FROM by_category
ORDER BY dimension, review_count DESC;
