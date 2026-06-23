id       = "truthnovel"
name     = "Truth Novel"
version  = "1.0.5"
baseUrl  = "https://truthnovel.top"
language = "en"
icon     = "https://truthnovel.top/wp-content/uploads/2024/02/الجديدة.jpg"

local function absUrl(href)
    if not href or href == "" then
        return ""
    end

    if string_starts_with(href, "http") then
        return href
    end

    if string_starts_with(href, "//") then
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

    -- First selector
    for _, a in ipairs(html_select(r.body, "a.post_title")) do
        table.insert(chapters, {
            title = string_clean(a.text),
            url = absUrl(a.href)
        })
    end

    -- Backup selector
    if #chapters == 0 then
        for _, a in ipairs(html_select(r.body, "a")) do
            if a.href and string.find(a.href, baseUrl) then
                local t = string_clean(a.text)

                if t ~= "" and string.match(t, "^%d+") then
                    table.insert(chapters, {
                        title = t,
                        url = absUrl(a.href)
                    })
                end
            end
        end
    end

    return chapters
end

function getChapterListHash(bookUrl)
    return "truthnovel-v5"
end

function getChapterText(html, url)

    local startPos =
        string.find(
            html,
            '<a href=".-" class="next%-post">'
        )

    if not startPos then
        startPos =
            string.find(
                html,
                '<article class="small single">'
            )
    end

    local endPos =
        string.find(
            html,
            '<div class="post%-views'
        )

    if not endPos then
        endPos =
            string.find(
                html,
                '<div class="post%-share'
            )
    end

    if not startPos or not endPos then

        local article =
            html:match(
                '<article.-</article>'
            )

        if article then
            return string_trim(
                html_to_text(article)
            )
        end

        return ""
    end

    local content =
        string.sub(
            html,
            startPos,
            endPos - 1
        )

    content =
        content:gsub(
            "<script.-</script>",
            ""
        )

    content =
        content:gsub(
            "<style.-</style>",
            ""
        )

    content =
        content:gsub(
            "<hr ?/?>",
            "\n\n"
        )

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

    local text =
        html_to_text(content)

    text =
        text:gsub(
            "الموضوع التالي.-\n",
            ""
        )

    return string_trim(text)
end
