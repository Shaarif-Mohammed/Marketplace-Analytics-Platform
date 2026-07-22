"""
02_load_warehouse.py
Marketplace Analytics Platform 

Reads from the staging schema, applies all documented cleaning rules,
resolves surrogate keys, generates dim_date, and loads the warehouse
schema in strict dependency order.

Run 01_load_staging.py before this script.

Idempotency: all warehouse tables are truncated (RESTART IDENTITY CASCADE)
before any inserts, so the script is safe to re-run at any time.

Warehouse load order (dependency sequence):
  1. dim_date          — generated programmatically; no dependencies
  2. dim_geolocation   — from stg_geolocation; no FK dependencies
  3. dim_customer      — depends on dim_geolocation
  4. dim_seller        — depends on dim_geolocation
  5. dim_product       — no FK dependencies
  6. dim_order         — depends on dim_customer, dim_date
  7. fact_order_items  — depends on dim_order, dim_seller, dim_product
  8. fact_payments     — no FK dependencies (joins warehouse via order_id)
  9. fact_reviews      — no FK dependencies (joins warehouse via order_id)

Cleaning rules applied :
  • dim_geolocation : filter lat outside (-34, 6) or lng outside (-75, -32); avg per zip
  • dim_product     : product_weight_g = 0 → NULL; join category translation;
                      manual-map 2 missing entries
  • dim_order       : derive purchase_date_key from order_purchase_timestamp
  • fact_order_items: null shipping_limit_date > order_purchase_timestamp + 60d
  • fact_payments   : payment_installments = 0 → 1

Usage:
    conda activate Marketplace-Analytics-Platform
    cd "Marketplace Analytics Platform"
    python Python/etl/02_load_warehouse.py
"""

import io
import sys
import logging
from pathlib import Path
from datetime import date

import numpy as np
import pandas as pd
from sqlalchemy import text

# ── path setup ────────────────────────────────────────────────────────────────
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'python' / 'utils'))
from db_connection import get_engine

# ── constants ─────────────────────────────────────────────────────────────────
DATE_RANGE_START = date(2016, 1, 1)
DATE_RANGE_END   = date(2019, 12, 31)

LAT_MIN, LAT_MAX = -34.0,  6.0
LNG_MIN, LNG_MAX = -75.0, -32.0

MANUAL_CATEGORY_MAP: dict[str, str] = {
    'pc_gamer': 'gaming_pc',
    'portateis_cozinha_e_preparadores_de_alimentos': 'portable_kitchen_food_preparators',
}

# Reverse dependency order — safe truncation sequence
TRUNCATE_ORDER = [
    'fact_reviews',
    'fact_payments',
    'fact_order_items',
    'dim_order',
    'dim_product',
    'dim_seller',
    'dim_customer',
    'dim_geolocation',
    'dim_date',
]

# ── logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s  %(levelname)-8s  %(message)s',
    datefmt='%H:%M:%S',
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger(__name__)


# ══════════════════════════════════════════════════════════════════════════════
# Utility helpers
# ══════════════════════════════════════════════════════════════════════════════

def sql_read(engine, query: str) -> pd.DataFrame:
    with engine.connect() as conn:
        return pd.read_sql(text(query), conn)


def bulk_load(engine, df: pd.DataFrame, schema: str, table: str) -> None:
    """
    Stream data into Postgres via COPY FROM STDIN.
    Avoids all parameter-limit issues; fastest possible load method.
    """
    df = df.copy()
    # Convert nullable Int64 to plain Python objects so integers write without
    # a trailing '.0' in the CSV (NULL → empty string via na_rep='')
    for col in df.select_dtypes(include='Int64').columns:
        df[col] = df[col].astype(object).where(df[col].notna(), None)

    csv_buffer = io.StringIO()
    df.to_csv(csv_buffer, index=False, header=False, na_rep='')
    csv_buffer.seek(0)

    with engine.connect() as conn:
        raw    = conn.connection
        cursor = raw.cursor()
        cols   = ', '.join(f'"{c}"' for c in df.columns)
        cursor.copy_expert(
            f"COPY {schema}.\"{table}\" ({cols}) FROM STDIN WITH (FORMAT CSV, NULL '')",
            csv_buffer,
        )
        raw.commit()
        cursor.close()

    log.info(f'    ✓ Loaded  {len(df):>9,} rows  →  warehouse.{table}')


