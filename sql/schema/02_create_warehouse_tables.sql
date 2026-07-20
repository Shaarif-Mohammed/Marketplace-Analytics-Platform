-- =============================================================================
-- Marketplace Analytics Platform
-- Script: 02_create_warehouse_tables.sql
-- Schema: warehouse
-- Description: Creates all 9 warehouse tables — 6 dimension tables and 3 fact
--              tables. Tables use surrogate integer keys (SERIAL) as primary
--              keys with natural business keys retained as regular columns.
--              Foreign key constraints and indexes are applied at this layer.
-- Run order: Run AFTER 00_create_schemas.sql and 01_create_staging_tables.sql.
-- Usage: Run against the Marketplace-Analytics-Platform database.
--        psql -U postgres -d Marketplace-Analytics-Platform -f 02_create_warehouse_tables.sql
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Drop existing warehouse tables if they exist (safe re-run)
-- Order matters: fact tables must be dropped before dimension tables
-- they reference via foreign keys
-- -----------------------------------------------------------------------------

DROP TABLE IF EXISTS warehouse.fact_reviews;
DROP TABLE IF EXISTS warehouse.fact_payments;
DROP TABLE IF EXISTS warehouse.fact_order_items;
DROP TABLE IF EXISTS warehouse.dim_order;
DROP TABLE IF EXISTS warehouse.dim_product;
DROP TABLE IF EXISTS warehouse.dim_seller;
DROP TABLE IF EXISTS warehouse.dim_customer;
DROP TABLE IF EXISTS warehouse.dim_geolocation;
DROP TABLE IF EXISTS warehouse.dim_date;


-- -----------------------------------------------------------------------------
-- dim_date
-- Generated programmatically in ETL — not loaded from a source CSV.
-- Spans 2016-01-01 to 2019-12-31 to cover the full dataset range with buffer.
-- No foreign key dependencies.
-- -----------------------------------------------------------------------------

CREATE TABLE warehouse.dim_date (
    date_key        INTEGER         PRIMARY KEY,    -- YYYYMMDD format e.g. 20170315
    full_date       DATE            NOT NULL UNIQUE,
    day             SMALLINT        NOT NULL,
    month           SMALLINT        NOT NULL,
    month_name      VARCHAR(20)     NOT NULL,
    quarter         SMALLINT        NOT NULL,
    year            SMALLINT        NOT NULL,
    week_of_year    SMALLINT        NOT NULL,
    weekday_name    VARCHAR(20)     NOT NULL,
    is_weekend      BOOLEAN         NOT NULL
);


-- -----------------------------------------------------------------------------
-- dim_geolocation
-- One row per zip code prefix. Deduplicated from 1,000,163 raw rows using
-- average lat/lng per prefix. 31 out-of-bounds coordinates excluded before
-- averaging. No foreign key dependencies.
-- -----------------------------------------------------------------------------

CREATE TABLE warehouse.dim_geolocation (
    geolocation_key     SERIAL          PRIMARY KEY,
    zip_code_prefix     VARCHAR(10)     NOT NULL UNIQUE,
    avg_lat             NUMERIC(9, 6)   NOT NULL,
    avg_lng             NUMERIC(9, 6)   NOT NULL,
    city                VARCHAR(100),
    state               CHAR(2)
);


-- -----------------------------------------------------------------------------
-- dim_customer
-- One row per customer_id (order-scoped). Both customer_id and
-- customer_unique_id are retained — customer_id is the join key to dim_order,
-- customer_unique_id is the true person identifier for all analytics.
-- Depends on: dim_geolocation
-- -----------------------------------------------------------------------------

CREATE TABLE warehouse.dim_customer (
    customer_key            SERIAL          PRIMARY KEY,
    customer_id             VARCHAR(64)     NOT NULL UNIQUE,
    customer_unique_id      VARCHAR(64)     NOT NULL,
    customer_zip_code_prefix VARCHAR(10),
    customer_city           VARCHAR(100),
    customer_state          CHAR(2),
    geolocation_key         INTEGER         REFERENCES warehouse.dim_geolocation(geolocation_key)
);

