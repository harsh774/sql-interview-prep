-- =====================================================================
-- Day 5: Reading EXPLAIN ANALYZE, why Postgres skips indexes, JOIN indexes
-- Run:  psql -d <your_db> -f day-05.sql
-- Needs the students table from day-04.sql (run that first).
-- =====================================================================


-- ---------------------------------------------------------------------
-- Warm-up: index on (city, joined_on)
-- ---------------------------------------------------------------------
DROP INDEX IF EXISTS idx_city_marks;
DROP INDEX IF EXISTS idx_students_joined;
CREATE INDEX IF NOT EXISTS idx_city_joined ON students (city, joined_on);
ANALYZE students;

-- ✅ city is the FIRST column
EXPLAIN SELECT * FROM students WHERE city = 'Pune';

-- ❌ joined_on is the SECOND column → Seq Scan (leftmost rule)
-- Mistake I made: said yes
EXPLAIN SELECT * FROM students WHERE joined_on >= '2026-06-01';

-- ✅ both, first column included
EXPLAIN SELECT * FROM students
WHERE city = 'Pune' AND joined_on >= '2026-01-01';

-- ⚠️ partly: city uses the index (Index Cond), date_trunc is checked
-- row by row (Filter). A function only blocks ITS OWN condition.
-- Mistake I made: said no
EXPLAIN SELECT * FROM students
WHERE city = 'Pune' AND date_trunc('year', joined_on) = '2026-01-01';


-- ---------------------------------------------------------------------
-- Expression index: an index on a CALCULATED value
--   The query must use exactly the same expression.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS users;
CREATE TABLE users (id int PRIMARY KEY, email text);
INSERT INTO users
SELECT i, CASE WHEN i % 2 = 0 THEN 'User' || i || '@Gmail.com'
               ELSE 'user' || i || '@gmail.com' END
FROM generate_series(1, 200000) i;
CREATE INDEX idx_users_lower_email ON users (LOWER(email));
ANALYZE users;

-- ✅ same expression as the index
EXPLAIN SELECT * FROM users WHERE LOWER(email) = LOWER('USER42@gmail.COM');

-- ❌ different expression → can't use it
EXPLAIN SELECT * FROM users WHERE UPPER(email) = 'USER42@GMAIL.COM';


-- ---------------------------------------------------------------------
-- Lesson 18: Reading EXPLAIN ANALYZE — look at 4 things
--   1. Scan type          Seq Scan / Index Scan / Bitmap Index Scan
--   2. Rows Removed by Filter   big number = wasted work
--   3. rows=estimate vs actual rows   huge gap → run ANALYZE
--   4. Execution Time
--   Index Cond = part that used the index. Filter = checked row by row.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS orders;
CREATE TABLE orders (id int PRIMARY KEY, customer_id int, status text, amount int);
INSERT INTO orders
SELECT i, i % 10000, (ARRAY['PAID','PENDING','FAILED'])[1 + i % 3], (i * 7) % 5000
FROM generate_series(1, 300000) i;
ANALYZE orders;

-- Seq Scan on orders + Filter: (customer_id = 42) + ~299970 rows removed
-- → index the Filter column ON THAT TABLE
-- Mistake I made: created an index on students(marks)
EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 42;

CREATE INDEX idx_orders_customer_id ON orders (customer_id);
EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 42;


-- ---------------------------------------------------------------------
-- Lesson 19: Why Postgres sometimes skips your index (cost-based planner)
--   A few rows        → Index Scan
--   A medium amount   → Bitmap Scan (collect positions, sort, read table once)
--   Big share / tiny table → Seq Scan
-- ---------------------------------------------------------------------

-- Unique id → Index Scan (primary key index)
EXPLAIN SELECT * FROM orders WHERE id = 12345;

-- 3 values, a third of rows each → Bitmap Scan
CREATE INDEX idx_orders_status ON orders (status);
ANALYZE orders;
EXPLAIN SELECT * FROM orders WHERE status = 'PAID';

-- Tiny table (200 rows = 2 pages) → Seq Scan even with an index. Not a bug.
DROP TABLE IF EXISTS countries;
CREATE TABLE countries (id int PRIMARY KEY, name text);
INSERT INTO countries SELECT i, 'country_' || i FROM generate_series(1, 199) i;
INSERT INTO countries VALUES (200, 'India');
CREATE INDEX idx_countries_name ON countries (name);
ANALYZE countries;
EXPLAIN ANALYZE SELECT * FROM countries WHERE name = 'India';


-- ---------------------------------------------------------------------
-- Lesson 20: Indexes for JOINs
--   Postgres auto-indexes ONLY primary keys and UNIQUE columns.
--   Foreign keys are NOT indexed automatically → index JOIN columns.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS customers;
CREATE TABLE customers (id int PRIMARY KEY, name text);
INSERT INTO customers SELECT i, 'customer_' || i FROM generate_series(0, 9999) i;
ANALYZE customers;

-- Auto-indexed: customers.id, orders.id (primary keys) — nothing else.
-- Mistake I made: said "customers columns"; customers.name is NOT indexed.
SELECT tablename, indexname FROM pg_indexes
WHERE tablename IN ('customers', 'orders') ORDER BY tablename;

-- Needs orders.customer_id indexed (created in Lesson 18)
EXPLAIN ANALYZE
SELECT c.name, SUM(o.amount)
FROM customers c
JOIN orders o ON o.customer_id = c.id
WHERE c.id = 7
GROUP BY c.name;
