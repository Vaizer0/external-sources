id       = "truthnovel"
name     = "Truth Novel"
version  = "1.1.0"
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

            table.insert(chapters,{
                title = a.text,
                url = absUrl(a.href)
            })
        end
    end

    if #chapters == 0 then

        for _, a in ipairs(html_select(r.body, "a.post_title")) do

            if a.href and a.text then

                table.insert(chapters,{
                    title = a.text,
                    url = absUrl(a.href)
                })
            end
        end
    end

    table.sort(chapters,function(a,b)

        local na =
            tonumber(
                (a.title or ""):match("^(%d+)")
            ) or 0

        local nb =
            tonumber(
                (b.title or ""):match("^(%d+)")
            ) or 0

        return na < nb
    end)

    return chapters
end

function getChapterListHash(bookUrl)
    return "truthnovel-v110"
end

function getChapterText(html,url)

    if not html or html == "" then
        return ""
    end

    html =
        html:gsub(
            "<script.-</script>",
            ""
        )

    html =
        html:gsub(
            "<style.-</style>",
            ""
        )

    html =
        html:gsub(
            '<script type="application/ld%+json".-</script>',
            ""
        )

    local content =
        html:match(
            '<div class="entry%-content[^"]*">(.-)<div id="wpdcom"'
        )

    if not content then
        content =
            html:match(
                '<div class="entry%-content[^"]*">(.-)wpDiscuz'
            )
    end

    if not content then
        content =
            html:match(
                '<article.-<div class="entry%-content[^"]*">(.-)</article>'
            )
    end

    if not content then
        local el =
            html_select_first(
                html,
                ".entry-content"
            )

        if el then
            return html_text(el.html)
        end

        return ""
    end

    content =
        content:gsub(
            '<script.-</script>',
            ''
        )

    content =
        content:gsub(
            '<style.-</style>',
            ''
        )

    content =
        content:gsub(
            '<!%-%-.-%-%->',
            ''
        )

    content =
        content:gsub(
            '<br%s*/?>',
            '\n'
        )

    content =
        content:gsub(
            '</p>',
            '\n\n'
        )

    content =
        content:gsub(
            '<[^>]+>',
            ''
        )

    content =
        content:gsub('&nbsp;',' ')
        :gsub('&amp;','&')
        :gsub('&quot;','"')
        :gsub('&#8217;',"'")
        :gsub('&#8220;','"')
        :gsub('&#8221;','"')

    content =
        content:gsub(
            '"@context".-Novel Stories',
            ''
        )

    content =
        content:gsub(
            'Novel Stories.-الموضوع التالي',
            ''
        )

    content =
        content:gsub(
            'Disclaimer.-$',
            ''
        )

    content =
        content:gsub(
            'wpDiscuz.-$',
            ''
        )

    content =
        content:gsub(
            '\n%s*\n%s*\n+',
            '\n\n'
        )

    return content
end
