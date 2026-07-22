"""
01_load_staging.py
Marketplace Analytics Platform  

Reads all 9 Olist source CSVs from data/ and bulk-loads them into the
staging schema of Marketplace-Analytics-Platform.

Design decisions:
  - Minimal type coercion: zip code columns kept as VARCHAR to preserve
    leading zeros; everything else lands as pandas infers.
  - Idempotent: each staging table is TRUNCATED (with RESTART IDENTITY)
    before load, so the script is safe to re-run at any time.
  - Loads in a fixed order that mirrors the ETL dependency sequence so
    log output is easy to follow.

Usage:
    conda activate Marketplace-Analytics-Platform
    cd "Marketplace Analytics Platform"
    python python/etl/01_load_staging.py
"""

import sys
import logging
from pathlib import Path

import pandas as pd
from sqlalchemy import text

# ── path setup ────────────────────────────────────────────────────────────────
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'python' / 'utils'))
from db_connection import get_engine

# ── config ────────────────────────────────────────────────────────────────────
RAW_DIR = ROOT / 'data'

# (csv filename, staging schema, staging table name)
# Ordered to mirror ETL dependency sequence for readable logs.
LOAD_PLAN: list[tuple[str, str, str]] = [
    ('olist_orders_dataset.csv',              'staging', 'stg_orders'),
    ('olist_customers_dataset.csv',           'staging', 'stg_customers'),
    ('olist_order_items_dataset.csv',         'staging', 'stg_order_items'),
    ('olist_order_payments_dataset.csv',      'staging', 'stg_payments'),
    ('olist_order_reviews_dataset.csv',       'staging', 'stg_reviews'),
    ('olist_products_dataset.csv',            'staging', 'stg_products'),
    ('olist_sellers_dataset.csv',             'staging', 'stg_sellers'),
    ('olist_geolocation_dataset.csv',         'staging', 'stg_geolocation'),
    ('product_category_name_translation.csv', 'staging', 'stg_category_translation'),
]

# Columns that must stay VARCHAR to preserve leading zeros.
ZIP_COLS = {
    'customer_zip_code_prefix',
    'seller_zip_code_prefix',
    'geolocation_zip_code_prefix',
}

# ── logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s  %(levelname)-8s  %(message)s',
    datefmt='%H:%M:%S',
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger(__name__)


# ── helpers ───────────────────────────────────────────────────────────────────

def read_csv(filepath: Path) -> pd.DataFrame:
    """
    Read a CSV with minimal processing.
    Zip code columns are forced to str; everything else uses pandas defaults.
    """
    # Peek at headers to build dtype dict only for columns that are present.
    headers = pd.read_csv(filepath, nrows=0).columns.tolist()
    dtype_override = {col: str for col in headers if col in ZIP_COLS}
    return pd.read_csv(filepath, dtype=dtype_override, low_memory=False)


def truncate_table(conn, schema: str, table: str) -> None:
    conn.execute(
        text(f'TRUNCATE TABLE {schema}."{table}" RESTART IDENTITY CASCADE')
    )
    log.info(f'    ✓ Truncated  {schema}.{table}')


def bulk_load(engine, df: pd.DataFrame, schema: str, table: str) -> None:
    import io
    csv_buffer = io.StringIO()
    df.to_csv(csv_buffer, index=False, header=False)
    csv_buffer.seek(0)
    
    with engine.connect() as conn:
        raw = conn.connection
        cursor = raw.cursor()
        cursor.copy_expert(
            f'COPY {schema}."{table}" ({", ".join(df.columns)}) FROM STDIN WITH CSV',
            csv_buffer
        )
        raw.commit()
        cursor.close()
    
    log.info(f'    ✓ Loaded     {len(df):>9,} rows  →  {schema}.{table}')

# ── main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    log.info('━' * 60)
    log.info('Step 1 : Load Staging')
    log.info('━' * 60)

    engine = get_engine()
    total  = len(LOAD_PLAN)
    errors = []

    for i, (filename, schema, table) in enumerate(LOAD_PLAN, start=1):
        filepath = RAW_DIR / filename
        log.info(f'[{i}/{total}]  {filename}')

        # ── guard: file must exist ──
        if not filepath.exists():
            msg = f'File not found: {filepath}'
            log.error(f'    ✗ {msg}')
            errors.append(msg)
            continue

        # ── read ──
        df = read_csv(filepath)
        log.info(f'    → Read {len(df):>9,} rows × {len(df.columns)} columns')

        # ── rename columns to match staging DDL ──
        COLUMN_RENAMES = {
            # stg_products: fix source typos
            'product_name_lenght':        'product_name_length',
            'product_description_lenght': 'product_description_length',
            # stg_geolocation: strip 'geolocation_' prefix
            'geolocation_zip_code_prefix': 'zip_code_prefix',
            'geolocation_lat':             'lat',
            'geolocation_lng':             'lng',
            'geolocation_city':            'city',
            'geolocation_state':           'state',
        }
        df = df.rename(columns=COLUMN_RENAMES)

        # ── fix float columns that should be integer in staging DDL ──
        FLOAT_TO_INT_COLS = [
            'product_name_length',
            'product_description_length',
            'product_photos_qty',
        ]
        for col in FLOAT_TO_INT_COLS:
            if col in df.columns:
                df[col] = pd.to_numeric(df[col], errors='coerce').astype('Int64')

        # ── truncate + load (single transaction per table) ──
        try:
            with engine.begin() as conn:
                truncate_table(conn, schema, table)
            bulk_load(engine, df, schema, table)
        except Exception as exc:
            log.error(f'    ✗ Failed to load {schema}.{table}: {exc}')
            errors.append(str(exc))

    # ── summary ──
    log.info('━' * 60)
    if errors:
        log.error(f'Staging load finished with {len(errors)} error(s):')
        for e in errors:
            log.error(f'  • {e}')
        sys.exit(1)
    else:
        log.info('Staging load complete — all 9 tables populated.')
    log.info('━' * 60)


if __name__ == '__main__':
    main()
