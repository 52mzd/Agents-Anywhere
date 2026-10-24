# Database Guidelines

> How this project talks to its database.

---

## Overview

<!--
Describe this project's database conventions.

Questions worth answering:
- Which query layer or ORM is actually used?
- How are migrations authored, reviewed and applied?
- What are the naming rules for tables, columns and indexes?
- How are transactions scoped, and who is allowed to open one?
-->

(To be filled by the team)

---

## Query Patterns

<!-- How queries are written, how lists are batched, what N+1 looks like here -->

(To be filled by the team)

---

## Migrations

<!-- How to add, order, and roll back a migration -->

(To be filled by the team)

---

## Naming Conventions

<!-- Tables, columns, indexes, constraints -->

(To be filled by the team)

---

## Common Mistakes

<!-- Database mistakes this team has already made -->

### Hand-inserted test user cannot log in (email_verified_at is NULL)

**Scope / Trigger**: seeding a test account straight into PostgreSQL (e.g. for
simulator/device verification on a self-hosted instance where open registration
is closed).

**Contract** — `agent_server/infra/repositories/email_accounts.py:117`
(`_email_login_row`) requires ALL of: `email` match, `disabled == 0`, and
**`email_verified_at IS NOT NULL`**. A row with `email_verified_at = NULL`
makes `/api/v2/auth/login` return 401 `invalid credentials` even though the
password hash is correct. Registration-closed instances hit this because the
normal register flow always sets the timestamp.

**Password hash format** — `agent_server/core/auth.py:67` (`hash_password`):

```
pbkdf2_sha256$<urlsafe-b64 salt>$<urlsafe-b64 PBKDF2-SHA256 digest, no padding>
```

120,000 iterations, UTF-8 password and salt. Reproduce in one line:

```python
import hashlib, secrets, base64
salt = secrets.token_urlsafe(16)
digest = hashlib.pbkdf2_hmac("sha256", "pw".encode(), salt.encode(), 120000)
stored = f"pbkdf2_sha256${salt}${base64.urlsafe_b64encode(digest).decode().rstrip('=')}"
```

**Wrong vs Correct**

```sql
-- Wrong: login returns 401 despite a valid hash
INSERT INTO users (id, password_hash, role, disabled, created_at, updated_at, email, display_name)
VALUES ('usr_x', '<hash>', 'member', 0, now_iso, now_iso, 't@local.test', 'T');

-- Correct: the update that fixes it
UPDATE users SET email_verified_at = '<iso8601>' WHERE email = 't@local.test';
```

Verify before handing the account to a client:

```bash
curl -s -X POST http://127.0.0.1:19000/api/v2/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"t@local.test","password":"pw"}'   # must return accessToken
```
