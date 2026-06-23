-- ── Метаданные ───────────────────────────────────────────────────────────────
id       = "websearch"
name     = "Web Search"
version  = "1.0.0"
baseUrl  = "https://www.google.com/"
language = "en"
icon     = "https://github.com/Vaizer0/external-sources/blob/main/icons/websearch.png?raw=true"
charset  = "UTF-8"

-- ── Настройки ────────────────────────────────────────────────────────────────
local PREF_ENGINE = "websearch_engine"

local function getEngine()
    local v = get_preference(PREF_ENGINE)
    return (v ~= "" and v) or "google"
end

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local function absUrl(href, base)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(base or baseUrl, href)
end

-- Retry wrapper (as per guide)
local function http_get_retry(url, config, retries)
    retries = retries or 3
    for attempt = 1, retries do
        local r = http_get(url, config)
        if r.success then return r end
        if attempt < retries then sleep(200 * attempt) end
    end
    log_error("websearch: http_get_retry failed for " .. url)
    return { success = false, code = 0, body = "" }
end

-- Standard text cleaning (from guide)
local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    text = regex_replace(text, "(?i)\\A[\\s\\uFEFF]*((Глава\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
    text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
    text = string_trim(text)
    return text
end

-- ── Каталог (пустой – используется только поиск) ──────────────────────────

function getCatalogList(index)
    return { items = {}, hasNext = false }
end

-- ── Поиск ────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
    if query == "" then
        return { items = {}, hasNext = false }
    end

    local engine = getEngine()
    local page = index + 1
    local url

    if engine == "google" then
        url = "https://www.google.com/search?q=" .. url_encode(query) .. "&start=" .. tostring((page - 1) * 10)
    elseif engine == "duckduckgo" then
        url = "https://html.duckduckgo.com/html/?q=" .. url_encode(query) .. "&s=" .. tostring((page - 1) * 10)
    else
        return { items = {}, hasNext = false }
    end

    local r = http_get_retry(url, {
        headers = {
            ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            ["Accept-Language"] = "en-US,en;q=0.5"
            -- User-Agent and Referer are added automatically by the engine
        }
    }, 2)

    if not r.success then
        log_error("websearch: search failed code=" .. tostring(r.code))
        return { items = {}, hasNext = false }
    end

    local html = r.body
    local items = {}

    if engine == "google" then
        -- Google result blocks: <div class="g"> or <div data-sokoban-container>
        for _, block in ipairs(html_select(html, "div.g, div[data-sokoban-container]")) do
            local titleEl = html_select_first(block.html, "a[href^='/url?']")
            if titleEl then
                local title = html_select_first(block.html, "h3")
                if title then
                    title = string_clean(title.text)
                else
                    title = string_clean(titleEl.text) or "Untitled"
                end
                local link = titleEl.href
                -- Extract real URL from Google redirect
                local realUrl = string.match(link, "q=([^&]+)")
                if realUrl then
                    realUrl = url_decode(realUrl)
                else
                    realUrl = absUrl(link, "https://www.google.com")
                end
                if realUrl and realUrl ~= "" then
                    table.insert(items, {
                        title = title,
                        url   = realUrl,
                        cover = ""  -- no cover for generic pages
                    })
                end
            end
        end
    elseif engine == "duckduckgo" then
        for _, a in ipairs(html_select(html, "a.result__a")) do
            local title = string_clean(a.text)
            local link = a.href
            if link and title ~= "" then
                table.insert(items, {
                    title = title,
                    url   = absUrl(link, "https://html.duckduckgo.com"),
                    cover = ""
                })
            end
        end
    end

    -- Determine if there's a next page (simple heuristic: if we got at least 10 items)
    local hasNext = #items >= 10
    return { items = items, hasNext = hasNext }
end

-- ── Детали "книги" (для выбранной страницы) ──────────────────────────────

function getBookTitle(bookUrl)
    local r = http_get_retry(bookUrl, {
        headers = { ["Accept"] = "text/html,application/xhtml+xml" }
    }, 2)
    if not r.success then return "Web Page" end
    local el = html_select_first(r.body, "title")
    return el and string_clean(el.text) or "Web Page"
end

function getBookCoverImageUrl(bookUrl)
    return nil
end

function getBookDescription(bookUrl)
    return "Loaded from: " .. bookUrl
end

function getChapterListHash(bookUrl)
    return "1"  -- single chapter, always the same
end

-- ── Список глав (всегда одна глава) ────────────────────────────────────────

function getChapterList(bookUrl)
    return {{
        title = "Page Content",
        url   = bookUrl
    }}
end

-- ── Текст главы (содержимое страницы) ─────────────────────────────────────

local function cleanWebPageText(html)
    -- Remove scripts, styles, navigation, ads, etc.
    local cleaned = html_remove(html,
        "script", "style", "noscript",
        "nav", "footer", "aside",
        ".ads", ".advertisement", ".popup"
    )
    local body = html_select_first(cleaned, "body")
    if not body then
        -- Fallback: entire document
        local text = html_text(cleaned)
        return applyStandardContentTransforms(text)
    end
    local text = html_text(body.html)
    -- Collapse multiple newlines
    text = string_normalize(text)
    text = regex_replace(text, "\\n\\s*\\n", "\n\n")
    return applyStandardContentTransforms(text)
end

function getChapterText(html, chapterUrl)
    if not chapterUrl or chapterUrl == "" then
        chapterUrl = html_attr(html, "link[rel='canonical']", "href")
    end
    if not chapterUrl or chapterUrl == "" then
        log_error("websearch: no chapterUrl available")
        return ""
    end

    log_info("websearch: fetching page " .. chapterUrl)

    -- If html is provided (from engine), we could use it, but we fetch fresh to avoid cache issues
    local r = http_get_retry(chapterUrl, {
        headers = {
            ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            ["Accept-Language"] = "en-US,en;q=0.5",
            ["Referer"] = "https://www.google.com/"
        }
    }, 2)

    if not r.success then
        log_error("websearch: failed to fetch " .. chapterUrl .. " code=" .. tostring(r.code))
        return ""
    end

    local text = cleanWebPageText(r.body)
    if text == "" then
        log_error("websearch: empty content for " .. chapterUrl)
        return ""
    end

    log_info("websearch: extracted " .. tostring(#text) .. " characters")
    return text
end

-- ── Настройки плагина ──────────────────────────────────────────────────────

function getSettingsSchema()
    return {{
        key     = PREF_ENGINE,
        type    = "select",
        label   = "Search Engine",
        current = getEngine(),
        options = {
            { value = "google",      label = "Google" },
            { value = "duckduckgo",  label = "DuckDuckGo (HTML)" }
        }
    }}
end

-- ── Неиспользуемые, но обязательные функции (заглушки) ──────────────────────

function getBookGenres(bookUrl)
    return {}
end

function getFilterList()
    return {}
end

function getCatalogFiltered(index, filters)
    return { items = {}, hasNext = false }
end