def truncate_all_warehouse(engine) -> None:
    log.info('Truncating warehouse tables …')
    with engine.begin() as conn:
        for table in TRUNCATE_ORDER:
            conn.execute(
                text(f'TRUNCATE TABLE warehouse."{table}" RESTART IDENTITY CASCADE')
            )
            log.info(f'  ✓ Truncated warehouse.{table}')


# ══════════════════════════════════════════════════════════════════════════════
# Read staging
# ══════════════════════════════════════════════════════════════════════════════

def read_staging(engine) -> dict[str, pd.DataFrame]:
    log.info('Reading staging tables …')

    tables = {
        'orders':      'SELECT * FROM staging.stg_orders',
        'customers':   'SELECT * FROM staging.stg_customers',
        'order_items': 'SELECT * FROM staging.stg_order_items',
        'payments':    'SELECT * FROM staging.stg_payments',
        'reviews':     'SELECT * FROM staging.stg_reviews',
        'products':    'SELECT * FROM staging.stg_products',
        'sellers':     'SELECT * FROM staging.stg_sellers',
        'geolocation': 'SELECT * FROM staging.stg_geolocation',
        'cat_trans':   'SELECT * FROM staging.stg_category_translation',
    }

    # Zip code columns that must stay as zero-padded strings
    zip_cols = {
        'customer_zip_code_prefix',
        'seller_zip_code_prefix',
        'zip_code_prefix',   # geolocation — renamed in 01_load_staging.py
    }

    staging: dict[str, pd.DataFrame] = {}
    for key, query in tables.items():
        df = sql_read(engine, query)
        for col in zip_cols:
            if col in df.columns:
                df[col] = df[col].astype(str).str.zfill(5)
        staging[key] = df
        log.info(f'  → staging.{key:<18}  {len(df):>9,} rows')

    return staging


# ══════════════════════════════════════════════════════════════════════════════
# dim_date
# ══════════════════════════════════════════════════════════════════════════════

def build_dim_date() -> pd.DataFrame:
    dates = pd.date_range(start=DATE_RANGE_START, end=DATE_RANGE_END, freq='D')
    df = pd.DataFrame({'full_date': dates})
    df['date_key']     = df['full_date'].dt.strftime('%Y%m%d').astype(int)
    df['day']          = df['full_date'].dt.day
    df['month']        = df['full_date'].dt.month
    df['month_name']   = df['full_date'].dt.strftime('%B')
    df['quarter']      = df['full_date'].dt.quarter
    df['year']         = df['full_date'].dt.year
    df['week_of_year'] = df['full_date'].dt.isocalendar().week.astype(int)
    df['weekday_name'] = df['full_date'].dt.strftime('%A')
    df['is_weekend']   = df['full_date'].dt.dayofweek >= 5
    df['full_date']    = df['full_date'].dt.date
    return df[['date_key', 'full_date', 'day', 'month', 'month_name',
               'quarter', 'year', 'week_of_year', 'weekday_name', 'is_weekend']]


def load_dim_date(engine) -> pd.DataFrame:
    log.info('Loading dim_date …')
    df = build_dim_date()
    bulk_load(engine, df, 'warehouse', 'dim_date')
    log.info(f'  → date range: {df["full_date"].min()} → {df["full_date"].max()}')
    return df


# ══════════════════════════════════════════════════════════════════════════════
# dim_geolocation
# DDL columns: zip_code_prefix, avg_lat, avg_lng, city, state
# ══════════════════════════════════════════════════════════════════════════════

