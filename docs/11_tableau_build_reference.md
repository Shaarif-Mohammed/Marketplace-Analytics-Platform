# Tableau Workbook Blueprint
## Marketplace Analytics Platform

*A field-by-field record of how every worksheet, dashboard, and interactive element was built.*

---

## 1. Introduction

This document is a build blueprint for the Tableau workbook underlying the Marketplace Analytics Platform — a 5-dashboard BI deliverable covering customer, seller, regional/delivery, and product/category analytics on the Olist Brazilian e-commerce dataset.

Its purpose is to document exactly how the workbook was constructed at the field level: which raw and calculated fields were placed on which shelf (Rows, Columns, Filters, Color, Detail, Label, Parameters) for every worksheet across all five dashboards, how the workbook's interactive layer (a full segment drill-through dashboard, a viz-in-tooltip, cross-filtering, navigation, and a scoped date-range filter) was assembled, and a complete dictionary of every calculated field and LOD (Level of Detail) expression used, with its formula and purpose.

The workbook is organized around five dashboards, each following a consistent layout pattern (one large anchor visual plus 3–5 supporting visuals), with two dashboards additionally supporting drill-through and cross-filter interactivity:

- **Dashboard 0 — Executive Overview**: platform-wide KPIs and trend lines, functioning as a landing page with navigation into the other four dashboards.
- **Dashboard 1 — Customer Intelligence**: RFM segmentation, cohort retention, CLV distribution, and a dedicated Segment Deep-Dive drill-through dashboard.
- **Dashboard 2 — Seller Performance**: quality-vs-revenue clustering, tier/cluster agreement analysis (with an embedded viz-in-tooltip), and seller revenue concentration.
- **Dashboard 3 — Regional & Delivery Ops**: a parameter-driven choropleth map plus delivery-time and regional revenue analysis.
- **Dashboard 4 — Product & Category**: category-level revenue/volume clustering, review-score extremes, and category revenue concentration.

Every field name referenced in this document reflects the field's actual, final name in the Tableau workbook. Calculated fields and LOD expressions are named once and reused wherever they appear; the full formula for each is documented once, in the Appendix, rather than repeated at every point of use.

---

## 2. Field Mapping by Dashboard

This section documents, worksheet by worksheet, exactly which fields sit on which Tableau shelf. Calculated fields are referenced by name only here; full definitions are in the Appendix.

### Dashboard 0 — Executive Overview

*Eight KPI tiles, one anchor trend chart, one additional trend chart, and one comparison table, plus a 4-button navigation panel and a scoped Date Range parameter filter.*

#### KPI – Total Revenue
| Pane / Shelf | Fields / Notes |
|---|---|
| Label / Text | `SUM(Total Revenue)`, formatted with Millions (M) unit abbreviation |

#### KPI – Active Customer %
| Pane / Shelf | Fields / Notes |
|---|---|
| Calculated Fields Used | `Pct Active Customers` |
| Label / Text | `Pct Active Customers` |

#### KPI – On-Time Delivery %
| Pane / Shelf | Fields / Notes |
|---|---|
| Filters | Dimension = "Overall"; Dimension Value = "National" |
| Label / Text | `AVG(On Time Rate)` |

#### KPI – Active Seller %
| Pane / Shelf | Fields / Notes |
|---|---|
| Filters | Metric Type = "Status Snapshot" |
| Calculated Fields Used | `Pct Active Sellers` |
| Label / Text | `Pct Active Sellers` |

#### KPI – Total Orders
| Pane / Shelf | Fields / Notes |
|---|---|
| Label / Text | `SUM(Total Orders)` |

#### KPI – Average Order Value
| Pane / Shelf | Fields / Notes |
|---|---|
| Calculated Fields Used | `Average Order Value (AOV)` |
| Label / Text | `Average Order Value (AOV)` |

#### KPI – Avg Review Score
| Pane / Shelf | Fields / Notes |
|---|---|
| Label / Text | `AVG(Avg Review Score)` |

#### KPI – Repeat Purchase Rate
| Pane / Shelf | Fields / Notes |
|---|---|
| Calculated Fields Used | `Repeat Rate %` |
| Label / Text | `Repeat Rate %` |

