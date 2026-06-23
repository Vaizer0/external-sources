-- ── Метаданные ───────────────────────────────────────────────────────────────
id = "local_text"
name = "Local Text (Paste)"
version = "1.0.0"
baseUrl = "local://"
language = "en"
icon = ""

-- ── Константы ───────────────────────────────────────────────────────────────
local STORAGE_KEY = "local_text_books"

-- ── Вспомогательные функции ─────────────────────────────────────────────────

-- Загрузить все книги из настроек
local function loadBooks()
    local json = get_preference(STORAGE_KEY)
    if json and json ~= "" then
        local ok, data = pcall(json_parse, json)
        if ok and type(data) == "table" then
            return data
        end
    end
    return {}  -- массив книг, каждая: { title, chapters = { { title, content }, ... } }
end

-- Сохранить книги в настройки
local function saveBooks(books)
    local json = json_stringify(books)
    set_preference(STORAGE_KEY, json)
end

-- Найти книгу по точному названию (case‑sensitive)
local function findBook(books, title)
    for _, book in ipairs(books) do
        if book.title == title then
            return book
        end
    end
    return nil
end

-- URL‑encode для безопасного использования в URL
local function urlEncode(s)
    return string.gsub(s, "([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

-- URL‑decode
local function urlDecode(s)
    return string.gsub(s, "%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end)
end

-- Создать URL для книги
local function bookUrl(title)
    return "local://book/" .. urlEncode(title)
end

-- Создать URL для главы
local function chapterUrl(bookTitle, chapterIndex)
    return "local://chapter/" .. urlEncode(bookTitle) .. "/" .. tostring(chapterIndex)
end

-- Парсить URL книги
local function parseBookUrl(url)
    local titleEncoded = string.match(url, "^local://book/(.+)$")
    if titleEncoded then
        return urlDecode(titleEncoded)
    end
    return nil
end

-- Парсить URL главы
local function parseChapterUrl(url)
    local bookTitleEnc, idx = string.match(url, "^local://chapter/(.+)/(%d+)$")
    if bookTitleEnc and idx then
        return urlDecode(bookTitleEnc), tonumber(idx)
    end
    return nil, nil
end

-- ── Обязательные функции плагина ─────────────────────────────────────────────

-- Каталог: список всех сохранённых книг
function getCatalogList(index)
    if index > 0 then
        return { items = {}, hasNext = false }
    end
    local books = loadBooks()
    local items = {}
    for _, book in ipairs(books) do
        table.insert(items, {
            title = book.title,
            url = bookUrl(book.title),
            cover = "" -- нет обложки
        })
    end
    return { items = items, hasNext = false }
end

-- Поиск / команды
function getCatalogSearch(index, query)
    if index > 0 then
        return { items = {}, hasNext = false }
    end

    local books = loadBooks()

    -- Команда: добавить книгу
    if query:match("^addbook:") then
        local title = query:sub(9) -- после "addbook:"
        title = string.trim(title)
        if title ~= "" and not findBook(books, title) then
            table.insert(books, { title = title, chapters = {} })
            saveBooks(books)
            return {
                items = { { title = "✅ Book added: " .. title, url = bookUrl(title), cover = "" } },
                hasNext = false
            }
        else
            return {
                items = { { title = "⚠️ Book already exists or empty title", url = "", cover = "" } },
                hasNext = false
            }
        end
    end

    -- Команда: добавить главу
    if query:match("^addchapter:") then
        -- формат: addchapter:Book Title:Chapter Title:Chapter Content
        local rest = query:sub(12) -- после "addchapter:"
        local parts = {}
        for part in string.gmatch(rest, "([^:]+)") do
            table.insert(parts, part)
        end
        if #parts < 3 then
            return {
                items = { { title = "⚠️ Format: addchapter:Book:Chapter:Content", url = "", cover = "" } },
                hasNext = false
            }
        end
        local bookTitle = parts[1]
        local chapterTitle = parts[2]
        local content = table.concat(parts, ":", 3) -- остальное – это содержимое (может содержать двоеточия)

        local book = findBook(books, bookTitle)
        if not book then
            return {
                items = { { title = "⚠️ Book not found: " .. bookTitle, url = "", cover = "" } },
                hasNext = false
            }
        end

        table.insert(book.chapters, { title = chapterTitle, content = content })
        saveBooks(books)
        local idx = #book.chapters
        return {
            items = { {
                title = "✅ Chapter added: " .. chapterTitle .. " (#" .. idx .. ")",
                url = chapterUrl(bookTitle, idx),
                cover = ""
            } },
            hasNext = false
        }
    end

    -- Обычный поиск по названиям книг
    local items = {}
    local lowerQuery = string.lower(query)
    for _, book in ipairs(books) do
        if string.find(string.lower(book.title), lowerQuery, 1, true) then
            table.insert(items, {
                title = book.title,
                url = bookUrl(book.title),
                cover = ""
            })
        end
    end
    return { items = items, hasNext = false }
end

-- Детали книги
function getBookTitle(bookUrl)
    local title = parseBookUrl(bookUrl)
    if not title then return nil end
    local books = loadBooks()
    local book = findBook(books, title)
    if book then
        return book.title
    end
    return nil
end

function getBookCoverImageUrl(bookUrl)
    return nil  -- нет обложек
end

function getBookDescription(bookUrl)
    local title = parseBookUrl(bookUrl)
    if not title then return nil end
    local books = loadBooks()
    local book = findBook(books, title)
    if book then
        return "Chapters: " .. tostring(#book.chapters)
    end
    return nil
end

function getBookGenres(bookUrl)
    return {}
end

-- Список глав
function getChapterList(bookUrl)
    local title = parseBookUrl(bookUrl)
    if not title then return {} end
    local books = loadBooks()
    local book = findBook(books, title)
    if not book then return {} end

    local chapters = {}
    for i, ch in ipairs(book.chapters) do
        table.insert(chapters, {
            title = ch.title or ("Chapter " .. i),
            url = chapterUrl(title, i)
        })
    end
    return chapters
end

function getChapterListHash(bookUrl)
    -- Возвращаем количество глав как хеш, чтобы обновлять при изменениях
    local title = parseBookUrl(bookUrl)
    if not title then return nil end
    local books = loadBooks()
    local book = findBook(books, title)
    if book then
        return tostring(#book.chapters) .. ":" .. os_time()
    end
    return nil
end

-- Текст главы
function getChapterText(html, chapterUrl)
    local bookTitle, idx = parseChapterUrl(chapterUrl)
    if not bookTitle or not idx then
        log_error("local_text: cannot parse chapter URL: " .. tostring(chapterUrl))
        return ""
    end

    local books = loadBooks()
    local book = findBook(books, bookTitle)
    if not book then
        log_error("local_text: book not found: " .. bookTitle)
        return ""
    end

    local ch = book.chapters[idx]
    if not ch then
        log_error("local_text: chapter " .. idx .. " not found in " .. bookTitle)
        return ""
    end

    return ch.content or ""
end

-- ── Настройки (опционально) ──────────────────────────────────────────────────

function getSettingsSchema()
    return {
        {
            key = "local_text_help",
            type = "text",
            label = "How to use",
            current = "Search: addbook:Title | addchapter:Book:Chapter:Content",
            options = {}
        }
    }
end

-- ── Фильтры не поддерживаются ───────────────────────────────────────────────

function getFilterList()
    return {}
end

function getCatalogFiltered(index, filters)
    return { items = {}, hasNext = false }
end
