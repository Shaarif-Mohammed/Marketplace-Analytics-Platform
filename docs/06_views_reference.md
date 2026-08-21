# Views Reference
## Marketplace Analytics Platform

All views live in the `warehouse` schema and are prefixed with `vw_`. They are built on top of the warehouse dimension and fact tables and should be queried after the ETL pipeline has run successfully. All views use delivered orders only unless stated otherwise.

---

## View Index

| View | Business Question | Grain |
|---|---|---|
| `vw_rfm` | Who are the most valuable customers? | One row per `customer_unique_id` |
| `vw_clv` | What is each customer worth historically and projected? | One row per `customer_unique_id` |
| `vw_retention` | How many customers come back each month? | One row per `cohort_month × period_number` |
| `vw_seller_performance` | Which sellers are performing well or poorly? | One row per `seller_id` |
| `vw_regional_analysis` | Where is revenue and demand concentrated? | One row per `customer_state` |
| `vw_customer_health` | What is each customer's current activity status? | One row per `customer_unique_id` |
| `vw_seller_health` | How is the seller base growing and what is each seller's status? | Mixed — see Grain section |
| `vw_new_vs_returning_revenue` | What share of revenue comes from new vs returning customers? | One row per `order_month` |
| `vw_pareto_analysis` | Do 20% of customers/sellers drive 80% of revenue? | One row per `entity_id` (customer or seller) |
| `vw_delivery_experience` | How does delivery speed affect customer satisfaction? | Three grains via UNION ALL |
| `vw_product_customer_affinity` | Which categories drive the most revenue and satisfaction? | One row per `product_category_name_english` |
| `vw_payment_behaviour` | How do customers pay and does payment method affect order value? | Three grains via UNION ALL |
| `vw_review_response_intelligence` | What does the review profile look like and how fast does Olist respond? | Four grains via UNION ALL |

---

## `vw_rfm` — RFM Segmentation

**Business question:** Which customers are most valuable, and how should they be targeted?

**Grain:** One row per `customer_unique_id` (the true person identifier, not order-scoped `customer_id`).

**Reference date:** `2018-09-01` — start of the month following the last delivered order in the dataset. Consistent across all views that require a reference date.

**Logic:**
- Recency: days between last delivered order and reference date
- Frequency: count of distinct delivered orders
- Monetary: sum of order totals across all delivered orders (collapsed to order level before aggregation)
- Each dimension scored 1–5 using `NTILE(5)`. Recency is inverted (fewer days = higher score = 5)
- Segment assigned based on R and F score combination (M score not used for segmentation — only for ordering within segments)

**Segment definitions:**

| Segment | R Score | F Score |
|---|---|---|
| Champions | 5 | 5 |
| Cannot Lose Them | 1 | ≥ 4 |
| Loyal | — | ≥ 4 |
| Recent | 5 | 1 |
| Potential Loyal | ≥ 4 | ≤ 2 |
| Need Attention | ≥ 3 | ≥ 3 |
| Promising | ≥ 3 | ≤ 2 |
| At Risk | ≤ 2 | ≥ 3 |
| About to Sleep | ≤ 2 | ≤ 2 |
| Lost | else | — |

**Known limitations:**
- NTILE scoring on highly skewed frequency data (most customers ordered once) compresses segments. The Loyal segment can appear large because even a small difference in order count places customers in the top NTILE.
- The Lost segment is a defensive fallback — all R/F score combinations are covered by the nine named conditions, so this branch should never fire.

**Key columns:**
- `rfm_score` — combined score string e.g. `5-4-3` (R-F-M)
- `rfm_composite` — simple average of R, F, M scores (max 5.0)
- `segment` — human-readable segment label

---

## `vw_clv` — Customer Lifetime Value

**Business question:** What is each customer worth historically and what will they likely spend in the next 12 months?

**Grain:** One row per `customer_unique_id`.

**Logic:**
- `historical_clv` — actual total spend on all delivered orders (collapsed to order level before aggregation)
- `projected_clv_12m` — forward-looking 12-month estimate using two paths:
  - **One-time buyers:** `projected_clv_12m = avg_order_value` (conservative — assumes one repeat purchase)
  - **Repeat buyers:** `projected_clv_12m = avg_order_value × MIN(annualised_purchase_rate, 12)`
  - Purchase rate capped at 12 (monthly) to prevent inflation from customers who placed multiple orders within a very short window
- `clv_tier` — NTILE(3) on `projected_clv_12m` → High / Mid / Low

