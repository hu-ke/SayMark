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
    device_id VARCHAR(255) NOT NULL DEFAULT '',
    position INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS files (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    device_id VARCHAR(255) NOT NULL DEFAULT '',
    content TEXT DEFAULT '',
    parent_id INTEGER REFERENCES folders(id) ON DELETE SET NULL,
    -- note=笔记 | appointment=安排(一次性) | alarm=闹钟(周期性)
    type VARCHAR(20) DEFAULT 'note' CHECK (type IN ('note', 'appointment', 'alarm')),
    date DATE,          -- 仅 appointment 使用：具体日期 YYYY-MM-DD
    "time" TIME,        -- appointment=开始时间；alarm=周期触发时间
    recurrence VARCHAR(20) CHECK (recurrence IS NULL OR recurrence IN ('', 'daily', 'weekly', 'monthly')),
    position INTEGER NOT NULL DEFAULT 0,
    embedding FLOAT8[] DEFAULT '{}',
    archived BOOLEAN NOT NULL DEFAULT FALSE,
    archived_parent_id INTEGER REFERENCES folders(id) ON DELETE SET NULL,
    archived_path TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 为已有库补齐 position 字段（同级排序）
ALTER TABLE folders ADD COLUMN IF NOT EXISTS position INTEGER NOT NULL DEFAULT 0;
ALTER TABLE files ADD COLUMN IF NOT EXISTS position INTEGER NOT NULL DEFAULT 0;

-- 为已有库补齐归档字段
ALTER TABLE files ADD COLUMN IF NOT EXISTS archived BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE files ADD COLUMN IF NOT EXISTS archived_parent_id INTEGER REFERENCES folders(id) ON DELETE SET NULL;
ALTER TABLE files ADD COLUMN IF NOT EXISTS archived_path TEXT DEFAULT '';

-- 为已有库补齐 device_id 字段（数据隔离）
ALTER TABLE folders ADD COLUMN IF NOT EXISTS device_id VARCHAR(255) NOT NULL DEFAULT '';
ALTER TABLE files ADD COLUMN IF NOT EXISTS device_id VARCHAR(255) NOT NULL DEFAULT '';
CREATE INDEX IF NOT EXISTS idx_folders_device ON folders(device_id);
CREATE INDEX IF NOT EXISTS idx_files_device ON files(device_id);

-- 迁移：旧的 type='event' 统一改名 appointment；其中带 recurrence 的转为闹钟 alarm
ALTER TABLE files DROP CONSTRAINT IF EXISTS files_type_check;
ALTER TABLE files ALTER COLUMN type TYPE VARCHAR(20);
ALTER TABLE files ADD CONSTRAINT files_type_check CHECK (type IN ('note', 'appointment', 'alarm'));
UPDATE files SET type = 'appointment' WHERE type = 'event';
UPDATE files SET type = 'alarm' WHERE type = 'appointment' AND recurrence IS NOT NULL AND recurrence <> '';

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
