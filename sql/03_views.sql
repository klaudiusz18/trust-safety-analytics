CREATE OR REPLACE VIEW public.agreement_operational_analysis AS  WITH base AS (
         SELECT c.case_id,
                CASE
                    WHEN mp.prediction::text = hr.decision::text THEN 'Agreement'::text
                    ELSE 'Disagreement'::text
                END AS agreement_status
           FROM cases c
             JOIN model_predictions mp ON c.case_id = mp.case_id AND mp.model_version::text = 'v3.2'::text
             JOIN human_reviews hr ON c.case_id = hr.case_id
          WHERE c.case_id >= 1007 AND c.case_id <= 11006
        ), flags AS (
         SELECT b.case_id,
            b.agreement_status,
                CASE
                    WHEN (EXISTS ( SELECT 1
                       FROM escalations e
                      WHERE e.case_id = b.case_id)) THEN 1
                    ELSE 0
                END AS is_escalated,
                CASE
                    WHEN (EXISTS ( SELECT 1
                       FROM appeals a
                      WHERE a.case_id = b.case_id)) THEN 1
                    ELSE 0
                END AS is_appealed,
                CASE
                    WHEN (EXISTS ( SELECT 1
                       FROM appeals a
                      WHERE a.case_id = b.case_id AND (a.appeal_outcome::text = ANY (ARRAY['Overturned'::character varying, 'Partially Overturned'::character varying]::text[])))) THEN 1
                    ELSE 0
                END AS is_changed
           FROM base b
        )
 SELECT agreement_status,
    count(*) AS total_cases,
    sum(is_escalated) AS escalated_cases,
    round(sum(is_escalated)::numeric / count(*)::numeric * 100::numeric, 2) AS escalation_rate,
    sum(is_appealed) AS appealed_cases,
    round(sum(is_appealed)::numeric / count(*)::numeric * 100::numeric, 2) AS appeal_rate,
    sum(is_changed) AS changed_appeals,
    round(sum(is_changed)::numeric / NULLIF(sum(is_appealed), 0)::numeric * 100::numeric, 2) AS appeal_change_rate
   FROM flags
  GROUP BY agreement_status
  ORDER BY agreement_status;;
CREATE OR REPLACE VIEW public.case_triage AS  WITH case_signals AS (
         SELECT c.case_id,
            c.user_id,
            c.priority,
            c.queue,
            c.content_type,
            c.risk_score,
            hr.decision AS human_decision,
            mp.prediction AS ai_prediction,
            mp.confidence AS ai_confidence,
                CASE
                    WHEN hr.decision::text <> mp.prediction::text THEN 1
                    ELSE 0
                END AS ai_human_disagreement,
                CASE
                    WHEN hr.decision::text <> mp.prediction::text AND mp.confidence >= 0.80 THEN 1
                    ELSE 0
                END AS high_confidence_error,
                CASE
                    WHEN e.case_id IS NOT NULL THEN 1
                    ELSE 0
                END AS escalated,
                CASE
                    WHEN a.case_id IS NOT NULL THEN 1
                    ELSE 0
                END AS appealed
           FROM cases c
             JOIN human_reviews hr ON c.case_id = hr.case_id
             JOIN model_predictions mp ON c.case_id = mp.case_id AND mp.model_version::text = 'v3.3'::text
             LEFT JOIN escalations e ON c.case_id = e.case_id
             LEFT JOIN appeals a ON c.case_id = a.case_id
          WHERE c.case_id >= 1007 AND c.case_id <= 11006
        ), scored_cases AS (
         SELECT case_signals.case_id,
            case_signals.user_id,
            case_signals.priority,
            case_signals.queue,
            case_signals.content_type,
            case_signals.risk_score,
            case_signals.human_decision,
            case_signals.ai_prediction,
            case_signals.ai_confidence,
            case_signals.ai_human_disagreement,
            case_signals.high_confidence_error,
            case_signals.escalated,
            case_signals.appealed,
                CASE
                    WHEN case_signals.priority::text = 'Critical'::text THEN 30
                    WHEN case_signals.priority::text = 'High'::text THEN 20
                    WHEN case_signals.priority::text = 'Medium'::text THEN 10
                    ELSE 0
                END +
                CASE
                    WHEN case_signals.risk_score >= 0.80 THEN 25
                    WHEN case_signals.risk_score >= 0.60 THEN 15
                    WHEN case_signals.risk_score >= 0.40 THEN 5
                    ELSE 0
                END + case_signals.ai_human_disagreement * 20 + case_signals.escalated * 15 + case_signals.appealed * 10 + case_signals.high_confidence_error * 20 AS triage_score
           FROM case_signals
        )
 SELECT case_id,
    user_id,
    priority,
    queue,
    content_type,
    risk_score,
    human_decision,
    ai_prediction,
    ai_confidence,
    ai_human_disagreement,
    high_confidence_error,
    escalated,
    appealed,
    triage_score,
        CASE
            WHEN triage_score >= 80 THEN 'Very High'::text
            WHEN triage_score >= 60 THEN 'High'::text
            WHEN triage_score >= 40 THEN 'Medium'::text
            ELSE 'Low'::text
        END AS triage_level
   FROM scored_cases;;
