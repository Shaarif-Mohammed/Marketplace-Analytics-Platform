# ML Outputs Reference
## Marketplace Analytics Platform

All ML outputs live in the `warehouse` schema and are prefixed with `ml_`, distinguishing them from the `vw_` views documented in `06_views_reference.md`: a view is always current, an `ml_` table is a snapshot from the last time `python/etl/03_materialize_ml_outputs.py` was run. Create them via `sql/schema/03_create_ml_output_tables.sql` before the first script run, and re-populate by re-running the script any time the underlying warehouse data changes materially. All four require a trained model (K-means or Random Forest via scikit-learn) — computation neither SQL nor Tableau can perform on its own.

---

## Why These Exist (and Why Only These Four)

Four analytical notebooks (05–08) produced roughly a dozen notebook-only outputs that don't exist as SQL views — cohort heatmaps, a CLV outlier list, a Gini/Lorenz curve, macro-region groupings, seller and category clusters, seller outlier flags, and Random Forest feature importances, among others (see `tableau_planning_reference.md`, Section 3). Tableau can only visualize what's queryable in Postgres, so every one of those outputs had to be individually triaged: rebuild as a live SQL view, build live inside Tableau as a calculated field or table calculation, or materialize as a static table.

Most of them didn't need this treatment. A cohort heatmap is just a pivoted crosstab — Tableau does that natively off `vw_retention`. A Lorenz curve is a running-sum table calculation, better left live in Tableau so it stays filter-responsive. A CLV outlier list is a percentile filter Tableau computes on its own. The first-purchase-category and late-delivery findings also needed genuinely new logic, but nothing beyond a `ROW_NUMBER()` window function — plain SQL, not a trained model. Both were built as their own views (`vw_first_purchase_category_repeat`, `vw_late_delivery_repeat_cohort`) and later dropped from the warehouse when their worksheets were cut from the final dashboard build — but the underlying point holds regardless: needing new logic doesn't by itself mean needing materialization.

These four tables are different: **they are the only outputs that require a trained model — K-means or Random Forest — with no SQL or Tableau-native equivalent.** Postgres has no clustering or ensemble-learning capability, and a Tableau calculated field can't fit a model either. If these findings were going to appear on a dashboard at all, materialization was the only path.

The effort was worth it because each of these four carries a finding that materially changes the story the SQL-only views tell on their own, not just an interesting footnote:

- **`ml_seller_clusters`** — shows SQL's four-tier `performance_tier` doesn't reflect a real structural break in the data; the actual dividing line is Elite vs. everyone else, and 71.6% of "Strong"-tier sellers behave statistically like the weaker group.
- **`ml_seller_outliers`** — the composite performance score's revenue weighting can let a genuinely poor-quality seller buy their way into a respectable tier; this table names the specific sellers that happens to.
- **`ml_category_clusters`** — shows the categories that drive revenue and the categories that build customer loyalty are almost entirely different sets, a finding no single-metric SQL view could surface.
- **`ml_review_score_feature_importance`** — quantifies, in one number, that delivery time so thoroughly dominates review score (81% of model importance) that freight cost, category, state, and payment type collectively barely register — arguably the single most load-bearing number in the whole analysis.

Leaving any of these four Tableau-invisible would mean the dashboard suite told a measurably less accurate story than the notebooks already know.

---

## Design Decisions

These decisions apply specifically to this materialization layer and diverge from the `vw_*` view pattern for good reason — worth calling out rather than leaving implicit.

| Decision | Choice | Why |
|---|---|---|
| Naming prefix | `ml_` instead of `vw_` | Signals at a glance that a table is a static snapshot, not always-current — a real operational difference a view doesn't have |
| Schema | Same `warehouse` schema, not a separate one | A dedicated schema is more textbook-correct, but adds real friction (Tableau connection scope, cross-schema grants) for 4 small tables on a solo local Postgres instance — not worth it at this scale |
| Staleness tracking | `computed_at TIMESTAMP` on every table | The concrete mechanism marking these as point-in-time — re-running the ETL without re-running `03_materialize_ml_outputs.py` leaves these tables silently stale |
| Refresh mechanism | `TRUNCATE` + append, not `DROP`/recreate | Preserves the DDL-defined constraints and `COMMENT ON TABLE` metadata; only the DDL script should recreate table structure |
| Cluster naming | Semantic name (`'Elite'`, `'Revenue Core'`, etc.) derived post-hoc by rank on the defining metric, not the raw KMeans integer label | KMeans assigns `0`/`1`/`2`... arbitrarily on every run — the raw label isn't guaranteed to mean the same thing twice. The semantic name stays correct regardless of label order. |
| Outlier threshold | Relaxed (revenue z > 0.5, quality z < -0.5), not the stricter 1.0/1.0 | The strict threshold returned zero sellers on the actual data — an empirical finding, not an arbitrary relaxation. Documented as a limitation below, not hidden. |
| Feature-importance table shape | `train_r2`/`test_r2` repeated on every row (denormalized) | Normally avoided, but harmless at 5 rows and saves a join for a Tableau caption/subtitle that needs the R² alongside the bars |
| Script placement | `python/etl/03_materialize_ml_outputs.py`, separate from `load_olist_data.py` | Depends on the warehouse already being populated — it queries views, not raw CSVs, so it belongs downstream of the main ETL, not inside it |

