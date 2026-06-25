-- Novel Phoenix plugin for NovaLa
-- Source: https://novelphoenix.com/
-- Version: 1.0.0

id       = "novelphoenix"
name     = "Novel Phoenix"
version  = "1.0.0"
baseUrl  = "https://novelphoenix.com"
language = "en"
icon     = "https://novelphoenix.com/logo.png"
charset  = "UTF-8"

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

    -- Look for novel cards on homepage or listing pages
    local cards = html_select(body, ".novel-item, .book-item, .list-item, .col-lg-3 .item-summary")
    if #cards == 0 then
        cards = html_select(body, "a[href*='/novel/']")
    end

    for _, card in ipairs(cards) do
        local titleEl = html_select_first(card.html, "h3 a, h4 a, .title a, a[href*='/novel/']")
        if not titleEl then
            titleEl = html_select_first(card.html, "a[href*='/novel/']")
        end
        if titleEl then
            local title = string_clean(titleEl.text or "")
            local url = absUrl(titleEl.href or "")
            if title ~= "" and url ~= "" and not seen[url] then
                seen[url] = true
                local cover = html_attr(card.html, "img", "src")
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
    local el = html_select_first(body, "h1, .novel-title, .post-title h1")
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
    local img = html_select_first(body, ".novel-cover img, .summary_image img, .item-thumb img")
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
    local el = html_select_first(body, ".summary, .description, .novel-description, .summary__content")
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
    for _, a in ipairs(html_select(body, ".genres a, .tags a, .genre-list a, .categories a")) do
        local g = string_clean(a.text or "")
        if g ~= "" and not seen[g] then
            seen[g] = true
            table.insert(genres, g)
        end
    end
    return genres
end

-- ── Chapter List ────────────────────────────────────────────────────────

-- Extract the novel slug from the book URL (e.g., "shadow-slave")
local function getNovelSlug(bookUrl)
    return bookUrl:match("/novel/([^/]+)/?")
end

-- Fetch chapters from the dedicated /chapters page
local function fetchChaptersPage(novelSlug, page)
    local url = baseUrl .. "/novel/" .. novelSlug .. "/chapters"
    if page and page > 1 then
        url = url .. "?page=" .. page
    end
    local r = http_get(url, {
        headers = {
            ["X-Requested-With"] = "XMLHttpRequest",
        }
    })
    if not r.success then return nil end
    return r.body
end

-- Parse chapter links from the chapters page HTML
local function parseChapterLinksFromHtml(html)
    local chapters = {}
    local seen = {}

    -- Look for chapter items in the list
    local items = html_select(html, ".chapter-item, .list-group-item, .chapter-list li, ul li a[href*='/chapter-']")
    if #items == 0 then
        items = html_select(html, "a[href*='/chapter-']")
    end

    for _, item in ipairs(items) do
        local a = html_select_first(item.html, "a[href*='/chapter-']")
        if not a then
            a = item
        end
        if a and a.href and a.href ~= "" then
            local href = absUrl(a.href)
            if href ~= "" and not seen[href] then
                seen[href] = true
                local title = string_clean(a.text or "")
                if title == "" then
                    -- Try to extract chapter number from URL
                    local num = href:match("/chapter%-(%d+)")
                    title = "Chapter " .. (num or "?")
                end
                table.insert(chapters, {
                    title = title,
                    url = href
                })
            end
        end
    end

    return chapters
end

-- Get total number of chapters (from the /chapters page info)
local function getTotalChapters(html)
    local info = html_select_first(html, ".chapter-count, .total-chapters, p:contains('total of')")
    if info then
        local count = info.text:match("(%d+) chapters")
        if count then return tonumber(count) end
    end
    return nil
end

function getChapterList(bookUrl)
    local novelSlug = getNovelSlug(bookUrl)
    if not novelSlug then
        log_error("novelphoenix: cannot extract novel slug from " .. bookUrl)
        return {}
    end

    -- Fetch the first page of chapters
    local html = fetchChaptersPage(novelSlug, 1)
    if not html then return {} end

    local allChapters = parseChapterLinksFromHtml(html)

    -- Check if there are more pages (pagination)
    -- The site may have pagination for the chapter list
    local nextPage = 2
    while true do
        local nextHtml = fetchChaptersPage(novelSlug, nextPage)
        if not nextHtml then break end
        local moreChapters = parseChapterLinksFromHtml(nextHtml)
        if #moreChapters == 0 then break end
        for _, ch in ipairs(moreChapters) do
            table.insert(allChapters, ch)
        end
        nextPage = nextPage + 1
        sleep(200) -- be gentle
    end

    -- Reverse to get oldest first (most sites show newest first)
    local reversed = {}
    for i = #allChapters, 1, -1 do
        table.insert(reversed, allChapters[i])
    end

    return reversed
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
    local el = html_select_first(html, ".chapter-content, .reading-content, .entry-content, .novel-content, #content, article")
    if not el then
        -- Try to find the main text in the body
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
                { value = "all",      label = "All" },
                { value = "ongoing",  label = "Ongoing" },
                { value = "completed", label = "Completed" },
                { value = "dropped",  label = "Dropped" },
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
