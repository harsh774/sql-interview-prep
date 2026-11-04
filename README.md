# SQL & Database Interview Prep (PostgreSQL)

A 15-day plan, about 1–1.5 hours a day, for the database round of an SDE interview (around 3 years of experience). Every query here was written during practice and tested on PostgreSQL 16.

## Progress

| Day | Topic | Status | File |
| --- | --- | --- | --- |
| 1 | SELECT/WHERE, GROUP BY, HAVING, window functions, ROW_NUMBER, LAG, WITH | ✅ Done | [day-01.sql](day-01.sql) |
| 2 | Ties (RANK vs DENSE_RANK), Nth highest, JOINs, anti-join, NULL rules | ✅ Done (quiz 4/5) | [day-02.sql](day-02.sql) |
| 3 | Top N per group, DISTINCT ON, duplicates, FILTER, mock round | ✅ Done | [day-03.sql](day-03.sql) |
| 4–5 | Indexing & query plans (`EXPLAIN ANALYZE`) | ✅ Done | [day-04.sql](day-04.sql), [day-05.sql](day-05.sql) |
| 6–8 | Transactions & concurrency: ACID, isolation, MVCC, deadlocks, SKIP LOCKED, optimistic locking | ✅ Done | [day-06.sql](day-06.sql), [day-07.sql](day-07.sql), [day-08.sql](day-08.sql) |
| 9 | Schema design | | |
| 10 | Performance problems in production | | |
| 11–12 | Scaling concepts | | |
| 13 | Multi-tenancy, money, idempotency | | |
| 14–15 | Revision + mock interviews | | |

## Test scores

| Date | Test | Score |
| --- | --- | --- |
| Day 5 | Full test Days 1–5: MCQs | 11 / 12 |
| Day 5 | Full test Days 1–5: queries | 3.5 / 5 |
| Day 5 | Full test Days 1–5: theory | 2 / 3 |
| Day 8 | Test Days 6–8: MCQs | 5 / 10 (retake of misses 5 / 5) |
| Day 8 | Test Days 6–8: two-terminal scenario | 1.5 / 5 |
| Day 8 | Test Days 6–8: theory | 3 / 5 |

## How to run

Each file creates its own small tables, so it runs top to bottom on an empty database:

```bash
createdb sqlprep
psql -d sqlprep -f day-01.sql
```

The expected answer for each query is in the comment above it.

## Rules I keep forgetting

- **Writing order:** SELECT → FROM → WHERE → GROUP BY → HAVING → ORDER BY
- **GROUP BY** makes piles; **ORDER BY** only sorts.
- **WHERE** checks rows (before piles); **HAVING** checks whole piles (after).
- **FILTER** counts some rows *inside* a pile; **HAVING** removes *whole* piles.
- **The "per" rule:** whatever follows "per" / "each" in the question goes in GROUP BY.
- **Inside OVER:** "For each *X*, in order of *Y*" → `PARTITION BY X ORDER BY Y`
- **WITH:** step 2 reads `FROM <cte_name>` and only sees the columns step 1 selected.
- **Nth highest** → DENSE_RANK. **Top N per group** → ROW_NUMBER. **Top 1, Postgres** → DISTINCT ON.
- **NULL:** never `= NULL`, always `IS NULL`. `COUNT(col)`, `SUM`, `AVG` skip NULLs.

- **Index rules:** keep the column alone (no function, no math); `(A, B)` helps A or A+B, not B alone.
- **Auto-indexed:** only PRIMARY KEY and UNIQUE. Index foreign keys / JOIN columns yourself.
- **Reading a plan:** "Seq Scan on ___" = table, "Filter: (___)" = column to index.

- **Transactions:** Read Committed = live scoreboard, Repeatable Read = photo at start, Serializable = as if one at a time. Higher levels → retry on serialization errors.
- **Lost update fix:** `SET x = x - 100`, or `SELECT ... FOR UPDATE` before read-decide-write.
- **Every transaction ends with `COMMIT;` (or `ROLLBACK;`).** Until then nothing is saved and the row stays locked.
- **Plain SELECT never waits. `SELECT ... FOR UPDATE` waits** for whoever holds the row lock.
- **Which fix for which problem:** write skew → Serializable · deadlock → lock rows in the same order (`ORDER BY id FOR UPDATE`) + retry · workers grabbing any free job → `FOR UPDATE SKIP LOCKED` · one specific row → plain `FOR UPDATE` · long form edits → `version` column.
- **Optimistic locking:** `UPDATE ... WHERE id = ? AND version = ?` → `UPDATE 0` is NOT an error; the code must check the row count and retry.

See [mistakes.md](mistakes.md) for every mistake made so far, to revise on Days 14–15.
