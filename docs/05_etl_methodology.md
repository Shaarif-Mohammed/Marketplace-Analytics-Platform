# ETL Decisions
## Marketplace Analytics Platform

## Overview

This document records every data cleaning and transformation decision made during the ETL pipeline. Each entry documents the problem observed, the decision taken, and the rationale. This is the authoritative reference for any reviewer asking "why does the warehouse data differ from the raw CSVs?"

The pipeline runs in four scripts:

| Script | Responsibility |
|---|---|
| `python/etl/01_load_staging.py` | Reads 9 raw CSVs → applies minimal type fixes → bulk loads into `staging` schema |
| `python/etl/02_load_warehouse.py` | Reads `staging` → applies all cleaning rules → loads `warehouse` schema in dependency order |
| `python/etl/03_materialize_ml_outputs.py` | Reads warehouse views → fits K-means/Random Forest models → writes static `ml_*` tables back to `warehouse` schema |
| `python/etl/export_for_tableau.py` | Reads all 9 fact/dim tables, 15 views, and 4 `ml_*` tables → writes each to CSV in `data/processed/tableau_exports/` |

`03_materialize_ml_outputs.py` was added to support Tableau dashboards that need ML-derived groupings SQL alone can't produce — see `docs/08_ml_outputs_reference.md` for full business rationale and table-by-table detail. It differs from the two scripts above in one structural way: it reads from `warehouse` views, not `staging`, since it depends on the warehouse already being populated.

`export_for_tableau.py` was added because Tableau Public — the free tier used for this project's published dashboard — cannot hold a live connection to a local Postgres database; it only accepts static files or extracts. Rather than model the connection strategy around that limitation implicitly, it's captured explicitly as its own script and its own documented step. The underlying data is static (a one-time Kaggle download, no ongoing source updates), so this is a one-time export, not a scheduled job — re-run only if the warehouse or ML tables are intentionally rebuilt. Full reasoning (why CSV export over a live connection, the 5-island Tableau data model, connection-type tradeoffs) lives in `docs/dashboard_guide.md`, not here — this entry is deliberately just the mechanical record that the script exists and what it does, consistent with how the rest of this table treats each script.

---

## Design Principles

**Two-layer architecture.** Raw data lands in `staging` with only minimal, essential type fixes applied. All business-logic transformations happen in the move from staging to warehouse. This mirrors enterprise pipeline design and makes it straightforward to re-run or audit any transformation without touching source files.

**Idempotency.** Both scripts can be re-run at any time safely. Staging tables are truncated with `RESTART IDENTITY` before each load. Warehouse tables are truncated in reverse dependency order with `RESTART IDENTITY CASCADE` before each load. Re-running produces identical results.

**COPY-based bulk load.** Both scripts use PostgreSQL's `COPY FROM STDIN` to load data rather than SQLAlchemy's `to_sql`. This avoids psycopg2's 32,767 bind parameter limit, which was hit on the geolocation table (1,000,163 rows × 5 columns). COPY is also significantly faster than parameterised inserts.

**Surrogate keys.** All dimension tables use a Postgres `SERIAL` surrogate key as the primary key. Natural keys are retained as regular columns. Fact tables join to dimensions via surrogate keys, except `fact_payments` and `fact_reviews` which use `order_id` as a degenerate dimension key (see below).

---

## Staging Layer — Transformations Applied in `01_load_staging.py`

### Zip code columns preserved as VARCHAR

**Problem:** `customer_zip_code_prefix`, `seller_zip_code_prefix`, and `geolocation_zip_code_prefix` are 5-digit strings representing Brazilian postal prefix codes. Pandas infers them as integers, silently dropping leading zeros.

**Decision:** Force these columns to `str` on CSV read and zero-pad to 5 characters with `str.zfill(5)`. Stored as `VARCHAR` in staging DDL.

**Rationale:** Geographic joins between customers, sellers, and geolocation depend on exact string matching of these prefixes. Losing leading zeros silently breaks all geo lookups for São Paulo area codes (which start with `0`).

---

### Geolocation columns renamed on load

**Problem:** The raw geolocation CSV uses a `geolocation_` prefix on all columns (`geolocation_zip_code_prefix`, `geolocation_lat`, `geolocation_lng`, `geolocation_city`, `geolocation_state`). The staging DDL uses shorter, cleaner names without the prefix.

**Decision:** Rename at load time in `01_load_staging.py`:

