-- SayMark PostgreSQL Schema
-- Run: psql -U <user> -d <dbname> -f setup_pg.sql

CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    device_id VARCHAR(255) UNIQUE NOT NULL,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    home_address TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_places (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    lat DOUBLE PRECISION NOT NULL,
    lon DOUBLE PRECISION NOT NULL,
    UNIQUE(user_id, name)
);

CREATE TABLE IF NOT EXISTS folders (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    parent_id INTEGER REFERENCES folders(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS files (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    content TEXT DEFAULT '',
    parent_id INTEGER REFERENCES folders(id) ON DELETE SET NULL,
    type VARCHAR(10) DEFAULT 'note' CHECK (type IN ('note', 'event')),
    date DATE,
    "time" TIME,
    reminder_minutes INTEGER,
    recurrence VARCHAR(20) CHECK (recurrence IS NULL OR recurrence IN ('', 'daily', 'weekly', 'monthly')),
    recurrence_end_date DATE,
    embedding FLOAT8[] DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_folders_parent ON folders(parent_id);
CREATE INDEX IF NOT EXISTS idx_files_parent ON files(parent_id);
CREATE INDEX IF NOT EXISTS idx_files_type ON files(type);
CREATE INDEX IF NOT EXISTS idx_files_date ON files(date);
CREATE INDEX IF NOT EXISTS idx_files_name ON files(name);
CREATE INDEX IF NOT EXISTS idx_files_created ON files(created_at);
CREATE INDEX IF NOT EXISTS idx_users_device ON users(device_id);

-- Default "未分类" folder
INSERT INTO folders (name, parent_id) VALUES ('未分类', NULL) ON CONFLICT DO NOTHING;
