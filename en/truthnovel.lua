id       = "truthnovel"
name     = "Truth Novel"
version  = "1.0.2"
baseUrl  = "https://truthnovel.top"
language = "en"
icon     = "https://truthnovel.top/wp-content/uploads/2024/02/الجديدة.jpg"

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

function getCatalogList(index)
    if index > 0 then
        return { items = {}, hasNext = false }
    end

    return {
        items = {
            {
                title = "Lord of Truth",
                url = baseUrl .. "/list/257/",
                cover = icon
            }
        },
        hasNext = false
    }
end

function getCatalogSearch(index, query)
    return getCatalogList(index)
end

function getBookTitle(bookUrl)
    return "Lord of Truth"
end

function getBookCoverImageUrl(bookUrl)
    return icon
end

function getBookDescription(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then
        return "Lord of Truth / Master of Truth"
    end

    local meta = html_select_first(r.body, "meta[property='og:description']")
    if meta and meta.content then
        return meta.content
    end

    return "Lord of Truth / Master of Truth"
end

function getBookGenres(bookUrl)
    return {
        "Fantasy",
        "Action",
        "Adventure",
        "Mystery"
    }
end

function getChapterList(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return {} end

    local chapters = {}

    for _, a in ipairs(html_select(r.body, "a.w4pl_post_title")) do
        local title = string_clean(a.text)
        local url = absUrl(a.href)

        if title ~= "" and url ~= "" then
            table.insert(chapters, {
                title = title,
                url = url
            })
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

    local first = html_select_first(r.body, "a.w4pl_post_title")
    if first then
        return first.href
    end

    return nil
end

function getChapterText(html, url)

    local cleaned = html_remove(
        html,
        "script",
        "style",
        "#comments",
        "#wpdcom",
        ".comments-area",
        ".sharedaddy",
        ".post-share",
        ".post-views"
    )

    local el =
        html_select_first(cleaned, ".single-post-content")
        or html_select_first(cleaned, ".post-content")
        or html_select_first(cleaned, ".wp-block-post-content")
        or html_select_first(cleaned, ".entry-content")
        or html_select_first(cleaned, "article")

    if not el then
        return ""
    end

    local text = html_text(el.html)

    text = string_normalize(text)
    text = string_trim(text)

    return text
end
