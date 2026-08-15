
-- expense_categories (must be created first — referenced by expenses)
CREATE TABLE IF NOT EXISTS expense_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL,
    name TEXT NOT NULL,
    icon TEXT,
    is_active BOOLEAN DEFAULT true,
    is_default BOOLEAN DEFAULT false,
    sort_order INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_expense_categories_company ON expense_categories(company_id);

-- expense_settings (one row per company)
CREATE TABLE IF NOT EXISTS expense_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL UNIQUE,
    review_frequency TEXT DEFAULT 'weekly',
    auto_approve_threshold NUMERIC(12,2),
    admin_approval_threshold NUMERIC(12,2),
    require_receipt_photo BOOLEAN DEFAULT true,
    require_project_assignment BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- expense_batches
CREATE TABLE IF NOT EXISTS expense_batches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL,
    batch_number TEXT NOT NULL,
    period_start DATE,
    period_end DATE,
    status TEXT NOT NULL DEFAULT 'pending_review',
    submitted_by UUID,
    reviewed_by UUID,
    reviewed_at TIMESTAMPTZ,
    total_amount NUMERIC(12,2) DEFAULT 0,
    approved_amount NUMERIC(12,2) DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_expense_batches_company ON expense_batches(company_id);

-- expenses (core table)
CREATE TABLE IF NOT EXISTS expenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL,
    submitted_by UUID NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft',
    category_id UUID REFERENCES expense_categories(id),
    merchant_name TEXT,
    description TEXT,
    amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    tax_amount NUMERIC(12,2),
    currency TEXT DEFAULT 'USD',
    expense_date DATE,
    payment_method TEXT,
    receipt_image_url TEXT,
    receipt_thumbnail_url TEXT,
    ocr_raw_data JSONB,
    ocr_confidence REAL,
    batch_id UUID REFERENCES expense_batches(id),
    approved_by UUID,
    approved_at TIMESTAMPTZ,
    rejected_by UUID,
    rejected_at TIMESTAMPTZ,
    rejection_reason TEXT,
    accounting_sync_status TEXT DEFAULT 'pending',
    accounting_sync_id TEXT,
    accounting_synced_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_expenses_company ON expenses(company_id);
CREATE INDEX idx_expenses_submitted_by ON expenses(submitted_by);
CREATE INDEX idx_expenses_status ON expenses(status);
CREATE INDEX idx_expenses_batch ON expenses(batch_id);

-- expense_project_allocations
CREATE TABLE IF NOT EXISTS expense_project_allocations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    expense_id UUID NOT NULL REFERENCES expenses(id) ON DELETE CASCADE,
    project_id TEXT NOT NULL,
    percentage NUMERIC(5,2) NOT NULL CHECK (percentage > 0 AND percentage <= 100),
    amount NUMERIC(12,2)
);

CREATE INDEX idx_expense_allocations_expense ON expense_project_allocations(expense_id);
CREATE INDEX idx_expense_allocations_project ON expense_project_allocations(project_id);

-- accounting_category_mappings
CREATE TABLE IF NOT EXISTS accounting_category_mappings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL,
    expense_category_id UUID NOT NULL REFERENCES expense_categories(id),
    provider TEXT NOT NULL,
    external_account_id TEXT NOT NULL,
    external_account_name TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(company_id, expense_category_id, provider)
);

