# Sample Plan

## Global Constraints

- Nothing.

---

### Task 1: Database layer

**Depends on:** none
**Files:**
- Create: `src/db.py`
- Test: `tests/test_db.py`
**Exclusive:** none
**Interfaces:**
- Consumes: nothing
- Produces:
  - `connect(url: str) -> Conn`

- [ ] **Step 1: Do it**

### Task 2: API layer

**Depends on:** Task 1
**Files:**
- Create: `src/api.py`
- Test: `tests/test_api.py`
**Exclusive:** test-port:5432
**Interfaces:**
- Consumes:
  - `connect(url: str) -> Conn`
- Produces:
  - `getUser(id: str) -> User`
  - `UserSchema`

- [ ] **Step 1: Do it**

### Task 3: Settings page

**Depends on:** none
**Files:**
- Create: `web/settings.tsx`
**Exclusive:** none
**Interfaces:**
- Consumes: nothing
- Produces:
  - `SettingsPage`

- [ ] **Step 1: Do it**

Run: `npm test` — a backticked token below a step heading, which must NOT be
captured as a produced symbol.

### Task 4: Migrations

**Depends on:** Task 1
**Files:**
- Modify: `src/db.py:10-40`
**Exclusive:** test-port:5432, package-lock.json
**Interfaces:**
- Consumes:
  - `connect(url: str) -> Conn`
- Produces:
  - `migrate() -> None`

- [ ] **Step 1: Do it**

### Task 5: Profile page

**Depends on:** Task 2
**Files:**
- Create: `web/profile.tsx`
**Exclusive:** none
**Interfaces:**
- Consumes:
  - `getUser(id: str) -> User`
- Produces:
  - `ProfilePage`

- [ ] **Step 1: Do it**
