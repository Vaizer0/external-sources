id       = "sonicmtl"
name     = "Sonic MTL"
version  = "1.0.0"
baseUrl  = "https://www.sonicmtl.com"
language = "en"
icon     = "https://www.sonicmtl.com/wp-content/uploads/2021/09/sonicmtl-icon-1.png"

local function absUrl(href)
    if not href or href == "" then return "" end
    if href:sub(1, 4) == "http" then return href end
    if href:sub(1, 2) == "//" then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

local function cleanHtmlText(text)
    if not text or text == "" then return "" end
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    text = text:gsub("\n%s*\n%s*\n+", "\n\n")
    return string_trim(text)
end

local function parseNovelCard(cardHtml)
    local titleEl = html_select_first(cardHtml, ".item-summary .post-title a")
        or html_select_first(cardHtml, ".post-title a")
        or html_select_first(cardHtml, "a[title]")
    local linkEl = html_select_first(cardHtml, ".item-thumb a")
        or html_select_first(cardHtml, ".post-title a")
        or html_select_first(cardHtml, "a[title]")
    local cover = html_attr(cardHtml, "img", "src")
    if cover == "" then
        cover = html_attr(cardHtml, "img", "data-src")
    end

    if not titleEl or not linkEl then
        return nil
    end

    local title = string_clean(titleEl.text or "")
    local url = absUrl(linkEl.href or "")
    if title == "" or url == "" then
        return nil
    end

    return {
        title = title,
        url = url,
        cover = absUrl(cover)
    }
end

function getFilterList()
    return {
        {
            type = "select",
            key = "sort",
            label = "Sort",
            defaultValue = "new-manga",
            options = {
                { value = "new-manga", label = "Latest Updates" },
                { value = "trending", label = "Trending Novels" },
                { value = "end", label = "Completed Novels" },
            }
        }
    }
end

function getCatalogList(index)
    local page = index + 1
    local url = baseUrl .. "/?s=&post_type=wp-manga&m_orderby=new-manga&page=" .. tostring(page)

    local r = http_get(url)
    if not r.success then
        return { items = {}, hasNext = false }
    end

    local items = {}
    for _, card in ipairs(html_select(r.body, ".page-listing-item .item-summary, .page-listing-item .page-item-detail, .item-summary")) do
        local item = parseNovelCard(card.html or card)
        if item then
            table.insert(items, item)
        end
    end

    if #items == 0 then
        for _, card in ipairs(html_select(r.body, ".page-listing-item .item-thumb, .page-listing-item")) do
            local item = parseNovelCard(card.html or card)
            if item then
                table.insert(items, item)
            end
        end
    end

    return {
        items = items,
        hasNext = #items > 0
    }
end

function getCatalogSearch(index, query)
    local page = index + 1
    local url = baseUrl .. "/?s=" .. url_encode(query) .. "&post_type=wp-manga&page=" .. tostring(page)

    local r = http_get(url)
    if not r.success then
        return { items = {}, hasNext = false }
    end

    local items = {}
    for _, card in ipairs(html_select(r.body, ".page-listing-item .item-summary, .page-listing-item .page-item-detail, .item-summary")) do
        local item = parseNovelCard(card.html or card)
        if item then
            table.insert(items, item)
        end
    end

    if #items == 0 then
        for _, card in ipairs(html_select(r.body, ".page-listing-item .item-thumb, .page-listing-item")) do
            local item = parseNovelCard(card.html or card)
            if item then
                table.insert(items, item)
            end
        end
    end

    return {
        items = items,
        hasNext = #items > 0
    }
end

