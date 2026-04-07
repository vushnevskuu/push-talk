# VoiceInsert billing site (Next.js + Airwallex)

## Если на Vercel «404: NOT_FOUND»

Репозиторий — **монорепо**: в корне лежит macOS-приложение (Swift), а Next.js только в папке **`web`**.

1. Открой проект на [vercel.com](https://vercel.com) → **Settings** → **Build & Deployment**.
2. Найди **Root Directory** → укажи **`web`** (без слэша, именно эта папка).
3. **Save**, затем **Deployments** → **Redeploy** последнего деплоя (или запушь новый коммит).

**Framework preset:** должен быть **Next.js** (после смены корня обычно подхватывается сам). **Install command** по умолчанию `npm install`, **build** — `npm run build` (из `web/package.json`).

Без шага с Root Directory Vercel собирает пустой корень и выдаёт рабочий по статусу, но пустой сайт → 404.

---

Deploy this folder to **Vercel** with **Root Directory** = `web`.

## SEO & analytics

- Set **`NEXT_PUBLIC_SITE_URL`** (and **`NEXT_PUBLIC_APP_URL`**) to your live `https://…` origin so `metadataBase`, **sitemap.xml**, **robots.txt**, and JSON-LD use correct canonical URLs.
- Submit **`https://YOUR_DOMAIN/sitemap.xml`** in [Google Search Console](https://search.google.com/search-console) (see `tools/integrations/google-search-console.md` in the marketing skills repo for API ideas).
- Optional: **`NEXT_PUBLIC_GOOGLE_SITE_VERIFICATION`** for the meta tag verification method; **`NEXT_PUBLIC_GA_MEASUREMENT_ID`** for GA4 (`gtag.js`) in the root layout.
- Public **`/llms.txt`** hints crawlers at home + FAQ paths.
- Indexed routes: `/`, `/faq`. Not indexed / disallowed: `/gate`, `/success`, `/api/*`.

## Setup

1. Create a **PostgreSQL** database and set `DATABASE_URL` in Vercel → Settings → Environment Variables.
2. Run migrations once (locally with the same `DATABASE_URL`, or via Vercel build + `prisma migrate deploy` in a one-off command):

   ```bash
   cd web
   npm install
   npx prisma migrate deploy
   ```

3. In **Airwallex** (sandbox first): Billing → create a **Product** and **Price** for **$10/month** recurring. Optionally create a **one-time $1** price for the paid trial start; if `billing_checkouts/create` rejects two line items, leave `AIRWALLEX_TRIAL_SETUP_PRICE_ID` empty and keep only the recurring price with a 7-day trial in `subscription_data` (already set in code).
4. Copy **Client ID**, **API key**, **Legal entity ID**, **Linked payment account ID**, and **Price IDs** into Vercel env vars (see `.env.example`).
5. Set **NEXT_PUBLIC_APP_URL** to your production URL (e.g. `https://voiceinsert.vercel.app`).
6. Configure an Airwallex **webhook** to `https://YOUR_DOMAIN/api/webhooks/airwallex` and set `AIRWALLEX_WEBHOOK_SECRET`. Adjust signature verification in `src/lib/webhook-verify.ts` if your dashboard uses a different header format.

## Hidden crew access

There is an unlinked page **`/gate`** (not advertised on the home page) that accepts a login and password and mints the same **access token** the macOS app uses. Prefer overriding credentials with **`VOICEINSERT_CREW_LOGIN`** and **`VOICEINSERT_CREW_PASSWORD`** in Vercel so nothing sensitive lives only in the repo.

## macOS app

Set **VoiceInsertEntitlementBaseURL** in `Resources/Info.plist` (and packaging copy) to the same origin as `NEXT_PUBLIC_APP_URL` (no trailing slash). Leave empty to **disable** subscription UI and enforcement (open-source / local builds).

CI or local automation can set environment variable **`VOICEINSERT_SKIP_ENTITLEMENT=1`** to bypass checks.

## Legacy static page

The old `docs/index.html` GitHub Pages file is superseded by this app; keep it only if you still need a static mirror.
