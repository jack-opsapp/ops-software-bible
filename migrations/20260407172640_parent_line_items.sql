ALTER TABLE line_items
ADD COLUMN parent_line_item_id UUID REFERENCES line_items(id) ON DELETE CASCADE;

CREATE INDEX idx_line_items_parent ON line_items(parent_line_item_id)
WHERE parent_line_item_id IS NOT NULL;

COMMENT ON COLUMN line_items.parent_line_item_id IS
  'Self-referential FK for parent-child line item hierarchy. NULL = top-level or standalone item.';
