# Findings from SQL Views
## Marketplace Analytics Platform

---

## Finding 1 — Customer Retention Is the Platform's Core Problem

**The number:** Only 0.45% of customers place a second order within one month of their first — and the rate stays below 1% across every subsequent period. Retention never recovers meaningfully at any point in the dataset.

Of the 93,358 customers who ever placed a delivered order, 58.77% are currently inactive — 36.16% dormant (last order 6–12 months ago) and 22.61% effectively lost (no order in over a year). Active customers account for just 41.23% of the base.

New customer revenue accounts for 97–100% of monthly revenue throughout the entire dataset. The returning customer share grew from effectively zero in late 2016 to a peak of 2.98% in June 2018 — a positive trend, but from a very low base. The business is almost entirely dependent on continuous new customer acquisition to sustain revenue.

**Why this matters:** A business that cannot retain customers must perpetually acquire new ones to maintain revenue. The cost of acquiring a new customer is typically 5–7× higher than retaining an existing one. The data suggests Olist has a strong acquisition engine but a leaky retention bucket.

**The opportunity:** The dormant segment (33,760 customers) represents the highest-value reactivation target. These customers bought relatively recently, have demonstrated purchase intent, and have not been gone long enough to be considered permanently lost. A targeted win-back campaign for this segment — timed within 6 months of their last order — has the highest probability of success.

---

## Finding 2 — Delivery Speed Is the Strongest Driver of Customer Satisfaction

**The number:** Orders delivered on time receive an average review score of 4.29. Late orders receive 2.57. That is a 1.72-point gap on a 5-point scale driven by a single operational variable.

The national on-time delivery rate is 91.89%, which is strong. However, 8.11% of orders — approximately 7,826 in this dataset — arrive late. Those late orders average 31.1 days to deliver, compared to 10.4 days for on-time orders. When a delivery is late, it is not marginally late — it is typically three times slower than expected.

Olist systematically under-promises on delivery estimates. The average order is delivered 11 days ahead of the estimated delivery date, and 88.77% of all orders are delivered early by at least 2 days. This is a deliberate and effective strategy — by setting conservative estimates, Olist maximises the share of orders that register as "on-time" even when actual delivery takes longer than ideal.

**The geographic dimension:** Delivery time varies dramatically by state. São Paulo receives orders in 8.3 days on average; Roraima and Amapá take 27–29 days. Northern and northeastern states consistently show longer delivery times, lower on-time rates, and lower review scores. This is not a customer expectation problem — it is a logistics infrastructure problem. States like Alagoas (24-day average, 76.07% on-time, 3.82 review score) and Maranhão (21-day average, 80.33% on-time, 3.77 review score) are being structurally disadvantaged.

**The implication:** Improving on-time delivery from 91.89% to 95% — a 3-point operational improvement — would likely be the single highest-ROI change Olist could make to customer satisfaction. The delivery-to-review correlation is the clearest causal relationship in the dataset.

---

## Finding 3 — Sellers Are Far Stickier Than Customers

**The contrast:** 69.66% of sellers are currently active (last sale within 6 months), compared to 41.23% of customers. Returning sellers drive 92% of monthly revenue by mid-2018; returning customers never exceed 3%.

The seller base grew from a single active seller in September 2016 to 1,261 active sellers in August 2018. Unlike customer revenue — which is dominated by new buyers in every single month — seller revenue flipped to returning-dominated by February 2017, just five months after the platform launched at scale. From March 2017 onward, returning sellers consistently drove 80–95% of monthly revenue.

This tells a clear story: sellers who start selling on Olist tend to keep selling. Customers who buy on Olist tend not to come back.

**The structural implication:** The platform's supply side is healthy and self-sustaining. The demand side is not. Investment in seller acquisition and quality is already delivering returns. Investment in customer retention infrastructure — loyalty programmes, re-engagement campaigns, personalised recommendations — has not yet been made or has not yet had time to show results in this dataset window.

**The risk:** 42% of all sellers (1,301 out of 3,095) never crossed 5 delivered orders. A large proportion of registered sellers are effectively dormant or never launched. This suggests the onboarding funnel converts sellers but does not consistently activate them.

---

