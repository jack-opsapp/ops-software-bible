
-- Document templates for customizable invoice/estimate appearance
CREATE TABLE document_templates (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id       UUID NOT NULL,
  name             TEXT NOT NULL,
  document_type    TEXT NOT NULL CHECK (document_type IN ('invoice', 'estimate', 'both')),
  is_default       BOOLEAN NOT NULL DEFAULT false,

  -- Field visibility (all default true)
  show_quantities       BOOLEAN NOT NULL DEFAULT true,
  show_unit_prices      BOOLEAN NOT NULL DEFAULT true,
  show_line_totals      BOOLEAN NOT NULL DEFAULT true,
  show_descriptions     BOOLEAN NOT NULL DEFAULT true,
  show_tax              BOOLEAN NOT NULL DEFAULT true,
  show_discount         BOOLEAN NOT NULL DEFAULT true,
  show_terms            BOOLEAN NOT NULL DEFAULT true,
  show_footer           BOOLEAN NOT NULL DEFAULT true,
  show_payment_info     BOOLEAN NOT NULL DEFAULT true,
  show_from_section     BOOLEAN NOT NULL DEFAULT true,
  show_to_section       BOOLEAN NOT NULL DEFAULT true,

  -- Branding overrides (null = inherit from portal_branding)
  override_logo_url      TEXT,
  override_accent_color  TEXT,
  override_template      TEXT CHECK (override_template IS NULL OR override_template IN ('modern', 'classic', 'bold')),
  override_theme_mode    TEXT CHECK (override_theme_mode IS NULL OR override_theme_mode IN ('light', 'dark')),
  override_font_combo    TEXT CHECK (override_font_combo IS NULL OR override_font_combo IN ('modern', 'classic', 'bold')),

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX idx_doc_templates_company ON document_templates(company_id);
CREATE UNIQUE INDEX idx_doc_templates_default
  ON document_templates(company_id, document_type) WHERE is_default = true;

-- RLS
ALTER TABLE document_templates ENABLE ROW LEVEL SECURITY;

-- Add template_id FK to invoices and estimates
ALTER TABLE invoices ADD COLUMN template_id UUID REFERENCES document_templates(id) ON DELETE SET NULL;
ALTER TABLE estimates ADD COLUMN template_id UUID REFERENCES document_templates(id) ON DELETE SET NULL;

