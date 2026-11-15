-- ============================================================================
-- Urban Company Home Services Database
-- Checkpoint 1 (CP1): Production Schema Definition (DDL)
-- Author: Chirag Tyagi (Group Lead)
-- Engine: PostgreSQL 15+
-- Schema: uc
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS uc;
SET search_path TO uc;

-- Drop dependent tables in reverse topological order if re-running
DROP TABLE IF EXISTS payouts CASCADE;
DROP TABLE IF EXISTS reviews CASCADE;
DROP TABLE IF EXISTS reschedules CASCADE;
DROP TABLE IF EXISTS bookings CASCADE;
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS pro_availability CASCADE;
DROP TABLE IF EXISTS pro_skills CASCADE;
DROP TABLE IF EXISTS professionals CASCADE;
DROP TABLE IF EXISTS services CASCADE;
DROP TABLE IF EXISTS service_categories CASCADE;
DROP TABLE IF EXISTS cities CASCADE;

-- ----------------------------------------------------------------------------
-- 1. Cities
-- ----------------------------------------------------------------------------
CREATE TABLE cities (
    city_id     INT PRIMARY KEY,
    city_name   VARCHAR(50) NOT NULL UNIQUE,
    state       VARCHAR(50) NOT NULL
);

-- ----------------------------------------------------------------------------
-- 2. Service Categories
-- ----------------------------------------------------------------------------
CREATE TABLE service_categories (
    category_id     INT PRIMARY KEY,
    category_name   VARCHAR(50) NOT NULL UNIQUE
);

-- ----------------------------------------------------------------------------
-- 3. Services
-- ----------------------------------------------------------------------------
CREATE TABLE services (
    service_id      INT PRIMARY KEY,
    category_id     INT NOT NULL REFERENCES service_categories(category_id) ON DELETE RESTRICT,
    service_name    VARCHAR(100) NOT NULL UNIQUE,
    duration_min    INT NOT NULL CHECK (duration_min > 0),
    base_price      NUMERIC(10, 2) NOT NULL CHECK (base_price >= 0),
    is_active       BOOLEAN NOT NULL DEFAULT true
);

-- ----------------------------------------------------------------------------
-- 4. Professionals (Partners)
-- ----------------------------------------------------------------------------
CREATE TABLE professionals (
    pro_id          INT PRIMARY KEY,
    full_name       VARCHAR(100) NOT NULL,
    phone           VARCHAR(15) NOT NULL UNIQUE,
    city_id         INT NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    gender          CHAR(1) NOT NULL CHECK (gender IN ('M', 'F')),
    joined_on       DATE NOT NULL,
    rating          NUMERIC(3, 2) CHECK (rating IS NULL OR (rating >= 1.0 AND rating <= 5.0)),
    kyc_verified    BOOLEAN NOT NULL DEFAULT false,
    status          VARCHAR(20) NOT NULL CHECK (status IN ('ACTIVE', 'SUSPENDED', 'OFFBOARDED'))
);

-- ----------------------------------------------------------------------------
-- 5. Professional Skills (Certifications)
-- ----------------------------------------------------------------------------
CREATE TABLE pro_skills (
    pro_id          INT NOT NULL REFERENCES professionals(pro_id) ON DELETE CASCADE,
    category_id     INT NOT NULL REFERENCES service_categories(category_id) ON DELETE RESTRICT,
    certified_on    DATE NOT NULL,
    PRIMARY KEY (pro_id, category_id)
);

-- ----------------------------------------------------------------------------
-- 6. Professional Availability (Working Schedule)
-- ----------------------------------------------------------------------------
CREATE TABLE pro_availability (
    pro_id          INT NOT NULL REFERENCES professionals(pro_id) ON DELETE CASCADE,
    work_date       DATE NOT NULL,
    start_time      TIME NOT NULL,
    end_time        TIME NOT NULL,
    PRIMARY KEY (pro_id, work_date),
    CONSTRAINT chk_avail_time_order CHECK (end_time > start_time)
);

