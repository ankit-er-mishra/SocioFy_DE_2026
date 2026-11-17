-- ============================================================================
-- Urban Company Home Services Database
-- Checkpoint 3 (CP3): Index Engineering for Query Optimization
-- Author: Rishit Babbar (Member 3 - Optimization Engine & Index Tuning)
-- Engine: PostgreSQL 15+
-- Schema: uc
-- ============================================================================

SET search_path TO uc;

-- Enable pg_trgm extension for GIN trigram indexes (R18: ILIKE '%late%')
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ============================================================================
-- COMPOSITE B-TREE INDEXES (Equality first, then Range/Sort)
-- ============================================================================

-- R02: Slot picker - professionals in Bengaluru (city_id=1) with ACTIVE status
--      Equality on city_id, status + pro_id for joins
CREATE INDEX idx_professionals_city_status ON professionals (city_id, status)
    WHERE status = 'ACTIVE';

-- R02, R04, R07, R19: Bookings by professional + scheduled_start range
--      Equality on pro_id, range on scheduled_start
CREATE INDEX idx_bookings_pro_scheduled ON bookings (pro_id, scheduled_start);

-- R03: Customer's upcoming bookings - customer_id (equality) + scheduled_start (range)
CREATE INDEX idx_bookings_customer_scheduled ON bookings (customer_id, scheduled_start)
    WHERE scheduled_start >= '2026-07-01'; -- partial for upcoming only

-- R04: Professional's jobs on specific date - rewritten to use range
CREATE INDEX idx_bookings_pro_scheduled_date ON bookings (pro_id, scheduled_start)
    INCLUDE (service_id, scheduled_end, pincode, status);

-- R05: Dispatch - REQUESTED bookings before specific time
--      Equality on status, range on scheduled_start
CREATE INDEX idx_bookings_requested_scheduled ON bookings (status, scheduled_start)
    WHERE status = 'REQUESTED';

-- R06: Customer lookup by phone - already covered by UNIQUE constraint on customers.phone
--      No additional index needed

-- R07: Professional's earnings in a week - pro_id + completed_at range + status filter
CREATE INDEX idx_bookings_pro_completed_status ON bookings (pro_id, completed_at)
    WHERE status = 'COMPLETED';

-- R08: Payouts pending for specific week - status + week_start
CREATE INDEX idx_payouts_pending_week ON payouts (week_start, status)
    WHERE status = 'PENDING';

-- R09: June 2026 completed jobs by category - bookings scheduled_start range + status
CREATE INDEX idx_bookings_completed_june ON bookings (scheduled_start)
    WHERE status = 'COMPLETED'
      AND scheduled_start >= '2026-06-01' AND scheduled_start < '2026-07-01';

-- R10: Professionals with >=20 assigned jobs - grouping on pro_id
--      Covered by idx_bookings_pro_scheduled

-- R11: Reschedules in June 2026 - created_at range
CREATE INDEX idx_reschedules_created ON reschedules (created_at);

-- R12: Plus discounts in 2026 - discount > 0 + booked_at year
CREATE INDEX idx_bookings_plus_discount ON bookings (booked_at)
    WHERE discount > 0;

-- R13: Professionals never cancelled by customer - NOT EXISTS subquery on bookings
--      Needs index on bookings(pro_id) where status = 'CANCELLED_BY_CUSTOMER'
CREATE INDEX idx_bookings_cancelled_customer ON bookings (pro_id)
    WHERE status = 'CANCELLED_BY_CUSTOMER';

-- R14: Bengaluru bookings by category/weekday/hour - city_id + scheduled_start
CREATE INDEX idx_bookings_city_scheduled ON bookings (city_id, scheduled_start);

-- R15: Professional ratings in June 2026 - reviews.created_at + bookings join
CREATE INDEX idx_reviews_created ON reviews (created_at);
-- bookings.pro_id covered by idx_bookings_pro_scheduled

-- R16: Mumbai pincodes in June 2026 - city_id + booked_at + pincode
CREATE INDEX idx_bookings_city_booked_pincode ON bookings (city_id, booked_at, pincode);

-- R17: Customer repeat bookings by category - customer_id + service_id + booked_at
CREATE INDEX idx_bookings_customer_service_booked ON bookings (customer_id, service_id, booked_at)
    WHERE status = 'COMPLETED';

-- R18: Reviews with 'late' in comment - GIN trigram index (created below)

-- R19: Active Bengaluru professionals - city_id + status
CREATE INDEX idx_professionals_city_status_active ON professionals (city_id, status)
    WHERE status = 'ACTIVE';
-- Subqueries need bookings(pro_id, status, scheduled_start, completed_at)
CREATE INDEX idx_bookings_pro_status_scheduled_completed ON bookings (pro_id, status, scheduled_start, completed_at);

-- R20: Daily GMV June 2026 - scheduled_start::date + status
CREATE INDEX idx_bookings_completed_scheduled_date ON bookings (scheduled_start)
    WHERE status = 'COMPLETED'
      AND scheduled_start >= '2026-06-01' AND scheduled_start < '2026-07-01';

