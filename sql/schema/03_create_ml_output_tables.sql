-- =============================================================================
-- Marketplace Analytics Platform
-- Script: 03_create_ml_output_tables.sql
-- Location: sql/schema/
-- Description: Table definitions for materialized ML outputs (Bucket C) —
--              seller clustering, seller outlier flags, category clustering,
--              and review-score feature importance. Populated by
--              python/etl/03_materialize_ml_outputs.py, NOT by SQL. These are
--              static snapshots, not live views — they go stale if the
--              warehouse is reloaded and this script is not re-run.
--
-- Naming: All tables use the `ml_` prefix (not `vw_`) to signal at a glance
--         that they are script-refreshed, not query-time-live like the
--         `vw_` views in warehouse.
--
-- Usage: Run once to create tables. 03_materialize_ml_outputs.py TRUNCATEs and
--        re-populates them on every run — this script only needs re-running
--        if a table's structure changes.
-- =============================================================================


-- =============================================================================
-- Table: warehouse.ml_seller_clusters
-- Source: notebooks/06_seller_analysis.ipynb, Section 2 (K-Means, k=2)
-- Grain: One row per scored seller (total_orders >= 5, matching SQL's
--        performance_tier scoring population).
-- =============================================================================

DROP TABLE IF EXISTS warehouse.ml_seller_clusters CASCADE;

CREATE TABLE warehouse.ml_seller_clusters (
    seller_id         VARCHAR NOT NULL PRIMARY KEY,
    cluster_label     SMALLINT NOT NULL,               -- raw KMeans label (0/1) — not stable across reruns, use cluster_name instead
    cluster_name      VARCHAR NOT NULL,                -- 'Elite' / 'Non-Elite' — assigned post-hoc by avg_review_score rank, stable across reruns
    performance_tier  VARCHAR,                         -- carried over from vw_seller_performance for the tier-vs-cluster comparison worksheet
    avg_review_score  NUMERIC,
    on_time_rate      NUMERIC,
    total_revenue     NUMERIC,
    cancellation_rate NUMERIC,
    total_orders      INTEGER,
    silhouette_k      SMALLINT,                        -- k chosen by silhouette score on this run (expected: 2)
    computed_at       TIMESTAMP NOT NULL               -- when this run produced the row — these values go stale, unlike a live view
);

COMMENT ON TABLE warehouse.ml_seller_clusters IS
    'Static K-means output (k selected by silhouette score). Elite maps ~98% onto Cluster 0; manual "Strong" tier splits across both clusters.';


-- =============================================================================
-- Table: warehouse.ml_seller_outliers
-- Source: notebooks/06_seller_analysis.ipynb, Section 4 (relaxed threshold
--         revenue_z > 0.5 AND quality_z < -0.5, within the same scored
--         population as ml_seller_clusters). The strict 1.0/1.0 threshold
--         found zero sellers on the source data — relaxed is the
--         operationally useful cut.
-- Grain: One row per flagged near-outlier seller (expected: ~10 rows).
-- =============================================================================

DROP TABLE IF EXISTS warehouse.ml_seller_outliers CASCADE;

CREATE TABLE warehouse.ml_seller_outliers (
    seller_id         VARCHAR NOT NULL PRIMARY KEY,
    seller_state      CHAR(2),
    total_orders      INTEGER,
    total_revenue     NUMERIC,
    avg_review_score  NUMERIC,
    on_time_rate      NUMERIC,
    cancellation_rate NUMERIC,
    revenue_z         NUMERIC,                         -- z-score of total_revenue within the scored population
    quality_z         NUMERIC,                         -- composite z-score: (review_z + on_time_z - cancellation_z) / 3
    computed_at       TIMESTAMP NOT NULL
);

COMMENT ON TABLE warehouse.ml_seller_outliers IS
    'Sellers with above-average revenue AND below-average quality (relaxed z-score threshold 0.5/-0.5). Individual account-management flags, not a bulk tier.';


-- =============================================================================
-- Table: warehouse.ml_category_clusters
-- Source: notebooks/08_product_analysis.ipynb, Section 6 (K-Means, k=4)
-- Grain: One row per product category (expected: 74 rows, matching
--        vw_product_customer_affinity).
-- =============================================================================

DROP TABLE IF EXISTS warehouse.ml_category_clusters CASCADE;

CREATE TABLE warehouse.ml_category_clusters (
    category                 VARCHAR NOT NULL PRIMARY KEY,
    cluster_label            SMALLINT NOT NULL,               -- raw KMeans label (0-3) — not stable across reruns, use cluster_name instead
    cluster_name             VARCHAR NOT NULL,                -- 'Revenue Core' / 'Trouble Spot' / 'Small & Well-Reviewed' / 'Small & Sticky' — assigned post-hoc, stable across reruns
    total_revenue            NUMERIC,
    avg_review_score         NUMERIC,
    freight_pct_of_revenue   NUMERIC,
    category_repeat_rate_pct NUMERIC,
    silhouette_k             SMALLINT,                        -- k chosen by silhouette score on this run (expected: 4)
    computed_at              TIMESTAMP NOT NULL
);

COMMENT ON TABLE warehouse.ml_category_clusters IS
    'Static K-means output on revenue/review/freight/repeat-rate. Revenue-driving categories and loyalty-driving categories are almost entirely different sets.';


-- =============================================================================
-- Table: warehouse.ml_review_score_feature_importance
-- Source: notebooks/08_product_analysis.ipynb, Section 2 (Random Forest
--         Regressor predicting review_score from delivery days, freight %,
--         category, state, payment type)
-- Grain: One row per feature group (expected: 5 rows — delivery_days,
--        freight_pct, category, state, payment_type). Importances sum to 1.0
--        across all rows for a given computed_at run.
-- =============================================================================

DROP TABLE IF EXISTS warehouse.ml_review_score_feature_importance CASCADE;

CREATE TABLE warehouse.ml_review_score_feature_importance (
    feature_group  VARCHAR NOT NULL PRIMARY KEY,
    importance     NUMERIC NOT NULL,                -- raw importance, sums to ~1.0 across all rows in a run
    importance_pct NUMERIC NOT NULL,                -- importance * 100, rounded — convenience column for Tableau labels
    train_r2       NUMERIC,                         -- model-level metadata, repeated on every row (small table, denormalization is harmless here)
    test_r2        NUMERIC,
    computed_at    TIMESTAMP NOT NULL
);

COMMENT ON TABLE warehouse.ml_review_score_feature_importance IS
    'Random Forest feature importance for review_score. delivery_days dominates at ~81% — the single strongest, most consistent finding across the whole Python analysis.';
