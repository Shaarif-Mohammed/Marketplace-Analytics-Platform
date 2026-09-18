# Key Insights & Recommendations
## Marketplace Analytics Platform

This is the final synthesis document for the project — the one intended for leadership decision-making, not for auditing the analysis itself. It draws on all three prior analysis layers (`docs/07_findings_sql.md`, `docs/08_findings_python.md`, `docs/12_findings_tableau.md`) and condenses them into the handful of insights that actually warrant a leadership decision, each paired with what the data supports doing about it.

Two things this document deliberately does *not* do. First, it doesn't rank these insights by priority or estimate the effort required to act on them — those are resourcing and strategy calls that depend on budget, headcount, and competing initiatives this analysis has no visibility into. What it does provide, for each insight, is the quantified business exposure: what's actually at stake in the data, so leadership is prioritizing against real numbers rather than gut feel. Second, where the three underlying docs report slightly different figures for the same thing, this document states one reconciled number rather than repeating the discrepancy — the reconciliation logic is noted inline.

---

## 1. The Retention Problem Is Structural, Not Situational

Only 3.00% of the platform's 93,358 customers — 2,801 people — ever place a second order, and the Tableau cohort heatmap shows this decay is uniform across every cohort from September 2016 to August 2018, with no exception. Period-1 return rate specifically (the first 30 days) sits at just 0.45% — a stricter, narrower measure of the same underlying pattern, not a conflicting one. Neither the customer's spending pattern nor delivery experience explains it away: the effect holds regardless of how it's sliced.

**Recommendation:** Treat repeat-purchase rate as a structural characteristic of this business, not a metric that minor tweaks will move. Any retention initiative should be piloted and measured against this near-zero baseline, not against typical e-commerce repeat-rate benchmarks (often 20–30%), which don't apply here.

**Business exposure:** The entire repeat-customer economy — the revenue base behind Loyal, Cannot Lose Them, and Champions — rests on roughly 2,801 people out of over 93,000.

---

## 2. Delivery Speed Is the Highest-Confidence Lever in the Entire Project

Every phase of this analysis converges on the same relationship. On-time orders average a 4.29 review score versus 2.57 for late ones. A regression run in the Python phase found each additional delivery day costs 0.0453 review-score points with the highest explanatory power (R²=0.1113) of any relationship tested across the project. A Random Forest model built specifically to find competing explanations — freight cost, category, state, payment type — found delivery time still accounts for 81% of feature importance on its own.

**Recommendation:** Prioritize delivery-time reduction over the alternative review-score levers this project already tested and ruled out (see Insight 7). This is the one lever with both statistical strength and a large practical effect.

**Business exposure:** North Brazil customers wait a median 20–23 days for delivery versus 12–13 in the South and Southeast — roughly double. At 0.045 review-score points per day, that gap alone is large enough to meaningfully drag down the platform's 3.992 average review score in the regions it affects.

---

## 3. The Business Runs on a Narrow Core — On Every Side

Customer, seller, and category concentration all show the same shape. Three of nine RFM segments (Loyal, Cannot Lose Them, Champions) carry roughly 73% of platform revenue. The Elite seller cluster — 1,365 sellers — generates approximately 89% of platform revenue (13.7M of 15.42M BRL). And 76% of category-level revenue comes from just 20% of categories. This isn't three separate concentration problems; it's one pattern showing up on the demand side, the supply side, and the product assortment simultaneously.

**Recommendation:** Treat this narrow core — Loyal/Champions/Cannot Lose Them customers, Elite sellers, and the Revenue Core category cluster — as the business's primary asset to protect before funding acquisition or expansion initiatives aimed at the long tail.

**Business exposure:** Roughly 89% of total platform revenue is concentrated in a seller group that represents well under half of the active seller base — losing even a small share of it would be disproportionately damaging.

---

## 4. The Manual Grading Systems Leadership Currently Relies On Are Miscalibrated

Two labeling systems used to prioritize action — the seller `performance_tier` and RFM customer segments — both have specific, identifiable blind spots. On the seller side, statistical clustering finds the data naturally supports two real groups (Elite vs. everyone else), not the four manual tiers. The manual "Strong" tier specifically is close to a coin flip: only 29.14% of sellers labeled "Strong" actually cluster as high-performing; the other 70.86% behave statistically like the weaker group. This changes how big the seller-quality problem looks: the manual tiering system shows only 0.2% of revenue at risk from quality-troubled sellers; the statistically validated cluster shows 6.8% — an order-of-magnitude difference in exposure depending on which system is trusted.

On the customer side, RFM segment names overstate urgency for two segments specifically: At Risk and Need Attention both sit entirely in the Mid CLV tier — not high-value customers slipping away, just average one-time buyers. Six of the nine RFM segments show an identical pattern (1.0 orders/customer, 0% repeat rate), differing only in how recently the single order happened.

