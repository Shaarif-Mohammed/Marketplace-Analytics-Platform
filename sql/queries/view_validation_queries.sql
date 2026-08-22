-- =============================================================================
-- Marketplace Analytics Platform
-- Script: view_validation_queries.sql
-- Location: sql/queries/
-- Description: Sanity check queries for all 13 analytical views in the
--              warehouse schema. Run these after creating or recreating
--              any view to confirm it is returning expected results.
--
-- Usage: Run in pgAdmin against the Marketplace-Analytics-Platform database.
--        Each section is self-contained — run individually or all at once.
--        Expected results documented inline for each check.
-- =============================================================================


-- =============================================================================
-- 1. vw_rfm — RFM Segmentation
-- =============================================================================

-- Segment distribution — Champions should be 3-8%, Loyal largest segment
SELECT
    segment,
    COUNT(*)                                              AS customer_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)  AS pct,
    ROUND(AVG(total_spend), 2)                           AS avg_spend,
    ROUND(AVG(order_count), 2)                           AS avg_orders
FROM warehouse.vw_rfm
GROUP BY segment
ORDER BY avg_spend DESC;

-- Expected: 9 segments, Champions ~4%, avg_spend decreasing down the list
-- Expected: Most customers avg_orders close to 1.0 (one-time buyer platform)
-- Expected: Uncategorised segment should never appear (defensive fallback only)


-- =============================================================================
-- 2. vw_clv — Customer Lifetime Value
-- =============================================================================

-- CLV tier x RFM segment distribution
SELECT
    clv_tier,
    rfm_segment,
    COUNT(*)                            AS customer_count,
    ROUND(AVG(historical_clv), 2)       AS avg_historical_clv,
    ROUND(AVG(projected_clv_12m), 2)    AS avg_projected_clv,
    ROUND(AVG(order_count), 2)          AS avg_orders,
    ROUND(AVG(lifespan_days), 1)        AS avg_lifespan_days
FROM warehouse.vw_clv
GROUP BY clv_tier, rfm_segment
ORDER BY avg_projected_clv DESC
LIMIT 15;

-- Expected: Champions should lead High tier with highest projected CLV (~429 BRL)
-- Expected: One-time buyers show projected_clv = avg_order_value (no rate projection)
-- Expected: Total row count = 93,358 (unique customers with delivered orders)

SELECT COUNT(*) AS total_customers FROM warehouse.vw_clv;


-- =============================================================================
-- 3. vw_retention — Cohort Retention
-- =============================================================================

-- Check 1: Period 0 must always be 100%
SELECT cohort_month, cohort_size, retained_customers, retention_rate_pct
FROM warehouse.vw_retention
WHERE period_number = 0
ORDER BY cohort_month;

-- Expected: All rows show retention_rate_pct = 100.00
-- Expected: 23 cohorts (Sep 2016 to Aug 2018, minus Nov 2016)
-- Expected: November 2016 absent from period 0 (genuine zero-order month)

-- Check 2: Period-level summary — use SUM not AVG to avoid small-cohort inflation
-- AVG(retention_rate_pct) is misleading because tiny cohorts (e.g. Dec 2016: 1 customer,
-- 100% retention) get equal weight to large cohorts. Weighted calculation is correct.
SELECT
    period_number,
    SUM(cohort_size)                                        AS total_cohort_customers,
    SUM(retained_customers)                                 AS total_retained,
    ROUND(
        SUM(retained_customers) * 100.0 / SUM(cohort_size)
    , 2)                                                    AS weighted_retention_pct,
    COUNT(DISTINCT cohort_month)                            AS cohorts_in_period
FROM warehouse.vw_retention
GROUP BY period_number
ORDER BY period_number;

-- Expected: Period 1 weighted retention ~0.45% — all individual cohorts under 1%
-- Expected: Period 2+ also sub-1%, confirming retention never recovers
-- Expected: Cohorts in period decreases as period increases (right-censoring)
-- Expected: Zero-retention periods appear as explicit rows (not absent)

-- Check 3: Platform-wide weighted period-1 retention (single headline number)
SELECT
    ROUND(
        SUM(CASE WHEN period_number = 1 THEN retained_customers ELSE 0 END) * 100.0
        / SUM(CASE WHEN period_number = 0 THEN cohort_size ELSE 0 END)
    , 2) AS weighted_period_1_retention_pct
