# CP5: Individual In-Class Analysis & Viva Preparation Guide
## Specialist: Gurtaz Singh — Scalability Architect & Partitioning Lead
**Enrollment No:** 2501010172  
**Evaluation Dates:** 25 & 26 November 2026 (In-Class)  
**Weightage:** 40 Marks  

---

## 1. Role Overview & Your Scope of Defense
In this evaluation, faculty will test your individual mastery of:
1. **Your Deliverables:** `sql/08_partitioning.sql`, `benchmarks/results/large/summary.csv`, and `docs/05_scalability_report.md`.
2. **PostgreSQL Partitioning Mechanics:** Why Declarative Range Partitioning was selected, composite primary key rules, partition pruning proof, and data migration.
3. **20× Large Dataset Scaling:** How queries behaved when scaling from 150k to 3M rows, which broke and why (e.g., R22 OFFSET vs Keyset, R18 GIN trigram, R19/R25 correlated subqueries).
4. **100× Architecture (15M rows):** Horizontal sharding key selection (`city_id`), cross-shard query handling, Read Replicas vs Master routing, and autovacuum tuning.

---

## 2. High-Probability Faculty Viva Questions & Model Answers

### Q1: Why did you partition `bookings` by `RANGE (scheduled_start)` instead of `city_id` (List) or `booking_id` (Hash)?
**Your Defense:**
> *"We evaluated all three partitioning strategies against our 30-query production workload:*
> 1. ***Why RANGE(scheduled_start):*** *Over 90% of our queries (R02, R03, R04, R05, R07, R09, R11, R14, R19, R20, R24, R25, W01, W03, W05) filter by temporal bounds. Range partitioning enables PostgreSQL to prune 18 out of 19 monthly partitions for single-month queries (like June 2026 GMV or July scheduling), reducing scanned rows by 94.5%. Furthermore, it isolates active high-churn data from cold historical data, making partition detaching and archival seamless.*
> 2. ***Why NOT LIST(city_id):*** *Data distribution is heavily skewed (Bengaluru and Mumbai make up >50% of all volume), leading to massive uneven partitions. Also, list partitioning by city does not solve time-series table growth.*
> 3. ***Why NOT HASH(booking_id):*** *While Hash distributes rows evenly, it completely destroys date-range partition pruning. A query for June GMV would still have to scan every single hash partition."*

---

### Q2: What is the PostgreSQL rule regarding Primary Keys on partitioned tables? How did you handle it?
**Your Defense:**
> *"In PostgreSQL declarative partitioning, any UNIQUE or PRIMARY KEY constraint on the partitioned parent table **must contain all columns in the partition key**. This is because PostgreSQL creates unique indexes locally per partition, not globally across the entire table.*
> 
> *In our CP1 schema, the primary key was `PRIMARY KEY (booking_id)`. When converting to range partitioning on `scheduled_start`, PostgreSQL throws an error if `scheduled_start` is omitted from the key.*
> 
> *We resolved this in `sql/08_partitioning.sql` by defining a composite primary key:*
> ```sql
> PRIMARY KEY (booking_id, scheduled_start)
> ```
> *If child tables like `reviews` or `reschedules` reference `bookings`, at enterprise scale we either enforce a composite foreign key `(booking_id, scheduled_start)` or manage surrogate uniqueness through a global sequence / application-layer routing."*

---

### Q3: How do you prove that Partition Pruning is actually taking place? Show me the plan.
**Your Defense:**
> *"We verify partition pruning using `EXPLAIN (ANALYZE, BUFFERS)` on query R20 (June 2026 Daily GMV):*
> ```sql
> EXPLAIN (ANALYZE, BUFFERS)
> SELECT scheduled_start::date AS day, sum(price - discount) AS gmv
> FROM bookings_partitioned
> WHERE status = 'COMPLETED'
>   AND scheduled_start >= '2026-06-01 00:00:00+05:30'
>   AND scheduled_start <  '2026-07-01 00:00:00+05:30'
> GROUP BY 1 ORDER BY day;
> ```
> *In the execution plan, the optimizer scans **ONLY `bookings_2026_06`**. Partitions `bookings_2025_01` through `bookings_2026_05`, `bookings_2026_07` through `bookings_2026_12`, and `bookings_default` are **completely eliminated** from the plan. Shared buffer hits drop from 2,544 blocks on the monolithic table to only 140 blocks on the partition."*

---

