"""
Marketplace Analytics Platform
Script: 04_export_for_tableau.py
Location: python/etl/

Description:
    Exports the 9 warehouse fact/dimension tables, 13 vw_* views, and 4
    ml_* tables from the warehouse schema to individual CSV files for
    Tableau Public, which cannot connect live to a database. Since the
    underlying data is static (all 9 raw Olist CSVs were downloaded once
    and the warehouse was built from them, with no ongoing source
    updates), this is a one-time export, not a scheduled job — re-run
    only if the warehouse is intentionally rebuilt or the ML outputs are
    re-materialized.

    Does NOT export the raw Kaggle CSVs (data/raw/) — those were only
    ever an ETL input. Everything Tableau needs is already cleaned and
    modeled in the warehouse schema.

Usage:
    python python/etl/04_export_for_tableau.py

Output:
    26 CSV files written to data/processed/tableau_exports/
"""

import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "utils"))
from db_connection import get_engine  # noqa: E402


OUTPUT_DIR = Path(__file__).resolve().parents[2] / "data" / "processed" / "tableau_exports"

# 9 warehouse fact/dim tables + 13 vw_* views + 4 ml_* materialized tables
TABLES = [
    # Fact/dimension tables (needed for worksheets that read below view-level:
    # Overview KPIs/trend, macro-region delivery chart, regional map lat/lng,
    # Category Deep-Dive drill-through)
    "dim_customer",
    "dim_seller",
    "dim_product",
    "dim_order",
    "dim_date",
    "dim_geolocation",
    "fact_order_items",
    "fact_payments",
    "fact_reviews",
    # Views
    "vw_rfm",
    "vw_clv",
    "vw_retention",
    "vw_seller_performance",
    "vw_regional_analysis",
    "vw_customer_health",
    "vw_seller_health",
    "vw_new_vs_returning_revenue",
    "vw_pareto_analysis",
    "vw_delivery_experience",
    "vw_payment_behaviour",
    "vw_product_customer_affinity",
    "vw_review_response_intelligence",
    "ml_seller_clusters",
    "ml_seller_outliers",
    "ml_category_clusters",
    "ml_review_score_feature_importance",
]


def export_all():
    engine = get_engine()
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Exporting {len(TABLES)} tables/views to {OUTPUT_DIR}\n")

    for name in TABLES:
        df = pd.read_sql(f"SELECT * FROM warehouse.{name}", engine)
        out_path = OUTPUT_DIR / f"{name}.csv"
        df.to_csv(out_path, index=False, encoding="utf-8")
        print(f"  {name}: {len(df):,} rows -> {out_path.name}")

    print("\nDone.")


if __name__ == "__main__":
    export_all()
