-- queries.sql
-- Skip behaviour analysis - Spotify style listening data
-- All of this is plain SQL (window functions + self joins), no python/pandas involved
-- Tested on MariaDB 10.11 / should run fine on MySQL 8+

USE spotify_skip_analysis;


-- ===========================================================
-- PART 1: Songs people skip the most in the first 10 seconds
-- ===========================================================

-- basic version - just raw skip counts per song
SELECT
    s.song_id,
    s.title,
    s.artist,
    s.genre,
    COUNT(*) AS times_played,
    SUM(CASE WHEN le.skipped_at_second IS NOT NULL AND le.skipped_at_second <= 10 THEN 1 ELSE 0 END) AS early_skips,
    ROUND(
        SUM(CASE WHEN le.skipped_at_second IS NOT NULL AND le.skipped_at_second <= 10 THEN 1 ELSE 0 END)
        / COUNT(*) * 100, 1
    ) AS early_skip_rate_pct
FROM listening_events le
JOIN songs s ON s.song_id = le.song_id
GROUP BY s.song_id, s.title, s.artist, s.genre
HAVING COUNT(*) >= 5   -- ignore songs that barely got played, rate would be misleading
ORDER BY early_skip_rate_pct DESC, times_played DESC
LIMIT 20;


-- same thing but broken down by genre, so we can see if certain genres
-- just get skipped fast in general (looking at you, random shuffle intros)
SELECT
    s.genre,
    COUNT(*) AS total_plays,
    SUM(CASE WHEN le.skipped_at_second IS NOT NULL AND le.skipped_at_second <= 10 THEN 1 ELSE 0 END) AS early_skips,
    ROUND(
        SUM(CASE WHEN le.skipped_at_second IS NOT NULL AND le.skipped_at_second <= 10 THEN 1 ELSE 0 END)
        / COUNT(*) * 100, 1
    ) AS early_skip_rate_pct
FROM listening_events le
JOIN songs s ON s.song_id = le.song_id
GROUP BY s.genre
ORDER BY early_skip_rate_pct DESC;


-- ===========================================================
-- PART 2: Binge-listening session detection
-- ===========================================================

-- a session counts as "binge" if it has 15+ songs played OR runs for 45+ minutes.
-- using window functions to get session length + song count in one pass instead
-- of a second aggregation query
WITH session_stats AS (
    SELECT
        le.session_id,
        ls.user_id,
        COUNT(*) AS songs_played,
        MIN(le.played_at) AS session_first_play,
        MAX(le.played_at) AS session_last_play,
        TIMESTAMPDIFF(MINUTE, MIN(le.played_at), MAX(le.played_at)) AS session_length_minutes
    FROM listening_events le
    JOIN listening_sessions ls ON ls.session_id = le.session_id
    GROUP BY le.session_id, ls.user_id
)
SELECT
    session_id,
    user_id,
    songs_played,
    session_length_minutes,
    CASE
        WHEN songs_played >= 15 OR session_length_minutes >= 45 THEN 'binge'
        ELSE 'normal'
    END AS session_type
FROM session_stats
ORDER BY songs_played DESC
LIMIT 25;


-- which users binge the most often? (as a % of their total sessions)
WITH session_stats AS (
    SELECT
        le.session_id,
        ls.user_id,
        COUNT(*) AS songs_played,
        TIMESTAMPDIFF(MINUTE, MIN(le.played_at), MAX(le.played_at)) AS session_length_minutes
    FROM listening_events le
    JOIN listening_sessions ls ON ls.session_id = le.session_id
    GROUP BY le.session_id, ls.user_id
),
flagged AS (
    SELECT
        user_id,
        session_id,
        CASE WHEN songs_played >= 15 OR session_length_minutes >= 45 THEN 1 ELSE 0 END AS is_binge
    FROM session_stats
)
SELECT
    u.user_id,
    u.username,
    COUNT(*) AS total_sessions,
    SUM(f.is_binge) AS binge_sessions,
    ROUND(SUM(f.is_binge) / COUNT(*) * 100, 1) AS binge_rate_pct
