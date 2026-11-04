-- =====================================================================
-- Day 8: Deadlocks, SKIP LOCKED job queues, optimistic locking
--        + test on Days 6–8
-- Run:  psql -d <your_db> -f day-08.sql
-- Concurrency needs TWO sessions: the two-terminal steps are written
-- as comments. Open two psql windows and run them in the order shown.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Warm-up (from memory)
-- Q1 top 2 per city: fully correct (commas, DESC, <= 2, AS position,
--    FROM positions). First clean one!
-- Q2 FOR UPDATE wallet: logic right.
--   Mistake I made: no ";" after BEGIN and the SELECT, and NO COMMIT.
--   Without COMMIT the change is never saved and the row stays LOCKED,
--   so everyone else waiting on Ravi's row keeps waiting.
--   BEGIN opens the lock; COMMIT / ROLLBACK releases it.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS students CASCADE;
CREATE TABLE students (id int PRIMARY KEY, name text, city text, marks int);
INSERT INTO students VALUES
    (1, 'Ravi', 'Mumbai', 80), (2, 'Priya', 'Pune', 95), (3, 'Amit', 'Mumbai', 60),
    (4, 'Neha', 'Pune', 70), (5, 'Sara', 'Mumbai', 90);

-- Expected: Sara 90, Ravi 80 (Mumbai); Priya 95, Neha 70 (Pune)
WITH positions AS (
    SELECT name,
           city,
           marks,
           ROW_NUMBER() OVER (PARTITION BY city ORDER BY marks DESC) AS position
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
-- code checks: balance >= 100? (if not: ROLLBACK;)
UPDATE wallets SET balance = balance - 100 WHERE name = 'Ravi';
COMMIT;                                   -- <-- don't forget this


-- ---------------------------------------------------------------------
-- Lesson 28: Deadlocks
--   Two bathrooms, one key each. A holds key 1 and wants key 2;
--   B holds key 2 and wants key 1 → both wait forever = DEADLOCK.
--   Postgres checks after deadlock_timeout (1 s by default) and cancels
--   ONE of them ("deadlock detected"); its whole transaction is rolled
--   back, and the other one carries on.
--   Mistake I made: thought Postgres cancels BOTH. It cancels one victim.
-- ---------------------------------------------------------------------
UPDATE students SET marks = 80 WHERE id = 1;
UPDATE students SET marks = 95 WHERE id = 2;
SHOW deadlock_timeout;   -- 1s

-- Test A (tested on PG 16: T1 killed, T2 committed, final Ravi 75, Priya 90)
--   T1: BEGIN;
--   T1: UPDATE students SET marks = marks + 5 WHERE id = 1;   -- locks row 1
--   T2: BEGIN;
--   T2: UPDATE students SET marks = marks - 5 WHERE id = 2;   -- locks row 2
--   T1: UPDATE students SET marks = marks + 5 WHERE id = 2;   -- waits for T2
--   T2: UPDATE students SET marks = marks - 5 WHERE id = 1;   -- waits for T1
--   ~1 s later, T1:
--     ERROR:  deadlock detected
--     DETAIL: Process A waits for ShareLock on transaction X; blocked by process B.
--             Process B waits for ShareLock on transaction Y; blocked by process A.
--   T2: COMMIT;   -- succeeds
--
-- Fixes:
--   1. Always lock rows in the SAME order (lowest id first).
--      The second transaction then waits at row 1 while holding NOTHING,
--      so there's no circle of waiting.
--      Mistake I made: said "no deadlock because they're individual
--      transactions". Real reason: whoever gets row 1 first wins; the other
--      waits before holding any lock.
--   2. Keep transactions short.
--   3. Catch "deadlock detected" and RETRY the whole transaction.

-- Lock both rows, lowest id first, in one statement:
BEGIN;
SELECT * FROM students
WHERE id IN (1, 2)
ORDER BY id
FOR UPDATE;
UPDATE students SET marks = marks + 5 WHERE id = 1;
UPDATE students SET marks = marks - 5 WHERE id = 2;
COMMIT;
-- Mistake I made: wrote only ORDER BY. FOR UPDATE is what takes the locks;
-- without it this is a normal read that locks nothing.


-- ---------------------------------------------------------------------
-- Lesson 29: Job queues with FOR UPDATE SKIP LOCKED
--   Plain FOR UPDATE: busy row → WAIT.
--   SKIP LOCKED:      busy row → skip it, take the next free one.
--   (Bakery: first counter busy → go to the next free counter.)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS jobs;
CREATE TABLE jobs (id int PRIMARY KEY, status text);
INSERT INTO jobs SELECT g, 'pending' FROM generate_series(1, 4) g;

-- Tested on PG 16 with 4 sessions at once:
--   Worker A  FOR UPDATE SKIP LOCKED → job 1, no wait
--   Worker B  FOR UPDATE SKIP LOCKED → job 2, no wait
--   Worker C  FOR UPDATE SKIP LOCKED → job 3, no wait
--   Worker D  plain FOR UPDATE       → job 1, WAITED ~2.5 s for A's COMMIT

-- One worker's loop:
BEGIN;
SELECT id FROM jobs
WHERE status = 'pending'
ORDER BY id
LIMIT 1
FOR UPDATE SKIP LOCKED;                  -- expected: 1
-- app does the work (send the email...)
UPDATE jobs SET status = 'done' WHERE id = 1;
COMMIT;
-- Worker crashes before COMMIT → rollback → job is 'pending' and unlocked
-- again → another worker picks it up. Nothing lost.

-- When to use which:
--   ANY free row will do (job queue, coupon codes) → FOR UPDATE SKIP LOCKED
--   ONE SPECIFIC row (Ravi's wallet, seat 7)       → plain FOR UPDATE (wait)
-- Mistake I made: said yes to SKIP LOCKED for the wallet. If Ravi's row is
-- locked it returns 0 rows, and the code thinks there's no wallet / skips
-- the withdrawal.
SELECT balance FROM wallets WHERE name = 'Ravi' FOR UPDATE SKIP LOCKED;
-- (here: 400; if another session held the lock: 0 rows)


-- ---------------------------------------------------------------------
-- Lesson 30: Optimistic locking (version column)
--   Pessimistic = lock first, others WAIT (FOR UPDATE).
--   Optimistic  = no lock; at SAVE time check nobody changed it since you read.
--   UPDATE ... WHERE id = ? AND version = ?   then check the row count:
--     UPDATE 1 → saved          UPDATE 0 → someone else changed it → reload/retry
--   Postgres does NOT throw an error on UPDATE 0. YOUR CODE must check it.
--   Mistake I made: said Bala's UPDATE would "throw an error".
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS products;
CREATE TABLE products (id int PRIMARY KEY, name text, price int, version int NOT NULL DEFAULT 1);
INSERT INTO products VALUES (1, 'Pen', 10, 3);

-- Asha and Bala both read the Pen at version 3.
SELECT id, price, version FROM products WHERE id = 1;   -- 10, version 3

-- Asha saves first → UPDATE 1, version becomes 4
UPDATE products
SET price = 12,
    version = version + 1
WHERE id = 1
  AND version = 3
RETURNING price, version;                               -- 12, 4

-- Bala saves with the version he read → UPDATE 0 (no error!)
UPDATE products
SET price = 15,
    version = version + 1
WHERE id = 1
  AND version = 3
RETURNING price, version;                               -- (0 rows)

SELECT id, price, version FROM products WHERE id = 1;   -- 12, 4 (Asha's)

--                 Pessimistic (FOR UPDATE)        Optimistic (version)
--   On a clash    others WAIT                     loser gets 0 rows → retry
--   Best when     clashes common, short work      clashes rare, or long gap
--                 inside one transaction          between read and save
--   Example       wallet, hot stock count         admin "Edit product" form
--   Never hold FOR UPDATE while a user is looking at a form.


-- ---------------------------------------------------------------------
-- Test on Days 6–8
-- Part 1 MCQs: 5/10 first try, 5/5 on the reworded retake.
--   Missed: crash before COMMIT saves NOTHING; write skew → SERIALIZABLE
--   (not Repeatable Read); MVCC UPDATE = new row version + dead row;
--   deadlock fix = same lock order (not SKIP LOCKED); workers → SKIP LOCKED
--   (not version column).
--
--   Problem                               Fix
--   Lost update (same row, read → write)  SET x = x - 100, or FOR UPDATE
--   Write skew (different rows)           SERIALIZABLE
--   Deadlock                              lock in the same order + retry
--   Workers waiting on each other         FOR UPDATE SKIP LOCKED
--   User edits a form for a long time     version column (optimistic)
--
-- Part 2 scenario: 1.5/5. Tested on PG 16 — T1 sees 500, T2 WAITS 1.5 s,
--   then sees 400, final 200. No deadlock, no lost update.
--   Mistake I made: said T2's SELECT ... FOR UPDATE returns immediately with
--   500 (photo) and the final is 300 (lost update).
--     Plain SELECT            → never waits (MVCC)
--     SELECT ... FOR UPDATE   → WAITS for the lock holder to COMMIT
--     Read Committed          → live scoreboard: after waiting, sees 400
--     FOR UPDATE is the FIX for lost update, not the cause.
-- ---------------------------------------------------------------------
UPDATE wallets SET balance = 500 WHERE name = 'Ravi';
--   T1: BEGIN;
--   T1: SELECT balance FROM wallets WHERE name = 'Ravi' FOR UPDATE;   -- 500
--   T2: BEGIN;
--   T2: SELECT balance FROM wallets WHERE name = 'Ravi' FOR UPDATE;   -- WAITS
--   T1: UPDATE wallets SET balance = balance - 100 WHERE name = 'Ravi';
--   T1: COMMIT;                     -- T2 unblocks and sees 400
--   T2: UPDATE wallets SET balance = balance - 200 WHERE name = 'Ravi';
--   T2: COMMIT;                     -- final 200

-- Part 3 theory: 3/5. Model answers:
--   ACID: Atomicity = all or nothing. Consistency = constraints always hold.
--     Isolation = others don't see your uncommitted changes. Durability =
--     committed data survives crashes (WAL written to disk before COMMIT returns).
--     Mistake I made: Atomicity = "runs on its own" (that's Isolation);
--     forgot I and D.
--   Default level: Read Committed. Can go wrong: non-repeatable reads, lost
--     update with read-then-write code, write skew.
--   Lost update: atomic SET balance = balance - 100, or SELECT ... FOR UPDATE.
--     (Repeatable Read also works: 2nd writer gets an error → retry.)
--     Mistake I made: "Repeatable Read will read the data again" — it errors.
--   Deadlock: two transactions each hold a lock the other needs. Postgres
--     kills one after ~1 s. Avoid: lock rows in the same order, short
--     transactions, retry on "deadlock detected".
--     Mistake I made: "process them one by one" — they still run at the
--     same time; only the LOCK ORDER is the same.
--   Pessimistic vs optimistic: FOR UPDATE for short, high-contention work
--     (wallet); version column when clashes are rare or read and save are
--     far apart (forms); 0 rows → reload and retry.
-- ---------------------------------------------------------------------
