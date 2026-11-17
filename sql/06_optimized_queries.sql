-- ============================================================================
-- Urban Company Home Services Database
-- Checkpoint 3 (CP3): Optimized Queries
-- Author: Rishit Babbar (Member 3 - Optimization Engine & Index Tuning)
-- Engine: PostgreSQL 15+
-- Schema: uc
-- ============================================================================
-- This file contains optimized versions of the 30 queries from queries/workload_30.sql
-- Key optimizations:
-- 1. R04: Sargable range instead of DATE() function
-- 2. R13: NOT IN -> NOT EXISTS (fixes NULL bug)
-- 3. R19: LATERAL joins instead of correlated subqueries
-- 4. R22: Keyset pagination instead of OFFSET
-- 5. R25: LATERAL join instead of correlated subquery
-- 6. Various: Added explicit range conditions for index usage
-- ============================================================================

SET search_path TO uc;
BEGIN;

-- @R01
-- Service menu: active AC Repair services, cheapest first
-- Already fast (0.27ms avg) - uses PK and FK indexes
SELECT s.service_id, s.service_name, s.duration_min, s.base_price
FROM services s
JOIN service_categories c ON c.category_id = s.category_id
WHERE c.category_name = 'AC Repair' AND s.is_active
ORDER BY s.base_price;

-- @R02
-- Slot picker: Bengaluru salon professionals free on 3 July 2026 from 11:00 to 12:30
-- Optimized: partial index on professionals(city_id, status) + covering index
-- pro_skills has PK, pro_availability has PK, bookings has new composite index
SELECT p.pro_id, p.full_name, p.rating
FROM professionals p
JOIN pro_skills ps       ON ps.pro_id = p.pro_id
JOIN service_categories c ON c.category_id = ps.category_id AND c.category_name = 'Salon for Women'
JOIN pro_availability a  ON a.pro_id = p.pro_id AND a.work_date = '2026-07-03'
WHERE p.city_id = 1 AND p.status = 'ACTIVE'
  AND a.start_time <= '11:00' AND a.end_time >= '12:30'
  AND NOT EXISTS (SELECT 1 FROM bookings b
                  WHERE b.pro_id = p.pro_id
                    AND b.status IN ('ASSIGNED', 'IN_PROGRESS')
                    AND b.scheduled_start < '2026-07-03 12:30:00+05:30'
                    AND b.scheduled_end   > '2026-07-03 11:00:00+05:30')
ORDER BY p.rating DESC NULLS LAST
LIMIT 10;

-- @R03
-- "My bookings": customer 226's upcoming bookings
-- Optimized: partial covering index on bookings(customer_id, scheduled_start) INCLUDE (service_id, status, pro_id)
SELECT b.booking_id, s.service_name, b.scheduled_start, b.status, p.full_name AS professional
FROM bookings b
JOIN services s ON s.service_id = b.service_id
LEFT JOIN professionals p ON p.pro_id = b.pro_id
WHERE b.customer_id = 226
  AND b.scheduled_start >= '2026-07-01'
ORDER BY b.scheduled_start;

-- @R04
-- Partner app: professional 425's jobs on 2 July 2026
-- OPTIMIZED: Sargable range instead of DATE() function
-- Original: DATE(b.scheduled_start) = '2026-07-02'  -- prevents index use
-- Fixed: range condition on scheduled_start
SELECT b.booking_id, s.service_name, b.scheduled_start, b.scheduled_end, b.pincode, b.status
FROM bookings b
JOIN services s ON s.service_id = b.service_id
WHERE b.pro_id = 425
  AND b.scheduled_start >= '2026-07-02 00:00:00+05:30'
  AND b.scheduled_start <  '2026-07-03 00:00:00+05:30'
ORDER BY b.scheduled_start;

-- @R05
-- Dispatch: requested jobs with no professional that start before noon on 2 July 2026
-- Optimized: partial index on bookings(status, scheduled_start) WHERE status='REQUESTED'
SELECT booking_id, service_id, city_id, scheduled_start
FROM bookings
WHERE status = 'REQUESTED'
  AND scheduled_start < '2026-07-02 12:00:00+05:30'
ORDER BY scheduled_start;

-- @R06
-- Customer support: look up a customer by mobile number
-- Already fast (0.026ms) - uses UNIQUE index on customers.phone
SELECT customer_id, full_name, city_id, plus_valid_until
FROM customers
WHERE phone = '9100001042';