FROM flagged f
JOIN users u ON u.user_id = f.user_id
GROUP BY u.user_id, u.username
HAVING COUNT(*) >= 3  -- need a decent sample size before calling someone a "binger"
ORDER BY binge_rate_pct DESC
LIMIT 15;


-- ===========================================================
-- PART 3: Genre switching within a session (self join + LAG)
-- ===========================================================

-- for every consecutive pair of songs in a session, check if the genre changed.
-- self join version first (join events table to itself on position_in_session - 1)
SELECT
    curr.session_id,
    curr.position_in_session,
    prev_song.genre AS previous_genre,
    curr_song.genre AS current_genre,
    CASE WHEN prev_song.genre != curr_song.genre THEN 1 ELSE 0 END AS genre_switched
FROM listening_events curr
JOIN listening_events prev
    ON prev.session_id = curr.session_id
    AND prev.position_in_session = curr.position_in_session - 1
JOIN songs curr_song ON curr_song.song_id = curr.song_id
JOIN songs prev_song ON prev_song.song_id = prev.song_id
ORDER BY curr.session_id, curr.position_in_session
LIMIT 30;


-- same idea but with LAG() instead of the self join - way cleaner, and this is
-- basically what I'd actually use in a real analysis
SELECT
    session_id,
    position_in_session,
    genre,
    LAG(genre) OVER (PARTITION BY session_id ORDER BY position_in_session) AS previous_genre,
    CASE
        WHEN genre != LAG(genre) OVER (PARTITION BY session_id ORDER BY position_in_session) THEN 1
        ELSE 0
    END AS genre_switched
FROM (
    SELECT le.session_id, le.position_in_session, s.genre
    FROM listening_events le
    JOIN songs s ON s.song_id = le.song_id
) t
ORDER BY session_id, position_in_session
LIMIT 30;


-- rolling that up: how many genre switches per session, and switches per song
-- (higher number = person is jumping around moods/playlists a lot in that session)
WITH events_with_genre AS (
    SELECT le.session_id, le.position_in_session, s.genre
    FROM listening_events le
    JOIN songs s ON s.song_id = le.song_id
),
switches AS (
    SELECT
        session_id,
        CASE
            WHEN genre != LAG(genre) OVER (PARTITION BY session_id ORDER BY position_in_session) THEN 1
            ELSE 0
        END AS switched
    FROM events_with_genre
)
SELECT
    session_id,
    COUNT(*) AS total_songs,
    SUM(switched) AS genre_switches,
    ROUND(SUM(switched) / COUNT(*), 2) AS switch_ratio
FROM switches
GROUP BY session_id
HAVING COUNT(*) >= 5
ORDER BY switch_ratio DESC
LIMIT 20;


-- bonus: does genre-hopping correlate with binging? do people who binge also
-- jump genres a lot, or do they lock into one genre and just play it for hours?
WITH events_with_genre AS (
    SELECT le.session_id, le.position_in_session, s.genre
    FROM listening_events le
    JOIN songs s ON s.song_id = le.song_id
),
switches AS (
    SELECT
        session_id,
        CASE
            WHEN genre != LAG(genre) OVER (PARTITION BY session_id ORDER BY position_in_session) THEN 1
            ELSE 0
        END AS switched
    FROM events_with_genre
),
session_summary AS (
    SELECT
        session_id,
        COUNT(*) AS total_songs,
        SUM(switched) AS genre_switches
    FROM switches
    GROUP BY session_id
)
SELECT
    CASE WHEN total_songs >= 15 THEN 'binge session' ELSE 'normal session' END AS session_bucket,
    COUNT(*) AS num_sessions,
    ROUND(AVG(genre_switches / total_songs), 2) AS avg_switch_ratio
FROM session_summary
GROUP BY session_bucket;
