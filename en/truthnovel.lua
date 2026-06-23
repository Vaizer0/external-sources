id       = "truthnovel"
name     = "Truth Novel"
version  = "1.0.0"
baseUrl  = "https://truthnovel.top"
language = "en"
icon     = "https://truthnovel.top/wp-content/uploads/2024/02/الجديدة.jpg"

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

    for _, a in ipairs(html_select(r.body, "a.post_title")) do
        table.insert(chapters, {
            title = string_clean(a.text),
            url = a.href
        })
    end

    return chapters
end

function getChapterText(html, url)
    local el = html_select_first(html, ".entry-content")

    if not el then
        return ""
    end

    return html_text(el.html)
end
