"""
Marketplace Analytics Platform
Script: 03_materialize_ml_outputs.py
Location: python/etl/

Description:
    Reproduces the four Bucket-C ML outputs from notebooks/06_seller_analysis.ipynb
    and notebooks/08_product_analysis.ipynb, and writes them back to the
    `warehouse` schema as static tables (see sql/schema/03_create_ml_output_tables.sql
    for DDL — run that once before the first execution of this script).

    These are NOT views. Unlike the 13 `vw_*` views, which are always
    live/current, these tables are snapshots as of the last time this script
    ran. If the warehouse is reloaded with new data, re-run this script to
    refresh them — otherwise Tableau dashboards reading from these tables
    will silently show stale results.

Outputs (all in the `warehouse` schema):
    - ml_seller_clusters                 (K-Means, k=2, seller quality split)
    - ml_seller_outliers                 (high-revenue / low-quality flags)
    - ml_category_clusters               (K-Means, k=4, category groupings)
    - ml_review_score_feature_importance (Random Forest driver analysis)

Usage:
    python python/etl/03_materialize_ml_outputs.py

Requires (beyond the conda env): scikit-learn, scipy — already used
in notebooks 06 and 08, not newly introduced here.

Shared utils (python/utils/) used here, and why:
    - db_connection.get_engine() — used. Matches the exact convention every
      notebook already uses (plain engine + explicit `warehouse.` schema
      prefixes in every query), not the schema-scoped get_warehouse_engine(),
      to stay consistent with notebooks 05-08 rather than introduce a second
      connection style.
    - imports.py — NOT imported wholesale (`from imports import *`). That
      module sets up matplotlib/seaborn theming and IPython.display for
      notebook output — irrelevant overhead for a headless script, and
      matplotlib's import chain is worth avoiding in a script that may
      eventually run on a schedule or in CI. Only its `scipy.stats` usage
      pattern is followed below (`from scipy import stats`, not
      `from scipy.stats import zscore`), for stylistic consistency.
    - load_data.py — NOT used. It loads raw CSVs from data/raw/; this
      script never touches raw CSVs, only the already-populated warehouse.
    - date_conversion.py — NOT used. It converts CSV-sourced date strings to
      datetime; Postgres TIMESTAMP columns already come back as proper
      datetime64 dtype via pd.read_sql(), so there's nothing to convert.
"""

import sys
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats
from sklearn.cluster import KMeans
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import r2_score, silhouette_score
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sqlalchemy import text

# Confirmed against the real repo layout (python/utils/load_data.py resolves
# DATA_DIR via parents[2], i.e. utils/ sits directly under python/ — same
# level as etl/, so parents[1] from this script lands on python/, and
# parents[1] / "utils" is correct).
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "utils"))
from db_connection import get_engine  # noqa: E402


RANDOM_STATE = 42
K_RANGE = range(2, 9)


# =============================================================================
# Shared helpers
# =============================================================================

def _best_k_by_silhouette(X_scaled, k_range=K_RANGE):
    """Runs KMeans across k_range, returns (best_k, fitted_labels_for_best_k)."""
    best_k, best_score, best_labels = None, -1.0, None
    for k in k_range:
        km = KMeans(n_clusters=k, random_state=RANDOM_STATE, n_init=10)
        labels = km.fit_predict(X_scaled)
        score = silhouette_score(X_scaled, labels)
        if score > best_score:
            best_k, best_score, best_labels = k, score, labels
    return best_k, best_labels


def _load_scored_sellers(engine):
    """Sellers with >=5 orders — same population SQL uses for performance_tier
    scoring (see vw_seller_performance). Shared by seller clustering and
    seller outlier detection so both operate on an identical population."""
    seller_performance = pd.read_sql(
        "SELECT * FROM warehouse.vw_seller_performance", engine
    )
    scored = seller_performance[seller_performance["total_orders"] >= 5].copy()
    return scored


def _truncate_and_load(engine, table_name, df):
    """TRUNCATEs the target table then appends df — preserves the DDL-defined
    structure/comments/PK rather than pandas to_sql(if_exists='replace'),
    which would drop and recreate the table from scratch."""
    with engine.begin() as conn:
        conn.execute(text(f"TRUNCATE TABLE warehouse.{table_name}"))
    df.to_sql(table_name, engine, schema="warehouse", if_exists="append", index=False)
    print(f"  -> wrote {len(df)} rows to warehouse.{table_name}")


# =============================================================================
# 1. Seller clusters (notebooks/06_seller_analysis.ipynb, Section 2)
# =============================================================================

