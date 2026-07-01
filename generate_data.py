"""
generate_data.py

Quick script to spit out fake listening data for the skip-behaviour project.
Not meant to be "production" code, just needed enough realistic rows to make
the SQL queries actually interesting (binge sessions, early skips, genre
hopping etc). Run once, commit the resulting data.sql, done.

Usage: python3 generate_data.py > data.sql
"""

import random
from datetime import datetime, timedelta
from faker import Faker

fake = Faker()
random.seed(42)  # keeping this fixed so results are reproducible while I write the queries

NUM_USERS = 60
NUM_SONGS = 220
NUM_SESSIONS = 350

COUNTRIES = ["India", "USA", "UK", "Canada", "Germany", "Australia", "Brazil"]
DEVICES = ["mobile", "desktop", "tablet", "smart_speaker"]

GENRES = ["Pop", "Rock", "Hip-Hop", "EDM", "Classical", "Jazz", "Indie", "R&B", "Metal", "Lo-fi"]

# a handful of made-up artist names per genre, easier than pure random gibberish
ARTIST_POOL = {
    "Pop": ["Nova Reyes", "The Skyline", "Mira Quinn", "Echo Bloom"],
    "Rock": ["Iron Tide", "The Wreckage", "Static Coast", "Velvet Fault"],
    "Hip-Hop": ["Lyric Genesis", "MC Vantage", "Kid Cipher", "North Bound"],
    "EDM": ["Pulse Theory", "Neon Drift", "Voltage Kid", "Circuit Bloom"],
    "Classical": ["Orchestra Lumen", "Solace Ensemble", "The Quiet Strings"],
    "Jazz": ["Blue Alley Trio", "The Midnight Horns", "Sable & Sax"],
    "Indie": ["Paper Moths", "Hollow Pines", "Faded Radio"],
    "R&B": ["Velvet Hour", "Silk Static", "Aria Monroe"],
    "Metal": ["Ashfall", "Grim Circuit", "The Iron Choir"],
    "Lo-fi": ["Rainy Desk", "Study Static", "Slow Tape Club"],
}


def esc(s):
    """escape single quotes for sql strings, real basic"""
    return str(s).replace("'", "''")


def gen_users():
    rows = []
    for uid in range(1, NUM_USERS + 1):
        username = fake.user_name()
        country = random.choice(COUNTRIES)
        signup = fake.date_between(start_date="-2y", end_date="-30d")
        rows.append(f"({uid}, '{esc(username)}', '{country}', '{signup}')")
    return rows


def gen_songs():
    rows = []
    sid = 1
    for _ in range(NUM_SONGS):
        genre = random.choice(GENRES)
        artist = random.choice(ARTIST_POOL[genre])
        # song titles - just mash a couple of fake words together, sounds song-ish enough
        title = fake.catch_phrase().title()
        duration = random.randint(150, 300)  # 2:30 to 5:00 roughly
        rows.append(f"({sid}, '{esc(title)}', '{esc(artist)}', '{genre}', {duration})")
        sid += 1
    return rows


def gen_sessions_and_events(song_durations):
    session_rows = []
    event_rows = []
    session_id = 1
    event_id = 1

    for _ in range(NUM_SESSIONS):
        user_id = random.randint(1, NUM_USERS)
        device = random.choice(DEVICES)
        start_time = fake.date_time_between(start_date="-6M", end_date="now")

        # ~15% of sessions are "binge" sessions - a lot more songs played back to back
        is_binge = random.random() < 0.15
        num_songs_in_session = random.randint(18, 35) if is_binge else random.randint(2, 8)

        session_rows.append(
            f"({session_id}, {user_id}, '{start_time.strftime('%Y-%m-%d %H:%M:%S')}', '{device}')"
        )

        current_time = start_time
        # every so often (roughly every 4-6 songs) the "session" drifts to a new genre bucket
        # to simulate someone switching moods / playlists mid session
        for pos in range(1, num_songs_in_session + 1):
            song_id = random.randint(1, NUM_SONGS)
            duration = song_durations[song_id]

            # skip bias: about 35% chance of skipping, and when skipping, a good chunk
            # happen in the first 10 seconds (people bail fast on stuff they don't like)
            skipped_at = None
            if random.random() < 0.35:
                if random.random() < 0.55:
                    skipped_at = random.randint(1, 10)
                else:
                    skipped_at = random.randint(11, max(11, duration - 5))

            event_rows.append(
                f"({event_id}, {session_id}, {song_id}, {pos}, "
                f"'{current_time.strftime('%Y-%m-%d %H:%M:%S')}', "
                f"{skipped_at if skipped_at is not None else 'NULL'})"
            )

            # move the clock forward - either the full song or up to the skip point
            played_for = skipped_at if skipped_at else duration
            current_time += timedelta(seconds=played_for + random.randint(1, 4))
            event_id += 1

        session_id += 1

    return session_rows, event_rows


def main():
    print("-- data.sql")
    print("-- auto generated with generate_data.py, seed=42 so it's reproducible")
    print("USE spotify_skip_analysis;\n")

    print("-- ~~~ users ~~~")
    user_rows = gen_users()
    print("INSERT INTO users (user_id, username, country, signup_date) VALUES")
    print(",\n".join(user_rows) + ";\n")

    print("-- ~~~ songs ~~~")
    song_rows = gen_songs()
    print("INSERT INTO songs (song_id, title, artist, genre, duration_seconds) VALUES")
    print(",\n".join(song_rows) + ";\n")

    # need durations mapped back for the session/event generator
    song_durations = {}
    for row in song_rows:
        # crude parse, fine since we built these strings ourselves above
        parts = row.strip("()").split(", ")
        sid = int(parts[0])
        dur = int(parts[-1])
        song_durations[sid] = dur

    print("-- ~~~ sessions + events ~~~")
    session_rows, event_rows = gen_sessions_and_events(song_durations)

    print("INSERT INTO listening_sessions (session_id, user_id, session_start, device) VALUES")
    print(",\n".join(session_rows) + ";\n")

    # events table is big, batch the inserts so it's not one giant statement
    BATCH = 400
    print(f"-- {len(event_rows)} events total, inserting in batches of {BATCH}")
    for i in range(0, len(event_rows), BATCH):
        chunk = event_rows[i:i + BATCH]
        print(
            "INSERT INTO listening_events "
            "(event_id, session_id, song_id, position_in_session, played_at, skipped_at_second) VALUES"
        )
        print(",\n".join(chunk) + ";\n")


if __name__ == "__main__":
    main()
