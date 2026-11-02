-- =====================================================================
-- Day 6: Transactions — all or nothing, ACID, concurrent updates
-- Run:  psql -d <your_db> -f day-06.sql
-- Some statements FAIL ON PURPOSE (marked "error on purpose") to show
-- what Postgres does. Don't run with ON_ERROR_STOP.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Warm-up (from memory)
-- Mistakes I made: W2 again had no DESC, >= 2, missing comma (city marks),
--                  comma before FROM/WHERE, missing FROM positions.
-- Memory trick: Top = DESC. Top 2 = <= 2.
-- Habit: no comma right before FROM or WHERE.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS clubs;
DROP TABLE IF EXISTS tests;
DROP TABLE IF EXISTS students CASCADE;
CREATE TABLE students (id int PRIMARY KEY, name text, city text, marks int);
CREATE TABLE clubs (student_id int, club text);
CREATE TABLE tests (student_id int, test_date date, marks int);
INSERT INTO students VALUES
    (1, 'Ravi', 'Mumbai', 80), (2, 'Priya', 'Pune', 95), (3, 'Amit', 'Mumbai', 60),
    (4, 'Neha', 'Pune', 70), (5, 'Sara', 'Mumbai', 90);
INSERT INTO clubs VALUES (1, 'Music'), (1, 'Chess'), (2, 'Dance');
INSERT INTO tests VALUES
    (1, '2026-01-10', 60), (1, '2026-02-10', 75), (1, '2026-03-10', 70),
    (2, '2026-01-12', 90), (2, '2026-02-12', 85);

-- W1: students in no club → Amit, Neha, Sara
SELECT s.name
FROM students s
LEFT JOIN clubs c ON c.student_id = s.id
WHERE c.student_id IS NULL;

-- W2: top 2 per city → Sara, Ravi (Mumbai); Priya, Neha (Pune)
WITH positions AS (
    SELECT name, city, marks,
           ROW_NUMBER() OVER (PARTITION BY city ORDER BY marks DESC) AS position
    FROM students
)
SELECT name, city, marks
FROM positions
WHERE position <= 2;

-- W3: change from each student's previous test
SELECT student_id, test_date, marks,
       marks - LAG(marks) OVER (PARTITION BY student_id ORDER BY test_date) AS change
FROM tests;


-- ---------------------------------------------------------------------
-- Lesson 21: Transaction = all or nothing
--   BEGIN    → start a group of steps
--   COMMIT   → save all of them together
--   ROLLBACK → undo everything since BEGIN
--   Crash/error before COMMIT → Postgres discards the partial work.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS wallets;
CREATE TABLE wallets (name text PRIMARY KEY, balance int);
INSERT INTO wallets VALUES ('Ravi', 500), ('Priya', 300);

-- Transfer ₹100 Ravi → Priya, both steps or neither
BEGIN;
UPDATE wallets SET balance = balance - 100 WHERE name = 'Ravi';
UPDATE wallets SET balance = balance + 100 WHERE name = 'Priya';
COMMIT;
SELECT * FROM wallets ORDER BY name;   -- Priya 400, Ravi 400

-- ROLLBACK: cancel on purpose (e.g. your code found a problem)
BEGIN;
UPDATE wallets SET balance = balance - 1000 WHERE name = 'Ravi';
SELECT * FROM wallets WHERE name = 'Ravi';   -- -600 (only inside this transaction)
ROLLBACK;
SELECT * FROM wallets WHERE name = 'Ravi';   -- back to 400

-- Mistake I made: thought Postgres would "crash" on a negative balance.
-- It doesn't — it happily stores -600 unless YOU add a rule:
ALTER TABLE wallets ADD CONSTRAINT balance_not_negative CHECK (balance >= 0);

BEGIN;
UPDATE wallets SET balance = balance - 1000 WHERE name = 'Ravi';   -- error on purpose: violates the CHECK
UPDATE wallets SET balance = balance + 1000 WHERE name = 'Priya';  -- error: transaction is already aborted
ROLLBACK;
SELECT * FROM wallets ORDER BY name;   -- unchanged: Priya 400, Ravi 400


-- ---------------------------------------------------------------------
-- Lesson 22: ACID
--   A  Atomicity    all or nothing                     (the ROLLBACK above)
--   C  Consistency  constraints always hold            (the CHECK above)
--   I  Isolation    others don't see uncommitted work  (Days 7–8)
--   D  Durability   committed data survives a crash    (Postgres writes the WAL
--                                                        to disk before COMMIT returns)
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- Lesson 23: The lost update
--   Two transactions READ the same value, compute in app code, WRITE back.
--   The second write overwrites the first.
--
--   I tested it: Ravi 500, phone pays 100, laptop pays 200 at the same time.
--     phone reads 500 → laptop reads 500 → phone writes 400 → laptop writes 300
--   Final 300 instead of 200. The phone's payment was lost.
--
--   To see it yourself, open TWO psql terminals and run in this order:
--     T1: BEGIN; SELECT balance FROM wallets WHERE name = 'Ravi';   -- 500
--     T2: BEGIN; SELECT balance FROM wallets WHERE name = 'Ravi';   -- 500
--     T1: UPDATE wallets SET balance = 400 WHERE name = 'Ravi'; COMMIT;
--     T2: UPDATE wallets SET balance = 300 WHERE name = 'Ravi'; COMMIT;
--     → 300 (wrong)
-- ---------------------------------------------------------------------
UPDATE wallets SET balance = 500 WHERE name = 'Ravi';

-- Fix 1: let the database do the math (atomic; the row is locked during
-- the update, so a second update waits and then uses the NEW value)
UPDATE wallets SET balance = balance - 100 WHERE name = 'Ravi';
UPDATE wallets SET balance = balance - 200 WHERE name = 'Ravi';
SELECT balance FROM wallets WHERE name = 'Ravi';   -- 200 ✅

-- Fix 2: read → decide → write? Lock the row while reading: FOR UPDATE.
--   Another transaction's SELECT ... FOR UPDATE on the same row WAITS
--   here until this one COMMITs, then reads the new value.
UPDATE wallets SET balance = 500 WHERE name = 'Ravi';
BEGIN;
SELECT balance FROM wallets WHERE name = 'Ravi' FOR UPDATE;   -- lock Ravi's row
-- (app code checks: balance >= 100?)
UPDATE wallets SET balance = balance - 100 WHERE name = 'Ravi';
COMMIT;                                                         -- lock released
SELECT balance FROM wallets WHERE name = 'Ravi';   -- 400


-- ---------------------------------------------------------------------
-- Seat booking: check-then-book without double booking
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS seats;
CREATE TABLE seats (id int PRIMARY KEY, booked_by text);
INSERT INTO seats VALUES (7, NULL);

-- Way 1: lock, check, book
BEGIN;
SELECT * FROM seats WHERE id = 7 FOR UPDATE;   -- person B would wait here
-- (app code: booked_by IS NULL? → book)
UPDATE seats SET booked_by = 'A' WHERE id = 7;
COMMIT;

-- Way 2: one atomic conditional update; check the row count
UPDATE seats SET booked_by = 'B' WHERE id = 7 AND booked_by IS NULL;   -- UPDATE 0 → seat taken
SELECT * FROM seats;   -- 7 | A