#### Monthly Revenue Trend
*Anchor visual; line chart of platform revenue over time.*

| Pane / Shelf | Fields / Notes |
|---|---|
| Columns | `MONTH(Order Month)` — continuous, exact date |
| Rows | `SUM(Total Revenue)` |
| Filters | `In Date Range` = True |
| Calculated Fields Used | `In Date Range` (New vs Returning Revenue source) |
| Parameters | `Date Range Start`, `Date Range End` |

#### New Customers Over Time
| Pane / Shelf | Fields / Notes |
|---|---|
| Columns | `MONTH(First Order Date)` — continuous, exact date |
| Rows | `CNTD(Customer Unique Id)` |
| Filters | `In Date Range` = True |
| Calculated Fields Used | `In Date Range` (Customer Analytics source) |
| Parameters | `Date Range Start`, `Date Range End` |

#### Revenue Mix by Customer Segment
*Table: Segment × % of Customers × % of Revenue, sorted by revenue share descending.*

| Pane / Shelf | Fields / Notes |
|---|---|
| Rows | `Segment` |
| Columns | Measure Names / Measure Values (`pct of Total Customers`, `pct of Total Spend`) |
| Calculated Fields Used | `pct of Total Customers`, `pct of Total Spend` |
| Sort | Descending by `SUM(Total Spend)` |

---

### Dashboard 1 — Customer Intelligence

*One cohort heatmap and four additional worksheets, plus a full secondary drill-through dashboard (see Section 3).*

#### Cohort Retention Heatmap
| Pane / Shelf | Fields / Notes |
|---|---|
| Rows | `Cohort Month` (exact date, discrete) |
| Columns | `Period Number` |
| Filters | `Period Number` ≤ 12 |
| Color | `AVG(Retention Rate Pct)` |
| Label | `AVG(Retention Rate Pct)` |

#### RFM Segment Distribution
| Pane / Shelf | Fields / Notes |
|---|---|
| Rows | `Segment` |
| Columns | `CNTD(Customer Unique Id)` |
| Label | `CNTD(Customer Unique Id)`, `Pct of Total Customers` |
| Calculated Fields Used | `Pct of Total Customers` |
| Sort | Descending by `CNTD(Customer Unique Id)` |
| Notes | Source sheet for the Dashboard 1 cross-filter action (see Section 3). |

#### RFM × CLV Tier Crosstab
| Pane / Shelf | Fields / Notes |
|---|---|
| Rows | `Segment` |
| Columns | `CLV Tier` |
| Color | `CNTD(Customer Unique Id)` |
| Label | `CNTD(Customer Unique Id)`, `Pct Within Segment Row` |
| Calculated Fields Used | `Pct Within Segment Row` (table calc, Compute Using CLV Tier) |

#### CLV Distribution
| Pane / Shelf | Fields / Notes |
|---|---|
| Columns | `Projected Clv 12M` (binned) |
| Rows | `CNTD(Customer Unique Id)` — log-scale axis |

#### Days to Second Purchase
| Pane / Shelf | Fields / Notes |
|---|---|
| Columns | `Days to Second Purchase Bucket` |
| Rows | `CNTD(Customer Unique Id)` |
| Filters | `Second Order Date` is not Null |
| Calculated Fields Used | `First Order Date`, `Second Order Date`, `Days to Second Purchase`, `Days to Second Purchase Buckets` |
| Sort | Manual (chronological bucket order) |

---

### Dashboard 2 — Seller Performance

*One scatter chart, three additional worksheets (one with an embedded viz-in-tooltip), and one standalone mini-worksheet used only inside that tooltip.*

#### Quality vs. Revenue Scatter
| Pane / Shelf | Fields / Notes |
|---|---|
| Columns | `AVG(Avg Review Score)` |
| Rows | `SUM(Total Revenue)` — log-scale axis |
| Detail | `Seller Id` |
| Color | `Cluster Name` |

