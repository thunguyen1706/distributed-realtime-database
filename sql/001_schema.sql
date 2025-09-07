-- Enable UUIDs
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Trigger to maintain updated_at
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END
$$;

-- USERS: id, username, email, created_at, updated_at
CREATE TABLE IF NOT EXISTS users (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  username    TEXT UNIQUE NOT NULL,
  email       TEXT UNIQUE NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- POSTS: id, user_id, content, created_at, updated_at  
CREATE TABLE IF NOT EXISTS posts (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL,
  content     TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_posts_user_created_at 
  ON posts (user_id, created_at DESC);

-- COMMENTS: id, post_id, user_id, content, created_at, updated_at
CREATE TABLE IF NOT EXISTS comments (
  id          TEXT PRIMARY KEY,
  post_id     TEXT NOT NULL,
  user_id     TEXT NOT NULL,
  content     TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_comments_post_created_at 
  ON comments (post_id, created_at DESC);

-- LIKES: id, post_id, user_id, created_at
CREATE TABLE IF NOT EXISTS likes (
  id          TEXT PRIMARY KEY,
  post_id     TEXT NOT NULL,
  user_id     TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (post_id, user_id)             
);

-- Triggers to auto-maintain updated_at
DO $$ BEGIN
  -- users
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_users_updated_at'
  ) THEN
    CREATE TRIGGER trg_users_updated_at
      BEFORE UPDATE ON users
      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;

  -- posts
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_posts_updated_at'
  ) THEN
    CREATE TRIGGER trg_posts_updated_at
      BEFORE UPDATE ON posts
      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;

  -- comments
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_comments_updated_at'
  ) THEN
    CREATE TRIGGER trg_comments_updated_at
      BEFORE UPDATE ON comments
      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;
END$$;