| CSV column | Staging column |
|---|---|
| `geolocation_zip_code_prefix` | `zip_code_prefix` |
| `geolocation_lat` | `lat` |
| `geolocation_lng` | `lng` |
| `geolocation_city` | `city` |
| `geolocation_state` | `state` |

**Rationale:** Cleaner column names in staging; avoids having to strip the prefix repeatedly in the warehouse script and any downstream queries.

---

### Product column name typos corrected

**Problem:** The source CSV contains two column names with a spelling error: `product_name_lenght` and `product_description_lenght` (missing the `t` in `length`).

**Decision:** Rename at staging load time:

| CSV column | Staging / Warehouse column |
|---|---|
| `product_name_lenght` | `product_name_length` |
| `product_description_lenght` | `product_description_length` |

**Rationale:** Correcting at the earliest point (staging load) means the typo never propagates to the warehouse or any downstream query.

---

### Product dimension columns converted from float to integer

**Problem:** `product_name_length`, `product_description_length`, and `product_photos_qty` are stored as `FLOAT` in the CSV (e.g. `40.0`, `NaN`) because pandas infers float when nulls are present. The staging and warehouse DDL defines these as `INTEGER`, causing a type mismatch on load.

**Decision:** Convert these three columns to pandas nullable integer (`Int64`) before loading into staging. `Int64` handles `NaN` rows without error, which plain `int` cannot.

**Rationale:** These are counts of characters and photos — they are semantically integers. Float representation is a pandas inference artefact, not meaningful data.

---

## Warehouse Layer — Cleaning Rules Applied in `02_load_warehouse.py`

### `dim_geolocation` — Out-of-bounds geocoordinates

**Problem:** The raw geolocation file contains rows with latitude/longitude values that fall outside the geographic boundaries of Brazil, indicating corrupt or erroneous geocoding entries.

**Decision:** Drop any row where `lat` falls outside (−34, 6) or `lng` falls outside (−75, −32) before aggregating.

**Rationale:** These bounding box values encompass all of Brazil's land territory with a small buffer. Rows outside this range cannot represent valid Brazilian locations and would skew geographic aggregations and map visualisations.

---

### `dim_geolocation` — Duplicate zip code prefixes

**Problem:** The raw geolocation file contains 1,000,163 rows but only ~19,000 unique zip code prefixes. Brazil's Correios geocoding data includes multiple coordinate entries per prefix. The warehouse requires one row per zip prefix to serve as a geographic lookup dimension.

**Decision:** Deduplicate to one row per `zip_code_prefix` using:
- `avg_lat`, `avg_lng`: arithmetic mean of all valid coordinates for that prefix
- `city`, `state`: most-frequent value (mode) for that prefix

**Note on column names:** The warehouse DDL stores the aggregated coordinates as `avg_lat` and `avg_lng` (not `lat`/`lng`) to make clear these are averaged values, not raw source coordinates.

**Rationale:** Averaging produces a centroid representative of the prefix's coverage area, appropriate for state-level aggregation and map use cases. Mode for city/state handles minor spelling variations in the source (e.g. `sao paulo` vs `são paulo`).

---

### `dim_customer` and `dim_seller` — Geolocation key as nullable integer

**Problem:** After mapping `zip_code_prefix` to `geolocation_key` via a pandas Series lookup, unmatched zip codes produce `NaN` values. Pandas stores this as `float64`, causing Postgres to receive values like `5359.0` instead of `5359`, which fails the `INTEGER` type check.

**Decision:** Explicitly cast `geolocation_key` to pandas nullable integer (`Int64`) after the map lookup. The `bulk_load` function then serialises non-null values as clean integers and nulls as empty strings in the COPY stream.

**Rationale:** Not all customer and seller zip codes have a matching entry in the geolocation table — the source file does not provide 100% coverage. `NULL` correctly represents "location unknown" and is handled gracefully in all geographic SQL views.

---

### `dim_product` — Zero product weight

**Problem:** 4 product rows have `product_weight_g = 0`. A weight of exactly zero is physically impossible for a shipped product and is clearly a data entry error. All 4 affected products are in the `cama_mesa_banho` (bed/bath) category.

**Decision:** Replace `product_weight_g = 0` with `NULL`.

**Rationale:** `NULL` correctly signals unknown/missing data. Zero weight would cause errors in any weight-based freight calculation. SQL aggregation functions and pandas both handle `NULL` gracefully.

---

