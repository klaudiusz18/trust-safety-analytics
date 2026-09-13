-- ============================================================
-- 02_data_generation.sql
-- Trust & Safety Analytics Portfolio
-- ------------------------------------------------------------
-- Purpose:
--   Generate a reproducible synthetic Trust & Safety dataset.
--
-- Important:
--   This script is intended for a fresh/empty database.
--   The production portfolio database used during development
--   already contains populated data and should not be overwritten.
--
-- Synthetic design:
--   ~2,000 users
--   ~10,000 generated cases + 6 seed cases
--   3 model versions
--   Human reviews, model predictions, escalations and appeals
--
-- The data is simulated for portfolio demonstration purposes.
-- ============================================================


-- ============================================================
-- 1. Reference data
-- ============================================================

INSERT INTO policies
    (policy_id, policy_name, severity)
VALUES
    (1, 'Spam', 'Low'),
    (2, 'Fraud', 'High'),
    (3, 'Counterfeit Goods', 'High'),
    (4, 'Harassment', 'Medium'),
    (5, 'Regulated Goods', 'Critical'),
    (6, 'Account Abuse', 'High')
ON CONFLICT (policy_id) DO NOTHING;


INSERT INTO reviewers
    (reviewer_id, reviewer_name, team, experience_level)
VALUES
    (101, 'Reviewer A', 'Marketplace Safety', 'Senior'),
    (102, 'Reviewer B', 'Marketplace Safety', 'Mid'),
    (103, 'Reviewer C', 'Fraud Operations', 'Junior')
ON CONFLICT (reviewer_id) DO NOTHING;


INSERT INTO model_versions
    (model_version, model_name, deployment_date)
VALUES
    ('v3.1', 'TrustGuard', DATE '2025-12-01'),
    ('v3.2', 'TrustGuard', DATE '2026-01-05'),
    ('v3.3', 'TrustGuard', DATE '2026-02-15')
ON CONFLICT (model_version) DO NOTHING;


-- ============================================================
-- 2. Users
-- ============================================================

INSERT INTO users
    (user_id, account_created_at, seller_type, account_status)
SELECT
    gs,
    TIMESTAMP '2024-01-01'
        + (gs % 700) * INTERVAL '1 day',
    CASE
        WHEN gs % 5 = 0 THEN 'Business'
        ELSE 'Individual'
    END,
    CASE
        WHEN gs % 20 = 0 THEN 'Suspended'
        ELSE 'Active'
    END
FROM generate_series(1, 2000) AS gs
ON CONFLICT (user_id) DO NOTHING;


-- ============================================================
-- 3. Seed cases
-- ============================================================

INSERT INTO cases
    (case_id, user_id, priority, queue, created_at,
     risk_score, policy_id, content_type, review_status)
VALUES
    (1001, 1, 'Critical', 'Fraud',
     TIMESTAMP '2025-10-03 09:00:00',
     0.920, 2, 'Product Listing', 'Reviewed'),

    (1002, 2, 'Low', 'Spam',
     TIMESTAMP '2025-10-05 10:00:00',
     0.310, 1, 'Message', 'Reviewed'),

    (1003, 3, 'Critical', 'Marketplace Integrity',
     TIMESTAMP '2025-10-10 11:00:00',
     0.880, 5, 'Product Listing', 'Reviewed'),

    (1004, 4, 'High', 'Fraud',
     TIMESTAMP '2025-10-12 13:00:00',
     NULL, 2, 'Image', 'Reviewed'),

    (1005, 5, 'Medium', 'Spam',
     TIMESTAMP '2025-10-15 14:00:00',
     NULL, 1, 'Advertisement', 'Reviewed'),

    (1006, 6, 'High', 'Fraud',
     TIMESTAMP '2025-10-18 15:00:00',
     NULL, 2, 'Seller Profile', 'Reviewed')
ON CONFLICT (case_id) DO NOTHING;


-- ============================================================
-- 4. Generated cases
-- ============================================================

