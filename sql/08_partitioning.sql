-- ============================================================================
-- Urban Company Home Services Database
-- Checkpoint 4 (CP4): Declarative Table Partitioning & Scalability Architecture
-- Author: Gurtaz Singh (Scalability Architect & Partitioning Specialist)
-- Enrollment No: 2501010172
-- Engine: PostgreSQL 15+
-- Schema: uc
-- ============================================================================

SET search_path TO uc;

-- ============================================================================
-- 1. ARCHITECTURAL DECISION RECORD (ADR)
-- ============================================================================
-- Problem Statement:
-- At 20x scale (3,000,000 bookings) and future 100x scale (15,000,000+ bookings),
-- a monolithic bookings table creates massive index trees (B-tree depth >= 4),
-- buffer pool thrashing, heavy vacuum overhead, and slow sequential scans.
--
-- Why Declarative RANGE Partitioning on `scheduled_start`?
-- 1. Access Pattern Alignment:
--    Over 90% of business workload queries (R02, R03, R04, R05, R07, R09, R11,
--    R14, R19, R20, R24, R25, W01, W03, W05) filter by time ranges on
--    `scheduled_start`, `completed_at`, or `booked_at`.
-- 2. Partition Pruning Efficiency:
--    PostgreSQL planner uses constraint exclusion / run-time partition pruning
--    to eliminate non-qualifying partitions. A monthly report for June 2026
--    prunes 18 out of 19 partitions, scanning ONLY ~165,000 rows instead of
--    3,000,000 rows (a 94.5% reduction in scanned tuples and buffer hits).
-- 3. High-Churn vs Cold Historical Isolation:
--    Recent and upcoming bookings receive 99% of updates (ASSIGNED -> IN_PROGRESS
--    -> COMPLETED). Old partitions become immutable read-only segments that do
--    not require aggressive autovacuuming or buffer space.
-- 4. Lifecycle Data Tiering:
--    Historical partitions older than 18 months can be detached via:
--    `ALTER TABLE bookings DETACH PARTITION bookings_2025_01;`
--    and offloaded to cold columnar/Parquet storage on Amazon S3 without locking
--    the live production table.
--
-- Evaluation of Alternative Partitioning Keys:
-- - LIST (city_id): Rejected. Highly skewed data distribution (Bengaluru and
--   Mumbai account for 50%+ of all bookings), and does not solve time-series
--   index growth or historical archiving.
-- - HASH (booking_id): Rejected. Distributes rows uniformly, but destroys all
--   date-range pruning capabilities. Range queries would still hit every partition.
--
-- The PostgreSQL Declarative Partitioning Primary Key Rule:
-- In PostgreSQL declarative partitioning, any UNIQUE or PRIMARY KEY constraint
-- MUST include the partition key column. Therefore, the single-column primary
-- key `PRIMARY KEY (booking_id)` must be expanded to composite primary key:
-- `PRIMARY KEY (booking_id, scheduled_start)`.
-- ============================================================================

-- Drop temporary or existing partitioned table during migration
DROP TABLE IF EXISTS bookings_partitioned CASCADE;

-- ----------------------------------------------------------------------------
-- 2. DECLARATIVE PARTITIONED TABLE DEFINITION
-- ----------------------------------------------------------------------------
CREATE TABLE bookings_partitioned (
    booking_id          INT NOT NULL,
    customer_id         INT NOT NULL REFERENCES customers(customer_id) ON DELETE RESTRICT,
    service_id          INT NOT NULL REFERENCES services(service_id) ON DELETE RESTRICT,
    pro_id              INT REFERENCES professionals(pro_id) ON DELETE SET NULL,
    city_id             INT NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    pincode             VARCHAR(10) NOT NULL,
    booked_at           TIMESTAMPTZ NOT NULL,
    scheduled_start     TIMESTAMPTZ NOT NULL,
    scheduled_end       TIMESTAMPTZ NOT NULL,
    started_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    status              VARCHAR(30) NOT NULL CHECK (
                            status IN (
                                'REQUESTED',
                                'ASSIGNED',
                                'IN_PROGRESS',
                                'COMPLETED',
                                'CANCELLED_BY_CUSTOMER',
                                'CANCELLED_BY_PRO',
                                'NO_SHOW'
                            )
                        ),
    price               NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
    discount            NUMERIC(10, 2) NOT NULL DEFAULT 0.00 CHECK (discount >= 0 AND discount <= price),
    cancellation_fee    NUMERIC(10, 2) NOT NULL DEFAULT 0.00 CHECK (cancellation_fee >= 0),
    tip                 NUMERIC(10, 2) CHECK (tip IS NULL OR tip >= 0),
    payment_method      VARCHAR(20) NOT NULL CHECK (payment_method IN ('CASH', 'UPI', 'WALLET', 'CARD')),

    -- Business Rules & Temporal Constraints (identical to CP1 schema)
    CONSTRAINT chk_bkg_part_sched_order CHECK (scheduled_end > scheduled_start),
    CONSTRAINT chk_bkg_part_actual_order CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at),
    CONSTRAINT chk_bkg_part_tip_completed CHECK (tip IS NULL OR status = 'COMPLETED'),
    CONSTRAINT chk_bkg_part_cancellation_fee CHECK (cancellation_fee = 0.00 OR status = 'CANCELLED_BY_CUSTOMER'),

    -- Composite Primary Key required by PostgreSQL declarative partitioning
    PRIMARY KEY (booking_id, scheduled_start)
) PARTITION BY RANGE (scheduled_start);