function getBookTitle(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end

    local el = html_select_first(r.body, "h1")
        or html_select_first(r.body, ".post-title h1")
        or html_select_first(r.body, ".post-title a")

    if el and el.text and el.text ~= "" then
        return string_clean(el.text)
    end

    local meta = html_select_first(r.body, "meta[property='og:title']")
    if meta and meta.content and meta.content ~= "" then
        local t = string_clean(meta.content)
        t = t:gsub("%s*MTL and Audiobook$", "")
        t = t:gsub("%s*MTL$", "")
        return t
    end

    return nil
end

function getBookCoverImageUrl(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end

    local meta = html_select_first(r.body, "meta[property='og:image']")
    if meta and meta.content and meta.content ~= "" then
        return absUrl(meta.content)
    end

    local img = html_select_first(r.body, ".item-thumb img")
    if img and img.src and img.src ~= "" then
        return absUrl(img.src)
    end

    return nil
end

function getBookDescription(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end

    local meta = html_select_first(r.body, "meta[property='og:description']")
    if meta and meta.content and meta.content ~= "" then
        return string_clean(meta.content)
    end

    local el = html_select_first(r.body, ".summary__content")
        or html_select_first(r.body, ".description-summary")
        or html_select_first(r.body, ".summary")

    if el and el.text and el.text ~= "" then
        return string_trim(el.text)
    end

    return nil
end

function getBookGenres(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return {} end

    local genres = {}
    for _, a in ipairs(html_select(r.body, ".genres_wrap a.btn-genres, .item-tags a, .genres a")) do
        local g = string_clean(a.text or "")
        if g ~= "" then
            table.insert(genres, g)
        end
    end

    if #genres == 0 then
        local jsonld = r.body:match('articleSection":%[(.-)%]')
        if jsonld then
            for g in jsonld:gmatch('"([^"]+)"') do
                g = string_clean(g)
                if g ~= "" then table.insert(genres, g) end
            end
        end
    end

    return genres
end

function getChapterList(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return {} end

    local chapters = {}
    local seen = {}

    local function addChapter(title, href)
        local url = absUrl(href or "")
        title = string_clean(title or "")
        if url ~= "" and title ~= "" and not seen[url] then
            seen[url] = true
            table.insert(chapters, {
                title = title,
                url = url
            })
        end
    end

    for _, a in ipairs(html_select(r.body, ".listing-chapters_wrap a.btn-link, .listing-chapters_wrap .wp-manga-chapter a, .list-chapter .chapter-item .chapter a.btn-link, .chapter-item .chapter a.btn-link")) do
        addChapter(a.text, a.href)
    end

    if #chapters == 0 then
        for _, a in ipairs(html_select(r.body, "a.btn-link")) do
            local href = a.href or ""
            if href:find("/chapter%-") or href:find("/chapter/") then
                addChapter(a.text, href)
            end
        end
    end

    table.sort(chapters, function(a, b)
        local na = tonumber(a.title:match("^(%d+)")) or 0
        local nb = tonumber(b.title:match("^(%d+)")) or 0
        return na < nb
    end)

    return chapters
end

function getChapterListHash(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end

    local first = html_select_first(r.body, ".listing-chapters_wrap a.btn-link, .list-chapter .chapter-item .chapter a.btn-link")
    if first and first.href and first.href ~= "" then
        return first.href
    end

    return bookUrl
end

function getChapterText(html, url)
    if not html or html == "" then
        return ""
    end

    html = html:gsub('<script.-</script>', '')
    html = html:gsub('<style.-</style>', '')
    html = html:gsub('<!%-%-.-%-%->', '')

    local el = html_select_first(html, ".reading-content .text-left")
        or html_select_first(html, ".reading-content")
        or html_select_first(html, ".entry-content .entry-content_wrap")
        or html_select_first(html, ".entry-content")
        or html_select_first(html, "article")

    if not el then
        return cleanHtmlText(html_text(html))
    end

    local text = html_text(el.html or "")
    text = cleanHtmlText(text)

    text = text:gsub("Listen to this Chapter", "")
    text = text:gsub("Next", "")
    text = text:gsub("Previous", "")
    text = text:gsub("DMCA.-$", "")
    text = text:gsub("PRIVACY POLICY.-$", "")
    text = text:gsub("COOKIES POLICY.-$", "")

    return cleanHtmlText(text)
end
