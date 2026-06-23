-- ── Метаданные ───────────────────────────────────────────────────────────────
id       = "localpaste"
name     = "Local Paste"
version  = "1.0.2"
baseUrl  = "https://httpbin.org/"
language = "en"
icon     = "https://raw.githubusercontent.com/Vaizer0/external-sources/refs/heads/main/icons/vaizero.png"

-- ── Константы ────────────────────────────────────────────────────────────────
local STORAGE_KEY = "localpaste_chapters"
local BOOK_TITLE  = "Copypaste"
local BOOK_URL    = "https://httpbin.org/html?book=copypaste"   -- always returns a sample HTML page

-- ── Вспомогательные функции ──────────────────────────────────────────────────

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

local function loadChapters()
    local json = get_preference(STORAGE_KEY)
    if json and json ~= "" then
        local ok, data = pcall(json_parse, json)
        if ok and type(data) == "table" then
            return data
        end
    end
    return {}
end

local function saveChapters(chapters)
    local json = json_stringify(chapters)
    set_preference(STORAGE_KEY, json)
end

local function addChapter(text)
    local chapters = loadChapters()
    table.insert(chapters, text)
    saveChapters(chapters)
    return #chapters
end

local function deleteChapter(index)
    local chapters = loadChapters()
    if index >= 1 and index <= #chapters then
        table.remove(chapters, index)
        saveChapters(chapters)
        return true
    end
    return false
end

local function getChapterTextByIndex(index)
    local chapters = loadChapters()
    if index >= 1 and index <= #chapters then
        return chapters[index]
    end
    return nil
end

local function getChapterCount()
    local chapters = loadChapters()
    return #chapters
end

-- ── Обязательные функции ─────────────────────────────────────────────────────

function getCatalogList(index)
    if index > 0 then
        return { items = {}, hasNext = false }
    end
    local count = getChapterCount()
    return {
        items = {
            {
                title = BOOK_TITLE .. " (" .. count .. " chapters)",
                url   = BOOK_URL,
                cover = ""
            }
        },
        hasNext = false
    }
end

function getCatalogSearch(index, query)
    if index > 0 then
        return { items = {}, hasNext = false }
    end

    -- Delete command
    if query:match("^delete=") then
        local numStr = query:sub(8)
        local num = tonumber(numStr)
        if not num or num < 1 then
            return { items = { { title = "⚠️ Invalid chapter number", url = "", cover = "" } }, hasNext = false }
        end
        local success = deleteChapter(num)
        local count = getChapterCount()
        if success then
            return {
                items = { { title = "🗑️ Chapter " .. num .. " deleted (" .. count .. " remaining)", url = "", cover = "" } },
                hasNext = false
            }
        else
            return {
                items = { { title = "⚠️ Chapter " .. num .. " not found", url = "", cover = "" } },
                hasNext = false
            }
        end
    end

    -- Add new chapter (any text that is not a delete command)
    local text = string_trim(query)
    if text == "" then
        return { items = { { title = "⚠️ Empty text, nothing added", url = "", cover = "" } }, hasNext = false }
    end
    local newNum = addChapter(text)
    return {
        items = { {
            title = "✅ Chapter " .. newNum .. " added (" .. newNum .. " total)",
            url   = "https://httpbin.org/html?chapter=" .. tostring(newNum),
            cover = ""
        } },
        hasNext = false
    }
end

function getBookTitle(bookUrl)
    if bookUrl == BOOK_URL then return BOOK_TITLE end
    return nil
end

function getBookCoverImageUrl(bookUrl)
    return nil
end

function getBookDescription(bookUrl)
    if bookUrl == BOOK_URL then
        return "Total chapters: " .. getChapterCount()
    end
    return nil
end

function getBookGenres(bookUrl)
    return {}
end

function getChapterList(bookUrl)
    if bookUrl ~= BOOK_URL then return {} end
    local chapters = loadChapters()
    local result = {}
    for i, _ in ipairs(chapters) do
        table.insert(result, {
            title = "Chapter " .. i,
            url   = "https://httpbin.org/html?chapter=" .. tostring(i)
        })
    end
    return result
end

function getChapterListHash(bookUrl)
    if bookUrl ~= BOOK_URL then return nil end
    return tostring(getChapterCount()) .. ":" .. tostring(os_time())
end

function getChapterText(html, chapterUrl)
    -- Extract chapter number from the URL
    local num = tonumber(string.match(chapterUrl, "chapter=(%d+)"))
    if not num then
        num = tonumber(string.match(chapterUrl, "/chapter/(%d+)"))
    end
    if not num then
        log_error("localpaste: cannot parse chapter number from " .. tostring(chapterUrl))
        return "Error: Invalid chapter URL. Please re-add the chapter."
    end

    local text = getChapterTextByIndex(num)
    if text then
        return text
    else
        log_error("localpaste: chapter " .. num .. " not found in storage")
        return "Chapter " .. num .. " content missing. Please re-add the chapter."
    end
end

-- ── Настройки ────────────────────────────────────────────────────────────────

function getSettingsSchema()
    return {
        {
            key     = "localpaste_help",
            type    = "text",
            label   = "How to use",
            current = "Search any text to add a chapter. Search 'delete=N' to delete chapter N.",
            options = {}
        }
    }
end

-- ── Фильтры (не поддерживаются) ─────────────────────────────────────────────

function getFilterList()
    return {}
end

function getCatalogFiltered(index, filters)
    return { items = {}, hasNext = false }
end