FROM warehouse.vw_retention;

-- Expected: ~0.45%
-- NOTE: AVG(retention_rate_pct) WHERE period_number = 1 gives ~4.96% — this is WRONG.
-- The Dec 2016 cohort (1 customer, 100% retention) inflates the simple average.
-- Always use the weighted calculation above for a platform-wide retention figure.


-- =============================================================================
-- 4. vw_seller_performance — Seller Scorecard
-- =============================================================================

-- Check 1: on_time_rate must never exceed 100%
SELECT
    MIN(on_time_rate)   AS min_rate,
    MAX(on_time_rate)   AS max_rate,
    AVG(on_time_rate)   AS avg_rate,
    COUNT(*) FILTER (WHERE on_time_rate > 100) AS above_100
FROM warehouse.vw_seller_performance
WHERE performance_tier != 'Insufficient Data';

-- Expected: max_rate = 100.00, above_100 = 0

-- Check 2: Tier distribution
SELECT
    performance_tier,
    COUNT(*)                            AS seller_count,
    ROUND(AVG(total_orders), 1)         AS avg_orders,
    ROUND(AVG(total_revenue), 2)        AS avg_revenue,
    ROUND(AVG(avg_review_score), 2)     AS avg_review_score,
    ROUND(AVG(on_time_rate), 2)         AS avg_on_time_rate,
    ROUND(AVG(cancellation_rate), 2)    AS avg_cancellation_rate,
    ROUND(AVG(performance_score), 2)    AS avg_performance_score
FROM warehouse.vw_seller_performance
GROUP BY performance_tier
ORDER BY avg_performance_score DESC NULLS LAST;

-- Expected: Elite (1,404 sellers, ~78% of scored) has highest review score (~4.27), on-time rate (~94.30%)
-- Expected: Strong (374 sellers), Average (15 sellers), Needs Work (1 seller)
-- Expected: Insufficient Data (1,301 sellers) = largest single group
-- Expected: Total seller count = 3,095 (matches dim_seller)

SELECT COUNT(*) AS total_sellers FROM warehouse.vw_seller_performance;


-- =============================================================================
-- 5. vw_regional_analysis — Geographic Revenue
-- =============================================================================

SELECT
    state,
    unique_customers,
    total_orders,
    total_revenue,
    revenue_share_pct,
    cumulative_revenue_pct,
    avg_delivery_days,
    on_time_rate,
    avg_review_score,
    total_sellers,
    orders_per_seller
FROM warehouse.vw_regional_analysis
ORDER BY total_revenue DESC;

-- Expected: 27 rows (26 states + DF)
-- Expected: SP first with ~37% revenue share
-- Expected: Top 3 states (SP, RJ, MG) account for ~63% cumulative revenue
-- Expected: Northern states (AM, AP, RR) show longest avg_delivery_days
-- Expected: States with 0 sellers show NULL orders_per_seller

SELECT COUNT(*) AS total_states FROM warehouse.vw_regional_analysis;


-- =============================================================================
-- 6. vw_customer_health — Customer Status Snapshot
-- =============================================================================

-- Status distribution at dataset end (2018-09-01)
SELECT
    customer_status,
    COUNT(*)                                              AS customer_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)  AS pct
FROM warehouse.vw_customer_health
GROUP BY customer_status
ORDER BY customer_count DESC;

-- Expected: Active ~41%, Dormant ~36%, Lost ~23%
-- Expected: Total = 93,358 (one row per customer with at least one delivered order)

SELECT COUNT(*) AS total_customers FROM warehouse.vw_customer_health;

-- Sample rows — confirm grain is one row per customer_unique_id
SELECT customer_unique_id, last_order_month, customer_status
FROM warehouse.vw_customer_health
LIMIT 5;


-- =============================================================================
-- 7. vw_seller_health — Seller Base Health
-- =============================================================================

-- Monthly trend — new vs returning sellers
-- Filter to Monthly Trend rows only (view has two grains via metric_type)
SELECT
    order_month,
    seller_type,
    seller_count,
    total_revenue,
    revenue_share_pct,
    total_active_sellers
FROM warehouse.vw_seller_health
WHERE metric_type = 'Monthly Trend'
ORDER BY order_month, seller_type;

