-- ============================================================
-- StreamDeck Triggers
-- Run after schema.sql in Supabase SQL Editor
-- ============================================================

-- Auto-update updated_at on every UPDATE
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER playlists_updated_at BEFORE UPDATE ON playlists
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER channels_updated_at BEFORE UPDATE ON channels
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER vod_items_updated_at BEFORE UPDATE ON vod_items
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER watch_progress_updated_at BEFORE UPDATE ON watch_progress
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER user_preferences_updated_at BEFORE UPDATE ON user_preferences
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- PowerSync publication
-- Required for PowerSync to replicate changes from Postgres
-- ============================================================
CREATE PUBLICATION powersync FOR TABLE
    playlists, channels, vod_items, watch_progress, user_preferences;

-- ============================================================
-- Auto-create user_preferences row on signup
-- Ensures every user has a preferences row from the start
-- ============================================================
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.user_preferences (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION handle_new_user();
