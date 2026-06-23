id       = "sonicmtl"
name     = "Sonic MTL"
version  = "1.2.0"
baseUrl  = "https://www.sonicmtl.com"
language = "mtl"
icon     = "https://www.sonicmtl.com/wp-content/uploads/2021/09/sonicmtl-icon-1.png"

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

local function parseCard(cardHtml)
    local titleEl =
        html_select_first(cardHtml, ".item-summary .post-title a")
        or html_select_first(cardHtml, ".post-title a")
        or html_select_first(cardHtml, "a[title]")

    local linkEl =
        html_select_first(cardHtml, ".item-thumb a")
        or html_select_first(cardHtml, ".item-summary .post-title a")
        or html_select_first(cardHtml, ".post-title a")
        or html_select_first(cardHtml, "a[title]")

    if not titleEl or not linkEl then
        return nil
    end

    local title = string_clean(titleEl.text or "")
    local url = absUrl(linkEl.href or "")
    if title == "" or url == "" then
        return nil
    end

    local cover = html_attr(cardHtml, "img", "src")
    if cover == "" then
        cover = html_attr(cardHtml, "img", "data-src")
    end

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
        ".slider__item",
        ".popular-item-wrap",
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

        if not href:find("/chapter") and not href:find("chapter%-") and not href:find("/chapter%-") then
            return
        end

        seen[href] = true
        table.insert(chapters, {
            title = title,
            url = href
        })
    end

    local selectors = {
        ".wp-manga-chapter a",
        ".listing-chapters_wrap a",
        ".listing-chapters_wrap .wp-manga-chapter a",
        ".chapter-item a",
        ".chapter a",
        "a.btn-link"
    }

    for _, sel in ipairs(selectors) do
        for _, a in ipairs(html_select(body, sel)) do
            addChapter(a.text or "", a.href or "")
        end
    end

    if #chapters == 0 then
        for _, a in ipairs(html_select(body, "a[href*='/chapter']")) do
            addChapter(a.text or "", a.href or "")
        end
    end

    table.sort(chapters, function(a, b)
        local na = tonumber((a.title or ""):match("^(%d+)")) or tonumber((a.url or ""):match("chapter%-(%d+)")) or 0
        local nb = tonumber((b.title or ""):match("^(%d+)")) or tonumber((b.url or ""):match("chapter%-(%d+)")) or 0
        return na < nb
    end)

    return chapters
end

local function fetchChaptersFromAjax(bookUrl, mangaId)
    local ajaxUrl = baseUrl .. "/wp-admin/admin-ajax.php"
    local attempts = {
        "action=wp-manga-get-chapters&post_id=" .. tostring(mangaId),
        "action=wp-manga-get-chapters&manga_id=" .. tostring(mangaId),
        "action=wp-manga-get-chapters&manga=" .. tostring(mangaId),
        "action=manga_get_chapters&post_id=" .. tostring(mangaId),
        "action=manga_get_chapters&manga_id=" .. tostring(mangaId),
        "action=manga_get_chapters&manga=" .. tostring(mangaId),
        "action=madara_load_chapters&post_id=" .. tostring(mangaId),
        "action=madara_load_chapters&manga_id=" .. tostring(mangaId),
        "action=madara_load_chapters&manga=" .. tostring(mangaId),
    }

    for _, body in ipairs(attempts) do
        local r = http_post(ajaxUrl, body, {
            headers = {
                ["X-Requested-With"] = "XMLHttpRequest",
                ["Referer"] = bookUrl,
                ["Origin"] = baseUrl
            }
        })

        if r.success and r.body and r.body ~= "" then
            local chapters = parseChapterLinks(r.body, bookUrl:match("/novel/([^/]+)/"))
            if #chapters > 0 then
                return chapters
            end
        end
    end

    return {}
end

function getCatalogList(index)
    local page = index + 1
    local url

    if page == 1 then
        url = baseUrl .. "/novel/"
    else
        url = baseUrl .. "/novel/page/" .. tostring(page) .. "/"
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

function getCatalogSearch(index, query)
    local page = index + 1
    local url

    if page == 1 then
        url = baseUrl .. "/?s=" .. url_encode(query) .. "&post_type=wp-manga"
    else
        url = baseUrl .. "/page/" .. tostring(page) .. "/?s=" .. url_encode(query) .. "&post_type=wp-manga"
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

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end

    local el =
        html_select_first(body, ".post-title h1")
        or html_select_first(body, "h1")

    if el and el.text and el.text ~= "" then
        return string_clean(el.text)
    end

    local og = html_select_first(body, "meta[property='og:title']")
    if og and og.content and og.content ~= "" then
        local t = string_clean(og.content)
        t = t:gsub("%s*MTL and Audiobook$", "")
        t = t:gsub("%s*MTL$", "")
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

    local img = html_select_first(body, ".summary_image img")
    if img and img.src and img.src ~= "" then
        return absUrl(img.src)
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
        html_select_first(body, ".summary__content")
        or html_select_first(body, ".description-summary .summary__content")
        or html_select_first(body, ".description-summary")

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

    for _, a in ipairs(html_select(body, ".genres-content a, .genres_wrap a.btn-genres, a[href*='/novel-genre/']")) do
        local g = string_clean(a.text or "")
        if g ~= "" and not seen[g] then
            seen[g] = true
            table.insert(genres, g)
        end
    end

    return genres
end

function getChapterList(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end

    local novelSlug = bookUrl:match("/novel/([^/]+)/")
    local holder = html_select_first(body, "#manga-chapters-holder")

    if holder and holder["data-id"] then
        local mangaId = holder["data-id"]
        local chapters = fetchChaptersFromAjax(bookUrl, mangaId)
        if #chapters > 0 then
            return chapters
        end
    end

    local varId = body:match([["manga_id":"(%d+)"]]) or body:match([[manga_id":"(%d+)"]])
    if varId then
        local chapters = fetchChaptersFromAjax(bookUrl, varId)
        if #chapters > 0 then
            return chapters
        end
    end

    local chapters = parseChapterLinks(body, novelSlug)
    if #chapters > 0 then
        return chapters
    end

    local ajaxFallback = http_get(bookUrl:gsub("/?$", "") .. "/ajax/chapters/?t=1")
    if ajaxFallback.success and ajaxFallback.body and ajaxFallback.body ~= "" then
        chapters = parseChapterLinks(ajaxFallback.body, novelSlug)
        if #chapters > 0 then
            return chapters
        end
    end

    return {}
end

function getChapterListHash(bookUrl)
    local chapters = getChapterList(bookUrl)
    if #chapters == 0 then
        local body = fetchPage(bookUrl)
        if not body then return nil end
        local holder = html_select_first(body, "#manga-chapters-holder")
        if holder and holder["data-id"] then
            return "manga_" .. holder["data-id"]
        end
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

    html = html:gsub("<script.-</script>", "")
    html = html:gsub("<style.-</style>", "")
    html = html:gsub("<!%-%-.-%-%->", "")

    local el =
        html_select_first(html, ".reading-content .text-left")
        or html_select_first(html, ".reading-content")
        or html_select_first(html, ".entry-content")
        or html_select_first(html, "article")

    if not el then
        return ""
    end

    local text = html_text(el.html or "")
    text = cleanText(text)

    text = text:gsub("Read More", "")
    text = text:gsub("Next Chapter", "")
    text = text:gsub("Previous Chapter", "")
    text = text:gsub("Report this chapter", "")
    text = text:gsub("NOVEL DISCUSSION.-$", "")

    return cleanText(text)
end
