-- 003_friends_settlements_verification.sql
-- Migration: Schema for features added after 002, which the API already uses:
--   * group descriptions, per-user and per-expense currency
--   * settlements (settle-up records), friendships (friend requests), email verification
-- Also locks the tables down: the API talks to Supabase with the secret key (which
-- bypasses RLS), so RLS is enabled with no policies to keep the public Data API closed.
--
-- Note: sync_full_database rewrites users on every save, so friendships and
-- email_verifications intentionally have no foreign key to users (a cascade would
-- wipe them on each write).

-- 1. New columns
ALTER TABLE users        ADD COLUMN IF NOT EXISTS currency    TEXT NOT NULL DEFAULT 'MYR';
ALTER TABLE groups_table ADD COLUMN IF NOT EXISTS description TEXT NOT NULL DEFAULT '';
ALTER TABLE expenses     ADD COLUMN IF NOT EXISTS currency    TEXT NULL;

-- 2. Settlements: "A paid B back" records, mirrored per group by supabaseService.syncSettlements
CREATE TABLE IF NOT EXISTS settlements (
    id        TEXT PRIMARY KEY,
    group_id  TEXT NOT NULL REFERENCES groups_table(id) ON DELETE CASCADE,
    from_user TEXT NOT NULL,
    to_user   TEXT NOT NULL,
    amount    NUMERIC(10,2) NOT NULL CHECK (amount > 0),
    date      TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_settlements_group_id ON settlements(group_id);

-- 3. Friendships: one row per request; status moves pending -> accepted (rejects are deleted)
CREATE TABLE IF NOT EXISTS friendships (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    requester_id TEXT NOT NULL,
    target_id    TEXT NOT NULL,
    status       TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted')),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (requester_id, target_id),
    CHECK (requester_id <> target_id)
);

CREATE INDEX IF NOT EXISTS idx_friendships_target_status ON friendships(target_id, status);

-- 4. Email verification: one row per user (upserted on register / resend)
CREATE TABLE IF NOT EXISTS email_verifications (
    user_id     TEXT PRIMARY KEY,
    token       TEXT NOT NULL UNIQUE,
    expires_at  TIMESTAMPTZ NOT NULL,
    verified_at TIMESTAMPTZ NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5. Persist the new columns in the full-database sync
CREATE OR REPLACE FUNCTION sync_full_database(
    p_current_user_id TEXT,
    p_users JSONB,
    p_accounts JSONB,
    p_groups JSONB
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    group_record RECORD;
    expense_record RECORD;
BEGIN
    DELETE FROM expense_split_members WHERE true;
    DELETE FROM expenses WHERE true;
    DELETE FROM group_members WHERE true;
    DELETE FROM groups_table WHERE true;
    DELETE FROM accounts WHERE true;
    DELETE FROM app_state WHERE true;
    DELETE FROM users WHERE true;

    INSERT INTO users (id, name, avatar, email, currency)
    SELECT x.id, x.name, COALESCE(x.avatar, '👤'), x.email, COALESCE(x.currency, 'MYR')
    FROM jsonb_to_recordset(p_users) AS x(id TEXT, name TEXT, avatar TEXT, email TEXT, currency TEXT);

    INSERT INTO app_state (id, current_user_id) VALUES (1, p_current_user_id);

    IF p_accounts IS NOT NULL AND jsonb_array_length(p_accounts) > 0 THEN
        INSERT INTO accounts (user_id, email, password_hash, salt, created_at)
        SELECT x."userId", x.email, x."passwordHash", x.salt, x."createdAt"
        FROM jsonb_to_recordset(p_accounts) AS x(
            "userId" TEXT, email TEXT, "passwordHash" TEXT, salt TEXT, "createdAt" TEXT
        );
    END IF;

    IF p_groups IS NOT NULL AND jsonb_array_length(p_groups) > 0 THEN
        INSERT INTO groups_table (id, name, emoji, description, created_at)
        SELECT x.id, x.name, x.emoji, COALESCE(x.description, ''), x."createdAt"
        FROM jsonb_to_recordset(p_groups) AS x(
            id TEXT, name TEXT, emoji TEXT, description TEXT, "createdAt" TEXT
        );

        FOR group_record IN
            SELECT * FROM jsonb_to_recordset(p_groups) AS x(
                id TEXT, members JSONB, expenses JSONB
            )
        LOOP
            IF group_record.members IS NOT NULL AND jsonb_array_length(group_record.members) > 0 THEN
                INSERT INTO group_members (group_id, user_id)
                SELECT group_record.id, member_data->>'id'
                FROM jsonb_array_elements(group_record.members) AS member_data;
            END IF;

            IF group_record.expenses IS NOT NULL AND jsonb_array_length(group_record.expenses) > 0 THEN
                INSERT INTO expenses (id, description, amount, paid_by, category, date, group_id, currency)
                SELECT
                    e_data->>'id',
                    e_data->>'description',
                    (e_data->>'amount')::NUMERIC,
                    e_data->>'paidBy',
                    e_data->>'category',
                    e_data->>'date',
                    group_record.id,
                    e_data->>'currency'
                FROM jsonb_array_elements(group_record.expenses) AS e_data;

                FOR expense_record IN
                    SELECT
                        e_data->>'id' AS exp_id,
                        e_data->'splitBetween' AS split_data,
                        e_data->'splitAmounts' AS amounts_data
                    FROM jsonb_array_elements(group_record.expenses) AS e_data
                LOOP
                    IF expense_record.split_data IS NOT NULL AND
                       jsonb_array_length(expense_record.split_data) > 0 THEN
                        INSERT INTO expense_split_members (expense_id, user_id, amount)
                        SELECT
                            expense_record.exp_id,
                            split_user_id,
                            CASE
                                WHEN expense_record.amounts_data IS NOT NULL
                                     AND expense_record.amounts_data ? split_user_id
                                THEN (expense_record.amounts_data->>split_user_id)::NUMERIC
                                ELSE NULL
                            END
                        FROM jsonb_array_elements_text(expense_record.split_data) AS split_user_id;
                    END IF;
                END LOOP;
            END IF;
        END LOOP;
    END IF;
END;
$$;

-- 6. Lock down: only the API (secret key) may read/write; the public Data API sees nothing.
ALTER TABLE users                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE accounts              ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_state             ENABLE ROW LEVEL SECURITY;
ALTER TABLE groups_table          ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_members         ENABLE ROW LEVEL SECURITY;
ALTER TABLE expenses              ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_split_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE settlements           ENABLE ROW LEVEL SECURITY;
ALTER TABLE friendships           ENABLE ROW LEVEL SECURITY;
ALTER TABLE email_verifications   ENABLE ROW LEVEL SECURITY;

REVOKE EXECUTE ON FUNCTION sync_full_database(TEXT, JSONB, JSONB, JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION sync_full_database(TEXT, JSONB, JSONB, JSONB) TO service_role;