-- Index on customer_unique_id — used in every customer-level analytical query
CREATE INDEX idx_dim_customer_unique_id
    ON warehouse.dim_customer (customer_unique_id);

-- Index on geolocation_key — used in geographic joins
CREATE INDEX idx_dim_customer_geolocation_key
    ON warehouse.dim_customer (geolocation_key);


-- -----------------------------------------------------------------------------
-- dim_seller
-- One row per seller. Depends on: dim_geolocation
-- -----------------------------------------------------------------------------

CREATE TABLE warehouse.dim_seller (
    seller_key              SERIAL          PRIMARY KEY,
    seller_id               VARCHAR(64)     NOT NULL UNIQUE,
    seller_zip_code_prefix  VARCHAR(10),
    seller_city             VARCHAR(100),
    seller_state            CHAR(2),
    geolocation_key         INTEGER         REFERENCES warehouse.dim_geolocation(geolocation_key)
);

-- Index on geolocation_key — used in geographic joins
CREATE INDEX idx_dim_seller_geolocation_key
    ON warehouse.dim_seller (geolocation_key);


-- -----------------------------------------------------------------------------
-- dim_product
-- One row per product. English category name resolved at ETL time via join
-- to stg_category_translation — no downstream join to translation table needed.
-- Source CSV typos (product_name_lenght, product_description_lenght) corrected.
-- No foreign key dependencies.
-- -----------------------------------------------------------------------------

CREATE TABLE warehouse.dim_product (
    product_key                     SERIAL          PRIMARY KEY,
    product_id                      VARCHAR(64)     NOT NULL UNIQUE,
    product_category_name           VARCHAR(100),
    product_category_name_english   VARCHAR(100),
    product_name_length             INTEGER,
    product_description_length      INTEGER,
    product_photos_qty              INTEGER,
    product_weight_g                NUMERIC(10, 2), -- 4 rows with value 0 nulled out at ETL time
    product_length_cm               NUMERIC(10, 2),
    product_height_cm               NUMERIC(10, 2),
    product_width_cm                NUMERIC(10, 2)
);


-- -----------------------------------------------------------------------------
-- dim_order
-- One row per order. Carries all order-level attributes — status and all
-- lifecycle timestamps. Kept as a separate dimension rather than denormalized
-- onto fact_order_items to replicate enterprise warehouse design practice.
-- Depends on: dim_customer, dim_date
-- -----------------------------------------------------------------------------

CREATE TABLE warehouse.dim_order (
    order_key                       SERIAL          PRIMARY KEY,
    order_id                        VARCHAR(64)     NOT NULL UNIQUE,
    customer_key                    INTEGER         NOT NULL REFERENCES warehouse.dim_customer(customer_key),
    purchase_date_key               INTEGER         REFERENCES warehouse.dim_date(date_key),
    order_status                    VARCHAR(20)     NOT NULL,
    order_purchase_timestamp        TIMESTAMP       NOT NULL,
    order_approved_at               TIMESTAMP,                  -- null for 160 orders (never approved)
    order_delivered_carrier_date    TIMESTAMP,                  -- null for 1,783 orders
    order_delivered_customer_date   TIMESTAMP,                  -- null for 2,965 orders
    order_estimated_delivery_date   TIMESTAMP
);

-- Index on order_id — primary join key from all three fact tables
CREATE INDEX idx_dim_order_order_id
    ON warehouse.dim_order (order_id);

-- Index on customer_key — used in customer-level aggregations
CREATE INDEX idx_dim_order_customer_key
    ON warehouse.dim_order (customer_key);

-- Index on purchase_date_key — used in time-series and cohort analysis
CREATE INDEX idx_dim_order_purchase_date_key
    ON warehouse.dim_order (purchase_date_key);

-- Index on order_status — used in status-based filtering
CREATE INDEX idx_dim_order_status
    ON warehouse.dim_order (order_status);


-- -----------------------------------------------------------------------------
-- fact_order_items
-- Primary fact table. One row per order line item — lowest grain in warehouse.
-- Contains all item-level measures (price, freight) and foreign keys to all
-- relevant dimensions. Joins to fact_payments and fact_reviews via order_id.
-- Depends on: dim_order, dim_seller, dim_product
-- -----------------------------------------------------------------------------

