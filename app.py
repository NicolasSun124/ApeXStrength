import hashlib
import os
import secrets
import smtplib
import uuid
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
    VERIFICATION_CODE=os.getenv("VERIFICATION_CODE", "123456"),
    SMTP_HOST=os.getenv("SMTP_HOST"),
    SMTP_PORT=int(os.getenv("SMTP_PORT", "587")),
    SMTP_USERNAME=os.getenv("SMTP_USERNAME"),
    SMTP_PASSWORD=os.getenv("SMTP_PASSWORD"),
    SMTP_FROM_EMAIL=os.getenv("SMTP_FROM_EMAIL"),
)
db = SQLAlchemy(app)


class User(db.Model):
    __tablename__ = "users"

    id = db.Column(db.Uuid, primary_key=True, default=uuid.uuid4)
    email = db.Column(db.String(320), unique=True, nullable=False)
    password_hash = db.Column(db.Text, nullable=False)
    verification_code_hash = db.Column(db.String(64))
    verification_code_expires_at = db.Column(db.DateTime(timezone=True))
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


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def authenticated_user():
    header = request.headers.get("Authorization", "")
    token = header.removeprefix("Bearer ") if header.startswith("Bearer ") else ""
    if not token:
        return None
    return db.session.execute(db.select(User).filter_by(session_token_hash=digest(token))).scalar_one_or_none()


def send_email(email, code):
    sender = app.config.get("CODE_SENDER")
    if sender:
        sender(email, code)
        return

    host = app.config.get("SMTP_HOST")
    from_email = app.config.get("SMTP_FROM_EMAIL")
    if not host or not from_email:
        return  # Local prototype mode: use VERIFICATION_CODE=123456.

    message = EmailMessage()
    message["Subject"] = "Your Ape X Strength verification code"
    message["From"] = from_email
    message["To"] = email
    message.set_content(f"Your verification code is {code}. It expires in 10 minutes.")
    with smtplib.SMTP(host, app.config["SMTP_PORT"], timeout=10) as smtp:
        smtp.starttls()
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
    if user and not check_password_hash(user.password_hash, password):
        return jsonify(error="Incorrect email or password."), 401
    if not user:
        user = User(email=email, password_hash=generate_password_hash(password))
        db.session.add(user)

    code = app.config["VERIFICATION_CODE"]
    user.verification_code_hash = digest(code)
    user.verification_code_expires_at = datetime.now(timezone.utc) + timedelta(minutes=10)
    send_email(email, code)
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
        entity = str(change.get("entity", ""))
        client_uuid = str(change.get("client_uuid", ""))
        operation = str(change.get("operation", ""))
        if not entity or not client_uuid or operation not in {"upsert", "delete"}:
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
        if operation == "delete":
            record.deleted_at = now
            record.data = None
        else:
            # Server arrival order provides last-write-wins per independent record.
            record.deleted_at = None
            record.data = change.get("data") or {}
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
