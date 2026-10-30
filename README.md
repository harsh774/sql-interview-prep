# SQL & Database Interview Prep (PostgreSQL)

A 15-day plan, about 1–1.5 hours a day, for the database round of an SDE interview (around 3 years of experience). Every query here was written during practice and tested on PostgreSQL 16.

## Progress

| Day | Topic | Status | File |
| --- | --- | --- | --- |
| 1 | SELECT/WHERE, GROUP BY, HAVING, window functions, ROW_NUMBER, LAG, WITH | ✅ Done | [day-01.sql](day-01.sql) |
| 2 | Ties (RANK vs DENSE_RANK), Nth highest, JOINs, anti-join, NULL rules | ✅ Done (quiz 4/5) | [day-02.sql](day-02.sql) |
| 3 | Top N per group, DISTINCT ON, duplicates, FILTER, mock round | ✅ Done | [day-03.sql](day-03.sql) |
| 4–5 | Indexing & query plans (`EXPLAIN ANALYZE`) | ⏳ Next | |
| 6–8 | Transactions & concurrency | | |
| 9 | Schema design | | |
| 10 | Performance problems in production | | |
| 11–12 | Scaling concepts | | |
| 13 | Multi-tenancy, money, idempotency | | |
| 14–15 | Revision + mock interviews | | |

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

See [mistakes.md](mistakes.md) for every mistake made so far, to revise on Days 14–15.
