-- SonicMTL plugin for NovaLa
-- Source: https://www.sonicmtl.com/
-- Version: 1.6.0

-- ── Metadata ──────────────────────────────────────────────────────────────

id       = "sonicmtl"
name     = "Sonic MTL"
version  = "1.0.0"
baseUrl  = "https://www.sonicmtl.com"
language = "mtl"          -- machine‑translated novels
icon     = "https://www.sonicmtl.com/wp-content/uploads/2021/09/sonicmtl-icon-1.png"
charset  = "UTF-8"

-- ── Helpers ────────────────────────────────────────────────────────────────

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
    text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
    text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Chapter|Глава)\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*", "")
    text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
    text = string_trim(text)
    return text
end

-- Cache for book pages (single request per book URL)
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

-- Extract numeric post ID from body class (e.g. postid-147851)
local function extractNovelIdFromBody(body)
    local id = regex_match(body, 'postid[%-_](%d+)')
    if id and #id > 0 then return id[1] end
    return nil
end

-- ── Catalog parsing (Madara theme) ──────────────────────────────────────

local function parseCatalogItems(body)
    local items = {}
    local cards = html_select(body, ".page-item-detail .item-summary, .c-tabs-item__content, .novel-item, .book-item")
    if #cards == 0 then
        cards = html_select(body, ".row .col a[href*='/novel/']")
    end
    for _, card in ipairs(cards) do
        local titleEl = html_select_first(card.html, "h3 a, h4 a, .title a, a[href*='/novel/']")
        if not titleEl then
            titleEl = html_select_first(card.html, "a[href*='/novel/']")
        end
        if titleEl then
            local title = string_clean(titleEl.text)
            local url = absUrl(titleEl.href)
            if title ~= "" and url ~= "" then
                local cover = html_attr(card.html, "img", "src")
                if cover == "" then cover = html_attr(card.html, "img[src*='cover']", "src") end
                cover = absUrl(cover)
                table.insert(items, { title = title, url = url, cover = cover })
            end
        end
    end
    return items
end

local function hasNextPage(body)
    local nextLink = html_select_first(body, ".nav-previous a, .pagination .next a, .pagination .next")
    if nextLink then
        local text = string_trim(nextLink.text)
        if text == "" then text = nextLink.href or "" end
        if string.find(text, "Next") or string.find(text, ">") or string.find(text, "→") then
            return true
        end
        return true
    end
    return false
end

-- ── Catalog ────────────────────────────────────────────────────────────────

function getCatalogList(index)
    local page = index + 1
    local url = baseUrl .. "/novel/?page=" .. page
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

-- ── Search ─────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
    local page = index + 1
    local url = baseUrl .. "/?s=" .. url_encode(query) .. "&post_type=wp-manga"
    if page > 1 then
        url = baseUrl .. "/page/" .. page .. "/?s=" .. url_encode(query) .. "&post_type=wp-manga"
    end
    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end
    local items = parseCatalogItems(r.body)
    return { items = items, hasNext = hasNextPage(r.body) }
end

-- ── Book Details (cached) ─────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".post-title h1, h1.title, .post-title")
    return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local cover = html_attr(body, ".summary_image img, .cover-image img, img[src*='cover']", "src")
    if cover == "" then cover = html_attr(body, "meta[property='og:image']", "content") end
    return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".description-summary .summary__content, .novel-description, .summary__content")
    return el and string_trim(el.text) or nil
end

function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end
    local genres = {}
    for _, a in ipairs(html_select(body, ".genres-content a, .genres a")) do
        local label = string_trim(a.text)
        if label ~= "" then table.insert(genres, label) end
    end
    return genres
end

-- ── Chapter List (AJAX via admin-ajax.php) ──────────────────────────────

