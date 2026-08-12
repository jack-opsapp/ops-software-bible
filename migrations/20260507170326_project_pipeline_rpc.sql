CREATE OR REPLACE FUNCTION project_pipeline_summary(p_project_id UUID)
RETURNS TABLE(
  quoted_total          NUMERIC,
  quoted_record_id      TEXT,
  invoiced_total        NUMERIC,
  invoiced_record_id    TEXT,
  change_orders_count   INT,
  received_total        NUMERIC,
  received_record_id    TEXT,
  deposit_pct           INT,
  outstanding_total     NUMERIC,
  outstanding_due_date  DATE,
  days_aged             INT
)
LANGUAGE SQL
STABLE
AS $$
  WITH e AS (
    SELECT
      COALESCE(SUM(total), 0)::NUMERIC AS total,
      (SELECT estimate_number FROM estimates
         WHERE project_id = p_project_id::TEXT
           AND status = 'approved'
           AND deleted_at IS NULL
         ORDER BY created_at DESC
         LIMIT 1) AS rec
    FROM estimates
    WHERE project_id = p_project_id::TEXT
      AND status = 'approved'
      AND deleted_at IS NULL
  ),
  i AS (
    SELECT
      COALESCE(SUM(total), 0)::NUMERIC AS total,
      (SELECT invoice_number FROM invoices
         WHERE project_id = p_project_id
           AND status NOT IN ('void','draft')
           AND deleted_at IS NULL
         ORDER BY created_at DESC
         LIMIT 1) AS rec,
      COUNT(*) FILTER (
        WHERE estimate_id IS NOT NULL
          AND created_at > (
            SELECT MIN(created_at) FROM invoices
            WHERE project_id = p_project_id
              AND deleted_at IS NULL
          )
      )::INT AS co_count
    FROM invoices
    WHERE project_id = p_project_id
      AND status NOT IN ('void','draft')
      AND deleted_at IS NULL
  ),
  p AS (
    SELECT
      COALESCE(SUM(pay.amount), 0)::NUMERIC AS total,
      (SELECT pp.reference_number
         FROM payments pp
         JOIN invoices ii ON ii.id = pp.invoice_id
         WHERE ii.project_id = p_project_id
           AND pp.voided_at IS NULL
         ORDER BY pp.payment_date DESC, pp.created_at DESC
         LIMIT 1) AS rec
    FROM payments pay
    JOIN invoices inv ON inv.id = pay.invoice_id
    WHERE inv.project_id = p_project_id
      AND pay.voided_at IS NULL
  )
  SELECT
    e.total                                         AS quoted_total,
    e.rec                                           AS quoted_record_id,
    i.total                                         AS invoiced_total,
    i.rec                                           AS invoiced_record_id,
    i.co_count                                      AS change_orders_count,
    p.total                                         AS received_total,
    p.rec                                           AS received_record_id,
    CASE WHEN i.total > 0
         THEN ROUND((p.total / i.total) * 100)::INT
         ELSE NULL END                              AS deposit_pct,
    GREATEST(i.total - p.total, 0)                  AS outstanding_total,
    (SELECT MIN(due_date) FROM invoices
       WHERE project_id = p_project_id
         AND status NOT IN ('void','paid','draft')
         AND deleted_at IS NULL)                    AS outstanding_due_date,
    (SELECT EXTRACT(DAY FROM NOW() - MIN(due_date))::INT FROM invoices
       WHERE project_id = p_project_id
         AND status = 'past_due'
         AND deleted_at IS NULL)                    AS days_aged
  FROM e, i, p;
$$;

COMMENT ON FUNCTION project_pipeline_summary(UUID) IS
'Workspace accounting aggregate. Returns one row with the 4-cell pipeline (QUOTED / INVOICED / RECEIVED / OUTSTANDING) plus latest-record identifiers, change-order count, deposit %, due date, and aging days. SECURITY INVOKER — relies on table-level RLS for company scoping.';

GRANT EXECUTE ON FUNCTION project_pipeline_summary(UUID) TO authenticated;
