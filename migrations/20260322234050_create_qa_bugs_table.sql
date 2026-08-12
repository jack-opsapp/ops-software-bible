
-- QA Agent Bug Pipeline
-- Designed for: OpenClaw QA agent → Claude Code auto-fix workflow
-- Agent writes bugs here. Claude Code reads and fixes them.

CREATE TABLE IF NOT EXISTS qa_bugs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Bug identity
  title TEXT NOT NULL,                          -- Short descriptive title
  slug TEXT UNIQUE,                             -- URL-safe slug for file references (auto-generated)
  
  -- Classification  
  severity TEXT NOT NULL DEFAULT 'medium'       -- critical, high, medium, low
    CHECK (severity IN ('critical', 'high', 'medium', 'low')),
  category TEXT DEFAULT 'functional'            -- functional, ui, data, performance, security, accessibility
    CHECK (category IN ('functional', 'ui', 'data', 'performance', 'security', 'accessibility')),
  platform TEXT DEFAULT 'web'                   -- web, ios, api
    CHECK (platform IN ('web', 'ios', 'api')),
  
  -- Where it happened
  url TEXT,                                     -- Exact page URL
  page_or_screen TEXT,                          -- e.g. "Job Board", "Estimate Builder", "Client Portal"
  
  -- Who found it
  reporter_agent TEXT NOT NULL,                 -- pete, nick, mike, orchestrator
  reporter_role TEXT,                           -- owner, operator, office, crew, client
  account_used TEXT,                            -- Email of the account that was logged in
  
  -- Reproduction (structured for Claude Code)
  steps JSONB NOT NULL DEFAULT '[]',            -- Array of step strings: ["Navigate to /dashboard", "Click 'New Project'", ...]
  expected_behavior TEXT NOT NULL,              -- What should happen
  actual_behavior TEXT NOT NULL,                -- What actually happened
  
  -- Technical context (minimizes Claude Code investigation time)
  console_errors JSONB DEFAULT '[]',            -- Array of JS console errors captured
  network_errors JSONB DEFAULT '[]',            -- Failed HTTP requests: [{url, status, method}]
  screenshot_url TEXT,                          -- S3 or local path to screenshot
  dom_snapshot TEXT,                            -- Relevant DOM fragment if applicable
  
  -- Code hints (from Software Bible mapping)
  suspected_file TEXT,                          -- e.g. "src/components/ops/pipeline-board.tsx"
  suspected_component TEXT,                     -- e.g. "PipelineBoardCard", "EstimateLineItemEditor"
  related_table TEXT,                           -- e.g. "projects", "estimates", "line_items"
  bible_section TEXT,                           -- e.g. "01_PRODUCT_REQUIREMENTS.md > Task Management"
  
  -- Fix workflow (Claude Code reads/writes these)
  status TEXT NOT NULL DEFAULT 'new'
    CHECK (status IN ('new', 'claimed', 'fixing', 'review', 'verified', 'closed', 'wont_fix', 'cannot_reproduce')),
  fix_branch TEXT,                              -- e.g. "fix/qa-broken-estimate-total"
  fix_pr_url TEXT,                              -- GitHub PR link
  fix_commit TEXT,                              -- Commit SHA of the fix
  fix_notes TEXT,                               -- Claude Code's notes on what it changed
  requires_human_review BOOLEAN DEFAULT false,  -- True if the fix might have side effects
  human_review_reason TEXT,                     -- Why human review is needed
  
  -- Verification
  verified BOOLEAN DEFAULT false,               -- Did re-test confirm the bug?
  verification_notes TEXT,                      -- Notes from verification test
  false_positive BOOLEAN DEFAULT false,         -- Was this a false alarm?
  
  -- Context for prioritization
  user_impact TEXT,                             -- "Blocks estimate approval", "Cosmetic only", etc.
  frequency TEXT DEFAULT 'always'               -- always, often, sometimes, rare, once
    CHECK (frequency IN ('always', 'often', 'sometimes', 'rare', 'once')),
  
  -- Git context
  likely_regression_commit TEXT,                -- If agent can identify when this broke
  related_feature TEXT,                         -- e.g. "pipeline-crm", "client-portal", "estimates"
  
  -- Timestamps
  found_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  claimed_at TIMESTAMPTZ,
  fixed_at TIMESTAMPTZ,
  verified_at TIMESTAMPTZ,
  closed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Auto-generate slug from title
CREATE OR REPLACE FUNCTION generate_qa_bug_slug()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.slug IS NULL THEN
    NEW.slug := lower(regexp_replace(
      regexp_replace(NEW.title, '[^a-zA-Z0-9\s-]', '', 'g'),
      '\s+', '-', 'g'
    )) || '-' || to_char(NEW.found_at, 'YYYYMMDD-HH24MI');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_qa_bug_slug
  BEFORE INSERT ON qa_bugs
  FOR EACH ROW
  EXECUTE FUNCTION generate_qa_bug_slug();

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_qa_bugs_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_qa_bugs_updated_at
  BEFORE UPDATE ON qa_bugs
  FOR EACH ROW
  EXECUTE FUNCTION update_qa_bugs_timestamp();

-- Indexes for Claude Code queries
CREATE INDEX idx_qa_bugs_status ON qa_bugs(status);
CREATE INDEX idx_qa_bugs_severity ON qa_bugs(severity);
CREATE INDEX idx_qa_bugs_status_severity ON qa_bugs(status, severity);
CREATE INDEX idx_qa_bugs_platform ON qa_bugs(platform);
CREATE INDEX idx_qa_bugs_related_feature ON qa_bugs(related_feature);
CREATE INDEX idx_qa_bugs_found_at ON qa_bugs(found_at DESC);

-- RLS: service role only (agents use service key, not user auth)
ALTER TABLE qa_bugs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access" ON qa_bugs
  FOR ALL
  USING (true)
  WITH CHECK (true);

-- Comments for Claude Code discoverability
COMMENT ON TABLE qa_bugs IS 'QA agent bug pipeline. OpenClaw agent writes bugs, Claude Code reads and fixes them.';
COMMENT ON COLUMN qa_bugs.steps IS 'JSON array of string steps. e.g. ["Navigate to /dashboard", "Click New Project button", "Leave title empty", "Click Save"]';
COMMENT ON COLUMN qa_bugs.status IS 'Workflow: new → claimed → fixing → review → verified → closed. Also: wont_fix, cannot_reproduce.';
COMMENT ON COLUMN qa_bugs.suspected_file IS 'Best guess at which source file contains the bug. Reference ops-software-bible for file inventory.';
COMMENT ON COLUMN qa_bugs.requires_human_review IS 'Set true if fix touches auth, payments, data deletion, or permissions.';