def build_dim_geolocation(stg: pd.DataFrame) -> pd.DataFrame:
    """
    Staging columns: zip_code_prefix, lat, lng, city, state
    (renamed from geolocation_* by 01_load_staging.py)
    Warehouse columns: zip_code_prefix, avg_lat, avg_lng, city, state
    """
    df = stg.copy()

    before = len(df)
    df = df[
        df['lat'].between(LAT_MIN, LAT_MAX) &
        df['lng'].between(LNG_MIN, LNG_MAX)
    ]
    log.info(f'  → Dropped {before - len(df):,} out-of-bounds geocode rows')

    agg = (
        df.groupby('zip_code_prefix')
          .agg(
              avg_lat = ('lat',   'mean'),
              avg_lng = ('lng',   'mean'),
              city    = ('city',  lambda x: x.mode().iloc[0]),
              state   = ('state', lambda x: x.mode().iloc[0]),
          )
          .reset_index()
    )
    log.info(f'  → Deduplicated {before:,} → {len(agg):,} unique zip prefixes')
    return agg[['zip_code_prefix', 'avg_lat', 'avg_lng', 'city', 'state']]


def load_dim_geolocation(engine, stg: pd.DataFrame) -> None:
    log.info('Loading dim_geolocation …')
    df = build_dim_geolocation(stg)
    bulk_load(engine, df, 'warehouse', 'dim_geolocation')


def query_geo_map(engine) -> pd.Series:
    """zip_code_prefix → geolocation_key"""
    return sql_read(engine,
        'SELECT geolocation_key, zip_code_prefix FROM warehouse.dim_geolocation'
    ).set_index('zip_code_prefix')['geolocation_key']


# ══════════════════════════════════════════════════════════════════════════════
# dim_customer
# DDL columns: customer_id, customer_unique_id, customer_zip_code_prefix,
#              customer_city, customer_state, geolocation_key
# ══════════════════════════════════════════════════════════════════════════════

def build_dim_customer(stg: pd.DataFrame, geo_map: pd.Series) -> pd.DataFrame:
    """
    Staging column names already match DDL — no renaming needed.
    Just add geolocation_key via zip code lookup.
    """
    df = stg.copy()
    df['geolocation_key'] = df['customer_zip_code_prefix'].map(geo_map)
    df['geolocation_key'] = df['geolocation_key'].astype('Int64')
    null_geo = df['geolocation_key'].isna().sum()
    if null_geo:
        log.info(f'  → {null_geo:,} customers have no geo match (geolocation_key = NULL)')
    return df[['customer_id', 'customer_unique_id', 'customer_zip_code_prefix',
               'customer_city', 'customer_state', 'geolocation_key']]


def load_dim_customer(engine, stg: pd.DataFrame, geo_map: pd.Series) -> None:
    log.info('Loading dim_customer …')
    df = build_dim_customer(stg, geo_map)
    bulk_load(engine, df, 'warehouse', 'dim_customer')


def query_customer_map(engine) -> pd.Series:
    """customer_id → customer_key"""
    return sql_read(engine,
        'SELECT customer_key, customer_id FROM warehouse.dim_customer'
    ).set_index('customer_id')['customer_key']


# ══════════════════════════════════════════════════════════════════════════════
# dim_seller
# DDL columns: seller_id, seller_zip_code_prefix, seller_city,
#              seller_state, geolocation_key
# ══════════════════════════════════════════════════════════════════════════════

def build_dim_seller(stg: pd.DataFrame, geo_map: pd.Series) -> pd.DataFrame:
    """
    Staging column names already match DDL — no renaming needed.
    Just add geolocation_key via zip code lookup.
    """
    df = stg.copy()
    df['geolocation_key'] = df['seller_zip_code_prefix'].map(geo_map)
    df['geolocation_key'] = df['geolocation_key'].astype('Int64')
    null_geo = df['geolocation_key'].isna().sum()
    if null_geo:
        log.info(f'  → {null_geo:,} sellers have no geo match (geolocation_key = NULL)')
    return df[['seller_id', 'seller_zip_code_prefix', 'seller_city',
               'seller_state', 'geolocation_key']]


def load_dim_seller(engine, stg: pd.DataFrame, geo_map: pd.Series) -> None:
    log.info('Loading dim_seller …')
    df = build_dim_seller(stg, geo_map)
    bulk_load(engine, df, 'warehouse', 'dim_seller')


