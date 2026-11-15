-- ============================================================================
-- Urban Company Home Services Database
-- Checkpoint 1 (CP1): Seed Data Loading Script
-- Author: Chirag Tyagi (Group Lead)
-- Engine: PostgreSQL 15+ (psql)
-- Schema: uc
-- ============================================================================

SET search_path TO uc;

-- Note: Run this script via psql from the project root:
--   psql -d <database_name> -f sql/02_load_data.sql
-- Ensure seed_data.zip has been extracted so that seed_data/*.csv is available.

\echo 'Loading cities...'
\copy cities (city_id, city_name, state) FROM 'seed_data/cities.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading service_categories...'
\copy service_categories (category_id, category_name) FROM 'seed_data/service_categories.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading services...'
\copy services (service_id, category_id, service_name, duration_min, base_price, is_active) FROM 'seed_data/services.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading professionals...'
\copy professionals (pro_id, full_name, phone, city_id, gender, joined_on, rating, kyc_verified, status) FROM 'seed_data/professionals.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading pro_skills...'
\copy pro_skills (pro_id, category_id, certified_on) FROM 'seed_data/pro_skills.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading pro_availability...'
\copy pro_availability (pro_id, work_date, start_time, end_time) FROM 'seed_data/pro_availability.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading customers...'
\copy customers (customer_id, full_name, phone, email, city_id, plus_valid_until, created_at) FROM 'seed_data/customers.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading bookings...'
\copy bookings (booking_id, customer_id, service_id, pro_id, city_id, pincode, booked_at, scheduled_start, scheduled_end, started_at, completed_at, status, price, discount, cancellation_fee, tip, payment_method) FROM 'seed_data/bookings.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading reschedules...'
\copy reschedules (reschedule_id, booking_id, old_start, new_start, requested_by, reason, created_at) FROM 'seed_data/reschedules.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading reviews...'
\copy reviews (booking_id, rating_for_pro, comment, rating_for_customer, created_at) FROM 'seed_data/reviews.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading payouts...'
\copy payouts (payout_id, pro_id, week_start, jobs, gross_earnings, commission, net_payout, status, paid_at) FROM 'seed_data/payouts.csv' WITH (FORMAT csv, HEADER true);

\echo 'Gathering optimizer statistics...'
ANALYZE;

\echo 'Verifying record counts...'
SELECT 'cities' AS table_name, count(*) AS count FROM cities
UNION ALL SELECT 'service_categories', count(*) FROM service_categories
UNION ALL SELECT 'services', count(*) FROM services
UNION ALL SELECT 'professionals', count(*) FROM professionals
UNION ALL SELECT 'pro_skills', count(*) FROM pro_skills
UNION ALL SELECT 'pro_availability', count(*) FROM pro_availability
UNION ALL SELECT 'customers', count(*) FROM customers
UNION ALL SELECT 'bookings', count(*) FROM bookings
UNION ALL SELECT 'reschedules', count(*) FROM reschedules
UNION ALL SELECT 'reviews', count(*) FROM reviews
UNION ALL SELECT 'payouts', count(*) FROM payouts;
