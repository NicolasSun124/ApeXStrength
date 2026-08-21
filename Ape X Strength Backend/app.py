import hashlib
import os
import secrets
import smtplib
import uuid
import json
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from email.message import EmailMessage

from flask import Flask, jsonify, request
from flask_sqlalchemy import SQLAlchemy
from werkzeug.security import check_password_hash, generate_password_hash

app = Flask(__name__)
app.config.update(
    # TODO: Before deploying, remove the credential fallback, rotate the development
    # password, and provide DATABASE_URL through the deployment environment.
    SQLALCHEMY_DATABASE_URI=os.getenv(
        "DATABASE_URL", "postgresql+psycopg://nicolassun:dba_pass_123@127.0.0.1:5432/apexstrength"
    ),
    SQLALCHEMY_TRACK_MODIFICATIONS=False,
    APP_ENV=os.getenv("APP_ENV", "development").lower(),
    EMAIL_TRANSPORT=os.getenv("EMAIL_TRANSPORT"),
    SMTP_HOST=os.getenv("SMTP_HOST", "127.0.0.1"),
    SMTP_PORT=int(os.getenv("SMTP_PORT", "1025")),
    SMTP_USERNAME=os.getenv("SMTP_USERNAME"),
    SMTP_PASSWORD=os.getenv("SMTP_PASSWORD"),
    EMAIL_FROM_EMAIL=os.getenv("EMAIL_FROM_EMAIL", "no-reply@apexstrength.local"),
    EMAIL_FROM_NAME=os.getenv("EMAIL_FROM_NAME", "Ape X Strength"),
    BREVO_API_KEY=os.getenv("BREVO_API_KEY"),
    BREVO_API_URL=os.getenv("BREVO_API_URL", "https://api.brevo.com/v3/smtp/email"),
)
db = SQLAlchemy(app)


class User(db.Model):
    __tablename__ = "users"

    id = db.Column(db.Uuid, primary_key=True, default=uuid.uuid4)
    email = db.Column(db.String(320), unique=True, nullable=False)
    password_hash = db.Column(db.Text, nullable=False)
    verification_code_hash = db.Column(db.String(64))
    verification_code_expires_at = db.Column(db.DateTime(timezone=True))
    password_reset_code_hash = db.Column(db.String(64))
    password_reset_code_expires_at = db.Column(db.DateTime(timezone=True))
    email_verified = db.Column(db.Boolean, nullable=False, default=False)
    name = db.Column(db.String(120))
    session_token_hash = db.Column(db.String(64), unique=True)
    sync_data = db.Column(db.JSON)
    synced_at = db.Column(db.DateTime(timezone=True))
    sync_revision = db.Column(db.BigInteger, nullable=False, default=0)

    def json(self):
        return {
            "id": str(self.id),
            "email": self.email,
            "email_verified": self.email_verified,
            "name": self.name,
        }


