-- =====================================================================
-- Day 7: Isolation levels and MVCC
-- Run:  psql -d <your_db> -f day-07.sql
-- Concurrency needs TWO sessions: the two-terminal steps are written
-- as comments. Open two psql windows and run them in the order shown.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Warm-up (from memory)
-- Logic was right this time (DESC, <= 2, FROM positions). Mistakes:
--   "marks dense_rank()" (no comma), no "AS position", "marks city" (no comma)
-- Habit: ONE COLUMN PER LINE, comma at the end of every line except the last.
-- DENSE_RANK can return more than 2 per city on ties; "exactly 2" → ROW_NUMBER.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS students CASCADE;
CREATE TABLE students (id int PRIMARY KEY, name text, city text, marks int);
INSERT INTO students VALUES
    (1, 'Ravi', 'Mumbai', 80), (2, 'Priya', 'Pune', 95), (3, 'Amit', 'Mumbai', 60),
    (4, 'Neha', 'Pune', 70), (5, 'Sara', 'Mumbai', 90);

WITH positions AS (
    SELECT name,
           city,
           marks,
           DENSE_RANK() OVER (PARTITION BY city ORDER BY marks DESC) AS position
    FROM students
)
SELECT name,
       city,
       marks
FROM positions
WHERE position <= 2;

DROP TABLE IF EXISTS wallets;
CREATE TABLE wallets (name text PRIMARY KEY, balance int CHECK (balance >= 0));
INSERT INTO wallets VALUES ('Ravi', 500), ('Priya', 400);

BEGIN;
SELECT balance FROM wallets WHERE name = 'Ravi' FOR UPDATE;
-- code checks: balance >= 100?
UPDATE wallets SET balance = balance - 100 WHERE name = 'Ravi';
COMMIT;


-- ---------------------------------------------------------------------
-- Lesson 24: What can a transaction see?
--   Dirty read          = seeing someone's UNCOMMITTED change. Never in Postgres.
--   Non-repeatable read = same row read twice in one transaction, different
--                         answers, because someone committed in between.
--
--   Read Committed (DEFAULT) = live scoreboard: each STATEMENT sees the latest
--                              committed data.
--   Repeatable Read          = photo taken when the transaction STARTED.
-- ---------------------------------------------------------------------
SHOW default_transaction_isolation;   -- read committed

UPDATE wallets SET balance = 500 WHERE name = 'Ravi';

-- Test B (tested: read 1 = 500, read 2 = 400)
--   T2: BEGIN;
--   T2: SELECT balance FROM wallets WHERE name = 'Ravi';    -- 500
--   T1: UPDATE wallets SET balance = 400 WHERE name = 'Ravi';   (auto-commits)
--   T2: SELECT balance FROM wallets WHERE name = 'Ravi';    -- 400 ⚠️
--   T2: COMMIT;
--
-- Test C (tested: read 1 = 500, read 2 = 500)
--   T2: BEGIN ISOLATION LEVEL REPEATABLE READ;
--   T2: SELECT balance FROM wallets WHERE name = 'Ravi';    -- 500
--   T1: UPDATE wallets SET balance = 400 WHERE name = 'Ravi';
--   T2: SELECT balance FROM wallets WHERE name = 'Ravi';    -- still 500 ✅
--   T2: COMMIT;

-- A consistent multi-query report:
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT SUM(balance) AS total_money FROM wallets;
SELECT name, balance FROM wallets ORDER BY name;
COMMIT;


-- ---------------------------------------------------------------------
-- Lesson 25: Repeatable Read's catch — serialization error → RETRY
--   Read Committed:  2nd updater WAITS, then uses the new value. No error.
--   Repeatable Read: 2nd updater gets an ERROR; retry the WHOLE transaction.
--
-- Test D (tested: T1 commits, T2 errors, final 400)
--   T1: BEGIN ISOLATION LEVEL REPEATABLE READ;
--   T1: SELECT balance FROM wallets WHERE name = 'Ravi';   -- 500
--   T2: BEGIN ISOLATION LEVEL REPEATABLE READ;
--   T2: SELECT balance FROM wallets WHERE name = 'Ravi';   -- 500
--   T1: UPDATE wallets SET balance = balance - 100 WHERE name = 'Ravi'; COMMIT;
--   T2: UPDATE wallets SET balance = balance - 200 WHERE name = 'Ravi';
--       ERROR:  could not serialize access due to concurrent update
--   T2: ROLLBACK;  → app retries from BEGIN → final 200
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- Lesson 26: Write skew and SERIALIZABLE
--   Rule: at least 1 doctor on call. Both check "2 on call", both leave
--   (each updates a DIFFERENT row) → 0 on call.
--   Repeatable Read: tested → 0 on call (rule broken)
--   Serializable:    tested → 2nd commit fails, 1 on call ✅
--     ERROR: could not serialize access due to read/write dependencies
--            among transactions   HINT: might succeed if retried.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS doctors;
CREATE TABLE doctors (name text PRIMARY KEY, on_call boolean);
INSERT INTO doctors VALUES ('Asha', true), ('Bala', true);

-- Each doctor runs (in their own session, at the same time):
--   BEGIN ISOLATION LEVEL SERIALIZABLE;
--   SELECT count(*) FROM doctors WHERE on_call;               -- 2 → safe?
--   UPDATE doctors SET on_call = false WHERE name = 'Asha';   -- Bala: 'Bala'
--   COMMIT;

-- Summary
--   Level            Dirty  Non-repeatable  Lost update   Write skew
--   Read Committed   no     YES             YES*          YES        (default)
--   Repeatable Read  no     no              no (retry)    YES
--   Serializable     no     no              no (retry)    no
--   * with read-then-write app code; use atomic updates or FOR UPDATE.
--
--   Loan rule "total open loans < 5 lakh": Serializable, OR stay at Read
--   Committed and lock the borrower row first (SELECT ... FOR UPDATE).


-- ---------------------------------------------------------------------
-- Lesson 27: MVCC — an UPDATE writes a NEW row version
--   Each transaction sees the versions that fit its snapshot.
--   Readers never block writers; writers never block readers.
--   Old versions = dead rows → cleaned by VACUUM (autovacuum).
-- ---------------------------------------------------------------------

-- ctid = where the row physically lives; xmin = transaction that created it.
SELECT ctid, xmin, name, balance FROM wallets WHERE name = 'Ravi';
UPDATE wallets SET balance = 450 WHERE name = 'Ravi';
-- Both change: it's a NEW version in a new place, not an overwrite.
SELECT ctid, xmin, name, balance FROM wallets WHERE name = 'Ravi';

-- Dead rows pile up with updates...
UPDATE wallets SET balance = balance;
UPDATE wallets SET balance = balance;
SELECT pg_sleep(1);   -- stats are reported after a short delay
SELECT relname, n_live_tup, n_dead_tup
FROM pg_stat_user_tables WHERE relname = 'wallets';

-- ...and VACUUM cleans them up.
VACUUM wallets;
SELECT pg_sleep(1);
SELECT relname, n_live_tup, n_dead_tup
FROM pg_stat_user_tables WHERE relname = 'wallets';
