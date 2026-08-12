
ALTER TABLE expense_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_project_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE accounting_category_mappings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Company members can access expense_categories"
    ON expense_categories FOR ALL USING (true);

CREATE POLICY "Company members can access expense_settings"
    ON expense_settings FOR ALL USING (true);

CREATE POLICY "Company members can access expense_batches"
    ON expense_batches FOR ALL USING (true);

CREATE POLICY "Company members can access expenses"
    ON expenses FOR ALL USING (true);

CREATE POLICY "Company members can access expense_project_allocations"
    ON expense_project_allocations FOR ALL USING (true);

CREATE POLICY "Company members can access accounting_category_mappings"
    ON accounting_category_mappings FOR ALL USING (true);

