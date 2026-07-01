-- schema.sql
-- Spotify-style listening data, made up for practicing SQL (window fns, self joins etc)
-- ran this on MySQL 8 / MariaDB 10.11, should work on both

DROP DATABASE IF EXISTS spotify_skip_analysis;
CREATE DATABASE spotify_skip_analysis;
USE spotify_skip_analysis;

-- basic user table, nothing fancy
CREATE TABLE users (
    user_id      INT AUTO_INCREMENT PRIMARY KEY,
    username     VARCHAR(50) NOT NULL,
    country      VARCHAR(50) NOT NULL,
    signup_date  DATE NOT NULL
);

-- song catalog
CREATE TABLE songs (
    song_id           INT AUTO_INCREMENT PRIMARY KEY,
    title             VARCHAR(150) NOT NULL,
    artist            VARCHAR(100) NOT NULL,
    genre             VARCHAR(50) NOT NULL,
    duration_seconds  INT NOT NULL
);

-- one row per "listening session" - basically a user opening the app and playing stuff
-- until they close it / go idle
CREATE TABLE listening_sessions (
    session_id     INT AUTO_INCREMENT PRIMARY KEY,
    user_id        INT NOT NULL,
    session_start  DATETIME NOT NULL,
    device         VARCHAR(30) NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

-- the actual play events inside a session, in order
-- skipped_at_second is NULL if the song was played till (roughly) the end
CREATE TABLE listening_events (
    event_id            INT AUTO_INCREMENT PRIMARY KEY,
    session_id          INT NOT NULL,
    song_id             INT NOT NULL,
    position_in_session INT NOT NULL,   -- 1st song played in that session, 2nd, etc
    played_at            DATETIME NOT NULL,
    skipped_at_second    INT NULL,       -- null = finished the song, otherwise skipped at Nth second
    FOREIGN KEY (session_id) REFERENCES listening_sessions(session_id),
    FOREIGN KEY (song_id) REFERENCES songs(song_id)
);

-- indexes that actually matter for the queries below
CREATE INDEX idx_events_session ON listening_events(session_id, position_in_session);
CREATE INDEX idx_events_song ON listening_events(song_id);
CREATE INDEX idx_sessions_user ON listening_sessions(user_id);
