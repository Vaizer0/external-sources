id       = "truthnovel"
name     = "Truth Novel"
version  = "1.0.8"
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
return {
"Fantasy"
}
end

function getChapterList(bookUrl)

local r = http_get(bookUrl)

if not r.success then
    return {}
end

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

if #chapters == 0 then

    for _, a in ipairs(html_select(r.body, "a.post_title")) do

        local title = string_clean(a.text)
        local url = absUrl(a.href)

        if title ~= "" and url ~= "" then
            table.insert(chapters, {
                title = title,
                url = url
            })
        end
    end
end

table.sort(chapters, function(a, b)

    local na =
        tonumber(
            a.title:match("^(%d+)")
        ) or 0

    local nb =
        tonumber(
            b.title:match("^(%d+)")
        ) or 0

    return na < nb
end)

return chapters

end

function getChapterListHash(bookUrl)
return "truthnovel-v8"
end

function getChapterText(html, url)

html = html:gsub(
    '<script type="application/ld%+json".-</script>',
    ''
)

html = html:gsub(
    '<script.-</script>',
    ''
)

html = html:gsub(
    '<style.-</style>',
    ''
)

local content =
    html:match(
        '<div class="entry%-content.-</div>%s*</div>'
    )

if not content then
    content =
        html:match(
            '<article.-</article>'
        )
end

if not content then
    return html
end

content =
    content:gsub(
        "<br ?/?>",
        "\n"
    )

content =
    content:gsub(
        "</p>",
        "\n\n"
    )

local text = html_text(content)

text =
    text:gsub(
        "الموضوع التالي.*",
        ""
    )

text =
    text:gsub(
        "Disclaimer.*",
        ""
    )

text =
    text:gsub(
        "Novel Stories.*",
        ""
    )

return string_trim(text)

end
