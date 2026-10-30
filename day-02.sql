-- =====================================================================
-- Day 2: Ties & Nth highest → JOINs → NULL rules
-- Run:  psql -d <your_db> -f day-02.sql
-- =====================================================================


-- ---------------------------------------------------------------------
-- Warm-up: Day 1 final challenge, from scratch
--   Step 1 = piles:  SELECT who, when, SUM(...) FROM table GROUP BY who, when
--   Step 2 = LAG:    OVER (PARTITION BY who ORDER BY when)
--   GROUP BY = make piles, ORDER BY = sort only.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS steps;
CREATE TABLE steps (
    person    text,
    walked_on date,
    steps     int
);
INSERT INTO steps VALUES
    ('Ravi',  '2026-01-03', 5000),
    ('Ravi',  '2026-02-08', 6000),
    ('Priya', '2026-01-10', 8000),
    ('Priya', '2026-02-12', 4000);

WITH monthly AS (
    SELECT person,
           date_trunc('month', walked_on) AS month,
           SUM(steps) AS total_steps
    FROM steps
    GROUP BY person, date_trunc('month', walked_on)
)
SELECT person, month, total_steps,
       total_steps - LAG(total_steps) OVER (PARTITION BY person ORDER BY month) AS change
FROM monthly
ORDER BY person, month;


-- ---------------------------------------------------------------------
-- Lesson 8: Ties — ROW_NUMBER vs RANK vs DENSE_RANK
--   ROW_NUMBER: never shares (1,2,3,4)
--   RANK:       ties share, then skips (1,2,2,4)
--   DENSE_RANK: ties share, no skipping (1,2,2,3)  ← use for "Nth highest"
-- ---------------------------------------------------------------------
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

SELECT name, marks,
       ROW_NUMBER() OVER (ORDER BY marks DESC) AS row_number,
       RANK()       OVER (ORDER BY marks DESC) AS rank,
       DENSE_RANK() OVER (ORDER BY marks DESC) AS dense_rank
FROM students;

-- 2nd highest marks → Ravi 80, Neha 80
-- Mistake I made: WHERE marks > 80 (hard-coded, and before FROM). Filter on position.
WITH positions AS (
    SELECT name, marks,
           DENSE_RANK() OVER (ORDER BY marks DESC) AS position
    FROM students
)
SELECT name, marks
FROM positions
WHERE position = 2;

-- 3rd highest marks → Amit 60 (only the number changes)
WITH positions AS (
    SELECT name, marks,
           DENSE_RANK() OVER (ORDER BY marks DESC) AS position
    FROM students
)
SELECT name, marks
FROM positions
WHERE position = 3;


-- ---------------------------------------------------------------------
-- Lesson 9: JOINs
--   INNER JOIN = only matches.  LEFT JOIN = keep every left row (NULL if no match).
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS clubs;
DROP TABLE IF EXISTS students;
CREATE TABLE students (
    id   int PRIMARY KEY,
    name text
);
CREATE TABLE clubs (
    student_id int,
    club       text
);
INSERT INTO students VALUES (1, 'Ravi'), (2, 'Priya'), (3, 'Amit');
INSERT INTO clubs VALUES (1, 'Music'), (1, 'Chess'), (2, 'Dance');

-- INNER JOIN → Amit disappears
SELECT s.name, c.club
FROM students s
INNER JOIN clubs c ON c.student_id = s.id;

-- LEFT JOIN → Amit stays, club is NULL
SELECT s.name, c.club
FROM students s
LEFT JOIN clubs c ON c.student_id = s.id;

-- Anti-join: students in NO club → Amit
-- Mistake I made: AND club IS NOT NULL inside ON. Filter with WHERE ... IS NULL.
SELECT s.name
FROM students s
LEFT JOIN clubs c ON c.student_id = s.id
WHERE c.club IS NULL;

-- Students in at least one club, each once → Ravi, Priya
-- Mistake I made: used s.name without declaring the nickname (FROM students s)
SELECT DISTINCT s.name
FROM students s
INNER JOIN clubs c ON c.student_id = s.id;


-- ---------------------------------------------------------------------
-- Lesson 10: NULL = empty / unknown
--   COUNT(*) counts rows; COUNT(col) skips NULLs.
--   SUM / AVG ignore NULLs.
--   Never = NULL, always IS NULL.
--   COALESCE(x, 0) replaces NULL with 0.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS clubs;
DROP TABLE IF EXISTS students;
CREATE TABLE students (
    name  text,
    marks int
);
INSERT INTO students VALUES
    ('Ravi',  80),
    ('Priya', 95),
    ('Amit',  NULL),   -- absent
    ('Neha',  70);

-- → 4, 3
SELECT COUNT(*), COUNT(marks) FROM students;

-- → 81.67 (divides by 3, NULL skipped)
SELECT ROUND(AVG(marks), 2) FROM students;

-- → nothing, ever
SELECT name FROM students WHERE marks = NULL;

-- → Amit
SELECT name FROM students WHERE marks IS NULL;

-- → Amit shows 0
SELECT name, COALESCE(marks, 0) AS marks FROM students;

-- → 61.25 (NULL became 0, so divides by 4)
SELECT AVG(COALESCE(marks, 0)) FROM students;

-- How many were absent → 1
SELECT COUNT(*) FROM students WHERE marks IS NULL;

-- Same answer without WHERE → 4 - 3 = 1
SELECT COUNT(*) - COUNT(marks) AS absent FROM students;