def materialize_seller_clusters(engine, run_ts):
    print("\n[1/4] Seller clusters (K-Means)...")
    scored_sellers = _load_scored_sellers(engine)

    features = ["avg_review_score", "on_time_rate", "total_revenue", "cancellation_rate"]
    X = scored_sellers[features].copy()
    X["total_revenue"] = np.log1p(X["total_revenue"])  # heavily right-skewed

    X_scaled = StandardScaler().fit_transform(X)
    best_k, labels = _best_k_by_silhouette(X_scaled)
    scored_sellers["cluster_label"] = labels

    # Cluster naming is post-hoc and rank-based (NOT the raw integer label,
    # which KMeans assigns arbitrarily) so it stays stable across reruns:
    # the cluster with the higher avg review score is 'Elite'.
    cluster_quality = scored_sellers.groupby("cluster_label")["avg_review_score"].mean()
    elite_label = cluster_quality.idxmax()
    scored_sellers["cluster_name"] = np.where(
        scored_sellers["cluster_label"] == elite_label, "Elite", "Non-Elite"
    )

    out = scored_sellers[
        ["seller_id", "cluster_label", "cluster_name", "performance_tier"]
        + features
        + ["total_orders"]
    ].copy()
    out["silhouette_k"] = best_k
    out["computed_at"] = run_ts

    print(f"  best k = {best_k} (expected: 2)")
    print(f"  cluster sizes: {scored_sellers['cluster_name'].value_counts().to_dict()}")
    _truncate_and_load(engine, "ml_seller_clusters", out)


# =============================================================================
# 2. Seller outliers (notebooks/06_seller_analysis.ipynb, Section 4)
# =============================================================================

def materialize_seller_outliers(engine, run_ts):
    print("\n[2/4] Seller outliers (z-score, relaxed threshold)...")
    scored_sellers = _load_scored_sellers(engine)

    z = scored_sellers.copy()
    z["revenue_z"] = stats.zscore(z["total_revenue"])
    z["review_z"] = stats.zscore(z["avg_review_score"])
    z["on_time_z"] = stats.zscore(z["on_time_rate"])
    z["cancellation_z"] = stats.zscore(z["cancellation_rate"])
    z["quality_z"] = (z["review_z"] + z["on_time_z"] - z["cancellation_z"]) / 3

    # Strict threshold (1.0/1.0) found zero sellers on the source data — the
    # relaxed threshold (0.5/0.5) is the operationally useful cut and matches
    # what notebooks/06_seller_analysis.ipynb actually flags.
    threshold = 0.5
    outliers = z[
        (z["revenue_z"] > threshold) & (z["quality_z"] < -threshold)
    ].sort_values("total_revenue", ascending=False)

    out = outliers[
        ["seller_id", "seller_state", "total_orders", "total_revenue",
         "avg_review_score", "on_time_rate", "cancellation_rate",
         "revenue_z", "quality_z"]
    ].copy()
    out["computed_at"] = run_ts

    print(f"  {len(out)} near-outliers flagged (expected: ~10)")
    _truncate_and_load(engine, "ml_seller_outliers", out)


# =============================================================================
# 3. Category clusters (notebooks/08_product_analysis.ipynb, Section 6)
# =============================================================================

def materialize_category_clusters(engine, run_ts):
    print("\n[3/4] Category clusters (K-Means)...")
    product_affinity = pd.read_sql(
        "SELECT * FROM warehouse.vw_product_customer_affinity", engine
    )

    features = ["total_revenue", "avg_review_score", "freight_pct_of_revenue",
                "category_repeat_rate_pct"]
    X = product_affinity[features].copy()
    X["total_revenue"] = np.log1p(X["total_revenue"])

    X_scaled = StandardScaler().fit_transform(X)
    best_k, labels = _best_k_by_silhouette(X_scaled)
    product_affinity["cluster_label"] = labels

    # Post-hoc, rank-based naming (stable across reruns, unlike the raw
    # integer label). Assigned sequentially so all four names are distinct:
    # highest revenue -> Revenue Core; of what's left, lowest review score ->
    # Trouble Spot; of what's left, highest repeat rate -> Small & Sticky;
    # whatever remains -> Small & Well-Reviewed.
    profile = product_affinity.groupby("cluster_label")[features].mean()
    remaining = set(profile.index)

    revenue_core = profile.loc[list(remaining), "total_revenue"].idxmax()
    remaining.discard(revenue_core)

    trouble_spot = profile.loc[list(remaining), "avg_review_score"].idxmin()
    remaining.discard(trouble_spot)

    small_sticky = profile.loc[list(remaining), "category_repeat_rate_pct"].idxmax()
    remaining.discard(small_sticky)

    small_well_reviewed = next(iter(remaining))

    name_map = {
        revenue_core: "Revenue Core",
        trouble_spot: "Trouble Spot",
        small_sticky: "Small & Sticky",
        small_well_reviewed: "Small & Well-Reviewed",
    }
    product_affinity["cluster_name"] = product_affinity["cluster_label"].map(name_map)

    out = product_affinity[["category"] + ["cluster_label", "cluster_name"] + features].copy()
    out["silhouette_k"] = best_k
    out["computed_at"] = run_ts

    print(f"  best k = {best_k} (expected: 4)")
    print(f"  cluster sizes: {product_affinity['cluster_name'].value_counts().to_dict()}")
    _truncate_and_load(engine, "ml_category_clusters", out)


