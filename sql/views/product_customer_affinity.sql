-- =============================================================================
-- Marketplace Analytics Platform
-- View: warehouse.vw_product_customer_affinity
-- Script: product_customer_affinity.sql
-- Description: Product category performance analysis linking revenue,
--              volume, customer profile, and review scores at category level.
--              Identifies which categories drive the most value and how
--              customer satisfaction varies by category.
--
-- Grain: One row per product_category_name_english.
--
-- Metrics:
--   Revenue         : total and average order value by category
--   Volume          : order count, item count, unique customers
--   Customer profile: avg CLV of customers who buy in this category,
--                     repeat purchase rate within category
--   Review          : avg score, % 5-star, % 1-star by category
--   Geography       : top customer state by order volume
--   Delivery        : avg delivery days for category orders
--
-- Notes:
--   • Delivered orders only
--   • Categories with NULL English name grouped as 'uncategorised'
--   • Revenue = price + freight_value (total customer spend)
--   • Repeat purchase rate = customers with 2+ orders in the category
--     / total unique customers in the category
-- =============================================================================

CREATE OR REPLACE VIEW warehouse.vw_product_customer_affinity AS

WITH
-- ── Step 1: Base — delivered order items with category and customer ────────────
base AS (
    SELECT
        COALESCE(p.product_category_name_english, 'uncategorised') AS category,
        p.product_id,
        i.order_id,
        i.order_item_id,
        c.customer_unique_id,
        c.customer_state,
        o.order_purchase_timestamp,
        o.order_delivered_customer_date,
        i.price,
        i.freight_value,
        i.price + i.freight_value                                   AS item_revenue
    FROM warehouse.fact_order_items i
    JOIN warehouse.dim_order o
        ON i.order_key = o.order_key
    JOIN warehouse.dim_product p
        ON i.product_key = p.product_key
    JOIN warehouse.dim_customer c
        ON o.customer_key = c.customer_key
    WHERE o.order_status = 'delivered'
),

-- ── Step 2: Revenue and volume metrics per category ───────────────────────────
category_revenue AS (
    SELECT
        category,
        COUNT(DISTINCT order_id)                        AS total_orders,
        COUNT(*)                                        AS total_items,
        COUNT(DISTINCT product_id)                      AS unique_products,
        COUNT(DISTINCT customer_unique_id)              AS unique_customers,
        ROUND(SUM(item_revenue)::NUMERIC, 2)            AS total_revenue,
        ROUND(AVG(item_revenue)::NUMERIC, 2)            AS avg_item_value,
        ROUND(SUM(price)::NUMERIC, 2)                   AS total_product_revenue,
        ROUND(SUM(freight_value)::NUMERIC, 2)           AS total_freight_revenue,
        -- Freight as % of total revenue (high = expensive to ship)
        ROUND(
            SUM(freight_value) * 100.0 / NULLIF(SUM(item_revenue), 0)
        , 2)                                            AS freight_pct_of_revenue,
        -- Avg delivery days for this category
        ROUND(AVG(
            DATE_PART('day',
                order_delivered_customer_date - order_purchase_timestamp
            )
        )::NUMERIC, 1)                                  AS avg_delivery_days
    FROM base
    GROUP BY category
),

-- ── Step 3: Review metrics per category ──────────────────────────────────────
category_reviews AS (
    SELECT
        COALESCE(p.product_category_name_english, 'uncategorised') AS category,
        ROUND(AVG(r.review_score)::NUMERIC, 2)          AS avg_review_score,
        COUNT(DISTINCT r.review_id)                     AS total_reviews,
        ROUND(
            SUM(CASE WHEN r.review_score = 5 THEN 1 ELSE 0 END)
            * 100.0 / COUNT(DISTINCT r.review_id)
        , 2)                                            AS pct_5_star,
        ROUND(
            SUM(CASE WHEN r.review_score = 1 THEN 1 ELSE 0 END)
            * 100.0 / COUNT(DISTINCT r.review_id)
        , 2)                                            AS pct_1_star
    FROM warehouse.fact_order_items i
    JOIN warehouse.dim_product p
        ON i.product_key = p.product_key
    JOIN warehouse.fact_reviews r
        ON i.order_id = r.order_id
    JOIN warehouse.dim_order o
        ON i.order_key = o.order_key
    WHERE o.order_status = 'delivered'
    GROUP BY COALESCE(p.product_category_name_english, 'uncategorised')
),

-- ── Step 4: Repeat purchase rate within category ──────────────────────────────
-- Customers who placed 2+ orders containing this category
category_repeat AS (
    SELECT
        category,
        COUNT(DISTINCT customer_unique_id)              AS customers_with_repeat,
        COUNT(DISTINCT CASE WHEN order_count >= 2
            THEN customer_unique_id END)                AS repeat_customers
    FROM (
        SELECT
            category,
            customer_unique_id,
            COUNT(DISTINCT order_id) AS order_count
        FROM base
        GROUP BY category, customer_unique_id
    ) cust_orders
    GROUP BY category
),

-- ── Step 5: Top customer state per category ───────────────────────────────────
category_top_state AS (
    SELECT DISTINCT ON (category)
        category,
        customer_state                                  AS top_customer_state,
        COUNT(DISTINCT order_id)                        AS top_state_orders
    FROM base
    GROUP BY category, customer_state
    ORDER BY category, COUNT(DISTINCT order_id) DESC
),

-- ── Step 6: Revenue share of total ───────────────────────────────────────────
total_revenue AS (
    SELECT SUM(total_revenue) AS grand_total
    FROM category_revenue
)

-- ── Final output ──────────────────────────────────────────────────────────────
SELECT
    cr.category,
    cr.total_orders,
    cr.total_items,
    cr.unique_products,
    cr.unique_customers,
    cr.total_revenue,
    cr.avg_item_value,
    cr.total_product_revenue,
    cr.total_freight_revenue,
    cr.freight_pct_of_revenue,
    cr.avg_delivery_days,
    -- Revenue share
    ROUND(cr.total_revenue * 100.0 / tr.grand_total, 2) AS revenue_share_pct,
    -- Cumulative revenue share (ranked by revenue)
    ROUND(
        SUM(cr.total_revenue) OVER (
            ORDER BY cr.total_revenue DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) * 100.0 / tr.grand_total
    , 2)                                                AS cumulative_revenue_pct,
    -- Review metrics
    rv.avg_review_score,
    rv.total_reviews,
    rv.pct_5_star,
    rv.pct_1_star,
    -- Repeat purchase within category
    rep.customers_with_repeat,
    rep.repeat_customers,
    ROUND(
        rep.repeat_customers * 100.0
        / NULLIF(rep.customers_with_repeat, 0)
    , 2)                                                AS category_repeat_rate_pct,
    -- Top customer state
    ts.top_customer_state,
    ts.top_state_orders,
    -- Revenue tier
    CASE
        WHEN ROUND(cr.total_revenue * 100.0 / tr.grand_total, 2) >= 5
            THEN 'High Revenue'
        WHEN ROUND(cr.total_revenue * 100.0 / tr.grand_total, 2) >= 1
            THEN 'Mid Revenue'
        ELSE
            'Long Tail'
    END                                                 AS revenue_tier
FROM category_revenue cr
CROSS JOIN total_revenue tr
LEFT JOIN category_reviews rv   ON cr.category = rv.category
LEFT JOIN category_repeat rep   ON cr.category = rep.category
LEFT JOIN category_top_state ts ON cr.category = ts.category
ORDER BY cr.total_revenue DESC;
