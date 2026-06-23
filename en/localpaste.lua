-- ── Метаданные ───────────────────────────────────────────────────────────────
id       = "localpaste"
name     = "Local Paste (Copypaste)"
version  = "1.0.1"
baseUrl  = "local://"
language = "en"
icon     = ""

-- ── Константы ────────────────────────────────────────────────────────────────
local STORAGE_KEY = "localpaste_chapters"
local BOOK_TITLE  = "Copypaste"
local BOOK_URL    = "local://book/copypaste"

-- ── Вспомогательные функции ──────────────────────────────────────────────────

-- Загрузить массив глав (каждая глава – строка текста)
local function loadChapters()
    local json = get_preference(STORAGE_KEY)
    if json and json ~= "" then
        local ok, data = pcall(json_parse, json)
        if ok and type(data) == "table" then
            return data
        end
    end
    return {}  -- массив строк
end

-- Сохранить массив глав
local function saveChapters(chapters)
    local json = json_stringify(chapters)
    set_preference(STORAGE_KEY, json)
end

-- Добавить главу (возвращает новый номер)
local function addChapter(text)
    local chapters = loadChapters()
    table.insert(chapters, text)
    saveChapters(chapters)
    return #chapters
end

-- Удалить главу по номеру (1‑based), возвращает успех
local function deleteChapter(index)
    local chapters = loadChapters()
    if index >= 1 and index <= #chapters then
        table.remove(chapters, index)
        saveChapters(chapters)
        return true
    end
    return false
end

-- Получить текст главы по номеру
local function getChapterTextByIndex(index)
    local chapters = loadChapters()
    if index >= 1 and index <= #chapters then
        return chapters[index]
    end
    return nil
end

-- Получить количество глав
local function getChapterCount()
    local chapters = loadChapters()
    return #chapters
end

-- ── Обязательные функции (согласно гайду) ───────────────────────────────────

-- Каталог: всегда показываем одну книгу "Copypaste"
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

-- Поиск / команды
function getCatalogSearch(index, query)
    if index > 0 then
        return { items = {}, hasNext = false }
    end

    -- Команда удаления: delete=<число>
    if query:match("^delete=") then
        local numStr = query:sub(8)  -- после "delete="
        local num = tonumber(numStr)
        if not num or num < 1 then
            return {
                items = { { title = "⚠️ Invalid chapter number", url = "", cover = "" } },
                hasNext = false
            }
        end
        local success = deleteChapter(num)
        local count = getChapterCount()
        if success then
            return {
                items = { {
                    title = "🗑️ Chapter " .. num .. " deleted (" .. count .. " remaining)",
                    url = "",
                    cover = ""
                } },
                hasNext = false
            }
        else
            return {
                items = { { title = "⚠️ Chapter " .. num .. " not found", url = "", cover = "" } },
                hasNext = false
            }
        end
    end

    -- Всё остальное считается текстом новой главы
    local text = string.trim(query)
    if text == "" then
        return {
            items = { { title = "⚠️ Empty text, nothing added", url = "", cover = "" } },
            hasNext = false
        }
    end
    local newNum = addChapter(text)
    return {
        items = { {
            title = "✅ Chapter " .. newNum .. " added (" .. newNum .. " total)",
            url   = "local://chapter/" .. tostring(newNum),
            cover = ""
        } },
        hasNext = false
    }
end

-- Детали книги
function getBookTitle(bookUrl)
    if bookUrl == BOOK_URL then
        return BOOK_TITLE
    end
    return nil
end

function getBookCoverImageUrl(bookUrl)
    return nil  -- нет обложки
end

function getBookDescription(bookUrl)
    if bookUrl == BOOK_URL then
        local count = getChapterCount()
        return "Total chapters: " .. count
    end
    return nil
end

function getBookGenres(bookUrl)
    return {}
end

-- Список глав
function getChapterList(bookUrl)
    if bookUrl ~= BOOK_URL then
        return {}
    end
    local chapters = loadChapters()
    local result = {}
    for i, ch in ipairs(chapters) do
        table.insert(result, {
            title = "Chapter " .. i,
            url   = "local://chapter/" .. tostring(i)
        })
    end
    return result
end

function getChapterListHash(bookUrl)
    if bookUrl ~= BOOK_URL then
        return nil
    end
    local count = getChapterCount()
    -- Хеш = количество глав + время последнего изменения (приблизительно)
    return tostring(count) .. ":" .. tostring(os_time())
end

-- Текст главы
function getChapterText(html, chapterUrl)
    -- Извлекаем номер главы из URL
    local num = tonumber(string.match(chapterUrl, "/chapter/(%d+)$"))
    if not num then
        log_error("localpaste: cannot parse chapter number from " .. tostring(chapterUrl))
        return ""
    end
    local text = getChapterTextByIndex(num)
    if text then
        return text
    else
        log_error("localpaste: chapter " .. num .. " not found")
        return ""
    end
end

-- ── Настройки (инструкция) ──────────────────────────────────────────────────

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
