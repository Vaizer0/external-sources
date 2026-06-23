-- SonicMTL plugin for NovaLa
-- Source: https://www.sonicmtl.com/
-- Version: 1.6.3

id       = "sonicmtl"
name     = "Sonic MTL"
version  = "1.6.3"
baseUrl  = "https://www.sonicmtl.com"
language = "mtl"
icon     = "https://www.sonicmtl.com/wp-content/uploads/2021/09/sonicmtl-icon-1.png"
charset  = "UTF-8"

local _pageCache = {}

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

local function parseCard(cardHtml)
    local titleEl =
        html_select_first(cardHtml, ".item-summary .post-title a") or
        html_select_first(cardHtml, ".post-title a") or
        html_select_first(cardHtml, "h3 a") or
        html_select_first(cardHtml, "a[title]")

    local linkEl =
        html_select_first(cardHtml, ".item-thumb a") or
        html_select_first(cardHtml, ".item-summary .post-title a") or
        html_select_first(cardHtml, ".post-title a") or
        html_select_first(cardHtml, "a[title]")

    if not titleEl or not linkEl then return nil end

    local title = string_clean(titleEl.text or "")
    local url = absUrl(linkEl.href or "")
    if title == "" or url == "" then return nil end

    local cover = html_attr(cardHtml, "img", "src")
    if cover == "" then cover = html_attr(cardHtml, "img", "data-src") end
    if cover == "" then cover = html_attr(cardHtml, "img", "data-lazy-src") end

    return {
        title = title,
        url = url,
        cover = absUrl(cover)
    }
end

local function parseCatalogItems(body)
    local items = {}
    local seen = {}

    local selectors = {
        ".page-item-detail",
        ".page-listing-item .page-item-detail",
        ".c-tabs-item__content",
        ".item-summary",
        ".popular-item-wrap",
        ".slider__item",
    }

    for _, sel in ipairs(selectors) do
        for _, card in ipairs(html_select(body, sel)) do
            local item = parseCard(card.html or card)
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

-- ── Chapter parsing ─────────────────────────────────────────────────────

local function parseChapterLinks(body, novelSlug)
    local chapters = {}
    local seen = {}

    local function addChapter(title, href)
        href = absUrl(href or "")
        title = string_clean(title or "")

        if href == "" or title == "" or seen[href] then
            return
        end

        if novelSlug and not href:find("/novel/" .. novelSlug .. "/") then
            return
        end

        if not href:find("/chapter") and not href:find("chapter%-") then
            return
        end

        seen[href] = true
        table.insert(chapters, {
            title = title,
            url = href
        })
    end

    for _, sel in ipairs({
        ".wp-manga-chapter a",
        ".listing-chapters_wrap a",
        ".listing-chapters_wrap .wp-manga-chapter a",
        ".chapters_selectbox_holder a",
        ".chapter-item a",
        ".chapter a",
        "a.btn-link",
        "a[href*='/chapter']",
    }) do
        for _, a in ipairs(html_select(body, sel)) do
            addChapter(a.text or "", a.href or "")
        end
    end

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

-- ── AJAX chapter fetching (fixed for Star Odyssey) ─────────────────────

