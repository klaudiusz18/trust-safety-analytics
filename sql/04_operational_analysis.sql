-- ============================================================
-- 04_operational_analysis.sql
-- Trust & Safety Analytics Portfolio
-- ============================================================
-- Purpose:
--   Operational analytics for Trust & Safety case handling.
--
-- Includes:
--   1. Executive operational KPIs
--   2. Monthly operational trends
--   3. Escalation analysis
--   4. SLA compliance
--   5. Appeal outcomes
--
-- Note:
--   Thresholds used in this portfolio are synthetic analytical
--   assumptions for demonstration purposes.
-- ============================================================


-- ============================================================
-- 1. Executive operational KPIs
-- ============================================================

SELECT
    COUNT(DISTINCT c.case_id) AS total_cases,

    ROUND(
        COUNT(*) FILTER (
            WHERE hr.decision = 'Violation'
        )::numeric
        / COUNT(*) * 100,
        2
    ) AS violation_rate,

    ROUND(
        COUNT(*) FILTER (
            WHERE mp.prediction <> hr.decision
        )::numeric
        / COUNT(*) * 100,
        2
    ) AS ai_human_disagreement_rate,

    ROUND(
        COUNT(DISTINCT e.case_id)::numeric
        / COUNT(DISTINCT c.case_id) * 100,
        2
    ) AS escalation_rate,

    ROUND(
        AVG(hr.review_duration_minutes),
        2
    ) AS avg_review_minutes,

    ROUND(
        COUNT(DISTINCT a.case_id)::numeric
        / COUNT(DISTINCT c.case_id) * 100,
        2
    ) AS appeal_rate

FROM cases c
JOIN human_reviews hr
    ON c.case_id = hr.case_id
JOIN model_predictions mp
    ON c.case_id = mp.case_id
   AND mp.model_version = 'v3.2'
LEFT JOIN escalations e
    ON c.case_id = e.case_id
LEFT JOIN appeals a
    ON c.case_id = a.case_id

WHERE c.case_id BETWEEN 1007 AND 11006;


-- ============================================================
-- 2. Monthly operational trends
-- ============================================================

SELECT
    DATE_TRUNC('month', c.created_at)::date AS month,

    COUNT(DISTINCT c.case_id) AS total_cases,

    COUNT(*) FILTER (
        WHERE hr.decision = 'Violation'
    ) AS violations,

    ROUND(
        COUNT(*) FILTER (
            WHERE hr.decision = 'Violation'
        )::numeric
        / COUNT(*) * 100,
        2
    ) AS violation_rate,

    COUNT(DISTINCT e.case_id) AS escalated_cases,

    ROUND(
        COUNT(DISTINCT e.case_id)::numeric
        / COUNT(DISTINCT c.case_id) * 100,
        2
    ) AS escalation_rate,

    COUNT(DISTINCT a.case_id) AS appealed_cases,

    ROUND(
        COUNT(DISTINCT a.case_id)::numeric
        / COUNT(DISTINCT c.case_id) * 100,
        2
    ) AS appeal_rate

FROM cases c

JOIN human_reviews hr
    ON c.case_id = hr.case_id

LEFT JOIN escalations e
    ON c.case_id = e.case_id

LEFT JOIN appeals a
    ON c.case_id = a.case_id

WHERE c.case_id BETWEEN 1007 AND 11006

GROUP BY DATE_TRUNC('month', c.created_at)

ORDER BY month;


-- ============================================================
-- 3. Escalation rate by AI-human agreement
-- ============================================================

WITH agreement_status AS (

    SELECT
        c.case_id,

        CASE
            WHEN mp.prediction = hr.decision
                THEN 'Agreement'
            ELSE 'Disagreement'
        END AS agreement_status

    FROM cases c

    JOIN human_reviews hr
        ON c.case_id = hr.case_id

    JOIN model_predictions mp
        ON c.case_id = mp.case_id
       AND mp.model_version = 'v3.2'

    WHERE c.case_id BETWEEN 1007 AND 11006
)

SELECT
    s.agreement_status,

    COUNT(*) AS total_cases,

    COUNT(e.case_id) AS escalated_cases,

    ROUND(
        COUNT(e.case_id)::numeric
        / COUNT(*) * 100,
        2
    ) AS escalation_rate

FROM agreement_status s

LEFT JOIN escalations e
    ON s.case_id = e.case_id

GROUP BY s.agreement_status

ORDER BY s.agreement_status;


-- ============================================================
-- 4. SLA compliance by escalation level
-- ============================================================
-- Synthetic SLA assumptions:
--   Level 1 <= 2 days
--   Level 2 <= 3 days
--   Level 3 <= 5 days

WITH sla AS (

    SELECT
        escalation_level,

        COUNT(*) AS total_escalations,

        COUNT(*) FILTER (
            WHERE resolved_at - escalated_at <=
                CASE
                    WHEN escalation_level = 1
                        THEN INTERVAL '2 days'
                    WHEN escalation_level = 2
                        THEN INTERVAL '3 days'
                    WHEN escalation_level = 3
                        THEN INTERVAL '5 days'
                END
        ) AS within_sla

    FROM escalations

    GROUP BY escalation_level
)

SELECT
    escalation_level,
    total_escalations,
    within_sla,

    total_escalations - within_sla AS sla_breaches,

    ROUND(
        within_sla::numeric
        / total_escalations * 100,
        2
    ) AS sla_compliance_rate

FROM sla

ORDER BY escalation_level;


-- ============================================================
-- 5. Overall SLA compliance
-- ============================================================

WITH sla AS (

    SELECT
        escalation_level,
        escalated_at,
        resolved_at,

        CASE
            WHEN escalation_level = 1
                THEN INTERVAL '2 days'
            WHEN escalation_level = 2
                THEN INTERVAL '3 days'
            WHEN escalation_level = 3
                THEN INTERVAL '5 days'
        END AS sla_target

    FROM escalations
)

SELECT
    COUNT(*) AS total_escalations,

    COUNT(*) FILTER (
        WHERE resolved_at - escalated_at <= sla_target
    ) AS within_sla,

    COUNT(*) FILTER (
        WHERE resolved_at - escalated_at > sla_target
    ) AS sla_breaches,

    ROUND(
        COUNT(*) FILTER (
            WHERE resolved_at - escalated_at <= sla_target
        )::numeric
        / COUNT(*) * 100,
        2
    ) AS sla_compliance_rate

FROM sla;


-- ============================================================
-- 6. Appeal outcomes
-- ============================================================

SELECT
    appeal_outcome,

    COUNT(*) AS appeal_count,

    ROUND(
        COUNT(*)::numeric
        / SUM(COUNT(*)) OVER () * 100,
        2
    ) AS outcome_rate

FROM appeals

WHERE case_id BETWEEN 1007 AND 11006

GROUP BY appeal_outcome

ORDER BY appeal_count DESC;


-- ============================================================
-- 7. Appeal change rate
-- ============================================================
-- "Changed" means Overturned or Partially Overturned.

SELECT

    COUNT(*) AS total_appeals,

    COUNT(*) FILTER (
        WHERE appeal_outcome IN (
            'Overturned',
            'Partially Overturned'
        )
    ) AS changed_appeals,

    ROUND(
        COUNT(*) FILTER (
            WHERE appeal_outcome IN (
                'Overturned',
                'Partially Overturned'
            )
        )::numeric
        / COUNT(*) * 100,
        2
    ) AS appeal_change_rate

FROM appeals

WHERE case_id BETWEEN 1007 AND 11006;


-- ============================================================
-- End of operational analysis
-- ============================================================