CREATE OR REPLACE VIEW public.model_evaluation_summary AS  WITH evaluation AS (
         SELECT mp.model_version,
            p.policy_name,
            hr.decision AS human_decision,
            mp.prediction AS ai_prediction
           FROM model_predictions mp
             JOIN human_reviews hr ON mp.case_id = hr.case_id
             JOIN cases c ON mp.case_id = c.case_id
             JOIN policies p ON c.policy_id = p.policy_id
          WHERE c.case_id >= 1007 AND c.case_id <= 11006
        ), metrics AS (
         SELECT evaluation.model_version,
            evaluation.policy_name,
            count(
                CASE
                    WHEN evaluation.human_decision::text = 'Violation'::text AND evaluation.ai_prediction::text = 'Violation'::text THEN 1
                    ELSE NULL::integer
                END) AS true_positives,
            count(
                CASE
                    WHEN evaluation.human_decision::text = 'No Violation'::text AND evaluation.ai_prediction::text = 'No Violation'::text THEN 1
                    ELSE NULL::integer
                END) AS true_negatives,
            count(
                CASE
                    WHEN evaluation.human_decision::text = 'No Violation'::text AND evaluation.ai_prediction::text = 'Violation'::text THEN 1
                    ELSE NULL::integer
                END) AS false_positives,
            count(
                CASE
                    WHEN evaluation.human_decision::text = 'Violation'::text AND evaluation.ai_prediction::text = 'No Violation'::text THEN 1
                    ELSE NULL::integer
                END) AS false_negatives
           FROM evaluation
          GROUP BY evaluation.model_version, evaluation.policy_name
        )
 SELECT model_version,
    policy_name,
    true_positives,
    true_negatives,
    false_positives,
    false_negatives,
    round(true_positives::numeric / NULLIF(true_positives + false_positives, 0)::numeric, 3) AS "precision",
    round(true_positives::numeric / NULLIF(true_positives + false_negatives, 0)::numeric, 3) AS recall,
    round(2::numeric * (true_positives::numeric / NULLIF(true_positives + false_positives, 0)::numeric) * (true_positives::numeric / NULLIF(true_positives + false_negatives, 0)::numeric) / NULLIF(true_positives::numeric / NULLIF(true_positives + false_positives, 0)::numeric + true_positives::numeric / NULLIF(true_positives + false_negatives, 0)::numeric, 0::numeric), 3) AS f1
   FROM metrics;;
CREATE OR REPLACE VIEW public.model_executive_summary AS  SELECT model_version,
    "precision",
    recall,
    f1,
    false_positives,
    false_negatives,
    rank() OVER (ORDER BY f1 DESC) AS overall_rank,
        CASE
            WHEN f1 = max(f1) OVER () THEN 'Best Overall F1'::text
            WHEN recall = max(recall) OVER () THEN 'Best Recall'::text
            WHEN "precision" = max("precision") OVER () THEN 'Best Precision'::text
            ELSE 'Other'::text
        END AS performance_highlight
   FROM model_kpis;;
CREATE OR REPLACE VIEW public.model_kpis AS  WITH model_metrics AS (
         SELECT mp.model_version,
            count(*) AS total_predictions,
            count(
                CASE
                    WHEN hr.decision::text = 'Violation'::text AND mp.prediction::text = 'Violation'::text THEN 1
                    ELSE NULL::integer
                END) AS true_positives,
            count(
                CASE
                    WHEN hr.decision::text = 'No Violation'::text AND mp.prediction::text = 'No Violation'::text THEN 1
                    ELSE NULL::integer
                END) AS true_negatives,
            count(
                CASE
                    WHEN hr.decision::text = 'No Violation'::text AND mp.prediction::text = 'Violation'::text THEN 1
                    ELSE NULL::integer
                END) AS false_positives,
            count(
                CASE
                    WHEN hr.decision::text = 'Violation'::text AND mp.prediction::text = 'No Violation'::text THEN 1
                    ELSE NULL::integer
                END) AS false_negatives
           FROM model_predictions mp
             JOIN human_reviews hr ON mp.case_id = hr.case_id
          WHERE mp.case_id >= 1007 AND mp.case_id <= 11006
          GROUP BY mp.model_version
        )
 SELECT model_version,
    total_predictions,
    true_positives,
    true_negatives,
    false_positives,
    false_negatives,
    round(true_positives::numeric / NULLIF(true_positives + false_positives, 0)::numeric, 3) AS "precision",
    round(true_positives::numeric / NULLIF(true_positives + false_negatives, 0)::numeric, 3) AS recall,
    round(2::numeric * (true_positives::numeric / NULLIF(true_positives + false_positives, 0)::numeric) * (true_positives::numeric / NULLIF(true_positives + false_negatives, 0)::numeric) / NULLIF(true_positives::numeric / NULLIF(true_positives + false_positives, 0)::numeric + true_positives::numeric / NULLIF(true_positives + false_negatives, 0)::numeric, 0::numeric), 3) AS f1
   FROM model_metrics;;
