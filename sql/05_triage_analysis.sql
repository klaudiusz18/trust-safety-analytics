-- ============================================================
-- 05_triage_analysis.sql
-- Trust & Safety Analytics Portfolio
-- ============================================================
-- Purpose:
--   Create a synthetic analytical triage score to help prioritise
--   cases for deeper review.
--
-- Important:
--   This is NOT an enforcement policy or production decision rule.
--   It is a portfolio demonstration of analytical prioritisation.
--
-- Scoring:
--   Critical priority       +30
--   High priority           +20
--   Medium priority         +10
--   Low priority             +0
--
--   Risk score >= 0.80      +25
--   Risk score >= 0.60      +15
--   Risk score >= 0.40       +5
--   Risk score <  0.40      +0
--
--   AI-human disagreement   +20
--   Escalation              +15
--   Appeal                  +10
--   High-confidence error   +20
--
-- Triage levels:
--   >= 80  Very High
--   >= 60  High
--   >= 40  Medium
--   <  40  Low
-- ============================================================


-- ============================================================
-- 1. Case-level triage scoring
-- ============================================================

WITH model_comparison AS (

    SELECT
        c.case_id,
        c.priority,
        c.risk_score,

        CASE
            WHEN c.priority = 'Critical' THEN 30
            WHEN c.priority = 'High' THEN 20
            WHEN c.priority = 'Medium' THEN 10
            ELSE 0
        END AS priority_points,

        CASE
            WHEN c.risk_score >= 0.80 THEN 25
            WHEN c.risk_score >= 0.60 THEN 15
            WHEN c.risk_score >= 0.40 THEN 5
            ELSE 0
        END AS risk_points,

        CASE
            WHEN mp.prediction <> hr.decision THEN 20
            ELSE 0
        END AS disagreement_points,

        CASE
            WHEN EXISTS (
                SELECT 1
                FROM escalations e
                WHERE e.case_id = c.case_id
            ) THEN 15
            ELSE 0
        END AS escalation_points,

        CASE
            WHEN EXISTS (
                SELECT 1
                FROM appeals a
                WHERE a.case_id = c.case_id
            ) THEN 10
            ELSE 0
        END AS appeal_points,

        CASE
            WHEN mp.prediction <> hr.decision
                 AND mp.confidence >= 0.80
                THEN 20
            ELSE 0
        END AS high_confidence_error_points

    FROM cases c

    JOIN human_reviews hr
        ON c.case_id = hr.case_id

    JOIN model_predictions mp
        ON c.case_id = mp.case_id
       AND mp.model_version = 'v3.2'

    WHERE c.case_id BETWEEN 1007 AND 11006
),

triage AS (

    SELECT
        *,
        priority_points
        + risk_points
        + disagreement_points
        + escalation_points
        + appeal_points
        + high_confidence_error_points
        AS triage_score

    FROM model_comparison
)

SELECT
    case_id,
    priority,
    risk_score,
    triage_score,

    CASE
        WHEN triage_score >= 80 THEN 'Very High'
        WHEN triage_score >= 60 THEN 'High'
        WHEN triage_score >= 40 THEN 'Medium'
        ELSE 'Low'
    END AS triage_level

FROM triage

ORDER BY triage_score DESC, case_id;


-- ============================================================
-- 2. Triage-level validation
-- ============================================================

