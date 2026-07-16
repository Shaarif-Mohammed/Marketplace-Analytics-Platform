# =============================================================================
# python/utils/load_data.py
# Loads all 9 raw Olist CSV files into a dictionary of DataFrames.
# Path is resolved relative to this file's location so it works correctly
# regardless of where the notebook calling it is located.
# =============================================================================

from pathlib import Path
import pandas as pd

DATA_DIR = Path(__file__).resolve().parents[2] / "data"

FILES = {
    "orders": "olist_orders_dataset.csv",
    "customers": "olist_customers_dataset.csv",
    "order_items": "olist_order_items_dataset.csv",
    "payments": "olist_order_payments_dataset.csv",
    "reviews": "olist_order_reviews_dataset.csv",
    "products": "olist_products_dataset.csv",
    "sellers": "olist_sellers_dataset.csv",
    "geolocation": "olist_geolocation_dataset.csv",
    "category_translation": "product_category_name_translation.csv"
}


def load_datasets():
    """
    Load all raw Olist CSV files from data/ into a dictionary of DataFrames.

    Returns
    -------
    dict[str, pd.DataFrame]
        Keys are dataset names, values are the corresponding DataFrames.
    """
    return {
        name: pd.read_csv(DATA_DIR / filename)
        for name, filename in FILES.items()
    }