-- ----------------------------------------------------------------------------
-- 3. DECLARATIVE MONTHLY PARTITIONS (2025 & 2026)
-- ----------------------------------------------------------------------------

-- 2025 Monthly Partitions
CREATE TABLE bookings_2025_01 PARTITION OF bookings_partitioned FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-02-01 00:00:00+05:30');
CREATE TABLE bookings_2025_02 PARTITION OF bookings_partitioned FOR VALUES FROM ('2025-02-01 00:00:00+05:30') TO ('2025-03-01 00:00:00+05:30');
CREATE TABLE bookings_2025_03 PARTITION OF bookings_partitioned FOR VALUES FROM ('2025-03-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');
CREATE TABLE bookings_2025_04 PARTITION OF bookings_partitioned FOR VALUES FROM ('2025-04-01 00:00:00+05:30') TO ('2025-05-01 00:00:00+05:30');
CREATE TABLE bookings_2025_05 PARTITION OF bookings_partitioned FOR VALUES FROM ('2025-05-01 00:00:00+05:30') TO ('2025-06-01 00:00:00+05:30');
CREATE TABLE bookings_2025_06 PARTITION OF bookings_partitioned FOR VALUES FROM ('2025-06-01 00:00:00+05:30') TO ('2025-07-01 00:00:00+05:30');
CREATE TABLE bookings_2025_07 PARTITION OF bookings_partitioned FOR VALUES FROM ('2025-07-01 00:00:00+05:30') TO ('2025-08-01 00:00:00+05:30');
CREATE TABLE bookings_2025_08 PARTITION OF bookings_partitioned FOR VALUES FROM ('2025-08-01 00:00:00+05:30') TO ('2025-09-01 00:00:00+05:30');
CREATE TABLE bookings_2025_09 PARTITION OF bookings_partitioned FOR VALUES FROM ('2025-09-01 00:00:00+05:30') TO ('2025-10-01 00:00:00+05:30');
CREATE TABLE bookings_2025_10 PARTITION OF bookings_partitioned FOR VALUES FROM ('2025-10-01 00:00:00+05:30') TO ('2025-11-01 00:00:00+05:30');
CREATE TABLE bookings_2025_11 PARTITION OF bookings_partitioned FOR VALUES FROM ('2025-11-01 00:00:00+05:30') TO ('2025-12-01 00:00:00+05:30');
CREATE TABLE bookings_2025_12 PARTITION OF bookings_partitioned FOR VALUES FROM ('2025-12-01 00:00:00+05:30') TO ('2026-01-01 00:00:00+05:30');

-- 2026 Monthly Partitions
CREATE TABLE bookings_2026_01 PARTITION OF bookings_partitioned FOR VALUES FROM ('2026-01-01 00:00:00+05:30') TO ('2026-02-01 00:00:00+05:30');
CREATE TABLE bookings_2026_02 PARTITION OF bookings_partitioned FOR VALUES FROM ('2026-02-01 00:00:00+05:30') TO ('2026-03-01 00:00:00+05:30');
CREATE TABLE bookings_2026_03 PARTITION OF bookings_partitioned FOR VALUES FROM ('2026-03-01 00:00:00+05:30') TO ('2026-04-01 00:00:00+05:30');
CREATE TABLE bookings_2026_04 PARTITION OF bookings_partitioned FOR VALUES FROM ('2026-04-01 00:00:00+05:30') TO ('2026-05-01 00:00:00+05:30');
CREATE TABLE bookings_2026_05 PARTITION OF bookings_partitioned FOR VALUES FROM ('2026-05-01 00:00:00+05:30') TO ('2026-06-01 00:00:00+05:30');
CREATE TABLE bookings_2026_06 PARTITION OF bookings_partitioned FOR VALUES FROM ('2026-06-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');
CREATE TABLE bookings_2026_07 PARTITION OF bookings_partitioned FOR VALUES FROM ('2026-07-01 00:00:00+05:30') TO ('2026-08-01 00:00:00+05:30');
CREATE TABLE bookings_2026_08 PARTITION OF bookings_partitioned FOR VALUES FROM ('2026-08-01 00:00:00+05:30') TO ('2026-09-01 00:00:00+05:30');
CREATE TABLE bookings_2026_09 PARTITION OF bookings_partitioned FOR VALUES FROM ('2026-09-01 00:00:00+05:30') TO ('2026-10-01 00:00:00+05:30');
CREATE TABLE bookings_2026_10 PARTITION OF bookings_partitioned FOR VALUES FROM ('2026-10-01 00:00:00+05:30') TO ('2026-11-01 00:00:00+05:30');
CREATE TABLE bookings_2026_11 PARTITION OF bookings_partitioned FOR VALUES FROM ('2026-11-01 00:00:00+05:30') TO ('2026-12-01 00:00:00+05:30');
CREATE TABLE bookings_2026_12 PARTITION OF bookings_partitioned FOR VALUES FROM ('2026-12-01 00:00:00+05:30') TO ('2027-01-01 00:00:00+05:30');

