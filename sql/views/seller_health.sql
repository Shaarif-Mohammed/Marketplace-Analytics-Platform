-- =============================================================================
-- Marketplace Analytics Platform
-- View: warehouse.vw_seller_health
-- Script: seller_health.sql
-- Description: Two things unioned into one view, distinguished by
--              metric_type:
--                'Monthly Trend'   — new vs. returning sellers, revenue
--                                    contribution by seller type, each
--                                    month (unchanged from the original).
--                'Status Snapshot' — each individual seller's current
--                                    Active/Dormant/Inactive status,
--                                    newly surfaced (see change log).
--
-- Grain: Mixed, distinguished by metric_type — order_month x seller_type
--        for 'Monthly Trend' rows, one row per seller_id for
--        'Status Snapshot' rows. Same pattern already used in
--        vw_pareto_analysis (entity_type) and vw_delivery_experience
--        (dimension) — filter on metric_type per worksheet, same as
--        those views.
--
-- Definitions:
--   New seller       : first ever delivered order in that month
--   Returning seller : has at least one prior delivered order before this month
--   Active           : last delivered sale within the last 6 months
--                       (evaluated at dataset end date 2018-09-01, i.e.
--                       on/after 2018-03-01)
--   Dormant          : last delivered sale 6-12 months ago (on/after 2017-09-01)
--   Inactive         : last delivered sale more than 12 months ago
--   Never Active     : registered seller, zero delivered orders ever
--
-- This version keeps the monthly trend completely unchanged (it has no
-- equivalent in any other view, and directly backs the "seller revenue
-- flipped to returning-dominated by Feb 2017" finding in
-- docs/07_findings_sql.md) and adds the missing status classification —
-- using the same Active/Dormant threshold logic vw_customer_health uses —
-- as a second, unioned result set. Status Snapshot rows are seller-grain
-- specifically so this view can now relate to vw_seller_performance and
-- ml_seller_clusters on seller_id, which the original could not do.
--
-- Notes:
--   • Based on delivered orders only for the Monthly Trend rows
--   • seller_id grain for Status Snapshot rows (not seller_key)
--   • Status Snapshot covers all 3,095 registered sellers via LEFT JOIN
--     from dim_seller, including 125 who never made a delivered sale
--     ('Never Active'). An earlier version of this view scoped Status
--     Snapshot to only sellers with a delivered order (2,970), which
--     produced 72.59% Active instead of the documented 69.66% — caught
--     by validating against docs/07_findings_sql.md Finding 3 rather
--     than assumed correct. Fixed by including the full seller
--     population, matching how that 69.66% figure was actually computed.
--   • Month-over-month active seller growth tracked via LAG (unchanged)
-- =============================================================================

DROP VIEW IF EXISTS warehouse.vw_seller_health;

CREATE VIEW warehouse.vw_seller_health AS

WITH
-- ── Step 1: All delivered orders with seller and month ───────────────────────
delivered_sales AS (
    SELECT
        s.seller_id,
        s.seller_state,
        o.order_id,
        o.order_purchase_timestamp,
        DATE_TRUNC('month', o.order_purchase_timestamp)::DATE   AS order_month,
        i.price + i.freight_value                               AS order_value
    FROM warehouse.fact_order_items i
    JOIN warehouse.dim_order o
        ON i.order_key = o.order_key
    JOIN warehouse.dim_seller s
        ON i.seller_key = s.seller_key
    WHERE o.order_status = 'delivered'
),

-- ── Step 2: First active month per seller ────────────────────────────────────
seller_first_sale AS (
    SELECT
        seller_id,
        MIN(order_month) AS first_sale_month
    FROM delivered_sales
    GROUP BY seller_id
),

-- ── Step 3: Tag each month's activity as new or returning seller ─────────────
sales_tagged AS (
    SELECT
        d.seller_id,
        d.seller_state,
        d.order_id,
        d.order_month,
        d.order_value,
        CASE
            WHEN d.order_month = f.first_sale_month THEN 'New'
            ELSE 'Returning'
        END AS seller_type
    FROM delivered_sales d
    JOIN seller_first_sale f
        ON d.seller_id = f.seller_id
),

