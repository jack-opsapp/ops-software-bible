-- Daily account-level metrics
CREATE TABLE ads_daily_account (
  date date PRIMARY KEY,
  spend numeric NOT NULL DEFAULT 0,
  clicks integer NOT NULL DEFAULT 0,
  impressions integer NOT NULL DEFAULT 0,
  conversions numeric NOT NULL DEFAULT 0,
  cpa numeric NOT NULL DEFAULT 0,
  ctr numeric NOT NULL DEFAULT 0,
  synced_at timestamptz NOT NULL DEFAULT now()
);

-- Daily campaign-level metrics
CREATE TABLE ads_daily_campaign (
  date date NOT NULL,
  campaign_name text NOT NULL,
  campaign_status text NOT NULL DEFAULT 'ENABLED',
  spend numeric NOT NULL DEFAULT 0,
  clicks integer NOT NULL DEFAULT 0,
  impressions integer NOT NULL DEFAULT 0,
  conversions numeric NOT NULL DEFAULT 0,
  cpa numeric NOT NULL DEFAULT 0,
  ctr numeric NOT NULL DEFAULT 0,
  synced_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (date, campaign_name)
);

-- Daily keyword-level metrics
CREATE TABLE ads_daily_keyword (
  date date NOT NULL,
  keyword text NOT NULL,
  match_type text NOT NULL DEFAULT 'BROAD',
  spend numeric NOT NULL DEFAULT 0,
  clicks integer NOT NULL DEFAULT 0,
  impressions integer NOT NULL DEFAULT 0,
  conversions numeric NOT NULL DEFAULT 0,
  quality_score integer,
  synced_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (date, keyword)
);

-- Sync status tracking
CREATE TABLE ads_sync_status (
  id text PRIMARY KEY,
  status text NOT NULL DEFAULT 'idle',
  last_synced_date date,
  backfill_progress jsonb,
  error text,
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX idx_ads_daily_account_date ON ads_daily_account (date DESC);
CREATE INDEX idx_ads_daily_campaign_date ON ads_daily_campaign (date DESC);
CREATE INDEX idx_ads_daily_keyword_date ON ads_daily_keyword (date DESC);

-- RLS
ALTER TABLE ads_daily_account ENABLE ROW LEVEL SECURITY;
ALTER TABLE ads_daily_campaign ENABLE ROW LEVEL SECURITY;
ALTER TABLE ads_daily_keyword ENABLE ROW LEVEL SECURITY;
ALTER TABLE ads_sync_status ENABLE ROW LEVEL SECURITY;

-- Seed sync status rows
INSERT INTO ads_sync_status (id, status) VALUES ('daily-sync', 'idle'), ('backfill', 'idle');