# =============================================================================
# 4. Review-score feature importance (notebooks/08_product_analysis.ipynb, Section 2)
# =============================================================================

DRIVER_QUERY = """
WITH order_items_agg AS (
    SELECT order_id, SUM(price) AS total_price, SUM(freight_value) AS total_freight
    FROM warehouse.fact_order_items
    GROUP BY order_id
),
order_category AS (
    SELECT
        foi.order_id,
        dp.product_category_name_english,
        ROW_NUMBER() OVER (PARTITION BY foi.order_id ORDER BY foi.price DESC) AS item_rank
    FROM warehouse.fact_order_items foi
    JOIN warehouse.dim_product dp ON dp.product_key = foi.product_key
),
order_payment AS (
    SELECT
        order_id,
        (ARRAY_AGG(payment_type ORDER BY payment_value DESC))[1] AS payment_type
    FROM warehouse.fact_payments
    GROUP BY order_id
)
SELECT
    do_.order_id,
    dc.customer_state,
    EXTRACT(DAY FROM (do_.order_delivered_customer_date - do_.order_purchase_timestamp)) AS delivery_days,
    (oi.total_freight / NULLIF(oi.total_price + oi.total_freight, 0)) * 100 AS freight_pct,
    COALESCE(oc.product_category_name_english, 'uncategorised') AS order_category,
    op.payment_type,
    fr.review_score
FROM warehouse.dim_order do_
JOIN warehouse.dim_customer dc ON dc.customer_key = do_.customer_key
JOIN order_items_agg oi ON oi.order_id = do_.order_id
JOIN order_category oc ON oc.order_id = do_.order_id AND oc.item_rank = 1
JOIN order_payment op ON op.order_id = do_.order_id
JOIN warehouse.fact_reviews fr ON fr.order_id = do_.order_id
WHERE do_.order_status = 'delivered'
  AND do_.order_delivered_customer_date IS NOT NULL
"""


def materialize_review_score_feature_importance(engine, run_ts):
    print("\n[4/4] Review-score feature importance (Random Forest)...")
    driver_data = pd.read_sql(DRIVER_QUERY, engine)

    top_categories = driver_data["order_category"].value_counts().head(15).index
    driver_data["category_grouped"] = driver_data["order_category"].where(
        driver_data["order_category"].isin(top_categories), "other"
    )
    top_states = driver_data["customer_state"].value_counts().head(10).index
    driver_data["state_grouped"] = driver_data["customer_state"].where(
        driver_data["customer_state"].isin(top_states), "other"
    )

    features_df = pd.get_dummies(
        driver_data[["delivery_days", "freight_pct", "category_grouped",
                     "state_grouped", "payment_type"]],
        columns=["category_grouped", "state_grouped", "payment_type"],
        drop_first=False,
    )
    target = driver_data["review_score"]

    X_train, X_test, y_train, y_test = train_test_split(
        features_df, target, test_size=0.2, random_state=RANDOM_STATE
    )

    rf = RandomForestRegressor(
        n_estimators=200, max_depth=8, random_state=RANDOM_STATE, n_jobs=-1
    )
    rf.fit(X_train, y_train)

    train_r2 = r2_score(y_train, rf.predict(X_train))
    test_r2 = r2_score(y_test, rf.predict(X_test))

    importance_df = pd.DataFrame(
        {"feature": features_df.columns, "importance": rf.feature_importances_}
    )

    def _group_feature(f):
        if f.startswith("category_grouped_"):
            return "category"
        if f.startswith("state_grouped_"):
            return "state"
        if f.startswith("payment_type_"):
            return "payment_type"
        return f  # delivery_days, freight_pct pass through unchanged

    importance_df["feature_group"] = importance_df["feature"].apply(_group_feature)
    group_importance = (
        importance_df.groupby("feature_group")["importance"].sum().sort_values(ascending=False)
    )

    out = group_importance.reset_index()
    out.columns = ["feature_group", "importance"]
    out["importance_pct"] = (out["importance"] * 100).round(2)
    out["train_r2"] = round(train_r2, 4)
    out["test_r2"] = round(test_r2, 4)
    out["computed_at"] = run_ts

    print(f"  train R^2={train_r2:.4f}, test R^2={test_r2:.4f} (expected: ~0.18 / ~0.15)")
    print(f"  {out[['feature_group', 'importance_pct']].to_string(index=False)}")
    _truncate_and_load(engine, "ml_review_score_feature_importance", out)


# =============================================================================
# Main
# =============================================================================

def main():
    engine = get_engine()
    run_ts = datetime.now()
    print(f"Materializing ML outputs — run timestamp: {run_ts}")

    materialize_seller_clusters(engine, run_ts)
    materialize_seller_outliers(engine, run_ts)
    materialize_category_clusters(engine, run_ts)
    materialize_review_score_feature_importance(engine, run_ts)

    print("\nDone. All 4 ml_* tables refreshed.")


if __name__ == "__main__":
    main()
