-- =============================================================================
-- Marketplace Analytics Platform
-- Script: 01_create_staging_tables.sql
-- Schema: staging
-- Description: Creates all 9 staging tables — one per raw source CSV file.
--              Staging tables are a raw landing zone: no foreign keys, no
--              surrogate keys, permissive data types. All transformation,
--              cleaning, and surrogate key resolution happens in the warehouse
--              layer (02_create_warehouse_tables.sql).
-- Run order: Run AFTER 00_create_schemas.sql and BEFORE 02_create_warehouse_tables.sql.
-- Usage: Run against the Marketplace-Analytics-Platform database.
--        psql -U postgres -d Marketplace-Analytics-Platform -f 01_create_staging_tables.sql
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Drop existing staging tables if they exist (safe re-run)
-- Order matters: no FK constraints here so any order is fine
-- -----------------------------------------------------------------------------

DROP TABLE IF EXISTS staging.stg_category_translation;
DROP TABLE IF EXISTS staging.stg_geolocation;
DROP TABLE IF EXISTS staging.stg_sellers;
DROP TABLE IF EXISTS staging.stg_products;
DROP TABLE IF EXISTS staging.stg_reviews;
DROP TABLE IF EXISTS staging.stg_payments;
DROP TABLE IF EXISTS staging.stg_order_items;
DROP TABLE IF EXISTS staging.stg_customers;
DROP TABLE IF EXISTS staging.stg_orders;


-- -----------------------------------------------------------------------------
-- stg_orders
-- Source: olist_orders_dataset.csv
-- One row per order. Contains order status and all lifecycle timestamps.
-- -----------------------------------------------------------------------------

CREATE TABLE staging.stg_orders (
    order_id                        TEXT,
    customer_id                     TEXT,
    order_status                    TEXT,
    order_purchase_timestamp        TIMESTAMP,
    order_approved_at               TIMESTAMP,
    order_delivered_carrier_date    TIMESTAMP,
    order_delivered_customer_date   TIMESTAMP,
    order_estimated_delivery_date   TIMESTAMP
);


-- -----------------------------------------------------------------------------
-- stg_customers
-- Source: olist_customers_dataset.csv
-- One row per customer_id (order-scoped). Contains both customer_id and
-- customer_unique_id — the true person-level identifier.
-- -----------------------------------------------------------------------------

CREATE TABLE staging.stg_customers (
    customer_id                 TEXT,
    customer_unique_id          TEXT,
    customer_zip_code_prefix    TEXT,
    customer_city               TEXT,
    customer_state              TEXT
);


-- -----------------------------------------------------------------------------
-- stg_order_items
-- Source: olist_order_items_dataset.csv
-- One row per order line item. Primary revenue source.
-- -----------------------------------------------------------------------------

CREATE TABLE staging.stg_order_items (
    order_id                TEXT,
    order_item_id           INTEGER,
    product_id              TEXT,
    seller_id               TEXT,
    shipping_limit_date     TIMESTAMP,
    price                   NUMERIC(10, 2),
    freight_value           NUMERIC(10, 2)
);


-- -----------------------------------------------------------------------------
-- stg_payments
-- Source: olist_order_payments_dataset.csv
-- One row per payment record. Multiple rows per order for installments
-- or split payment types.
-- -----------------------------------------------------------------------------

CREATE TABLE staging.stg_payments (
    order_id                TEXT,
    payment_sequential      INTEGER,
    payment_type            TEXT,
    payment_installments    INTEGER,
    payment_value           NUMERIC(10, 2)
);


-- -----------------------------------------------------------------------------
-- stg_reviews
-- Source: olist_order_reviews_dataset.csv
-- One row per review record. review_id is not strictly unique — 814 review_ids
-- are fanned out across multiple order_ids due to split-seller checkout behavior.
-- -----------------------------------------------------------------------------

CREATE TABLE staging.stg_reviews (
    review_id                   TEXT,
    order_id                    TEXT,
    review_score                INTEGER,
    review_comment_title        TEXT,
    review_comment_message      TEXT,
    review_creation_date        TIMESTAMP,
    review_answer_timestamp     TIMESTAMP
);


-- -----------------------------------------------------------------------------
-- stg_products
-- Source: olist_products_dataset.csv
-- One row per product. Note: source CSV has typos in two column names
-- (product_name_lenght, product_description_lenght) — corrected here.
-- English category name is not in the source file; it is resolved at
-- warehouse load time via stg_category_translation.
-- -----------------------------------------------------------------------------

CREATE TABLE staging.stg_products (
    product_id                      TEXT,
    product_category_name           TEXT,
    product_name_length             INTEGER,    -- corrected from 'product_name_lenght' in source
    product_description_length      INTEGER,    -- corrected from 'product_description_lenght' in source
    product_photos_qty              INTEGER,
    product_weight_g                NUMERIC(10, 2),
    product_length_cm               NUMERIC(10, 2),
    product_height_cm               NUMERIC(10, 2),
    product_width_cm                NUMERIC(10, 2)
);


-- -----------------------------------------------------------------------------
-- stg_sellers
-- Source: olist_sellers_dataset.csv
-- One row per seller.
-- -----------------------------------------------------------------------------

CREATE TABLE staging.stg_sellers (
    seller_id               TEXT,
    seller_zip_code_prefix  TEXT,
    seller_city             TEXT,
    seller_state            TEXT
);


-- -----------------------------------------------------------------------------
-- stg_geolocation
-- Source: olist_geolocation_dataset.csv
-- Raw file has 1,000,163 rows with 261,831 exact duplicate rows and multiple
-- lat/lng entries per zip code prefix. This staging table loads the raw file
-- as-is. Deduplication to one row per zip_code_prefix (avg lat/lng) and
-- exclusion of 31 out-of-bounds coordinates happens at warehouse load time.
-- -----------------------------------------------------------------------------

CREATE TABLE staging.stg_geolocation (
    zip_code_prefix     TEXT,
    lat                 NUMERIC(9, 6),
    lng                 NUMERIC(9, 6),
    city                TEXT,
    state               TEXT
);


-- -----------------------------------------------------------------------------
-- stg_category_translation
-- Source: product_category_name_translation.csv
-- Lookup table mapping Portuguese category names to English.
-- 71 rows in source. Two categories missing from this file
-- (pc_gamer, portateis_cozinha_e_preparadores_de_alimentos) are manually
-- mapped at warehouse load time.
-- -----------------------------------------------------------------------------

CREATE TABLE staging.stg_category_translation (
    product_category_name           TEXT,
    product_category_name_english   TEXT
);


-- =============================================================================
-- End of script
