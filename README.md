# Trust & Safety Analytics: AI Model Evaluation & Operational Risk

## Overview

End-to-end Trust & Safety analytics project using PostgreSQL, SQL and Power BI to evaluate AI moderation models, identify policy risk, and analyse operational performance.

The project demonstrates skills relevant to Trust & Safety Analytics, AI/ML quality analysis, SQL, data quality, operational analytics and risk prioritisation.

## Power BI Dashboard

### Executive Dashboard

![Executive Dashboard](screenshots/Executive_Dashboard.PNG)

### Trust & Safety Investigation

![Trust & Safety Investigation](screenshots/Trust_Safety_Investigation.PNG)

## Tools

- PostgreSQL
- DBeaver
- Power BI Desktop
- DAX
- GitHub

## Dataset

Synthetic Trust & Safety dataset covering approximately 10,000 cases, users, policies, human reviews, AI predictions, model versions, escalations and appeals.

**Important:** All data, model behaviour, thresholds and results are synthetic and were created for portfolio demonstration purposes. They should not be interpreted as real-platform evidence.

## Key Analysis

### AI Model Evaluation

| Model | Precision | Recall | F1 |
|---|---:|---:|---:|
| v3.1 | 91.4% | 83.9% | 87.5% |
| **v3.2** | **94.0%** | **89.7%** | **91.8%** |
| v3.3 | 89.5% | **92.3%** | 90.9% |

**Recommendation:** v3.2 provides the strongest overall balance of precision, recall and F1. v3.3 improves recall but creates more false positives.

### Policy Risk

**Regulated Goods** is the main synthetic safety hotspot, with a **22.5% missed-violation rate**, materially above the other policies.

### Operational KPIs

| KPI | Result |
|---|---:|
| Total Cases | 10,000 |
| Violation Rate | 53.94% |
| Escalation Rate | 18.36% |
| SLA Compliance | 77.18% |

### AI-Human Agreement

For model v3.2, disagreement did **not** increase escalation or appeal-change rates in this dataset.

| Status | Escalation Rate | Appeal Change Rate |
|---|---:|---:|
| Agreement | 18.5% | 33.8% |
| Disagreement | 16.7% | 31.2% |

This demonstrates testing assumptions against data rather than treating them as facts.

## SQL Skills Demonstrated

- Joins and aggregations
- CTEs
- CASE logic
- Window functions
- Date/time analysis
- Precision, recall and F1 calculation
- SLA analysis
- Operational KPI reporting
- Risk prioritisation
- Reusable SQL views
- Data quality validation

## Project Structure

```text
Trust & Safety SQL Projects/
├── README.md
├── sql/
│   ├── 01_schema.sql
│   ├── 02_data_generation.sql
│   ├── 03_views.sql
│   ├── 04_operational_analysis.sql
│   └── 05_triage_analysis.sql
├── powerbi/
│   └── Trust_Safety_Analytics.pbix
├── screenshots/
│   ├── Executive_Dashboard.png
│   └── Trust_Safety_Investigation.png
└── documentation/
```

## Key Takeaways

- **v3.2** is the preferred baseline model in the synthetic analysis.
- **Regulated Goods** is the primary model-risk hotspot.
- Model release analysis highlights a clear precision/recall trade-off.
- Operational and model metrics were combined to support Trust & Safety decision-making.
- The project demonstrates how SQL analysis can be translated into an executive Power BI dashboard.

## Author

**Klaudiusz Nowakowski**
