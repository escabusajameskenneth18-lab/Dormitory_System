-- ================================================================
--  DORMITORY RESERVATION MANAGEMENT SYSTEM — dorm_db
--  Built for: dormitory1_system_hashed (NetBeans / Java Swing)
--  Compatible: XAMPP MySQL 5.7 / 8.x
--
--  HOW TO IMPORT
--  ─────────────
--  Option A (phpMyAdmin):
--    1. Open http://localhost/phpmyadmin
--    2. Click "Import" tab → Choose File → select this file → Go
--
--  Option B (command line):
--    mysql -u root -p < dorm_db.sql
--
--  LOGIN CREDENTIALS (after import)
--  ──────────────────────────────────
--  Username: admin     Password: admin123
--  Username: manager   Password: manager123
--  Username: staff     Password: staff123
--  (All passwords stored as SHA-256 hashes — matches PasswordUtil.java)
-- ================================================================

-- ──────────────────────────────────────────────────────────────
--  1. CREATE DATABASE
-- ──────────────────────────────────────────────────────────────
DROP DATABASE IF EXISTS dorm_db;
CREATE DATABASE dorm_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE dorm_db;

-- ──────────────────────────────────────────────────────────────
--  2. TABLES
-- ──────────────────────────────────────────────────────────────

-- 2.1  USERS  (admin accounts — passwords stored as SHA-256 hex)
-- UserDAO.java: SELECT id, username, full_name, role, password FROM users WHERE username = ?
-- PasswordUtil.java: SHA-256 hash comparison on Java side
CREATE TABLE users (
    id          INT           NOT NULL AUTO_INCREMENT PRIMARY KEY,
    username    VARCHAR(50)   NOT NULL UNIQUE,
    password    VARCHAR(64)   NOT NULL,
    full_name   VARCHAR(100)  NOT NULL,
    role        ENUM('Admin','Manager','Staff') NOT NULL DEFAULT 'Staff',
    created_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- 2.2  STUDENTS
-- StudentDAO.java: SELECT student_id, full_name, course, email, contact, gender, address FROM students
CREATE TABLE students (
    student_id  VARCHAR(20)   NOT NULL PRIMARY KEY,
    full_name   VARCHAR(100)  NOT NULL,
    course      VARCHAR(100),
    email       VARCHAR(100),
    contact     VARCHAR(20),
    gender      ENUM('Male','Female','Other'),
    address     TEXT,
    created_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- 2.3  ROOMS
-- RoomDAO.java: SELECT room_no, room_type, capacity, floor_no, monthly_rate, status, reserved_by FROM rooms
CREATE TABLE rooms (
    room_no       VARCHAR(10)     NOT NULL PRIMARY KEY,
    room_type     VARCHAR(50)     NOT NULL,
    capacity      INT             NOT NULL DEFAULT 1,
    floor_no      INT             NOT NULL DEFAULT 1,
    monthly_rate  DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    status        ENUM('Available','Booked','Under Maintenance') NOT NULL DEFAULT 'Available',
    reserved_by   VARCHAR(100)    NULL,
    updated_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP
                                  ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- 2.4  RESERVATIONS
-- ReservationDAO.java: reads res_code, student_name, student_id_ref, room_no, status,
--                      date_in, date_out, created_by, created_at
-- ReportsView.java "Reservation History": also reads updated_at
CREATE TABLE reservations (
    id              INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    res_code        VARCHAR(15)  NOT NULL UNIQUE,
    student_name    VARCHAR(100) NOT NULL,
    student_id_ref  VARCHAR(20)  NOT NULL,
    room_no         VARCHAR(10)  NOT NULL,
    status          ENUM('Pending','Approved','Rejected','Checked-In','Checked-Out','Cancelled')
                                 NOT NULL DEFAULT 'Pending',
    date_in         DATE         NULL,
    date_out        DATE         NULL,
    notes           TEXT         NULL,
    approved_by     VARCHAR(50)  NULL,
    approved_at     DATETIME     NULL,
    created_by      VARCHAR(50)  NULL,
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                 ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (room_no)        REFERENCES rooms(room_no)       ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (student_id_ref) REFERENCES students(student_id) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ──────────────────────────────────────────────────────────────
--  3. VIEW  (required by DashboardView.java)
--
--  DashboardView.java:
--    rs = st.executeQuery("SELECT * FROM vw_dashboard_stats");
--    totalRoomsVal   ← total_rooms
--    availVal        ← available_rooms
--    bookedVal       ← booked_rooms
--    maintenanceVal  ← maintenance_rooms
--    pendingVal      ← pending_res
--    studVal         ← total_students
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_dashboard_stats AS
SELECT
    (SELECT COUNT(*) FROM rooms)                                          AS total_rooms,
    (SELECT COUNT(*) FROM rooms        WHERE status = 'Available')        AS available_rooms,
    (SELECT COUNT(*) FROM rooms        WHERE status = 'Booked')           AS booked_rooms,
    (SELECT COUNT(*) FROM rooms        WHERE status = 'Under Maintenance') AS maintenance_rooms,
    (SELECT COUNT(*) FROM reservations WHERE status = 'Pending')          AS pending_res,
    (SELECT COUNT(*) FROM students)                                        AS total_students;

-- ──────────────────────────────────────────────────────────────
--  4. STORED PROCEDURES
--
--  ReservationDAO.callProc() dispatch:
--    "sp_approve_reservation"  → CALL sp_approve_reservation(p_res_code, p_approved_by)
--    "sp_reject_reservation"   → CALL sp_reject_reservation(p_res_code)
--    "sp_cancel_reservation"   → CALL sp_cancel_reservation(p_res_code)
--    "sp_checkin"              → CALL sp_checkin(p_res_code)
--    "sp_checkout"             → CALL sp_checkout(p_res_code)
-- ──────────────────────────────────────────────────────────────

DELIMITER $$

-- ════════════════════════════════════════════════════════════
--  sp_approve_reservation
--  Pending → Approved  |  room status → Booked
-- ════════════════════════════════════════════════════════════
DROP PROCEDURE IF EXISTS sp_approve_reservation$$
CREATE PROCEDURE sp_approve_reservation(
    IN p_res_code    VARCHAR(15),
    IN p_approved_by VARCHAR(50)
)
BEGIN
    DECLARE v_room_no      VARCHAR(10);
    DECLARE v_student_name VARCHAR(100);
    DECLARE v_status       VARCHAR(20);

    SELECT room_no, student_name, status
      INTO v_room_no, v_student_name, v_status
      FROM reservations
     WHERE res_code = p_res_code;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Reservation not found.';
    END IF;

    IF v_status <> 'Pending' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Only Pending reservations can be approved.';
    END IF;

    UPDATE reservations
       SET status      = 'Approved',
           approved_by = p_approved_by,
           approved_at = NOW()
     WHERE res_code = p_res_code;

    UPDATE rooms
       SET status      = 'Booked',
           reserved_by = v_student_name
     WHERE room_no = v_room_no;
END$$


-- ════════════════════════════════════════════════════════════
--  sp_reject_reservation
--  Pending → Rejected  |  room freed if no other active booking
-- ════════════════════════════════════════════════════════════
DROP PROCEDURE IF EXISTS sp_reject_reservation$$
CREATE PROCEDURE sp_reject_reservation(
    IN p_res_code VARCHAR(15)
)
BEGIN
    DECLARE v_room_no VARCHAR(10);
    DECLARE v_status  VARCHAR(20);

    SELECT room_no, status
      INTO v_room_no, v_status
      FROM reservations
     WHERE res_code = p_res_code;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Reservation not found.';
    END IF;

    IF v_status <> 'Pending' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Only Pending reservations can be rejected.';
    END IF;

    UPDATE reservations
       SET status = 'Rejected'
     WHERE res_code = p_res_code;

    UPDATE rooms
       SET status      = 'Available',
           reserved_by = NULL
     WHERE room_no = v_room_no
       AND NOT EXISTS (
           SELECT 1 FROM reservations
            WHERE room_no  = v_room_no
              AND res_code <> p_res_code
              AND status   IN ('Pending','Approved','Checked-In')
       );
END$$


-- ════════════════════════════════════════════════════════════
--  sp_cancel_reservation
--  Any active status → Cancelled  |  room freed if no other active booking
--  Called from both RoomReservationView and ReservationApprovalView
-- ════════════════════════════════════════════════════════════
DROP PROCEDURE IF EXISTS sp_cancel_reservation$$
CREATE PROCEDURE sp_cancel_reservation(
    IN p_res_code VARCHAR(15)
)
BEGIN
    DECLARE v_room_no VARCHAR(10);
    DECLARE v_status  VARCHAR(20);

    SELECT room_no, status
      INTO v_room_no, v_status
      FROM reservations
     WHERE res_code = p_res_code;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Reservation not found.';
    END IF;

    IF v_status IN ('Checked-Out','Cancelled','Rejected') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'This reservation cannot be cancelled.';
    END IF;

    UPDATE reservations
       SET status = 'Cancelled'
     WHERE res_code = p_res_code;

    UPDATE rooms
       SET status      = 'Available',
           reserved_by = NULL
     WHERE room_no = v_room_no
       AND NOT EXISTS (
           SELECT 1 FROM reservations
            WHERE room_no  = v_room_no
              AND res_code <> p_res_code
              AND status   IN ('Pending','Approved','Checked-In')
       );
END$$


-- ════════════════════════════════════════════════════════════
--  sp_checkin
--  Approved → Checked-In
-- ════════════════════════════════════════════════════════════
DROP PROCEDURE IF EXISTS sp_checkin$$
CREATE PROCEDURE sp_checkin(
    IN p_res_code VARCHAR(15)
)
BEGIN
    DECLARE v_status VARCHAR(20);

    SELECT status INTO v_status
      FROM reservations
     WHERE res_code = p_res_code;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Reservation not found.';
    END IF;

    IF v_status <> 'Approved' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Only Approved reservations can be checked in.';
    END IF;

    UPDATE reservations
       SET status = 'Checked-In'
     WHERE res_code = p_res_code;
END$$


-- ════════════════════════════════════════════════════════════
--  sp_checkout
--  Checked-In → Checked-Out  |  room → Available
-- ════════════════════════════════════════════════════════════
DROP PROCEDURE IF EXISTS sp_checkout$$
CREATE PROCEDURE sp_checkout(
    IN p_res_code VARCHAR(15)
)
BEGIN
    DECLARE v_room_no VARCHAR(10);
    DECLARE v_status  VARCHAR(20);

    SELECT room_no, status
      INTO v_room_no, v_status
      FROM reservations
     WHERE res_code = p_res_code;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Reservation not found.';
    END IF;

    IF v_status <> 'Checked-In' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Only Checked-In reservations can be checked out.';
    END IF;

    UPDATE reservations
       SET status = 'Checked-Out'
     WHERE res_code = p_res_code;

    UPDATE rooms
       SET status      = 'Available',
           reserved_by = NULL
     WHERE room_no = v_room_no;
END$$


DELIMITER ;


-- ──────────────────────────────────────────────────────────────
--  5. SEED DATA
-- ──────────────────────────────────────────────────────────────

-- ── Users  (SHA-256 hashed passwords — generated by PasswordUtil.hash()) ──
-- PasswordUtil.hash("admin123")   = 240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9
-- PasswordUtil.hash("manager123") = 866485796cfa8d7c0cf7111640205b83076433547577511d81f8030ae99ecea5
-- PasswordUtil.hash("staff123")   = 10176e7b7b24d317acfcf8d2064cfd2f24e154f7b5a96603077d5ef813d6a6b6
INSERT INTO users (username, password, full_name, role) VALUES
('admin',
 '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9',
 'System Administrator', 'Admin'),
('manager',
 '866485796cfa8d7c0cf7111640205b83076433547577511d81f8030ae99ecea5',
 'Dormitory Manager', 'Manager'),
('staff',
 '10176e7b7b24d317acfcf8d2064cfd2f24e154f7b5a96603077d5ef813d6a6b6',
 'Front Desk Staff', 'Staff');

-- ── Rooms ──
INSERT INTO rooms (room_no, room_type, capacity, floor_no, monthly_rate, status) VALUES
('101', 'Single',           1, 1, 3500.00, 'Available'),
('102', 'Single',           1, 1, 3500.00, 'Available'),
('103', 'Double',           2, 1, 5000.00, 'Available'),
('104', 'Double',           2, 1, 5000.00, 'Available'),
('105', 'Single',           1, 1, 3500.00, 'Under Maintenance'),
('201', 'Single',           1, 2, 3800.00, 'Available'),
('202', 'Single',           1, 2, 3800.00, 'Available'),
('203', 'Double',           2, 2, 5500.00, 'Available'),
('204', 'Suite',            2, 2, 7500.00, 'Available'),
('301', 'Single',           1, 3, 4000.00, 'Available'),
('302', 'Double',           2, 3, 5800.00, 'Available'),
('303', 'Suite',            2, 3, 8000.00, 'Available');

-- ── Students ──
INSERT INTO students (student_id, full_name, course, email, contact, gender, address) VALUES
('2021-0001', 'Juan Dela Cruz',    'BSIT',  'juan.delacruz@email.com',  '09171234567', 'Male',   'Mambusao, Capiz'),
('2021-0002', 'Maria Santos',      'BSBA',  'maria.santos@email.com',   '09181234567', 'Female', 'Roxas City, Capiz'),
('2022-0001', 'Pedro Reyes',       'BSEd',  'pedro.reyes@email.com',    '09191234567', 'Male',   'Pontevedra, Capiz'),
('2022-0002', 'Ana Lim',           'BSCS',  'ana.lim@email.com',        '09201234567', 'Female', 'Sigma, Capiz'),
('2022-0003', 'Carlos Mendoza',    'BSCE',  'carlos.mendoza@email.com', '09211234567', 'Male',   'Dumalag, Capiz'),
('2023-0001', 'Rosario Buenaflor', 'BSN',   'rosario.b@email.com',      '09221234567', 'Female', 'Ivisan, Capiz'),
('2023-0002', 'Mark Villanueva',   'BSHRM', 'mark.v@email.com',         '09231234567', 'Male',   'Panitan, Capiz');

-- ── Reservations (covers all status values for full UI testing) ──

-- Pending — visible in Approvals, dashboard pending count
INSERT INTO reservations
    (res_code, student_name, student_id_ref, room_no, status,
     date_in, date_out, notes, created_by)
VALUES
    ('RES-0001', 'Juan Dela Cruz', '2021-0001', '101',
     'Pending',
     CURDATE(), DATE_ADD(CURDATE(), INTERVAL 6 MONTH),
     'Requesting ground floor single room.', 'staff');

-- Approved — room must be Booked
INSERT INTO reservations
    (res_code, student_name, student_id_ref, room_no, status,
     date_in, date_out, notes, approved_by, approved_at, created_by)
VALUES
    ('RES-0002', 'Maria Santos', '2021-0002', '204',
     'Approved',
     CURDATE(), DATE_ADD(CURDATE(), INTERVAL 12 MONTH),
     'Suite room preferred.', 'manager', NOW(), 'admin');

-- Checked-In — room must be Booked
INSERT INTO reservations
    (res_code, student_name, student_id_ref, room_no, status,
     date_in, date_out, notes, approved_by, approved_at, created_by)
VALUES
    ('RES-0003', 'Pedro Reyes', '2022-0001', '201',
     'Checked-In',
     DATE_SUB(CURDATE(), INTERVAL 1 MONTH),
     DATE_ADD(CURDATE(), INTERVAL 5 MONTH),
     'Second floor preference.', 'admin', DATE_SUB(NOW(), INTERVAL 35 DAY), 'admin');

-- Checked-Out — historical record for Reports > Reservation History
INSERT INTO reservations
    (res_code, student_name, student_id_ref, room_no, status,
     date_in, date_out, notes, approved_by, approved_at, created_by)
VALUES
    ('RES-0004', 'Rosario Buenaflor', '2023-0001', '103',
     'Checked-Out',
     DATE_SUB(CURDATE(), INTERVAL 3 MONTH),
     DATE_SUB(CURDATE(), INTERVAL 1 MONTH),
     'Completed stay.', 'manager', DATE_SUB(NOW(), INTERVAL 95 DAY), 'staff');

-- Cancelled
INSERT INTO reservations
    (res_code, student_name, student_id_ref, room_no, status,
     date_in, date_out, notes, created_by)
VALUES
    ('RES-0005', 'Ana Lim', '2022-0002', '102',
     'Cancelled',
     DATE_SUB(CURDATE(), INTERVAL 2 MONTH),
     DATE_ADD(CURDATE(), INTERVAL 4 MONTH),
     'Cancelled before approval.', 'staff');

-- Rejected
INSERT INTO reservations
    (res_code, student_name, student_id_ref, room_no, status,
     date_in, date_out, notes, created_by)
VALUES
    ('RES-0006', 'Mark Villanueva', '2023-0002', '302',
     'Rejected',
     DATE_SUB(CURDATE(), INTERVAL 1 MONTH),
     DATE_ADD(CURDATE(), INTERVAL 5 MONTH),
     'Rejected due to incomplete requirements.', 'admin');

-- ── Sync rooms table to reflect active reservation states ──
-- Room 204 → Booked by Maria Santos (Approved)
UPDATE rooms SET status = 'Booked', reserved_by = 'Maria Santos' WHERE room_no = '204';
-- Room 201 → Booked by Pedro Reyes (Checked-In)
UPDATE rooms SET status = 'Booked', reserved_by = 'Pedro Reyes'  WHERE room_no = '201';


-- ──────────────────────────────────────────────────────────────
--  6. QUICK SANITY CHECK  (uncomment to run after import)
-- ──────────────────────────────────────────────────────────────
-- SELECT * FROM vw_dashboard_stats;
-- SELECT username, role, LEFT(password,16) AS hash_prefix FROM users;
-- SELECT room_no, status, reserved_by FROM rooms ORDER BY floor_no, room_no;
-- SELECT res_code, student_name, room_no, status FROM reservations;
-- CALL sp_approve_reservation('RES-0001', 'admin');
-- CALL sp_checkin('RES-0001');
-- CALL sp_checkout('RES-0001');
-- CALL sp_cancel_reservation('RES-0002');
-- ──────────────────────────────────────────────────────────────