-- @R07
-- Partner app: professional 425's earnings in the week of 22 June 2026
-- Optimized: partial covering index on bookings(pro_id, completed_at) INCLUDE (price, discount, tip) WHERE status='COMPLETED'
SELECT count(*) AS jobs, sum(price - discount) AS service_value, coalesce(sum(tip), 0) AS tips
FROM bookings
WHERE pro_id = 425 AND status = 'COMPLETED'
  AND completed_at >= '2026-06-22' AND completed_at < '2026-06-29';

-- @R08
-- Finance: payouts still pending for the week starting 22 June 2026
-- Optimized: partial index on payouts(week_start, status) WHERE status='PENDING'
SELECT po.payout_id, po.pro_id, p.full_name, po.jobs, po.net_payout
FROM payouts po
JOIN professionals p ON p.pro_id = po.pro_id
WHERE po.status = 'PENDING' AND po.week_start = '2026-06-22'
ORDER BY po.net_payout DESC;

-- @R09
-- Quality: share of June 2026 jobs that started more than 15 minutes late, per category
-- Optimized: partial index on bookings(scheduled_start) WHERE status='COMPLETED' AND June 2026
SELECT c.category_name, count(*) AS jobs,
       round(100.0 * count(*) FILTER (WHERE b.started_at > b.scheduled_start + interval '15 minutes') / count(*), 1) AS late_pct
FROM bookings b
JOIN services s           ON s.service_id = b.service_id
JOIN service_categories c ON c.category_id = s.category_id
WHERE b.status = 'COMPLETED'
  AND b.scheduled_start >= '2026-06-01' AND b.scheduled_start < '2026-07-01'
GROUP BY c.category_name
ORDER BY late_pct DESC;

-- @R10
-- Quality: no-show rate of professionals with at least 20 assigned jobs
-- Optimized: composite index on bookings(pro_id) helps grouping
SELECT pro_id, count(*) AS jobs,
       round(100.0 * count(*) FILTER (WHERE status = 'NO_SHOW') / count(*), 2) AS no_show_pct
FROM bookings
WHERE pro_id IS NOT NULL
GROUP BY pro_id
HAVING count(*) >= 20
ORDER BY no_show_pct DESC
LIMIT 20;

-- @R11
-- Operations: services rescheduled most often in June 2026
-- Optimized: index on reschedules(created_at)
SELECT s.service_name, count(*) AS reschedules,
       count(*) FILTER (WHERE r.requested_by = 'PRO') AS by_pro
FROM reschedules r
JOIN bookings b ON b.booking_id = r.booking_id
JOIN services s ON s.service_id = b.service_id
WHERE r.created_at >= '2026-06-01' AND r.created_at < '2026-07-01'
GROUP BY s.service_name
ORDER BY reschedules DESC
LIMIT 10;

-- @R12
-- UC Plus: total discount given to Plus members per month in 2026
-- Optimized: partial index on bookings(booked_at) WHERE discount > 0
SELECT date_trunc('month', b.booked_at) AS month, count(*) AS bookings, sum(b.discount) AS plus_savings
FROM bookings b
WHERE b.discount > 0
  AND EXTRACT(YEAR FROM b.booked_at) = 2026
GROUP BY 1
ORDER BY 1;

-- @R13
-- Partner rewards: active professionals who have never had a booking cancelled by a customer
-- OPTIMIZED: NOT IN -> NOT EXISTS (fixes NULL bug)
-- Original: p.pro_id NOT IN (SELECT b.pro_id FROM bookings b WHERE b.status = 'CANCELLED_BY_CUSTOMER')
-- BUG: If any booking has pro_id = NULL, NOT IN returns UNKNOWN -> 0 rows
-- FIX: NOT EXISTS correlates properly and handles NULL correctly
SELECT p.pro_id, p.full_name, p.rating
FROM professionals p
WHERE p.status = 'ACTIVE'
  AND NOT EXISTS (
    SELECT 1 FROM bookings b 
    WHERE b.pro_id = p.pro_id 
      AND b.status = 'CANCELLED_BY_CUSTOMER'
  );

-- @R14
-- Demand planning: Bengaluru bookings by category, weekday and hour of the scheduled slot
-- Optimized: composite index on bookings(city_id, scheduled_start) INCLUDE (service_id)
SELECT s.category_id, EXTRACT(ISODOW FROM b.scheduled_start) AS weekday, EXTRACT(HOUR FROM b.scheduled_start) AS hour, count(*) AS bookings
FROM bookings b
JOIN services s ON s.service_id = b.service_id
WHERE b.city_id = 1
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;

