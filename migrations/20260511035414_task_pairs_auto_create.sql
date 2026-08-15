-- Task Pairs: Auto-create dependent tasks with scheduling rules.
-- Spec: docs/superpowers/specs/2026-05-10-task-pairs-auto-create-design.md
-- Bug:  f4bbd11c-7e79-482f-843d-b286052f3477

-- Additive only. Safe for older iOS clients (unknown columns are ignored).

ALTER TABLE project_tasks
    ADD COLUMN IF NOT EXISTS paired_from_task_id UUID NULL
        REFERENCES project_tasks(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS schedule_locked BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_project_tasks_paired_from
    ON project_tasks(paired_from_task_id)
    WHERE paired_from_task_id IS NOT NULL;

ALTER TABLE task_types
    ADD COLUMN IF NOT EXISTS default_duration INTEGER NOT NULL DEFAULT 1
        CHECK (default_duration >= 1 AND default_duration <= 365);

COMMENT ON COLUMN project_tasks.paired_from_task_id IS
    'ID of the predecessor task that auto-spawned this task. Used for cascading delete/cancel and pair disambiguation. NULL for manually-created tasks.';

COMMENT ON COLUMN project_tasks.schedule_locked IS
    'True once user has manually edited start_date. Predecessor date cascades skip this task. Reset by deleting/recreating.';

COMMENT ON COLUMN task_types.default_duration IS
    'Default duration in days for newly-created tasks of this type (used by TaskPairSpawner and other auto-creation paths).';

-- TaskTypeDependency JSONB schema extended in-place — no DDL needed for new
-- fields (auto_create, inherit_crew, min_gap_days_after_end, weekday_constraint).
-- Backward-compatible decoders apply safe defaults for older payloads.

