
-- ============================================================
-- What's New admin-managed roadmap system
-- ============================================================

-- Categories
CREATE TABLE IF NOT EXISTS whats_new_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  icon TEXT NOT NULL DEFAULT 'star',
  sort_order INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Items
CREATE TABLE IF NOT EXISTS whats_new_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id UUID NOT NULL REFERENCES whats_new_categories(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  icon TEXT NOT NULL DEFAULT 'star',
  status TEXT NOT NULL DEFAULT 'planned'
    CHECK (status IN ('planned', 'in_development', 'in_testing', 'coming_soon', 'shipped', 'completed')),
  feature_flag_slug TEXT,
  sort_order INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_whats_new_items_category ON whats_new_items(category_id);
CREATE INDEX IF NOT EXISTS idx_whats_new_items_status ON whats_new_items(status);

-- Beta Access Requests
CREATE TABLE IF NOT EXISTS beta_access_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  user_email TEXT NOT NULL,
  user_name TEXT NOT NULL,
  company_id TEXT NOT NULL,
  company_name TEXT NOT NULL,
  whats_new_item_id UUID NOT NULL REFERENCES whats_new_items(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),
  admin_notes TEXT,
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_beta_requests_status ON beta_access_requests(status);
CREATE INDEX IF NOT EXISTS idx_beta_requests_user ON beta_access_requests(user_id);

-- RLS
ALTER TABLE whats_new_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE whats_new_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE beta_access_requests ENABLE ROW LEVEL SECURITY;

-- Categories: anyone can read, only service_role can write
CREATE POLICY "whats_new_categories_select" ON whats_new_categories
  FOR SELECT USING (true);

CREATE POLICY "whats_new_categories_admin" ON whats_new_categories
  FOR ALL USING (auth.role() = 'service_role');

-- Items: anyone can read, only service_role can write
CREATE POLICY "whats_new_items_select" ON whats_new_items
  FOR SELECT USING (true);

CREATE POLICY "whats_new_items_admin" ON whats_new_items
  FOR ALL USING (auth.role() = 'service_role');

-- Beta requests: anyone can insert and read, service_role can do anything
CREATE POLICY "beta_requests_insert" ON beta_access_requests
  FOR INSERT WITH CHECK (true);

CREATE POLICY "beta_requests_select" ON beta_access_requests
  FOR SELECT USING (true);

CREATE POLICY "beta_requests_admin" ON beta_access_requests
  FOR ALL USING (auth.role() = 'service_role');

-- ============================================================
-- Seed existing hardcoded data
-- ============================================================

-- Calendar & Scheduling
INSERT INTO whats_new_categories (id, name, icon, sort_order) VALUES
  ('a1000000-0000-0000-0000-000000000001', 'Calendar & Scheduling', 'calendar', 1);

INSERT INTO whats_new_items (category_id, title, description, icon, status, sort_order) VALUES
  ('a1000000-0000-0000-0000-000000000001', 'Calendar Request System', 'Long press on calendar dates to request days off or schedule changes', 'calendar.badge.plus', 'in_development', 1),
  ('a1000000-0000-0000-0000-000000000001', 'Weather Integration', 'Choose weather source in settings, mark jobs as weather dependent, get rain warnings', 'cloud.sun.rain', 'in_development', 2),
  ('a1000000-0000-0000-0000-000000000001', 'Apple Watch', 'Access OPS on Apple Watch to view project notes and details.', 'applewatch.watchface', 'in_development', 3);

-- Time & Analytics
INSERT INTO whats_new_categories (id, name, icon, sort_order) VALUES
  ('a1000000-0000-0000-0000-000000000002', 'Time & Analytics', 'clock', 2);

INSERT INTO whats_new_items (category_id, title, description, icon, status, sort_order) VALUES
  ('a1000000-0000-0000-0000-000000000002', 'Automatic Time Tracking', 'Auto-start tracking when arriving at projects, stop when leaving', 'location.circle', 'coming_soon', 1),
  ('a1000000-0000-0000-0000-000000000002', 'Work Analytics', 'Track days worked, hours logged, jobs completed per hour, and productivity trends', 'chart.line.uptrend.xyaxis', 'in_development', 2),
  ('a1000000-0000-0000-0000-000000000002', 'Project Analytics', 'Track project completion times, team productivity, and trends', 'chart.line.uptrend.xyaxis', 'in_development', 3);

-- Team & Communication
INSERT INTO whats_new_categories (id, name, icon, sort_order) VALUES
  ('a1000000-0000-0000-0000-000000000003', 'Team & Communication', 'person.2', 3);

INSERT INTO whats_new_items (category_id, title, description, icon, status, sort_order) VALUES
  ('a1000000-0000-0000-0000-000000000003', 'Team Member Notes', 'Add specific notes for each team member on a project', 'person.2', 'in_development', 1),
  ('a1000000-0000-0000-0000-000000000003', 'Team Member Locations', 'See where your team members are on the map with real-time updates', 'map', 'in_development', 2),
  ('a1000000-0000-0000-0000-000000000003', 'In-App Messaging', 'Message team members directly within the app with project context', 'message', 'planned', 3),
  ('a1000000-0000-0000-0000-000000000003', 'Contact Info Updates', 'Update teammate contact info with approval notifications', 'person.crop.circle.badge.checkmark', 'coming_soon', 4),
  ('a1000000-0000-0000-0000-000000000003', 'Project Note Notifications', 'Get notified when teammates update project notes', 'bell.badge', 'in_development', 5);

-- Business Features
INSERT INTO whats_new_categories (id, name, icon, sort_order) VALUES
  ('a1000000-0000-0000-0000-000000000004', 'Business Features', 'dollarsign.circle', 4);

INSERT INTO whats_new_items (category_id, title, description, icon, status, sort_order) VALUES
  ('a1000000-0000-0000-0000-000000000004', 'Expense Tracking', 'Detailed expense tracking and submission functionality', 'receipt', 'in_development', 1),
  ('a1000000-0000-0000-0000-000000000004', 'Certifications & Training', 'Track team member certifications, training records, and expiration dates', 'checkmark.shield', 'coming_soon', 2),
  ('a1000000-0000-0000-0000-000000000004', 'Client Portal', 'Allow clients to log in, see their projects and create RFQs.', 'person.circle', 'planned', 3);

-- AI & Web Features
INSERT INTO whats_new_categories (id, name, icon, sort_order) VALUES
  ('a1000000-0000-0000-0000-000000000005', 'AI & Web Features', 'brain', 5);

INSERT INTO whats_new_items (category_id, title, description, icon, status, sort_order) VALUES
  ('a1000000-0000-0000-0000-000000000005', 'AI Quoting System', 'Upload price sheets and project drawings for AI-powered quotes', 'doc.text.magnifyingglass', 'planned', 1);

-- Data & Projects
INSERT INTO whats_new_categories (id, name, icon, sort_order) VALUES
  ('a1000000-0000-0000-0000-000000000006', 'Data & Projects', 'folder', 6);

INSERT INTO whats_new_items (category_id, title, description, icon, status, sort_order) VALUES
  ('a1000000-0000-0000-0000-000000000006', 'Multiple Project Tasks', 'Track and schedule multiple visits to the same project with new TASK data type', 'arrow.triangle.2.circlepath', 'in_development', 1),
  ('a1000000-0000-0000-0000-000000000006', 'Client Project History', 'View all projects for a specific client in one place', 'doc.text', 'planned', 2);

-- Technology Integration
INSERT INTO whats_new_categories (id, name, icon, sort_order) VALUES
  ('a1000000-0000-0000-0000-000000000007', 'Technology Integration', 'apps.iphone', 7);

INSERT INTO whats_new_items (category_id, title, description, icon, status, sort_order) VALUES
  ('a1000000-0000-0000-0000-000000000007', 'Apple CarPlay', 'Access OPS safely while driving with CarPlay integration', 'car', 'coming_soon', 1),
  ('a1000000-0000-0000-0000-000000000007', 'Apple Watch', 'Access OPS on Apple Watch to view project notes and details.', 'applewatch.watchface', 'coming_soon', 2),
  ('a1000000-0000-0000-0000-000000000007', 'Quickbooks Integration', 'Integrate with Quickbooks to import client information and invoices.', 'books.vertical', 'planned', 3);