**Joins:** Joins to `vw_rfm` to bring in RFM segment for combined customer analysis.

**Known limitations:**
- Simplified projection model — not BG/NBD or Pareto/NBD. A probabilistic model would require longer purchase history than this 2-year dataset provides.
- CLV tier for one-time buyers reflects AOV potential, not purchase frequency. A high-AOV one-time buyer can land in the High tier purely because their single order was large.
- The purchase rate cap of 12 is a judgement call. Sellers (who place large volume orders) are not in this view — it covers customers only.

**Key columns:**
- `historical_clv` — confirmed spend to date
- `projected_clv_12m` — estimated next 12-month spend
- `annualised_purchase_rate` — estimated orders per year (capped at 12)
- `avg_days_between_orders` — NULL for one-time buyers

---

## `vw_retention` — Cohort Retention

**Business question:** Of customers who first bought in a given month, how many came back in subsequent months?

**Grain:** One row per `cohort_month × period_number`. All periods up to the dataset end date are present for every cohort, including periods with zero returning customers.

**Logic:**
- Cohort month = month of each `customer_unique_id`'s first delivered order
- Period number = months elapsed since cohort month (0 = acquisition month)
- A customer is retained in period N if they placed at least one delivered order N months after their cohort month
- `retention_rate_pct` = retained customers / cohort_size × 100
- `churned_from_prev_period` = retained customers in period N−1 minus retained in period N
- A complete cohort × period grid is generated so periods with zero retention appear explicitly as zero rows rather than being absent

**Known limitations:**
- Right-censoring: later cohorts (mid-2018) have fewer observable periods because the dataset ends August 2018. Low retention rates for recent cohorts are partly a data availability issue, not purely a business problem.
- Period 0 is always 100% by definition — every customer is active in their acquisition month.

**Key columns:**
- `cohort_month` — month of first purchase (DATE, first of month)
- `cohort_size` — total customers acquired in that month
- `period_number` — 0 = acquisition month, 1 = one month later, etc.
- `retained_customers` — distinct customers who purchased in this period
- `retention_rate_pct` — % of cohort still active in this period

---

## `vw_seller_performance` — Seller Scorecard

**Business question:** Which sellers are performing well across revenue, reviews, and delivery — and which need intervention?

**Grain:** One row per `seller_id`.

**Logic:**
- Revenue totals at item level; `avg_order_value` calculated at order level to avoid multi-item inflation
- On-time delivery calculated at order level (deduplicated to avoid multi-item inflation)
- Review metrics deduplicated to order grain before joining — a multi-item order contributes exactly one review score per seller
- **Performance score** (0–100) is a weighted composite:
  - 40% avg review score (normalised to 0–100 by dividing by 5)
  - 30% on-time delivery rate
  - 20% revenue percentile (NTILE 1–100)
  - 10% low cancellation rate (inverted: 100 − cancellation_rate)
- Sellers with fewer than 5 orders excluded from scoring → `performance_tier = 'Insufficient Data'`

**Performance tiers:**

| Tier | Score |
|---|---|
| Elite | ≥ 80 |
| Strong | ≥ 60 |
| Average | ≥ 40 |
| Needs Work | < 40 |
| Insufficient Data | < 5 orders |

**Known limitations:**
- The 5-order minimum threshold is a judgement call. Sellers with 1–4 orders cannot be fairly scored but are still included in the view for completeness.
- Performance score weights are subjective. Review score is weighted highest (40%) based on the finding that review score is the primary driver of platform trust.

**Key columns:**
- `on_time_rate` — % of orders delivered on or before estimated date (order-level, max 100%)
- `performance_score` — weighted composite 0–100 (NULL for Insufficient Data)
- `performance_tier` — Elite / Strong / Average / Needs Work / Insufficient Data

---

## `vw_regional_analysis` — Geographic Revenue

**Business question:** Where is customer demand and seller supply concentrated across Brazil?

**Grain:** One row per `customer_state` (27 rows — 26 states + DF).

**Logic:**
- Demand side: revenue, orders, customers, delivery metrics grouped by `customer_state` (where the buyer is). Items collapsed to order level before aggregation to prevent multi-item inflation
- Reviews deduplicated to order grain before joining to prevent fan-out
- Supply side: seller count and revenue grouped by `seller_state` (where the seller is), joined back to customer state
- `orders_per_seller` = customer state orders / seller count in that state — proxy for market underservice
- Cumulative revenue share calculated using a window function ordered by `total_revenue DESC`

