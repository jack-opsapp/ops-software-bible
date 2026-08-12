
-- inventory_units
CREATE TABLE public.inventory_units (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    display text NOT NULL,
    is_default boolean NOT NULL DEFAULT false,
    sort_order integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);
ALTER TABLE public.inventory_units ENABLE ROW LEVEL SECURITY;
CREATE POLICY "company_isolation" ON public.inventory_units FOR ALL USING (company_id = (SELECT private.get_user_company_id()));

-- inventory_tags
CREATE TABLE public.inventory_tags (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    name text NOT NULL,
    warning_threshold double precision,
    critical_threshold double precision,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);
ALTER TABLE public.inventory_tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY "company_isolation" ON public.inventory_tags FOR ALL USING (company_id = (SELECT private.get_user_company_id()));

-- inventory_items
CREATE TABLE public.inventory_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    name text NOT NULL,
    description text,
    quantity double precision NOT NULL DEFAULT 0,
    unit_id uuid REFERENCES public.inventory_units(id),
    sku text,
    notes text,
    image_url text,
    warning_threshold double precision,
    critical_threshold double precision,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);
ALTER TABLE public.inventory_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "company_isolation" ON public.inventory_items FOR ALL USING (company_id = (SELECT private.get_user_company_id()));

-- inventory_item_tags (junction table)
CREATE TABLE public.inventory_item_tags (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    item_id uuid NOT NULL REFERENCES public.inventory_items(id) ON DELETE CASCADE,
    tag_id uuid NOT NULL REFERENCES public.inventory_tags(id) ON DELETE CASCADE,
    UNIQUE(item_id, tag_id)
);
ALTER TABLE public.inventory_item_tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY "company_isolation" ON public.inventory_item_tags FOR ALL USING (
    item_id IN (SELECT id FROM public.inventory_items WHERE company_id = (SELECT private.get_user_company_id()))
);

-- inventory_snapshots
CREATE TABLE public.inventory_snapshots (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    created_by_id uuid REFERENCES public.users(id),
    is_automatic boolean NOT NULL DEFAULT false,
    item_count integer NOT NULL DEFAULT 0,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.inventory_snapshots ENABLE ROW LEVEL SECURITY;
CREATE POLICY "company_isolation" ON public.inventory_snapshots FOR ALL USING (company_id = (SELECT private.get_user_company_id()));

-- inventory_snapshot_items
CREATE TABLE public.inventory_snapshot_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    snapshot_id uuid NOT NULL REFERENCES public.inventory_snapshots(id) ON DELETE CASCADE,
    original_item_id uuid,
    name text NOT NULL,
    quantity double precision NOT NULL DEFAULT 0,
    unit_display text,
    sku text,
    tags_string text,
    description text
);
ALTER TABLE public.inventory_snapshot_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "company_isolation" ON public.inventory_snapshot_items FOR ALL USING (
    snapshot_id IN (SELECT id FROM public.inventory_snapshots WHERE company_id = (SELECT private.get_user_company_id()))
);

