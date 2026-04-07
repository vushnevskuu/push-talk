# VoiceInsert site (Next.js)

Публичный лендинг, FAQ и раздача **`VoiceInsert-macos.zip`**. Опциональная ссылка на донат: **`NEXT_PUBLIC_DONATION_URL`**. Код Airwallex / entitlement в репозитории остаётся для возможного будущего использования, но основной сценарий — бесплатная сборка без токена.

## Если на Vercel «404: NOT_FOUND»

Репозиторий — **монорепо**: в корне лежит macOS-приложение (Swift), а Next.js только в папке **`web`**.

1. Открой проект на [vercel.com](https://vercel.com) → **Settings** → **Build & Deployment**.
2. Найди **Root Directory** → укажи **`web`** (без слэша, именно эта папка).
3. **Save**, затем **Deployments** → **Redeploy** последнего деплоя (или запушь новый коммит).

**Framework preset:** должен быть **Next.js** (после смены корня обычно подхватывается сам). **Install command** по умолчанию `npm install`, **build** — `npm run build` (из `web/package.json`).

Без шага с Root Directory Vercel собирает пустой корень и выдаёт рабочий по статусу, но пустой сайт → 404.

---

Deploy this folder to **Vercel** with **Root Directory** = `web`.

## Mac app download (`public/VoiceInsert-macos.zip`)

The homepage and `/success` link to **`/VoiceInsert-macos.zip`** (static file). After each app release, rebuild from the repo root and overwrite the file:

```bash
CI=1 ./Scripts/build_app.sh
ditto -c -k --keepParent Build/VoiceInsert.app web/public/VoiceInsert-macos.zip
```

Then commit the new ZIP and deploy. For a **licensed** build only, set `VOICEINSERT_ENTITLEMENT_BASE_URL` when running `build_app.sh` so the plist matches your billing site.

## SEO & analytics

- Set **`NEXT_PUBLIC_SITE_URL`** (and **`NEXT_PUBLIC_APP_URL`**) to your live `https://…` origin so `metadataBase`, **sitemap.xml**, **robots.txt**, and JSON-LD use correct canonical URLs.
- Submit **`https://YOUR_DOMAIN/sitemap.xml`** in [Google Search Console](https://search.google.com/search-console) (see `tools/integrations/google-search-console.md` in the marketing skills repo for API ideas).
- Optional: **`NEXT_PUBLIC_GOOGLE_SITE_VERIFICATION`** for the meta tag verification method; **`NEXT_PUBLIC_GA_MEASUREMENT_ID`** for GA4 (`gtag.js`) in the root layout.
- Public **`/llms.txt`** hints crawlers at home + FAQ paths.
- Indexed routes: `/`, `/faq`. Not indexed / disallowed: `/gate`, `/success`, `/api/*`.

## Setup

1. Set **NEXT_PUBLIC_APP_URL** in Vercel to your production URL (e.g. `https://push-talk.vercel.app`).
2. Optional: **NEXT_PUBLIC_DONATION_URL** — Buy Me a Coffee, Ko-fi, Patreon, etc. (adds **Support** in the footer and on `/success`).
3. **PostgreSQL + `DATABASE_URL` + `npx prisma migrate deploy`** — только если вы снова используете claim/entitlement и вебхуки Airwallex. Для статического лендинга и раздачи ZIP без этих API шаг можно пропустить (сборка Next.js может всё ещё требовать Prisma-схему в репо — смотрите ваш `npm run build` на Vercel).

## Hidden crew access

There is an unlinked page **`/gate`** (not advertised on the home page) that accepts a login and password and mints the same **access token** the macOS app uses. Prefer overriding credentials with **`VOICEINSERT_CREW_LOGIN`** and **`VOICEINSERT_CREW_PASSWORD`** in Vercel so nothing sensitive lives only in the repo.

## macOS app

Set **VoiceInsertEntitlementBaseURL** in `Resources/Info.plist` to the same origin as your deployed site (no trailing slash), or inject it at package time:

```bash
VOICEINSERT_ENTITLEMENT_BASE_URL=https://your-domain.vercel.app ./Scripts/build_app.sh
```

Leave the plist value **empty** to **disable** online license checks (default for the public ZIP).  
CI smoke tests and local runs can also use **`VOICEINSERT_SKIP_ENTITLEMENT=1`** to bypass enforcement.

GitHub **Release** workflow (tags `v*`) собирает ZIP **без** вшитого entitlement URL — публичная раздача остаётся бесплатной.

## Legacy static page

The old `docs/index.html` GitHub Pages file is superseded by this app; keep it only if you still need a static mirror.