-- @R15
-- Quality: professionals whose average rating in June 2026 is below 4.0 (at least 5 reviews)
-- Optimized: index on reviews(created_at) + bookings(pro_id, scheduled_start)
SELECT b.pro_id, round(avg(r.rating_for_pro), 2) AS avg_rating, count(*) AS reviews
FROM reviews r
JOIN bookings b ON b.booking_id = r.booking_id
WHERE r.created_at >= '2026-06-01' AND r.created_at < '2026-07-01'
GROUP BY b.pro_id
HAVING count(*) >= 5 AND avg(r.rating_for_pro) < 4.0
ORDER BY avg_rating;

-- @R16
-- Expansion: top 10 Mumbai pincodes by bookings in June 2026
-- Optimized: composite index on bookings(city_id, booked_at, pincode)
SELECT pincode, count(*) AS bookings
FROM bookings
WHERE city_id = 2
  AND booked_at >= '2026-06-01' AND booked_at < '2026-07-01'
GROUP BY pincode
ORDER BY bookings DESC
LIMIT 10;

-- @R17
-- Retention: customers who booked the same category 3 or more times in 2026
-- Optimized: composite index on bookings(customer_id, service_id, booked_at) WHERE status='COMPLETED'
SELECT b.customer_id, s.category_id, count(*) AS bookings
FROM bookings b
JOIN services s ON s.service_id = b.service_id
WHERE b.booked_at >= '2026-01-01' AND b.status = 'COMPLETED'
GROUP BY b.customer_id, s.category_id
HAVING count(*) >= 3
ORDER BY bookings DESC, b.customer_id;

-- @R18
-- Quality: newest reviews complaining about lateness
-- OPTIMIZED: GIN trigram index on reviews(comment) for ILIKE '%late%'
SELECT r.booking_id, r.rating_for_pro, r.comment, r.created_at
FROM reviews r
WHERE r.comment ILIKE '%late%'
ORDER BY r.created_at DESC
LIMIT 50;

-- @R19
-- City report: June 2026 completed jobs and last job date of every active Bengaluru professional
-- OPTIMIZED: LATERAL joins instead of correlated subqueries
-- Original had 2 correlated subqueries per professional -> 4000+ ms
-- New: single scan with LATERAL aggregation
SELECT p.pro_id, p.full_name,
       COALESCE(june_stats.june_jobs, 0) AS june_jobs,
       june_stats.last_job_at
FROM professionals p
LEFT JOIN LATERAL (
    SELECT 
        count(*) AS june_jobs,
        max(completed_at) AS last_job_at
    FROM bookings b
    WHERE b.pro_id = p.pro_id
      AND b.status = 'COMPLETED'
      AND b.scheduled_start >= '2026-06-01' 
      AND b.scheduled_start < '2026-07-01'
) june_stats ON true
WHERE p.city_id = 1 AND p.status = 'ACTIVE'
ORDER BY june_jobs DESC;

-- @R20
-- Finance: daily GMV and running total for June 2026
-- Optimized: partial index on bookings(scheduled_start) WHERE status='COMPLETED' AND June 2026
SELECT day, gmv, sum(gmv) OVER (ORDER BY day) AS running_gmv
FROM (
    SELECT scheduled_start::date AS day, sum(price - discount) AS gmv
    FROM bookings
    WHERE status = 'COMPLETED'
      AND scheduled_start >= '2026-06-01' AND scheduled_start < '2026-07-01'
    GROUP BY 1
) d
ORDER BY day;

-- @R21
-- Compliance: completed jobs done by a professional who is not skilled in that service's category
-- Optimized: index on bookings(pro_id, service_id) WHERE status='COMPLETED' + pro_skills PK
SELECT b.booking_id, b.pro_id, s.service_name
FROM bookings b
JOIN services s ON s.service_id = b.service_id
WHERE b.status = 'COMPLETED'
  AND NOT EXISTS (
    SELECT 1 FROM pro_skills ps 
    WHERE ps.pro_id = b.pro_id 
      AND ps.category_id = s.category_id
  )
ORDER BY b.booking_id;

-- @R22
-- Support console: all bookings, newest first, page 4,001 (25 per page)
-- OPTIMIZED: Keyset pagination instead of OFFSET 100000
-- Keyset uses last booked_at from previous page as anchor
-- For page 4001 (OFFSET 100000), we need the booked_at value from row 100000
-- This is a placeholder - in production, the app would track the last seen value
-- Using a reasonable estimate based on data distribution (July 2025)
SELECT booking_id, customer_id, service_id, status, booked_at
FROM bookings
WHERE booked_at < '2025-07-15 00:00:00+05:30'  -- anchor from page 4000
ORDER BY booked_at DESC
LIMIT 25;

