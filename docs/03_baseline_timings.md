# CP2: Baseline Timings & Query Execution Profiling

## 1. Benchmark setup

- Database: PostgreSQL local database `uc_db`
- Dataset: Seed dataset (150,000 bookings)
- Workload: 30 queries (R01–R25 and W01–W05)
- Method: Three executions per query using `EXPLAIN (ANALYZE, BUFFERS)`.
- Write queries were executed inside transaction rollback blocks.

## 2. Query execution timings

All times are in milliseconds (ms). Run timings are extracted from the raw execution plans; average timings are taken from `summary.csv`.

| Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01 | READ | 0.367 | 0.226 | 0.214 | 0.269 |
| R02 | READ | 23.905 | 16.146 | 13.763 | 17.938 |
| R03 | READ | 13.219 | 11.024 | 11.213 | 11.819 |
| R04 | READ | 7.795 | 7.423 | 9.092 | 8.103 |
| R05 | READ | 17.774 | 15.549 | 14.968 | 16.097 |
| R06 | READ | 0.028 | 0.026 | 0.024 | 0.026 |
| R07 | READ | 9.220 | 8.729 | 10.621 | 9.523 |
| R08 | READ | 5.023 | 2.207 | 3.790 | 3.673 |
| R09 | READ | 14.869 | 11.111 | 13.370 | 13.117 |
| R10 | READ | 31.736 | 25.582 | 22.468 | 26.595 |
| R11 | READ | 0.939 | 0.936 | 1.039 | 0.971 |
| R12 | READ | 10.925 | 10.961 | 10.753 | 10.880 |
| R13 | READ | 14.296 | 13.182 | 11.757 | 13.078 |
| R14 | READ | 25.610 | 20.855 | 21.289 | 22.585 |
| R15 | READ | 14.410 | 13.439 | 13.677 | 13.842 |
| R16 | READ | 5.773 | 5.987 | 5.867 | 5.876 |
| R17 | READ | 18.571 | 17.928 | 16.763 | 17.754 |
| R18 | READ | 11.210 | 11.141 | 10.586 | 10.979 |
| R19 | READ | 3996.749 | 4018.960 | 4144.057 | 4053.255 |
| R20 | READ | 12.451 | 11.357 | 12.166 | 11.991 |
| R21 | READ | 20.519 | 18.466 | 16.683 | 18.556 |
| R22 | READ | 34.039 | 31.974 | 31.671 | 32.561 |
| R23 | READ | 0.060 | 0.054 | 0.057 | 0.057 |
| R24 | READ | 18.592 | 16.436 | 15.444 | 16.824 |
| R25 | READ | 2670.306 | 2684.808 | 2794.694 | 2716.603 |
| W01 | WRITE | 0.857 | 0.786 | 0.768 | 0.804 |
| W02 | WRITE | 19.773 | 18.068 | 16.707 | 18.183 |
| W03 | WRITE | 11.619 | 11.011 | 10.504 | 11.045 |
| W04 | WRITE | 13.771 | 12.483 | 12.109 | 12.788 |
| W05 | WRITE | 10.743 | 10.461 | 10.397 | 10.534 |

## 3. Execution plan scan types

| Query | Scan nodes recorded in benchmark summary |
|---|---|
| R01 | Seq Scan on services ,  Seq Scan on service_categories |
| R02 | Seq Scan on pro_skills ,  Seq Scan on professionals ,  Seq Scan on service_categories ,  Index Scan using pro_availability_pkey on pro_availability ,  Seq Scan on bookings |
| R03 | Seq Scan on bookings ,  Seq Scan on services ,  Index Scan using professionals_pkey on professionals |
| R04 | Seq Scan on bookings ,  Seq Scan on services |
| R05 | Seq Scan on bookings |
| R06 | Index Scan using customers_phone_key on customers |
| R07 | Seq Scan on bookings |
| R08 | Seq Scan on professionals ,  Seq Scan on payouts |
| R09 | Seq Scan on bookings ,  Seq Scan on services ,  Seq Scan on service_categories |
| R10 | Seq Scan on bookings |
| R11 | Seq Scan on reschedules ,  Index Scan using bookings_pkey on bookings ,  Index Scan using services_pkey on services |
| R12 | Seq Scan on bookings |
| R13 | Seq Scan on professionals ,  Seq Scan on bookings |
| R14 | Seq Scan on bookings ,  Seq Scan on services |
| R15 | Seq Scan on bookings ,  Seq Scan on reviews |
| R16 | Seq Scan on bookings |
| R17 | Seq Scan on bookings ,  Seq Scan on services |
| R18 | Seq Scan on reviews |
| R19 | Seq Scan on professionals ,  Seq Scan on bookings |
| R20 | Seq Scan on bookings |
| R21 | Seq Scan on bookings ,  Seq Scan on services ,  Seq Scan on pro_skills |
| R22 | Seq Scan on bookings |
| R23 | Seq Scan on services ,  Index Scan using bookings_pkey on bookings |
| R24 | Seq Scan on bookings |
| R25 | Index Scan using professionals_pkey on professionals ,  Seq Scan on pro_availability ,  Seq Scan on bookings |
| W01 | (no scan) |
| W02 | Index Scan using bookings_pkey on bookings |
| W03 | Seq Scan on bookings |
| W04 | Seq Scan on bookings |
| W05 | Seq Scan on bookings |

## 4. Root-cause analysis

### R19 – City report (average: 4053.255 ms)

R19 is the slowest query in the baseline workload. It uses two correlated subqueries against the bookings table for every qualifying active professional: one counts June completed jobs and the other finds the latest completion time. The repeated bookings-table scans make the query expensive as the number of professionals and bookings grows. The execution summary records sequential scans on professionals and bookings.

### R25 – Professional utilisation (average: 2716.603 ms)

R25 calculates available minutes and booked minutes for Bengaluru professionals. Its correlated subquery calculates completed booking duration separately for each professional. The plan summary records sequential scans on pro_availability and bookings, which contributes to the high execution time.

### R22 – Deep pagination (average: 32.561 ms)

R22 requests page 4,001 using OFFSET 100000. PostgreSQL must process and skip a large number of earlier rows before returning only 25 records. This makes deep OFFSET pagination more expensive than fetching an early page.

### General baseline observations

Several queries use sequential scans on bookings, professionals, reviews, payouts, or other tables. Sequential scans are expected in this untuned baseline because the workload has not yet received the additional indexes and query rewrites planned for the optimization phase. Queries that repeatedly scan large tables or process many rows are the main candidates for further investigation.

## 5. Conclusion

The baseline benchmark completed for all 30 queries, with three execution runs recorded for each query. R19 and R25 are the two slowest queries in this workload and should be investigated during the optimization phase. The raw execution plans are included alongside the summary CSV for verification.