def query_seller_map(engine) -> pd.Series:
    """seller_id → seller_key"""
    return sql_read(engine,
        'SELECT seller_key, seller_id FROM warehouse.dim_seller'
    ).set_index('seller_id')['seller_key']


# ══════════════════════════════════════════════════════════════════════════════
# dim_product
# DDL columns: product_id, product_category_name, product_category_name_english,
#              product_name_length, product_description_length, product_photos_qty,
#              product_weight_g, product_length_cm, product_height_cm, product_width_cm
# ══════════════════════════════════════════════════════════════════════════════

def build_dim_product(stg_products: pd.DataFrame,
                      stg_cat: pd.DataFrame) -> pd.DataFrame:
    df = stg_products.copy()

    # 1. Fix integer columns
    for col in ['product_name_length', 'product_description_length', 'product_photos_qty']:
        df[col] = pd.to_numeric(df[col], errors='coerce').astype('Int64')

    # 2. Clean weight
    zero_weight = (df['product_weight_g'] == 0).sum()
    df.loc[df['product_weight_g'] == 0, 'product_weight_g'] = np.nan
    if zero_weight:
        log.info(f'  → Nulled {zero_weight} product_weight_g = 0 rows')

    # 3. Category translation (creates the column)
    cat_map = dict(zip(stg_cat['product_category_name'],
                       stg_cat['product_category_name_english']))
    cat_map.update(MANUAL_CATEGORY_MAP)
    df['product_category_name_english'] = df['product_category_name'].map(cat_map)

    # 4. Now safe to check unmapped
    unmapped_cats = (
        df.loc[df['product_category_name_english'].isna() &
               df['product_category_name'].notna(), 'product_category_name']
          .unique().tolist()
    )
    if unmapped_cats:
        log.warning(f'  → Unmapped categories: {unmapped_cats}')
    else:
        null_cat = df['product_category_name'].isna().sum()
        log.info(f'  → {null_cat} products have no category (source is blank)')

    return df[['product_id', 'product_category_name', 'product_category_name_english',
               'product_name_length', 'product_description_length', 'product_photos_qty',
               'product_weight_g', 'product_length_cm', 'product_height_cm',
               'product_width_cm']]


def load_dim_product(engine, stg_products: pd.DataFrame,
                     stg_cat: pd.DataFrame) -> None:
    log.info('Loading dim_product …')
    df = build_dim_product(stg_products, stg_cat)
    bulk_load(engine, df, 'warehouse', 'dim_product')


def query_product_map(engine) -> pd.Series:
    """product_id → product_key"""
    return sql_read(engine,
        'SELECT product_key, product_id FROM warehouse.dim_product'
    ).set_index('product_id')['product_key']


# ══════════════════════════════════════════════════════════════════════════════
# dim_order
# DDL columns: order_id, customer_key, purchase_date_key, order_status,
#              order_purchase_timestamp, order_approved_at,
#              order_delivered_carrier_date, order_delivered_customer_date,
#              order_estimated_delivery_date
# ══════════════════════════════════════════════════════════════════════════════

def build_dim_order(stg: pd.DataFrame,
                    customer_map: pd.Series,
                    dim_date: pd.DataFrame) -> pd.DataFrame:
    df = stg.copy()

    df['customer_key'] = df['customer_id'].map(customer_map)
    unmatched = df['customer_key'].isna().sum()
    if unmatched:
        log.warning(f'  → {unmatched:,} orders have no matching customer_key')

    df['order_purchase_timestamp'] = pd.to_datetime(
        df['order_purchase_timestamp'], errors='coerce'
    )
    purchase_date_int = (
        df['order_purchase_timestamp']
          .dt.strftime('%Y%m%d')
          .astype('Int64')
    )
    valid_keys = set(dim_date['date_key'].astype(int))
    df['purchase_date_key'] = purchase_date_int.where(
        purchase_date_int.isin(valid_keys), other=pd.NA
    )
    out_of_range = df['purchase_date_key'].isna().sum()
    if out_of_range:
        log.warning(f'  → {out_of_range:,} orders have purchase dates outside dim_date range')

    for col in ['order_approved_at', 'order_delivered_carrier_date',
                'order_delivered_customer_date', 'order_estimated_delivery_date']:
        df[col] = pd.to_datetime(df[col], errors='coerce')

    return df[['order_id', 'customer_key', 'purchase_date_key', 'order_status',
               'order_purchase_timestamp', 'order_approved_at',
               'order_delivered_carrier_date', 'order_delivered_customer_date',
               'order_estimated_delivery_date']]


