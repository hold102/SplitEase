# Full setup

Everything you need to run SplitEase locally. For hosting, see [DEPLOY.md](DEPLOY.md).

---

## Prerequisites

- [Node.js 20+](https://nodejs.org)
- [Flutter 3+](https://flutter.dev/docs/get-started/install)
- A [Supabase](https://supabase.com) project
- Optional: a [Brevo](https://brevo.com) account for verification emails. Without `BREVO_API_KEY`, the verification link is printed to the backend console instead.

---

## 1. Database Setup

1. Open your Supabase project → **SQL Editor**
2. Run `backend/src/db/migrations/001_initial_schema.sql`
3. Run `backend/src/db/migrations/002_split_amounts.sql`
4. Run `backend/src/db/migrations/003_friends_settlements_verification.sql` (friends, settle-ups, email verification, row-level security)

---

## 2. Backend Setup

```bash
cd backend
cp .env.example .env
npm install
npm run dev
```

Fill in `backend/.env`:

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SECRET_KEY=your-service-role-key
BREVO_API_KEY=your-brevo-api-key   # optional
APP_BASE_URL=http://localhost:5001
PORT=5001
```

- `SUPABASE_URL` and `SUPABASE_SECRET_KEY` → Supabase dashboard → Project Settings → API
- `BREVO_API_KEY` → Brevo dashboard → SMTP & API → API Keys
- `APP_BASE_URL` → the public URL of your backend (use `http://localhost:5001` for local dev)

The API will be running at `http://localhost:5001`.

---

## Demo data

`npm --prefix backend run seed:demo` loads 5 demo people, two groups (a Penang trip and a shared house), equal and exact splits, a settle-up and friend requests. Sign in with `demo@splitease.app` / `splitease-demo`. It only runs on an empty database; `-- --force` replaces existing data.

---

## 3. Frontend Setup

```bash
cd frontend
flutter pub get
flutter run
```

To point the app at a specific backend URL:

```bash
flutter run --dart-define=API_BASE_URL=http://localhost:5001/api
```

For web:

```bash
flutter build web
# Output is in frontend/build/web/
```

---

## 4. Running tests

```bash
# Backend
npm --prefix backend test

# Frontend
cd frontend && flutter test
```
