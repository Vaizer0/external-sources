-- Novel Phoenix plugin for NovaLa
-- Source: https://novelphoenix.com/
-- Version: 1.0.0

id       = "novelphoenix"
name     = "Novel Phoenix"
version  = "1.0.0"
baseUrl  = "https://novelphoenix.com"
language = "en"
icon     = "https://novelphoenix.com/logo.png"
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

local _pageCache = {}

local function fetchPage(url)
    if _pageCache[url] then return _pageCache[url] end
    local r = http_get(url)
    if r.success then
        _pageCache[url] = r.body
        return r.body
    end
    return nil
end

-- ── Catalog parsing ─────────────────────────────────────────────────────

local function parseCatalogItems(body)
    local items = {}
    local seen = {}

    -- Try to find novel items in the page
    local cards = html_select(body, ".novel-item, .rank-container .novel-item, .novel-list .novel-item")
    if #cards == 0 then
        cards = html_select(body, "a[href*='/novel/']")
    end

    for _, card in ipairs(cards) do
        local titleEl = html_select_first(card.html, "h4.novel-title a, h4 a, .novel-title a, a[title]")
        if not titleEl then
            titleEl = html_select_first(card.html, "a[href*='/novel/']")
        end
        if titleEl then
            local title = string_clean(titleEl.text or "")
            local url = absUrl(titleEl.href or "")
            if title ~= "" and url ~= "" and not seen[url] then
                seen[url] = true
                local cover = html_attr(card.html, ".novel-cover img", "src")
                if cover == "" then cover = html_attr(card.html, "img", "src") end
                if cover == "" then cover = html_attr(card.html, "img", "data-src") end
                cover = absUrl(cover)
                table.insert(items, {
                    title = title,
                    url = url,
                    cover = cover
                })
            end
        end
    end

    return items
end

local function hasNextPage(body)
    local nextLink = html_select_first(body, ".pagination .next a, .next-page a, a[rel='next']")
    if not nextLink then
        nextLink = html_select_first(body, ".load-more a, .show-more a")
    end
    return nextLink ~= nil
end

-- ── Catalog ─────────────────────────────────────────────────────────────

function getCatalogList(index)
    local page = index + 1
    local url = baseUrl .. "/genre-all/sort-new/status-all/all-novel?page=" .. page
    if page == 1 then
        url = baseUrl
    end

    local r = http_get(url)
    if not r.success then
        if index == 0 then
            r = http_get(baseUrl)
            if not r.success then return { items = {}, hasNext = false } end
        else
            return { items = {}, hasNext = false }
        end
    end

    local items = parseCatalogItems(r.body)
    return { items = items, hasNext = hasNextPage(r.body) }
end

-- ── Search ─────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
    if index > 0 then return { items = {}, hasNext = false } end
    local url = baseUrl .. "/search?q=" .. url_encode(query)
    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end
    local items = parseCatalogItems(r.body)
    return { items = items, hasNext = false }
end

-- ── Book Details ────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end

    local el = html_select_first(body, "h1.novel-title, .novel-title h1, h1")
    if el and el.text and el.text ~= "" then
        return string_clean(el.text)
    end

    local og = html_select_first(body, "meta[property='og:title']")
    if og and og.content and og.content ~= "" then
        return string_clean(og.content)
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

    local img = html_select_first(body, ".cover img, .novel-cover img, .fixed-img .cover img")
    if img then
        local src = img.src or img["data-src"] or ""
        if src ~= "" then return absUrl(src) end
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

    local el = html_select_first(body, ".summary .content, .summary__content, .description-summary .summary__content")
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

    for _, a in ipairs(html_select(body, ".categories a, .genres a, .genre-list a")) do
        local g = string_clean(a.text or "")
        if g ~= "" and not seen[g] then
            seen[g] = true
            table.insert(genres, g)
        end
    end

    return genres
end

-- ── Chapter List ────────────────────────────────────────────────────────

local function getNovelSlug(bookUrl)
    return bookUrl:match("/novel/([^/]+)/?")
end

local function fetchChaptersPage(novelSlug, page)
    local url = baseUrl .. "/novel/" .. novelSlug
    if page and page > 1 then
        url = url .. "?page=" .. page
    end
    local r = http_get(url)
    if not r.success then return nil end
    return r.body
end

local function parseChapterLinksFromHtml(html)
    local chapters = {}
    local seen = {}

    -- Look for chapter links in the page
    -- Novel Phoenix uses a select dropdown or a list
    local items = html_select(html, "select.chapindex option, .chapter-item a, .list-chapter a, a[href*='/chapter-']")
    if #items == 0 then
        items = html_select(html, "a[href*='/chapter-']")
    end

    for _, item in ipairs(items) do
        local a = item
        local href = a.href or ""
        local title = a.text or ""

        -- If it's an option, get the value and text
        if item.tag == "option" then
            href = item:attr("value") or ""
            title = item.text or ""
        end

        href = absUrl(href)
        title = string_clean(title)

        if href ~= "" and title ~= "" and not seen[href] then
            seen[href] = true
            table.insert(chapters, {
                title = title,
                url = href
            })
        end
    end

    -- Sort by chapter number if possible
    local numbered = {}
    for _, ch in ipairs(chapters) do
        local n = tonumber((ch.title or ""):match("^(%d+)")) or
                  tonumber((ch.url or ""):match("chapter%-(%d+)")) or
                  tonumber((ch.url or ""):match("/(%d+)%-[^/]+/?$")) or 0
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
        table.insert(sorted, {
            title = ch.title,
            url = ch.url
        })
    end

    return sorted
