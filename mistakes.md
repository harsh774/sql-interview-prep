# Mistake Log

Redo each one without looking during revision (Days 14–15).

| Day | Topic | Mistake | Fix |
| --- | --- | --- | --- |
| 1 | HAVING | `HAVING count > 1` | Write the full function: `HAVING COUNT(*) > 1` |
| 1 | Window functions | `OVER (GROUP BY ...)` | OVER takes only `PARTITION BY` and `ORDER BY` |
| 1 | WITH (CTE) | Step 2 read `FROM expenses` (twice) | Step 2 reads only from the CTE and its columns |
| 1 | Tables vs columns | `FROM person` | FROM takes a table (`steps`); `person` is a column |
| 1, 2 | date_trunc | `date_trunc('month', steps)`, `datetime('trunck')`, `date_truck` | `date_trunc('month', walked_on)`, with the date column |
| 1, 2 | GROUP BY | `GROUP BY person` only; `ORDER BY person` in step 1 | GROUP BY = make piles, ORDER BY = sort. Group by every non-aggregated SELECT column |
| 1, 2 | SELECT | Missing comma (`person total_steps`); comma after last column | Commas between columns, none after the last |
| 1, 2 | PARTITION vs ORDER | `PARTITION BY month ORDER BY person` | "For each person, in order of month" → `PARTITION BY person ORDER BY month` |
| 2 | WITH syntax | `WITH monthly (`; missing `FROM`; missing `)` | `WITH name AS ( SELECT ... FROM ... GROUP BY ... )` |
| 2 | Nth highest | `WHERE marks > 80`, written before FROM | Filter on the position: `FROM positions WHERE position = 2` |
| 2 | JOIN filter | `AND club IS NOT NULL` inside ON | Remove rows with `WHERE` after the join; anti-join uses `IS NULL` |
| 2 | Table nickname | `FROM students` then `s.name` | Declare it: `FROM students s` |
| 2 | Ties (quiz) | ROW_NUMBER for 3rd highest of 95, 80, 80, 60 | ROW_NUMBER never shares. "Nth highest" → DENSE_RANK |
| 3 | Top N per group | `PARTITION BY city DESC` | `PARTITION BY city ORDER BY marks DESC` |
| 3 | WITH (CTE) | Step 2 used `marks`, step 1 didn't select it | Select everything step 2 needs in step 1 |
| 3 | Top N filter | `WHERE position >= 2` | Top 2 = `WHERE position <= 2` |
| 3 | GROUP BY + FILTER | GROUP BY city without selecting city | When you GROUP BY a column, SELECT it too |
| 3 (mock) | FILTER vs HAVING | `count(*) filter (where avg_marks > 75)` | Whole piles → `HAVING AVG(marks) > 75` |
| 3 (mock) | JOIN + GROUP BY | Couldn't start "students in more than one club" | JOIN, then `GROUP BY s.id, s.name`, then `HAVING COUNT(*) > 1` |
| 3 | GROUP BY choice | `GROUP BY s.id, s.city` for a per-city count | The "per" rule: per city → `GROUP BY s.city` |
| 4 | LIKE and indexes | Thought `name LIKE '%vi'` (ends with) can use an index | A `%` at the start breaks the index: matches are scattered, like words ending in "vi" in a dictionary |
| 4 | Math on a column | Thought `marks + 10 > 90` can use an index (no function) | Math counts too. Column must be completely alone: `marks > 80` |
| 5 | Composite index | Thought `WHERE joined_on >= ...` uses an index on `(city, joined_on)` | Leftmost rule: the second column alone is scattered. Say "city is the FIRST column", not just "city is indexed" |
| 5 | Function + composite | Said `city = 'Pune' AND date_trunc(..., joined_on) = ...` can't use the index at all | A function only blocks its own condition: city uses the index (Index Cond), date_trunc is checked row by row (Filter) |
| 5 | Reading EXPLAIN | Plan showed `Seq Scan on orders`, `Filter: (customer_id = 42)`; I indexed `students(marks)` | "Seq Scan on ___" = table, "Filter: (___)" = column → `CREATE INDEX ON orders (customer_id)` |
| 5 | Auto indexes | Said all customers columns are indexed | Postgres auto-indexes only PRIMARY KEY and UNIQUE columns. Foreign keys are NOT indexed automatically |
| 5 (test) | LEFT JOIN syntax | `left join on ... from clubs as c`, no `IS NULL` step | `FROM a LEFT JOIN b ON ... WHERE b.col IS NULL` — table name right after JOIN |
| 5 (test) | Counting rows | `HAVING count(students) >= 2` | Use `COUNT(*)`; `students` is a table, not a column |
| 5 (test) | Top N per group | `ORDER BY marks` (no DESC), empty WHERE | "Top" = `ORDER BY marks DESC`; top 2 = `WHERE position <= 2` |
| 5 (test) | LAG ordering | `PARTITION BY student_id ORDER BY marks` | "Previous" means previous in time: `ORDER BY test_date` |
| 5 (test) | WHERE vs HAVING (theory) | Said "WHERE is aggregator and HAVING is not" (reversed) | WHERE filters rows BEFORE grouping, can't use aggregates. HAVING filters groups AFTER GROUP BY, can use aggregates |
| 6 (warm-up) | Top N per group (again) | No DESC, `>= 2`, `city marks` (no comma), comma before FROM, missing `FROM positions`; retry had `marks, from` | Top = DESC, top 2 = `<= 2`. No comma right before FROM or WHERE |
| 6 | Transactions | Said Postgres would "crash" on a negative balance | Postgres stores it unless a rule says no. Your code runs ROLLBACK; add `CHECK (balance >= 0)` as a safety net |
