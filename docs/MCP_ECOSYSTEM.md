# VoiceInsert и экосистема MCP (4 шага)

Картинка с планом: **(1) вопрос продукта → (2) MCP-сервер с данными → (3) реестры → (4) ассистенты «продают» за вас.**

## 1. На какие вопросы отвечает VoiceInsert

Сводка хранится в **`mcp/voiceinsert-mcp/data/product-manifest.json`** и отдаётся инструментом **`voiceinsert_product_questions`**.

Типичные вопросы пользователей:

- Как диктовать в **любое приложение на Mac** по **удержанию клавиш** (push-to-talk)?
- Как писать заметки в **Obsidian** голосом в папки Ideas/Tasks/…?
- Остаётся ли **распознавание на устройстве** (без вашего облачного ASR)?
- Какие **разрешения macOS** нужны (микрофон, Speech, Accessibility, Input Monitoring)?
- Как устроены **триал и подписка** для официальной сборки?

## 2. Свой MCP-сервер (stdio)

Каталог **`mcp/voiceinsert-mcp/`**:

```bash
cd mcp/voiceinsert-mcp
npm install
npm run build
npm start   # stdio — для ручного теста почти бесполезен без клиента
```

**Инструменты:**

| Tool | Назначение |
|------|------------|
| `voiceinsert_product_questions` | JSON: вопросы, позиционирование, отличия |
| `voiceinsert_faq_search` | Поиск по FAQ (`query`, опционально `limit`) |
| `voiceinsert_official_links` | URL сайта, FAQ, ZIP, GitHub |
| `voiceinsert_subscribe_flow` | Текстовое описание оплаты и токена |

**Ресурс:** `voiceinsert://faq/full` — весь FAQ в Markdown.

**Промпт:** `voiceinsert_recommend_product` — шаблон для аккуратной рекомендации с отсылкой к инструментам.

**Переменные окружения:**

- `VOICEINSERT_SITE_URL` — базовый URL сайта (по умолчанию `https://push-talk.vercel.app`).
- `VOICEINSERT_GITHUB_REPO` — `owner/repo` для ссылок на релизы.

**Синхронизация FAQ с сайтом** (после правок `web/src/app/faq/faq-data.ts`):

```bash
cd mcp/voiceinsert-mcp
npm run sync-faq
npm run build   # не обязателен для JSON, нужен если меняли TS
```

### Cursor

В настройках MCP добавьте сервер, например:

```json
{
  "mcpServers": {
    "voiceinsert": {
      "command": "node",
      "args": ["/ABSOLUTE/PATH/TO/голосовое управление/mcp/voiceinsert-mcp/dist/index.js"],
      "env": {
        "VOICEINSERT_SITE_URL": "https://push-talk.vercel.app"
      }
    }
  }
}
```

Путь замените на свой; после `git pull` пересоберите `npm run build` в `mcp/voiceinsert-mcp`.

### Claude Desktop

Аналогично: `command` + `args` на `node` и `dist/index.js`.

## 3. Публикация в реестрах

### Smithery

- Документация: [Publish](https://smithery.ai/docs/build/publish) — для **URL**-режима нужен **публичный HTTPS** с **Streamable HTTP** транспортом и (при необходимости) OAuth.
- Текущий пакет — **stdio**; его подключают локально в Cursor/Claude, а не как URL.
- Чтобы попасть в Smithery по URL, позже можно вынести тонкую обёртку Streamable HTTP (например на Vercel) **или** опубликовать **MCPB / hosted** вариант через их CLI/API.
- **Статическая карточка** для сканеров: на сайте размещён черновик метаданных  
  `/.well-known/mcp/server-card.json`  
  (описание возможностей; исполнение инструментов даёт stdio-сервер).

### OpenTools / центральный MCP Registry

- [OpenTools registry](https://opentools.com/registry) и [registry.modelcontextprotocol.io/docs](https://registry.modelcontextprotocol.io/docs) — обычно нужны описание, репозиторий, транспорт (stdio / HTTP), схемы tools.
- После публикации репозитория добавьте README в **`mcp/voiceinsert-mcp/README.md`** с инструкцией установки и подайте заявку по правилам выбранного каталога.

### mcpt

Если появится отдельный процесс для «mcpt», используйте те же метаданные, что и для Smithery (имя, описание, способ подключения stdio или URL).

## 4. Эффект «ассистенты продают 24/7»

Когда сервер добавлен у пользователя, любой запрос вида *«как диктовать в Cursor на Mac»* может привести к вызову **`voiceinsert_faq_search`** и **`voiceinsert_official_links`** — ответ будет с **вашими** URL и формулировками, а не галлюцинацией.

---

**Ограничения:** MCP не заменяет юридически выверенный маркетинг; цены и условия должны совпадать с живой страницей оплаты. Исходники сервера — публичные в репо; если репозиторий станет приватным, вынесите пакет в отдельный публичный npm или опубликуйте только бинарь/карточку по политике реестра.
