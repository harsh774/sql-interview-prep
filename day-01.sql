-- =====================================================================
-- Day 1: SQL basics → window functions → WITH
-- Run:  psql -d <your_db> -f day-01.sql
-- Each lesson creates its own small table, so the file runs top to bottom.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Setup for Lessons 1–5
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS students;
CREATE TABLE students (
    id    int PRIMARY KEY,
    name  text,
    marks int,
    city  text
);
INSERT INTO students VALUES
    (1, 'Ravi',  80, 'Mumbai'),
    (2, 'Priya', 95, 'Pune'),
    (3, 'Amit',  60, 'Mumbai'),
    (4, 'Neha',  70, 'Delhi');


-- ---------------------------------------------------------------------
-- Lesson 1: SELECT, FROM, WHERE
--   SELECT = which columns, FROM = which table, WHERE = which rows
-- ---------------------------------------------------------------------

-- Names of students from Mumbai → Ravi, Amit
SELECT name
FROM students
WHERE city = 'Mumbai';

-- Names of students with more than 75 marks → Ravi, Priya
SELECT name
FROM students
WHERE marks > 75;


-- ---------------------------------------------------------------------
-- Lesson 2: GROUP BY = make piles
--   One pile per value; COUNT / SUM / AVG / MAX work on each pile.
-- ---------------------------------------------------------------------

-- Students per city → Mumbai 2, Pune 1, Delhi 1
SELECT city, COUNT(*)
FROM students
GROUP BY city;

-- Total marks per city → Mumbai 140, Pune 95, Delhi 70
SELECT city, SUM(marks)
FROM students
GROUP BY city;


-- ---------------------------------------------------------------------
-- Lesson 3: HAVING = keep only some piles
--   WHERE checks single rows (before piles), HAVING checks piles (after).
-- ---------------------------------------------------------------------

-- Cities with total marks above 100 → Mumbai 140
SELECT city, SUM(marks)
FROM students
GROUP BY city
HAVING SUM(marks) > 100;

-- Cities with more than 1 student → Mumbai 2
-- Mistake I made: HAVING count > 1  →  write the full function again
SELECT city, COUNT(*)
FROM students
GROUP BY city
HAVING COUNT(*) > 1;


-- ---------------------------------------------------------------------
-- Lesson 4: Window functions = piles WITHOUT squashing
--   PARTITION BY is the window-function version of GROUP BY.
-- ---------------------------------------------------------------------

-- Every student + their city's total marks
SELECT name, city, marks,
       SUM(marks) OVER (PARTITION BY city) AS city_total
FROM students;

-- Every student + highest marks in their city
SELECT name, city, marks,
       MAX(marks) OVER (PARTITION BY city) AS highest_mark
FROM students;


-- ---------------------------------------------------------------------
-- Lesson 5: ROW_NUMBER = positions 1, 2, 3
-- ---------------------------------------------------------------------

-- Position inside each city (restarts at 1 per city)
SELECT name, city, marks,
       ROW_NUMBER() OVER (PARTITION BY city ORDER BY marks DESC) AS position
FROM students;

-- Position across the whole class (no PARTITION BY = one big pile)
-- → Priya 1, Ravi 2, Neha 3, Amit 4
SELECT name, marks,
       ROW_NUMBER() OVER (ORDER BY marks DESC) AS position
FROM students;


-- ---------------------------------------------------------------------
-- Lesson 6: LAG = value from the previous row
--   ORDER BY decides which row is "previous". First row gets NULL.
--   Order by a real date, not month names (text sorts Feb, Jan, Mar).
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS tests;
CREATE TABLE tests (
    month date,
    marks int
);
INSERT INTO tests VALUES
    ('2026-01-01', 60),
    ('2026-02-01', 75),
    ('2026-03-01', 70);

-- Marks + last month's marks
SELECT month, marks,
       LAG(marks) OVER (ORDER BY month) AS last_month_marks
FROM tests;

-- Change from last month → NULL, 15, -5
SELECT month, marks,
       marks - LAG(marks) OVER (ORDER BY month) AS change
FROM tests;


-- ---------------------------------------------------------------------
-- Lesson 7: WITH = do it in two steps
--   Step 1 saves a result under a name; step 2 reads FROM that name.
--   date_trunc('month', d) cuts a date to its month: 2026-01-20 → 2026-01-01
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS expenses;
CREATE TABLE expenses (
    spent_on date,
    amount   int
);
INSERT INTO expenses VALUES
    ('2026-01-05', 100),
    ('2026-01-20', 200),
    ('2026-02-10', 150),
    ('2026-03-03', 400);

-- Monthly total + change from last month → 300 (NULL), 150 (-150), 400 (250)
-- Mistakes I made: OVER (GROUP BY ...)  and  step 2 reading FROM expenses
WITH monthly AS (
    SELECT date_trunc('month', spent_on) AS month,
           SUM(amount) AS total
    FROM expenses
    GROUP BY date_trunc('month', spent_on)
)
SELECT month, total,
       total - LAG(total) OVER (ORDER BY month) AS change
FROM monthly;


-- ---------------------------------------------------------------------
-- Practice: one person's steps per month
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS steps;
CREATE TABLE steps (
    person    text,
    walked_on date,
    steps     int
);
INSERT INTO steps VALUES
    ('Ravi',  '2026-01-03', 5000),
    ('Ravi',  '2026-01-15', 7000),
    ('Ravi',  '2026-02-08', 6000);

-- → Jan 12000 (NULL), Feb 6000 (-6000)
WITH monthly AS (
    SELECT date_trunc('month', walked_on) AS month,
           SUM(steps) AS total
    FROM steps
    GROUP BY date_trunc('month', walked_on)
)
SELECT month, total,
       total - LAG(total) OVER (ORDER BY month) AS change
FROM monthly;


-- ---------------------------------------------------------------------
-- Final challenge: many people → compare each person with THEMSELVES
--   "For each person, in order of month" → PARTITION BY person ORDER BY month
-- ---------------------------------------------------------------------
TRUNCATE steps;
INSERT INTO steps VALUES
    ('Ravi',  '2026-01-03', 5000),
    ('Ravi',  '2026-02-08', 6000),
    ('Priya', '2026-01-10', 8000),
    ('Priya', '2026-02-12', 4000);

-- → Priya 8000 (NULL), 4000 (-4000); Ravi 5000 (NULL), 6000 (1000)
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