#### Tier vs. Cluster Agreement Matrix
| Pane / Shelf | Fields / Notes |
|---|---|
| Rows | `Performance Tier` |
| Columns | `Cluster Name` |
| Color | `CNTD(Seller Id)` |
| Label | `CNTD(Seller Id)`, `Pct Within Tier Row` |
| Calculated Fields Used | `Pct Within Tier Row` (table calc, Compute Using Cluster Name) |
| Filters | `Seller Id` filter (Context) to remove zero-count cells |
| Notes | Custom tooltip embeds the Tooltip - Quality vs Revenue Scatter Plot worksheet (Viz-in-Tooltip); see Section 3. |

#### Revenue at Risk: Manual vs. Cluster
| Pane / Shelf | Fields / Notes |
|---|---|
| Columns | Measure Names |
| Rows | Measure Values (`manual_RaR%`, `Cluster_RaR%`) |
| Color | Measure Names |
| Calculated Fields Used | `manual_RaR%`, `Cluster_RaR%` |

#### Seller Revenue Concentration (Lorenz Curve)
| Pane / Shelf | Fields / Notes |
|---|---|
| Columns | `Cumulative Pct of Entities` |
| Rows | Measure Values (`Cumulative Revenue Pct`, `Line of Equality`) |
| Color | Measure Names |
| Detail | `Entity Id` |
| Filters | Data source filter: Entity Type = "Seller" |
| Calculated Fields Used | `Line of Equality` |

#### Tooltip - Quality vs Revenue Scatter Plot
*Standalone mini-worksheet, never placed on a dashboard directly — embedded only inside the Tier vs. Cluster Matrix's tooltip (Section 3).*

| Pane / Shelf | Fields / Notes |
|---|---|
| Columns | `Avg Review Score` |
| Rows | `Total Revenue` — log-scale axis |
| Detail | `Seller Id`, `Performance Tier`, `Cluster Name` |

---

### Dashboard 3 — Regional & Delivery Ops

*One parameter-toggled choropleth map and four additional worksheets.*

#### Revenue / On-Time Rate / Avg Delivery Days Map
*Filled/choropleth map; shading measure switches based on the Map Measure Selector parameter.*

| Pane / Shelf | Fields / Notes |
|---|---|
| Detail | `State` |
| Color | `Selected Map Measure` |
| Calculated Fields Used | `Selected Map Measure` |
| Parameters | `Map Measure Selector` |
| Notes | Custom tooltip: State, Map Measure Selector, Selected Map Measure. Geographic Role on State field set to State/Province. |

#### Delivery Days by Macro-Region
| Pane / Shelf | Fields / Notes |
|---|---|
| Rows | `Region` |
| Columns | `AVG(Avg Delivery Days)` |
| Calculated Fields Used | `Region` |
| Sort | Descending by `AVG(Avg Delivery Days)` |

#### Review Score vs. Delivery Speed
| Pane / Shelf | Fields / Notes |
|---|---|
| Columns | `Dimension Value` ("Late" / "On-Time") |
| Rows | `AVG(Avg Review Score)` |
| Filters | Dimension = "On-time vs Late" |

#### Seller Supply Gap by State
| Pane / Shelf | Fields / Notes |
|---|---|
| Rows | `State` |
| Columns | `AVG(Orders Per Seller)` |
| Filters | Top 10 by `AVG(Orders Per Seller)` |
| Sort | Descending |

#### Revenue vs. Delivery Performance Quadrant
| Pane / Shelf | Fields / Notes |
|---|---|
| Columns | `AVG(On Time Rate)` |
| Rows | `SUM(Total Revenue)` |
| Label | `State` |
| Color | `Region` |
| Calculated Fields Used | `Region` |
| Notes | Reference lines at the Average value on both axes, forming the four quadrants. |

---

### Dashboard 4 — Product & Category

*One scatter chart and four additional worksheets, rebuilt from an earlier, weaker version of this dashboard.*

#### Order Volume vs Revenue per Category
| Pane / Shelf | Fields / Notes |
|---|---|
| Columns | `SUM(Total Orders)` |
| Rows | `SUM(Total Revenue)` |
| Detail | `Category` |
| Color | `AVG(Avg Review Score)` — sequential |
| Label | `Label Filter` |
| Calculated Fields Used | `Label Filter` |
| Notes | Reference lines at the Average value on both axes. |

