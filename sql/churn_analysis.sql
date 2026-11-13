-- Insurance customer retention analysis in SQL (SQLite)
-- Table policy_terms is the cleaned output of notebooks/03_data_cleaning.ipynb
-- churned = 1 when the term was cancelled at renewal (CAN_REN) or mid-term (CAN_MT)

-- Q1: Overall cancellation rates
SELECT COUNT(*)                     AS terms,
       ROUND(AVG(CAN_REN) * 100, 1) AS renewal_cancel_pct,
       ROUND(AVG(CAN_MT) * 100, 1)  AS midterm_cancel_pct,
       ROUND(AVG(churned) * 100, 1) AS churn_pct
FROM policy_terms;

-- Q2: Churn by line of business (lines with at least 200 terms)
SELECT Line_of_Business,
       COUNT(*)                     AS terms,
       ROUND(AVG(churned) * 100, 1) AS churn_pct
FROM policy_terms
GROUP BY Line_of_Business
HAVING COUNT(*) >= 200
ORDER BY churn_pct DESC;

-- Q3: Bundled (auto + property) vs single-line clients, built from client product mix
WITH client_mix AS (
    SELECT Client_id,
           CASE WHEN COUNT(DISTINCT LOB_Group) = 2 THEN 'Auto + Property' ELSE 'Single line' END AS bundle_status
    FROM policy_terms
    GROUP BY Client_id
)
SELECT c.bundle_status,
       p.LOB_Group,
       COUNT(*)                       AS terms,
       ROUND(AVG(p.churned) * 100, 1) AS churn_pct
FROM policy_terms p
JOIN client_mix c USING (Client_id)
GROUP BY c.bundle_status, p.LOB_Group
ORDER BY p.LOB_Group, c.bundle_status;

-- Q4: Churn by customer tenure band
SELECT CASE
           WHEN tenure_years <= 1  THEN '1) <1 yr'
           WHEN tenure_years <= 3  THEN '2) 1-3 yrs'
           WHEN tenure_years <= 5  THEN '3) 3-5 yrs'
           WHEN tenure_years <= 10 THEN '4) 5-10 yrs'
           ELSE '5) 10+ yrs'
       END                          AS tenure_band,
       COUNT(*)                     AS terms,
       ROUND(AVG(churned) * 100, 1) AS churn_pct
FROM policy_terms
GROUP BY tenure_band
ORDER BY tenure_band;

-- Q5: Churn by premium quartile (window function)
WITH ranked AS (
    SELECT churned, Term_Premium,
           NTILE(4) OVER (ORDER BY Term_Premium) AS premium_quartile
    FROM policy_terms
)
SELECT premium_quartile,
       COUNT(*)                     AS terms,
       MIN(Term_Premium)            AS min_premium,
       MAX(Term_Premium)            AS max_premium,
       ROUND(AVG(churned) * 100, 1) AS churn_pct
FROM ranked
GROUP BY premium_quartile
ORDER BY premium_quartile;

-- Q6a: Churn by province (at least 1,000 terms)
SELECT Province,
       COUNT(*)                     AS terms,
       ROUND(AVG(churned) * 100, 1) AS churn_pct
FROM policy_terms
GROUP BY Province
HAVING COUNT(*) >= 1000
ORDER BY churn_pct DESC;

-- Q6b: Worst carrier inside each major province (rank within partition)
WITH carrier_prov AS (
    SELECT Province, Carrier_id,
           COUNT(*)                     AS terms,
           ROUND(AVG(churned) * 100, 1) AS churn_pct
    FROM policy_terms
    WHERE Province IN ('ON', 'AB', 'NB')
    GROUP BY Province, Carrier_id
    HAVING COUNT(*) >= 500
)
SELECT Province, Carrier_id, terms, churn_pct,
       RANK() OVER (PARTITION BY Province ORDER BY churn_pct DESC) AS churn_rank
FROM carrier_prov
ORDER BY Province, churn_rank;

-- Impact: Priority segment and estimated value of a 10% churn reduction
WITH segment AS (
    SELECT *
    FROM policy_terms
    WHERE LOB_Group = 'Auto' AND bundled = 'Single line' AND tenure_years <= 5
)
SELECT COUNT(*)                                                       AS segment_terms,
       SUM(churned)                                                   AS lost_terms,
       ROUND(SUM(churned) * 100.0 / (SELECT SUM(churned) FROM policy_terms), 1) AS share_of_all_cancellations_pct,
       ROUND(AVG(CASE WHEN churned = 1 AND premium_outlier = 0 THEN Term_Premium END), 0) AS avg_lost_premium,
       ROUND(SUM(churned) * 0.10, 0)                                  AS terms_saved_at_10pct,
       ROUND(SUM(churned) * 0.10
             * AVG(CASE WHEN churned = 1 AND premium_outlier = 0 THEN Term_Premium END), 0) AS premium_retained_at_10pct
FROM segment;