local function getNovelId(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    return extractNovelIdFromBody(body)
end

-- Fetch one page of chapters via AJAX
local function fetchChaptersPage(novelId, page)
    local url = baseUrl .. "/wp-admin/admin-ajax.php"
    local body = "action=wp-manga-get-chapters&manga_id=" .. novelId .. "&paged=" .. page
    local r = http_post(url, body, {
        headers = {
            ["X-Requested-With"] = "XMLHttpRequest",
            ["Content-Type"] = "application/x-www-form-urlencoded",
        }
    })
    if not r.success then return nil end
    return r.body
end

-- Parse chapters from AJAX HTML response
local function parseChaptersFromHtml(html)
    local chapters = {}
    for _, li in ipairs(html_select(html, ".wp-manga-chapter")) do
        local a = html_select_first(li.html, "a[href]")
        if a and a.href and a.href ~= "" then
            local title = string_clean(a.text)
            if title == "" then title = "Chapter " .. #chapters + 1 end
            table.insert(chapters, { title = title, url = absUrl(a.href) })
        end
    end
    return chapters
end

-- Get total number of pages from pagination in AJAX response
local function getTotalPagesFromHtml(html)
    local pagination = html_select_first(html, ".pagination, .page-numbers")
    if pagination then
        local last = html_select_first(pagination.html, "a:last-child, span:last-child")
        if last then
            local num = tonumber(string_trim(last.text))
            if num then return num end
        end
        local max = 1
        for _, el in ipairs(html_select(pagination.html, "a, span")) do
            local n = tonumber(string_trim(el.text))
            if n and n > max then max = n end
        end
        if max > 1 then return max end
    end
    return 1
end

-- getChapterList: fetch all pages, combine, reverse (oldest first)
function getChapterList(bookUrl)
    local novelId = getNovelId(bookUrl)
    if not novelId then
        log_error("sonicmtl: cannot extract novelId from " .. bookUrl)
        return {}
    end

    local html = fetchChaptersPage(novelId, 1)
    if not html then return {} end
    local totalPages = getTotalPagesFromHtml(html)
    local allChapters = parseChaptersFromHtml(html)

    if totalPages > 1 then
        for p = 2, totalPages do
            local pageHtml = fetchChaptersPage(novelId, p)
            if pageHtml then
                local pageChapters = parseChaptersFromHtml(pageHtml)
                for _, ch in ipairs(pageChapters) do
                    table.insert(allChapters, ch)
                end
            end
            sleep(150)
        end
    end

    local reversed = {}
    for i = #allChapters, 1, -1 do
        table.insert(reversed, allChapters[i])
    end
    return reversed
end

-- Chapter hash: use the latest chapter link (direct HTTP, no cache)
function getChapterListHash(bookUrl)
    local novelId = getNovelId(bookUrl)
    if not novelId then return nil end
    local html = fetchChaptersPage(novelId, 1)
    if not html then return nil end
    local a = html_select_first(html, ".wp-manga-chapter:first-child a")
    return a and a.href or nil
end

-- ── Paginated Chapter List (parsePage) ─────────────────────────────────

function parsePage(bookUrl, page)
    local novelId = getNovelId(bookUrl)
    if not novelId then
        return { chapters = {}, totalPages = 1 }
    end

    local html1 = fetchChaptersPage(novelId, 1)
    if not html1 then
        return { chapters = {}, totalPages = 1 }
    end
    local total = getTotalPagesFromHtml(html1)
    if total < 1 then total = 1 end

    -- Invert: engine page 1 → site page total (oldest)
    local sitePage = total - page + 1
    if sitePage < 1 then sitePage = 1 end
    if sitePage > total then sitePage = total end

    local html = fetchChaptersPage(novelId, sitePage)
    if not html then
        return { chapters = {}, totalPages = total }
    end

    local chapters = parseChaptersFromHtml(html)
    local reversed = {}
    for i = #chapters, 1, -1 do
        table.insert(reversed, chapters[i])
    end
    return { chapters = reversed, totalPages = total }
end

-- ── Chapter Text ───────────────────────────────────────────────────────────

function getChapterText(html, url)
    local cleaned = html_remove(html,
        "script", "style",
        ".ads", ".advertisement",
        ".chapter-nav", ".nav-links",
        "#comments", ".disqus"
    )

    local selectors = {
        ".reading-content .text-left",
        ".entry-content .reading-content",
        ".chapter-content",
        ".content-area",
        ".text-content",
        "#content"
    }
    local el = nil
    for _, sel in ipairs(selectors) do
        el = html_select_first(cleaned, sel)
        if el then break end
    end
    if not el then
        el = html_select_first(cleaned, "body")
        if not el then return "" end
    end
    return applyStandardContentTransforms(html_text(el.html))
end

-- ── Filters ────────────────────────────────────────────────────────────────

function getFilterList()
    return {
        {
            type         = "select",
            key          = "m_orderby",
            label        = "Order By",
            defaultValue = "rating",
            options = {
                { value = "rating",     label = "Rating"      },
                { value = "latest",     label = "Latest"      },
                { value = "alphabet",   label = "A–Z"         },
                { value = "trending",   label = "Trending"    },
                { value = "views",      label = "Most Views"  },
                { value = "new-manga",  label = "New"         },
                { value = "",           label = "Relevance"   },
            }
        },
        {
            type  = "checkbox",
            key   = "genre",
            label = "Genres",
            options = {
                { value = "action",         label = "Action"         },
                { value = "adventure",      label = "Adventure"      },
                { value = "comedy",         label = "Comedy"         },
                { value = "drama",          label = "Drama"          },
                { value = "fantasy",        label = "Fantasy"        },
                { value = "historical",     label = "Historical"     },
                { value = "horror",         label = "Horror"         },
                { value = "martial-arts",   label = "Martial Arts"   },
                { value = "mystery",        label = "Mystery"        },
                { value = "psychological",  label = "Psychological"  },
                { value = "romance",        label = "Romance"        },
                { value = "sci-fi",         label = "Sci-fi"         },
                { value = "shounen",        label = "Shounen"        },
                { value = "slice-of-life",  label = "Slice of Life"  },
                { value = "supernatural",   label = "Supernatural"   },
                { value = "xianxia",        label = "Xianxia"        },
                { value = "xuanhuan",       label = "Xuanhuan"       },
            }
        },
        {
            type         = "select",
            key          = "op",
            label        = "Genres Condition",
            defaultValue = "",
            options = {
                { value = "",  label = "OR (any selected)" },
                { value = "1", label = "AND (all selected)" },
            }
        },
        {
            type         = "select",
            key          = "adult",
            label        = "Adult Content",
            defaultValue = "",
            options = {
                { value = "",  label = "All"               },
                { value = "0", label = "None adult"        },
                { value = "1", label = "Only adult"        },
            }
        },
        {
            type  = "checkbox",
            key   = "status",
            label = "Status",
            options = {
                { value = "on-going",  label = "Ongoing"   },
                { value = "end",       label = "Completed" },
                { value = "canceled",  label = "Canceled"  },
                { value = "on-hold",   label = "On Hold"   },
                { value = "upcoming",  label = "Upcoming"  },
            }
        },
        {
            type         = "text",
            key          = "author",
            label        = "Author",
            defaultValue = ""
        },
        {
            type         = "text",
            key          = "release",
            label        = "Year Released",
            defaultValue = ""
        },
    }
end

-- ── Catalog with Filters ──────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
    local page = index + 1
    local orderby = filters["m_orderby"] or "rating"
    local op = filters["op"] or ""
    local adult = filters["adult"] or ""
    local author = filters["author"] or ""
    local release = filters["release"] or ""
    local genres = filters["genre_included"] or {}
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
    if not r.success then return { items = {}, hasNext = false } end

    local items = parseCatalogItems(r.body)
    return { items = items, hasNext = hasNextPage(r.body) }
end

-- ── End of plugin ─────────────────────────────────────────────────────────