#### Category Cluster Distribution
*Treemap.*

| Pane / Shelf | Fields / Notes |
|---|---|
| Color | `Cluster Name` |
| Detail | `CNTD(Category)`, used to drive treemap Size |
| Label | `Cluster Name`, `CNTD(Category)`, `Pct of Categories` |
| Calculated Fields Used | `Pct of Categories` |

#### Top 5 vs Bottom 5 by Review Score
| Pane / Shelf | Fields / Notes |
|---|---|
| Columns | `Top Bottom Flag`; `AVG(Avg Review Score)` |
| Rows | `Category` |
| Color | `Top Bottom Flag (Color)` — duplicate field, isolated from the Filters-shelf instance to avoid a shared table-calc addressing conflict |
| Filters | `Top Bottom Flag` (keep "Top 5" and "Bottom 5", exclude Null) |
| Calculated Fields Used | `Top Bottom Flag`, `Top Bottom Flag (Color)` |
| Sort | Descending by `AVG(Avg Review Score)` |

#### Top Revenue Driving Categories
*Table with a Grand Total row.*

| Pane / Shelf | Fields / Notes |
|---|---|
| Rows | `Category` |
| Label | `SUM(Total Revenue)`, `pct of Total Revenue` |
| Filters | Top 15 by `SUM(Total Revenue)` (Context filter) |
| Calculated Fields Used | `pct of Total Revenue` |
| Sort | Descending by `SUM(Total Revenue)` |
| Notes | Analysis → Totals → Show Row Grand Totals enabled. |

#### Category Revenue Concentration (Lorenz Curve)
| Pane / Shelf | Fields / Notes |
|---|---|
| Columns | `Cumulative Pct Categories` |
| Rows | Measure Values (`Cumulative Pct Revenue`, `Line of Equality`) |
| Color | Measure Names |
| Detail | `Category` |
| Calculated Fields Used | `Category Revenue Rank`, `Cumulative Pct Categories`, `Cumulative Pct Revenue`, `Line of Equality` |
| Notes | Reference lines at 20% of categories and the corresponding 76% of revenue. |

---

## 3. Interactive Elements

Beyond the static worksheets, the workbook has five interactive systems layered on top: a full segment drill-through dashboard, a viz-in-tooltip, dashboard-level cross-filtering, a two-way navigation system, and a scoped date-range parameter filter.

### 3.1 Customer Segment Deep-Dive (Drill-Through Dashboard)

A dedicated second dashboard, reached by clicking a bar on Dashboard 1's RFM Segment Distribution chart. Triggered by three simultaneous Dashboard Actions, all sourced from RFM Segment Distribution and run on Select:

- **Go to Sheet** — navigates to the drill-through dashboard.
- **Filter** — passes the clicked Segment value to every worksheet on the drill-through dashboard that shares the Segment field.
- **Change Parameter** — writes the clicked Segment value into the `selected segment` parameter, which drives the dashboard's dynamic title.

Contents of the drill-through dashboard:

#### Drill-Through - Total Customers
| Pane / Shelf | Fields / Notes |
|---|---|
| Label | `CNTD(Customer Unique Id)` |

#### Drill-Through - Total Spend
| Pane / Shelf | Fields / Notes |
|---|---|
| Label | `SUM(Total Spend)`, `pct of Platform Total` (subtitle) |
| Calculated Fields Used | `pct of Platform Total` |

#### Drill-Through - Total Orders
| Pane / Shelf | Fields / Notes |
|---|---|
| Label | `SUM(Order Count)`, `pct of Total Orders` (subtitle) |
| Calculated Fields Used | `pct of Total Orders` |

#### Drill-Through - Avg Order Value
| Pane / Shelf | Fields / Notes |
|---|---|
| Label | `AVG(Avg Order Value)` |

#### Drill-Through - Avg Days Since Last Order
| Pane / Shelf | Fields / Notes |
|---|---|
| Label | `AVG(Days Since Last Order)` |