def load_dim_order(engine, stg: pd.DataFrame,
                   customer_map: pd.Series,
                   dim_date: pd.DataFrame) -> None:
    log.info('Loading dim_order …')
    df = build_dim_order(stg, customer_map, dim_date)
    bulk_load(engine, df, 'warehouse', 'dim_order')


def query_order_map(engine) -> pd.Series:
    """order_id → order_key"""
    return sql_read(engine,
        'SELECT order_key, order_id FROM warehouse.dim_order'
    ).set_index('order_id')['order_key']


# ══════════════════════════════════════════════════════════════════════════════
# fact_order_items
# DDL columns: order_id, order_item_id, order_key, seller_key, product_key,
#              price, freight_value, shipping_limit_date
# ══════════════════════════════════════════════════════════════════════════════

def build_fact_order_items(stg_items: pd.DataFrame,
                            stg_orders: pd.DataFrame,
                            order_map: pd.Series,
                            seller_map: pd.Series,
                            product_map: pd.Series) -> pd.DataFrame:
    """
    Cleaning rule: null shipping_limit_date > order_purchase_timestamp + 60 days.
    order_id kept as degenerate dimension (natural key for cross-fact joins).
    """
    df = stg_items.copy()

    df['order_key']   = df['order_id'].map(order_map)
    df['seller_key']  = df['seller_id'].map(seller_map)
    df['product_key'] = df['product_id'].map(product_map)

    for col, name in [('order_key', 'order'), ('seller_key', 'seller'),
                      ('product_key', 'product')]:
        n = df[col].isna().sum()
        if n:
            log.warning(f'  → {n:,} fact_order_items rows have no matching {name}_key')

    df['shipping_limit_date'] = pd.to_datetime(df['shipping_limit_date'], errors='coerce')

    stg_orders_dt = stg_orders[['order_id', 'order_purchase_timestamp']].copy()
    stg_orders_dt['order_purchase_timestamp'] = pd.to_datetime(
        stg_orders_dt['order_purchase_timestamp'], errors='coerce'
    )
    df = df.merge(stg_orders_dt, on='order_id', how='left')
    cutoff       = df['order_purchase_timestamp'] + pd.Timedelta(days=60)
    outlier_mask = df['shipping_limit_date'] > cutoff
    if outlier_mask.sum():
        log.info(f'  → Nulled {outlier_mask.sum()} shipping_limit_date outliers (> purchase + 60 days)')
    df.loc[outlier_mask, 'shipping_limit_date'] = pd.NaT

    return df[['order_id', 'order_item_id', 'order_key', 'seller_key',
               'product_key', 'price', 'freight_value', 'shipping_limit_date']]


def load_fact_order_items(engine, stg_items: pd.DataFrame,
                           stg_orders: pd.DataFrame,
                           order_map: pd.Series,
                           seller_map: pd.Series,
                           product_map: pd.Series) -> None:
    log.info('Loading fact_order_items …')
    df = build_fact_order_items(stg_items, stg_orders, order_map,
                                 seller_map, product_map)
    bulk_load(engine, df, 'warehouse', 'fact_order_items')


# ══════════════════════════════════════════════════════════════════════════════
# fact_payments
# DDL columns: order_id, payment_sequential, payment_type,
#              payment_installments, payment_value
# ══════════════════════════════════════════════════════════════════════════════

def build_fact_payments(stg: pd.DataFrame) -> pd.DataFrame:
    df = stg.copy()
    zero_inst = (df['payment_installments'] == 0).sum()
    df.loc[df['payment_installments'] == 0, 'payment_installments'] = 1
    if zero_inst:
        log.info(f'  → Fixed {zero_inst} payment_installments = 0 → 1')
    return df[['order_id', 'payment_sequential', 'payment_type',
               'payment_installments', 'payment_value']]


