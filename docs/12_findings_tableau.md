# Findings — Tableau Dashboards
## Marketplace Analytics Platform

**Live workbook:** [Marketplace Analytics Platform — Tableau Public](https://public.tableau.com/views/MarketplaceAnalyticsPlatform/ExecutiveOverview?:language=en-US&:sid=&:redirect=auth&:display_count=n&:origin=viz_share_link)

This memo tells the story the dashboards tell once you actually click through them — not a re-statement of the SQL and Python phases, but what the workbook itself reveals when its charts are read together. The SQL and Python findings sit underneath this analysis and are referenced inline where they connect, but the goal here is what the visual layer adds: shape, concentration, and the relationships between metrics that only show up when they're sitting on the same dashboard.

---

## Executive Overview: A Business That Grew Fast, Then Stalled — Running on a Narrow Core

The topline numbers look healthy in isolation — BRL 15.42M in revenue, 100,010 orders, 91.89% on-time delivery, a 3.992 average review score. But the Monthly Revenue Trend tells a more specific story: revenue climbs steadily from late 2016 through a sharp peak around November 2017, then flattens into a choppy plateau through mid-2018, with a visible dip into August 2018. New Customers Over Time follows almost the same shape, peaking around the same point and tapering off afterward. This isn't a business in early-stage hockey-stick growth — it's one that scaled hard for about a year and has been treading water since.

The KPI row hints at why. Active Sellers sit at 69.66%, but Active Customers sit at just 41.23% — the supply side of this marketplace is far stickier than the demand side. Sellers stay engaged; customers don't. That asymmetry is the seed of everything the rest of the dashboards go on to explain.

The Revenue Mix by Customer Segment table makes the concentration explicit: Loyal customers are 28.26% of the customer base but 50.93% of all spend. Add Cannot Lose Them (14.21% of spend) and Champions (8.13%), and three segments — out of nine — account for nearly three-quarters of platform revenue. The other six segments, representing the majority of customers, are mostly noise on the revenue line. This single table is the thesis for the rest of the workbook: this is a business that runs on a small core of engaged customers, not a broad base of casual ones.

![Executive Overview](../dashboard/00_executive_overview.png)

---

## Customer Intelligence: Most of the Customer Base Never Really Arrives

The Cohort Retention Heatmap is the most visually blunt chart in the whole workbook. Every cohort — from September 2016 through August 2018, with no exceptions — falls from 100% at month zero to well under 1% by month one, and stays there. There's no cohort that behaves noticeably better or worse than any other. That uniformity matters: it means this isn't a fixable onboarding problem or a one-time bad quarter, it's how the platform has always worked.

The CLV Distribution chart adds a layer the cohort heatmap doesn't show on its own: of roughly 93,358 customers with a projected CLV, 93,094 of them sit in the lowest bucket, with only a few hundred customers reaching any meaningfully higher tier — the bars for the next few buckets (210, 33, 12, 8) are barely visible next to the first one, even on a log scale. Value on this platform isn't just concentrated, it's concentrated to an extreme that makes "average customer value" close to a meaningless number — nearly the entire customer base is worth close to nothing individually, and the platform's actual value sits in a sliver of customers so small it barely registers on the chart.

The RFM Segment Distribution bar chart shows why the labels can be misleading at a glance: Loyal is the largest segment (28.26%), but Champions — the segment actually representing the platform's best, most frequent, most recent customers — is the smallest at just 4.09%. Read next to the Revenue Mix table above, that's a business with very few true power users and a long tail of everyone else.

### Segment Deep-Dive (Drill-Through)

Clicking into the individual segments is where the RFM labels either hold up or fall apart. Three segments genuinely earn their names. **Champions** average a 16.25% repeat rate and a 173-day customer lifespan — the only segment with real, sustained relationship depth, and the RFM × CLV crosstab shows just how concentrated that value is: 99.11% of Champions land in the High CLV tier. **Cannot Lose Them** back up their name with a 269.30 BRL average order value (the highest of any segment) and 48-day lifespan, even though their last order was, on average, 475 days ago — these are genuinely high-value customers who have gone quiet, which is exactly the risk the label implies. **Loyal**, the platform's revenue backbone, carries 50.9% of total spend from 28.3% of customers with a 6.61% repeat rate.

Everywhere else, the label overpromises. **About to Sleep** and **At Risk** both show a 0.00% repeat rate and exactly 1.0 orders per customer — these aren't valuable customers drifting away, they're one-time buyers who never had a second order to begin with. **Need Attention**, **Potential Loyal**, **Promising**, and **Recent** show the identical pattern: 1.0 orders per customer, 0% repeat rate, differing only in how recently that single order happened. The RFM × CLV crosstab confirms this in hard numbers — About to Sleep is 82.23% Low CLV, Potential Loyal is 78.23% Low, Promising is 84.81% Low, and Need Attention and At Risk are both **100% Mid** CLV, not high value at all. Of the nine segments, only Loyal, Cannot Lose Them, and Champions carry any meaningful weight in the High CLV tier. Six segment names describe urgency or opportunity; six segments' actual numbers describe an average or below-average one-time buyer.

![Customer Intelligence](../dashboard/01_customer_intelligence.png)

---

## Seller Performance: A Trusted Middle Tier That Doesn't Deserve the Trust

The Quality vs Revenue Scatter has a detail easy to miss on first look: a large population of yellow "No Cluster" sellers strung in vertical lines at exactly 1.0, 2.0, 3.0, 4.0, and 5.0 on the review-score axis, almost all at the bottom of the revenue scale. Those are sellers with too little order history to reliably score or cluster — and the Tier vs Cluster Agreement Matrix puts a number on that population: 1,301 sellers, entirely uncategorized. That's a meaningful slice of the seller base essentially invisible to any quality-management process, not because they're bad, but because there isn't enough data to know.

Among sellers with enough history to be scored, the matrix reveals which manual tier can actually be trusted. **Elite** holds up — 97.22% of manually-tiered Elite sellers cluster the same way statistically. **Average** and **Needs Work** also hold up, both landing 100% in the Non-Elite cluster, as expected. The tier that doesn't hold up is **Strong** — the second-highest manual tier — where only 29.14% of sellers actually cluster as high-performing, and 70.86% behave statistically like the weaker group. "Strong" is the label a manager would reach for to justify trust, and it's the one label on this platform that's closest to a coin flip.

Hovering the Elite cell surfaces a number that doesn't appear anywhere else in the workbook: those 1,365 Elite-clustered sellers generate 13,700,629 BRL in total revenue at a 10,044 BRL average per seller and a 4.265 average review score. Against the platform's 15.42M total revenue, that's roughly **89% of all platform revenue running through the Elite cluster alone** — this isn't just the best-performing seller group, it's functionally where the business's revenue actually lives.

The Revenue at Risk chart is where the tiering gap turns into a dollar figure leadership would actually act on: 6.8% of revenue sits with the statistically low-quality cluster, versus just 0.2% under the manual tiering system — an order-of-magnitude difference in how exposed the business looks depending on which system is trusted. The Seller Revenue Concentration curve closes the seller story out with its own extreme: roughly 81% of revenue from the top 20% of sellers, meaning this Strong-tier ambiguity sits inside the group that already carries most of the platform's revenue risk.

![Seller Performance](../dashboard/02_seller_performance.png)

---

## Regional & Delivery Ops: Geography Compounds Itself

The filled map, colored by average delivery days, makes the North and Northeast visibly darker than the rest of the country — and the supporting bar chart quantifies it: 23.10 days in the North versus 12.48 in the Southeast, nearly double. But the more useful chart here is the Revenue vs Delivery Performance Quadrant, because it shows delivery performance and revenue moving together geographically, not independently. SP, RJ, and MG sit in the top-right — high revenue, strong on-time rates. AL and MA sit in the bottom-left — both weak on-time performance and by far the lowest revenue on the chart. The Seller Supply Gap by State chart explains the mechanism: those same states (PA, MA, PI) have the worst orders-per-seller ratios on the platform. Thin seller presence, slow delivery, and low revenue aren't three separate regional problems — they're one problem showing up on three charts, and it's not obvious which end of that chain to pull first.

Switching the same filled map to its other two measures adds two details the delivery-days view alone doesn't show. On **On-Time Rate**, the range across the country is fairly narrow (75.87% to 96.70%) and most states sit in a similar mid-range teal — except Pernambuco, which stands out as a single dark outlier at the low end. That's worth flagging on its own: Pernambuco isn't one of the states already called out for thin seller supply or long delivery times, which means its on-time problem likely has a different cause than the PA/MA/PI supply gap — something closer to the Northeast pattern Central-West and South data hints at elsewhere, where on-time performance and raw delivery speed don't move in lockstep. On **Revenue**, the map stops being subtle entirely: on a linear color scale, São Paulo is the only state with real color in it. MG and RJ — which looked like genuine second- and third-place contenders on the log-scale quadrant scatter — are nearly indistinguishable from the rest of the country once the scale isn't compressed. The quadrant chart says SP, RJ, and MG are the platform's strong states; the raw revenue map says it's SP, and then everyone else.

![Regional & Delivery Ops](../dashboard/03_regional_delivery_ops.png)

---

## Product & Category: One Category's Problem Isn't the Cluster's Problem

The Order Volume vs Revenue scatter splits the top categories into two visibly different shapes of success. `health_beauty`, `sports_leisure`, `computers_accessories`, and `auto` sit high on both axes with strong (teal) review scores — genuine volume-and-quality winners. `bed_bath_table` and `watches_gifts`, by contrast, reach similar revenue with a fraction of the order volume, which only works because their average order value is much higher — and both are colored pink, indicating below-average review scores. Revenue leadership on this platform comes from two structurally different paths: sell a lot of something people like, or sell fewer, pricier things people are less happy with.

The Top 5 vs Bottom 5 by Review Score table sharpens that same pattern. The best-reviewed categories — Fashion Children's Clothes (5.00), CDs/DVDs (4.64), Books (4.51) — are small, low-stakes purchases. The worst-reviewed — Security/Services (2.50, the single lowest score on the platform), Diapers & Hygiene (3.38), Portable Food Preparators (3.43), Office Furniture (3.52), Home Comfort Goods (3.63) — skew toward bulkier, higher-friction, higher-expectation purchases. Quality and popularity aren't just uncorrelated here; they're pulling in opposite directions.

Office Furniture is the clearest illustration of why category health needs more than one lens. On an individual basis it's genuinely troubled — a 3.52 review score puts it in the platform's bottom five, and it still lands in the Top Revenue Driving Categories table at 2.17% of total revenue, so it's not a category the business can simply deprioritize. But once revenue, freight burden, and repeat rate are weighed alongside review score, it clusters with the platform's healthy Revenue Core rather than its one real trouble group — its revenue strength and freight profile look like the categories around it, even though its review score doesn't. That's not a reason to ignore its quality problem; it's evidence the problem is a specific, addressable delivery-time issue rather than a symptom of something structurally broken in how the category is sold.

The Category Cluster Distribution treemap organizes all 74 categories into four groups worth remembering: a large **Revenue Core** — including Office Furniture — that carries strong revenue and a solid average review score but a thin repeat rate; a **Small & Well-Reviewed** group that's nearly as large in category count but contributes far less revenue per category, carrying the best average review score of any group at the cost of the heaviest freight burden; a tiny, genuinely troubled cluster (`portable_kitchen_food_preparators`, `gaming_pc`, `security_and_services`) with the lowest revenue, the lowest review score of any group, and zero repeat purchases; and a small **Small & Sticky** cluster with a repeat rate several times higher than everywhere else on the platform. The Category Revenue Concentration curve shows 76% of revenue coming from just 20% of categories — a Pareto pattern nearly as steep as the seller-side one.

![Product & Category](../dashboard/04_product_category.png)

---

## The Story, Pulled Together

Across five dashboards, the same shape keeps repeating: a small core carries the business, and the long tail around it is much shakier than its labels suggest. A small share of customers carries most of the revenue. A small share of categories carries most of the revenue. A small share of sellers carries most of the revenue. And in each case, a label built to flag urgency or risk — About to Sleep and At Risk customers, the Strong seller tier — turns out to describe something closer to average than alarming, once the underlying numbers are checked. The workbook's real contribution isn't a new number; it's making that pattern visible in one click, across customers, categories, and sellers alike, in a way no single SQL query or notebook cell was built to show at once.

---

## Appendix — Drill-Through and Custom Tooltip

**Segment Deep-Dive drill-through (Loyal):**

![Drill-Through — Loyal Segment](../dashboard/05_drill_through_segment.png)

**Custom tooltip viz** — hovering the Elite cell of the Tier vs Cluster Agreement Matrix embeds a live-filtered mini scatter (Quality vs Revenue) scoped to just that cell's sellers, surfacing the 13.7M BRL / 4.265 review score figures cited in the Seller Performance section above:

![Custom Tooltip Viz](../dashboard/06_custom_tooltip_viz.png)
