# Data Dictionary
## Marketplace Analytics Platform

---

## Data Overview

| | |
|---|---|
| **Source** | Olist Brazilian E-Commerce Public Dataset |
| **Publisher** | Olist Store |
| **Platform** | Kaggle |
| **Dataset Link** | https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce |
| **License** | Creative Commons Attribution Non-Commercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0) |
| **Coverage** | September 2016 — October 2018 |
| **Total Orders** | ~100,000 |
| **Source Tables** | 9 CSV files |
| **Geography** | Brazil — 27 states |

This dataset is a real, anonymized export of Olist's transactional data. All customer and seller identifiers have been anonymized using cryptographic hashing. No personally identifiable information (PII) is present. The data captures the full order lifecycle — from customer purchase through seller fulfillment, logistics, payment settlement, and post-delivery review.

---

## Table of Contents

1. [olist_orders_dataset](#1-olist_orders_dataset)
2. [olist_customers_dataset](#2-olist_customers_dataset)
3. [olist_order_items_dataset](#3-olist_order_items_dataset)
4. [olist_order_payments_dataset](#4-olist_order_payments_dataset)
5. [olist_order_reviews_dataset](#5-olist_order_reviews_dataset)
6. [olist_products_dataset](#6-olist_products_dataset)
7. [olist_sellers_dataset](#7-olist_sellers_dataset)
8. [olist_geolocation_dataset](#8-olist_geolocation_dataset)
9. [product_category_name_translation](#9-product_category_name_translation)

---

## 1. olist_orders_dataset

**Description:** The central order header table. One row per order. Contains the order's status and all lifecycle timestamps from purchase through delivery. All other transactional tables join back to this table via `order_id`.

**Rows:** 99,441 | **Primary Key:** `order_id`

| Column | Data Type | Description |
|---|---|---|
| `order_id` | VARCHAR | Unique identifier for each order. Primary key of this table. Referenced as a foreign key in `order_items`, `payments`, and `reviews`. |
| `customer_id` | VARCHAR | Identifier linking this order to a customer record in `olist_customers_dataset`. **Olist quirk:** this is an order-scoped identifier — a new `customer_id` is generated for each order, even for returning customers. It is not a stable personal identifier. Use `customer_unique_id` (from the customers table) for any analysis involving repeat customers. |
| `order_status` | VARCHAR | Current status of the order in the fulfillment lifecycle. See status definitions below. |
| `order_purchase_timestamp` | TIMESTAMP | Date and time the customer placed the order. The earliest event in the order lifecycle and the most reliable timestamp — always populated. |
| `order_approved_at` | TIMESTAMP | Date and time the payment was approved. Null for orders that were canceled or became unavailable before payment was confirmed (160 null values). |
| `order_delivered_carrier_date` | TIMESTAMP | Date and time the seller handed the package to the logistics carrier. Null for undelivered orders (1,783 null values). **Olist quirk:** in some cases this timestamp precedes `order_approved_at`, likely due to pre-shipment by sellers before payment is formally logged. Do not use this column as a reliable midpoint in delivery time calculations. |
| `order_delivered_customer_date` | TIMESTAMP | Date and time the customer received the package. Null for orders that were not delivered (2,965 null values). This is the definitive end point of the delivery lifecycle and the correct column for calculating delivery duration. |
| `order_estimated_delivery_date` | TIMESTAMP | Estimated delivery date shown to the customer at time of purchase. Always populated. May extend beyond the last `order_purchase_timestamp` in the dataset since it is a forward-looking estimate set at order time. |

**Order status values:**

| Status | Description |
|---|---|
| `delivered` | Order successfully delivered to the customer (96,478 orders, 97% of total) |
| `shipped` | Order dispatched to carrier but not yet confirmed delivered |
| `canceled` | Order canceled before fulfillment |
| `unavailable` | Product became unavailable after order was placed |
| `invoiced` | Order invoiced but not yet shipped |
| `processing` | Order being processed |
| `created` | Order created but not yet approved |
| `approved` | Payment approved but not yet processed for fulfillment |

---

## 2. olist_customers_dataset

**Description:** Customer identity and location table. One row per `customer_id` — which is order-scoped in Olist's data model (see quirk below). Contains both the order-scoped identifier and the true person-level identifier.

**Rows:** 99,441 | **Primary Key:** `customer_id`

| Column | Data Type | Description |
|---|---|---|
| `customer_id` | VARCHAR | Order-scoped customer identifier. Primary key of this table. Joins to `order_id` in `olist_orders_dataset`. **Olist quirk:** a new `customer_id` is generated for every order — even when the same real person places multiple orders. This means `customer_id` is 1:1 with orders, not 1:1 with people. Never use this column to identify repeat customers or calculate customer-level metrics across orders. |
| `customer_unique_id` | VARCHAR | The true, stable identifier for a real customer across all their orders. 96,096 distinct values vs 99,441 rows — the difference (3,345) represents customers who placed more than one order and appear multiple times in this table with different `customer_id`s but the same `customer_unique_id`. **Always use this column for customer-level analysis** — RFM, CLV, retention cohorts, customer health scores, and any metric that needs to count or group real people rather than orders. |
| `customer_zip_code_prefix` | INTEGER | First 5 digits of the customer's postal (ZIP) code. Links to `olist_geolocation_dataset` for lat/lng coordinates. Not a complete ZIP code — it is a prefix covering a geographic area rather than a single address. |
| `customer_city` | VARCHAR | Customer's city name as recorded at time of registration. Free text — minor spelling variations may exist for the same city across rows. |
| `customer_state` | CHAR(2) | Brazilian state abbreviation (e.g. `SP` for São Paulo, `RJ` for Rio de Janeiro). 27 distinct values covering all 26 Brazilian states plus the Federal District (DF). |

---

## 3. olist_order_items_dataset

**Description:** Line item detail for every order. One row per item within an order — an order with 3 products has 3 rows. This is the primary revenue table; `price` and `freight_value` here are the definitive item-level transaction values.

**Rows:** 112,650 | **Primary Key:** (`order_id`, `order_item_id`)

| Column | Data Type | Description |
|---|---|---|
| `order_id` | VARCHAR | Foreign key to `olist_orders_dataset.order_id`. Multiple rows per `order_id` when an order contains more than one item. |
| `order_item_id` | INTEGER | Sequential item number within an order. Starts at 1 for each order and increments by 1 per additional item. Maximum value in the dataset is 21 — meaning one order contained 21 line items. Not unique across the table; only unique within a given `order_id`. |
| `product_id` | VARCHAR | Foreign key to `olist_products_dataset.product_id`. Identifies the product purchased. |
| `seller_id` | VARCHAR | Foreign key to `olist_sellers_dataset.seller_id`. Identifies the seller who listed and fulfilled this item. A single order can contain items from multiple sellers — each seller's items are tracked separately via `order_item_id`. |
| `shipping_limit_date` | TIMESTAMP | Deadline by which the seller must hand the item to the logistics carrier. Set at the time of purchase based on the seller's handling SLA. Should logically fall within a few days of `order_purchase_timestamp`. |
| `price` | DECIMAL | Item sale price in Brazilian Reais (BRL), excluding freight. This is the primary revenue column for item-level and product-level revenue analysis. |
| `freight_value` | DECIMAL | Freight cost in Brazilian Reais (BRL) for this specific item. When an order contains multiple items, the total freight is distributed across items — this column holds each item's freight allocation, not the total order freight. |

---

## 4. olist_order_payments_dataset

**Description:** Payment records for each order. One row per payment installment sequence entry. An order paid in a single transaction has one row; an order paid in installments or via multiple payment methods may have several rows.

**Rows:** 103,886 | **Primary Key:** (`order_id`, `payment_sequential`)

| Column | Data Type | Description |
|---|---|---|
| `order_id` | VARCHAR | Foreign key to `olist_orders_dataset.order_id`. Multiple rows per `order_id` when an order has multiple payment records. |
| `payment_sequential` | INTEGER | Sequential number identifying each payment record within an order. Starts at 1. An order paid entirely by credit card in one transaction has `payment_sequential = 1` only. An order split across a voucher and a credit card has `payment_sequential = 1` (voucher) and `payment_sequential = 2` (credit card). **Olist quirk:** one `order_id` in the dataset has no payment record at all (no `payment_sequential = 1` or any other row). This is the only such case and is documented in the data quality report. |
| `payment_type` | VARCHAR | Method of payment used. See payment type values below. |
| `payment_installments` | INTEGER | Number of installments the payment was split into. A value of `1` means a single lump-sum payment. Brazil has a strong installment payment culture — splitting purchases into monthly installments (`parcelamento`) is standard practice, particularly for higher-value items. The average in this dataset is 2.85 installments. |
| `payment_value` | DECIMAL | Total value of this payment record in Brazilian Reais (BRL). For installment payments, this is the full payment value (not per-installment). When an order has multiple payment rows (split payment types), summing `payment_value` across all rows for the same `order_id` gives the total order payment value. |

**Payment type values:**

| Value | Description |
|---|---|
| `credit_card` | Credit card payment — most common type (76,795 records, 74%) |
| `boleto` | Brazilian bank slip payment method — printed or digital slip paid at a bank or ATM |
| `voucher` | Olist gift voucher or promotional credit |
| `debit_card` | Debit card payment |
| `not_defined` | Payment type not captured — present in a small number of records |

---

## 5. olist_order_reviews_dataset

**Description:** Customer reviews submitted after order delivery. One row per review record. Reviews are submitted via Olist's post-delivery survey and consist of a mandatory star rating and optional free-text fields.

**Rows:** 99,224 | **Primary Key:** `review_id` (with caveats — see quirk below)

| Column | Data Type | Description |
|---|---|---|
| `review_id` | VARCHAR | Identifier for the review record. **Olist quirk:** 814 `review_id` values appear attached to more than one `order_id`. This occurs when a customer's cart spans multiple sellers — Olist splits the checkout into multiple `order_id`s but collects only one review for the entire purchase session, then attaches that single review (with its `review_id`) to every resulting order. The review content (score, comment, timestamps) is identical across all rows sharing the same `review_id`. Always use `COUNT(DISTINCT review_id)` when counting the number of reviews received — row count overcounts by approximately 1,600. |
| `order_id` | VARCHAR | Foreign key to `olist_orders_dataset.order_id`. A small number of `order_id`s appear more than once in this table due to the fan-out behavior described above. |
| `review_score` | INTEGER | Star rating given by the customer. Integer value from 1 (worst) to 5 (best). Always populated. The distribution is strongly skewed toward 5 stars (median = 5, mean = 4.09). |
| `review_comment_title` | VARCHAR | Optional short title for the review, written by the customer in Portuguese. Null in approximately 88% of records — customers are not required to provide a title. |
| `review_comment_message` | VARCHAR | Optional free-text review body, written by the customer in Portuguese. Null in approximately 59% of records. Stored in the warehouse for future NLP analysis but not processed in this project. |
| `review_creation_date` | TIMESTAMP | Date the review survey was sent to the customer (not the date the customer submitted it). |
| `review_answer_timestamp` | TIMESTAMP | Date and time the customer submitted the completed review. The difference between this and `review_creation_date` is the customer's response time. |

---

## 6. olist_products_dataset

**Description:** Product catalogue. One row per product listed on the Olist platform. Contains the product's category (in Portuguese), physical dimensions and weight, and listing quality attributes (name length, description length, photo count).

**Rows:** 32,951 | **Primary Key:** `product_id`

| Column | Data Type | Description |
|---|---|---|
| `product_id` | VARCHAR | Unique identifier for each product. Primary key of this table. Anonymized — the actual product name is not disclosed. |
| `product_category_name` | VARCHAR | Product category in Portuguese (e.g. `cama_mesa_banho` for bed/bath/table linens, `informatica_acessorios` for computer accessories). Null for 610 products (~1.9%). **Olist quirk:** 2 category names (`pc_gamer` and `portateis_cozinha_e_preparadores_de_alimentos`) have no matching entry in the translation file and are manually mapped in the ETL pipeline. |
| `product_name_lenght` | INTEGER | Character count of the product's name as listed by the seller. Note the column name contains a typo (`lenght` instead of `length`) — this is present in the original Olist dataset and preserved as-is. Null for 610 products. |
| `product_description_lenght` | INTEGER | Character count of the product's description text. Note the same typo (`lenght`). Longer descriptions may indicate higher listing quality. Null for 610 products. |
| `product_photos_qty` | INTEGER | Number of photos uploaded for the product listing. More photos generally indicate a more complete listing. Null for 610 products. |
| `product_weight_g` | DECIMAL | Product weight in grams. Used by the logistics system to calculate freight cost. 4 products have a value of 0 — treated as null in the ETL pipeline since a physical product cannot weigh zero grams. |
| `product_length_cm` | DECIMAL | Product length in centimetres. Part of the dimensional data used for freight calculation. |
| `product_height_cm` | DECIMAL | Product height in centimetres. |
| `product_width_cm` | DECIMAL | Product width in centimetres. |

---

## 7. olist_sellers_dataset

**Description:** Seller registry. One row per seller registered on the Olist platform. Contains the seller's location at the zip code prefix level.

**Rows:** 3,095 | **Primary Key:** `seller_id`

| Column | Data Type | Description |
|---|---|---|
| `seller_id` | VARCHAR | Unique identifier for each seller. Primary key of this table. Anonymized — the actual seller name or business identity is not disclosed. Referenced as a foreign key in `olist_order_items_dataset`. |
| `seller_zip_code_prefix` | INTEGER | First 5 digits of the seller's postal (ZIP) code. Links to `olist_geolocation_dataset` for lat/lng coordinates. |
| `seller_city` | VARCHAR | Seller's city as registered on the platform. Free text — minor spelling variations may exist. |
| `seller_state` | CHAR(2) | Brazilian state abbreviation. 23 distinct values — sellers are present in 23 of Brazil's 27 states. São Paulo (`SP`) accounts for the largest share of sellers (1,849 of 3,095, 60%). |

---

## 8. olist_geolocation_dataset

**Description:** Geographic coordinates for Brazilian postal code prefixes. Maps zip code prefixes to latitude, longitude, city, and state. Used to enable geographic heatmap analysis in Tableau.

**Rows:** 1,000,163 (before deduplication) | **Key:** `geolocation_zip_code_prefix` (non-unique in raw file)

| Column | Data Type | Description |
|---|---|---|
| `geolocation_zip_code_prefix` | INTEGER | First 5 digits of a Brazilian postal code. This is the join key to `customer_zip_code_prefix` in the customers table and `seller_zip_code_prefix` in the sellers table. **Not unique** in the raw file — a given prefix may appear many times with slightly different lat/lng coordinates since the raw file logs individual geocoded addresses rather than one canonical point per prefix. In the ETL pipeline, this table is deduplicated to one row per prefix using the average lat/lng. |
| `geolocation_lat` | DECIMAL | Latitude coordinate in decimal degrees. Negative values indicate locations south of the equator (Brazil is predominantly in the southern hemisphere). Valid range for Brazilian territory: approximately -34 to +6. **Olist quirk:** 31 rows contain coordinates outside Brazil's bounding box — including points in Argentina, Portugal, Mexico, and the Philippines — due to a geocoding name-collision bug where Brazilian town names were matched to same-named towns in other countries. These rows are excluded during ETL. |
| `geolocation_lng` | DECIMAL | Longitude coordinate in decimal degrees. Negative values indicate locations west of the prime meridian. Valid range for Brazilian territory: approximately -75 to -32 (including the island of Fernando de Noronha at approximately -32.4). |
| `geolocation_city` | VARCHAR | City name associated with the zip code prefix. Free text in Portuguese. |
| `geolocation_state` | CHAR(2) | Brazilian state abbreviation associated with the zip code prefix. |

---

## 9. product_category_name_translation

**Description:** Lookup table mapping Portuguese product category names to their English equivalents. Used at ETL time to populate `product_category_name_english` in the product dimension table.

**Rows:** 71 | **Primary Key:** `product_category_name`

| Column | Data Type | Description |
|---|---|---|
| `product_category_name` | VARCHAR | Product category name in Portuguese. Primary key of this table — one row per category. Joins to `product_category_name` in `olist_products_dataset`. **Olist quirk:** 2 category names present in the products table (`pc_gamer` and `portateis_cozinha_e_preparadores_de_alimentos`) are missing from this translation file, affecting 13 products. These are manually mapped in the ETL pipeline: `pc_gamer` → `gaming_pc` and `portateis_cozinha_e_preparadores_de_alimentos` → `portable_kitchen_food_preparators`. |
| `product_category_name_english` | VARCHAR | English translation of the product category name. This column is joined into `dim_product` during ETL so that all downstream SQL views and Tableau dashboards display English category names without requiring a separate join. |

---

*For data quality findings related to specific columns, see `docs/03_data_assessment_and_quality_report.md`.*
*For ETL cleaning rules applied to specific columns, see `docs/05_etl_methodology.md`.*
*For the warehouse schema these tables map to, see `docs/04_schema_design.md`.*