class SyncRecord(db.Model):
    __tablename__ = "sync_records"
    __table_args__ = (db.UniqueConstraint("user_id", "entity_type", "client_uuid"),)

    id = db.Column(db.Uuid, primary_key=True, default=uuid.uuid4)
    user_id = db.Column(db.Uuid, db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    entity_type = db.Column(db.String(40), nullable=False)
    client_uuid = db.Column(db.String(64), nullable=False)
    data = db.Column(db.JSON)
    revision = db.Column(db.BigInteger, nullable=False)
    deleted_at = db.Column(db.DateTime(timezone=True))
    updated_at = db.Column(db.DateTime(timezone=True), nullable=False)


workout_template_tags = db.Table(
    "workout_template_tags",
    db.Column("workout_template_id", db.Uuid, db.ForeignKey("workout_templates.id", ondelete="CASCADE"), primary_key=True),
    db.Column("tag_id", db.Uuid, db.ForeignKey("tags.id", ondelete="CASCADE"), primary_key=True),
)

exercise_secondary_muscles = db.Table(
    "exercise_secondary_muscles",
    db.Column("exercise_id", db.Uuid, db.ForeignKey("exercises.id", ondelete="CASCADE"), primary_key=True),
    db.Column("muscle_id", db.Uuid, db.ForeignKey("muscles.id", ondelete="RESTRICT"), primary_key=True),
)

template_exercise_alternates = db.Table(
    "template_exercise_alternates",
    db.Column("template_exercise_id", db.Uuid, db.ForeignKey("template_exercises.id", ondelete="CASCADE"), primary_key=True),
    db.Column("exercise_id", db.Uuid, db.ForeignKey("exercises.id", ondelete="RESTRICT"), primary_key=True),
)


class UserSettings(db.Model):
    __tablename__ = "user_settings"
    user_id = db.Column(db.Uuid, db.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    weight_unit = db.Column(db.String(16), nullable=False, default="lbs")
    distance_unit = db.Column(db.String(16), nullable=False, default="mi")
    rest_timer_notifications_enabled = db.Column(db.Boolean, nullable=False, default=True)


class Muscle(db.Model):
    __tablename__ = "muscles"
    id = db.Column(db.Uuid, primary_key=True)
    name = db.Column(db.String(120), nullable=False)
    color_hex = db.Column(db.String(6), nullable=False)


class Exercise(db.Model):
    __tablename__ = "exercises"
    __table_args__ = (db.UniqueConstraint("user_id", "client_uuid"),)
    id = db.Column(db.Uuid, primary_key=True, default=uuid.uuid4)
    user_id = db.Column(db.Uuid, db.ForeignKey("users.id", ondelete="CASCADE"), index=True)
    client_uuid = db.Column(db.String(64))
    name = db.Column(db.String(160), nullable=False)
    created_at = db.Column(db.DateTime(timezone=True), nullable=False)
    is_archived = db.Column(db.Boolean, nullable=False, default=False)
    tracking_type = db.Column(db.String(80), nullable=False)
    target_rest_seconds = db.Column(db.Integer, nullable=False, default=120)
    primary_muscle_id = db.Column(db.Uuid, db.ForeignKey("muscles.id", ondelete="RESTRICT"))
    primary_muscle = db.relationship(Muscle, foreign_keys=[primary_muscle_id])
    secondary_muscles = db.relationship(Muscle, secondary=exercise_secondary_muscles)


class Tag(db.Model):
    __tablename__ = "tags"
    __table_args__ = (db.UniqueConstraint("user_id", "client_uuid"),)
    id = db.Column(db.Uuid, primary_key=True, default=uuid.uuid4)
    user_id = db.Column(db.Uuid, db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    client_uuid = db.Column(db.String(64), nullable=False)
    name = db.Column(db.String(120), nullable=False)


class WorkoutTemplate(db.Model):
    __tablename__ = "workout_templates"
    __table_args__ = (db.UniqueConstraint("user_id", "client_uuid"),)
    id = db.Column(db.Uuid, primary_key=True, default=uuid.uuid4)
    user_id = db.Column(db.Uuid, db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    client_uuid = db.Column(db.String(64), nullable=False)
    name = db.Column(db.String(160), nullable=False)
    created_at = db.Column(db.DateTime(timezone=True), nullable=False)
    updated_at = db.Column(db.DateTime(timezone=True), nullable=False)
    is_archived = db.Column(db.Boolean, nullable=False, default=False)
    tags = db.relationship(Tag, secondary=workout_template_tags)


class TemplateExercise(db.Model):
    __tablename__ = "template_exercises"
    __table_args__ = (db.UniqueConstraint("user_id", "client_uuid"),)
    id = db.Column(db.Uuid, primary_key=True, default=uuid.uuid4)
    user_id = db.Column(db.Uuid, db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    client_uuid = db.Column(db.String(64), nullable=False)
    workout_template_id = db.Column(db.Uuid, db.ForeignKey("workout_templates.id", ondelete="CASCADE"), nullable=False)
    exercise_id = db.Column(db.Uuid, db.ForeignKey("exercises.id", ondelete="RESTRICT"), nullable=False)
    position = db.Column(db.Integer, nullable=False)
    alternate_exercises = db.relationship(Exercise, secondary=template_exercise_alternates)


class TemplateSet(db.Model):
    __tablename__ = "template_sets"
    __table_args__ = (db.UniqueConstraint("user_id", "client_uuid"),)
    id = db.Column(db.Uuid, primary_key=True, default=uuid.uuid4)
    user_id = db.Column(db.Uuid, db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    client_uuid = db.Column(db.String(64), nullable=False)
    template_exercise_id = db.Column(db.Uuid, db.ForeignKey("template_exercises.id", ondelete="CASCADE"), nullable=False)
    set_number = db.Column(db.Integer, nullable=False)
    is_warmup = db.Column(db.Boolean, nullable=False, default=False)
    planned_reps = db.Column(db.Integer)
    planned_time_seconds = db.Column(db.Float)
    planned_distance = db.Column(db.Numeric(12, 3))
    planned_weight = db.Column(db.Numeric(12, 3))


class WorkoutSession(db.Model):
    __tablename__ = "workout_sessions"
    __table_args__ = (db.UniqueConstraint("user_id", "client_uuid"),)
    id = db.Column(db.Uuid, primary_key=True, default=uuid.uuid4)
    user_id = db.Column(db.Uuid, db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    client_uuid = db.Column(db.String(64), nullable=False)
    workout_template_id = db.Column(db.Uuid, db.ForeignKey("workout_templates.id", ondelete="SET NULL"))
    started_at = db.Column(db.DateTime(timezone=True), nullable=False)
    ended_at = db.Column(db.DateTime(timezone=True))
    duration_seconds = db.Column(db.BigInteger)
    rating = db.Column(db.SmallInteger)
    note = db.Column(db.Text)
    percent_completed = db.Column(db.Float)
    volume_weight = db.Column(db.Numeric(14, 3))
    average_rest_seconds = db.Column(db.Float)
    estimated_intensity = db.Column(db.Float)


class SessionExercise(db.Model):
    __tablename__ = "session_exercises"
    __table_args__ = (db.UniqueConstraint("user_id", "client_uuid"),)
    id = db.Column(db.Uuid, primary_key=True, default=uuid.uuid4)
    user_id = db.Column(db.Uuid, db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    client_uuid = db.Column(db.String(64), nullable=False)
    workout_session_id = db.Column(db.Uuid, db.ForeignKey("workout_sessions.id", ondelete="CASCADE"), nullable=False)
    exercise_id = db.Column(db.Uuid, db.ForeignKey("exercises.id", ondelete="SET NULL"))
    position = db.Column(db.Integer, nullable=False)
    exercise_name = db.Column(db.String(160), nullable=False)
    tracking_type = db.Column(db.String(80), nullable=False)
    difficulty_type = db.Column(db.String(80), nullable=False)
    primary_muscle_name = db.Column(db.String(120), nullable=False)
    primary_muscle_color_hex = db.Column(db.String(6), nullable=False)
    target_rest_seconds = db.Column(db.Integer)


class SessionSet(db.Model):
    __tablename__ = "session_sets"
    __table_args__ = (db.UniqueConstraint("user_id", "client_uuid"),)
    id = db.Column(db.Uuid, primary_key=True, default=uuid.uuid4)
    user_id = db.Column(db.Uuid, db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    client_uuid = db.Column(db.String(64), nullable=False)
    session_exercise_id = db.Column(db.Uuid, db.ForeignKey("session_exercises.id", ondelete="CASCADE"), nullable=False)
    set_number = db.Column(db.Integer, nullable=False)
    completed = db.Column(db.Boolean, nullable=False, default=False)
    completed_at = db.Column(db.DateTime(timezone=True))
    is_warmup = db.Column(db.Boolean, nullable=False, default=False)
    reps = db.Column(db.Integer)
    time_seconds = db.Column(db.Float)
    distance = db.Column(db.Numeric(12, 3))
    weight = db.Column(db.Numeric(12, 3))
    pace = db.Column(db.Float)


DOMAIN_MODELS = {
    "exercise": Exercise,
    "tag": Tag,
    "workout": WorkoutTemplate,
    "template_exercise": TemplateExercise,
    "template_set": TemplateSet,
    "workout_session": WorkoutSession,
    "session_exercise": SessionExercise,
    "session_set": SessionSet,
}

PREMADE_MUSCLES = (
    "Abdominals", "Abductors", "Adductors", "Biceps", "Calves", "Forearm Extensors",
    "Forearm Flexors", "Front Deltoid", "Gluteus maximus", "Hamstrings", "Lateral Deltoid",
    "Lats", "Lower Back", "Lower Chest", "Lower Traps", "Middle Traps", "Obliques", "Quads",
    "Rear Deltoid", "Triceps", "Upper Chest", "Upper Traps",
)
PREMADE_TAGS = (
    "Upper", "Lower", "Core", "Push", "Pull", "Legs", "Back", "Chest", "Hypertrophy",
    "Strength", "Plyometrics", "Calisthenics", "Circuit", "Beginner", "Intermediate",
    "Advanced", "Endurance", "Flexibility", "Stability", "Cardio", "Functional", "Bodyweight",
)


class DomainProjectionError(ValueError):
    pass


def deterministic_seed_uuid(value):
    value_hash = hashlib.md5(value.encode(), usedforsecurity=False).hexdigest()
    return uuid.UUID(f"{value_hash[:8]}-{value_hash[8:12]}-5{value_hash[13:16]}-a{value_hash[17:20]}-{value_hash[20:32]}")


def seed_premade_domain_data(user):
    for name in PREMADE_MUSCLES:
        existing = db.session.execute(db.select(Muscle).filter(db.func.lower(Muscle.name) == name.lower())).scalar_one_or_none()
        if not existing:
            db.session.add(Muscle(
                id=deterministic_seed_uuid(f"apexstrength:muscle:{name.lower()}"),
                name=name,
                color_hex="8AC5FF",
            ))
    for name in PREMADE_TAGS:
        existing = db.session.execute(db.select(Tag).filter(
            Tag.user_id == user.id, db.func.lower(Tag.name) == name.lower()
        )).scalar_one_or_none()
        if not existing:
            tag_id = deterministic_seed_uuid(f"apexstrength:tag:{user.id}:{name.lower()}")
            db.session.add(Tag(id=tag_id, user_id=user.id, client_uuid=str(tag_id), name=name))


def parsed_datetime(value, default=None):
    if not value:
        return default
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError as error:
        raise DomainProjectionError(f"Invalid date: {value}") from error


def domain_row(model, user_id, client_uuid):
    return db.session.execute(db.select(model).filter_by(
        user_id=user_id, client_uuid=client_uuid
    )).scalar_one_or_none()


def require_domain_row(model, user_id, client_uuid, field):
    # The current child row is still incomplete; do not let this lookup flush it
    # before its required foreign keys have been assigned.
    with db.session.no_autoflush:
        row = domain_row(model, user_id, str(client_uuid or ""))
    if not row:
        raise DomainProjectionError(f"{field} references a record that has not been synced.")
    return row


def upsert_muscle(raw_id, name, color):
    if not raw_id:
        return None
    try:
        muscle_id = uuid.UUID(str(raw_id))
    except ValueError as error:
        raise DomainProjectionError("Muscle identifiers must be UUIDs.") from error
    muscle = db.session.get(Muscle, muscle_id)
    if not muscle and name:
        muscle = db.session.execute(db.select(Muscle).filter(
            db.func.lower(Muscle.name) == str(name).lower()
        )).scalar_one_or_none()
    if not muscle:
        muscle = Muscle(id=muscle_id, name=str(name or "Unknown")[:120], color_hex=str(color or "8AC5FF")[:6])
        db.session.add(muscle)
    else:
        muscle.name = str(name or muscle.name)[:120]
        muscle.color_hex = str(color or muscle.color_hex)[:6]
    return muscle


def project_domain_delete(user_id, entity, client_uuid):
    if entity == "settings":
        settings = db.session.get(UserSettings, user_id)
        if settings:
            db.session.delete(settings)
        return
    model = DOMAIN_MODELS.get(entity)
    if model:
        row = domain_row(model, user_id, client_uuid)
        if row:
            db.session.delete(row)


def project_domain_upsert(user_id, entity, client_uuid, data, now):
    """Project one accepted sync change into its normalized domain table."""
    if entity == "settings":
        row = db.session.get(UserSettings, user_id) or UserSettings(user_id=user_id)
        db.session.add(row)
        row.weight_unit = str(data.get("weight_unit") or "lbs")
        row.distance_unit = str(data.get("distance_unit") or "mi")
        row.rest_timer_notifications_enabled = bool(data.get("rest_timer_notifications_enabled", True))
        return

    model = DOMAIN_MODELS.get(entity)
    if not model:
        return
    row = domain_row(model, user_id, client_uuid)
    if entity == "tag" and not row and data.get("name"):
        row = db.session.execute(db.select(Tag).filter(
            Tag.user_id == user_id,
            db.func.lower(Tag.name) == str(data["name"]).lower(),
        )).scalar_one_or_none()
        if row:
            row.client_uuid = client_uuid
    if not row:
        row = model(user_id=user_id, client_uuid=client_uuid)
        db.session.add(row)

    if entity == "exercise":
        row.name = str(data.get("name") or "Untitled Exercise")[:160]
        row.created_at = parsed_datetime(data.get("created_at"), now)
        row.is_archived = bool(data.get("is_archived", False))
        row.tracking_type = str(data.get("tracking_type") or "reps|weighted")[:80]
        row.target_rest_seconds = int(data.get("target_rest_seconds", 120))
        primary = upsert_muscle(data.get("primary_muscle_id"), data.get("primary_muscle_name"), data.get("primary_muscle_color"))
        # Assign the relationship, not only its foreign-key value, so SQLAlchemy
        # orders a newly created muscle before the exercise that references it.
        row.primary_muscle = primary
        secondary_ids = data.get("secondary_muscle_ids") or []
        row.secondary_muscles = [
            upsert_muscle(raw_id, "Unknown", "8AC5FF") for raw_id in secondary_ids
        ]
    elif entity == "tag":
        row.name = str(data.get("name") or "Untitled Tag")[:120]
    elif entity == "workout":
        row.name = str(data.get("name") or "Untitled Workout")[:160]
        row.created_at = parsed_datetime(data.get("created_at"), now)
        row.updated_at = parsed_datetime(data.get("updated_at"), now)
        row.is_archived = bool(data.get("is_archived", False))
        row.tags = [require_domain_row(Tag, user_id, item, "tag_ids") for item in data.get("tag_ids") or []]
    elif entity == "template_exercise":
        row.workout_template_id = require_domain_row(WorkoutTemplate, user_id, data.get("workout_id"), "workout_id").id
        row.exercise_id = require_domain_row(Exercise, user_id, data.get("exercise_id"), "exercise_id").id
        row.position = int(data.get("position", 0))
        row.alternate_exercises = [
            require_domain_row(Exercise, user_id, item, "alternate_exercise_ids")
            for item in data.get("alternate_exercise_ids") or []
        ]
    elif entity == "template_set":
        row.template_exercise_id = require_domain_row(TemplateExercise, user_id, data.get("template_exercise_id"), "template_exercise_id").id
        row.set_number = int(data.get("number", 1))
        row.is_warmup = bool(data.get("warmup", False))
        row.planned_reps = data.get("reps")
        row.planned_time_seconds = data.get("time_seconds")
        row.planned_distance = data.get("distance")
        row.planned_weight = data.get("weight")
    elif entity == "workout_session":
        workout_id = data.get("workout_id")
        row.workout_template_id = require_domain_row(WorkoutTemplate, user_id, workout_id, "workout_id").id if workout_id else None
        row.started_at = parsed_datetime(data.get("started_at"), now)
        row.ended_at = parsed_datetime(data.get("ended_at"))
        row.duration_seconds = data.get("duration_seconds")
        row.rating = data.get("rating")
        row.note = data.get("note")
        row.percent_completed = data.get("percent_completed")
        row.volume_weight = data.get("volume_weight")
        row.average_rest_seconds = data.get("average_rest_seconds")
        row.estimated_intensity = data.get("estimated_intensity")
    elif entity == "session_exercise":
        row.workout_session_id = require_domain_row(WorkoutSession, user_id, data.get("session_id"), "session_id").id
        exercise_id = data.get("exercise_id")
        row.exercise_id = require_domain_row(Exercise, user_id, exercise_id, "exercise_id").id if exercise_id else None
        row.position = int(data.get("position", 0))
        row.exercise_name = str(data.get("name") or "Untitled Exercise")[:160]
        row.tracking_type = str(data.get("tracking_type") or "")[:80]
        row.difficulty_type = str(data.get("difficulty_type") or "")[:80]
        row.primary_muscle_name = str(data.get("primary_muscle_name") or "")[:120]
        row.primary_muscle_color_hex = str(data.get("primary_muscle_color") or "")[:6]
        row.target_rest_seconds = data.get("target_rest_seconds")
    elif entity == "session_set":
        row.session_exercise_id = require_domain_row(SessionExercise, user_id, data.get("session_exercise_id"), "session_exercise_id").id
        row.set_number = int(data.get("number", 1))
        row.completed = bool(data.get("completed", False))
        row.completed_at = parsed_datetime(data.get("completed_at"))
        row.is_warmup = bool(data.get("warmup", False))
        row.reps = data.get("reps")
        row.time_seconds = data.get("time_seconds")
        row.distance = data.get("distance")
        row.weight = data.get("weight")
        row.pace = data.get("pace")


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def authenticated_user():
    header = request.headers.get("Authorization", "")
    token = header.removeprefix("Bearer ") if header.startswith("Bearer ") else ""
    if not token:
        return None
    return db.session.execute(db.select(User).filter_by(session_token_hash=digest(token))).scalar_one_or_none()


def generate_code():
    """Return a cryptographically secure, zero-padded six-digit code."""
    return f"{secrets.randbelow(1_000_000):06d}"


def email_content(purpose, code):
    if purpose == "password_reset":
        return (
            "Reset your Ape X Strength password",
            f"Your password reset code is {code}. It expires in 10 minutes. "
            "If you did not request this, you can ignore this email.",
        )
    return (
        "Verify your Ape X Strength email",
        f"Your email verification code is {code}. It expires in 10 minutes.",
    )


def send_email(email, code, purpose):
    sender = app.config.get("CODE_SENDER")
    if sender:
        sender(email, code, purpose)
        return

    subject, content = email_content(purpose, code)
    transport = app.config.get("EMAIL_TRANSPORT") or (
        "brevo" if app.config["APP_ENV"] == "production" else "mailpit"
    )
    if transport == "brevo":
        api_key = app.config.get("BREVO_API_KEY")
        if not api_key:
            raise RuntimeError("BREVO_API_KEY is required in production.")
        payload = json.dumps({
            "sender": {
                "email": app.config["EMAIL_FROM_EMAIL"],
                "name": app.config["EMAIL_FROM_NAME"],
            },
            "to": [{"email": email}],
            "subject": subject,
            "textContent": content,
        }).encode()
        brevo_request = urllib.request.Request(
            app.config["BREVO_API_URL"],
            data=payload,
            headers={
                "api-key": api_key,
                "accept": "application/json",
                "content-type": "application/json",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(brevo_request, timeout=10) as response:
                if response.status != 201:
                    raise RuntimeError(f"Brevo returned HTTP {response.status}.")
        except urllib.error.HTTPError as error:
            raise RuntimeError(f"Brevo returned HTTP {error.code}.") from error
        return

    if transport != "mailpit":
        raise RuntimeError(f"Unsupported EMAIL_TRANSPORT: {transport}")

    message = EmailMessage()
    message["Subject"] = subject
    message["From"] = f'{app.config["EMAIL_FROM_NAME"]} <{app.config["EMAIL_FROM_EMAIL"]}>'
    message["To"] = email
    message.set_content(content)
    with smtplib.SMTP(app.config["SMTP_HOST"], app.config["SMTP_PORT"], timeout=10) as smtp:
        if app.config.get("SMTP_USERNAME"):
            smtp.login(app.config["SMTP_USERNAME"], app.config.get("SMTP_PASSWORD", ""))
        smtp.send_message(message)


@app.get("/")
def home():
    return {"name": "Ape X Strength API", "status": "running"}


@app.post("/v1/auth/send-code")
def send_code():
    data = request.get_json(silent=True) or {}
    email = str(data.get("email", "")).strip().lower()
    password = str(data.get("password", ""))
    if "@" not in email:
        return jsonify(error="Enter a valid email address."), 400
    if len(password) < 8:
        return jsonify(error="Password must contain at least 8 characters."), 400

    user = db.session.execute(db.select(User).filter_by(email=email)).scalar_one_or_none()
    if user and user.email_verified:
        return jsonify(error="An account with this email already exists. Log in instead."), 409
    if user and not check_password_hash(user.password_hash, password):
        return jsonify(error="Incorrect email or password."), 401
    if not user:
        user = User(email=email, password_hash=generate_password_hash(password))
        db.session.add(user)
        db.session.flush()
        seed_premade_domain_data(user)

    code = generate_code()
    user.verification_code_hash = digest(code)
    user.verification_code_expires_at = datetime.now(timezone.utc) + timedelta(minutes=10)
    send_email(email, code, "verification")
    db.session.commit()
    return "", 204


@app.post("/v1/auth/login")
def login():
    data = request.get_json(silent=True) or {}
    email = str(data.get("email", "")).strip().lower()
    password = str(data.get("password", ""))
    user = db.session.execute(db.select(User).filter_by(email=email)).scalar_one_or_none()
    if not user or not check_password_hash(user.password_hash, password):
        return jsonify(error="Incorrect email or password."), 401
    if not user.email_verified:
        return jsonify(error="Verify your email before logging in."), 403

    token = secrets.token_urlsafe(32)
    user.session_token_hash = digest(token)
    db.session.commit()
    return jsonify(token=token, user=user.json())


@app.post("/v1/auth/request-password-reset")
def request_password_reset():
    data = request.get_json(silent=True) or {}
    email = str(data.get("email", "")).strip().lower()
    if "@" not in email:
        return jsonify(error="Enter a valid email address."), 400

    user = db.session.execute(db.select(User).filter_by(email=email)).scalar_one_or_none()
    if user and user.email_verified:
        code = generate_code()
        user.password_reset_code_hash = digest(code)
        user.password_reset_code_expires_at = datetime.now(timezone.utc) + timedelta(minutes=10)
        send_email(email, code, "password_reset")
        db.session.commit()

    # Deliberately identical for known and unknown addresses to prevent enumeration.
    return jsonify(message="If an account exists for that email, a reset code has been sent."), 200


@app.post("/v1/auth/reset-password")
def reset_password():
    data = request.get_json(silent=True) or {}
    email = str(data.get("email", "")).strip().lower()
    code = str(data.get("code", "")).strip()
    password = str(data.get("password", ""))
    if len(password) < 8:
        return jsonify(error="Password must contain at least 8 characters."), 400

    user = db.session.execute(db.select(User).filter_by(email=email)).scalar_one_or_none()
    now = datetime.now(timezone.utc)
    expires_at = user.password_reset_code_expires_at if user else None
    if expires_at and expires_at.tzinfo is None:
        now = now.replace(tzinfo=None)
    if not user or not expires_at or expires_at <= now or user.password_reset_code_hash != digest(code):
        return jsonify(error="Invalid or expired password reset code."), 400

    user.password_hash = generate_password_hash(password)
    user.password_reset_code_hash = None
    user.password_reset_code_expires_at = None
    user.session_token_hash = None
    db.session.commit()
    return "", 204


@app.post("/v1/auth/verify-code")
def verify_code():
    data = request.get_json(silent=True) or {}
    email = str(data.get("email", "")).strip().lower()
    code = str(data.get("code", "")).strip()
    user = db.session.execute(db.select(User).filter_by(email=email)).scalar_one_or_none()
    now = datetime.now(timezone.utc)
    expires_at = user.verification_code_expires_at if user else None
    if expires_at and expires_at.tzinfo is None:
        now = now.replace(tzinfo=None)
    if not user or not expires_at or expires_at <= now or user.verification_code_hash != digest(code):
        return jsonify(error="Invalid or expired verification code."), 400

    token = secrets.token_urlsafe(32)
    user.email_verified = True
    user.verification_code_hash = None
    user.verification_code_expires_at = None
    user.session_token_hash = digest(token)
    db.session.commit()
    return jsonify(token=token, user=user.json())


@app.patch("/v1/profile")
def save_profile():
    user = authenticated_user()
    if not user:
        return jsonify(error="Unauthorized."), 401

    name = str((request.get_json(silent=True) or {}).get("name", "")).strip()
    if not name or len(name) > 120:
        return jsonify(error="Enter a valid name."), 400
    user.name = name
    db.session.commit()
    return jsonify(user=user.json())


@app.post("/v1/auth/sign-out")
def sign_out():
    header = request.headers.get("Authorization", "")
    token = header.removeprefix("Bearer ") if header.startswith("Bearer ") else ""
    user = db.session.execute(db.select(User).filter_by(session_token_hash=digest(token))).scalar_one_or_none()
    if not token or not user:
        return jsonify(error="Unauthorized."), 401

    user.session_token_hash = None
    db.session.commit()
    return "", 204


@app.delete("/v1/account")
def delete_account():
    user = authenticated_user()
    if not user:
        return jsonify(error="Unauthorized."), 401

    db.session.delete(user)
    db.session.commit()
    return "", 204


@app.delete("/v1/data")
def reset_data():
    user = authenticated_user()
    if not user:
        return jsonify(error="Unauthorized."), 401

    # Every predicate is ownership-scoped. Deleting parent rows cascades to their
    # child and join-table rows while leaving global muscles and other users alone.
    db.session.execute(db.delete(WorkoutSession).where(WorkoutSession.user_id == user.id))
    db.session.execute(db.delete(WorkoutTemplate).where(WorkoutTemplate.user_id == user.id))
    db.session.execute(db.delete(Exercise).where(Exercise.user_id == user.id))
    db.session.execute(db.delete(Tag).where(Tag.user_id == user.id))
    db.session.execute(db.delete(SyncRecord).where(SyncRecord.user_id == user.id))
    user.sync_data = None
    user.synced_at = None
    user.sync_revision = 0
    db.session.commit()
    return "", 204


@app.put("/v1/sync")
def sync_data():
    user = authenticated_user()
    if not user:
        return jsonify(error="Unauthorized."), 401

    payload = request.get_json(silent=True) or {}
    changes = payload.get("changes")
    cursor = payload.get("cursor", 0)
    if not isinstance(changes, list) or not isinstance(cursor, int) or cursor < 0:
        return jsonify(error="Invalid incremental sync request."), 400

    accepted = []
    conflicts = []
    now = datetime.now(timezone.utc)
    append_only = {"workout_session", "session_exercise", "session_set"}
    for change in changes:
        if not isinstance(change, dict):
            db.session.rollback()
            return jsonify(error="Invalid sync change."), 400
        entity = str(change.get("entity", ""))
        client_uuid = str(change.get("client_uuid", ""))
        operation = str(change.get("operation", ""))
        if not entity or not client_uuid or operation not in {"upsert", "delete"}:
            db.session.rollback()
            return jsonify(error="Invalid sync change."), 400
        record = db.session.execute(db.select(SyncRecord).filter_by(
            user_id=user.id, entity_type=entity, client_uuid=client_uuid
        )).scalar_one_or_none()

        # Historical sessions are idempotent create-only records.
        if entity in append_only and record:
            accepted.append({"entity": entity, "client_uuid": client_uuid, "revision": record.revision})
            continue
        # A tombstone cannot be overwritten by an old device.
        if record and record.deleted_at is not None and operation != "delete":
            conflicts.append({"entity": entity, "client_uuid": client_uuid, "revision": record.revision,
                              "operation": "delete", "data": None})
            continue

        user.sync_revision += 1
        if not record:
            record = SyncRecord(user_id=user.id, entity_type=entity, client_uuid=client_uuid)
            db.session.add(record)
        record.revision = user.sync_revision
        record.updated_at = now
        try:
            if operation == "delete":
                record.deleted_at = now
                record.data = None
                project_domain_delete(user.id, entity, client_uuid)
            else:
                data = change.get("data") or {}
                if not isinstance(data, dict):
                    raise DomainProjectionError("Sync data must be an object.")
                # Server arrival order provides last-write-wins per independent record.
                record.deleted_at = None
                record.data = data
                project_domain_upsert(user.id, entity, client_uuid, data, now)
        except (DomainProjectionError, TypeError, ValueError) as error:
            db.session.rollback()
            return jsonify(error=str(error)), 400
        accepted.append({"entity": entity, "client_uuid": client_uuid, "revision": record.revision})

    remote = db.session.execute(
        db.select(SyncRecord).filter(SyncRecord.user_id == user.id, SyncRecord.revision > cursor)
        .order_by(SyncRecord.revision)
    ).scalars().all()
    user.synced_at = now
    db.session.commit()
    return jsonify(
        cursor=user.sync_revision,
        accepted=accepted,
        conflicts=conflicts,
        changes=[{
            "entity": row.entity_type,
            "client_uuid": row.client_uuid,
            "revision": row.revision,
            "operation": "delete" if row.deleted_at else "upsert",
            "data": row.data,
        } for row in remote],
    )

if __name__ == "__main__":
    app.run(debug=True, host='0.0.0.0')
