# Spotify-style Skip Behaviour Analysis (SQL only)

Simulated music streaming data (users, songs, sessions, play events) analyzed
entirely in SQL — no pandas, no Python analysis layer. The point of this
project was to practice window functions and self joins on something that
actually feels like a real product analytics question, instead of another
"students and courses" schema.

Questions this answers:
- Which songs get skipped the most in the first 10 seconds?
- What does a "binge listening" session look like, and which users binge the most?
- Do people jump between genres a lot within a session, or stick to one mood?
- Does binging correlate with genre hopping, or do bingers lock into one groove?

## Why I built it this way

Most beginner SQL projects are CRUD-y (insert/update/delete on a library or
student table). This one is closer to what an actual analyst would be asked —
"why are people skipping this song" or "who are our power users" — and it
forces you to actually use `LAG()`, `PARTITION BY`, CTEs, and self joins
instead of just `SELECT * FROM table WHERE`.

## Schema

```
users (user_id, username, country, signup_date)
songs (song_id, title, artist, genre, duration_seconds)
listening_sessions (session_id, user_id, session_start, device)
listening_events (event_id, session_id, song_id, position_in_session, played_at, skipped_at_second)
```

`listening_events` is the core table — one row per song played inside a
session, in order (`position_in_session`). `skipped_at_second` is NULL if the
song played through, otherwise it's the second at which the user skipped.

Roughly:
- 60 users, 220 songs across 10 genres, 350 sessions, ~2,900 play events
- ~15% of sessions are deliberately generated as "binge" sessions (18-35 songs)
- ~35% of plays get skipped, and just over half of those skips happen in the
  first 10 seconds — matches the general "people bail fast" pattern you'd
  expect from real skip data

## Files

| File | What it is |
|---|---|
| `schema.sql` | table definitions + indexes |
| `generate_data.py` | script that generated the fake data (seeded, so it's reproducible) |
| `data.sql` | the actual INSERT statements (output of the script above) |
| `queries.sql` | all the analysis queries, commented |

## How to run it

```bash
mysql -u root -e "CREATE DATABASE spotify_skip_analysis;"
mysql -u root < schema.sql
mysql -u root < data.sql
mysql -u root spotify_skip_analysis < queries.sql
```

Tested on MariaDB 10.11 and should run without changes on MySQL 8+.

If you want to regenerate the data with different numbers, just tweak the
constants at the top of `generate_data.py` (`NUM_USERS`, `NUM_SONGS`,
`NUM_SESSIONS`) and re-run `python3 generate_data.py > data.sql`.

## What the queries actually cover

**Part 1 — early skip behaviour**
Straight aggregation with `CASE WHEN` + `HAVING` to find songs (and genres)
with the highest first-10-second skip rate. Filters out songs with too few
plays so the percentage isn't misleading.

**Part 2 — binge session detection**
A CTE computes song count and session length per session, then flags
sessions as "binge" if they hit 15+ songs or run 45+ minutes. A second query
rolls that up per user to find who binges most often (as a % of their total
sessions, not raw count, so it's not just "who uses the app the most").

**Part 3 — genre switching**
Shows the same result two ways on purpose: once with a self join (join the
events table to itself on `position_in_session - 1`), then again with
`LAG() OVER (PARTITION BY session_id ORDER BY position_in_session)`. The
`LAG()` version is what you'd actually use, the self join is there to show
the same logic solved without window functions. Last query checks whether
binge sessions have a higher or lower genre-switch ratio than normal ones.

## A few findings from the generated data

- Early-skip rate varies more by song than by genre — a few specific songs
  sit at 40-55% early skip, while genre-level averages are all clustered in
  the 15-22% range. Worth remembering if you're tempted to blame "genre" for
  skip behaviour — it's mostly a per-song thing.
- Binge sessions have a noticeably higher genre-switch ratio (~0.86) than
  normal sessions (~0.67) in this dataset — so bingers aren't locking into
  one mood, they're actually jumping around more. Wasn't expecting that going
  in, honestly assumed it'd go the other way.

## Notes

- Data is synthetic (generated with `Faker` + a fixed random seed), not real
  Spotify data — this is a SQL practice project, not a data source claim.
- Kept the schema intentionally small (4 tables) — the point was to go deep
  on query technique, not build out a huge normalized catalog.
