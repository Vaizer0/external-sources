id       = "truthnovel"
name     = "Truth Novel"
version  = "1.0.3"
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
    return "Lord of Truth / Master of Truth"
end

function getBookGenres(bookUrl)
    return {"Fantasy"}
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
    return "truthnovel-debug"
end

function getChapterText(html, url)
    return html
end