CREATE OR REPLACE VIEW public.model_recommendation AS  SELECT model_version,
    "precision",
    recall,
    f1,
    rank() OVER (ORDER BY f1 DESC) AS f1_rank,
    rank() OVER (ORDER BY "precision" DESC) AS precision_rank,
    rank() OVER (ORDER BY recall DESC) AS recall_rank,
        CASE
            WHEN rank() OVER (ORDER BY f1 DESC) = 1 THEN 'Best overall balance'::text
            WHEN rank() OVER (ORDER BY recall DESC) = 1 THEN 'Best violation detection'::text
            WHEN rank() OVER (ORDER BY "precision" DESC) = 1 THEN 'Best prediction precision'::text
            ELSE 'Other'::text
        END AS recommendation
   FROM model_kpis;;
CREATE OR REPLACE VIEW public.monthly_model_quality AS  WITH monthly_metrics AS (
         SELECT date_trunc('month'::text, c.created_at::timestamp with time zone)::date AS month,
            count(
                CASE
                    WHEN hr.decision::text = 'Violation'::text AND mp.prediction::text = 'Violation'::text THEN 1
                    ELSE NULL::integer
                END) AS true_positives,
            count(
                CASE
                    WHEN hr.decision::text = 'No Violation'::text AND mp.prediction::text = 'Violation'::text THEN 1
                    ELSE NULL::integer
                END) AS false_positives,
            count(
                CASE
                    WHEN hr.decision::text = 'Violation'::text AND mp.prediction::text = 'No Violation'::text THEN 1
                    ELSE NULL::integer
                END) AS false_negatives
           FROM cases c
             JOIN human_reviews hr ON c.case_id = hr.case_id
             JOIN model_predictions mp ON c.case_id = mp.case_id AND mp.model_version::text = 'v3.3'::text
          WHERE c.case_id >= 1007 AND c.case_id <= 11006
          GROUP BY (date_trunc('month'::text, c.created_at::timestamp with time zone))
        )
 SELECT month,
    true_positives,
    false_positives,
    false_negatives,
    round(true_positives::numeric / NULLIF(true_positives + false_positives, 0)::numeric, 3) AS "precision",
    round(true_positives::numeric / NULLIF(true_positives + false_negatives, 0)::numeric, 3) AS recall,
    round(2::numeric * (true_positives::numeric / NULLIF(true_positives + false_positives, 0)::numeric) * (true_positives::numeric / NULLIF(true_positives + false_negatives, 0)::numeric) / NULLIF(true_positives::numeric / NULLIF(true_positives + false_positives, 0)::numeric + true_positives::numeric / NULLIF(true_positives + false_negatives, 0)::numeric, 0::numeric), 3) AS f1
   FROM monthly_metrics
  ORDER BY month;;
CREATE OR REPLACE VIEW public.monthly_operations AS  SELECT date_trunc('month'::text, c.created_at::timestamp with time zone)::date AS month,
    count(*) AS total_cases,
    count(
        CASE
            WHEN hr.decision::text = 'Violation'::text THEN 1
            ELSE NULL::integer
        END) AS violations,
    round(count(
        CASE
            WHEN hr.decision::text = 'Violation'::text THEN 1
            ELSE NULL::integer
        END)::numeric / count(*)::numeric * 100::numeric, 2) AS violation_rate,
    count(DISTINCT e.case_id) AS escalated_cases,
    round(count(DISTINCT e.case_id)::numeric / count(*)::numeric * 100::numeric, 2) AS escalation_rate,
    count(DISTINCT a.case_id) AS appealed_cases,
    round(count(DISTINCT a.case_id)::numeric / count(*)::numeric * 100::numeric, 2) AS appeal_rate
   FROM cases c
     JOIN human_reviews hr ON c.case_id = hr.case_id
     LEFT JOIN escalations e ON c.case_id = e.case_id
     LEFT JOIN appeals a ON c.case_id = a.case_id
  WHERE c.case_id >= 1007 AND c.case_id <= 11006
  GROUP BY (date_trunc('month'::text, c.created_at::timestamp with time zone))
  ORDER BY (date_trunc('month'::text, c.created_at::timestamp with time zone)::date);;
