-- Relational projection of the v2 sync domain. sync_records remains the
-- append/change journal; these tables are the queryable source of domain data.
CREATE TABLE IF NOT EXISTS user_settings (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    weight_unit VARCHAR(16) NOT NULL DEFAULT 'lbs',
    distance_unit VARCHAR(16) NOT NULL DEFAULT 'mi',
    rest_timer_notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    CHECK (weight_unit IN ('lbs', 'kg')),
    CHECK (distance_unit IN ('mi', 'km'))
);

CREATE TABLE IF NOT EXISTS muscles (
    id UUID PRIMARY KEY,
    name VARCHAR(120) NOT NULL,
    color_hex VARCHAR(6) NOT NULL,
    CHECK (color_hex ~ '^[0-9A-Fa-f]{6}$')
);

CREATE TABLE IF NOT EXISTS exercises (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    client_uuid VARCHAR(64),
    name VARCHAR(160) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    is_archived BOOLEAN NOT NULL DEFAULT FALSE,
    tracking_type VARCHAR(80) NOT NULL,
    target_rest_seconds INTEGER NOT NULL DEFAULT 120 CHECK (target_rest_seconds >= 0),
    primary_muscle_id UUID REFERENCES muscles(id) ON DELETE RESTRICT,
    UNIQUE (user_id, client_uuid),
    CHECK ((user_id IS NULL) = (client_uuid IS NULL))
);
CREATE INDEX IF NOT EXISTS ix_exercises_user_id ON exercises(user_id);

CREATE TABLE IF NOT EXISTS exercise_secondary_muscles (
    exercise_id UUID NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
    muscle_id UUID NOT NULL REFERENCES muscles(id) ON DELETE RESTRICT,
    PRIMARY KEY (exercise_id, muscle_id)
);

CREATE TABLE IF NOT EXISTS user_hidden_exercises (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    exercise_id UUID NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, exercise_id)
);

CREATE TABLE IF NOT EXISTS tags (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    client_uuid VARCHAR(64) NOT NULL,
    name VARCHAR(120) NOT NULL,
    UNIQUE (user_id, client_uuid)
);

CREATE TABLE IF NOT EXISTS workout_templates (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    client_uuid VARCHAR(64) NOT NULL,
    name VARCHAR(160) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    is_archived BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE (user_id, client_uuid)
);
CREATE INDEX IF NOT EXISTS ix_workout_templates_user_id ON workout_templates(user_id);

CREATE TABLE IF NOT EXISTS workout_template_tags (
    workout_template_id UUID NOT NULL REFERENCES workout_templates(id) ON DELETE CASCADE,
    tag_id UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (workout_template_id, tag_id)
);

CREATE TABLE IF NOT EXISTS template_exercises (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    client_uuid VARCHAR(64) NOT NULL,
    workout_template_id UUID NOT NULL REFERENCES workout_templates(id) ON DELETE CASCADE,
    exercise_id UUID NOT NULL REFERENCES exercises(id) ON DELETE RESTRICT,
    position INTEGER NOT NULL CHECK (position >= 0),
    UNIQUE (user_id, client_uuid),
    UNIQUE (workout_template_id, position)
);

CREATE TABLE IF NOT EXISTS template_exercise_alternates (
    template_exercise_id UUID NOT NULL REFERENCES template_exercises(id) ON DELETE CASCADE,
    exercise_id UUID NOT NULL REFERENCES exercises(id) ON DELETE RESTRICT,
    PRIMARY KEY (template_exercise_id, exercise_id)
);

