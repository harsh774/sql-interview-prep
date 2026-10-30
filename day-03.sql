-- =====================================================================
-- Day 3: Top N per group → duplicates → FILTER → mock round
-- Run:  psql -d <your_db> -f day-03.sql
-- =====================================================================


-- ---------------------------------------------------------------------
-- Warm-up: 3rd highest marks → Amit 60 (written from scratch, first try)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS clubs;
DROP TABLE IF EXISTS students;
CREATE TABLE students (
    name  text,
    marks int
);
INSERT INTO students VALUES
    ('Priya', 95),
    ('Ravi',  80),
    ('Neha',  80),
    ('Amit',  60);

WITH positions AS (
    SELECT name, marks,
           DENSE_RANK() OVER (ORDER BY marks DESC) AS position
    FROM students
)
SELECT name, marks
FROM positions
WHERE position = 3;


-- ---------------------------------------------------------------------
-- Lesson 11: Top N per group
--   "For each city, in order of marks (highest first)"
--   → PARTITION BY city ORDER BY marks DESC
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS students;
CREATE TABLE students (
    id    int PRIMARY KEY,
    name  text,
    city  text,
    marks int
);
INSERT INTO students VALUES
    (1, 'Ravi',  'Mumbai', 80),
    (2, 'Priya', 'Pune',   95),
    (3, 'Amit',  'Mumbai', 60),
    (4, 'Neha',  'Pune',   70),
    (5, 'Sara',  'Mumbai', 90);

-- Top 2 per city → Sara, Ravi (Mumbai); Priya, Neha (Pune)
-- Mistakes I made: PARTITION BY city DESC (no ORDER BY),
--                  step 2 used marks but step 1 didn't select it,
--                  WHERE position >= 2 (should be <= 2)
WITH positions AS (
    SELECT name, city, marks,
           ROW_NUMBER() OVER (PARTITION BY city ORDER BY marks DESC) AS position
    FROM students
)
SELECT name, city, marks
FROM positions
WHERE position <= 2;

-- Top 1 per city → Sara (Mumbai), Priya (Pune)
WITH positions AS (
    SELECT name, city,
           ROW_NUMBER() OVER (PARTITION BY city ORDER BY marks DESC) AS position
    FROM students
)
SELECT name, city
FROM positions
WHERE position = 1;

-- Postgres-only shortcut for top 1 per group: DISTINCT ON
--   ORDER BY must start with the DISTINCT ON column.
--   Interview move: write ROW_NUMBER, then mention DISTINCT ON.
SELECT DISTINCT ON (city) name, city, marks
FROM students
ORDER BY city, marks DESC;


-- ---------------------------------------------------------------------
-- Lesson 12 & 13: Duplicates
--   Find   → GROUP BY + HAVING COUNT(*) > 1
--   Delete → ROW_NUMBER, delete rows numbered > 1
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS people;
CREATE TABLE people (
    id   int PRIMARY KEY,
    name text
);
INSERT INTO people VALUES
    (1, 'Ravi'), (2, 'Priya'), (3, 'Ravi'), (4, 'Amit'), (5, 'Ravi');

-- Find duplicates → Ravi 3
SELECT name, COUNT(*)
FROM people
GROUP BY name
HAVING COUNT(*) > 1;

-- Safe habit: SELECT first to see what would be deleted → ids 3, 5
WITH numbered AS (
    SELECT id,
           ROW_NUMBER() OVER (PARTITION BY name ORDER BY id) AS copy_no
    FROM people
)
SELECT id
FROM numbered
WHERE copy_no > 1;

-- Then delete, keeping the oldest copy (smallest id)
WITH numbered AS (
    SELECT id,
           ROW_NUMBER() OVER (PARTITION BY name ORDER BY id) AS copy_no
    FROM people
)
DELETE FROM people
WHERE id IN (SELECT id FROM numbered WHERE copy_no > 1);

-- → 1 Ravi, 2 Priya, 4 Amit
SELECT * FROM people ORDER BY id;


-- ---------------------------------------------------------------------
-- Lesson 14: FILTER = count only some rows inside each pile (Postgres)
--   FILTER  → counts some rows INSIDE a pile
--   HAVING  → keeps or removes WHOLE piles
-- ---------------------------------------------------------------------

-- Whole table: 75+ vs below 75 → 3, 2
SELECT COUNT(*) FILTER (WHERE marks >= 75) AS high,
       COUNT(*) FILTER (WHERE marks < 75)  AS low
FROM students;

-- Per city: all students and how many scored 75+
-- → Mumbai 3 / 2, Pune 2 / 1
-- Mistake I made: GROUP BY city without selecting city
SELECT city,
       COUNT(*) AS total_students,
       COUNT(*) FILTER (WHERE marks >= 75) AS high_scorers
FROM students
GROUP BY city;

-- Same thing the non-Postgres way
SELECT city,
       COUNT(*) AS total_students,
       SUM(CASE WHEN marks >= 75 THEN 1 ELSE 0 END) AS high_scorers
FROM students
GROUP BY city;


-- ---------------------------------------------------------------------
-- Mock round (tables: students + clubs)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS clubs;
CREATE TABLE clubs (
    student_id int,
    club       text
);
INSERT INTO clubs VALUES
    (1, 'Music'), (1, 'Chess'), (2, 'Dance'), (5, 'Music');

-- Q1: cities with average marks above 75 → Mumbai 76.67 (3), Pune 82.50 (2)
-- Mistake I made: FILTER (WHERE avg_marks > 75). Whole piles → HAVING.
SELECT city,
       ROUND(AVG(marks), 2) AS avg_marks,
       COUNT(*) AS total_students
FROM students
GROUP BY city
HAVING AVG(marks) > 75;

-- Q2: students in more than one club → Ravi 2
--   JOIN first (one row per membership), then pile per student, then HAVING.
SELECT s.name, COUNT(*) AS club_count
FROM students s
JOIN clubs c ON c.student_id = s.id
GROUP BY s.id, s.name
HAVING COUNT(*) > 1;

-- Q3: 2nd highest marks in each city → Mumbai Ravi 80, Pune Neha 70 (correct first try)
WITH positions AS (
    SELECT city, name, marks,
           DENSE_RANK() OVER (PARTITION BY city ORDER BY marks DESC) AS position
    FROM students
)
SELECT city, name, marks
FROM positions
WHERE position = 2;

-- Retry: club memberships per city → Mumbai 3, Pune 1
--   The "per" rule: whatever follows "per" / "each" goes in GROUP BY.
-- Mistake I made: GROUP BY s.id, s.city (that's per student, not per city)
SELECT s.city, COUNT(*) AS memberships
FROM students s
JOIN clubs c ON s.id = c.student_id
GROUP BY s.city;