-- Fail-Safe Default Partition (Prevents insert errors if bookings fall outside mapped ranges)
CREATE TABLE bookings_default PARTITION OF bookings_partitioned DEFAULT;

-- ----------------------------------------------------------------------------
-- 4. AUTOMATED INDEX PROPAGATION ON PARTITIONED HIERARCHY
-- ----------------------------------------------------------------------------
-- In PostgreSQL 11+, indexes created on the partitioned parent table are
-- automatically propagated to every existing partition and all future partitions.

-- Customer lookups (R03)
CREATE INDEX idx_part_bookings_cust_sched ON bookings_partitioned (customer_id, scheduled_start)
    INCLUDE (service_id, pro_id, status);

-- Professional schedules & job lookups (R04)
CREATE INDEX idx_part_bookings_pro_sched ON bookings_partitioned (pro_id, scheduled_start)
    INCLUDE (service_id, scheduled_end, pincode, status);

-- Dispatch partial index for requested jobs (R05, W02)
CREATE INDEX idx_part_bookings_requested ON bookings_partitioned (scheduled_start)
    INCLUDE (service_id, city_id)
    WHERE status = 'REQUESTED';

-- Pro completed earnings & reports (R07, R19, R25, W04)
CREATE INDEX idx_part_bookings_pro_sched_comp ON bookings_partitioned (pro_id, scheduled_start)
    INCLUDE (scheduled_end, completed_at, price, discount, tip)
    WHERE status = 'COMPLETED';

-- Pro latest completed job (R19 SubPlan 2)
CREATE INDEX idx_part_bookings_pro_last_job ON bookings_partitioned (pro_id, completed_at DESC NULLS LAST);

-- Quality & monthly category aggregations (R09)
CREATE INDEX idx_part_bookings_sched_comp ON bookings_partitioned (scheduled_start, service_id)
    INCLUDE (started_at)
    WHERE status = 'COMPLETED';

-- Pro no-show rate calculations (R10)
CREATE INDEX idx_part_bookings_pro_status ON bookings_partitioned (pro_id, status)
    WHERE pro_id IS NOT NULL;

-- UC Plus member discounts (R12)
CREATE INDEX idx_part_bookings_plus_discount ON bookings_partitioned (booked_at)
    INCLUDE (discount)
    WHERE discount > 0;

-- Customer cancellations for partner rewards (R13)
CREATE INDEX idx_part_bookings_cancelled_cust ON bookings_partitioned (pro_id)
    WHERE status = 'CANCELLED_BY_CUSTOMER';

-- City-level demand heat map and planning (R14)
CREATE INDEX idx_part_bookings_city_serv_sched ON bookings_partitioned (city_id, service_id, scheduled_start);

-- City-level pincode expansion (R16)
CREATE INDEX idx_part_bookings_city_booked_pin ON bookings_partitioned (city_id, booked_at, pincode);

-- Customer retention analysis (R17)
CREATE INDEX idx_part_bookings_cust_serv_comp ON bookings_partitioned (booked_at, customer_id, service_id)
    WHERE status = 'COMPLETED';

-- Finance GMV daily reporting (R20)
CREATE INDEX idx_part_bookings_gmv_comp ON bookings_partitioned (scheduled_start)
    INCLUDE (price, discount)
    WHERE status = 'COMPLETED';

-- Keyset pagination for customer support console (R22)
CREATE INDEX idx_part_bookings_booked_at_id ON bookings_partitioned (booked_at DESC, booking_id DESC);