## Finding 4 — Revenue Is Heavily Concentrated in the Southeast

**The number:** São Paulo state alone accounts for 37.44% of national revenue. The top three states — São Paulo, Rio de Janeiro, and Minas Gerais — account for 62.55%. The top six states account for 80% of all revenue.

Brazil has 27 states and the federal district. The bottom 10 states combined contribute less than 2% of revenue. Roraima, the smallest market, generates 0.06% of revenue from 40 customers.

**The seller supply gap:** Several high-demand states have critically low seller presence, creating long delivery chains and poor customer experiences:

- Pará: 946 customer orders, 1 local seller (946 orders per seller)
- Maranhão: 717 orders, 1 local seller (717 orders per seller)
- Mato Grosso: 886 orders, 4 local sellers (221 orders per seller)
- Bahia: 3,256 orders, 18 local sellers (181 orders per seller)

Five states — Alagoas, Tocantins, Acre, Amapá, and Roraima — have zero local sellers. All demand in these states is served by out-of-state sellers, which directly explains their longer delivery times and lower review scores.

**The opportunity:** Targeted seller recruitment in underserved states — particularly Bahia, Pará, Maranhão, and Mato Grosso — would simultaneously reduce delivery times, improve review scores, and unlock demand that currently converts poorly due to poor service. Bahia in particular stands out: it is Brazil's fourth most populous state, has 3,256 orders (meaningful demand), but only 18 local sellers.

---

## Finding 5 — A Small Number of Sellers Drive the Majority of Revenue

**The number:** 18.52% of sellers (550 out of 2,970 with delivered orders) generate 80% of platform revenue. The top 20% of sellers generate 81.62% of revenue — almost exactly the classic 80/20 distribution.

This is a typical marketplace power law and is not inherently problematic. However, it creates a concentration risk: the loss of a small number of high-performing sellers would have an outsized impact on platform revenue.

Of the 1,794 sellers with 5 or more orders who were eligible for performance scoring, 1,386 (77%) scored Elite — the highest tier. This initially seems surprising, but reflects a genuine survivorship effect: sellers who persisted long enough to build volume on a competitive marketplace tend to be the ones operating well. Low-performing sellers self-select out.

The 19 Average-tier sellers (avg review score 2.36, on-time rate 49.73%) and the 1 Needs Work seller are actively harmful to platform reputation. These sellers are processing real orders and generating real negative reviews despite clear operational deficiencies.

---

## Finding 6 — Instalment Depth Drives Higher Order Values

**The number:** Customers paying in a single instalment spend an average of 129 BRL per order. Customers using 7–12 instalments spend 343 BRL — 2.65× more. The relationship is consistent and monotonic across all instalment bands.

Credit card is the dominant payment method at 76.93% of orders and 79.66% of revenue. Boleto (Brazilian bank slip) accounts for 19.90% of orders — a significant segment that represents Brazil's large unbanked and underbanked population. Boleto customers are limited to single-instalment purchases by definition, capping their average order value at 144 BRL compared to 165 BRL for credit card customers.

Only 33% of credit card orders use a single instalment — meaning 67% of credit card customers actively choose to split their payment. This is not a niche behaviour; it is the dominant pattern among card users.

**The implication:** Promoting instalment options more prominently — particularly to first-time buyers considering higher-value purchases — could directly increase average order value. The data suggests customers who understand and use instalments spend significantly more. Boleto customers represent a segment that could benefit from alternative financing products (BNPL, instalment boleto) to unlock higher-value purchasing that is currently inaccessible to them.

---

## Finding 7 — Review Response Is Uniform Regardless of Score

**The number:** Olist responds to 1-star reviews in an average of 73.3 hours. It responds to 5-star reviews in 77.1 hours. The difference is less than 4 hours.

This is a missed opportunity. Industry best practice for marketplace review management is to respond to negative reviews within 24 hours — both to attempt service recovery and to signal to other customers that complaints are taken seriously. The current uniform response pattern suggests review triage and prioritisation is not in place.

Negative reviews are also the most informative: 76.59% of 1-star reviews include a written comment explaining the problem, compared to 35.91% of 5-star reviews. This means the data needed to diagnose and fix problems exists in the review text — it is simply not being acted on quickly.

