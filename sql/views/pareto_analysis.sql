-- =============================================================================
-- Marketplace Analytics Platform
-- View: warehouse.vw_pareto_analysis
-- Script: pareto_analysis.sql
-- Description: Cumulative revenue concentration analysis at both customer
--              and seller level. Tests the 80/20 rule — what share of
--              customers and sellers drive 80% of revenue.
--
-- Grain: Two result sets unified via UNION ALL:
--        - One row per customer_unique_id (entity_type = 'Customer')
--        - One row per seller_id          (entity_type = 'Seller')
--
-- Metrics per entity:
--   total_revenue         : lifetime revenue from delivered orders
--   revenue_rank          : ranked 1 = highest revenue
--   revenue_pct_of_total  : this entity's share of total revenue
--   cumulative_revenue_pct: running total — used to identify 80/20 threshold
--   cumulative_pct_of_entities: what % of entities have been counted so far
--
-- Usage in Tableau:
--   Filter entity_type = 'Customer' or 'Seller' separately.
--   Plot cumulative_pct_of_entities (x) vs cumulative_revenue_pct (y).
--   Draw reference lines at x=20, y=80 to show the 80/20 intersection.
--
-- Notes:
--   • Delivered orders only
--   • Revenue = price + freight_value
--   • Customers with zero delivered orders excluded (not in dim_order)
--   • Sellers with zero delivered orders excluded
-- =============================================================================

CREATE OR REPLACE VIEW warehouse.vw_pareto_analysis AS

WITH
-- ── Customer revenue totals ───────────────────────────────────────────────────
customer_revenue AS (
    SELECT
        c.customer_unique_id                            AS entity_id,
        'Customer'                                      AS entity_type,
        ROUND(SUM(i.price + i.freight_value)::NUMERIC, 2) AS total_revenue,
        COUNT(DISTINCT o.order_id)                      AS total_orders
    FROM warehouse.dim_order o
    JOIN warehouse.dim_customer c
        ON o.customer_key = c.customer_key
    JOIN warehouse.fact_order_items i
        ON o.order_id = i.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),

-- ── Seller revenue totals ─────────────────────────────────────────────────────
seller_revenue AS (
    SELECT
        s.seller_id                                     AS entity_id,
        'Seller'                                        AS entity_type,
        ROUND(SUM(i.price + i.freight_value)::NUMERIC, 2) AS total_revenue,
        COUNT(DISTINCT o.order_id)                      AS total_orders
    FROM warehouse.fact_order_items i
    JOIN warehouse.dim_order o
        ON i.order_key = o.order_key
    JOIN warehouse.dim_seller s
        ON i.seller_key = s.seller_key
    WHERE o.order_status = 'delivered'
    GROUP BY s.seller_id
),

-- ── Combine both entity types ─────────────────────────────────────────────────
combined AS (
    SELECT * FROM customer_revenue
    UNION ALL
    SELECT * FROM seller_revenue
),

-- ── Total revenue per entity type (for share calculation) ─────────────────────
entity_totals AS (
    SELECT
        entity_type,
        SUM(total_revenue)      AS grand_total_revenue,
        COUNT(*)                AS total_entities
    FROM combined
    GROUP BY entity_type
),

-- ── Rank entities by revenue and calculate cumulative metrics ─────────────────
ranked AS (
    SELECT
        c.entity_id,
        c.entity_type,
        c.total_revenue,
        c.total_orders,
        et.grand_total_revenue,
        et.total_entities,
        -- Rank 1 = highest revenue
        RANK() OVER (
            PARTITION BY c.entity_type
            ORDER BY c.total_revenue DESC
        )                                               AS revenue_rank,
        -- This entity's share of total revenue
        ROUND(
            c.total_revenue * 100.0 / et.grand_total_revenue
        , 4)                                            AS revenue_pct_of_total,
        -- Cumulative revenue percentage (running total from highest to lowest)
        ROUND(
            SUM(c.total_revenue) OVER (
                PARTITION BY c.entity_type
                ORDER BY c.total_revenue DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) * 100.0 / et.grand_total_revenue
        , 2)                                            AS cumulative_revenue_pct,
        -- What % of all entities have been counted so far
        ROUND(
            RANK() OVER (
                PARTITION BY c.entity_type
                ORDER BY c.total_revenue DESC
            ) * 100.0 / et.total_entities
        , 2)                                            AS cumulative_pct_of_entities
    FROM combined c
    JOIN entity_totals et
        ON c.entity_type = et.entity_type
)

-- ── Final output ──────────────────────────────────────────────────────────────
SELECT
    entity_type,
    entity_id,
    total_revenue,
    total_orders,
    revenue_rank,
    revenue_pct_of_total,
    cumulative_revenue_pct,
    cumulative_pct_of_entities,
    grand_total_revenue,
    total_entities,
    -- Flag entities that fall within the top 20% by count
    CASE WHEN cumulative_pct_of_entities <= 20 THEN TRUE ELSE FALSE END
        AS is_top_20_pct,
    -- Flag entities needed to reach 80% cumulative revenue
    CASE WHEN cumulative_revenue_pct <= 80 THEN TRUE ELSE FALSE END
        AS is_within_80_pct_revenue
FROM ranked
ORDER BY entity_type, revenue_rank;