-- R21: Unskilled jobs - bookings.completed + NOT EXISTS pro_skills
--      pro_skills(pro_id, category_id) is PK, already indexed
--      Need bookings(pro_id, service_id, status) for the join
CREATE INDEX idx_bookings_pro_service_completed ON bookings (pro_id, service_id)
    WHERE status = 'COMPLETED';

-- R22: Deep pagination - booked_at DESC (keyset pagination will replace OFFSET)
--      But for OFFSET path, need index on booked_at
CREATE INDEX idx_bookings_booked_desc ON bookings (booked_at DESC);

-- R23: Booking detail by PK - already covered by PRIMARY KEY

-- R24: Cancellation fees per month - scheduled_start + cancellation_fee > 0
CREATE INDEX idx_bookings_cancellation_fees ON bookings (scheduled_start)
    WHERE cancellation_fee > 0;

-- R25: Utilisation - pro_availability join professionals(city_id=1) + bookings
--      pro_availability(pro_id, work_date) is PK
--      Need professionals(city_id) index
CREATE INDEX idx_professionals_city ON professionals (city_id);

-- ============================================================================
-- PARTIAL INDEXES (Filter rare statuses / specific conditions)
-- ============================================================================

-- R02: Only active professionals in specific cities
CREATE INDEX idx_professionals_active_city ON professionals (city_id, pro_id)
    WHERE status = 'ACTIVE';

-- R05: Only REQUESTED bookings (rare status)
CREATE INDEX idx_bookings_requested_only ON bookings (scheduled_start)
    WHERE status = 'REQUESTED';

-- R08: Only PENDING payouts
CREATE INDEX idx_payouts_pending ON payouts (week_start)
    WHERE status = 'PENDING';

-- R13: Only CANCELLED_BY_CUSTOMER bookings
CREATE INDEX idx_bookings_cancelled_by_customer ON bookings (pro_id)
    WHERE status = 'CANCELLED_BY_CUSTOMER';

-- R19: Only ACTIVE professionals
CREATE INDEX idx_professionals_active ON professionals (pro_id, city_id)
    WHERE status = 'ACTIVE';

-- ============================================================================
-- COVERING INDEXES (INCLUDE for Index-Only Scans)
-- ============================================================================

-- R02: Slot picker needs pro_id, full_name, rating from professionals
--      plus joins through pro_skills, pro_availability, bookings
CREATE INDEX idx_professionals_cover_slot ON professionals (city_id, status, pro_id)
    INCLUDE (full_name, rating)
    WHERE status = 'ACTIVE';

-- R03: My bookings - include service_id, scheduled_start, status, pro_id
CREATE INDEX idx_bookings_customer_cover ON bookings (customer_id, scheduled_start)
    INCLUDE (service_id, status, pro_id)
    WHERE scheduled_start >= '2026-07-01';

-- R04: Partner app jobs - include all selected columns for Index-Only Scan
CREATE INDEX idx_bookings_pro_cover_jobs ON bookings (pro_id, scheduled_start)
    INCLUDE (service_id, scheduled_end, pincode, status);

-- R05: Dispatch - include service_id, city_id for SELECT
CREATE INDEX idx_bookings_requested_cover ON bookings (status, scheduled_start)
    INCLUDE (service_id, city_id, booking_id)
    WHERE status = 'REQUESTED';

-- R07: Earnings - include price, discount, tip
CREATE INDEX idx_bookings_pro_cover_earnings ON bookings (pro_id, completed_at)
    INCLUDE (price, discount, tip)
    WHERE status = 'COMPLETED';

-- R14: Demand planning - include service_id for category join
CREATE INDEX idx_bookings_city_cover_category ON bookings (city_id, scheduled_start)
    INCLUDE (service_id);

-- R19: City report - covering index for subqueries
CREATE INDEX idx_bookings_pro_cover_report ON bookings (pro_id, status, scheduled_start)
    INCLUDE (completed_at)
    WHERE status = 'COMPLETED';

-- R24: Cancellation fees - include cancellation_fee
CREATE INDEX idx_bookings_cancellation_cover ON bookings (scheduled_start)
    INCLUDE (cancellation_fee)
    WHERE cancellation_fee > 0;

-- ============================================================================
-- GIN TRIGRAM INDEX (for ILIKE '%pattern%')
-- ============================================================================

-- R18: Reviews complaining about lateness - ILIKE '%late%'
CREATE INDEX idx_reviews_comment_trgm ON reviews USING GIN (comment gin_trgm_ops);

-- ============================================================================
-- ADDITIONAL SUPPORTING INDEXES (Foreign key join indexes)
-- PostgreSQL doesn't auto-create indexes on foreign keys
-- ============================================================================

CREATE INDEX idx_pro_skills_category ON pro_skills (category_id);
CREATE INDEX idx_bookings_service ON bookings (service_id);
CREATE INDEX idx_bookings_city ON bookings (city_id);
CREATE INDEX idx_bookings_customer ON bookings (customer_id);
CREATE INDEX idx_reschedules_booking ON reschedules (booking_id);
CREATE INDEX idx_reviews_booking ON reviews (booking_id);
CREATE INDEX idx_payouts_pro ON payouts (pro_id);

-- ============================================================================
-- INDEX STATISTICS REFRESH
-- ============================================================================

ANALYZE;
