-- 20260716233055_add_projects_vinyl_color_po.sql
-- VINYL ORDERS board (2026-07-16): ordered color + supplier PO record on the
-- project vinyl marker. Additive + nullable — safe for every shipped iOS
-- build (schema discipline: 03_DATA_ARCHITECTURE.md). Written by every MARK
-- ORDERED path in the same atomic updateProjectFields payload as the
-- vinyl_order_status trio; CLEAR ORDERED nulls all five together.

ALTER TABLE projects
  ADD COLUMN vinyl_color text NULL,
  ADD COLUMN vinyl_po text NULL;
