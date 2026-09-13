--
-- PostgreSQL database dump
--

\restrict fGcgeGpojGyduOVOVUgMGABcVqnNDPMKCcPGlIDwJalmqGeyHC8tzFn0ojaE0wF

-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: appeals; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.appeals (
    appeal_id integer NOT NULL,
    case_id integer,
    appeal_reason character varying(100),
    appeal_outcome character varying(30),
    submitted_at date,
    resolved_at date
);


ALTER TABLE public.appeals OWNER TO postgres;

--
-- Name: cases; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.cases (
    case_id integer NOT NULL,
    user_id integer,
    priority character varying(20),
    queue character varying(50),
    created_at date,
    risk_score numeric(4,3),
    policy_id integer,
    content_type character varying(50),
    review_status character varying(30)
);


ALTER TABLE public.cases OWNER TO postgres;

--
-- Name: escalations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.escalations (
    escalation_id integer NOT NULL,
    case_id integer,
    escalation_reason character varying(100),
    escalation_level integer,
    escalated_at date,
    resolved_at date
);


ALTER TABLE public.escalations OWNER TO postgres;

--
-- Name: human_reviews; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.human_reviews (
    review_id integer NOT NULL,
    case_id integer,
    reviewer_id integer,
    decision character varying(20),
    reviewed_at date,
    review_duration_minutes integer
);


ALTER TABLE public.human_reviews OWNER TO postgres;

--
-- Name: model_predictions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.model_predictions (
    prediction_id integer NOT NULL,
    case_id integer,
    model_version character varying(20),
    prediction character varying(20),
    confidence numeric(4,3),
    predicted_at date
);


ALTER TABLE public.model_predictions OWNER TO postgres;

--
-- Name: agreement_operational_analysis; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.agreement_operational_analysis AS
 WITH base AS (
         SELECT c.case_id,
                CASE
                    WHEN ((mp.prediction)::text = (hr.decision)::text) THEN 'Agreement'::text
                    ELSE 'Disagreement'::text
                END AS agreement_status
           FROM ((public.cases c
             JOIN public.model_predictions mp ON (((c.case_id = mp.case_id) AND ((mp.model_version)::text = 'v3.2'::text))))
             JOIN public.human_reviews hr ON ((c.case_id = hr.case_id)))
          WHERE ((c.case_id >= 1007) AND (c.case_id <= 11006))
        ), flags AS (
         SELECT b.case_id,
            b.agreement_status,
                CASE
                    WHEN (EXISTS ( SELECT 1
                       FROM public.escalations e
                      WHERE (e.case_id = b.case_id))) THEN 1
                    ELSE 0
                END AS is_escalated,
                CASE
                    WHEN (EXISTS ( SELECT 1
                       FROM public.appeals a
                      WHERE (a.case_id = b.case_id))) THEN 1
                    ELSE 0
                END AS is_appealed,
                CASE
                    WHEN (EXISTS ( SELECT 1
                       FROM public.appeals a
                      WHERE ((a.case_id = b.case_id) AND ((a.appeal_outcome)::text = ANY ((ARRAY['Overturned'::character varying, 'Partially Overturned'::character varying])::text[]))))) THEN 1
                    ELSE 0
                END AS is_changed
           FROM base b
        )
 SELECT agreement_status,
    count(*) AS total_cases,
    sum(is_escalated) AS escalated_cases,
    round((((sum(is_escalated))::numeric / (count(*))::numeric) * (100)::numeric), 2) AS escalation_rate,
    sum(is_appealed) AS appealed_cases,
    round((((sum(is_appealed))::numeric / (count(*))::numeric) * (100)::numeric), 2) AS appeal_rate,
    sum(is_changed) AS changed_appeals,
    round((((sum(is_changed))::numeric / (NULLIF(sum(is_appealed), 0))::numeric) * (100)::numeric), 2) AS appeal_change_rate
   FROM flags
  GROUP BY agreement_status
  ORDER BY agreement_status;


ALTER VIEW public.agreement_operational_analysis OWNER TO postgres;

