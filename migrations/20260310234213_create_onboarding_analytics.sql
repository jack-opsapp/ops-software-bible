
CREATE TABLE IF NOT EXISTS public.onboarding_analytics (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id text NOT NULL,
    session_id text NOT NULL,
    user_id uuid,
    variant text,
    flow_type text NOT NULL,
    step_name text NOT NULL,
    action text NOT NULL,
    metadata jsonb,
    created_at timestamptz DEFAULT now()
);

-- Index for querying funnels by session
CREATE INDEX idx_onboarding_analytics_session ON public.onboarding_analytics(session_id);

-- Index for querying by variant for A/B test analysis
CREATE INDEX idx_onboarding_analytics_variant ON public.onboarding_analytics(variant, step_name, action);

-- Index for querying by flow type
CREATE INDEX idx_onboarding_analytics_flow ON public.onboarding_analytics(flow_type, step_name, action);

-- RLS: allow inserts from authenticated and anon (pre-signup analytics)
ALTER TABLE public.onboarding_analytics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow anonymous inserts" ON public.onboarding_analytics
    FOR INSERT TO anon, authenticated
    WITH CHECK (true);

CREATE POLICY "Allow authenticated reads" ON public.onboarding_analytics
    FOR SELECT TO authenticated
    USING (true);