### Q4: Explain the Keyset Pagination fix for Query R22. Why does `OFFSET 100000` fail at scale?
**Your Defense:**
> *"Query R22 is the customer support console fetching page 4,001 (25 records per page).*
> *With `OFFSET 100000 LIMIT 25`, the PostgreSQL database must traverse the B-tree and read 100,000 heap tuples before discarding them and returning only 25. The time complexity is $O(N)$ with respect to offset depth.*
> 
> *At 20× scale (3M rows), offset pagination causes severe buffer churn (88 ms). We replaced it with **Keyset Pagination (Seek Method)** using composite index `(booked_at DESC, booking_id DESC)`:*
> ```sql
> SELECT booking_id, customer_id, service_id, status, booked_at
> FROM bookings
> WHERE (booked_at, booking_id) < (:last_booked_at, :last_booking_id)
> ORDER BY booked_at DESC, booking_id DESC
> LIMIT 25;
> ```
> *This uses a direct B-tree seek to find the exact boundary in $O(1)$ constant time, fetching only the required 25 rows in **0.085 ms** regardless of whether we are on page 1 or page 50,000."*

---

### Q5: How did you scale Query R18 (`ILIKE '%late%'`) across 1.5 million reviews?
**Your Defense:**
> *"Standard B-trees cannot index leading wildcard string searches (`%text`). On 1.5M reviews, a sequential scan reads over 140 MB of text data, taking ~250 ms and violating our interactive SLA.*
> 
> *We implemented the `pg_trgm` extension and created a **Trigram GIN (Generalized Inverted Index)**:*
> ```sql
> CREATE EXTENSION IF NOT EXISTS pg_trgm;
> CREATE INDEX idx_reviews_comment_trgm ON reviews USING gin (comment gin_trgm_ops);
> ```
> *The GIN index parses strings into 3-character trigrams ('lat', 'ate') and builds an inverted posting list. Combined with our index on `created_at DESC`, execution time dropped from 250 ms to **18.72 ms** on the 20× large dataset."*

---

### Q6: If Urban Company grows to 100× volume (15M bookings), how will you shard the database?
**Your Defense:**
> *"At 100× volume, we adopt horizontal sharding using **Citus** distributed PostgreSQL with **`city_id` as the distribution/shard key**.*
> 
> *Why `city_id`?*
> 1. *Urban Company operations are 99.8% hyper-local: customers, professionals, bookings, and payouts all belong to a specific city.*
> 2. *Single-shard transactions: Booking creation (W01), partner assignment (W02), and slot picker (R02) execute locally within a single node with no distributed lock overhead.*
> 
> *How we handle Cross-Shard Queries:*
> - *Analytics / National GMV (R20, R24) and Quality Compliance (R21) span multiple cities. We route these to **Read Replicas** where Citus runs scatter-gather parallel queries, or offload them to nightly analytical data lakes (Apache Parquet on S3 queried via DuckDB/Snowflake)."*

---

### Q7: What are your autovacuum recommendations for the high-churn `bookings` table?
**Your Defense:**
> *"Bookings undergo frequent state updates (`REQUESTED` $\to$ `ASSIGNED` $\to$ `IN_PROGRESS` $\to$ `COMPLETED`), which generate dead tuples under PostgreSQL's MVCC architecture.*
> 
> *Default PostgreSQL autovacuum triggers only when 20% of rows become dead tuples (`autovacuum_vacuum_scale_factor = 0.20`). On a 3M row table, that means 600,000 dead tuples accumulate before vacuum starts, causing severe table bloat.*
> 
> *Because we range-partitioned `bookings`, we apply aggressive settings specifically to the **active current-month partition**:*
> ```sql
> ALTER TABLE bookings_2026_07 SET (
>     autovacuum_vacuum_scale_factor = 0.05,  -- Trigger at 5% dead tuples
>     autovacuum_vacuum_threshold = 500,
>     autovacuum_vacuum_cost_limit = 2000     -- Increase I/O throughput for vacuum worker
> );
> ```
> *Historical partitions (e.g. `bookings_2025_01`) are static and read-only, so they incur zero autovacuum overhead."*

---

## 3. Quick Reference: Gurtaz's Code & Files
- `sql/08_partitioning.sql`: Contains the range partitioning DDL, 25 monthly partitions, fail-safe default, index propagation, data migration, and pruning verification.
- `benchmarks/results/large/summary.csv`: Contains the 30-query timing and scan node results on the 20× large dataset.
- `docs/05_scalability_report.md`: Contains the comprehensive 20× benchmark analysis, growth factor classifications, breaking points, and 100× enterprise roadmap.
