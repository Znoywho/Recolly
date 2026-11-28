"""Schema changes `create_all` cannot make on an existing database (it only creates missing tables).

shortcut: idempotent SQL run at startup instead of Alembic; move these into migrations once Alembic is set up.
"""

from sqlalchemy import Engine, text

STATEMENTS = [
    # Sync redesign (2026-11-28): a sync mode replaces the two_way_sync flag; conflict policy; merge base.
    "ALTER TABLE calendar_connections ADD COLUMN IF NOT EXISTS sync_mode VARCHAR(32) NOT NULL DEFAULT 'push'",
    """DO $$ BEGIN
         IF EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_name = 'calendar_connections' AND column_name = 'two_way_sync') THEN
           UPDATE calendar_connections SET sync_mode = 'two_way' WHERE two_way_sync;
           ALTER TABLE calendar_connections DROP COLUMN two_way_sync;
         END IF;
       END $$""",
    "ALTER TABLE calendar_connections ADD COLUMN IF NOT EXISTS conflict_policy VARCHAR(32) NOT NULL DEFAULT 'ask'",
    "ALTER TABLE events ADD COLUMN IF NOT EXISTS synced_snapshot JSONB",
]


def upgrade_schema(engine: Engine) -> None:
    """Bring an older database up to the current models (safe to run on every start)."""
    with engine.begin() as conn:
        for statement in STATEMENTS:
            conn.execute(text(statement))
