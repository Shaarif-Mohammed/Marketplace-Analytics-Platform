# Data Assessment & Quality Report
## Marketplace Analytics Platform

| | |
|---|---|
| **Source Notebooks** | `01_data_assessment.ipynb`, `02_data_quality_check.ipynb`, `03_exploratory_data_analysis.ipynb` |

---

## 1. Dataset Overview

| Dataset | Rows | Columns | Duplicate Rows | Total Nulls |
|---|---|---|---|---|
| orders | 99,441 | 8 | 0 | 4,447 |
| customers | 99,441 | 5 | 0 | 0 |
| order_items | 112,650 | 7 | 0 | 0 |
| payments | 103,886 | 5 | 0 | 0 |
| reviews | 99,224 | 7 | 0 | 146,188 |
| products | 32,951 | 9 | 0 | 4,460 |
| sellers | 3,095 | 4 | 0 | 0 |
| geolocation | 1,000,163 | 5 | 261,831 | 0 |
| category_translation | 71 | 2 | 0 | 0 |

**Date range:** September 2016 — October 2018 (confirmed across all timestamp columns)

**Key structural observations:**

- `geolocation` is the only table with duplicate rows (261,831 / 26.2%). This is expected — the file logs multiple geocoded addresses per zip code prefix rather than one canonical row per prefix. It is not a data corruption issue.
- `reviews` accounts for the majority of null values, driven entirely by optional free-text fields (`review_comment_title` and `review_comment_message`) which customers are not required to complete.
- `orders` nulls are entirely in delivery and approval timestamp columns, explained by non-delivered order statuses (canceled, unavailable, processing, etc.) where those events never occurred.
- No duplicate rows exist in any table outside of `geolocation`. All foreign key relationships are fully intact — zero orphaned records across all six checked relationships.

---

## 2. Key Structural Findings

### 2.1 Customer Identity

`customer_id` is order-scoped — Olist generates a new `customer_id` for every order, even for returning customers. This means `customer_id` is effectively 1:1 with orders (99,441 unique values across 99,441 rows), not 1:1 with people. The true person-level identifier is `customer_unique_id`, which has 96,096 distinct values — confirming approximately 3,345 real customers placed more than one order. All customer-level analysis in this project uses `customer_unique_id`.

### 2.2 Order Status Distribution

97% of orders (96,478) are `delivered`. The remaining 3% are split across `shipped`, `canceled`, `unavailable`, `invoiced`, `processing`, `created`, and `approved`. Non-delivered orders are retained in the warehouse — they are real orders and contribute to order-status analysis, even though they are naturally excluded from delivery-time and revenue metrics.

### 2.3 Payment Behaviour

The dataset reflects Brazil's strong installment payment culture (`parcelamento`). Average installments per order: 2.85. Credit card is the dominant payment type (74% of payment records), followed by boleto (bank slip). A small number of orders use split payment types — e.g. a voucher covering part of the order value with a credit card covering the remainder — resulting in multiple payment rows per `order_id`.

### 2.4 Review Distribution

Review scores are strongly skewed toward positive ratings: median score is 5, mean is 4.09. 88% of reviews have no title and 59% have no comment — both fields are optional in Olist's post-delivery survey. Review text is stored in the warehouse for future NLP analysis.

### 2.5 Geographic Concentration

São Paulo (`SP`) dominates across both customers (41,746 / 42%) and sellers (1,849 / 60%), consistent with its position as Brazil's largest economic centre. Sellers are present in 23 of Brazil's 27 states, while customers are distributed across all 27.

---

## 3. Numeric Profile Summary

Key observations from descriptive statistics across all meaningful numeric columns:

| Column | Mean | Median | Notable |
|---|---|---|---|
| `price` | BRL 120.65 | BRL 74.99 | Right-skewed; max BRL 6,735 (confirmed legitimate) |
| `freight_value` | BRL 19.99 | BRL 16.26 | Right-skewed; min BRL 0.00 (valid — some free shipping) |
| `payment_value` | BRL 154.10 | BRL 100.00 | Right-skewed; max BRL 13,664 (confirmed legitimate bulk order) |
| `payment_installments` | 2.85 | 1.00 | Heavy right tail; max 24 installments |
| `review_score` | 4.09 | 5.00 | Left-skewed; majority 5-star ratings |
| `product_weight_g` | 2,276g | 700g | Wide variance reflecting category breadth; 4 products have weight = 0 (data entry gap) |

