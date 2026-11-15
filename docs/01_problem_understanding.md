# Problem Understanding & Business Requirements Analysis

**Course:** Database Management Systems · **Phase:** 1 (CP1)  
**Author:** Chirag Tyagi (Group Lead, Enrollment No: 2501010126)  
**Project:** Urban Company Home Services Database Engineering

---

## 1. Executive Summary & Problem Breakdown (P1–P8)

Urban Company operates a two-sided marketplace connecting homeowners with certified service professionals across 10 major metropolitan cities. The legacy data architecture lacks formal schema enforcement, normalized boundaries, and indexing strategies, causing operational bottlenecks across consumer apps and back-office pipelines. Below is the structured business analysis of problems P1 through P8.

| # | Business Problem Description | Impacted Stakeholders | Workload Type | Related Queries | SLA Performance Target |
|---|-----------------------------|-----------------------|---------------|-----------------|------------------------|
| **P1** | **Slow Service Discovery & Conflict-Free Slot Booking**<br>Customers browsing services face latency. Slot availability requires verifying multi-category partner certifications, daily working hours, and preventing double-booking overlaps. | Customer, Service Professional (Partner) | Customer-Facing / Real-Time (OLTP) | `R01`, `R02`, `W01` | **< 5 ms** |
| **P2** | **Delayed Customer History & Support Lookups**<br>Consumers checking upcoming appointments and support agents handling escalations by customer phone number experience query timeouts under heavy read concurrency. | Customer, Support Team | Customer-Facing / Real-Time (OLTP) | `R03`, `R06`, `R22`, `R23` | **< 5 ms** (R03, R06, R23)<br>**< 250 ms** (R22 console) |
| **P3** | **Partner App Field Latency**<br>Professionals on field devices struggle with slow retrieval of daily job schedules, real-time earnings, and status transitions upon service completion with tips. | Service Professional (Partner) | Real-Time Field App (OLTP) | `R04`, `R07`, `W03` | **< 5 ms** |
| **P4** | **Dispatch Pipeline Lag on Unassigned Slots**<br>Automated/manual dispatch engines fail to promptly surface unassigned `REQUESTED` jobs nearing their scheduled start times, resulting in SLA breaches and unfilled demand. | Dispatch / Operations Team | Real-Time Operations (OLTP) | `R05`, `W02`, `W05` | **< 5 ms** (R05, W02)<br>**< 250 ms** (W05 batch update) |
| **P5** | **Flawed Partner Rewards Due to NULL Propagation**<br>The partner rewards query intended to identify zero-cancellation top performers returns 0 rows due to a three-valued logic flaw (`NOT IN` against a subquery containing NULL `pro_id`s). | Partner Success, Top Professionals | Interactive Operations / Analytics | `R13` | **< 250 ms** |
| **P6** | **Quality Assurance & Compliance Report Timeouts**<br>Audits evaluating delayed service starts (>15 min), repeated partner no-shows, negative review sentiment analysis, and uncertified service executions exceed report timeout limits. | Quality Team, Compliance, Operations | Reporting / Analytics (OLAP) | `R09`, `R10`, `R15`, `R18`, `R21` | **< 5,000 ms** (Reports)<br>**< 250 ms** (R18 search) |
| **P7** | **Financial Reconciliation & Settlement Delays**<br>Weekly payout generation, UC Plus subscription discount tallies, cancellation fee aggregations, and daily GMV window calculations overload the transactional engine. | Finance Team, UC Plus Team, Partner Accounts | Financial Batch & Reporting | `R08`, `R12`, `R20`, `R24`, `W04` | **< 250 ms** (R08 pending)<br>**< 1,000 ms** (W04 batch)<br>**< 5,000 ms** (R12, R20, R24) |
| **P8** | **Capacity Planning & Growth Bottlenecks (20× Scale)**<br>Heat-maps of regional pincode demand, reschedule driver diagnostics, cohort retention, and labor utilization metrics are too slow to guide city expansion and 20× volume growth. | City Expansion, Regional GM, Capacity Planning | Reporting / Strategic Analytics (OLAP) | `R11`, `R14`, `R16`, `R17`, `R19`, `R25` | **< 250 ms** (R11, R16)<br>**< 5,000 ms** (R14, R17, R19, R25) |

---

## 2. Workload Classification & Performance SLAs

1. **Customer-Facing / Real-Time OLTP (`< 5 ms`):**
   - Direct user operations (`R01`, `R02`, `R03`, `R04`, `R05`, `R06`, `R07`, `R23`, `W01`, `W02`, `W03`).
   - Must execute via point lookups or narrow index range scans. Full table scans (`Seq Scan`) are unacceptable.

2. **Interactive Operations Tools (`< 250 ms`):**
   - Internal dispatch, operational dashboards, and support search screens (`R08`, `R11`, `R13`, `R16`, `R18`, `R22`, `W05`).
   - Must leverage selective composite indexes, keyset pagination, and text trigram indexes (`pg_trgm`).

3. **Reporting, Batch & Strategic Analytics (`< 1,000 ms – 5,000 ms`):**
   - Complex multi-way joins, aggregations, window functions, and financial accounting (`R09`, `R10`, `R12`, `R14`, `R15`, `R17`, `R19`, `R20`, `R21`, `R24`, `R25`, `W04`).
   - Target execution under 5 seconds on seed data and large data rounds via proper pruning and covering indexes.

---

## 3. Core Architectural & Business Assumptions

1. **Temporal & Timezone Consistency:** All booking events, availability slots, and payouts operate in Indian Standard Time (`UTC+05:30`). Storing timestamps as `TIMESTAMPTZ` guarantees seamless daylight-independent precision.
2. **Strict Partner Availability Model:** A professional can only be assigned to a booking if they possess a valid certification for that service category (`pro_skills`), have an explicit working schedule defined for that date (`pro_availability`), and do not have an overlapping active booking (`ASSIGNED` or `IN_PROGRESS`).
3. **Financial Integrity & Commission Formula:** Urban Company collects a standard 20% platform commission on net service charges (`price - discount`), while tips are credited 100% to the partner (`net_payout = (price - discount) * 0.80 + tip`).
4. **Billing Cadence:** Partner payouts settle on a strict weekly cycle starting Monday (`week_start` ISODOW = 1).
5. **Cancellation Fee Policy:** Cancellation fees are strictly levied on customer-initiated cancellations (`CANCELLED_BY_CUSTOMER`). Partner-cancelled or no-show bookings incur zero cancellation fee to the customer.
6. **Data Lifecycle & Soft Deletes:** Historical bookings and financial records must remain immutable for audit compliance. If a partner or customer profile status changes (`OFFBOARDED`/`SUSPENDED`), foreign keys on transactional tables must preserve historical references (`ON DELETE SET NULL` or `RESTRICT`).