-- ----------------------------------------------------------------------------
-- 7. Customers
-- ----------------------------------------------------------------------------
CREATE TABLE customers (
    customer_id         INT PRIMARY KEY,
    full_name           VARCHAR(100) NOT NULL,
    phone               VARCHAR(15) NOT NULL UNIQUE,
    email               VARCHAR(100) UNIQUE,
    city_id             INT NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    plus_valid_until    DATE,
    created_at          TIMESTAMPTZ NOT NULL
);

-- ----------------------------------------------------------------------------
-- 8. Bookings
-- ----------------------------------------------------------------------------
CREATE TABLE bookings (
    booking_id          INT PRIMARY KEY,
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

    -- Business Rules & Temporal Constraints
    CONSTRAINT chk_booking_sched_order CHECK (scheduled_end > scheduled_start),
    CONSTRAINT chk_booking_actual_order CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at),
    CONSTRAINT chk_booking_tip_completed CHECK (tip IS NULL OR status = 'COMPLETED'),
    CONSTRAINT chk_booking_cancellation_fee CHECK (cancellation_fee = 0.00 OR status = 'CANCELLED_BY_CUSTOMER')
);

-- ----------------------------------------------------------------------------
-- 9. Reschedules
-- ----------------------------------------------------------------------------
CREATE TABLE reschedules (
    reschedule_id       INT PRIMARY KEY,
    booking_id          INT NOT NULL REFERENCES bookings(booking_id) ON DELETE CASCADE,
    old_start           TIMESTAMPTZ NOT NULL,
    new_start           TIMESTAMPTZ NOT NULL,
    requested_by        VARCHAR(20) NOT NULL CHECK (requested_by IN ('CUSTOMER', 'PRO')),
    reason              TEXT NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL
);

-- ----------------------------------------------------------------------------
-- 10. Reviews
-- ----------------------------------------------------------------------------
CREATE TABLE reviews (
    booking_id          INT PRIMARY KEY REFERENCES bookings(booking_id) ON DELETE CASCADE,
    rating_for_pro      INT NOT NULL CHECK (rating_for_pro BETWEEN 1 AND 5),
    comment             TEXT,
    rating_for_customer INT CHECK (rating_for_customer IS NULL OR rating_for_customer BETWEEN 1 AND 5),
    created_at          TIMESTAMPTZ NOT NULL
);

-- ----------------------------------------------------------------------------
-- 11. Payouts (Weekly Settlement)
-- ----------------------------------------------------------------------------
CREATE TABLE payouts (
    payout_id           INT PRIMARY KEY,
    pro_id              INT NOT NULL REFERENCES professionals(pro_id) ON DELETE RESTRICT,
    week_start          DATE NOT NULL CHECK (EXTRACT(ISODOW FROM week_start) = 1),
    jobs                INT NOT NULL CHECK (jobs >= 0),
    gross_earnings      NUMERIC(10, 2) NOT NULL CHECK (gross_earnings >= 0),
    commission          NUMERIC(10, 2) NOT NULL CHECK (commission >= 0),
    net_payout          NUMERIC(10, 2) NOT NULL CHECK (net_payout >= 0),
    status              VARCHAR(20) NOT NULL CHECK (status IN ('PENDING', 'PAID')),
    paid_at             TIMESTAMPTZ,

    -- Candidate Key: exactly one weekly payout per professional per billing week
    CONSTRAINT uq_pro_payout_week UNIQUE (pro_id, week_start),
    CONSTRAINT chk_payout_net_calc CHECK (net_payout = (gross_earnings - commission)),
    CONSTRAINT chk_payout_paid_timestamp CHECK (
        (status = 'PAID' AND paid_at IS NOT NULL) OR
        (status = 'PENDING' AND paid_at IS NULL)
    )
);
