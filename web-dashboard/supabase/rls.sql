-- ============================================================
-- StreamDeck Row Level Security Policies
-- Run after schema.sql in Supabase SQL Editor
--
-- Pattern: each user can only CRUD their own data.
-- Uses (SELECT auth.uid()) subselect for performance (evaluates once).
-- ============================================================

-- Enable RLS on all tables
ALTER TABLE playlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE vod_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE watch_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- playlists
-- ============================================================
CREATE POLICY "playlists_select" ON playlists FOR SELECT
    TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY "playlists_insert" ON playlists FOR INSERT
    TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY "playlists_update" ON playlists FOR UPDATE
    TO authenticated USING ((SELECT auth.uid()) = user_id)
    WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY "playlists_delete" ON playlists FOR DELETE
    TO authenticated USING ((SELECT auth.uid()) = user_id);

-- ============================================================
-- channels
-- ============================================================
CREATE POLICY "channels_select" ON channels FOR SELECT
    TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY "channels_insert" ON channels FOR INSERT
    TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY "channels_update" ON channels FOR UPDATE
    TO authenticated USING ((SELECT auth.uid()) = user_id)
    WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY "channels_delete" ON channels FOR DELETE
    TO authenticated USING ((SELECT auth.uid()) = user_id);

-- ============================================================
-- vod_items
-- ============================================================
CREATE POLICY "vod_items_select" ON vod_items FOR SELECT
    TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY "vod_items_insert" ON vod_items FOR INSERT
    TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY "vod_items_update" ON vod_items FOR UPDATE
    TO authenticated USING ((SELECT auth.uid()) = user_id)
    WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY "vod_items_delete" ON vod_items FOR DELETE
    TO authenticated USING ((SELECT auth.uid()) = user_id);

-- ============================================================
-- watch_progress
-- ============================================================
CREATE POLICY "watch_progress_select" ON watch_progress FOR SELECT
    TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY "watch_progress_insert" ON watch_progress FOR INSERT
    TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY "watch_progress_update" ON watch_progress FOR UPDATE
    TO authenticated USING ((SELECT auth.uid()) = user_id)
    WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY "watch_progress_delete" ON watch_progress FOR DELETE
    TO authenticated USING ((SELECT auth.uid()) = user_id);

-- ============================================================
-- user_preferences
-- ============================================================
CREATE POLICY "user_preferences_select" ON user_preferences FOR SELECT
    TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY "user_preferences_insert" ON user_preferences FOR INSERT
    TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY "user_preferences_update" ON user_preferences FOR UPDATE
    TO authenticated USING ((SELECT auth.uid()) = user_id)
    WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY "user_preferences_delete" ON user_preferences FOR DELETE
    TO authenticated USING ((SELECT auth.uid()) = user_id);