def load_fact_payments(engine, stg: pd.DataFrame) -> None:
    log.info('Loading fact_payments …')
    df = build_fact_payments(stg)
    bulk_load(engine, df, 'warehouse', 'fact_payments')


# ══════════════════════════════════════════════════════════════════════════════
# fact_reviews
# DDL columns: review_id, order_id, review_score, review_comment_title,
#              review_comment_message, review_creation_date, review_answer_timestamp
# ══════════════════════════════════════════════════════════════════════════════

def build_fact_reviews(stg: pd.DataFrame) -> pd.DataFrame:
    df = stg.copy()
    for col in ['review_creation_date', 'review_answer_timestamp']:
        df[col] = pd.to_datetime(df[col], errors='coerce')
    return df[['review_id', 'order_id', 'review_score', 'review_comment_title',
               'review_comment_message', 'review_creation_date',
               'review_answer_timestamp']]


def load_fact_reviews(engine, stg: pd.DataFrame) -> None:
    log.info('Loading fact_reviews …')
    df = build_fact_reviews(stg)
    bulk_load(engine, df, 'warehouse', 'fact_reviews')


# ══════════════════════════════════════════════════════════════════════════════
# Validation
# ══════════════════════════════════════════════════════════════════════════════

VALIDATION_CHECKS = {
    'dim_date':         (1461, 1461),
    'dim_geolocation':  (18_000, 22_000),
    'dim_customer':     (99_441, 99_441),
    'dim_seller':       (3_095, 3_095),
    'dim_product':      (32_951, 32_951),
    'dim_order':        (99_441, 99_441),
    'fact_order_items': (112_650, 112_650),
    'fact_payments':    (103_886, 103_886),
    'fact_reviews':     (99_224, 99_224),
}


def validate(engine) -> None:
    log.info('━' * 60)
    log.info('Validation — row counts')
    log.info('━' * 60)
    all_ok = True
    for table, (lo, hi) in VALIDATION_CHECKS.items():
        count = sql_read(engine,
            f'SELECT COUNT(*) AS n FROM warehouse."{table}"'
        ).iloc[0]['n']
        in_range = lo <= count <= hi
        status = '✓' if in_range else '✗'
        log.info(f'  {status}  warehouse.{table:<22}  {count:>9,} rows'
                 + ('' if in_range else f'  ← expected [{lo:,} – {hi:,}]'))
        if not in_range:
            all_ok = False
    log.info('━' * 60)
    if all_ok:
        log.info('All row count checks passed.')
    else:
        log.warning('One or more row count checks failed — review warnings above.')
    log.info('━' * 60)


# ══════════════════════════════════════════════════════════════════════════════
# Main
# ══════════════════════════════════════════════════════════════════════════════

def main() -> None:
    log.info('━' * 60)
    log.info('Step 2 : Load Warehouse')
    log.info('━' * 60)

    engine = get_engine()

    truncate_all_warehouse(engine)
    staging     = read_staging(engine)

    dim_date_df = load_dim_date(engine)

    load_dim_geolocation(engine, staging['geolocation'])
    geo_map     = query_geo_map(engine)

    load_dim_customer(engine, staging['customers'], geo_map)
    customer_map = query_customer_map(engine)

    load_dim_seller(engine, staging['sellers'], geo_map)
    seller_map  = query_seller_map(engine)

    load_dim_product(engine, staging['products'], staging['cat_trans'])
    product_map = query_product_map(engine)

    load_dim_order(engine, staging['orders'], customer_map, dim_date_df)
    order_map   = query_order_map(engine)

    load_fact_order_items(
        engine,
        staging['order_items'], staging['orders'],
        order_map, seller_map, product_map,
    )
    load_fact_payments(engine, staging['payments'])
    load_fact_reviews(engine, staging['reviews'])

    validate(engine)
    log.info('Warehouse load complete.')


if __name__ == '__main__':
    main()
