
-- Wizard Analytics: event log for wizard interactions
CREATE TABLE public.wizard_analytics (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id text,
    user_role text,
    platform text NOT NULL DEFAULT 'ios',
    wizard_id text NOT NULL,
    event text NOT NULL,
    step_index integer,
    step_id text,
    total_steps integer,
    duration_ms integer,
    steps_skipped integer,
    trigger_type text,
    trigger_context text,
    is_restart boolean,
    session_id text NOT NULL,
    created_at timestamptz DEFAULT now()
);

-- Index for querying by wizard and user
CREATE INDEX idx_wizard_analytics_wizard_id ON public.wizard_analytics(wizard_id);
CREATE INDEX idx_wizard_analytics_user_id ON public.wizard_analytics(user_id);
CREATE INDEX idx_wizard_analytics_session_id ON public.wizard_analytics(session_id);
CREATE INDEX idx_wizard_analytics_created_at ON public.wizard_analytics(created_at);

-- Enable RLS
ALTER TABLE public.wizard_analytics ENABLE ROW LEVEL SECURITY;

-- Policy: authenticated users can insert their own events
CREATE POLICY "Users can insert own wizard analytics"
    ON public.wizard_analytics FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- Policy: users can read their own events
CREATE POLICY "Users can read own wizard analytics"
    ON public.wizard_analytics FOR SELECT
    TO authenticated
    USING (user_id = auth.uid()::text);

-- Wizard States: cross-device persistence for wizard progress
CREATE TABLE public.wizard_states (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    wizard_id text NOT NULL,
    user_id text NOT NULL,
    status text NOT NULL DEFAULT 'not_started',
    current_step_index integer NOT NULL DEFAULT 0,
    do_not_show boolean NOT NULL DEFAULT false,
    completed_at timestamptz,
    total_duration_ms integer NOT NULL DEFAULT 0,
    steps_skipped integer NOT NULL DEFAULT 0,
    last_active_at timestamptz,
    current_session_id text NOT NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    UNIQUE(wizard_id, user_id)
);

-- Index for querying by user
CREATE INDEX idx_wizard_states_user_id ON public.wizard_states(user_id);

-- Enable RLS
ALTER TABLE public.wizard_states ENABLE ROW LEVEL SECURITY;

-- Policy: users can manage their own wizard states
CREATE POLICY "Users can read own wizard states"
    ON public.wizard_states FOR SELECT
    TO authenticated
    USING (user_id = auth.uid()::text);

CREATE POLICY "Users can insert own wizard states"
    ON public.wizard_states FOR INSERT
    TO authenticated
    WITH CHECK (user_id = auth.uid()::text);

CREATE POLICY "Users can update own wizard states"
    ON public.wizard_states FOR UPDATE
    TO authenticated
    USING (user_id = auth.uid()::text)
    WITH CHECK (user_id = auth.uid()::text);

