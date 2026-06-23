id       = "truthnovel"
name     = "Truth Novel"
version  = "1.1.2"
baseUrl  = "https://truthnovel.top"
language = "en"
icon     = "https://truthnovel.top/wp-content/uploads/2024/02/الجديدة.jpg"

local function absUrl(href)
    if not href or href == "" then
        return ""
    end

    if href:sub(1,4) == "http" then
        return href
    end

    if href:sub(1,2) == "//" then
        return "https:" .. href
    end

    return url_resolve(baseUrl, href)
end

function getCatalogList(index)
    if index > 0 then
        return {
            items = {},
            hasNext = false
        }
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
    return { "Fantasy" }
end

function getChapterList(bookUrl)

    local r = http_get(bookUrl)

    if not r.success then
        return {}
    end

    local chapters = {}

    for _, a in ipairs(html_select(r.body, "a.w4pl_post_title")) do
        if a.href and a.text then
            table.insert(chapters, {
                title = a.text,
                url = absUrl(a.href)
            })
        end
    end

    if #chapters == 0 then
        for _, a in ipairs(html_select(r.body, "a.post_title")) do
            if a.href and a.text then
                table.insert(chapters, {
                    title = a.text,
                    url = absUrl(a.href)
                })
            end
        end
    end

    table.sort(chapters, function(a, b)
        local na = tonumber((a.title or ""):match("^(%d+)")) or 0
        local nb = tonumber((b.title or ""):match("^(%d+)")) or 0
        return na < nb
    end)

    return chapters
end

function getChapterListHash(bookUrl)
    return "truthnovel-v112"
end

function getChapterText(html, url)

    if not html or html == "" then
        return ""
    end

    html = html:gsub("<script.-</script>", "")
    html = html:gsub("<style.-</style>", "")

    local entry = html_select_first(html, ".entry-content")

    if not entry then
        return html
    end

    local content = entry.html

    content = content:gsub("<script.-</script>", "")
    content = content:gsub("<style.-</style>", "")

    content = content:gsub("<br%s*/?>", "\n")
    content = content:gsub("</p>", "\n\n")

    local text = html_text(content)

    if not text or text == "" then
        return content
    end

    text = text:gsub("الموضوع السابق.-اذكر الله", "")
    text = text:gsub("الموضوع التالي.*", "")
    text = text:gsub("Disclaimer.*", "")
    text = text:gsub("wpDiscuz.*", "")

    return text
end
