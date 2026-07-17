# =============================================================================
# python/utils/date_conversion.py
# Converts date columns in the Olist dataset to pandas datetime format.
# All date columns are defined in one place so any future additions
# require a single update here rather than changes across multiple notebooks.
# =============================================================================

import pandas as pd

DATE_COLUMNS = {
    "orders": [
        "order_purchase_timestamp",
        "order_approved_at",
        "order_delivered_carrier_date",
        "order_delivered_customer_date",
        "order_estimated_delivery_date"
    ],
    "order_items": ["shipping_limit_date"],
    "reviews": ["review_creation_date", "review_answer_timestamp"]
}


def convert_dates(dfs):
    """
    Convert all date columns in the Olist dataset to pandas datetime format.
    Uses errors='coerce' so malformed values become NaT rather than raising
    exceptions. The original dfs dictionary is modified in place and returned.

    Parameters
    ----------
    dfs : dict[str, pd.DataFrame]
        Dictionary of DataFrames as returned by load_datasets().

    Returns
    -------
    dict[str, pd.DataFrame]
        Same dictionary with date columns converted to datetime dtype.
    """
    for dataset, columns in DATE_COLUMNS.items():
        for column in columns:
            if column in dfs[dataset].columns:
                dfs[dataset][column] = pd.to_datetime(
                    dfs[dataset][column],
                    errors="coerce"
                )

    return dfs