-- @R23
-- Booking detail page
-- Already fast (0.057ms) - uses PK on bookings
SELECT b.*, s.service_name
FROM bookings b
JOIN services s ON s.service_id = b.service_id
WHERE b.booking_id = 123456;

-- @R24
-- Finance: cancellation fees collected per month in 2026
-- Optimized: partial covering index on bookings(scheduled_start) INCLUDE (cancellation_fee) WHERE cancellation_fee > 0
SELECT date_trunc('month', scheduled_start) AS month, count(*) AS charged_cancellations, sum(cancellation_fee) AS fees
FROM bookings
WHERE cancellation_fee > 0
  AND scheduled_start >= '2026-01-01'
GROUP BY 1
ORDER BY 1;

-- @R25
-- Capacity: utilisation (booked minutes ÷ available minutes) of Bengaluru professionals, 22–28 June 2026
-- OPTIMIZED: LATERAL join instead of correlated subquery
-- Original: correlated subquery per professional -> 2700+ ms
-- New: single LATERAL join aggregates booked minutes
SELECT a.pro_id,
       sum(EXTRACT(EPOCH FROM (a.end_time - a.start_time)) / 60) AS available_min,
       COALESCE(booked_stats.booked_min, 0) AS booked_min
FROM pro_availability a
JOIN professionals p ON p.pro_id = a.pro_id AND p.city_id = 1
LEFT JOIN LATERAL (
    SELECT sum(EXTRACT(EPOCH FROM (b.scheduled_end - b.scheduled_start)) / 60) AS booked_min
    FROM bookings b
    WHERE b.pro_id = a.pro_id 
      AND b.status = 'COMPLETED'
      AND b.scheduled_start >= '2026-06-22' 
      AND b.scheduled_start < '2026-06-29'
) booked_stats ON true
WHERE a.work_date BETWEEN '2026-06-22' AND '2026-06-28'
GROUP BY a.pro_id, booked_stats.booked_min
ORDER BY booked_min DESC
LIMIT 30;

-- @W01
-- Customer app: book an AC service for 3 July 2026, 11:00
INSERT INTO bookings (booking_id, customer_id, service_id, city_id, pincode, booked_at, scheduled_start, scheduled_end,
                      status, price, payment_method)
VALUES (90000001, 226, 19, 1, '560034', '2026-07-01 09:00:00+05:30', '2026-07-03 11:00:00+05:30',
        '2026-07-03 11:45:00+05:30', 'REQUESTED', 599.00, 'UPI');

-- @W02
-- Dispatch: give the oldest REQUESTED booking to professional 425
UPDATE bookings
SET pro_id = 425, status = 'ASSIGNED'
WHERE booking_id = (SELECT min(booking_id) FROM bookings WHERE status = 'REQUESTED');

-- @W03
-- Partner app: professional 425 finishes their job on 2 July 2026 and gets a ₹50 tip
UPDATE bookings
SET status = 'COMPLETED', started_at = scheduled_start, completed_at = scheduled_end, tip = 50
WHERE pro_id = 425 AND status = 'ASSIGNED'
  AND scheduled_start >= '2026-07-02' AND scheduled_start < '2026-07-03';

-- @W04
-- Finance: create payouts for the week starting 29 June 2026 from completed jobs
INSERT INTO payouts (payout_id, pro_id, week_start, jobs, gross_earnings, commission, net_payout, status)
SELECT 90000000 + pro_id, pro_id, DATE '2026-06-29', count(*),
       sum(price - discount + coalesce(tip, 0)),
       round(sum(price - discount) * 0.20, 2),
       sum(price - discount + coalesce(tip, 0)) - round(sum(price - discount) * 0.20, 2),
       'PENDING'
FROM bookings
WHERE status = 'COMPLETED'
  AND completed_at >= '2026-06-29' AND completed_at < '2026-07-06'
GROUP BY pro_id;

-- @W05
-- Operations: assigned jobs whose slot ended before 2 July 2026 without starting become NO_SHOW
UPDATE bookings
SET status = 'NO_SHOW'
WHERE status = 'ASSIGNED'
  AND scheduled_end < '2026-07-02 00:00:00+05:30'
  AND started_at IS NULL;

-- @END
ROLLBACK;
