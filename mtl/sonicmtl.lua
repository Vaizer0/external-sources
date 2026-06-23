id       = "sonicmtl"
name     = "SonicMTL"
version  = "0.1.0"
baseUrl  = "https://www.sonicmtl.com"
language = "en"
icon     = "https://www.sonicmtl.com/favicon.ico"

local function absUrl(href)
if not href or href == "" then return "" end
if string_starts_with(href, "http") then return href end
if string_starts_with(href, "//") then return "https:" .. href end
return url_resolve(baseUrl, href)
end

function getCatalogList(index)
local page = index + 1
local url = baseUrl .. "/page/" .. page .. "/"

local r = http_get(url)
if not r.success then
return { items = {}, hasNext = false }
end

local items = {}

for _, card in ipairs(html_select(r.body, ".page-item-detail")) do
local titleEl = html_select_first(card.html, ".post-title a")
local cover = html_attr(card.html, "img", "src")

if titleEl then
  table.insert(items, {
    title = string_clean(titleEl.text),
    url = absUrl(titleEl.href),
    cover = absUrl(cover)
  })
end

end

return {
items = items,
hasNext = #items > 0
}
end

function getCatalogSearch(index, query)
if index > 0 then
return { items = {}, hasNext = false }
end

local url = baseUrl .. "/?s=" .. url_encode(query)

local r = http_get(url)
if not r.success then
return { items = {}, hasNext = false }
end

local items = {}

for _, card in ipairs(html_select(r.body, ".page-item-detail")) do
local titleEl = html_select_first(card.html, ".post-title a")
local cover = html_attr(card.html, "img", "src")

if titleEl then
  table.insert(items, {
    title = string_clean(titleEl.text),
    url = absUrl(titleEl.href),
    cover = absUrl(cover)
  })
end

end

return {
items = items,
hasNext = false
}
end

function getBookTitle(bookUrl)
local r = http_get(bookUrl)
if not r.success then return nil end

local el = html_select_first(r.body, ".post-title h1")
return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
local r = http_get(bookUrl)
if not r.success then return nil end

local cover = html_attr(r.body, ".summary_image img", "src")
return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
local r = http_get(bookUrl)
if not r.success then return nil end

local el = html_select_first(r.body, ".summary__content")
return el and string_trim(el.text) or nil
end

function getBookGenres(bookUrl)
local r = http_get(bookUrl)
if not r.success then return {} end

local genres = {}

for _, a in ipairs(html_select(r.body, ".genres-content a")) do
local g = string_trim(a.text)
if g ~= "" then
table.insert(genres, g)
end
end

return genres
end

function getChapterList(bookUrl)
local r = http_get(bookUrl)
if not r.success then return {} end

local chapters = {}

for _, a in ipairs(html_select(r.body, ".listing-chapters_wrap a")) do
table.insert(chapters, {
title = string_clean(a.text),
url = absUrl(a.href)
})
end

return chapters
end

function getChapterListHash(bookUrl)
return bookUrl
end

function getChapterText(html, url)
local cleaned = html_remove(
html,
"script",
"style",
".ads",
".advertisement"
)

local el =
html_select_first(
cleaned,
".reading-content .text-left"
)

if not el then
return ""
end

return string_trim(
html_text(el.html)
)
end