CREATE OR REPLACE VIEW public.operational_kpis AS  WITH escalation_metrics AS (
         SELECT count(*) AS total_escalations,
            count(
                CASE
                    WHEN (e.resolved_at - e.escalated_at) <=
                    CASE
                        WHEN e.escalation_level = 1 THEN 2
                        WHEN e.escalation_level = 2 THEN 3
                        WHEN e.escalation_level = 3 THEN 5
                        ELSE NULL::integer
                    END THEN 1
                    ELSE NULL::integer
                END) AS within_sla
           FROM escalations e
          WHERE e.case_id >= 1007 AND e.case_id <= 11006
        ), appeal_metrics AS (
         SELECT count(*) AS total_appeals,
            count(
                CASE
                    WHEN appeals.appeal_outcome::text = 'Overturned'::text THEN 1
                    ELSE NULL::integer
                END) AS overturned_appeals,
            count(
                CASE
                    WHEN appeals.appeal_outcome::text = ANY (ARRAY['Overturned'::character varying, 'Partially Overturned'::character varying]::text[]) THEN 1
                    ELSE NULL::integer
                END) AS changed_appeals
           FROM appeals
          WHERE appeals.case_id >= 1007 AND appeals.case_id <= 11006
        )
 SELECT t.total_cases,
    t.violation_rate,
    t.ai_human_disagreement_rate,
    t.escalation_rate,
    t.appeal_rate,
    t.avg_review_minutes,
    round(em.within_sla::numeric / NULLIF(em.total_escalations, 0)::numeric * 100::numeric, 2) AS sla_compliance_rate,
    round(am.overturned_appeals::numeric / NULLIF(am.total_appeals, 0)::numeric * 100::numeric, 2) AS appeal_overturn_rate,
    round(am.changed_appeals::numeric / NULLIF(am.total_appeals, 0)::numeric * 100::numeric, 2) AS appeal_change_rate
   FROM trust_safety_kpis t
     CROSS JOIN escalation_metrics em
     CROSS JOIN appeal_metrics am;;
CREATE OR REPLACE VIEW public.policy_risk_hotspots AS  SELECT policy_name,
    true_positives,
    false_positives,
    false_negatives,
    round(true_positives::numeric / NULLIF(true_positives + false_positives, 0)::numeric, 3) AS "precision",
    round(true_positives::numeric / NULLIF(true_positives + false_negatives, 0)::numeric, 3) AS recall,
    round(false_negatives::numeric / NULLIF(true_positives + false_negatives, 0)::numeric * 100::numeric, 2) AS missed_violation_rate,
        CASE
            WHEN (false_negatives::numeric / NULLIF(true_positives + false_negatives, 0)::numeric) >= 0.15 THEN 'High safety concern'::text
            WHEN (false_negatives::numeric / NULLIF(true_positives + false_negatives, 0)::numeric) >= 0.10 THEN 'Moderate safety concern'::text
            ELSE 'Lower safety concern'::text
        END AS risk_category
   FROM model_evaluation_summary
  WHERE model_version::text = 'v3.2'::text;;
CREATE OR REPLACE VIEW public.trust_safety_kpis AS  SELECT count(DISTINCT c.case_id) AS total_cases,
    round(count(
        CASE
            WHEN hr.decision::text = 'Violation'::text THEN 1
            ELSE NULL::integer
        END)::numeric / count(*)::numeric * 100::numeric, 2) AS violation_rate,
    round(count(
        CASE
            WHEN hr.decision::text <> mp.prediction::text THEN 1
            ELSE NULL::integer
        END)::numeric / count(*)::numeric * 100::numeric, 2) AS ai_human_disagreement_rate,
    round(count(DISTINCT e.case_id)::numeric / count(DISTINCT c.case_id)::numeric * 100::numeric, 2) AS escalation_rate,
    round(count(DISTINCT a.case_id)::numeric / count(DISTINCT c.case_id)::numeric * 100::numeric, 2) AS appeal_rate,
    round(avg(hr.review_duration_minutes), 2) AS avg_review_minutes
   FROM cases c
     JOIN human_reviews hr ON c.case_id = hr.case_id
     JOIN model_predictions mp ON c.case_id = mp.case_id AND mp.model_version::text = 'v3.3'::text
     LEFT JOIN escalations e ON c.case_id = e.case_id
     LEFT JOIN appeals a ON c.case_id = a.case_id
  WHERE c.case_id >= 1007 AND c.case_id <= 11006;;