INSERT INTO cases
    (case_id, user_id, priority, queue, created_at,
     risk_score, policy_id, content_type, review_status)
SELECT
    gs,
    ((gs - 1007) % 2000) + 1,

    CASE
        WHEN gs % 101 < 10 THEN 'Critical'
        WHEN gs % 4 = 0 THEN 'High'
        WHEN gs % 3 = 0 THEN 'Low'
        ELSE 'Medium'
    END,

    CASE
        WHEN gs % 10 < 4 THEN 'Spam'
        WHEN gs % 10 < 8 THEN 'Fraud'
        ELSE 'Marketplace Integrity'
    END,

    TIMESTAMP '2025-10-01'
        + ((gs - 1007) % 365) * INTERVAL '1 day'
        + (gs % 24) * INTERVAL '1 hour',

    CASE
        WHEN (gs % 100) < 54 THEN
            ROUND((0.50 + ((gs % 50)::numeric / 100))::numeric, 3)
        ELSE
            ROUND((0.10 + ((gs % 40)::numeric / 100))::numeric, 3)
    END,

    CASE
        WHEN gs % 20 < 4 THEN 5
        WHEN gs % 20 < 8 THEN 2
        WHEN gs % 20 < 11 THEN 3
        WHEN gs % 20 < 14 THEN 6
        WHEN gs % 20 < 17 THEN 4
        ELSE 1
    END,

    CASE
        WHEN gs % 5 = 0 THEN 'Seller Profile'
        WHEN gs % 5 = 1 THEN 'Message'
        WHEN gs % 5 = 2 THEN 'Product Listing'
        WHEN gs % 5 = 3 THEN 'Image'
        ELSE 'Advertisement'
    END,

    'Reviewed'
FROM generate_series(1007, 11006) AS gs
ON CONFLICT (case_id) DO NOTHING;


-- ============================================================
-- 5. Human reviews
-- ============================================================

INSERT INTO human_reviews
    (review_id, case_id, reviewer_id, decision,
     reviewed_at, review_duration_minutes)
SELECT
    c.case_id,
    c.case_id,
    CASE
        WHEN c.case_id % 3 = 0 THEN 101
        WHEN c.case_id % 3 = 1 THEN 102
        ELSE 103
    END,

    CASE
        WHEN c.case_id % 100 < 54 THEN 'Violation'
        ELSE 'No Violation'
    END,

    c.created_at + INTERVAL '1 day'
        + (c.case_id % 12) * INTERVAL '1 hour',

    CASE
        WHEN c.case_id % 3 = 0 THEN 20 + (c.case_id % 15)
        WHEN c.case_id % 3 = 1 THEN 15 + (c.case_id % 10)
        ELSE 20 + (c.case_id % 12)
    END

FROM cases c
WHERE c.case_id BETWEEN 1007 AND 11006
ON CONFLICT (review_id) DO NOTHING;


-- ============================================================
-- 6. Model predictions
-- ============================================================

-- v3.1
INSERT INTO model_predictions
    (prediction_id, case_id, model_version,
     prediction, confidence, predicted_at)
SELECT
    c.case_id,
    c.case_id,
    'v3.1',

    CASE
        WHEN c.case_id % 100 < 54 THEN
            CASE
                WHEN c.case_id % 6 = 0 THEN 'No Violation'
                ELSE 'Violation'
            END
        ELSE
            CASE
                WHEN c.case_id % 11 = 0 THEN 'Violation'
                ELSE 'No Violation'
            END
    END,

    CASE
        WHEN c.case_id % 10 < 4 THEN 0.80 + ((c.case_id % 20)::numeric / 100)
        ELSE 0.55 + ((c.case_id % 25)::numeric / 100)
    END,

    c.created_at + INTERVAL '2 hours'

FROM cases c
WHERE c.case_id BETWEEN 1007 AND 11006;


-- v3.2
INSERT INTO model_predictions
    (prediction_id, case_id, model_version,
     prediction, confidence, predicted_at)