WITH model_comparison AS (

    SELECT
        c.case_id,
        c.risk_score,

        CASE
            WHEN c.priority = 'Critical' THEN 30
            WHEN c.priority = 'High' THEN 20
            WHEN c.priority = 'Medium' THEN 10
            ELSE 0
        END AS priority_points,

        CASE
            WHEN c.risk_score >= 0.80 THEN 25
            WHEN c.risk_score >= 0.60 THEN 15
            WHEN c.risk_score >= 0.40 THEN 5
            ELSE 0
        END AS risk_points,

        CASE
            WHEN mp.prediction <> hr.decision THEN 20
            ELSE 0
        END AS disagreement_points,

        CASE
            WHEN EXISTS (
                SELECT 1
                FROM escalations e
                WHERE e.case_id = c.case_id
            ) THEN 15
            ELSE 0
        END AS escalation_points,

        CASE
            WHEN EXISTS (
                SELECT 1
                FROM appeals a
                WHERE a.case_id = c.case_id
            ) THEN 10
            ELSE 0
        END AS appeal_points,

        CASE
            WHEN mp.prediction <> hr.decision
                 AND mp.confidence >= 0.80
                THEN 20
            ELSE 0
        END AS high_confidence_error_points,

        CASE
            WHEN EXISTS (
                SELECT 1
                FROM escalations e
                WHERE e.case_id = c.case_id
            ) THEN 1
            ELSE 0
        END AS escalated,

        CASE
            WHEN EXISTS (
                SELECT 1
                FROM appeals a
                WHERE a.case_id = c.case_id
            ) THEN 1
            ELSE 0
        END AS appealed,

        CASE
            WHEN mp.prediction <> hr.decision THEN 1
            ELSE 0
        END AS disagreement

    FROM cases c

    JOIN human_reviews hr
        ON c.case_id = hr.case_id

    JOIN model_predictions mp
        ON c.case_id = mp.case_id
       AND mp.model_version = 'v3.2'

    WHERE c.case_id BETWEEN 1007 AND 11006
),

triage AS (

    SELECT
        *,
        priority_points
        + risk_points
        + disagreement_points
        + escalation_points
        + appeal_points
        + high_confidence_error_points
        AS triage_score

    FROM model_comparison
),

classified AS (

    SELECT
        *,
        CASE
            WHEN triage_score >= 80 THEN 'Very High'
            WHEN triage_score >= 60 THEN 'High'
            WHEN triage_score >= 40 THEN 'Medium'
            ELSE 'Low'
        END AS triage_level
    FROM triage
)

SELECT
    triage_level,

    COUNT(*) AS total_cases,

    ROUND(
        AVG(risk_score),
        3
    ) AS avg_risk_score,

    ROUND(
        AVG(escalated) * 100,
        2
    ) AS escalation_rate,

    ROUND(
        AVG(appealed) * 100,
        2
    ) AS appeal_rate,

    ROUND(
        AVG(disagreement) * 100,
        2
    ) AS disagreement_rate

FROM classified

GROUP BY triage_level

ORDER BY
    CASE triage_level
        WHEN 'Very High' THEN 1
        WHEN 'High' THEN 2
        WHEN 'Medium' THEN 3
        ELSE 4
    END;


-- ============================================================
-- 3. Highest-priority analytical cases
-- ============================================================

WITH model_comparison AS (

    SELECT
        c.case_id,
        c.priority,
        c.risk_score,
        mp.prediction,
        mp.confidence,
        hr.decision,

        CASE
            WHEN c.priority = 'Critical' THEN 30
            WHEN c.priority = 'High' THEN 20
            WHEN c.priority = 'Medium' THEN 10
            ELSE 0
        END
        +
        CASE
            WHEN c.risk_score >= 0.80 THEN 25
            WHEN c.risk_score >= 0.60 THEN 15
            WHEN c.risk_score >= 0.40 THEN 5
            ELSE 0
        END
        +
        CASE
            WHEN mp.prediction <> hr.decision THEN 20
            ELSE 0
        END
        +
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM escalations e
                WHERE e.case_id = c.case_id
            ) THEN 15
            ELSE 0
        END
        +
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM appeals a
                WHERE a.case_id = c.case_id
            ) THEN 10
            ELSE 0
        END
        +
        CASE
            WHEN mp.prediction <> hr.decision
                 AND mp.confidence >= 0.80
                THEN 20
            ELSE 0
        END AS triage_score

    FROM cases c

    JOIN human_reviews hr
        ON c.case_id = hr.case_id

    JOIN model_predictions mp
        ON c.case_id = mp.case_id
       AND mp.model_version = 'v3.2'

    WHERE c.case_id BETWEEN 1007 AND 11006
)

SELECT
    case_id,
    priority,
    risk_score,
    prediction,
    confidence,
    decision,
    triage_score

FROM model_comparison

WHERE prediction <> decision

ORDER BY triage_score DESC, risk_score DESC

LIMIT 25;


-- ============================================================
-- End of triage analysis
-- ============================================================