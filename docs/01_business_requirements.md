# Business Requirements Document
## Marketplace Analytics Platform

## 1. Executive Summary

The Marketplace Analytics Platform is an end-to-end data and analytics platform built on real Brazilian e-commerce data from Olist, a marketplace connecting small and medium-sized sellers to customers across Brazil. The platform transforms approximately 100,000 raw transactional records spanning 2016–2018 into a structured, queryable PostgreSQL data warehouse, a suite of SQL analytical views and Python analysis notebooks, and an interactive Tableau dashboard surfacing customer, seller, product, and regional intelligence.

The project demonstrates a complete, production-grade data analyst and BI workflow — from raw data profiling and quality assessment through schema design, ETL pipeline development, multi-dimensional SQL analytics, statistical analysis in Python, and self-service dashboard delivery. The platform's ambition is to not just report on what happened, but to surface the actionable marketplace insights that drives business value.

---

## 2. Business Context

Olist operates as a marketplace intermediary in Brazil's e-commerce sector, connecting thousands of independent sellers to a national customer base. Its business model depends on the health of two distinct groups simultaneously — end consumers who purchase products, and the sellers who list and fulfill those orders — making it an analytically rich domain that touches customer behaviour, seller performance, logistics, and geographic distribution.

The dataset used in this project is a real, anonymized export of Olist's order data published on Kaggle, covering approximately 100,000 orders across 9 relational tables. It captures every stage of the order lifecycle: customer identity, product listings, seller fulfillment, payment processing, logistics timestamps, and post-delivery reviews. Brazil's unique e-commerce characteristics — including a strong installment payment culture, significant geographic spread across 27 states, and high import-driven product pricing — add domain-specific depth to the analysis that goes beyond a generic e-commerce template.

This breadth and richness makes the dataset well suited for demonstrating the kind of multi-dimensional, marketplace-centric analysis that retail and e-commerce businesses rely on for both operational and strategic decision-making.

---

## 3. Problem Statement

Raw transactional data, no matter how rich, is not intelligence. Without a structured analytical layer, Olist's data cannot answer the questions that matter most to the business:

- Who are the most valuable customers, and which ones are at risk of churning?
- Which sellers are driving the best customer experience, and which are damaging it?
- Where is revenue concentrated geographically, and where are the growth opportunities?
- Are customers coming back, or is the platform primarily acquiring one-time buyers?
- Does the delivery experience drive customer satisfaction, or is it product and price?
- What percentage of revenue comes from customers the platform already had?

These questions require more than a spreadsheet or a one-off SQL query. They require a validated data warehouse, well-designed analytical views, statistical analysis in Python, and a visual layer that makes answers accessible to non-technical stakeholders. This project builds that foundation from scratch — starting with 9 raw CSV files and ending with a production-grade warehouse, a SQL analytical layer, Python analysis notebooks, and a Tableau dashboard suite.

---

## 4. Project Objectives

| # | Objective | Why It Matters |
|---|---|---|
| O1 | Profile and validate all 9 raw data sources | Ensures the analytical foundation is built on trustworthy, well-understood data |
| O2 | Design and implement a PostgreSQL star schema | Provides a structured, query-optimized single source of truth for all analysis |
| O3 | Build a Python ETL pipeline | Automates data loading with documented cleaning rules, making the warehouse reproducible and maintainable |
| O4 | Develop SQL analytical views | Translates raw warehouse data into business-ready metrics across customer, seller, product, payment, and regional dimensions |
| O5 | Deliver Python analysis notebooks | Provides deep statistical analysis, cohort visualizations, and insight narratives that go beyond what SQL alone can express |
| O6 | Deliver a Tableau dashboard suite | Makes insights accessible to non-technical stakeholders without requiring SQL or Python knowledge |

---

## 5. Scope

The platform covers the complete analytical lifecycle from raw data to business intelligence across five sequential phases: data assessment and quality validation, warehouse design and ETL, SQL and Python analytics, Tableau dashboard delivery, and documentation finalization.

The analytical coverage spans four business dimensions — customer intelligence (segmentation, lifetime value, retention, health scoring), seller performance (scorecards, health scores, review response patterns), product intelligence (category affinity, pricing patterns), and regional analysis (revenue and customer distribution across Brazil's 27 states). The platform is built entirely on real, validated transactional data with no synthetic inputs, and is fully reproducible from a clean repository clone.

---

## 6. Deliverables

| Phase | Deliverable |
|---|---|
| Phase 1 — Data Assessment | EDA/quality notebooks, star schema DDL, schema documentation, data dictionary, data quality report |
| Phase 2 — ETL Pipeline | Python ETL script, fully populated and validated PostgreSQL warehouse, methodology documentation, data provenance statement |
| Phase 3 — Analytics |  SQL views,  Python analysis notebooks, findings report |
| Phase 4 — Dashboard | 5-dashboard Tableau workbook, screenshots, dashboard guide |
| Phase 5 — Documentation | README, complete `/docs` folder, final Git tag `v1.0` |

---

## 7. Tech Stack

| Layer | Tool |
|---|---|
| Data Warehouse | PostgreSQL (local) |
| Data Processing & Analysis | Python 3.11 — pandas, numpy, SQLAlchemy, psycopg2, matplotlib, seaborn, scipy, statsmodels, scikit-learn |
| Development Environment | Conda (`Marketplace-Analytics-Platform`), JupyterLab |
| Visualization | Tableau Desktop / Tableau Public |
| Version Control | Git / GitHub |
| Documentation | Markdown |

---

*This project uses real, anonymized data published by Olist on Kaggle under a Creative Commons Attribution Non-Commercial Share-Alike 4.0 International license. No synthetic data has been used or introduced at any stage.*