### `dim_product` — Missing English category translations

**Problem:** The `product_category_name_translation.csv` lookup file contains 71 entries but does not include translations for two categories present in the products table: `pc_gamer` and `portateis_cozinha_e_preparadores_de_alimentos`.

**Decision:** Apply manual translations hardcoded in the ETL script:

| Portuguese | English |
|---|---|
| `pc_gamer` | `gaming_pc` |
| `portateis_cozinha_e_preparadores_de_alimentos` | `portable_kitchen_food_preparators` |

**Rationale:** These categories are required for the product-customer affinity and category revenue analyses. Leaving them unmapped produces `NULL` English names, causing affected products to fall into an unknown bucket in all downstream views and dashboards.

---

### `dim_product` — Blank product category (source nulls)

**Problem:** 610 products in the source CSV have no `product_category_name` value (blank/null). These are not translation failures — the category is simply absent from the source data.

**Decision:** Leave `product_category_name` and `product_category_name_english` as `NULL` for these rows. No imputation applied.

**Rationale:** Imputing a category would introduce false data. `NULL` correctly represents unknown category. SQL views that aggregate by category use `COALESCE(product_category_name_english, 'uncategorised')` to handle these rows cleanly at query time.

---

### `dim_order` — `purchase_date_key` derivation

**Problem:** The warehouse star schema requires a `purchase_date_key` integer foreign key to `dim_date` to enable fast date-based filtering and time-intelligence calculations in SQL and Tableau.

**Decision:** Derive `purchase_date_key` from `order_purchase_timestamp` by extracting the date portion and formatting as `YYYYMMDD` integer (e.g. `2017-09-04` → `20170904`). This integer matches the `date_key` column in `dim_date` directly.

**Rationale:** Integer date keys outperform date-type joins. The `YYYYMMDD` format is self-documenting, sorts correctly without a lookup, and is a widely recognised warehouse convention.

---

### `fact_order_items` — `shipping_limit_date` outliers

**Problem:** 4 rows from a single seller have `shipping_limit_date` values in 2020, in a dataset covering only 2016–2018. The shipping deadline cannot be two or more years after the order was placed — these are clearly erroneous entries.

**Decision:** Null out `shipping_limit_date` where the value exceeds `order_purchase_timestamp` + 60 days.

**Rationale:** 60 days is a generous window that covers all legitimate shipping scenarios (median delivery time in this dataset is ~12 days). The 2020 outliers fall well outside `dim_date`'s range (2016–2019) so keeping them would cause silent join failures on date-based queries. `NULL` represents "shipping deadline unknown."

---

### `fact_order_items` — `order_id` retained as degenerate dimension

**Problem/Context:** `fact_order_items` is the primary fact table. `fact_payments` and `fact_reviews` need to join to it without going through `dim_order`, to avoid fan-out when aggregating across fact tables.

**Decision:** Retain `order_id` (natural key) as a column in `fact_order_items` alongside `order_key` (surrogate FK). Cross-fact joins between `fact_order_items`, `fact_payments`, and `fact_reviews` use `order_id`.

**Rationale:** Standard degenerate dimension pattern. Avoids double-counting (fan-out) that would occur if all three fact tables were joined through `dim_order` in a single query.

---

### `fact_payments` — Zero payment installments

**Problem:** 2 rows have `payment_installments = 0`. Zero installments is not a valid state — every payment must have at least one installment.

**Decision:** Replace `payment_installments = 0` with `1`.

**Rationale:** A value of 1 represents a single-installment payment (not split), the most logical interpretation of a zero entry. Prevents division-by-zero errors in per-installment calculations. Affects only 2 rows.

---

### `fact_payments` and `fact_reviews` — No surrogate key FK to `dim_order`

**Problem/Context:** `fact_payments` and `fact_reviews` have no FK constraint back to `dim_order` in the DDL, unlike `fact_order_items`.

**Decision:** Both tables retain `order_id` as the natural key. No surrogate `order_key` FK is added.

**Rationale:** Not all `order_id` values in `fact_payments` and `fact_reviews` have a corresponding row in `dim_order` (e.g. reviews for cancelled orders). Enforcing a FK would require dropping these legitimate rows. Joining via `order_id` string is acceptable at this data volume and is how all SQL views are written.

---

## ML Output Layer — Materialization in `03_materialize_ml_outputs.py`

