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
    position INTEGER NOT NULL DEFAULT 0,
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
    schedule TEXT DEFAULT '',
    position INTEGER NOT NULL DEFAULT 0,
    embedding FLOAT8[] DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 为已有库补齐 schedule 字段（日程属性独立存储为 JSON 字符串）
ALTER TABLE files ADD COLUMN IF NOT EXISTS schedule TEXT DEFAULT '';
-- 为已有库补齐 position 字段（同级排序）
ALTER TABLE folders ADD COLUMN IF NOT EXISTS position INTEGER NOT NULL DEFAULT 0;
ALTER TABLE files ADD COLUMN IF NOT EXISTS position INTEGER NOT NULL DEFAULT 0;

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