end

function getChapterList(bookUrl)
    local novelSlug = getNovelSlug(bookUrl)
    if not novelSlug then
        log_error("novelphoenix: cannot extract novel slug from " .. bookUrl)
        return {}
    end

    -- Try to get chapters from the novel page
    local html = fetchChaptersPage(novelSlug, 1)
    if not html then return {} end

    local chapters = parseChapterLinksFromHtml(html)
    if #chapters > 0 then
        return chapters
    end

    -- If no chapters found, try to get them from the chapters page
    local chaptersUrl = bookUrl:gsub("/?$", "") .. "/chapters"
    local r = http_get(chaptersUrl)
    if r and r.success and r.body then
        chapters = parseChapterLinksFromHtml(r.body)
        if #chapters > 0 then
            return chapters
        end
    end

    return {}
end

function getChapterListHash(bookUrl)
    local chapters = getChapterList(bookUrl)
    if #chapters == 0 then return bookUrl end
    local first = chapters[1] and chapters[1].url or ""
    local last = chapters[#chapters] and chapters[#chapters].url or ""
    return tostring(#chapters) .. ":" .. first .. ":" .. last
end

-- ── Chapter Text ────────────────────────────────────────────────────────

function getChapterText(html, url)
    if not html or html == "" then return "" end

    -- Remove unwanted elements
    html = html:gsub("<script.-</script>", "")
    html = html:gsub("<style.-</style>", "")
    html = html:gsub("<!%-%-.-%-%->", "")

    -- Look for the content container
    local el = html_select_first(html, "#content, .chapter-content, .reading-content, .entry-content, .novel-content, article")
    if not el then
        el = html_select_first(html, "body")
        if not el then return "" end
    end

    local text = html_text(el.html or "")
    text = cleanText(text)

    -- Remove common navigation/ads text
    text = text:gsub("Previous", "")
    text = text:gsub("Next", "")
    text = text:gsub("Report", "")
    text = text:gsub("Share", "")
    text = cleanText(text)

    return text
end

-- ── Filters ─────────────────────────────────────────────────────────────

function getFilterList()
    return {
        {
            type = "select",
            key = "sort",
            label = "Sort By",
            defaultValue = "new",
            options = {
                { value = "new",      label = "Newest" },
                { value = "popular",  label = "Most Popular" },
                { value = "rating",   label = "Top Rated" },
                { value = "alphabet", label = "Alphabetical" },
            }
        },
        {
            type = "select",
            key = "status",
            label = "Status",
            defaultValue = "all",
            options = {
                { value = "all",       label = "All" },
                { value = "ongoing",   label = "Ongoing" },
                { value = "completed", label = "Completed" },
                { value = "dropped",   label = "Dropped" },
            }
        },
        {
            type = "checkbox",
            key = "genre",
            label = "Genres",
            options = {
                { value = "action",        label = "Action" },
                { value = "adventure",     label = "Adventure" },
                { value = "comedy",        label = "Comedy" },
                { value = "drama",         label = "Drama" },
                { value = "fantasy",       label = "Fantasy" },
                { value = "historical",    label = "Historical" },
                { value = "horror",        label = "Horror" },
                { value = "mystery",       label = "Mystery" },
                { value = "romance",       label = "Romance" },
                { value = "sci-fi",        label = "Sci-Fi" },
                { value = "slice-of-life", label = "Slice of Life" },
                { value = "supernatural",  label = "Supernatural" },
                { value = "thriller",      label = "Thriller" },
                { value = "xianxia",       label = "Xianxia" },
                { value = "xuanhuan",      label = "Xuanhuan" },
            }
        },
    }
end

function getCatalogFiltered(index, filters)
    local page = index + 1
    local sort = filters["sort"] or "new"
    local status = filters["status"] or "all"

    -- Build the URL based on filters
    local url = baseUrl .. "/genre-all/sort-" .. url_encode(sort) .. "/status-" .. url_encode(status) .. "/all-novel"
    if page > 1 then
        url = url .. "?page=" .. page
    end

    -- Add genre filters if present
    local genres = filters["genre_included"] or {}
    if #genres > 0 then
        url = url .. "&genre[]=" .. table.concat(genres, "&genre[]=")
    end

    local r = http_get(url)
    if not r.success then
        return { items = {}, hasNext = false }
    end

    local items = parseCatalogItems(r.body)
    return { items = items, hasNext = hasNextPage(r.body) }
end

-- ── End of plugin ──────────────────────────────────────────────────────