*(Tableau Phase addition — see `docs/08_ml_outputs_reference.md` for full business rationale, table structure, and validated output per table. This section covers only the methodology-level decisions relevant to data trustworthiness, consistent with the rest of this document.)*

Unlike the staging and warehouse layers above, this script doesn't clean or transform source data — it derives new data (K-means clusters, Random Forest feature importances) that cannot be produced in SQL, and writes it back to the warehouse as static tables.

### Separate script, not folded into `02_load_warehouse.py`

**Problem/Context:** Four Tableau Phase findings require a trained model (K-means, Random Forest) — no SQL query or Tableau calculated field can reproduce them.

**Decision:** These outputs are produced by a third script, `python/etl/03_materialize_ml_outputs.py`, run after `02_load_warehouse.py` rather than folded into it.

**Rationale:** The script reads from warehouse views (`vw_seller_performance`, `vw_product_customer_affinity`), not raw CSVs or staging — it structurally depends on the warehouse already being populated, so it belongs downstream of both existing scripts, not inside either one. Keeps the original two-layer staging→warehouse architecture intact.

---

### `ml_` naming and `computed_at` — signalling non-live data

**Problem:** These tables are not always-current the way `vw_*` views are. A KMeans or Random Forest result is a snapshot from whenever the script last ran — reloading the warehouse without re-running this script leaves them silently stale.

**Decision:** All four output tables use an `ml_` prefix (not `vw_`), and every table carries a `computed_at` timestamp column.

**Rationale:** Makes the staleness risk visible both in the schema (naming) and in the data itself (timestamp), rather than leaving it as tribal knowledge.

---

### TRUNCATE + append, not drop/recreate

**Problem:** Pandas' `to_sql(if_exists='replace')` convenience default would drop and recreate each table on every run, silently discarding the primary key and `COMMENT ON TABLE` metadata defined in `sql/schema/03_create_ml_output_tables.sql`.

**Decision:** The script `TRUNCATE`s each table then appends fresh rows, rather than dropping and recreating.

**Rationale:** Preserves the DDL-defined structure; matches the same idempotent, re-runnable principle already established for the staging and warehouse layers above.

---

### Cluster naming derived post-hoc, not from the raw KMeans label

**Problem:** KMeans assigns integer cluster labels (`0`, `1`, `2`...) arbitrarily on every run. The same conceptual group (e.g. "Elite sellers") is not guaranteed to receive the same integer label twice.

**Decision:** A semantic `cluster_name` column (e.g. `'Elite'` / `'Non-Elite'`; `'Revenue Core'` / `'Trouble Spot'` / `'Small & Sticky'` / `'Small & Well-Reviewed'`) is derived by ranking each cluster on its defining metric after clustering, rather than reading the raw label directly. The raw `cluster_label` integer is retained in each table for audit only.

**Rationale:** Keeps `cluster_name` meaningful and stable across reruns for any query or Tableau worksheet built against these tables. Documented as a known limitation in `docs/08_ml_outputs_reference.md` that this naming logic is calibrated to the k currently found (2 for sellers, 4 for categories) and would need revisiting if a future rerun finds a different k.

---

### Seller outlier threshold: relaxed, not the stricter conventional cut

**Problem:** The statistically conventional outlier threshold (z-score > 1.0 on both revenue and quality) returned zero sellers on the actual data.

**Decision:** `ml_seller_outliers` uses a relaxed threshold (revenue z > 0.5, quality z < −0.5) instead.

**Rationale:** An empirical response to what the data actually showed, not an arbitrary loosening — chosen for operational usefulness over textbook rigor, and documented here rather than left implicit.

---

## Geolocation Coverage

Not all customer and seller zip code prefixes have a matching entry in `dim_geolocation`. Where no match exists, `geolocation_key` is `NULL`. This is expected — the geolocation source file does not provide 100% coverage of all Brazilian zip prefixes.

Rows with `NULL` geolocation_key are fully valid for all non-geographic analyses (RFM, CLV, seller performance, payment behaviour, etc.). SQL views that produce geographic output filter on `geolocation_key IS NOT NULL`.

---

## `dim_date` Range

`dim_date` is generated programmatically to cover **2016-01-01 through 2019-12-31**:
- Covers the full dataset period (September 2016 – October 2018)
- Provides buffer for `order_estimated_delivery_date` values that fall after the last order date
- The 2020 `shipping_limit_date` outliers are nulled in ETL before any date key lookup, so no 2020 dates ever reach the warehouse