--
-- Name: case_triage; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.case_triage AS
 WITH case_signals AS (
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
                    WHEN ((hr.decision)::text <> (mp.prediction)::text) THEN 1
                    ELSE 0
                END AS ai_human_disagreement,
                CASE
                    WHEN (((hr.decision)::text <> (mp.prediction)::text) AND (mp.confidence >= 0.80)) THEN 1
                    ELSE 0
                END AS high_confidence_error,
                CASE
                    WHEN (e.case_id IS NOT NULL) THEN 1
                    ELSE 0
                END AS escalated,
                CASE
                    WHEN (a.case_id IS NOT NULL) THEN 1
                    ELSE 0
                END AS appealed
           FROM ((((public.cases c
             JOIN public.human_reviews hr ON ((c.case_id = hr.case_id)))
             JOIN public.model_predictions mp ON (((c.case_id = mp.case_id) AND ((mp.model_version)::text = 'v3.3'::text))))
             LEFT JOIN public.escalations e ON ((c.case_id = e.case_id)))
             LEFT JOIN public.appeals a ON ((c.case_id = a.case_id)))
          WHERE ((c.case_id >= 1007) AND (c.case_id <= 11006))
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
            (((((
                CASE
                    WHEN ((case_signals.priority)::text = 'Critical'::text) THEN 30
                    WHEN ((case_signals.priority)::text = 'High'::text) THEN 20
                    WHEN ((case_signals.priority)::text = 'Medium'::text) THEN 10
                    ELSE 0
                END +
                CASE
                    WHEN (case_signals.risk_score >= 0.80) THEN 25
                    WHEN (case_signals.risk_score >= 0.60) THEN 15
                    WHEN (case_signals.risk_score >= 0.40) THEN 5
                    ELSE 0
                END) + (case_signals.ai_human_disagreement * 20)) + (case_signals.escalated * 15)) + (case_signals.appealed * 10)) + (case_signals.high_confidence_error * 20)) AS triage_score
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
            WHEN (triage_score >= 80) THEN 'Very High'::text
            WHEN (triage_score >= 60) THEN 'High'::text
            WHEN (triage_score >= 40) THEN 'Medium'::text
            ELSE 'Low'::text
        END AS triage_level
   FROM scored_cases;


ALTER VIEW public.case_triage OWNER TO postgres;

--
-- Name: policies; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.policies (
    policy_id integer NOT NULL,
    policy_name character varying(100),
    severity character varying(20)
);


ALTER TABLE public.policies OWNER TO postgres;

--
-- Name: model_evaluation_summary; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.model_evaluation_summary AS
 WITH evaluation AS (
         SELECT mp.model_version,
            p.policy_name,
            hr.decision AS human_decision,
            mp.prediction AS ai_prediction
           FROM (((public.model_predictions mp
             JOIN public.human_reviews hr ON ((mp.case_id = hr.case_id)))
             JOIN public.cases c ON ((mp.case_id = c.case_id)))
             JOIN public.policies p ON ((c.policy_id = p.policy_id)))
          WHERE ((c.case_id >= 1007) AND (c.case_id <= 11006))
        ), metrics AS (
         SELECT evaluation.model_version,
            evaluation.policy_name,
            count(
                CASE
                    WHEN (((evaluation.human_decision)::text = 'Violation'::text) AND ((evaluation.ai_prediction)::text = 'Violation'::text)) THEN 1
                    ELSE NULL::integer
                END) AS true_positives,
            count(
                CASE
                    WHEN (((evaluation.human_decision)::text = 'No Violation'::text) AND ((evaluation.ai_prediction)::text = 'No Violation'::text)) THEN 1
                    ELSE NULL::integer
                END) AS true_negatives,
            count(
                CASE
                    WHEN (((evaluation.human_decision)::text = 'No Violation'::text) AND ((evaluation.ai_prediction)::text = 'Violation'::text)) THEN 1
                    ELSE NULL::integer
                END) AS false_positives,
            count(
                CASE
                    WHEN (((evaluation.human_decision)::text = 'Violation'::text) AND ((evaluation.ai_prediction)::text = 'No Violation'::text)) THEN 1
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
    round(((true_positives)::numeric / (NULLIF((true_positives + false_positives), 0))::numeric), 3) AS "precision",
    round(((true_positives)::numeric / (NULLIF((true_positives + false_negatives), 0))::numeric), 3) AS recall,
    round(((((2)::numeric * ((true_positives)::numeric / (NULLIF((true_positives + false_positives), 0))::numeric)) * ((true_positives)::numeric / (NULLIF((true_positives + false_negatives), 0))::numeric)) / NULLIF((((true_positives)::numeric / (NULLIF((true_positives + false_positives), 0))::numeric) + ((true_positives)::numeric / (NULLIF((true_positives + false_negatives), 0))::numeric)), (0)::numeric)), 3) AS f1
   FROM metrics;


ALTER VIEW public.model_evaluation_summary OWNER TO postgres;

--
-- Name: model_kpis; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.model_kpis AS
 WITH model_metrics AS (
         SELECT mp.model_version,
            count(*) AS total_predictions,
            count(
                CASE
                    WHEN (((hr.decision)::text = 'Violation'::text) AND ((mp.prediction)::text = 'Violation'::text)) THEN 1
                    ELSE NULL::integer
                END) AS true_positives,
            count(
                CASE
                    WHEN (((hr.decision)::text = 'No Violation'::text) AND ((mp.prediction)::text = 'No Violation'::text)) THEN 1
                    ELSE NULL::integer
                END) AS true_negatives,
            count(
                CASE
                    WHEN (((hr.decision)::text = 'No Violation'::text) AND ((mp.prediction)::text = 'Violation'::text)) THEN 1
                    ELSE NULL::integer
                END) AS false_positives,
            count(
                CASE
                    WHEN (((hr.decision)::text = 'Violation'::text) AND ((mp.prediction)::text = 'No Violation'::text)) THEN 1
                    ELSE NULL::integer
                END) AS false_negatives
           FROM (public.model_predictions mp
             JOIN public.human_reviews hr ON ((mp.case_id = hr.case_id)))
          WHERE ((mp.case_id >= 1007) AND (mp.case_id <= 11006))
          GROUP BY mp.model_version
        )
 SELECT model_version,
    total_predictions,
    true_positives,
    true_negatives,
    false_positives,
    false_negatives,
    round(((true_positives)::numeric / (NULLIF((true_positives + false_positives), 0))::numeric), 3) AS "precision",
    round(((true_positives)::numeric / (NULLIF((true_positives + false_negatives), 0))::numeric), 3) AS recall,
    round(((((2)::numeric * ((true_positives)::numeric / (NULLIF((true_positives + false_positives), 0))::numeric)) * ((true_positives)::numeric / (NULLIF((true_positives + false_negatives), 0))::numeric)) / NULLIF((((true_positives)::numeric / (NULLIF((true_positives + false_positives), 0))::numeric) + ((true_positives)::numeric / (NULLIF((true_positives + false_negatives), 0))::numeric)), (0)::numeric)), 3) AS f1
   FROM model_metrics;


ALTER VIEW public.model_kpis OWNER TO postgres;

--
-- Name: model_executive_summary; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.model_executive_summary AS
 SELECT model_version,
    "precision",
    recall,
    f1,
    false_positives,
    false_negatives,
    rank() OVER (ORDER BY f1 DESC) AS overall_rank,
        CASE
            WHEN (f1 = max(f1) OVER ()) THEN 'Best Overall F1'::text
            WHEN (recall = max(recall) OVER ()) THEN 'Best Recall'::text
            WHEN ("precision" = max("precision") OVER ()) THEN 'Best Precision'::text
            ELSE 'Other'::text
        END AS performance_highlight
   FROM public.model_kpis;


ALTER VIEW public.model_executive_summary OWNER TO postgres;

--
-- Name: model_recommendation; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.model_recommendation AS
 SELECT model_version,
    "precision",
    recall,
    f1,
    rank() OVER (ORDER BY f1 DESC) AS f1_rank,
    rank() OVER (ORDER BY "precision" DESC) AS precision_rank,
    rank() OVER (ORDER BY recall DESC) AS recall_rank,
        CASE
            WHEN (rank() OVER (ORDER BY f1 DESC) = 1) THEN 'Best overall balance'::text
            WHEN (rank() OVER (ORDER BY recall DESC) = 1) THEN 'Best violation detection'::text
            WHEN (rank() OVER (ORDER BY "precision" DESC) = 1) THEN 'Best prediction precision'::text
            ELSE 'Other'::text
        END AS recommendation
   FROM public.model_kpis;


ALTER VIEW public.model_recommendation OWNER TO postgres;

--
-- Name: model_versions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.model_versions (
    model_version character varying(20) NOT NULL,
    model_name character varying(100),
    deployment_date date
);


ALTER TABLE public.model_versions OWNER TO postgres;

--
-- Name: monthly_model_quality; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.monthly_model_quality AS
 WITH monthly_metrics AS (
         SELECT (date_trunc('month'::text, (c.created_at)::timestamp with time zone))::date AS month,
            count(
                CASE
                    WHEN (((hr.decision)::text = 'Violation'::text) AND ((mp.prediction)::text = 'Violation'::text)) THEN 1
                    ELSE NULL::integer
                END) AS true_positives,
            count(
                CASE
                    WHEN (((hr.decision)::text = 'No Violation'::text) AND ((mp.prediction)::text = 'Violation'::text)) THEN 1
                    ELSE NULL::integer
                END) AS false_positives,
            count(
                CASE
                    WHEN (((hr.decision)::text = 'Violation'::text) AND ((mp.prediction)::text = 'No Violation'::text)) THEN 1
                    ELSE NULL::integer
                END) AS false_negatives
           FROM ((public.cases c
             JOIN public.human_reviews hr ON ((c.case_id = hr.case_id)))
             JOIN public.model_predictions mp ON (((c.case_id = mp.case_id) AND ((mp.model_version)::text = 'v3.3'::text))))
          WHERE ((c.case_id >= 1007) AND (c.case_id <= 11006))
          GROUP BY (date_trunc('month'::text, (c.created_at)::timestamp with time zone))
        )
 SELECT month,
    true_positives,
    false_positives,
    false_negatives,
    round(((true_positives)::numeric / (NULLIF((true_positives + false_positives), 0))::numeric), 3) AS "precision",
    round(((true_positives)::numeric / (NULLIF((true_positives + false_negatives), 0))::numeric), 3) AS recall,
    round(((((2)::numeric * ((true_positives)::numeric / (NULLIF((true_positives + false_positives), 0))::numeric)) * ((true_positives)::numeric / (NULLIF((true_positives + false_negatives), 0))::numeric)) / NULLIF((((true_positives)::numeric / (NULLIF((true_positives + false_positives), 0))::numeric) + ((true_positives)::numeric / (NULLIF((true_positives + false_negatives), 0))::numeric)), (0)::numeric)), 3) AS f1
   FROM monthly_metrics
  ORDER BY month;


ALTER VIEW public.monthly_model_quality OWNER TO postgres;

--
-- Name: monthly_operations; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.monthly_operations AS
 SELECT (date_trunc('month'::text, (c.created_at)::timestamp with time zone))::date AS month,
    count(*) AS total_cases,
    count(
        CASE
            WHEN ((hr.decision)::text = 'Violation'::text) THEN 1
            ELSE NULL::integer
        END) AS violations,
    round((((count(
        CASE
            WHEN ((hr.decision)::text = 'Violation'::text) THEN 1
            ELSE NULL::integer
        END))::numeric / (count(*))::numeric) * (100)::numeric), 2) AS violation_rate,
    count(DISTINCT e.case_id) AS escalated_cases,
    round((((count(DISTINCT e.case_id))::numeric / (count(*))::numeric) * (100)::numeric), 2) AS escalation_rate,
    count(DISTINCT a.case_id) AS appealed_cases,
    round((((count(DISTINCT a.case_id))::numeric / (count(*))::numeric) * (100)::numeric), 2) AS appeal_rate
   FROM (((public.cases c
     JOIN public.human_reviews hr ON ((c.case_id = hr.case_id)))
     LEFT JOIN public.escalations e ON ((c.case_id = e.case_id)))
     LEFT JOIN public.appeals a ON ((c.case_id = a.case_id)))
  WHERE ((c.case_id >= 1007) AND (c.case_id <= 11006))
  GROUP BY (date_trunc('month'::text, (c.created_at)::timestamp with time zone))
  ORDER BY ((date_trunc('month'::text, (c.created_at)::timestamp with time zone))::date);


ALTER VIEW public.monthly_operations OWNER TO postgres;

--
-- Name: trust_safety_kpis; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.trust_safety_kpis AS
 SELECT count(DISTINCT c.case_id) AS total_cases,
    round((((count(
        CASE
            WHEN ((hr.decision)::text = 'Violation'::text) THEN 1
            ELSE NULL::integer
        END))::numeric / (count(*))::numeric) * (100)::numeric), 2) AS violation_rate,
    round((((count(
        CASE
            WHEN ((hr.decision)::text <> (mp.prediction)::text) THEN 1
            ELSE NULL::integer
        END))::numeric / (count(*))::numeric) * (100)::numeric), 2) AS ai_human_disagreement_rate,
    round((((count(DISTINCT e.case_id))::numeric / (count(DISTINCT c.case_id))::numeric) * (100)::numeric), 2) AS escalation_rate,
    round((((count(DISTINCT a.case_id))::numeric / (count(DISTINCT c.case_id))::numeric) * (100)::numeric), 2) AS appeal_rate,
    round(avg(hr.review_duration_minutes), 2) AS avg_review_minutes
   FROM ((((public.cases c
     JOIN public.human_reviews hr ON ((c.case_id = hr.case_id)))
     JOIN public.model_predictions mp ON (((c.case_id = mp.case_id) AND ((mp.model_version)::text = 'v3.3'::text))))
     LEFT JOIN public.escalations e ON ((c.case_id = e.case_id)))
     LEFT JOIN public.appeals a ON ((c.case_id = a.case_id)))
  WHERE ((c.case_id >= 1007) AND (c.case_id <= 11006));


ALTER VIEW public.trust_safety_kpis OWNER TO postgres;

--
-- Name: operational_kpis; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.operational_kpis AS
 WITH escalation_metrics AS (
         SELECT count(*) AS total_escalations,
            count(
                CASE
                    WHEN ((e.resolved_at - e.escalated_at) <=
                    CASE
                        WHEN (e.escalation_level = 1) THEN 2
                        WHEN (e.escalation_level = 2) THEN 3
                        WHEN (e.escalation_level = 3) THEN 5
                        ELSE NULL::integer
                    END) THEN 1
                    ELSE NULL::integer
                END) AS within_sla
           FROM public.escalations e
          WHERE ((e.case_id >= 1007) AND (e.case_id <= 11006))
        ), appeal_metrics AS (
         SELECT count(*) AS total_appeals,
            count(
                CASE
                    WHEN ((appeals.appeal_outcome)::text = 'Overturned'::text) THEN 1
                    ELSE NULL::integer
                END) AS overturned_appeals,
            count(
                CASE
                    WHEN ((appeals.appeal_outcome)::text = ANY ((ARRAY['Overturned'::character varying, 'Partially Overturned'::character varying])::text[])) THEN 1
                    ELSE NULL::integer
                END) AS changed_appeals
           FROM public.appeals
          WHERE ((appeals.case_id >= 1007) AND (appeals.case_id <= 11006))
        )
 SELECT t.total_cases,
    t.violation_rate,
    t.ai_human_disagreement_rate,
    t.escalation_rate,
    t.appeal_rate,
    t.avg_review_minutes,
    round((((em.within_sla)::numeric / (NULLIF(em.total_escalations, 0))::numeric) * (100)::numeric), 2) AS sla_compliance_rate,
    round((((am.overturned_appeals)::numeric / (NULLIF(am.total_appeals, 0))::numeric) * (100)::numeric), 2) AS appeal_overturn_rate,
    round((((am.changed_appeals)::numeric / (NULLIF(am.total_appeals, 0))::numeric) * (100)::numeric), 2) AS appeal_change_rate
   FROM ((public.trust_safety_kpis t
     CROSS JOIN escalation_metrics em)
     CROSS JOIN appeal_metrics am);


ALTER VIEW public.operational_kpis OWNER TO postgres;

--
-- Name: policy_risk_hotspots; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.policy_risk_hotspots AS
 SELECT policy_name,
    true_positives,
    false_positives,
    false_negatives,
    round(((true_positives)::numeric / (NULLIF((true_positives + false_positives), 0))::numeric), 3) AS "precision",
    round(((true_positives)::numeric / (NULLIF((true_positives + false_negatives), 0))::numeric), 3) AS recall,
    round((((false_negatives)::numeric / (NULLIF((true_positives + false_negatives), 0))::numeric) * (100)::numeric), 2) AS missed_violation_rate,
        CASE
            WHEN (((false_negatives)::numeric / (NULLIF((true_positives + false_negatives), 0))::numeric) >= 0.15) THEN 'High safety concern'::text
            WHEN (((false_negatives)::numeric / (NULLIF((true_positives + false_negatives), 0))::numeric) >= 0.10) THEN 'Moderate safety concern'::text
            ELSE 'Lower safety concern'::text
        END AS risk_category
   FROM public.model_evaluation_summary
  WHERE ((model_version)::text = 'v3.2'::text);


ALTER VIEW public.policy_risk_hotspots OWNER TO postgres;

--
-- Name: reviewers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.reviewers (
    reviewer_id integer NOT NULL,
    reviewer_name character varying(100),
    team character varying(100),
    experience_level character varying(20)
);


ALTER TABLE public.reviewers OWNER TO postgres;

--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    user_id integer NOT NULL,
    account_created_at date,
    seller_type character varying(50),
    account_status character varying(30)
);


ALTER TABLE public.users OWNER TO postgres;

--
-- Name: appeals appeals_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.appeals
    ADD CONSTRAINT appeals_pkey PRIMARY KEY (appeal_id);


--
-- Name: cases cases_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cases
    ADD CONSTRAINT cases_pkey PRIMARY KEY (case_id);


--
-- Name: escalations escalations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.escalations
    ADD CONSTRAINT escalations_pkey PRIMARY KEY (escalation_id);


--
-- Name: human_reviews human_reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.human_reviews
    ADD CONSTRAINT human_reviews_pkey PRIMARY KEY (review_id);


--
-- Name: model_predictions model_predictions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.model_predictions
    ADD CONSTRAINT model_predictions_pkey PRIMARY KEY (prediction_id);


--
-- Name: model_versions model_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.model_versions
    ADD CONSTRAINT model_versions_pkey PRIMARY KEY (model_version);


--
-- Name: policies policies_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.policies
    ADD CONSTRAINT policies_pkey PRIMARY KEY (policy_id);


--
-- Name: reviewers reviewers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reviewers
    ADD CONSTRAINT reviewers_pkey PRIMARY KEY (reviewer_id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- Name: appeals fk_appeals_case; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.appeals
    ADD CONSTRAINT fk_appeals_case FOREIGN KEY (case_id) REFERENCES public.cases(case_id);


--
-- Name: cases fk_cases_policy; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cases
    ADD CONSTRAINT fk_cases_policy FOREIGN KEY (policy_id) REFERENCES public.policies(policy_id);


--
-- Name: cases fk_cases_user; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cases
    ADD CONSTRAINT fk_cases_user FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- Name: escalations fk_escalations_case; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.escalations
    ADD CONSTRAINT fk_escalations_case FOREIGN KEY (case_id) REFERENCES public.cases(case_id);


--
-- Name: human_reviews fk_human_reviews_case; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.human_reviews
    ADD CONSTRAINT fk_human_reviews_case FOREIGN KEY (case_id) REFERENCES public.cases(case_id);


--
-- Name: human_reviews fk_human_reviews_reviewer; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.human_reviews
    ADD CONSTRAINT fk_human_reviews_reviewer FOREIGN KEY (reviewer_id) REFERENCES public.reviewers(reviewer_id);


--
-- Name: model_predictions fk_model_predictions_case; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.model_predictions
    ADD CONSTRAINT fk_model_predictions_case FOREIGN KEY (case_id) REFERENCES public.cases(case_id);


--
-- Name: model_predictions fk_model_predictions_version; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.model_predictions
    ADD CONSTRAINT fk_model_predictions_version FOREIGN KEY (model_version) REFERENCES public.model_versions(model_version);


--
-- PostgreSQL database dump complete
--

\unrestrict fGcgeGpojGyduOVOVUgMGABcVqnNDPMKCcPGlIDwJalmqGeyHC8tzFn0ojaE0wF