-- Expected: Returning sellers dominate revenue from Feb 2017 onward (63%+)
-- Expected: Active seller count grows from 1 (Sep 2016) to ~1,261 (Aug 2018)
-- Expected: November 2016 appears as zero rows (complete month grid)

-- Status snapshot — one row per seller including Never Active sellers
SELECT
    seller_status,
    COUNT(*)                                              AS seller_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)  AS pct
FROM warehouse.vw_seller_health
WHERE metric_type = 'Status Snapshot'
GROUP BY seller_status
ORDER BY seller_count DESC;

-- Expected: Active ~70%, Dormant ~15%, Inactive ~12%, Never Active ~4%
-- Expected: Total = 3,095 (all registered sellers including those never active)

SELECT COUNT(*) AS total_sellers_snapshot
FROM warehouse.vw_seller_health
WHERE metric_type = 'Status Snapshot';


-- =============================================================================
-- 8. vw_new_vs_returning_revenue — Revenue Mix
-- =============================================================================

SELECT
    order_month,
    new_customers,
    returning_customers,
    new_revenue,
    returning_revenue,
    total_revenue,
    new_revenue_pct,
    returning_revenue_pct,
    returning_revenue_mom_growth_pct,
    returning_pct_3m_rolling_avg
FROM warehouse.vw_new_vs_returning_revenue
ORDER BY order_month;

-- Expected: 24 rows (Sep 2016 to Aug 2018 — complete calendar month grid)
-- Expected: November 2016 appears as a zero row (total_revenue = 0)
-- Expected: new_revenue_pct starts at 100%, trends down to ~97%
-- Expected: returning_pct_3m_rolling_avg shows gentle upward trend
-- Expected: June 2018 peak returning revenue share (~2.98%)

SELECT COUNT(*) AS total_months FROM warehouse.vw_new_vs_returning_revenue;


-- =============================================================================
-- 9. vw_pareto_analysis — Revenue Concentration
-- =============================================================================

SELECT
    entity_type,
    MAX(total_entities)                                             AS total_entities,
    COUNT(*) FILTER (WHERE is_within_80_pct_revenue)               AS entities_driving_80pct_revenue,
    ROUND(
        COUNT(*) FILTER (WHERE is_within_80_pct_revenue)
        * 100.0 / MAX(total_entities)
    , 2)                                                            AS pct_of_entities_driving_80pct,
    ROUND(
        SUM(total_revenue) FILTER (WHERE is_top_20_pct)
        * 100.0 / MAX(grand_total_revenue)
    , 2)                                                            AS top_20pct_revenue_share,
    ROUND(MAX(grand_total_revenue), 2)                             AS grand_total_revenue
FROM warehouse.vw_pareto_analysis
GROUP BY entity_type
ORDER BY entity_type;

-- Expected: Customer — ~49% of customers drive 80% of revenue (flatter than 80/20)
-- Expected: Seller — ~19% of sellers drive 80% of revenue (tighter than 80/20)
-- Expected: grand_total_revenue identical for both entity types (~15.4M BRL)


-- =============================================================================
-- 10. vw_delivery_experience — Delivery Performance
-- =============================================================================

-- National summary
SELECT * FROM warehouse.vw_delivery_experience
WHERE dimension = 'Overall';

-- Expected: avg_delivery_days ~12.1, median ~10, on_time_rate ~91.9%
-- Expected: early_delivery_rate ~88.8% (Olist under-promises on estimates)
-- Expected: avg_review_on_time ~4.29, avg_review_late ~2.57 (1.72 point gap)

-- State breakdown (sorted by delivery time)
SELECT * FROM warehouse.vw_delivery_experience
WHERE dimension = 'By State'
ORDER BY avg_delivery_days DESC;

-- Expected: 27 rows, RR/AP slowest (~27-29 days), SP fastest (~8 days)

-- On-time vs late comparison
SELECT * FROM warehouse.vw_delivery_experience
WHERE dimension = 'On-time vs Late';

-- Expected: On-Time avg 10.4 days, Late avg 31.1 days
-- Expected: On-Time review 4.29, Late review 2.57


-- =============================================================================
-- 11. vw_product_customer_affinity — Category Performance
-- =============================================================================

