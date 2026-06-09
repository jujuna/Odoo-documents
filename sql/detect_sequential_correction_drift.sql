-- ============================================================================
-- detect_sequential_correction_drift.sql
--
-- Read-only detection script for the rs_einvoice Phase A safety tightening.
-- Run BEFORE deploying Phase A to surface pre-existing risky data:
--   1. Sequential-correction clusters (>1 posted CN on the same original).
--   2. Amount-cap candidates — clusters where total credited amount per
--      product line already exceeds the original's net amount.
--   3. Chained k=1 candidates — clusters where a confirmed k_type=1 CN
--      coexists with any other posted CN on the same original.
--
-- Usage:
--   psql -h <host> -U <user> -d <db> -f detect_sequential_correction_drift.sql
--
-- Output is INFORMATIONAL. No rows are modified. Use the output to manually
-- review and reconcile risky clusters before flipping Phase A live.
-- ============================================================================

\echo
\echo '============================================================================='
\echo 'Pass 1 — Sequential-correction clusters (originals with > 1 posted CN)'
\echo '============================================================================='
\echo

SELECT
    parent.id                                       AS original_id,
    parent.name                                     AS original_name,
    COUNT(child.id)                                 AS cn_count,
    ARRAY_AGG(child.id ORDER BY child.invoice_date) AS cn_ids,
    ARRAY_AGG(child.rs_einv_status
              ORDER BY child.invoice_date)          AS cn_statuses,
    ARRAY_AGG(child.rs_einv_k_type
              ORDER BY child.invoice_date)          AS cn_k_types,
    ARRAY_AGG(child.rs_einv_tax_only
              ORDER BY child.invoice_date)          AS cn_tax_only_flags,
    ARRAY_AGG(child.rs_einv_skip
              ORDER BY child.invoice_date)          AS cn_skip_flags
FROM account_move parent
JOIN account_move child
  ON child.reversed_entry_id = parent.id
WHERE parent.move_type IN ('out_invoice', 'in_invoice')
  AND child.state = 'posted'
  AND child.move_type IN ('out_refund', 'in_refund')
GROUP BY parent.id, parent.name
HAVING COUNT(child.id) > 1
ORDER BY COUNT(child.id) DESC, parent.id;


\echo
\echo '============================================================================='
\echo 'Pass 2 — Amount-cap candidates (clusters where sum(CN amounts) > original)'
\echo
\echo 'These would FAIL the new amount cap if reposted. Manual review needed.'
\echo 'Filtering matches the new cap: excludes tax_only / k_type=2 CNs, and'
\echo 'excludes skipped CNs with reason in (bad_debt, netting, down_payment,'
\echo 'warranty, intercompany_mirror, commercial_gesture).'
\echo '============================================================================='
\echo

WITH cn_eligible AS (
    SELECT
        cn.id                AS cn_id,
        cn.reversed_entry_id AS original_id,
        cn.invoice_date,
        cn.rs_einv_k_type,
        cn.rs_einv_tax_only,
        cn.rs_einv_skip,
        cn.rs_einv_skip_reason
    FROM account_move cn
    WHERE cn.state = 'posted'
      AND cn.move_type IN ('out_refund', 'in_refund')
      AND cn.reversed_entry_id IS NOT NULL
      AND COALESCE(cn.rs_einv_tax_only, FALSE) = FALSE
      AND cn.rs_einv_k_type IS DISTINCT FROM '2'
      AND NOT (
          COALESCE(cn.rs_einv_skip, FALSE) = TRUE
          AND cn.rs_einv_skip_reason IN (
              'bad_debt', 'netting', 'down_payment',
              'warranty', 'intercompany_mirror', 'commercial_gesture'
          )
      )
),
cn_line_amounts AS (
    SELECT
        e.original_id,
        e.cn_id,
        aml.product_id,
        COALESCE(NULLIF(TRIM(aml.name), ''), '')        AS line_name,
        SUM(ABS(COALESCE(aml.price_subtotal, 0)))       AS cn_amount
    FROM cn_eligible e
    JOIN account_move_line aml
      ON aml.move_id = e.cn_id
    WHERE aml.display_type = 'product'
    GROUP BY e.original_id, e.cn_id, aml.product_id,
             COALESCE(NULLIF(TRIM(aml.name), ''), '')
),
orig_line_amounts AS (
    SELECT
        aml.move_id                                     AS original_id,
        aml.product_id,
        COALESCE(NULLIF(TRIM(aml.name), ''), '')        AS line_name,
        SUM(ABS(COALESCE(aml.price_subtotal, 0)))       AS orig_amount
    FROM account_move_line aml
    JOIN account_move m
      ON m.id = aml.move_id
    WHERE aml.display_type = 'product'
      AND m.move_type IN ('out_invoice', 'in_invoice')
    GROUP BY aml.move_id, aml.product_id,
             COALESCE(NULLIF(TRIM(aml.name), ''), '')
),
agg AS (
    SELECT
        c.original_id,
        c.product_id,
        c.line_name,
        SUM(c.cn_amount)                                AS used_amount,
        COUNT(DISTINCT c.cn_id)                         AS cn_count
    FROM cn_line_amounts c
    GROUP BY c.original_id, c.product_id, c.line_name
)
SELECT
    parent.id                                           AS original_id,
    parent.name                                         AS original_name,
    a.product_id,
    a.line_name,
    a.cn_count,
    ROUND(o.orig_amount::numeric, 2)                    AS original_net_amount,
    ROUND(a.used_amount::numeric, 2)                    AS sum_credited_amount,
    ROUND((a.used_amount - o.orig_amount)::numeric, 2)  AS overshoot
