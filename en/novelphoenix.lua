-- Novel Phoenix plugin for NovaLa
-- Source: https://novelphoenix.com/
-- Version: 1.0.5

id       = "novelphoenix"
name     = "Novel Phoenix"
version  = "1.0.5"
baseUrl  = "https://novelphoenix.com"
language = "en"
icon     = "https://novelphoenix.com/logo.png"

local _pageCache = {}

-- ── Helpers ──────────────────────────────────────────────────────────────

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

local function cleanText(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    text = text:gsub("\n%s*\n%s*\n+", "\n\n")
    return string_trim(text)
end

local function lower(s)
    return string.lower(tostring(s or ""))
end

local function containsIgnoreCase(haystack, needle)
    haystack = lower(haystack)
    needle = lower(needle)
    return needle ~= "" and haystack:find(needle, 1, true) ~= nil
end

local function fetchPage(url)
    if _pageCache[url] then
        return _pageCache[url]
    end
    local r = http_get(url)
    if r.success then
        _pageCache[url] = r.body
        return r.body
    end
    return nil
end

-- ── Parsing functions ──────────────────────────────────────────────────

local function parseNovelCard(cardHtml)
    local titleEl =
        html_select_first(cardHtml, "h4.novel-title")
        or html_select_first(cardHtml, ".novel-title")
        or html_select_first(cardHtml, "a[title]")

    local linkEl =
        html_select_first(cardHtml, "a[title]")
        or html_select_first(cardHtml, "a[href*='/novel/']")

    if not titleEl or not linkEl then
        return nil
    end

    local title = string_clean(titleEl.text or "")
    local url = absUrl(linkEl.href or "")
    if title == "" or url == "" then
        return nil
    end

    local cover = html_attr(cardHtml, "img", "data-src")
    if cover == "" then cover = html_attr(cardHtml, "img", "src") end
    if cover == "" then cover = html_attr(cardHtml, "img", "data-lazy-src") end

    return {
        title = title,
        url = url,
        cover = absUrl(cover)
    }
end

local function parseNovelItems(body)
    local items = {}
    local seen = {}

    for _, sel in ipairs({
        "li.novel-item",
        ".novel-item",
        ".rank-container .novel-item",
        ".section-body .novel-item",
        ".novel-list .novel-item",
        ".search-result .novel-item",
    }) do
        for _, card in ipairs(html_select(body, sel)) do
            local item = parseNovelCard(card.html or card)
            if item and not seen[item.url] then
                seen[item.url] = true
                table.insert(items, item)
            end
        end
    end

    if #items == 0 then
        for _, a in ipairs(html_select(body, "a[href*='/novel/']")) do
            local href = absUrl(a.href or "")
            local title = string_clean(a.text or "")
            if href ~= "" and title ~= "" and not seen[href] then
                seen[href] = true
                table.insert(items, {
                    title = title,
                    url = href,
                    cover = ""
                })
            end
        end
    end

    return items
end

-- ── Chapter parsing ────────────────────────────────────────────────────

-- Parse chapters from a single page (supports both <ul> and <select>)
local function parseChaptersFromPage(body, novelSlug)
    local chapters = {}
    local seen = {}

    local function addChapter(title, href)
        href = absUrl(href or "")
        title = string_clean(title or "")

        if href == "" or title == "" or seen[href] then
            return
        end

        if novelSlug and not href:find("/novel/" .. novelSlug .. "/chapter%-") then
            return
        end

        if not href:find("/chapter%-") then
            return
        end

        seen[href] = true
        table.insert(chapters, {
            title = title,
            url = href
        })
    end

    -- Strategy 1: <ul class="chapter-list"> <li> <a> (main chapter list)
    for _, a in ipairs(html_select(body, "ul.chapter-list li a[href*='/chapter-']")) do
        addChapter(a.text or "", a.href or "")
    end

    -- Strategy 2: <select> dropdown (used on reading pages)
    if #chapters == 0 then
        local select = html_select_first(body, "select.chapindex, select#chapter-select")
        if select then
            for _, opt in ipairs(html_select(select.html, "option")) do
                local val = opt:attr("value") or ""
                local text = opt.text or ""
                if val ~= "" then
                    addChapter(text, val)
                end
            end
        end
    end

    -- Strategy 3: Any link with /chapter- (fallback)
    if #chapters == 0 then
        if novelSlug and novelSlug ~= "" then
            for _, a in ipairs(html_select(body, "a[href*='/novel/" .. novelSlug .. "/chapter-']")) do
                addChapter(a.text or "", a.href or "")
            end
        end
        for _, a in ipairs(html_select(body, "a[href*='/chapter-']")) do
            addChapter(a.text or "", a.href or "")
        end
    end

    -- Sort by chapter number
    local numbered = {}
    for _, ch in ipairs(chapters) do
        local n = tonumber((ch.url or ""):match("/chapter%-(%d+)")) or
                  tonumber((ch.url or ""):match("/(%d+)%-.+/?$")) or
                  tonumber((ch.title or ""):match("^(%d+)")) or 0
        table.insert(numbered, { n = n, title = ch.title, url = ch.url })
    end

    table.sort(numbered, function(a, b)
        if a.n == b.n then
            return a.url < b.url
        end
        return a.n < b.n
    end)

    local sorted = {}
    for _, ch in ipairs(numbered) do
        table.insert(sorted, { title = ch.title, url = ch.url })
    end

    return sorted
end

-- Get total pages from pagination
local function getTotalPages(body)
    -- Look for the last page number in pagination
    local lastPageLink = html_select_first(body, ".pagination li:last-child a, .pagination li:last-child span")
    if lastPageLink then
        local text = string_trim(lastPageLink.text or "")
        local num = tonumber(text)
        if num then return num end
    end

    -- Try to find the highest page number in any pagination link
    local maxPage = 1
    for _, a in ipairs(html_select(body, ".pagination a")) do
        local num = tonumber(string_trim(a.text or ""))
        if num and num > maxPage then
            maxPage = num
        end
    end
    return maxPage
end

-- Build URL for a specific page of chapters
local function getChaptersPageUrl(bookUrl, page)
    local base = bookUrl:gsub("/?$", "")
    if page == 1 then
        return base .. "/chapters"
    end
    return base .. "/chapters?page=" .. page
end

-- Fetch all chapters across all pages
local function fetchAllChapters(bookUrl)
    local slug = bookUrl:match("/novel/([^/?#]+)")
    if not slug then
        log_error("novelphoenix: could not extract slug from " .. bookUrl)
        return {}
    end

    -- Fetch first page to get total pages
    local firstUrl = getChaptersPageUrl(bookUrl, 1)
    local firstBody = fetchPage(firstUrl)
    if not firstBody then
        log_error("novelphoenix: failed to fetch chapters page: " .. firstUrl)
        return {}
    end

    local allChapters = {}
    local seen = {}

    local function mergeChapters(list)
        for _, ch in ipairs(list or {}) do
            if ch.url and ch.url ~= "" and not seen[ch.url] then
                seen[ch.url] = true
                table.insert(allChapters, ch)
            end
        end
    end

    -- Parse first page
    mergeChapters(parseChaptersFromPage(firstBody, slug))

    -- Get total pages and fetch remaining pages
    local totalPages = getTotalPages(firstBody)
    if totalPages > 1 then
        for page = 2, totalPages do
            local url = getChaptersPageUrl(bookUrl, page)
            local body = fetchPage(url)
            if body then
                mergeChapters(parseChaptersFromPage(body, slug))
            end
            sleep(100) -- polite delay
        end
    end

    return allChapters
end

-- ── Browse / filter helpers ────────────────────────────────────────────

local function buildBrowseUrl(genre, sort, status, page)
    local g = genre and genre ~= "" and ("genre-" .. genre) or "genre-all"
    local s = sort and sort ~= "" and ("sort-" .. sort) or "sort-new"
    local st = status and status ~= "" and ("status-" .. status) or "status-all"

    local base = baseUrl .. "/" .. g .. "/" .. s .. "/" .. st .. "/all-novel"

    if page and page > 1 then
        return {
            base .. "/page/" .. tostring(page),
            base .. "?page=" .. tostring(page),
            base .. "/" .. tostring(page),
        }
    end

    return { base }
end

local function parseBrowseLikePage(urls)
    for _, u in ipairs(urls) do
        local r = http_get(u)
        if r.success then
            local items = parseNovelItems(r.body)
            if #items > 0 then
                return items
            end
        end
    end
    return {}
end

local function fuzzySearchFallback(query, maxPages)
    local results = {}
    local seen = {}
    local q = lower(query)

    for page = 1, (maxPages or 5) do
        local urls = buildBrowseUrl("all", "new", "all", page)
        local r = http_get(urls[1])
        if not r.success then
            break
        end

        for _, item in ipairs(parseNovelItems(r.body)) do
            if not seen[item.url] then
                local title = lower(item.title)
                if containsIgnoreCase(title, q) or containsIgnoreCase(item.url, q) then
                    seen[item.url] = true
                    table.insert(results, item)
                end
            end
        end
    end

    return results
end

-- ── Required plugin functions ──────────────────────────────────────────

function getFilterList()
    return {
        {
            type = "select",
            key = "sort",
            label = "Sort By",
            defaultValue = "new",
            options = {
                { value = "new",     label = "Newest" },
                { value = "popular", label = "Popular" },
            }
        },
        {
            type = "select",
            key = "status",
            label = "Status",
            defaultValue = "all",
            options = {
                { value = "all",       label = "All" },
                { value = "completed", label = "Completed" },
            }
        },
        {
            type = "checkbox",
            key = "genre",
            label = "Genre",
            multiselect = false,
            options = {
                { value = "action",        label = "Action" },
                { value = "adventure",     label = "Adventure" },
                { value = "comedy",        label = "Comedy" },
                { value = "drama",         label = "Drama" },
                { value = "fantasy",       label = "Fantasy" },
                { value = "historical",    label = "Historical" },
                { value = "horror",        label = "Horror" },
                { value = "josei",         label = "Josei" },
                { value = "martial-arts",  label = "Martial Arts" },
                { value = "mystery",       label = "Mystery" },
                { value = "romance",       label = "Romance" },
                { value = "school-life",   label = "School Life" },
                { value = "sci-fi",        label = "Sci-fi" },
                { value = "slice-of-life", label = "Slice of Life" },
                { value = "supernatural",  label = "Supernatural" },
                { value = "wuxia",         label = "Wuxia" },
                { value = "xianxia",       label = "Xianxia" },
                { value = "xuanhuan",      label = "Xuanhuan" },
            }
        },
    }
end

function getCatalogList(index)
    local page = index + 1
    local urls = buildBrowseUrl("all", "new", "all", page)
    local items = parseBrowseLikePage(urls)

    return {
        items = items,
        hasNext = #items > 0
    }
end

function getCatalogSearch(index, query)
    local page = index + 1
    if page > 1 then
        return { items = {}, hasNext = false }
    end

    local q = url_encode(query or "")

    local searchUrls = {
        baseUrl .. "/search-adv?keyword=" .. q,
        baseUrl .. "/search-adv?query=" .. q,
        baseUrl .. "/search-adv?title=" .. q,
        baseUrl .. "/search-adv?search=" .. q,
        baseUrl .. "/search?keyword=" .. q,
        baseUrl .. "/search?q=" .. q,
        baseUrl .. "/search?query=" .. q,
        baseUrl .. "/search?title=" .. q,
    }

    for _, u in ipairs(searchUrls) do
        local r = http_get(u)
        if r.success then
            local items = parseNovelItems(r.body)
            if #items > 0 then
                return { items = items, hasNext = false }
            end
        end
    end

    -- Fallback: scan browse pages
    local results = {}
    local seen = {}
    local ql = lower(query)

    for pg = 1, 3 do
        local urls = buildBrowseUrl("all", "new", "all", pg)
        local r = http_get(urls[1])
        if not r.success then break end

        for _, item in ipairs(parseNovelItems(r.body)) do
            if not seen[item.url] then
                local title = lower(item.title)
                if containsIgnoreCase(title, ql) then
                    seen[item.url] = true
                    table.insert(results, item)
                end
            end
        end
    end

    return { items = results, hasNext = false }
end

function getCatalogFiltered(index, filters)
    local page = index + 1
    local sort = filters["sort"] or "new"
    local status = filters["status"] or "all"

    local genres = filters["genre_included"] or {}
    local genre = #genres > 0 and genres[1] or "all"

    local urls = buildBrowseUrl(genre, sort, status, page)
    local items = parseBrowseLikePage(urls)

    return {
        items = items,
        hasNext = #items > 0
    }
end

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end

    local el =
        html_select_first(body, "h1.novel-title")
        or html_select_first(body, ".novel-title")
        or html_select_first(body, "h1")

    if el and el.text and el.text ~= "" then
        return string_clean(el.text)
    end

    local og = html_select_first(body, "meta[property='og:title']")
    if og and og.content and og.content ~= "" then
        local t = string_clean(og.content)
        t = t:gsub("%s*%- %s*Novel Phoenix$", "")
        return t
    end

    return nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end

    local og = html_select_first(body, "meta[property='og:image']")
    if og and og.content and og.content ~= "" then
        return absUrl(og.content)
    end

    local img =
        html_select_first(body, ".fixed-img img")
        or html_select_first(body, "figure.cover img")
        or html_select_first(body, ".novel-info img")

    if img then
        local src = img["data-src"] or img.src or img["data-lazy-src"] or ""
        if src ~= "" then
            return absUrl(src)
        end
    end

    return nil
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end

    local og = html_select_first(body, "meta[property='og:description']")
    if og and og.content and og.content ~= "" then
        return string_clean(og.content)
    end

    local el =
        html_select_first(body, ".summary .content")
        or html_select_first(body, ".summary .content.expand-wrapper")
        or html_select_first(body, "section#info .summary .content")
        or html_select_first(body, ".novel-info .summary .content")

    if el and el.text and el.text ~= "" then
        return cleanText(el.text)
    end

    return nil
end

function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end

    local genres = {}
    local seen = {}

    for _, a in ipairs(html_select(body, ".categories a.property-item, .categories a[href*='/genre-']")) do
        local g = string_clean(a.text or "")
        if g ~= "" and not seen[g] then
            seen[g] = true
            table.insert(genres, g)
        end
    end

    return genres
end

function getChapterList(bookUrl)
    return fetchAllChapters(bookUrl)
end

function getChapterListHash(bookUrl)
    local chapters = fetchAllChapters(bookUrl)
    if #chapters == 0 then
        return bookUrl
    end

    local first = chapters[1] and chapters[1].url or ""
    local last = chapters[#chapters] and chapters[#chapters].url or ""
    return tostring(#chapters) .. ":" .. first .. ":" .. last
end

function getChapterText(html, url)
    if not html or html == "" then
        return ""
    end

    local cleaned = html
    cleaned = cleaned:gsub("<script.-</script>", "")
    cleaned = cleaned:gsub("<style.-</style>", "")
    cleaned = cleaned:gsub("<!%-%-.-%-%->", "")

    local el =
        html_select_first(cleaned, "#content")
        or html_select_first(cleaned, "article")

    if not el then
        return ""
    end

    local text = html_text(el.html or "")
    text = cleanText(text)

    text = text:gsub("Restore scroll position.-\n", "")
    text = text:gsub("Restore scroll position.-", "")
    text = text:gsub("Previous Chapter", "")
    text = text:gsub("Next Chapter", "")
    text = text:gsub("Chapter List", "")
    text = text:gsub("Read More", "")
    text = cleanText(text)

    return text
end