---

## Table Index

| Table | Business Question | Grain | Refresh |
|---|---|---|---|
| `ml_seller_clusters` | Does unsupervised clustering agree with SQL's manual seller tiers? | One row per scored seller (≥5 orders) | Script |
| `ml_seller_outliers` | Which specific sellers combine high revenue with poor quality? | One row per flagged seller (~10) | Script |
| `ml_category_clusters` | Do revenue-driving categories differ from loyalty-driving ones? | One row per category (74) | Script |
| `ml_review_score_feature_importance` | What single factor best explains review score? | One row per feature group (5) | Script |

---

## `ml_seller_clusters` — Seller Quality Clusters

**Business question:** Does unsupervised clustering on seller quality and revenue agree with SQL's manually-defined `performance_tier`, or reveal a different structure?

**Grain:** One row per scored seller (`total_orders >= 5`, matching `vw_seller_performance`'s scoring population).

**Added for:** Tableau Phase — Seller Performance dashboard (Tier vs. Cluster Agreement Matrix, Revenue-at-Risk comparison, Quality vs. Revenue Scatter worksheets).

**Logic:**
- K-means on `avg_review_score`, `on_time_rate`, `total_revenue` (log-transformed — heavily right-skewed), and `cancellation_rate`, `StandardScaler`-normalized
- `k` chosen automatically by silhouette score across k=2–8 (found: k=2)
- `cluster_name` assigned post-hoc: the cluster with the higher average `avg_review_score` is `'Elite'`, the other `'Non-Elite'`

**Known limitations:**
- The naming logic assumes a binary split. It won't error if a future re-run's silhouette search selects k > 2, but every cluster beyond the top-quality one collapses into `'Non-Elite'`, losing resolution — worth revisiting if `silhouette_k` is ever reported as anything other than 2
- `cluster_label` (the raw integer) is not stable across reruns — always use `cluster_name` for analysis or filtering

**Key columns:**
- `cluster_name` — `'Elite'` / `'Non-Elite'`
- `performance_tier` — carried over from `vw_seller_performance` for direct comparison
- `silhouette_k` — k actually selected on this run, for audit

**Validated output (live run, 2026-07-13):** k=2 and cluster sizes confirmed exact — Elite 1,474 sellers, Non-Elite 320 sellers. The tier-crosstab percentages (Elite ~98.4% / Strong ~71.6%) reproduce the notebook's finding but haven't yet been independently re-queried against this table's `performance_tier` column — would need a `GROUP BY performance_tier, cluster_name` to fully confirm those two specific numbers.

---

## `ml_seller_outliers` — High-Revenue / Low-Quality Sellers

**Business question:** Which specific sellers combine above-average revenue with below-average quality, warranting individual account-management follow-up?

**Grain:** One row per flagged near-outlier seller (expected ~10 rows; not fixed — fluctuates with the data).

**Added for:** Tableau Phase — Seller Performance dashboard (Outlier Seller Detail drill-through).

**Logic:**
- Z-scores computed within the same scored-seller population as `ml_seller_clusters`, on `total_revenue`, `avg_review_score`, `on_time_rate`, `cancellation_rate`
- Composite `quality_z = (review_z + on_time_z − cancellation_z) / 3`
- Flagged if `revenue_z > 0.5 AND quality_z < -0.5`

**Known limitations:**
- The 0.5/0.5 threshold is a judgment call, not a statistically derived cutoff. The stricter, more conventional 1.0/1.0 threshold returned zero sellers on this dataset — relaxed was chosen for operational usefulness, not statistical rigor
- Row count is not fixed by the DDL and will vary run to run as the underlying data changes

**Key columns:**
- `revenue_z`, `quality_z` — the two flagging dimensions
- `seller_state` — included for quick geographic context without a join

**Validated output (live run, 2026-07-13):** 10 near-outliers confirmed, same seller IDs and order as the notebook. Total revenue exposure BRL 312,989.25 — matches the notebook's figure to the cent. Sharpest flag: seller `b1b3948701c5c72445495bd161b83a4c` (SP), quality z ≈ −4.15, 35.71% on-time rate, 11.11% cancellation, revenue z ≈ 0.69 on BRL 21,924.25 revenue — the clearest individual account-management flag in the dataset.

---

## `ml_category_clusters` — Category Groupings

**Business question:** Do product categories naturally group by revenue, review score, freight burden, and repeat rate — and do revenue-driving categories differ from loyalty-driving ones?

**Grain:** One row per product category (expected 74 rows, matching `vw_product_customer_affinity`).

**Added for:** Tableau Phase — Product & Category dashboard (Category Cluster Map worksheet).

**Logic:**
- K-means on `total_revenue` (log-transformed), `avg_review_score`, `freight_pct_of_revenue`, `category_repeat_rate_pct`, `StandardScaler`-normalized
- `k` chosen automatically by silhouette score across k=2–8 (found: k=4)
- `cluster_name` assigned post-hoc, sequentially: highest-revenue cluster → `'Revenue Core'`; of what's left, lowest review score → `'Trouble Spot'`; of what's left, highest repeat rate → `'Small & Sticky'`; whatever remains → `'Small & Well-Reviewed'`

**Known limitations:**
- The naming logic is calibrated to this data's k=4 finding, not fully k-agnostic. If a future re-run's silhouette search selects k < 4, the naming step raises an error (nothing left to assign to the fourth name); if k > 4, the extra cluster(s) beyond the four named ones get a null `cluster_name`. Worth revisiting if `silhouette_k` is ever reported as anything other than 4
- `cluster_label` (the raw integer) is not stable across reruns — always use `cluster_name`

**Key columns:**
- `cluster_name` — the four semantic groupings
- `category_repeat_rate_pct` — the dimension that most separates loyalty-driving from revenue-driving clusters

**Validated output (live run, 2026-07-13):** All 74 categories confirmed, cluster sizes exact (Revenue Core 30, Trouble Spot 9, Small & Sticky 4, Small & Well-Reviewed 31). Cluster membership matches the notebook exactly — `office_furniture` lands in `'Trouble Spot'` alongside `home_confort`, `fixed_telephony`, `audio`, `fashion_male_clothing`, `party_supplies`, `portable_kitchen_food_preparators`, `gaming_pc`, and `security_and_services`; `'Small & Sticky'` is exactly `home_appliances`, `arts_and_craftmanship`, `diapers_and_hygiene`, `home_comfort_2` — bit-for-bit identical membership, not just matching counts.

---

## `ml_review_score_feature_importance` — Review Score Driver Analysis

**Business question:** Of delivery time, freight cost, category, state, and payment type, which factor most explains variation in review score?

**Grain:** One row per feature group (5 rows: `delivery_days`, `freight_pct`, `category`, `state`, `payment_type`). Importances sum to 1.0 across all rows within a `computed_at` run.

**Added for:** Tableau Phase — Product & Category dashboard (Feature Importance / Delivery Dominance worksheet).

**Logic:**
- Random Forest Regressor (200 trees, max depth 8) predicting `review_score` from an order-level dataset built fresh via SQL: delivery days, freight %, dominant category (top 15 + `'other'`), customer state (top 10 + `'other'`), and payment type, one-hot encoded
- 80/20 train/test split; feature importances summed by original feature group across one-hot dummies (so all `category_*` dummies roll up into a single `category` row, etc.)

**Known limitations:**
- Test R² is modest (~0.15) — the model explains some but not most of review score variation; delivery time's dominance is about relative importance among the tested features, not that the model fits well overall
- Category and state are capped to their top 15/10 most frequent values (rest grouped as `'other'`) to keep the model interpretable, which slightly understates the true importance of long-tail categories and states

**Key columns:**
- `importance_pct` — convenience column (raw `importance` × 100) for direct use as a Tableau bar label
- `train_r2` / `test_r2` — model fit context, repeated on every row

**Validated output (live run, 2026-07-13):** train R²=0.1834, test R²=0.1491 — exact match to the notebook. `delivery_days` 80.85%, `state` 7.17%, `freight_pct` 6.59%, `category` 4.24%, `payment_type` 1.15% (sums to 100.00%). Note `state` edges out `freight_pct` at full precision — the notebook's 2-decimal display rounded both to 7%, reading as a tie that isn't quite real.
