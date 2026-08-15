
-- ============================================================
-- LEADERSHIP ASSESSMENT SCHEMA
-- ============================================================

-- 1. Question Pool — the calibrated item bank
CREATE TABLE question_pool (
  id TEXT PRIMARY KEY,
  dimension TEXT NOT NULL CHECK (dimension IN ('drive', 'resilience', 'vision', 'connection', 'adaptability', 'integrity')),
  secondary_dimension TEXT CHECK (secondary_dimension IN ('drive', 'resilience', 'vision', 'connection', 'adaptability', 'integrity')),
  type TEXT NOT NULL CHECK (type IN ('likert', 'situational', 'forced_choice')),
  text TEXT NOT NULL,
  options JSONB,
  scoring_weights JSONB NOT NULL,
  difficulty FLOAT NOT NULL DEFAULT 0.5 CHECK (difficulty >= 0 AND difficulty <= 1),
  reverse_scored BOOLEAN NOT NULL DEFAULT FALSE,
  validity_pair_id TEXT,
  is_impression_management BOOLEAN NOT NULL DEFAULT FALSE,
  version_availability TEXT[] NOT NULL DEFAULT '{quick,deep}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_question_pool_dimension ON question_pool(dimension);
CREATE INDEX idx_question_pool_type ON question_pool(type);
CREATE INDEX idx_question_pool_version ON question_pool USING GIN(version_availability);

-- 2. Archetype Profiles — the 8 leadership archetypes
CREATE TABLE archetype_profiles (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  tagline TEXT NOT NULL,
  ideal_scores JSONB NOT NULL,
  red_flags JSONB NOT NULL DEFAULT '{}',
  description_template TEXT NOT NULL,
  strengths TEXT[] NOT NULL DEFAULT '{}',
  blind_spots TEXT[] NOT NULL DEFAULT '{}',
  growth_actions TEXT[] NOT NULL DEFAULT '{}',
  compatible_with TEXT[] NOT NULL DEFAULT '{}',
  tension_with TEXT[] NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Assessment Sessions — one row per assessment attempt
CREATE TABLE assessment_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  token TEXT UNIQUE NOT NULL,
  first_name TEXT,
  email TEXT,
  version TEXT NOT NULL CHECK (version IN ('quick', 'deep')),
  status TEXT NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'completed', 'abandoned')),
  current_chunk INT NOT NULL DEFAULT 1,
  total_chunks INT NOT NULL,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  archetype TEXT REFERENCES archetype_profiles(id),
  secondary_archetype TEXT REFERENCES archetype_profiles(id),
  scores JSONB,
  score_details JSONB,
  ai_analysis JSONB,
  validity_flags JSONB DEFAULT '{}',
  demographic_context JSONB,
  metadata JSONB DEFAULT '{}',
  is_synthetic BOOLEAN NOT NULL DEFAULT FALSE,
  persona_type TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sessions_token ON assessment_sessions(token);
CREATE INDEX idx_sessions_email ON assessment_sessions(email);
CREATE INDEX idx_sessions_status ON assessment_sessions(status);
CREATE INDEX idx_sessions_synthetic ON assessment_sessions(is_synthetic);

-- 4. Assessment Responses — every individual answer
CREATE TABLE assessment_responses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES assessment_sessions(id) ON DELETE CASCADE,
  chunk_number INT NOT NULL,
  question_id TEXT NOT NULL REFERENCES question_pool(id),
  question_type TEXT NOT NULL,
  question_text TEXT NOT NULL,
  answer_value JSONB NOT NULL,
  dimension_target TEXT NOT NULL,
  secondary_dimension_target TEXT,
  response_time_ms INT,
  answered_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_responses_session ON assessment_responses(session_id);
CREATE INDEX idx_responses_question ON assessment_responses(question_id);

-- 5. Score Norms — percentile data for population comparison
CREATE TABLE score_norms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  dimension TEXT NOT NULL,
  segment TEXT NOT NULL DEFAULT 'all',
  percentile_map JSONB NOT NULL,
  sample_size INT NOT NULL DEFAULT 0,
  computed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_norms_dimension_segment ON score_norms(dimension, segment);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE question_pool ENABLE ROW LEVEL SECURITY;
ALTER TABLE archetype_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE assessment_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE assessment_responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE score_norms ENABLE ROW LEVEL SECURITY;

CREATE POLICY "question_pool_read" ON question_pool FOR SELECT TO anon USING (true);
CREATE POLICY "archetype_profiles_read" ON archetype_profiles FOR SELECT TO anon USING (true);
CREATE POLICY "sessions_insert" ON assessment_sessions FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "sessions_select_by_token" ON assessment_sessions FOR SELECT TO anon USING (true);
CREATE POLICY "sessions_update_own" ON assessment_sessions FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY "responses_insert" ON assessment_responses FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "responses_select" ON assessment_responses FOR SELECT TO anon USING (true);
CREATE POLICY "norms_read" ON score_norms FOR SELECT TO anon USING (true);