SELECT
    category,
    total_orders,
    unique_customers,
    total_revenue,
    revenue_share_pct,
    cumulative_revenue_pct,
    avg_item_value,
    freight_pct_of_revenue,
    avg_review_score,
    pct_5_star,
    pct_1_star,
    category_repeat_rate_pct,
    avg_delivery_days,
    top_customer_state,
    revenue_tier
FROM warehouse.vw_product_customer_affinity
ORDER BY total_revenue DESC;

-- Expected: 74 rows (71 translated + 2 manual + 1 uncategorised)
-- Expected: health_beauty #1 by revenue (~9.16%)
-- Expected: SP dominates as top_customer_state for most categories
-- Expected: office_furniture has lowest avg_review_score in high-volume categories (~3.64)
-- Expected: computers category has highest avg_item_value (~1,147 BRL)

SELECT COUNT(*) AS total_categories FROM warehouse.vw_product_customer_affinity;


-- =============================================================================
-- 12. vw_payment_behaviour — Payment Patterns
-- =============================================================================

-- Payment type summary
SELECT dimension_value, order_count, avg_payment_value,
       avg_instalments, pct_single_instalment, pct_of_orders, pct_of_revenue
FROM warehouse.vw_payment_behaviour
WHERE dimension = 'By Payment Type'
ORDER BY pct_of_orders DESC;

-- Expected: credit_card ~76.93% of orders, boleto ~19.90%, voucher ~1.6%, debit_card ~1.5%
-- Expected: boleto, voucher, debit_card always 100% single instalment
-- Expected: credit_card avg instalments ~3.51

-- Instalment band distribution
SELECT dimension_value, order_count, avg_payment_value,
       avg_order_item_total, pct_of_orders
FROM warehouse.vw_payment_behaviour
WHERE dimension = 'By Instalment Band'
ORDER BY dimension_value;

-- Expected: Single instalment ~48.5% of orders
-- Expected: avg_order_item_total increases with each instalment band
-- Expected: 1 instalment ~129 BRL → 7-12 instalments ~343 BRL

-- Cross: credit card by instalment band
SELECT dimension_value, sub_dimension, order_count,
       avg_payment_value, avg_order_item_total, pct_of_orders
FROM warehouse.vw_payment_behaviour
WHERE dimension = 'Cross' AND dimension_value = 'credit_card'
ORDER BY sub_dimension;

-- Expected: 5 rows (one per instalment band)
-- Expected: 12+ instalment band is entirely credit card


-- =============================================================================
-- 13. vw_review_response_intelligence — Review Intelligence
-- =============================================================================

-- Score distribution
SELECT dimension_value AS score, review_count, pct_of_total,
       cumulative_pct, avg_response_hours, pct_with_comment
FROM warehouse.vw_review_response_intelligence
WHERE dimension = 'Score Distribution'
ORDER BY dimension_value DESC;

-- Expected: 5 rows, 5-star ~57.8%, 1-star ~11.5%
-- Expected: 1-star has highest pct_with_comment (~76.6%)
-- Expected: 5-star has lowest pct_with_comment (~35.9%)

-- Response time by score
SELECT dimension_value AS score, review_count, avg_response_hours
FROM warehouse.vw_review_response_intelligence
WHERE dimension = 'Response Time'
ORDER BY dimension_value DESC;

-- Expected: Response time nearly identical across scores (71-77 hours)
-- Expected: Olist does NOT prioritise faster response to negative reviews

-- Score band summary
SELECT dimension_value, review_count, pct_of_total,
       avg_response_hours, pct_with_comment
FROM warehouse.vw_review_response_intelligence
WHERE dimension = 'By Score Band'
ORDER BY review_count DESC;

-- Expected: Positive (4-5) ~77%, Negative (1-2) ~15%, Neutral (3) ~8%

-- Worst reviewed categories
SELECT dimension_value AS category, review_count, avg_review_score,
       pct_5_star, pct_1_star, avg_response_hours
FROM warehouse.vw_review_response_intelligence
WHERE dimension = 'By Category'
ORDER BY avg_review_score ASC
LIMIT 10;

-- Expected: office_furniture, uncategorised, home_comfort categories in bottom 10
-- Expected: office_furniture ~3.64 avg with ~17.2% 1-star


-- =============================================================================
-- End of validation queries
-- =============================================================================