---

## 4. Data Quality Findings

All 12 findings below were identified during systematic quality investigation. Each has a documented decision determining how it is handled in the ETL pipeline.

**Severity definitions:**
- **Low** — affects a small number of rows, no material impact on aggregate analysis; requires a targeted cleaning rule
- **None** — expected behavior or confirmed legitimate; no action required

---

| # | Finding | Affected Rows | Severity | ETL Decision |
|---|---|---|---|---|
| 1 | `shipping_limit_date` — 4 rows from a single seller have dates in 2020, ~2 years past the dataset's last order date | 4 | Low | Cap or null out values beyond a reasonable bound in ETL |
| 2 | Geolocation coordinates outside Brazil — 31 rows land in Argentina, Portugal, Mexico, and the Philippines due to a geocoding name-collision bug | 31 | Low | Exclude using bounding box filter (lat -34 to +6, lng -75 to -32) in ETL |
| 3 | `payment_installments` = 0 — 2 rows have zero installments with no `payment_sequential` = 1 row for the same order | 2 | Low | Set to 1 (logical minimum) in ETL |
| 4 | `product_weight_g` = 0 — 4 products in `cama_mesa_banho` category have zero weight, all otherwise complete listings | 4 | Low | Null out or impute using category median weight in ETL |
| 5 | Extreme values in `price` and `payment_value` — max item price BRL 6,735, max payment BRL 13,664 | — | None | Confirmed legitimate: high-end electronics, luxury goods, and bulk purchases. No action required |
| 6 | 2 product categories missing English translation — `pc_gamer` and `portateis_cozinha_e_preparadores_de_alimentos` affect 13 products | 13 | Low | Manual mapping added in ETL: `pc_gamer` → `gaming_pc`, `portateis_cozinha_e_preparadores_de_alimentos` → `portable_kitchen_food_preparators` |
| 7 | `review_id` fan-out — 814 review IDs are attached to more than one `order_id` | 1,603 | None | Expected behavior: Olist attaches one review to all orders from a split-seller checkout. `fact_reviews` grain is one row per `order_id`. Always use `COUNT(DISTINCT review_id)` when counting reviews |
| 8 | 1 delivered order has no payment record — order value BRL 143.46, likely an early-platform logging gap | 1 order | Low | Left as-is. Revenue metrics derived from `fact_payments` will understate total revenue by BRL 143.46 vs `fact_order_items`. Discrepancy documented in `docs/05_etl_methodology.md` |
| 9 | 775 orders have no items in `order_items` — all are non-fulfilled statuses (unavailable, canceled, etc.) | 775 | None | Expected behavior. Order-level counts and item-level counts will not match by design |
| 10 | Timestamp sequence violations — 1,359 orders (1.39%) have `order_delivered_carrier_date` before `order_approved_at`; 23 orders have carrier date after customer delivery date | 1,382 | Low | All delivery-time metrics use end-to-end duration (`order_purchase_timestamp` → `order_delivered_customer_date`) only. Intermediate carrier timestamps not used in any metric |
| 11 | 8 delivered orders are missing `order_delivered_customer_date` — isolated carrier scan failures across 2017–2018 | 8 | Low | Accepted. These orders silently drop from delivery-time calculations. Documented in `docs/05_etl_methodology.md` |
| 12 | No negative values found in any numeric quantity column (price, freight, payment value, dimensions, weight) | — | None | Confirmed explicitly. No cleaning rule required |

---

## 5. Overall Assessment

The Olist dataset is of **high quality** for a real-world e-commerce dataset of this size and complexity. No finding is severe enough to materially distort any aggregate analysis. The relational structure is clean — all foreign key relationships hold, no duplicate rows exist outside of geolocation, and all identifier columns behave as expected for their role.

The most consequential finding for downstream analysis is the `customer_id` / `customer_unique_id` distinction (Section 2.1) — misusing `customer_id` for customer-level analysis would make every customer appear to be a first-time buyer, silently invalidating RFM, CLV, and retention metrics. All analytical views and notebooks in this project use `customer_unique_id` consistently.

All cleaning rules identified above are implemented in `python/etl/load_warehouse.py`.

---

*Full investigation detail, diagnostic code, and cell-by-cell findings are in `01_data_assessment.ipynb`, `02_data_quality_check.ipynb`, and `03_exploratory_data_analysis.ipynb`.*