CREATE TABLE IF NOT EXISTS template_sets (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    client_uuid VARCHAR(64) NOT NULL,
    template_exercise_id UUID NOT NULL REFERENCES template_exercises(id) ON DELETE CASCADE,
    set_number INTEGER NOT NULL CHECK (set_number > 0),
    is_warmup BOOLEAN NOT NULL DEFAULT FALSE,
    planned_reps INTEGER CHECK (planned_reps >= 0),
    planned_time_seconds DOUBLE PRECISION CHECK (planned_time_seconds >= 0),
    planned_distance NUMERIC(12,3) CHECK (planned_distance >= 0),
    planned_weight NUMERIC(12,3) CHECK (planned_weight >= 0),
    UNIQUE (user_id, client_uuid),
    UNIQUE (template_exercise_id, set_number)
);

CREATE TABLE IF NOT EXISTS workout_sessions (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    client_uuid VARCHAR(64) NOT NULL,
    workout_template_id UUID REFERENCES workout_templates(id) ON DELETE SET NULL,
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ,
    duration_seconds BIGINT CHECK (duration_seconds >= 0),
    rating SMALLINT CHECK (rating BETWEEN 1 AND 5),
    note TEXT,
    percent_completed DOUBLE PRECISION CHECK (percent_completed BETWEEN 0 AND 100),
    volume_weight NUMERIC(14,3) CHECK (volume_weight >= 0),
    average_rest_seconds DOUBLE PRECISION CHECK (average_rest_seconds >= 0),
    estimated_intensity DOUBLE PRECISION CHECK (estimated_intensity >= 0),
    UNIQUE (user_id, client_uuid),
    CHECK (ended_at IS NULL OR ended_at >= started_at)
);
CREATE INDEX IF NOT EXISTS ix_workout_sessions_user_started ON workout_sessions(user_id, started_at DESC);

CREATE TABLE IF NOT EXISTS session_exercises (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    client_uuid VARCHAR(64) NOT NULL,
    workout_session_id UUID NOT NULL REFERENCES workout_sessions(id) ON DELETE CASCADE,
    exercise_id UUID REFERENCES exercises(id) ON DELETE SET NULL,
    position INTEGER NOT NULL CHECK (position >= 0),
    exercise_name VARCHAR(160) NOT NULL,
    tracking_type VARCHAR(80) NOT NULL,
    difficulty_type VARCHAR(80) NOT NULL,
    primary_muscle_name VARCHAR(120) NOT NULL,
    primary_muscle_color_hex VARCHAR(6) NOT NULL,
    target_rest_seconds INTEGER CHECK (target_rest_seconds >= 0),
    UNIQUE (user_id, client_uuid),
    UNIQUE (workout_session_id, position)
);

CREATE TABLE IF NOT EXISTS session_sets (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    client_uuid VARCHAR(64) NOT NULL,
    session_exercise_id UUID NOT NULL REFERENCES session_exercises(id) ON DELETE CASCADE,
    set_number INTEGER NOT NULL CHECK (set_number > 0),
    completed BOOLEAN NOT NULL DEFAULT FALSE,
    completed_at TIMESTAMPTZ,
    is_warmup BOOLEAN NOT NULL DEFAULT FALSE,
    reps INTEGER CHECK (reps >= 0),
    time_seconds DOUBLE PRECISION CHECK (time_seconds >= 0),
    distance NUMERIC(12,3) CHECK (distance >= 0),
    weight NUMERIC(12,3) CHECK (weight >= 0),
    pace DOUBLE PRECISION CHECK (pace >= 0),
    UNIQUE (user_id, client_uuid),
    UNIQUE (session_exercise_id, set_number),
    CHECK (completed OR completed_at IS NULL)
);

CREATE INDEX IF NOT EXISTS ix_tags_user_id ON tags(user_id);
CREATE INDEX IF NOT EXISTS ix_template_exercises_user_id ON template_exercises(user_id);
CREATE INDEX IF NOT EXISTS ix_template_sets_user_id ON template_sets(user_id);
CREATE INDEX IF NOT EXISTS ix_session_exercises_user_id ON session_exercises(user_id);
CREATE INDEX IF NOT EXISTS ix_session_sets_user_id ON session_sets(user_id);
