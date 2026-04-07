# Plan: VoiceInsert billing + entitlement

1. Next.js app in `web/` — landing, Airwallex checkout, claim token, entitlement API, webhooks.
2. PostgreSQL + Prisma for customers, subscriptions, hashed access tokens.
3. macOS app — Keychain token, periodic `/api/entitlement` checks, gate dictation when inactive.
4. Vercel deploy — root directory `web`, env from `.env.example`.
