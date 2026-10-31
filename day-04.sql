-- =====================================================================
-- Day 4: Indexing — what an index is, and when Postgres can't use it
-- Run:  psql -d <your_db> -f day-04.sql
-- Tip: run each EXPLAIN ANALYZE yourself and look for
--      "Seq Scan" (read every row) vs "Index Scan" / "Bitmap Index Scan"
--      (both mean the index was used).
-- =====================================================================


-- ---------------------------------------------------------------------
-- Setup: 1 million students, so the speed difference is visible
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS students CASCADE;
CREATE TABLE students (
    id        int PRIMARY KEY,
    name      text,
    city      text,
    marks     int,
    joined_on date
);
INSERT INTO students
SELECT i,
       'student_' || i,
       (ARRAY['Mumbai','Pune','Delhi','Chennai','Kolkata'])[1 + i % 5],
       (i * 37) % 101,
       DATE '2024-01-01' + (i % 1095)
FROM generate_series(1, 1000000) i;
ANALYZE students;


-- ---------------------------------------------------------------------
-- Lesson 15: What is an index?
--   A separate list of one column's values, kept SORTED, each pointing
--   to its row. Sorted = Postgres can halve the list each step:
--   1,000,000 rows → about 20 checks instead of 1,000,000.
-- ---------------------------------------------------------------------

-- Before: Seq Scan (I measured ~46 ms)
EXPLAIN ANALYZE SELECT * FROM students WHERE name = 'student_777777';

CREATE INDEX idx_students_name ON students(name);

-- After: Index Scan (I measured ~0.06 ms)
EXPLAIN ANALYZE SELECT * FROM students WHERE name = 'student_777777';

-- Rule 1: an index only helps the column it is sorted by.
-- The name index does nothing for city; city needs its own index.
CREATE INDEX idx_students_city ON students(city);

-- Selectivity: "Pune" matches 20% of the table, so the city index barely
-- helps (I measured ~46 ms without vs ~45 ms with).
-- Indexes help most when the WHERE matches a SMALL fraction of rows.
EXPLAIN ANALYZE SELECT * FROM students WHERE city = 'Pune';


-- ---------------------------------------------------------------------
-- Lesson 16: When Postgres can't use your index
--   Rule 2: keep the column COMPLETELY ALONE in the WHERE.
--           No function on it, no math on it.
-- ---------------------------------------------------------------------

-- Function on the column → Seq Scan
EXPLAIN SELECT * FROM students WHERE LOWER(name) = 'student_777777';

-- Fix: index the expression itself → Index Scan (~0.04 ms)
CREATE INDEX idx_students_lower_name ON students (LOWER(name));
EXPLAIN ANALYZE SELECT * FROM students WHERE LOWER(name) = 'student_777777';

-- Dates: same rule
CREATE INDEX idx_students_joined ON students(joined_on);

-- ❌ function on the column
EXPLAIN SELECT * FROM students
WHERE date_trunc('year', joined_on) = '2026-01-01';

-- ✅ column alone: jump to 2026-01-01, read until 2027-01-01
EXPLAIN SELECT * FROM students
WHERE joined_on >= '2026-01-01' AND joined_on < '2027-01-01';

-- Math: same rule
CREATE INDEX idx_students_marks ON students(marks);

-- ❌ math on the column → Seq Scan
-- Mistake I made: thought this was fine because it has no function
EXPLAIN SELECT * FROM students WHERE marks + 10 > 109;

-- ✅ math moved to the other side → uses idx_students_marks
EXPLAIN SELECT * FROM students WHERE marks > 99;

-- LIKE
--   'abc%' (starts with) can jump, like a dictionary — but in Postgres a
--   plain index usually isn't used; create it with text_pattern_ops.
--   '%abc' (ends with) can never use a normal index.
--   (\_ escapes the underscore, which is a LIKE wildcard)
EXPLAIN SELECT * FROM students WHERE name LIKE 'student\_77777%';   -- Seq Scan

CREATE INDEX idx_students_name_pattern ON students (name text_pattern_ops);
EXPLAIN SELECT * FROM students WHERE name LIKE 'student\_77777%';   -- Index Scan

-- Mistake I made: thought ends-with could use the index
EXPLAIN SELECT * FROM students WHERE name LIKE '%\_777777';          -- Seq Scan


-- ---------------------------------------------------------------------
-- Trade-off: indexes make READS faster and WRITES slower
--   Every INSERT/UPDATE/DELETE must also update every index.
--   I measured inserting 100,000 rows: 172 ms with 1 index, 531 ms with 3.
-- ---------------------------------------------------------------------

-- See every index on the table
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'students';


-- ---------------------------------------------------------------------
-- Lesson 17: Composite index = one list sorted by two columns
--   Sorted by city first; marks are only sorted INSIDE each city.
--   Rule 3 (leftmost rule): an index on (A, B) helps A, or A + B,
--   but NOT B alone.
-- ---------------------------------------------------------------------
DROP INDEX IF EXISTS idx_students_marks;   -- so only the composite index can help
DROP INDEX IF EXISTS idx_students_city;
CREATE INDEX idx_city_marks ON students (city, marks);

-- ✅ city + marks → uses idx_city_marks
EXPLAIN SELECT * FROM students WHERE city = 'Pune' AND marks > 99;

-- ✅ city alone → still uses idx_city_marks
EXPLAIN SELECT * FROM students WHERE city = 'Pune';

-- ❌ marks alone → Seq Scan (marks are scattered across cities)
EXPLAIN SELECT * FROM students WHERE marks > 99;

-- The order you WRITE the WHERE doesn't matter, only the order IN THE INDEX.
-- Both of these use idx_city_marks:
EXPLAIN SELECT * FROM students WHERE city = 'Pune' AND marks > 99;
EXPLAIN SELECT * FROM students WHERE marks > 99 AND city = 'Pune';

-- Choosing the order: put FIRST the column you ALWAYS filter on.
--   Query A: WHERE customer_id = 42
--   Query B: WHERE customer_id = 42 AND status = 'PAID'
--   One index for both → (customer_id, status)
DROP TABLE IF EXISTS orders;
CREATE TABLE orders (id int PRIMARY KEY, customer_id int, status text);
INSERT INTO orders
SELECT i, i % 10000, (ARRAY['PAID','PENDING','FAILED'])[1 + i % 3]
FROM generate_series(1, 300000) i;
CREATE INDEX idx_orders_customer_status ON orders (customer_id, status);
ANALYZE orders;

EXPLAIN SELECT * FROM orders WHERE customer_id = 42;                     -- ✅
EXPLAIN SELECT * FROM orders WHERE customer_id = 42 AND status = 'PAID'; -- ✅