**Key columns:**
- `revenue_share_pct` — this state's share of national revenue
- `cumulative_revenue_pct` — running total (useful for identifying the states needed to reach 80% revenue)
- `orders_per_seller` — high values indicate underserved markets (demand exceeds local supply)

---

## `vw_customer_health` — Customer Status Snapshot

**Business question:** What is the current activity status of every customer — are they Active, Dormant, or Lost?

**Grain:** One row per `customer_unique_id` (with at least one delivered order).

**Logic:**
- Status evaluated at dataset end date (2018-09-01)
- Active: last delivered order on or after 2018-03-01 (within 6 months)
- Dormant: last delivered order between 2017-09-01 and 2018-02-01 (6–12 months ago)
- Lost: last delivered order before 2017-09-01 (more than 12 months ago)

**Key columns:**
- `customer_unique_id` — person-level identifier
- `last_order_month` — month of most recent delivered order
- `customer_status` — Active / Dormant / Lost

---

## `vw_seller_health` — Seller Base Health

**Business question:** How is the seller base growing month by month, and what is each seller's current activity status?

**Grain:** Mixed, distinguished by `metric_type`:
- `'Monthly Trend'` — one row per `order_month × seller_type` (New / Returning). Complete calendar month grid, zero-filled where a type had no sellers in a given month
- `'Status Snapshot'` — one row per `seller_id` covering all 3,095 registered sellers including those with no delivered orders

Filter by `metric_type` to work with one grain at a time.

**Logic:**
- New seller: first ever delivered order in that month
- Returning seller: has at least one prior delivered order before this month
- Items collapsed to (seller, order) grain before aggregation to correctly handle split-seller orders
- Status evaluated at dataset end (2018-09-01): Active (last sale ≥ 2018-03-01), Dormant (last sale ≥ 2017-09-01), Inactive (last sale before 2017-09-01), Never Active (no delivered orders ever)
- MoM growth calculated per seller type against the zero-filled grid

**Key columns (Monthly Trend rows):**
- `order_month`, `seller_type`, `seller_count`, `order_count`, `total_revenue`, `revenue_share_pct`, `total_active_sellers`, `mom_seller_growth_pct`

**Key columns (Status Snapshot rows):**
- `seller_id`, `seller_status`, `last_sale_month`

---

## `vw_new_vs_returning_revenue` — Revenue Mix

**Business question:** What percentage of monthly revenue comes from new vs returning customers, and is the returning share growing?

**Grain:** One row per `order_month`. Complete calendar month grid including months with zero activity (e.g. November 2016).

**Logic:** Same new/returning definitions as `vw_customer_health` monthly trend. Designed for Tableau — new and returning metrics in separate columns rather than separate rows, making it easier to build dual-axis charts and calculated fields. MoM growth and rolling averages are computed against a complete calendar grid so gaps between active months do not produce misleading comparisons.

**Key columns:**
- `new_revenue_pct` / `returning_revenue_pct` — revenue mix each month
- `returning_revenue_mom_growth_pct` — month-over-month change in returning revenue
- `returning_pct_3m_rolling_avg` — 3-month rolling average of returning revenue share (smooths monthly noise)
- `revenue_per_new_customer` — revenue efficiency of customer acquisition

---

## `vw_pareto_analysis` — Revenue Concentration

**Business question:** Does the 80/20 rule hold — do 20% of customers and sellers drive 80% of revenue?

**Grain:** Two entity types unified via UNION ALL — one row per `customer_unique_id` and one row per `seller_id`. Filter by `entity_type` to analyse each separately.

**Logic:**
- Entities ranked by total revenue descending within each entity type
- `cumulative_revenue_pct` — running revenue total from highest to lowest earner
- `cumulative_pct_of_entities` — what % of all entities have been counted so far. Uses ROW_NUMBER (not RANK) so the x-axis increments strictly even when multiple entities tie on revenue
- `is_top_20_pct` — TRUE if this entity falls within the top 20% by count
- `is_within_80_pct_revenue` — TRUE if this entity is needed to reach 80% cumulative revenue

**Key finding context:**
- Customer Pareto: ~49% of customers drive 80% of revenue (flatter than 80/20 — no dominant whale segment)
- Seller Pareto: ~19% of sellers drive 80% of revenue (tighter than 80/20 — classic marketplace power law)

---

## `vw_delivery_experience` — Delivery Performance

**Business question:** How fast are orders delivered and how strongly does delivery performance drive review scores?

