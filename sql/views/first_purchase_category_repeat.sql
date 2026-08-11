-- =============================================================================
-- Marketplace Analytics Platform
-- View: warehouse.vw_first_purchase_category_repeat
-- Script: first_purchase_category_repeat.sql
-- Description: Each customer's first delivered order and the product
--              category of its highest-value line item ("first-purchase
--              category"). Used to test whether first-purchase category
--              predicts repeat-purchase behavior.
--
-- Grain: One row per customer_unique_id.
-- Source: Promoted from notebooks/05_customer_analysis.ipynb, Section 3.
--
-- Notes: Does NOT include order_count or repeat-purchase status — join to
--        warehouse.vw_rfm on customer_unique_id for that (order_count
--        column), rather than duplicating logic that view already owns.
--        Ties on price (item_rank) resolve arbitrarily via ROW_NUMBER(),
--        matching the original notebook behavior.
-- =============================================================================

CREATE OR REPLACE VIEW warehouse.vw_first_purchase_category_repeat AS

WITH
-- ── Step 1: Customer's first delivered order ─────────────────────────────────
first_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp,
        c.customer_state,
        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp
        ) AS order_rank
    FROM warehouse.dim_order o
    JOIN warehouse.dim_customer c
        ON o.customer_key = c.customer_key
    WHERE o.order_status = 'delivered'
),

-- ── Step 2: Highest-value line item category on that order ───────────────────
first_order_category AS (
    SELECT
        f.customer_unique_id,
        f.order_purchase_timestamp AS first_order_date,
        f.customer_state,
        p.product_category_name_english,
        ROW_NUMBER() OVER (
            PARTITION BY f.customer_unique_id
            ORDER BY i.price DESC
        ) AS item_rank
    FROM first_orders f
    JOIN warehouse.fact_order_items i
        ON f.order_id = i.order_id
    JOIN warehouse.dim_product p
        ON i.product_key = p.product_key
    WHERE f.order_rank = 1
)

-- ── Final output ─────────────────────────────────────────────────────────────
SELECT
    customer_unique_id,
    first_order_date,
    customer_state,
    COALESCE(product_category_name_english, 'uncategorised') AS first_category
FROM first_order_category
WHERE item_rank = 1
ORDER BY first_category, customer_unique_id;