-- Cancellation fee tracking (R24)
CREATE INDEX idx_part_bookings_canc_fee ON bookings_partitioned (scheduled_start)
    INCLUDE (cancellation_fee)
    WHERE cancellation_fee > 0;

-- Dispatch oldest unassigned job picker (W02)
CREATE INDEX idx_part_bookings_requested_min ON bookings_partitioned (booking_id)
    WHERE status = 'REQUESTED';

-- Pro active assigned jobs (W03)
CREATE INDEX idx_part_bookings_assigned_pro ON bookings_partitioned (pro_id, scheduled_start)
    WHERE status = 'ASSIGNED';

-- Automated operations no-show sweeping (W05)
CREATE INDEX idx_part_bookings_noshow ON bookings_partitioned (scheduled_end)
    WHERE status = 'ASSIGNED' AND started_at IS NULL;

-- ----------------------------------------------------------------------------
-- 5. ZERO-DATA-LOSS MIGRATION SCRIPT
-- ----------------------------------------------------------------------------
-- Migrate data from original monolithic table to partitioned structure:
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'uc' AND table_name = 'bookings') THEN
        RAISE NOTICE 'Migrating data from uc.bookings to uc.bookings_partitioned...';
        INSERT INTO bookings_partitioned SELECT * FROM bookings;
        RAISE NOTICE 'Data migration complete. Analyzing partitioned table...';
    END IF;
END $$;

ANALYZE bookings_partitioned;

-- ----------------------------------------------------------------------------
-- 6. DEMONSTRATION OF PARTITION PRUNING
-- ----------------------------------------------------------------------------
-- Proof 1: Single-month query (June 2026 Daily GMV - R20)
-- The query planner scans ONLY `bookings_2026_06`. All other 24 partitions are pruned!
\echo '========================================================================'
\echo 'PROVING PARTITION PRUNING: Single-Month Query (June 2026 GMV)'
\echo '========================================================================'
EXPLAIN (ANALYZE, BUFFERS)
SELECT scheduled_start::date AS day, sum(price - discount) AS gmv
FROM bookings_partitioned
WHERE status = 'COMPLETED'
  AND scheduled_start >= '2026-06-01 00:00:00+05:30'
  AND scheduled_start <  '2026-07-01 00:00:00+05:30'
GROUP BY 1
ORDER BY day;

-- Proof 2: Operational Dispatch Query (July 2026 Jobs - R05)
-- The query planner scans ONLY `bookings_2026_07` (and default if open-ended).
\echo '========================================================================'
\echo 'PROVING PARTITION PRUNING: Dispatch Slot Query (July 2026)'
\echo '========================================================================'
EXPLAIN (ANALYZE, BUFFERS)
SELECT booking_id, service_id, city_id, scheduled_start
FROM bookings_partitioned
WHERE status = 'REQUESTED'
  AND scheduled_start >= '2026-07-01 00:00:00+05:30'
  AND scheduled_start <  '2026-07-02 12:00:00+05:30'
ORDER BY scheduled_start;

-- ----------------------------------------------------------------------------
-- 7. AUTOMATED PARTITION LIFECYCLE MANAGEMENT UTILITIES
-- ----------------------------------------------------------------------------

-- Function to automatically provision upcoming monthly partitions
CREATE OR REPLACE FUNCTION create_monthly_booking_partition(target_date DATE)
RETURNS VOID AS $$
DECLARE
    start_ts TIMESTAMPTZ := date_trunc('month', target_date);
    end_ts   TIMESTAMPTZ := start_ts + interval '1 month';
    part_name TEXT := 'bookings_' || to_char(start_ts, 'YYYY_MM');
    sql_stmt TEXT;
BEGIN
    sql_stmt := format(
        'CREATE TABLE IF NOT EXISTS %I PARTITION OF bookings_partitioned FOR VALUES FROM (%L) TO (%L);',
        part_name, start_ts, end_ts
    );
    EXECUTE sql_stmt;
    RAISE NOTICE 'Successfully provisioned partition: %', part_name;
END;
$$ LANGUAGE plpgsql;

-- Function to safely detach an aged partition for cold archiving
CREATE OR REPLACE FUNCTION detach_and_archive_old_partition(target_month DATE)
RETURNS VOID AS $$
DECLARE
    start_ts TIMESTAMPTZ := date_trunc('month', target_month);
    part_name TEXT := 'bookings_' || to_char(start_ts, 'YYYY_MM');
    sql_stmt TEXT;
BEGIN
    sql_stmt := format('ALTER TABLE bookings_partitioned DETACH PARTITION %I CONCURRENTLY;', part_name);
    EXECUTE sql_stmt;
    RAISE NOTICE 'Partition % has been safely detached for S3 cold storage export.', part_name;
END;
$$ LANGUAGE plpgsql;