**The review distribution:** The platform shows a classic bimodal pattern. 57.83% of reviews are 5-star and 11.46% are 1-star. The middle scores (2 and 3) are relatively rare. This reflects the fact that customers who have a neutral experience typically do not bother leaving a review — only strong reactions (positive or negative) prompt engagement.

---

## Finding 8 — Specific Categories Have Persistent Quality Problems

**The standout case:** `office_furniture` appears in the bottom tier across every relevant view. It has a 3.64 average review score (the lowest of any high-volume category), 17.20% 1-star rate, 20.4-day average delivery time (the slowest of any category), 20% freight as a share of revenue, and an 84.1-hour review response time. This category is simultaneously hard to ship, expensive to deliver, slow to arrive, and poorly reviewed. It requires specific intervention — whether through seller quality standards, logistics partnership, or better expectation-setting for buyers.

**Other problem categories:**
- `uncategorised` (610 products with no category): 3.17 avg score, 35.06% 1-star rate. Products with no category listing likely suffer from poor discoverability and buyer expectation mismatches.
- `home_comfort_2` and `home_confort`: 3.83 and 3.89 avg scores respectively, both with ~14–17% 1-star rates. Comfort and furnishing categories show a consistent pattern of buyer dissatisfaction — likely driven by expectation mismatches on product quality and slow delivery of bulky items.
- `bed_bath_table`: Despite being the third highest revenue category (7.95% share), it carries a 3.92 avg review score and 16.60% 1-star rate. High volume with a satisfaction gap suggests quality inconsistency across the many sellers in this category.
- `computers_accessories`: 3.98 avg score, 16.05% 1-star. Technology categories often suffer from specification mismatches between listing and reality.

**The health_beauty finding:** Health and beauty is the top revenue category at 9.16% share — above the traditionally dominant bed/bath/table. This reflects a global shift toward personal care e-commerce and may represent a category where Olist has particular strength or seller depth.

---

## Finding 9 — The Customer Value Distribution Is Flat

**The contrast with sellers:** While 20% of sellers drive 81.62% of seller revenue, 48.86% of customers are needed to drive 80% of customer revenue. The customer base does not follow the classic 80/20 rule — it is much flatter.

This means there is no small "whale" segment of customers who are individually critical to protect or retain. The value is distributed broadly. The implication is that retention strategy needs to be horizontal — improving retention across the whole base — rather than vertical (protecting a small elite segment). Every customer who returns matters almost equally.

This also means that the RFM Champions segment (4.13% of customers, avg spend 319 BRL) is valuable but not disproportionately so compared to the rest of the high-value tier. The distinction between Champions and other high-spend segments is real but not dramatic.

---

## Summary of Key Metrics

| Metric | Value |
|---|---|
| Total delivered orders | ~96,500 |
| Total revenue (delivered orders) | 15.4M BRL |
| National avg delivery time | 12.1 days |
| National on-time delivery rate | 91.89% |
| Period-1 customer retention rate (weighted) | 0.45% |
| Active customer base | 41.23% |
| Returning customer revenue share (peak) | 2.98% (June 2018) |
| Active seller base | 69.66% |
| Returning seller revenue share (Aug 2018) | 92.35% |
| Review score — on-time delivery | 4.29 |
| Review score — late delivery | 2.57 |
| Top state revenue share (SP) | 37.44% |
| Sellers driving 80% of revenue | 18.52% |
| Credit card payment share | 76.93% |
| 5-star review share | 57.83% |

---

## What This Analysis Does Not Cover

The following are intentionally out of scope for this project and reserved for a future AI-layer analysis built on top of this warehouse:

- **Review text sentiment and NLP** — the `review_comment_message` and `review_comment_title` fields are stored in the warehouse but not analysed here. Sentiment analysis, topic modelling, and keyword extraction from ~40,000 written reviews would add significant depth to the quality findings.
- **Price elasticity and discount analysis** — the dataset does not include list prices or discount fields, limiting pricing analysis.
- **Seller-level CLV** — equivalent lifetime value modelling applied to sellers rather than customers.
- **Predictive churn modelling** — the RFM and retention views identify at-risk customers descriptively; a machine learning model could score individual churn probability.
