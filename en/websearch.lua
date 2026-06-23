-- ── Метаданные ───────────────────────────────────────────────────────────────
id       = "websearch"
name     = "Web Search"
version  = "1.0.2"
baseUrl  = "https://www.google.com/"
language = "en"
icon     = "https://github.com/Vaizer0/external-sources/blob/main/icons/websearch.png?raw=true"

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

-- Extract real URL from DuckDuckGo redirect link
local function extractDuckDuckGoUrl(link)
    if not link or link == "" then return "" end
    
    -- Check if it's a DuckDuckGo redirect link
    if string.find(link, "/l/?") or string.find(link, "uddg=") then
        -- Extract the uddg parameter value
        local realUrl = string.match(link, "uddg=([^&]+)")
        if realUrl then
            -- URL-decode the extracted value
            realUrl = url_decode(realUrl)
            -- Also handle double-encoding
            if string.find(realUrl, "%%") then
                realUrl = url_decode(realUrl)
            end
            return realUrl
        end
    end
    
    -- If it's a direct link starting with http, return as-is
    if string_starts_with(link, "http") then
        return link
    end
    
    -- Otherwise try to resolve it
    return absUrl(link, "https://html.duckduckgo.com")
end

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

local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    text = regex_replace(text, "(?i)\\A[\\s\\uFEFF]*((Глава\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
    text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
    text = string_trim(text)
    return text
end

-- ── Каталог (пустой) ──────────────────────────────────────────────────────────

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
        }
    }, 2)

    if not r.success then
        log_error("websearch: search failed code=" .. tostring(r.code))
        return { items = {}, hasNext = false }
    end

    local html = r.body
    local items = {}

    if engine == "google" then
        -- Try multiple selectors for Google result blocks
        local blocks = html_select(html, "div.g, div[data-sokoban-container], div[class*='yuRUbf'], div[class*='tF2Cxc']")
        for _, block in ipairs(blocks) do
            local titleEl = html_select_first(block.html, "a[href^='/url?'], a[href^='http']")
            if titleEl then
                -- Try multiple ways to get the title
                local title = html_select_first(block.html, "h3, h2, h1, div[role='heading'], div[class*='LC20lb']")
                if title then
                    title = string_clean(title.text)
                else
                    title = string_clean(titleEl.text) or "Untitled"
                end
                
                local link = titleEl.href
                local realUrl
                
                if string_starts_with(link, "/url?") then
                    realUrl = string.match(link, "q=([^&]+)")
                    if realUrl then 
                        realUrl = url_decode(realUrl) 
                    end
                else
                    realUrl = absUrl(link, "https://www.google.com")
                end
                
                -- Filter out Google's own internal links
                if realUrl and realUrl ~= "" and 
                   not string.find(realUrl, "google.com") and
                   not string.find(realUrl, "youtube.com") then
                    table.insert(items, {
                        title = title,
                        url   = realUrl,
                        cover = ""
                    })
                end
            end
        end
    elseif engine == "duckduckgo" then
        -- DuckDuckGo: look for result links
        for _, a in ipairs(html_select(html, "a.result__a")) do
            local title = string_clean(a.text)
            local link = a.href
            
            if link and title ~= "" then
                -- Extract the real URL from DuckDuckGo's redirect
                local realUrl = extractDuckDuckGoUrl(link)
                
                -- Filter out DuckDuckGo's own pages
                if realUrl and realUrl ~= "" and 
                   not string.find(realUrl, "duckduckgo.com") then
                    table.insert(items, {
                        title = title,
                        url   = realUrl,
                        cover = ""
                    })
                end
            end
        end
        
        -- Fallback: also try other link selectors if the above didn't work
        if #items == 0 then
            for _, a in ipairs(html_select(html, "a[href*='uddg=']")) do
                local title = string_clean(a.text)
                local link = a.href
                if link and title ~= "" then
                    local realUrl = extractDuckDuckGoUrl(link)
                    if realUrl and realUrl ~= "" and 
                       not string.find(realUrl, "duckduckgo.com") then
                        table.insert(items, {
                            title = title,
                            url   = realUrl,
                            cover = ""
                        })
                    end
                end
            end
        end
    end

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
    return "1"
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
    local cleaned = html_remove(html,
        "script", "style", "noscript",
        "nav", "footer", "aside",
        ".ads", ".advertisement", ".popup"
    )
    local body = html_select_first(cleaned, "body")
    if not body then
        local text = html_text(cleaned)
        return applyStandardContentTransforms(text)
    end
    local text = html_text(body.html)
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

-- ── Настройки ──────────────────────────────────────────────────────────────────

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

-- ── Заглушки ──────────────────────────────────────────────────────────────────

function getBookGenres(bookUrl)
    return {}
end

function getFilterList()
    return {}
end

function getCatalogFiltered(index, filters)
    return { items = {}, hasNext = false }
end