local function fetchAjaxChapters(bookUrl, mangaId)
    local novelSlug = bookUrl:match("/novel/([^/]+)/")
    if not mangaId or mangaId == "" then
        return {}
    end

    -- Primary: use the standard WP‑Manga endpoint that returns clean HTML
    local url = baseUrl .. "/wp-admin/admin-ajax.php"
    local body = "action=wp-manga-get-chapters&manga_id=" .. mangaId

    local r = http_post(url, body, {
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8",
            ["X-Requested-With"] = "XMLHttpRequest",
            ["Referer"] = bookUrl,
            ["Origin"] = baseUrl
        }
    })

    if r and r.success and r.body and r.body ~= "" then
        local chapters = parseChapterLinks(r.body, novelSlug)
        if #chapters > 0 then
            return chapters
        end
    end

    -- Fallback: try the old endpoint (works for some novels)
    local fallbackUrl = bookUrl:gsub("/?$", "") .. "/ajax/chapters/?t=1"
    local r2 = http_get(fallbackUrl, {
        headers = {
            ["X-Requested-With"] = "XMLHttpRequest",
            ["Referer"] = bookUrl
        }
    })
    if r2 and r2.success and r2.body and r2.body ~= "" then
        local chapters = parseChapterLinks(r2.body, novelSlug)
        if #chapters > 0 then
            return chapters
        end
    end

    -- Last resort: try other possible endpoints
    local otherAttempts = {
        { url = bookUrl:gsub("/?$", "") .. "/ajax/chapters/", post = true, body = "" },
        { url = baseUrl .. "/wp-admin/admin-ajax.php", post = true, body = "action=wp-manga-get-chapters&post_id=" .. mangaId },
        { url = baseUrl .. "/wp-admin/admin-ajax.php", post = true, body = "action=wp-manga-get-chapters&manga=" .. mangaId },
        { url = baseUrl .. "/wp-admin/admin-ajax.php", post = true, body = "action=manga_get_chapters&manga_id=" .. mangaId },
        { url = baseUrl .. "/wp-admin/admin-ajax.php", post = true, body = "action=manga_get_chapters&post_id=" .. mangaId },
        { url = baseUrl .. "/wp-admin/admin-ajax.php", post = true, body = "action=madara_load_chapters&manga_id=" .. mangaId },
        { url = baseUrl .. "/wp-admin/admin-ajax.php", post = true, body = "action=madara_load_chapters&post_id=" .. mangaId },
    }

    for _, req in ipairs(otherAttempts) do
        local rr
        if req.post then
            rr = http_post(req.url, req.body, {
                headers = {
                    ["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8",
                    ["X-Requested-With"] = "XMLHttpRequest",
                    ["Referer"] = bookUrl,
                    ["Origin"] = baseUrl
                }
            })
        else
            rr = http_get(req.url, {
                headers = {
                    ["X-Requested-With"] = "XMLHttpRequest",
                    ["Referer"] = bookUrl
                }
            })
        end

        if rr and rr.success and rr.body and rr.body ~= "" then
            local chapters = parseChapterLinks(rr.body, novelSlug)
            if #chapters > 0 then
                return chapters
            end
        end
    end

    return {}
end

-- ── Catalog ─────────────────────────────────────────────────────────────

function getCatalogList(index)
    local page = index + 1
    local url = (page == 1) and (baseUrl .. "/novel/") or (baseUrl .. "/novel/page/" .. page .. "/")
    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end
    local items = parseCatalogItems(r.body)
    return { items = items, hasNext = #items > 0 }
end

function getCatalogSearch(index, query)
    local page = index + 1
    local url = (page == 1)
        and (baseUrl .. "/?s=" .. url_encode(query) .. "&post_type=wp-manga")
        or (baseUrl .. "/page/" .. page .. "/?s=" .. url_encode(query) .. "&post_type=wp-manga")
    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end
    local items = parseCatalogItems(r.body)
    return { items = items, hasNext = #items > 0 }
end

-- ── Book Details ────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".post-title h1") or html_select_first(body, "h1")
    if el and el.text and el.text ~= "" then
        return string_clean(el.text)
    end
    local og = html_select_first(body, "meta[property='og:title']")
    if og and og.content and og.content ~= "" then
        local t = string_clean(og.content)
        t = t:gsub("%s*MTL and Audiobook$", ""):gsub("%s*MTL$", "")
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
    local img = html_select_first(body, ".summary_image img") or html_select_first(body, ".item-thumb img")
    if img then
        local src = img.src or img["data-src"] or img["data-lazy-src"] or ""
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
    local el = html_select_first(body, ".summary__content") or
               html_select_first(body, ".description-summary .summary__content") or
               html_select_first(body, ".description-summary")
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
    for _, a in ipairs(html_select(body, ".genres-content a, .genres_wrap a.btn-genres, .post-content_item a[href*='/novel-genre/']")) do
        local g = string_clean(a.text or "")
        if g ~= "" and not seen[g] then
            seen[g] = true
            table.insert(genres, g)
        end
    end
    return genres
end

-- ── Chapter List ────────────────────────────────────────────────────────

function getChapterList(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end

    local novelSlug = bookUrl:match("/novel/([^/]+)/")
    local chapters = parseChapterLinks(body, novelSlug)
    if #chapters > 0 then
        return chapters
    end

    local mangaId = html_attr(body, "#manga-chapters-holder", "data-id")
    if not mangaId or mangaId == "" then
        mangaId = body:match('"manga_id":"(%d+)"') or body:match('data%-id="(%d+)"')
    end

    if mangaId and mangaId ~= "" then
        chapters = fetchAjaxChapters(bookUrl, mangaId)
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

    html = html:gsub("<script.-</script>", "")
    html = html:gsub("<style.-</style>", "")
    html = html:gsub("<!%-%-.-%-%->", "")

    local el = html_select_first(html, ".reading-content .text-left") or
               html_select_first(html, ".reading-content") or
               html_select_first(html, ".entry-content .entry-content_wrap") or
               html_select_first(html, ".entry-content") or
               html_select_first(html, ".chapter-content") or
               html_select_first(html, "#content") or
               html_select_first(html, "article")

    if not el then return "" end

    local text = html_text(el.html or "")
    text = cleanText(text)

    text = text:gsub("Listen to this Chapter", "")
    text = text:gsub("Read More", "")
    text = text:gsub("Previous", "")
    text = text:gsub("Next", "")
    text = text:gsub("Report this chapter", "")
    text = cleanText(text)

    return text
end

-- ── Filters ─────────────────────────────────────────────────────────────

function getFilterList()
    return {
        {
            type = "select",
            key = "m_orderby",
            label = "Order By",
            defaultValue = "rating",
            options = {
                { value = "rating",    label = "Rating" },
                { value = "latest",    label = "Latest" },
                { value = "alphabet",  label = "A-Z" },
                { value = "trending",  label = "Trending" },
                { value = "views",     label = "Most Views" },
                { value = "new-manga", label = "New" },
                { value = "",          label = "Relevance" },
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
                { value = "eastern",       label = "Eastern" },
                { value = "fantasy",       label = "Fantasy" },
                { value = "game",          label = "Game" },
                { value = "historical",    label = "Historical" },
                { value = "horror",        label = "Horror" },
                { value = "josei",         label = "Josei" },
                { value = "martial-arts",  label = "Martial Arts" },
                { value = "mystery",       label = "Mystery" },
                { value = "psychological", label = "Psychological" },
                { value = "romance",       label = "Romance" },
                { value = "school-life",   label = "School Life" },
                { value = "sci-fi",        label = "Sci-fi" },
                { value = "shounen",       label = "Shounen" },
                { value = "slice-of-life", label = "Slice of Life" },
                { value = "supernatural",  label = "Supernatural" },
                { value = "urban",         label = "Urban" },
                { value = "wuxia",         label = "Wuxia" },
                { value = "xianxia",       label = "Xianxia" },
                { value = "xuanhuan",      label = "Xuanhuan" },
            }
        },
        {
            type = "select",
            key = "op",
            label = "Genres Condition",
            defaultValue = "",
            options = {
                { value = "",  label = "OR (having one of selected genres)" },
                { value = "1", label = "AND (having all selected genres)" },
            }
        },
        {
            type = "select",
            key = "adult",
            label = "Adult Content",
            defaultValue = "",
            options = {
                { value = "",  label = "All" },
                { value = "0", label = "None adult content" },
                { value = "1", label = "Only adult content" },
            }
        },
        {
            type = "checkbox",
            key = "status",
            label = "Status",
            options = {
                { value = "on-going", label = "On Going" },
                { value = "end",      label = "Completed" },
                { value = "canceled", label = "Canceled" },
                { value = "on-hold",  label = "On Hold" },
                { value = "upcoming", label = "Upcoming" },
            }
        },
        {
            type = "text",
            key = "author",
            label = "Author",
            defaultValue = ""
        },
        {
            type = "text",
            key = "release",
            label = "Year of Released",
            defaultValue = ""
        },
    }
end

function getCatalogFiltered(index, filters)
    local page    = index + 1
    local orderby = filters["m_orderby"] or "rating"
    local op      = filters["op"] or ""
    local adult   = filters["adult"] or ""
    local author  = filters["author"] or ""
    local artist  = filters["artist"] or ""
    local release = filters["release"] or ""
    local genres  = filters["genre_included"] or {}
    local statuses = filters["status_included"] or {}

    local basePath = ""
    if page > 1 then
        basePath = "/page/" .. page .. "/"
    end

    local url = baseUrl .. basePath .. "?s&post_type=wp-manga"
        .. "&m_orderby=" .. url_encode(orderby)
        .. "&op=" .. url_encode(op)
        .. "&adult=" .. url_encode(adult)

    if author ~= "" then
        url = url .. "&author=" .. url_encode(author)
    end
    if artist ~= "" then
        url = url .. "&artist=" .. url_encode(artist)
    end
    if release ~= "" then
        url = url .. "&release=" .. url_encode(release)
    end

    for _, v in ipairs(genres) do
        url = url .. "&genre[]=" .. url_encode(v)
    end
    for _, v in ipairs(statuses) do
        url = url .. "&status[]=" .. url_encode(v)
    end

    local r = http_get(url)
    if not r.success then
        return { items = {}, hasNext = false }
    end

    local items = parseCatalogItems(r.body)
    return {
        items = items,
        hasNext = #items > 0
    }
end

-- ── End of plugin ──────────────────────────────────────────────────────