**Recommendation:** Before allocating retention or seller-intervention spend by segment or tier label, cross-check against CLV tier (customers) and cluster assignment (sellers). Both manual systems currently in use will misallocate effort if trusted on their own.

**Business exposure:** A roughly 30x understatement of at-risk seller revenue (0.2% vs. 6.8%) is the single largest quantifiable blind spot surfaced anywhere in this project.

---

## 5. Regional Inequality Is Self-Reinforcing

Delivery time, seller supply, and revenue move together geographically rather than independently. The states with the worst seller-supply gap — Pará (946 orders per seller) and Maranhão (717) — are the same states with the lowest revenue and the weakest delivery performance. On a linear revenue scale, São Paulo alone is visibly dominant; every other state, including Minas Gerais and Rio de Janeiro, is barely distinguishable from the rest of the country by comparison.

**Recommendation:** Target seller-supply density first in the identified gap states (Pará, Maranhão, Piauí). Thin seller presence appears to be the root cause of both the delivery-time and revenue gaps in these states, not simply a symptom of them.

**Business exposure:** North Brazil's delivery time runs roughly double the Southeast's, compounding both the review-score cost from Insight 2 and the revenue gap directly.

---

## 6. Category Problems Are Narrower and More Specific Than They First Appear

Clustering all 74 categories on revenue, review score, freight share, and repeat rate finds the platform's one genuine problem group is small and specific: a 3-category cluster (`portable_kitchen_food_preparators`, `gaming_pc`, `security_and_services`) with the lowest revenue, the lowest review score of any group, and zero repeat purchases. `office_furniture` is a separate case worth distinguishing from that cluster: despite an individually poor 3.52 review score and a real revenue contribution (2.17% of total revenue), it clusters with the platform's healthy Revenue Core — its revenue and freight profile resemble the core group, even though its review score doesn't. Freight cost, the intuitive explanation for its poor reviews, doesn't hold up on its own either: freight's effect on review score is statistically real but practically negligible (R²=0.0007). Delivery time is almost certainly the actual driver, both for `office_furniture` specifically and likely for the small trouble cluster as well.

**Recommendation:** Treat `office_furniture` as an isolated delivery-time problem rather than evidence of a broader category-level issue — it doesn't share a cluster with the platform's genuinely troubled categories, so a cluster-wide fix would misdirect effort. Address the small 3-category trouble cluster separately, as its own narrower and more targeted problem.

**Business exposure:** `office_furniture` alone represents 2.17% of category-level revenue carrying a real reputational liability. The separate 3-category trouble cluster is small in count but returns zero repeat purchases — an outright loyalty dead zone regardless of its size.

---

## 7. Three Intuitive Investments Don't Have a Revenue Case

Several plausible-sounding levers were tested rigorously and came back statistically real but practically negligible. Review-response speed has no effect on repeat purchase (p=0.3785); if anything, faster responses correlate with a slightly *lower* repeat rate. Freight cost's effect on review score is statistically significant but tiny (R²=0.0007). Customer lifespan predicts more spend, but explains almost none of the variation (R²=0.0017, worth roughly BRL 3.44 per extra active month). None of these are necessarily bad ideas — they may still be worth doing for brand or experience reasons — but none of them are backed by a revenue case in this data.

**Recommendation:** Don't fund review-response speed, freight-cost reduction, or lifespan-extension programs as revenue plays. If pursued, justify the spend on reputational or customer-experience grounds explicitly, since the data doesn't support a financial return.

**Business exposure:** None quantifiable as revenue — that absence is itself the finding, and the reason these three are called out separately from Insights 1–6.

---

## Limitations

CLV figures throughout rely on a simplified purchase-rate projection, not a formal model like BG/NBD, and should be read as directional. Several figures above come from small sub-populations by definition — repeat buyers are 3% of customers, scored sellers require a 5-order minimum — so they carry more noise than platform-wide numbers. No customer acquisition cost data exists in the source dataset, so no payback-period or ROI figure is provided for any recommendation above; that calculation would need to be supplied by whoever owns that cost. Where the seller revenue-at-risk figure appears elsewhere as 6.20%/0.22% (`docs/08_findings_python.md`) rather than the 6.8%/0.2% used here, this document uses the Tableau dashboard's live-connected figure as the source of truth; the ~30x order-of-magnitude gap and its direction hold under either version.

---

## Source Documents

- `docs/07_findings_sql.md` — descriptive SQL-layer findings
- `docs/08_findings_python.md` — regression, hypothesis testing, and clustering
- `docs/12_findings_tableau.md` — dashboard-driven narrative and drill-through detail