-- ── Step 4: Monthly aggregation by seller type ───────────────────────────────
monthly_by_type AS (
    SELECT
        order_month,
        seller_type,
        COUNT(DISTINCT seller_id)               AS seller_count,
        COUNT(DISTINCT order_id)                AS order_count,
        ROUND(SUM(order_value)::NUMERIC, 2)     AS total_revenue,
        ROUND(AVG(order_value)::NUMERIC, 2)     AS avg_order_value
    FROM sales_tagged
    GROUP BY order_month, seller_type
),

-- ── Step 5: Monthly totals across all seller types ───────────────────────────
monthly_totals AS (
    SELECT
        order_month,
        SUM(seller_count)                       AS total_active_sellers,
        SUM(order_count)                        AS total_orders,
        ROUND(SUM(total_revenue)::NUMERIC, 2)   AS total_revenue
    FROM monthly_by_type
    GROUP BY order_month
),

-- ── Step 6: Seller status at dataset end (2018-09-01) ────────────────────────
seller_last_sale AS (
    SELECT
        s.seller_id,
        MAX(ds.order_month)    AS last_sale_month,
        CASE
            WHEN MAX(ds.order_month) >= '2018-03-01' THEN 'Active'
            WHEN MAX(ds.order_month) >= '2017-09-01' THEN 'Dormant'
            WHEN MAX(ds.order_month) IS NULL THEN 'Never Active'
            ELSE 'Inactive'
        END AS seller_status
    FROM warehouse.dim_seller s
    LEFT JOIN delivered_sales ds
        ON s.seller_id = ds.seller_id
    GROUP BY s.seller_id
)

-- ── Final output: Monthly Trend rows UNION Status Snapshot rows ──────────────
SELECT
    'Monthly Trend'::VARCHAR                                   AS metric_type,
    mbt.order_month,
    mbt.seller_type,
    NULL::VARCHAR                                               AS seller_id,
    NULL::VARCHAR                                               AS seller_status,
    NULL::DATE                                                  AS last_sale_month,
    mbt.seller_count,
    mbt.order_count,
    mbt.total_revenue,
    mbt.avg_order_value,
    ROUND(
        mbt.total_revenue * 100.0 / NULLIF(mt.total_revenue, 0)
    , 2)                                                        AS revenue_share_pct,
    mt.total_active_sellers,
    mt.total_orders                                             AS total_monthly_orders,
    mt.total_revenue                                            AS total_monthly_revenue,
    LAG(mt.total_active_sellers) OVER (
        PARTITION BY mbt.seller_type
        ORDER BY mbt.order_month
    )                                                           AS prev_month_sellers,
    ROUND(
        (mt.total_active_sellers - LAG(mt.total_active_sellers) OVER (
            PARTITION BY mbt.seller_type
            ORDER BY mbt.order_month
        )) * 100.0 / NULLIF(LAG(mt.total_active_sellers) OVER (
            PARTITION BY mbt.seller_type
            ORDER BY mbt.order_month
        ), 0)
    , 2)                                                        AS mom_seller_growth_pct
FROM monthly_by_type mbt
JOIN monthly_totals mt
    ON mbt.order_month = mt.order_month

UNION ALL

SELECT
    'Status Snapshot'::VARCHAR                                  AS metric_type,
    NULL::DATE                                                  AS order_month,
    NULL::VARCHAR                                                AS seller_type,
    sls.seller_id,
    sls.seller_status,
    sls.last_sale_month,
    NULL::BIGINT                                                AS seller_count,
    NULL::BIGINT                                                AS order_count,
    NULL::NUMERIC                                                AS total_revenue,
    NULL::NUMERIC                                                AS avg_order_value,
    NULL::NUMERIC                                                AS revenue_share_pct,
    NULL::BIGINT                                                AS total_active_sellers,
    NULL::BIGINT                                                AS total_monthly_orders,
    NULL::NUMERIC                                                AS total_monthly_revenue,
    NULL::BIGINT                                                AS prev_month_sellers,
    NULL::NUMERIC                                                AS mom_seller_growth_pct
FROM seller_last_sale sls

ORDER BY metric_type, order_month, seller_type;