**Grain:** Three result sets via UNION ALL. Filter by `dimension`:
- `'Overall'` — one row, national summary
- `'By State'` — one row per customer state
- `'On-time vs Late'` — two rows comparing delivery status groups

**Logic:**
- Calculated at order level (deduplicated from item level to prevent multi-item inflation)
- On-time = `order_delivered_customer_date ≤ order_estimated_delivery_date`
- Early = delivered 2+ days before estimated date
- `days_vs_estimate` — negative means delivered ahead of schedule
- Delivery days = days from `order_purchase_timestamp` to `order_delivered_customer_date`
- Median calculated using `PERCENTILE_CONT(0.5)`

**Key finding context:**
- National avg delivery: 12.1 days, median 10 days
- On-time deliveries avg review: 4.29 vs late deliveries: 2.57 — 1.72 point gap
- 88.77% of orders delivered early (Olist systematically under-promises on estimates)

---

## `vw_product_customer_affinity` — Category Performance

**Business question:** Which product categories drive the most revenue, and which have satisfaction problems?

**Grain:** One row per `product_category_name_english` (74 categories including 'uncategorised').

**Logic:**
- NULL English category names grouped as `'uncategorised'`
- Revenue and volume metrics at item level; delivery days deduplicated to (category, order) grain to prevent multi-item orders over-weighting the average
- Review metrics deduplicated to order grain — a multi-item order in one category contributes exactly one review score. For orders spanning multiple categories, the review is attributed to the category of the highest-value item
- `category_repeat_rate_pct` — customers who placed 2+ orders containing this category / total unique customers in category
- `top_customer_state` — most frequent customer state for this category (`DISTINCT ON` pattern)
- Revenue tiers: High (≥5% revenue share), Mid (1–5%), Long Tail (<1%)

**Key columns:**
- `freight_pct_of_revenue` — high values indicate heavy/bulky categories where shipping erodes value
- `category_repeat_rate_pct` — category-level loyalty proxy
- `revenue_tier` — High Revenue / Mid Revenue / Long Tail

---

## `vw_payment_behaviour` — Payment Patterns

**Business question:** How do customers pay, and does instalment usage correlate with higher order values?

**Grain:** Three result sets via UNION ALL. Filter by `dimension`:
- `'By Payment Type'` — one row per payment type
- `'By Instalment Band'` — one row per instalment band (1, 2-3, 4-6, 7-12, 12+)
- `'Cross'` — one row per payment_type × instalment_band (for heatmap)

**Logic:**
- Item totals pre-aggregated to order level before joining payments — prevents fan-out from multi-item orders
- For orders with multiple payment methods, the lowest available sequential payment is used as the primary type. This avoids double-counting orders
- Revenue metrics use delivered orders only; payment type distribution uses all orders (payment intent is valid regardless of delivery outcome)
- Instalment bands: 1 (Single), 2-3, 4-6, 7-12, 12+
- Boleto, voucher, and debit card are always single-instalment by definition (only credit card has multi-instalment)

**Key finding context:**
- Credit card: 76.93% of orders, avg 3.51 instalments, only 33% single instalment
- Higher instalment bands consistently show higher avg order values (1 instalment: 120.24 BRL → 7-12 instalments: 332.71 BRL)

---

## `vw_review_response_intelligence` — Review Intelligence

**Business question:** What does the review profile look like and is Olist responding to negative reviews faster?

**Grain:** Four result sets via UNION ALL. Filter by `dimension`:
- `'Score Distribution'` — one row per review_score (1–5)
- `'Response Time'` — one row per review_score with avg response hours
- `'By Score Band'` — three rows: Positive (4-5), Neutral (3), Negative (1-2)
- `'By Category'` — one row per product category

**Logic:**
- Deduplicated to `review_id` grain to prevent fan-out from multi-item orders. For orders spanning multiple categories, the review is attributed to the category of the highest-value item
- Response time = hours between `review_creation_date` and `review_answer_timestamp`
- Score bands: Positive ≥ 4, Neutral = 3, Negative ≤ 2
- `has_comment` = TRUE if `review_comment_message` is not NULL

**Important note on review text:** `review_comment_title` and `review_comment_message` are stored in the warehouse but not analysed in this view. NLP and sentiment analysis on review text is reserved for a separate future AI-layer project.

**Key finding context:**
- Bimodal distribution: 57.83% 5-star, 11.46% 1-star — strong reactions dominate
- Response time nearly identical across scores (71–77 hours) — Olist does not prioritise negative review responses
- 1-star reviews have 76.59% comment rate vs 35.91% for 5-star — negative customers explain themselves far more