#### Drill-Through - Avg Orders per Customer
| Pane / Shelf | Fields / Notes |
|---|---|
| Label | `order frequency` |
| Calculated Fields Used | `order frequency` |

#### Drill-Through - Repeat Rate
| Pane / Shelf | Fields / Notes |
|---|---|
| Label | `Repeat Rate %` |
| Calculated Fields Used | `Repeat Rate %` (reused from Dashboard 0, responds to the incoming segment filter) |

#### Drill-Through - Avg Customer Lifespan
| Pane / Shelf | Fields / Notes |
|---|---|
| Label | `AVG(Lifespan Days)`, restricted to `Lifespan Days` ≥ 2 inside the aggregation |
| Calculated Fields Used | Embedded IF inside the AVG (see Appendix, `Lifespan Deviation %`) |

#### Drill-Through - Segment Value Concentration
| Pane / Shelf | Fields / Notes |
|---|---|
| Columns | `Cumulative Pct Customers` |
| Rows | Measure Values (`Cumulative Pct Spend`, `Line of Equality`) |
| Color | Measure Names |
| Calculated Fields Used | `Customer Spend Rank`, `Cumulative Pct Customers`, `Cumulative Pct Spend`, `Line of Equality` |

#### Drill-Through - Segment vs Platform Deviation
*Diverging bar chart; each bar shows the selected segment's % deviation from the platform-wide baseline for one metric.*

| Pane / Shelf | Fields / Notes |
|---|---|
| Rows | Measure Names |
| Columns | Measure Values (`AOV Deviation`, `Recency Deviation`, `Order frequency Deviation`, `Repeat Rate Deviation`, `Lifespan Deviation`) |
| Color | Measure Values — diverging, centered at 0 |
| Calculated Fields Used | `AOV Deviation`, `Recency Deviation`, `Order frequency Deviation`, `Repeat Rate Deviation`, `Lifespan Deviation` |
| Notes | For Recency specifically, a negative bar indicates better-than-average performance (more recent activity) — the interpretation is reversed relative to the other four metrics. |

**Dashboard title:** dynamic, built from the `selected segment` parameter — reads "Customer Segment Deep-Dive: [selected segment]", defaulting to "About to Sleep" until a different segment is clicked.

### 3.2 Viz-in-Tooltip — Tier vs. Cluster Matrix

Hovering any cell of Dashboard 2's Tier vs. Cluster Agreement Matrix displays a custom tooltip combining text KPIs with an embedded mini-worksheet (Tooltip - Quality vs Revenue Scatter Plot), automatically filtered by Tableau to the hovered cell's Performance Tier and Cluster Name.

- Tooltip text: Sellers (`CNTD(Seller Id)`), Avg Revenue (`AVG(Total Revenue)`), Total Revenue (`SUM(Total Revenue)`), Avg Review Score (`AVG(Avg Review Score)`).
- Embedded sheet: Tooltip - Quality vs Revenue Scatter Plot, rendered at a fixed compact size inside the tooltip.

### 3.3 Cross-Filtering — Dashboard 1

Clicking a bar on RFM Segment Distribution filters the sibling worksheets on the same dashboard that share the Segment field, via a Filter Action (Source: RFM Segment Distribution; Run on: Select; Target Filters: Segment → Segment; Clearing the selection: Show all values).

### 3.4 Navigation

- **Nav panel (Dashboard 0)**: four Button objects, each with a native "Navigate to" target pointing to Dashboards 1–4.
- **Dashboards 1, 2, and 3**: two Button objects each — a Back button ("Navigate to" the previous dashboard in sequence) and a Next button ("Navigate to" the following dashboard in sequence).
- **Dashboard 4**: one Button object — Back to Overview ("Navigate to" Dashboard 0).

### 3.5 Date Range Filter (Dashboard 0 only)

Deliberately scoped to the two genuine time-series charts on Dashboard 0 (Monthly Revenue Trend and New Customers Over Time). Excluded from all KPIs and from every other dashboard, since the remaining charts are current-state snapshots (RFM segments, CLV tiers, cluster assignments) or already use their own fixed date anchors, and would produce incorrect or meaningless results if a generic date filter were applied to their underlying rows.

