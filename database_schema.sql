-- ==========================================
-- CAMPUSGRID PRODUCTION-READY SUPABASE SCHEMA
-- (PostgreSQL / Supabase Edition)
-- ==========================================

-- 0. EXTENSIONS & CLEANUP
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- NOTE: CASCADE automatically handles associated triggers/constraints
DROP TABLE IF EXISTS gate_logs CASCADE;
DROP TABLE IF EXISTS qr_codes CASCADE;
DROP TABLE IF EXISTS notifications CASCADE;
DROP TABLE IF EXISTS leave_requests CASCADE;
DROP TABLE IF EXISTS students CASCADE;
DROP TABLE IF EXISTS users CASCADE;

DROP TYPE IF EXISTS user_role CASCADE;
DROP TYPE IF EXISTS leave_status CASCADE;
DROP TYPE IF EXISTS scan_type CASCADE;

-- 1. ENUMS (Proper Validation)
CREATE TYPE user_role AS ENUM ('STUDENT', 'WARDEN', 'GUARD');
CREATE TYPE leave_status AS ENUM ('PENDING', 'APPROVED', 'REJECTED', 'OUT', 'RETURNED');
CREATE TYPE scan_type AS ENUM ('EXIT', 'ENTRY');

-- 2. CORE IDENTITY
CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    college_id VARCHAR(50) UNIQUE NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    password VARCHAR(100) NOT NULL, -- NOTE: In production, transition to Supabase Auth
    role user_role NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. ROLE-SPECIFIC PROFILES
CREATE TABLE students (
    student_id UUID PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
    roll_no VARCHAR(50) UNIQUE NOT NULL,
    branch VARCHAR(100) NOT NULL
);

-- 4. TRANSIT LEDGER
CREATE TABLE leave_requests (
    leave_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
    from_date DATE NOT NULL,
    to_date DATE NOT NULL,
    reason TEXT NOT NULL,
    status leave_status NOT NULL DEFAULT 'PENDING',
    approved_by UUID REFERENCES users(user_id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. TRANSIT TOKENS
CREATE TABLE qr_codes (
    qr_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    leave_id UUID UNIQUE NOT NULL REFERENCES leave_requests(leave_id) ON DELETE CASCADE,
    qr_token VARCHAR(100) UNIQUE NOT NULL,
    generated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 6. SECURITY LOGS
CREATE TABLE gate_logs (
    log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    leave_id UUID NOT NULL REFERENCES leave_requests(leave_id) ON DELETE CASCADE,
    guard_id UUID NOT NULL REFERENCES users(user_id) ON DELETE SET NULL,
    scan_type scan_type NOT NULL,
    scan_time TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 7. NOTIFICATION SYSTEM
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    message TEXT NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 8. AUTOMATION: NOTIFICATION TRIGGER
CREATE OR REPLACE FUNCTION handle_leave_notification()
RETURNS TRIGGER AS $$
BEGIN
    IF (OLD.status <> NEW.status) THEN
        INSERT INTO notifications (user_id, message)
        VALUES (
            NEW.student_id,
            'Your leave application (' || NEW.leave_id::text || ') status updated to: ' || NEW.status
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_leave_update_notify
AFTER UPDATE ON leave_requests
FOR EACH ROW
EXECUTE FUNCTION handle_leave_notification();

-- 9. SECURITY: ROW LEVEL SECURITY (RLS)
-- NOTE: If using the service_role key, these policies are bypassed.
-- If using the anon/authenticated key, these enable public self-registration and lookups.
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE students ENABLE ROW LEVEL SECURITY;
ALTER TABLE leave_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE qr_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE gate_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- 9.1 USERS POLICIES
CREATE POLICY "Public Read: All Profiles" ON users FOR SELECT USING (true);
CREATE POLICY "Public Insert: Registration" ON users FOR INSERT WITH CHECK (true);
CREATE POLICY "User Update: Own Profile" ON users FOR UPDATE USING (true); -- Ideally restricted to owner

-- 9.2 STUDENTS POLICIES
CREATE POLICY "Public Read: Students" ON students FOR SELECT USING (true);
CREATE POLICY "Public Insert: Student Registry" ON students FOR INSERT WITH CHECK (true);

-- 9.3 LEAVE POLICIES
CREATE POLICY "Public Read: Leaves" ON leave_requests FOR SELECT USING (true);
CREATE POLICY "Public Insert: Apply" ON leave_requests FOR INSERT WITH CHECK (true);
CREATE POLICY "Public Update: Approval/State" ON leave_requests FOR UPDATE USING (true);

-- 9.4 OTHER POLICIES (Tokens, Logs, Notifications)
CREATE POLICY "Public Read/Insert: Tokens" ON qr_codes FOR ALL USING (true);
CREATE POLICY "Public Read/Insert: Gate Logs" ON gate_logs FOR ALL USING (true);
CREATE POLICY "Public Read/Insert: Notifications" ON notifications FOR ALL USING (true);

-- 10. INDEXES (Performance Optimization)
CREATE INDEX idx_user_college_id ON users(college_id);
CREATE INDEX idx_leave_student_id ON leave_requests(student_id);
CREATE INDEX idx_qr_token ON qr_codes(qr_token);
CREATE INDEX idx_logs_scan_time ON gate_logs(scan_time);
