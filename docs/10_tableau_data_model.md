# Tableau Data Model — Final
## Marketplace Analytics Platform

## Introduction

This document records the data model as actually built, not as originally planned — several worksheets were cut, added, or moved between data sources during the build, and this reflects the final state.

The model is split into **9 separate Tableau data sources** rather than one consolidated source, for two reasons. First, the underlying tables span genuinely different grains — customer, seller, category, state, order — and no worksheet ever needs to cross-filter between grains that don't naturally relate (a seller-grain table has no reason to join to a category-grain one). Second, Tableau itself enforces this structurally: every table inside a single data source must relate to at least one other table in that same source, so tables with nothing to relate to can't coexist with a fully-connected cluster in one source.

This produces two kinds of data source: **relationship islands**, where 2+ tables share a common key and are joined, and **standalone sources**, single tables used alone because nothing else shares their grain. Both are documented below with their grain, connection fields, and every downstream visual that reads from them.

---

## 1. Core Star Schema

**Tables:** `fact_order_items`, `dim_order`, `dim_date`, `dim_customer`, `dim_product`, `fact_payments`

**Grain:** One row per order line item (`fact_order_items` grain), enriched with order, date, customer, product, and payment attributes.

**Connected on:**
- `fact_order_items` ↔ `dim_order`: `order_id`
- `dim_order` ↔ `dim_date`: `purchase_date_key` = `date_key`
- `dim_order` ↔ `dim_customer`: `customer_key`
- `fact_order_items` ↔ `dim_product`: `product_key`
- `dim_order` ↔ `fact_payments`: `order_id`

**Visuals:**
- Days to Second Purchase

---

## 2. Customer Analytics

**Tables:** `vw_rfm`, `vw_clv`, `vw_customer_health`

**Grain:** One row per customer (`customer_unique_id`).

**Connected on:** `customer_unique_id` (all 3 tables).

**Visuals:**
- RFM Segment Distribution (Drill-Through)
- RFM × CLV Tier Crosstab
- CLV Distribution
- New Customers Over Time
- Revenue Mix by Customer Segment
- KPI - Active Customer %
- KPI - Repeat Purchase Rate
- **Drill-Through - Segment Deep-Dive** (destination dashboard, triggered from RFM Segment Distribution):
  - Drill-Through - Total Spend
  - Drill-Through - Total Customers
  - Drill-Through - Total Orders
  - Drill-Through - Avg Order Value
  - Drill-Through - Avg Days Since Last Order
  - Drill-Through - Avg Orders per Customer
  - Drill-Through - Repeat Rate
  - Drill-Through - Avg Customer Lifespan
  - Drill-Through - Segment Value Concentration
  - Drill-Through - Segment vs Platform Deviation

---

## 3. Seller Analytics

**Tables:** `vw_seller_performance`, `ml_seller_clusters`, `ml_seller_outliers`, `vw_seller_health`

**Grain:** One row per seller (`seller_id`).

**Connected on:** `seller_id` (all 4 tables) — `vw_seller_health` only matches on its Status Snapshot rows.

**Visuals:**
- Quality vs Revenue Scatter
- Tier vs Cluster Agreement Matrix
- Revenue at Risk: Manual vs Cluster
- Tooltip - Quality vs Revenue Scatter Plot
- KPI - Active Seller %
- KPI - Average Order Value
- KPI - Total Orders
- KPI - Avg Review Score

---

## 4. Category Analytics

**Tables:** `ml_category_clusters`, `vw_product_customer_affinity`, `vw_review_response_intelligence`

**Grain:** One row per product category.

**Connected on:** `category` — except `vw_review_response_intelligence`, which connects on `dimension_value` (only its "By Category" rows match).

**Visuals:**
- Category Cluster Distribution
- Order Volume vs Revenue per Category
- Top Revenue Driving Categories
- Top 5 vs Bottom 5 by Review Score
- Category Revenue Concentration

---

## 5. Geographic

**Tables:** `vw_regional_analysis`, `dim_geolocation`

**Grain:** One row per state, related to many zip-code-prefix rows in `dim_geolocation` (one-to-many).

**Connected on:** `state`.

**Visuals:**
- Revenue / On-Time Rate / Avg Delivery Days Map
- Seller Supply Gap by State
- Delivery Days by Macro-Region
- Revenue vs Delivery Performance Quadrant

---

## 6. New vs Returning Revenue (standalone)

**Table:** `vw_new_vs_returning_revenue`

**Grain:** One row per month.

**Connected on:** — (single table, no relationship)

**Visuals:**
- KPI - Total Revenue
- Monthly Revenue Trend

---

## 7. Retention (standalone)

**Table:** `vw_retention`

**Grain:** One row per cohort month × period number.

**Connected on:** — (single table, no relationship)

**Visuals:**
- Cohort Retention Heatmap

---

## 8. Delivery Experience (standalone)

**Table:** `vw_delivery_experience`

**Grain:** One row per dimension × dimension value (mixed — national overall, by state, on-time vs late).

**Connected on:** — (single table, no relationship)

**Visuals:**
- KPI - On-Time Delivery
- Review Score vs Delivery Speed

---

## 9. Pareto Analysis (standalone)

**Table:** `vw_pareto_analysis`

**Grain:** One row per entity × entity type (customer or seller).

**Connected on:** — (single table, no relationship)

**Visuals:**
- Seller Revenue Concentration (Lorenz Curve)

---

## Conclusion

The final model uses 9 data sources across 21 tables, powering 41 named visuals (including the 10 elements of the Drill-Through - Segment Deep-Dive dashboard). The `Feature Importance` data source (`ml_review_score_feature_importance`) was removed from the model — its planned worksheet was cut during the build, leaving it with no downstream visual. `vw_first_purchase_category_repeat` and `vw_late_delivery_repeat_cohort` were also dropped from the warehouse (and this model) — their worksheets were cut before the final build.