SELECT
    c.case_id + 10000,
    c.case_id,
    'v3.2',

    CASE
        WHEN c.case_id % 100 < 54 THEN
            CASE
                -- Regulated Goods gets a deliberately higher
                -- synthetic false-negative rate.
                WHEN c.policy_id = 5
                     AND c.case_id % 5 = 0
                    THEN 'No Violation'
                WHEN c.case_id % 10 = 0
                    THEN 'No Violation'
                ELSE 'Violation'
            END
        ELSE
            CASE
                WHEN c.case_id % 17 = 0 THEN 'Violation'
                ELSE 'No Violation'
            END
    END,

    CASE
        WHEN c.case_id % 8 < 4 THEN 0.85 + ((c.case_id % 10)::numeric / 100)
        ELSE 0.60 + ((c.case_id % 20)::numeric / 100)
    END,

    c.created_at + INTERVAL '3 hours'

FROM cases c
WHERE c.case_id BETWEEN 1007 AND 11006;


-- v3.3
INSERT INTO model_predictions
    (prediction_id, case_id, model_version,
     prediction, confidence, predicted_at)
SELECT
    c.case_id + 20000,
    c.case_id,
    'v3.3',

    CASE
        WHEN c.case_id % 100 < 54 THEN
            CASE
                WHEN c.case_id % 13 = 0 THEN 'No Violation'
                ELSE 'Violation'
            END
        ELSE
            CASE
                WHEN c.case_id % 9 = 0 THEN 'Violation'
                ELSE 'No Violation'
            END
    END,

    CASE
        WHEN c.case_id % 6 < 4 THEN 0.82 + ((c.case_id % 15)::numeric / 100)
        ELSE 0.58 + ((c.case_id % 25)::numeric / 100)
    END,

    c.created_at + INTERVAL '4 hours'

FROM cases c
WHERE c.case_id BETWEEN 1007 AND 11006;


-- ============================================================
-- 7. Escalations
-- ============================================================

INSERT INTO escalations
    (escalation_id, case_id, escalation_reason,
     escalation_level, escalated_at, resolved_at)
SELECT
    c.case_id,
    c.case_id,

    CASE
        WHEN c.case_id % 10 < 5 THEN 'Complex case'
        WHEN c.case_id % 10 < 7 THEN 'Critical priority review'
        WHEN c.case_id % 10 < 9 THEN 'AI-human disagreement'
        ELSE 'High-risk case'
    END,

    CASE
        WHEN c.case_id % 10 < 3 THEN 1
        WHEN c.case_id % 10 < 8 THEN 2
        ELSE 3
    END,

    c.created_at + INTERVAL '2 days',

    c.created_at
        + CASE
            WHEN c.case_id % 10 < 3 THEN INTERVAL '2 days'
            WHEN c.case_id % 10 < 8 THEN INTERVAL '3 days'
            ELSE INTERVAL '4 days'
          END

FROM cases c
WHERE c.case_id BETWEEN 1007 AND 11006
  AND c.case_id % 5 = 0;


-- ============================================================
-- 8. Appeals
-- ============================================================

INSERT INTO appeals
    (appeal_id, case_id, appeal_reason,
     appeal_outcome, submitted_at, resolved_at)
SELECT
    c.case_id,
    c.case_id,

    CASE
        WHEN c.case_id % 3 = 0 THEN 'Incorrect enforcement'
        WHEN c.case_id % 3 = 1 THEN 'Context not considered'
        ELSE 'Policy disagreement'
    END,

    CASE
        WHEN c.case_id % 20 < 13 THEN 'Upheld'
        WHEN c.case_id % 20 < 18 THEN 'Overturned'
        ELSE 'Partially Overturned'
    END,

    c.created_at + INTERVAL '5 days',

    c.created_at + INTERVAL '8 days'

FROM cases c
WHERE c.case_id BETWEEN 1007 AND 11006
  AND c.case_id % 7 = 0;


-- ============================================================
-- End of synthetic data generation
-- ============================================================