"""
Marketplace Analytics Platform — raw data acquisition.

Usage:
    python data/02_download_data.py
"""

import subprocess
import sys
from pathlib import Path

DATASET = "olistbr/brazilian-ecommerce"
DATASET_VERSION = 2
DATA_DIR = Path(__file__).resolve().parent

EXPECTED_FILES = [
    "olist_customers_dataset.csv",
    "olist_geolocation_dataset.csv",
    "olist_order_items_dataset.csv",
    "olist_order_payments_dataset.csv",
    "olist_order_reviews_dataset.csv",
    "olist_orders_dataset.csv",
    "olist_products_dataset.csv",
    "olist_sellers_dataset.csv",
    "product_category_name_translation.csv",
]


def already_downloaded() -> bool:
    return all((DATA_DIR / f).exists() for f in EXPECTED_FILES)


def main():
    DATA_DIR.mkdir(exist_ok=True)

    if already_downloaded():
        print(f"All 9 CSVs already present in {DATA_DIR}. Nothing to do.")
        return

    print(f"Downloading '{DATASET}' from Kaggle into {DATA_DIR} ...")
    print(f"(Built on dataset Version {DATASET_VERSION} — the kaggle CLI always pulls the latest version.)")
    cmd = ["kaggle", "datasets", "download", "-d", DATASET, "-p", str(DATA_DIR), "--unzip"]
    try:
        subprocess.run(cmd, check=True)
    except FileNotFoundError:
        sys.exit(
            "Error: 'kaggle' CLI not found. Install it with "
            "'conda install -c conda-forge kaggle' or 'pip install kaggle', "
            "then run 'kaggle auth login' (see docstring above)."
        )
    except subprocess.CalledProcessError as e:
        sys.exit(f"Kaggle download failed: {e}")

    missing = [f for f in EXPECTED_FILES if not (DATA_DIR / f).exists()]
    if missing:
        sys.exit(f"Download incomplete — missing files: {missing}")

    print(f"Done. All 9 CSVs are in {DATA_DIR}.")


if __name__ == "__main__":
    main()