- Parameters: `Date Range Start`, `Date Range End` (both Date type, Range allowable values, Sep 2016 – Aug 2018).
- Calculated fields: `In Date Range`, built once per qualifying data source (New vs Returning Revenue; Customer Analytics), each comparing that source's date field against both parameters.

---

## 4. Conclusion

The workbook documented here comprises five dashboards built from a consistent anchor-plus-supporting-visuals pattern, backed by a shared library of calculated fields and LOD expressions reused deliberately across dashboards (percentage-of-total patterns, Lorenz-curve concentration curves, macro-region lookups, and RANK/RUNNING_SUM-based cumulative calculations).

Beyond static visualization, the workbook demonstrates four distinct layers of Tableau interactivity: a fully-parameterized drill-through dashboard with a dynamic title, a viz-in-tooltip embedding a live filtered mini-chart, dashboard-level cross-filtering, and a deliberately-scoped date-range parameter applied only where it produces meaningful results. Each of these was chosen and scoped based on where it added genuine analytical value, with several candidate features (a fully cross-dashboard date filter, additional KPI change indicators, a customer-detail drill-through table) deliberately scoped down or dropped after review, in favor of the features that survived scrutiny.

This document, together with the workbook itself, is intended to serve as a complete, field-level record of how the platform was built — sufficient for another analyst (or a future version of the author) to understand, audit, or extend any worksheet without needing to reverse-engineer its construction from the rendered chart alone.

---

## 5. Appendix — Calculated Field & LOD Dictionary

Every calculated field and LOD (Level of Detail) expression used in a workbook visualization, listed once. Field names match their exact names in the Tableau Data pane.