FROM agg a
JOIN orig_line_amounts o
  ON o.original_id = a.original_id
 AND o.product_id IS NOT DISTINCT FROM a.product_id
 AND o.line_name  IS NOT DISTINCT FROM a.line_name
JOIN account_move parent
  ON parent.id = a.original_id
WHERE a.used_amount > o.orig_amount + 0.01  -- same tolerance as the new cap
ORDER BY (a.used_amount - o.orig_amount) DESC,
         parent.id;


\echo
\echo '============================================================================='
\echo 'Pass 3 — Chained k=1 candidates (k=1 confirmed coexists with another CN)'
\echo
\echo 'These would FAIL the new k=1-on-k=1 block if reposted. Manual review needed.'
\echo '============================================================================='
\echo

WITH k1_confirmed AS (
    SELECT
        cn.id                AS cn_id,
        cn.name              AS cn_name,
        cn.reversed_entry_id AS original_id,
        cn.invoice_date
    FROM account_move cn
    WHERE cn.state = 'posted'
      AND cn.move_type IN ('out_refund', 'in_refund')
      AND cn.rs_einv_status = '8'
      AND cn.rs_einv_k_type = '1'
)
SELECT
    parent.id                                           AS original_id,
    parent.name                                         AS original_name,
    k1.cn_id                                            AS confirmed_k1_cn_id,
    k1.cn_name                                          AS confirmed_k1_cn_name,
    ARRAY_AGG(other.id ORDER BY other.invoice_date)     AS other_posted_cn_ids,
    ARRAY_AGG(other.rs_einv_status
              ORDER BY other.invoice_date)              AS other_cn_statuses,
    ARRAY_AGG(other.rs_einv_k_type
              ORDER BY other.invoice_date)              AS other_cn_k_types
FROM k1_confirmed k1
JOIN account_move parent
  ON parent.id = k1.original_id
JOIN account_move other
  ON other.reversed_entry_id = k1.original_id
 AND other.id <> k1.cn_id
 AND other.state = 'posted'
 AND other.move_type IN ('out_refund', 'in_refund')
GROUP BY parent.id, parent.name, k1.cn_id, k1.cn_name
ORDER BY parent.id;


\echo
\echo '============================================================================='
\echo 'Pass 4 — Bad-debt / warranty skip CNs with VAT or income-account lines'
\echo
\echo 'Phase A.5 logs a soft warning on these at post time. Lines per Georgian TC:'
\echo '  - bad_debt / warranty (option B) CNs MUST NOT carry VAT taxes.'
\echo '  - Product lines MUST NOT post to income-type accounts (revenue stays).'
\echo 'Correct entry: Dr <Expense Account> / Cr Account Receivable, no VAT.'
\echo '============================================================================='
\echo

WITH problem_cns AS (
    SELECT cn.id                AS cn_id,
           cn.name               AS cn_name,
           cn.rs_einv_skip_reason,
           cn.invoice_date,
           p.name->>'en_US'      AS partner_name
    FROM account_move cn
    LEFT JOIN res_partner p ON p.id = cn.partner_id
    WHERE cn.state = 'posted'
      AND cn.move_type IN ('out_refund', 'in_refund')
      AND COALESCE(cn.rs_einv_skip, FALSE) = TRUE
      AND cn.rs_einv_skip_reason IN ('bad_debt', 'warranty')
)
SELECT pc.cn_id,
       pc.cn_name,
       pc.rs_einv_skip_reason,
       pc.invoice_date,
       pc.partner_name,
       COUNT(DISTINCT amlt.account_tax_id)                AS vat_line_count,
       COUNT(DISTINCT CASE
           WHEN aa.account_type = 'income' THEN aml.id END) AS income_line_count,
       ROUND(SUM(CASE
           WHEN aa.account_type = 'income'
           THEN ABS(COALESCE(aml.price_subtotal, 0)) END)::numeric, 2)
                                                          AS income_line_amount
FROM problem_cns pc
JOIN account_move_line aml
  ON aml.move_id = pc.cn_id
JOIN account_account aa
  ON aa.id = aml.account_id
LEFT JOIN account_move_line_account_tax_rel amlt
  ON amlt.account_move_line_id = aml.id
WHERE aml.display_type = 'product'
GROUP BY pc.cn_id, pc.cn_name, pc.rs_einv_skip_reason,
         pc.invoice_date, pc.partner_name
HAVING COUNT(DISTINCT amlt.account_tax_id) > 0
    OR COUNT(DISTINCT CASE
           WHEN aa.account_type = 'income' THEN aml.id END) > 0
ORDER BY pc.cn_id;


\echo
\echo '============================================================================='
\echo 'Detection complete. No data modified.'
\echo
\echo 'Next steps:'
\echo '  - Review each row from Pass 2 and Pass 3.'
\echo '  - For Pass 2 rows: confirm whether the over-credit is intentional or'
\echo '    operator error; reconcile manually if needed.'
\echo '  - For Pass 3 rows: confirm whether the follow-up CN was intentional'
\echo '    (e.g. a corrective k=1 after a partial), and if so, document the'
\echo '    rationale or cancel the follow-up.'
\echo '  - For Pass 4 rows: each is a bad-debt/warranty CN whose lines violate'
\echo '    Georgian TC. Either reset to draft + fix the lines (remove VAT,'
\echo '    move account from income to expense) + repost, or accept as'
\echo '    historical drift and document for the auditor.'
\echo '  - Once clean, deploy Phase A and rerun this script to confirm zero'
\echo '    rows from Pass 2, Pass 3, and Pass 4.'
\echo '============================================================================='
\echo
