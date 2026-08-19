-- =============================================================================
-- Marketplace Analytics Platform
-- View: warehouse.vw_seller_health
-- Script: seller_health.sql
-- Description: Two things unioned into one view, distinguished by
--              metric_type:
--                'Monthly Trend'   — new vs. returning sellers, revenue
--                                    contribution by seller type, each
--                                    month.
--                'Status Snapshot' — each individual seller's current
--                                    Active/Dormant/Inactive status.
--
-- Grain: Mixed, distinguished by metric_type — order_month x seller_type
--        for 'Monthly Trend' rows (now a COMPLETE grid, zero-filled where
--        a type had no sellers that month — see AUDIT FIX), one row per
--        seller_id for 'Status Snapshot' rows.
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
-- Notes:
--   • Based on delivered orders only for the Monthly Trend rows
--   • seller_id grain for Status Snapshot rows (not seller_key)
--   • Status Snapshot covers all 3,095 registered sellers via LEFT JOIN
--     from dim_seller, including 125 who never made a delivered sale
--     ('Never Active'). Confirmed on real data: 69.66% Active / 14.73%
--     Dormant / 11.57% Inactive / 4.04% Never Active — matches this
--     view's own documented Finding 3 figure exactly.
--   • Month-over-month active seller growth tracked via LAG, now
--     type-specific and gap-safe 
-- =============================================================================

DROP VIEW IF EXISTS warehouse.vw_seller_health;

CREATE VIEW warehouse.vw_seller_health AS

WITH
-- ── Step 1: All delivered order items with seller and month ─────────────────
delivered_items AS (
    SELECT
        s.seller_id,
        s.seller_state,
        i.order_id,
        o.order_purchase_timestamp,
        DATE_TRUNC('month', o.order_purchase_timestamp)::DATE   AS order_month,
        i.price + i.freight_value                               AS item_value
    FROM warehouse.fact_order_items i
    JOIN warehouse.dim_order o
        ON i.order_key = o.order_key
    JOIN warehouse.dim_seller s
        ON i.seller_key = s.seller_key
    WHERE o.order_status = 'delivered'
),

-- ── Step 1b: Collapse to (seller, order) grain — this seller's own share ────
-- of the order, correctly handling Olist's split-seller checkout where one
-- order can contain items from multiple sellers.
delivered_sales AS (
    SELECT
        seller_id,
        order_id,
        MAX(order_purchase_timestamp) AS order_purchase_timestamp,
        MAX(order_month)              AS order_month,
        SUM(item_value)               AS order_value
    FROM delivered_items
    GROUP BY seller_id, order_id
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

-- ── Step 4: Monthly aggregation by seller type (order grain) ────────────────
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

-- ── Step 4b: Complete (month x seller_type) grid, zero-filled ───────────────
-- Prevents LAG() from silently comparing non-adjacent calendar months when
-- a type had zero activity in a given month (e.g. Nov 2016, a genuine
-- zero-order month in the underlying dataset).
month_bounds AS (
    SELECT MIN(order_month) AS min_month, MAX(order_month) AS max_month
    FROM delivered_sales
),
month_grid AS (
    SELECT gs.month_start
    FROM month_bounds mb
    CROSS JOIN LATERAL generate_series(mb.min_month, mb.max_month, INTERVAL '1 month') AS gs(month_start)
),
type_grid AS (
    SELECT unnest(ARRAY['New','Returning']) AS seller_type
),
full_grid AS (
    SELECT mg.month_start::DATE AS order_month, tg.seller_type
    FROM month_grid mg
    CROSS JOIN type_grid tg
),
monthly_by_type_filled AS (
    SELECT
        fg.order_month,
        fg.seller_type,
        COALESCE(mbt.seller_count, 0)      AS seller_count,
        COALESCE(mbt.order_count, 0)       AS order_count,
        COALESCE(mbt.total_revenue, 0)     AS total_revenue,
        mbt.avg_order_value                AS avg_order_value
    FROM full_grid fg
    LEFT JOIN monthly_by_type mbt
        ON fg.order_month = mbt.order_month
        AND fg.seller_type = mbt.seller_type
),

-- ── Step 5: Monthly totals across all seller types (from the filled grid) ───
monthly_totals AS (
    SELECT
        order_month,
        SUM(seller_count)                       AS total_active_sellers,
        SUM(order_count)                        AS total_orders,
        ROUND(SUM(total_revenue)::NUMERIC, 2)   AS total_revenue
    FROM monthly_by_type_filled
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
    -- Type-specific previous month count, from the zero-filled grid, so
    -- gaps compare against a true zero rather than skipping the month
    LAG(mbt.seller_count) OVER (
        PARTITION BY mbt.seller_type
        ORDER BY mbt.order_month
    )                                                           AS prev_month_sellers,
    -- Type-specific month-over-month growth (was: cross-type total,
    -- duplicated onto both New and Returning rows — see AUDIT FIX)
    ROUND(
        (mbt.seller_count - LAG(mbt.seller_count) OVER (
            PARTITION BY mbt.seller_type
            ORDER BY mbt.order_month
        )) * 100.0 / NULLIF(LAG(mbt.seller_count) OVER (
            PARTITION BY mbt.seller_type
            ORDER BY mbt.order_month
        ), 0)
    , 2)                                                        AS mom_seller_growth_pct
FROM monthly_by_type_filled mbt
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