| Field Name | Definition | Formula |
|---|---|---|
| `Pct Active Customers` | % of customers active in the last 180 days | `COUNTD(IF [Customer Status]="Active" THEN [Customer Unique Id] END) / COUNTD([Customer Unique Id])` |
| `Pct Active Sellers` | % of sellers currently flagged Active | `COUNTD(IF [Seller Status]="Active" THEN [Seller Id] END) / COUNTD([Seller Id])` |
| `Average Order Value (AOV)` | Platform-wide average order value | `SUM([Total Revenue]) / SUM([Total Orders])` |
| `Repeat Rate %` | % of customers with 2 or more orders — reused platform-wide (Dashboard 0) and, once filtered by the segment drill-through, at the segment level | `COUNTD(IF [Order Count]>1 THEN [Customer Unique Id] END) / COUNTD([Customer Unique Id])` |
| `In Date Range` (New vs Returning Revenue) | Restricts monthly revenue rows to the selected date window | `[Order Month] >= [Date Range Start] AND [Order Month] <= [Date Range End]` |
| `In Date Range` (Customer Analytics) | Restricts new-customer rows to the selected date window | `[First Order Date] >= [Date Range Start] AND [First Order Date] <= [Date Range End]` |
| `pct of Total Customers` | A row's share of the total customer base | `COUNTD([Customer Unique Id]) / TOTAL(COUNTD([Customer Unique Id]))` |
| `pct of Total Spend` | A row's share of total platform spend | `SUM([Total Spend]) / TOTAL(SUM([Total Spend]))` |
| `order frequency` | Average orders per customer — reused platform-wide (Dashboard 0 context) and, once filtered, at the segment level (drill-through) | `SUM([Order Count]) / COUNTD([Customer Unique Id])` |
| `Pct Within Segment Row` | % of an RFM segment's customers falling into a given CLV tier | `COUNTD([Customer Unique Id]) / TOTAL(COUNTD([Customer Unique Id]))` — Compute Using: CLV Tier |
| `Pct Within Tier Row` | % of a performance tier's sellers falling into a given ML cluster | `COUNTD([Seller Id]) / TOTAL(COUNTD([Seller Id]))` — Compute Using: Cluster Name |
| `First Order Date` | A customer's earliest purchase date (LOD) | `{FIXED [Customer Unique Id] : MIN([Purchase Date Key])}` |
| `Second Order Date` | A customer's second purchase date, or Null if none exists (nested LOD) | `{FIXED [Customer Unique Id] : MIN(IF [Purchase Date Key] > {FIXED [Customer Unique Id] : MIN([Purchase Date Key])} THEN [Purchase Date Key] END)}` |
| `Days to Second Purchase` | Days elapsed between a customer's first and second order | `DATEDIFF('day', [First Order Date], [Second Order Date])` |
| `Days to Second Purchase Buckets` | Behavioral bucket for time-to-repeat-purchase | `IF [Days to Second Purchase]<=15 THEN "1-15 days" ELSEIF [Days to Second Purchase]<=30 THEN "16-30 days" ELSEIF [Days to Second Purchase]<=90 THEN "31-90 days" ELSEIF [Days to Second Purchase]<=180 THEN "91-180 days" ELSEIF [Days to Second Purchase]<=360 THEN "180-360 days" ELSE "360+ days" END` |
| `manual_RaR%` | % of platform revenue from sellers manually flagged at-risk (Average / Needs Work tiers) | `SUM(IF [Performance Tier]="Average" OR [Performance Tier]="Needs Work" THEN [Total Revenue] ELSE 0 END) / SUM([Total Revenue])` |
| `Cluster_RaR%` | % of platform revenue from sellers ML-flagged at-risk (Non-Elite cluster) | `SUM(IF [Cluster Name]="Non-Elite" THEN [Total Revenue] ELSE 0 END) / SUM([Total Revenue])` |
| `Region` | Maps each of the 27 Brazilian states to one of 5 macro-regions | `CASE [State] WHEN "AC" THEN "North" WHEN "AP" THEN "North" … (27 states mapped to North / Northeast / Central-West / Southeast / South) END` |
| `Selected Map Measure` | Switches the shaded measure on the Revenue / On-Time Rate / Avg Delivery Days Map, based on the Map Measure Selector parameter | `CASE [Map Measure Selector] WHEN "Revenue" THEN SUM([Total Revenue]) WHEN "On-Time Rate" THEN AVG([On Time Rate]) WHEN "Avg Delivery Days" THEN AVG([Avg Delivery Days]) END` |
| `Label Filter` | Shows a category's name as a chart label only if it exceeds a revenue or order-volume threshold | `IF SUM([Total Revenue]) > 208375 OR SUM([Total Orders]) > 1314.54 THEN ATTR([Category]) END` |
| `Pct of Categories` | A category's share of the total number of categories (Category Cluster Distribution treemap labels) | `COUNTD([Category]) / TOTAL(COUNTD([Category]))` |
| `Top Bottom Flag` | Flags each category as Top 5 or Bottom 5 by review score | `IF RANK(SUM([Avg Review Score]),'desc')<=5 THEN "Top 5" ELSEIF RANK(SUM([Avg Review Score]),'asc')<=5 THEN "Bottom 5" END` |
| `Top Bottom Flag (Color)` | Duplicate of Top Bottom Flag, isolated to the Color shelf to avoid a shared table-calc addressing conflict | Identical formula to `Top Bottom Flag`, with an added `ELSE "Other"` branch |
| `pct of Total Revenue` | A category's true share of platform-wide revenue, unaffected by the Top N filter | `SUM([Total Revenue]) / {FIXED : SUM([Total Revenue])}` |
| `Category Revenue Rank` | Rank of a category by total revenue, descending | `RANK(SUM([Total Revenue]),'desc')` |
| `Cumulative Pct Categories` | Running % of categories, ordered by revenue rank (Category Lorenz curve, x-axis) | `RUNNING_SUM(1) / TOTAL(COUNTD([Category]))` — Compute Using: Category, sorted by SUM(Total Revenue) desc |
| `Cumulative Pct Revenue` | Running % of revenue captured, ordered by revenue rank (Category Lorenz curve, y-axis) | `RUNNING_SUM(SUM([Total Revenue])) / TOTAL(SUM([Total Revenue]))` — Compute Using: Category, sorted by SUM(Total Revenue) desc |
| `Line of Equality` (Category) | 45° reference diagonal for the Category Lorenz curve | `[Cumulative Pct Categories]` |
| `Line of Equality` (Seller) | 45° reference diagonal for the Seller Lorenz curve | `[Cumulative Pct of Entities]` |
| `Line of Equality` (Segment) | 45° reference diagonal for the Segment Value Concentration curve | `[Cumulative Pct Customers]` |
| `Customer Spend Rank` | Rank of a customer by total spend within the filtered segment, descending | `RANK(SUM([Total Spend]),'desc')` |
| `Cumulative Pct Customers` | Running % of customers, ordered by spend rank (Segment Lorenz curve, x-axis) | `RUNNING_SUM(1) / TOTAL(COUNTD([Customer Unique Id]))` — Compute Using: Customer Unique Id, sorted by SUM(Total Spend) desc |
| `Cumulative Pct Spend` | Running % of spend captured, ordered by spend rank (Segment Lorenz curve, y-axis) | `RUNNING_SUM(SUM([Total Spend])) / TOTAL(SUM([Total Spend]))` — Compute Using: Customer Unique Id, sorted by SUM(Total Spend) desc |
| `pct of Platform Total` | Filtered segment's spend as a share of true platform-wide spend (Drill-Through Total Spend KPI subtitle) | `SUM([Total Spend]) / {FIXED : SUM([Total Spend])}` |
| `pct of Total Orders` | Filtered segment's order count as a share of true platform-wide orders (Drill-Through Total Orders KPI subtitle) | `SUM([Order Count]) / {FIXED : SUM([Order Count])}` |
| `AOV Deviation` | Filtered segment's average order value as a % deviation from the platform-wide baseline | `(AVG([Avg Order Value]) - {FIXED : AVG([Avg Order Value])}) / {FIXED : AVG([Avg Order Value])}` |
| `Recency Deviation` | Filtered segment's average recency as a % deviation from the platform-wide baseline. Negative = more recent = better, the inverse of the other four deviation metrics. | `(AVG([Days Since Last Order]) - {FIXED : AVG([Days Since Last Order])}) / {FIXED : AVG([Days Since Last Order])}` |
| `Order frequency Deviation` | Filtered segment's order frequency as a % deviation from the platform-wide baseline | `(SUM([Order Count]) / COUNTD([Customer Unique Id]) - {FIXED : SUM([Order Count])} / {FIXED : COUNTD([Customer Unique Id])}) / ({FIXED : SUM([Order Count])} / {FIXED : COUNTD([Customer Unique Id])})` |
| `Repeat Rate Deviation` | Filtered segment's repeat rate as a % deviation from the platform-wide baseline | `(COUNTD(IF [Order Count]>1 THEN [Customer Unique Id] END) / COUNTD([Customer Unique Id]) - {FIXED : COUNTD(IF [Order Count]>1 THEN [Customer Unique Id] END)} / {FIXED : COUNTD([Customer Unique Id])}) / ({FIXED : COUNTD(IF [Order Count]>1 THEN [Customer Unique Id] END)} / {FIXED : COUNTD([Customer Unique Id])})` |
| `Lifespan Deviation` | Filtered segment's average customer lifespan (repeat customers only, ≥2 days) as a % deviation from the platform-wide baseline | `(AVG(IF [Lifespan Days]>=2 THEN [Lifespan Days] END) - {FIXED : AVG(IF [Lifespan Days]>=2 THEN [Lifespan Days] END)}) / {FIXED : AVG(IF [Lifespan Days]>=2 THEN [Lifespan Days] END)}` |

### Parameters (for reference — not calculated fields)

- **`Date Range Start`** / **`Date Range End`** — Date type, Range, Sep 2016–Aug 2018. Drive the Dashboard 0 date filter.
- **`Map Measure Selector`** — String type, List (Revenue / On-Time Rate / Avg Delivery Days). Drives the shaded measure on Dashboard 3's Revenue / On-Time Rate / Avg Delivery Days Map.
- **`selected segment`** — String type, All allowable values, default "About to Sleep". Set via a Change Parameter action; drives the drill-through dashboard's dynamic title.
