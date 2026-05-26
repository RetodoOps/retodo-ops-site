-- ============================================================
-- RetodoOps TMS — Supabase Database Setup
-- Paste this into: Supabase → SQL Editor → New Query → Run
-- ============================================================

-- PROFILES (one per auth user)
CREATE TABLE IF NOT EXISTS profiles (
    id         UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    full_name  TEXT NOT NULL,
    role       TEXT DEFAULT 'user' CHECK (role IN ('admin','pm','qa','user')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- CLIENTS
CREATE TABLE IF NOT EXISTS clients (
    id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name       TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- PROJECTS
CREATE TABLE IF NOT EXISTS projects (
    id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    project_number  TEXT UNIQUE NOT NULL,
    client_id       UUID REFERENCES clients(id),
    sub_client      TEXT,
    source_language TEXT,
    target_language TEXT,
    deadline        TIMESTAMPTZ,
    job_deadline    TIMESTAMPTZ,
    project_manager TEXT,
    qa_specialist   TEXT,
    linguist        TEXT,
    status          TEXT DEFAULT 'Assign'
                    CHECK (status IN (
                        'Assign','Ongoing','QA Ready','QA Issues',
                        'PM Ready','Delivery','Completed','Approved'
                    )),
    project_type    TEXT,
    project_volume  TEXT,
    price           DECIMAL(10,2) DEFAULT 0,
    currency        TEXT DEFAULT 'EUR',
    scoop_margin    DECIMAL(5,2)  DEFAULT 0,
    upcoming        BOOLEAN DEFAULT FALSE,
    urgent          BOOLEAN DEFAULT FALSE,
    on_hold         BOOLEAN DEFAULT FALSE,
    missing_po      BOOLEAN DEFAULT FALSE,
    po_number       TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ── ROW LEVEL SECURITY ────────────────────────────────────────────────────
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE clients  ENABLE ROW LEVEL SECURITY;
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;

-- Authenticated users can read and write all rows
CREATE POLICY "auth_profiles" ON profiles FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_clients"  ON clients  FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_projects" ON projects FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ── AUTO-CREATE PROFILE ON SIGNUP ────────────────────────────────────────
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    INSERT INTO profiles (id, full_name)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email,'@',1))
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ── SAMPLE DATA ───────────────────────────────────────────────────────────
-- Remove this section if you want to start with a clean database.

INSERT INTO clients (name) VALUES
    ('RWS Life Sciences, Inc.'),
    ('Welocalize Ltd.'),
    ('Moravia IT S.r.o.'),
    ('Acolad, Inc.'),
    ('Parenty Reitmeier, Inc.');

INSERT INTO projects (
    project_number, client_id, sub_client,
    source_language, target_language,
    deadline, job_deadline,
    project_manager, qa_specialist, linguist,
    status, project_type, price, currency, scoop_margin
) VALUES
(
    'B22031-001',
    (SELECT id FROM clients WHERE name='RWS Life Sciences, Inc.'),
    'TikTok','English (US)','Bulgarian',
    NOW() + INTERVAL '1 day 3 hours', NOW() + INTERVAL '22 hours',
    'Martina Martinova','Lyubotsveta Stoyanova','Valeri Dimitrova',
    'PM Ready','Machine Translation Editing + Proofreading',67.8,'USD',79.26
),(
    'B22031-002',
    (SELECT id FROM clients WHERE name='RWS Life Sciences, Inc.'),
    'TikTok','English (US)','Bulgarian',
    NOW() + INTERVAL '1 day 3 hours', NOW() + INTERVAL '21 hours',
    'Martina Martinova','Lyubotsveta Stoyanova','Valeri Dimitrova',
    'PM Ready','Machine Translation Editing + Proofreading',10.2,'USD',91.57
),(
    'B21904-004',
    (SELECT id FROM clients WHERE name='Welocalize Ltd.'),
    'Microsoft','English (US)','Swedish',
    NOW() + INTERVAL '2 days', NOW() + INTERVAL '2 days',
    'Rumen Georgiev','QA Team','Josefine Lancaster',
    'PM Ready','Update',0,'USD',0
),(
    'B21924-002',
    (SELECT id FROM clients WHERE name='Moravia IT S.r.o.'),
    'Apple','English (US)','Danish',
    NOW() + INTERVAL '2 days', NULL,
    'Martina Martinova',NULL,NULL,
    'Assign','Update',0,'EUR',65.69
),(
    'B21944-001',
    (SELECT id FROM clients WHERE name='Moravia IT S.r.o.'),
    'Apple','English (US)','Finnish',
    NOW() + INTERVAL '2 days', NOW() + INTERVAL '1 day',
    'Rumen Georgiev','Maria Eftimova','Anna Laine',
    'PM Ready','Proofreading',35,'EUR',61.43
),(
    'B22002-001',
    (SELECT id FROM clients WHERE name='Acolad, Inc.'),
    'E-Filliate Inc.','English (US)','Danish',
    NOW() + INTERVAL '2 days', NOW() + INTERVAL '20 hours',
    'Martina Martinova','Kris Utev','Bjørn Eriksen',
    'PM Ready','Machine Translation Editing + Proofreading',92.96,'USD',19.88
),(
    'B22002-002',
    (SELECT id FROM clients WHERE name='Acolad, Inc.'),
    'E-Filliate Inc.','English (US)','Finnish',
    NOW() + INTERVAL '2 days', NOW() + INTERVAL '20 hours',
    'Martina Martinova','Kris Utev','Anna Laine',
    'PM Ready','Machine Translation Editing + Proofreading',92.85,'USD',19.88
),(
    'B22011-001',
    (SELECT id FROM clients WHERE name='Parenty Reitmeier, Inc.'),
    'Arctic Cat','English (US)','Norwegian (Bokmål)',
    NOW() - INTERVAL '1 hour', NOW() - INTERVAL '2 hours',
    'Tsvetelin Angelov','Kris Utev','Lise Skalberg',
    'QA Ready','Proofreading',81.55,'EUR',34.45
),(
    'B21990-004',
    (SELECT id FROM clients WHERE name='RWS Life Sciences, Inc.'),
    'TikTok','English (US)','Bulgarian',
    NOW() + INTERVAL '2 days', NOW() + INTERVAL '1 day 4 hours',
    'Martina Martinova',NULL,'Valeri Dimitrova',
    'Ongoing','Update',0,'USD',87.61
);
