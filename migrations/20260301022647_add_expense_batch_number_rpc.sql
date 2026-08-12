
CREATE OR REPLACE FUNCTION get_next_expense_batch_number(p_company_id UUID)
RETURNS TEXT AS $$
DECLARE
    next_num INT;
    result TEXT;
BEGIN
    SELECT COALESCE(MAX(
        CAST(REPLACE(batch_number, 'EXP-BATCH-', '') AS INT)
    ), 0) + 1
    INTO next_num
    FROM expense_batches
    WHERE company_id = p_company_id;

    result := 'EXP-BATCH-' || LPAD(next_num::TEXT, 4, '0');
    RETURN result;
END;
$$ LANGUAGE plpgsql;