CREATE TABLE warehouse.fact_order_items (
    order_item_key      SERIAL          PRIMARY KEY,
    order_id            VARCHAR(64)     NOT NULL,   -- degenerate dimension — join key to fact_payments and fact_reviews
    order_item_id       SMALLINT        NOT NULL,
    order_key           INTEGER         NOT NULL REFERENCES warehouse.dim_order(order_key),
    seller_key          INTEGER         NOT NULL REFERENCES warehouse.dim_seller(seller_key),
    product_key         INTEGER         NOT NULL REFERENCES warehouse.dim_product(product_key),
    price               NUMERIC(10, 2)  NOT NULL,
    freight_value       NUMERIC(10, 2)  NOT NULL,
    shipping_limit_date TIMESTAMP,                  -- 4 outlier rows with 2020 dates nulled at ETL time
    UNIQUE (order_id, order_item_id)
);

-- Index on order_id — primary cross-fact join key
CREATE INDEX idx_fact_order_items_order_id
    ON warehouse.fact_order_items (order_id);

-- Index on order_key — used in joins to dim_order
CREATE INDEX idx_fact_order_items_order_key
    ON warehouse.fact_order_items (order_key);

-- Index on seller_key — used in seller performance analysis
CREATE INDEX idx_fact_order_items_seller_key
    ON warehouse.fact_order_items (seller_key);

-- Index on product_key — used in product and category analysis
CREATE INDEX idx_fact_order_items_product_key
    ON warehouse.fact_order_items (product_key);


-- -----------------------------------------------------------------------------
-- fact_payments
-- One row per payment record at installment sequence grain. Kept separate from
-- fact_order_items to avoid fan-out — multiple payment rows per order would
-- multiply item rows if joined directly. Joins to warehouse via order_id.
-- No surrogate key foreign keys — cross-fact joins use order_id (degenerate).
-- -----------------------------------------------------------------------------

CREATE TABLE warehouse.fact_payments (
    payment_key             SERIAL          PRIMARY KEY,
    order_id                VARCHAR(64)     NOT NULL,
    payment_sequential      SMALLINT        NOT NULL,
    payment_type            VARCHAR(20)     NOT NULL,
    payment_installments    SMALLINT        NOT NULL,   -- 2 rows with value 0 set to 1 at ETL time
    payment_value           NUMERIC(10, 2)  NOT NULL,
    UNIQUE (order_id, payment_sequential)
);

-- Index on order_id — primary cross-fact join key
CREATE INDEX idx_fact_payments_order_id
    ON warehouse.fact_payments (order_id);

-- Index on payment_type — used in payment behaviour analysis
CREATE INDEX idx_fact_payments_payment_type
    ON warehouse.fact_payments (payment_type);


-- -----------------------------------------------------------------------------
-- fact_reviews
-- One row per review record. Kept separate from fact_order_items to avoid
-- fan-out — 814 review_ids are fanned out across multiple order_ids due to
-- Olist's split-seller checkout behavior. Always use COUNT(DISTINCT review_id)
-- when counting reviews — row count overcounts by approximately 1,600.
-- No surrogate key foreign keys — cross-fact joins use order_id (degenerate).
-- -----------------------------------------------------------------------------

CREATE TABLE warehouse.fact_reviews (
    review_key              SERIAL          PRIMARY KEY,
    review_id               VARCHAR(64)     NOT NULL,
    order_id                VARCHAR(64)     NOT NULL,
    review_score            SMALLINT        NOT NULL,
    review_comment_title    TEXT,                       -- null in 88% of records (optional field)
    review_comment_message  TEXT,                       -- null in 59% of records (optional field)
    review_creation_date    TIMESTAMP,
    review_answer_timestamp TIMESTAMP
);

-- Index on order_id — primary cross-fact join key
CREATE INDEX idx_fact_reviews_order_id
    ON warehouse.fact_reviews (order_id);

-- Index on review_score — used in seller and product review analysis
CREATE INDEX idx_fact_reviews_review_score
    ON warehouse.fact_reviews (review_score);


-- =============================================================================
-- End of script
