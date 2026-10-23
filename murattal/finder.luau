--!nonstrict
local surahs = noctalia.state.get("quran_surahs") or {}
local status = noctalia.state.get("quran_status") or { reciterId = "", surahId = 1, volume = 65 }
local favorites = {}
local reciters = noctalia.state.get("quran_reciters") or {}

noctalia.state.watch("quran_surahs", function(v)
  surahs = v or surahs
end)
noctalia.state.watch("quran_status", function(v)
  status = v or status
end)
noctalia.state.watch("quran_reciters", function(v)
  reciters = v or reciters
end)
noctalia.state.watch("quran_favorites", function(v)
  if type(v) == "table" then favorites = v end
end)

local function favPath()
  return noctalia.pluginDataDir() .. "/favorites.json"
end

local function loadFavorites()
  local raw = noctalia.readFile(favPath())
  if raw then
    local data = noctalia.json.decode(raw)
    if type(data) == "table" then
      favorites = data
      noctalia.state.set("quran_favorites", favorites)
    end
  end
  return favorites
end

local function saveFavorites()
  noctalia.state.set("quran_favorites", favorites)
  noctalia.writeFile(favPath(), noctalia.json.encode(favorites) or "[]")
end

local function reciterName(id)
  for _, r in ipairs(reciters) do
    if tostring(r.id) == tostring(id) then return r.name end
  end
  return tostring(id)
end

local function surahName(id)
  for _, s in ipairs(surahs) do
    if tonumber(s.id) == tonumber(id) then return s.name end
  end
  return "Surah " .. tostring(id)
end

local function favKey(f)
  return tostring(f.reciterId or "") .. ":" .. tostring(f.surahId or "")
end

local function removeFav(reciterId, surahId)
  for i, f in ipairs(favorites) do
    if tostring(f.reciterId) == tostring(reciterId) and tonumber(f.surahId) == tonumber(surahId) then
      table.remove(favorites, i)
      saveFavorites()
      return true
    end
  end
  return false
end

local function playId(reciterId, surahId)
  return "play:" .. tostring(reciterId or "") .. ":" .. tostring(surahId)
end

local function removeId(reciterId, surahId)
  return "remove:" .. tostring(reciterId or "") .. ":" .. tostring(surahId)
end

local function rowForFav(f, score)
  local rid = f.reciterId or status.reciterId
  local sid = f.surahId
  local title = (f.surahName or surahName(sid)) .. " — " .. (f.reciterName or reciterName(rid))
  return {
    id = playId(rid, sid),
    title = title,
    subtitle = "Favorite - Enter to play, type 'rm' to remove",
    glyph = "star-filled",
    score = score,
  }
end

local function requestPlay(reciterId, surahId)
  local prev = noctalia.state.get("quran_request")
  local seq = 0
  if type(prev) == "table" and tonumber(prev.seq) then seq = tonumber(prev.seq) end
  noctalia.state.set("quran_request", { seq = seq + 1, action = "play", reciterId = reciterId, surahId = tonumber(surahId) })
  noctalia.notify("Quran", "Playing " .. surahName(tonumber(surahId)))
end

function onQuery(text)
  local q = noctalia.string.trim(text or "")
  favorites = loadFavorites()
  local rows = {}

  local lower = q:lower()
  local removeMode = lower == "rm" or lower == "remove" or lower == "unfav"
    or lower:match("^rm%s") or lower:match("^remove%s") or lower:match("^unfav%s")
  if removeMode then
    local filter = q:gsub("^[Rr][Mm]%s*", ""):gsub("^[Rr]emove%s*", ""):gsub("^[Uu]nfav%s*", "")
    filter = noctalia.string.trim(filter)
    for i, f in ipairs(favorites) do
      local title = (f.surahName or surahName(f.surahId)) .. " — " .. (f.reciterName or reciterName(f.reciterId))
      if filter == "" or title:lower():find(filter:lower(), 1, true) then
        table.insert(rows, {
          id = removeId(f.reciterId, f.surahId),
          title = "Remove: " .. title,
          subtitle = "Enter to remove from favorites",
          glyph = "trash",
          score = 100 - i,
        })
      end
    end
    if #rows == 0 then
      rows[1] = { id = "", title = "No favorites to remove", glyph = "mood-empty" }
    end
    launcher.setResults(text, rows)
    return
  end

  if q == "" then
    if #favorites > 0 then
      for i, f in ipairs(favorites) do
        table.insert(rows, rowForFav(f, 100 - i))
      end
    else
      rows[1] = { id = "", title = "No favorites yet", subtitle = "Star a surah in the panel", glyph = "star" }
    end
    table.insert(rows, { id = "", title = "Type a surah name or number", glyph = "search" })
    table.insert(rows, { id = "", title = "Type 'rm' to remove a favorite", glyph = "trash" })
    launcher.setResults(text, rows)
    return
  end

  local n = 0
  for _, s in ipairs(surahs) do
    local score = noctalia.fuzzyScore(q, tostring(s.id) .. " " .. (s.name or ""))
    if score ~= nil then
      n = n + 1
      table.insert(rows, {
        id = playId(status.reciterId, s.id),
        title = s.name,
        subtitle = "Surah " .. tostring(s.id) .. " - Enter to play",
        glyph = "player-play",
        score = (score or 0) + 50 - n * 0.01,
      })
    end
    if n >= 30 then break end
  end

  local num = tonumber(q)
  if num and num >= 1 and num <= 114 then
    local found = false
    for _, r in ipairs(rows) do
      if r.id:find(":" .. tostring(num) .. "$") then found = true end
    end
    if not found then
      table.insert(rows, 1, {
        id = playId(status.reciterId, num),
        title = surahName(num),
        subtitle = "Surah " .. tostring(num) .. " - Enter to play",
        glyph = "player-play",
        score = 1000,
      })
    end
  end

  if #rows == 0 then
    rows[1] = { id = "", title = "No surah found", subtitle = "Try another name", glyph = "mood-empty" }
  end
  launcher.setResults(text, rows)
end

function onActivate(id)
  if id == "" or id == nil then return end
  local rid, sid = string.match(id, "^remove:([^:]+):(%d+)$")
  if rid and sid then
    removeFav(rid, sid)
    noctalia.notify("Quran", "Removed from favorites")
    return
  end
  local reciterId, surahId = string.match(id, "^play:([^:]+):(%d+)$")
  if not surahId then
    surahId = string.match(id, "^play:(%d+)$")
    reciterId = status.reciterId
  end
  if surahId then
    local rid2 = (reciterId and reciterId ~= "") and reciterId or status.reciterId
    requestPlay(rid2, surahId)
  end
end
