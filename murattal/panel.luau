--!nonstrict
local reciters = noctalia.state.get("quran_reciters") or {}
local surahs = noctalia.state.get("quran_surahs") or {}
local status = noctalia.state.get("quran_status") or { playing = false, name = "", reciterId = "", surahId = 1, volume = 65, url = "" }
local favorites = noctalia.state.get("quran_favorites") or {}

local favPath = noctalia.pluginDataDir() .. "/favorites.json"

local function reciterName(id)
  for _, r in ipairs(reciters) do
    if tostring(r.id) == tostring(id) then return r.name end
  end
  return tostring(id)
end

local function surahNameById(id)
  for _, s in ipairs(surahs) do
    if tonumber(s.id) == tonumber(id) then return s.name end
  end
  return "Surah " .. tostring(id)
end

local function loadFavorites()
  local raw = noctalia.readFile(favPath)
  if raw then
    local data = noctalia.json.decode(raw)
    if type(data) == "table" then favorites = data end
  end
  noctalia.state.set("quran_favorites", favorites)
end

local function saveFavorites()
  noctalia.state.set("quran_favorites", favorites)
  noctalia.writeFile(favPath, noctalia.json.encode(favorites) or "[]")
end

local function isFav(surahId, reciterId)
  for _, f in ipairs(favorites) do
    if tonumber(f.surahId) == tonumber(surahId) and tostring(f.reciterId) == tostring(reciterId) then return true end
  end
  return false
end

local function toggleFav(surahId, reciterId)
  for i, f in ipairs(favorites) do
    if tonumber(f.surahId) == tonumber(surahId) and tostring(f.reciterId) == tostring(reciterId) then
      table.remove(favorites, i)
      saveFavorites()
      render()
      return
    end
  end
  table.insert(favorites, { surahId = tonumber(surahId), reciterId = tostring(reciterId), reciterName = reciterName(reciterId), surahName = surahNameById(surahId) })
  saveFavorites()
  render()
end

noctalia.state.watch("quran_reciters", function(v)
  reciters = v or reciters
  render()
end)
noctalia.state.watch("quran_surahs", function(v)
  surahs = v or surahs
  render()
end)
noctalia.state.watch("quran_status", function(v)
  status = v or status
  render()
end)
noctalia.state.watch("quran_favorites", function(v)
  if type(v) == "table" then favorites = v end
  render()
end)

local reciterIndex = 0
local surahIndex = 0

local function syncIndices()
  for i, r in ipairs(reciters) do
    if tostring(r.id) == tostring(status.reciterId) then reciterIndex = i - 1 end
  end
  for i, s in ipairs(surahs) do
    if tonumber(s.id) == tonumber(status.surahId) then surahIndex = i - 1 end
  end
end

local function req(action, extra)
  local prev = noctalia.state.get("quran_request")
  local seq = 0
  if type(prev) == "table" and tonumber(prev.seq) then seq = tonumber(prev.seq) end
  local r = { seq = seq + 1, action = action }
  if type(extra) == "table" then for k,v in extra do r[k]=v end end
  noctalia.state.set("quran_request", r)
end

local function reciterOptions()
  local out = {}
  for _, r in ipairs(reciters) do table.insert(out, r.label or r.name) end
  if #out == 0 then table.insert(out, "Memuat qari...") end
  return out
end

local function surahOptions()
  local out = {}
  for _, s in ipairs(surahs) do table.insert(out, tostring(s.id) .. ". " .. (s.name or "")) end
  if #out == 0 then table.insert(out, "Memuat surah...") end
  return out
end

function render()
  syncIndices()
  local playing = status.playing == true
  panel.render(ui.column({ flexGrow = 1, gap = 16 }, {
    ui.row({ align = "center", justify = "space_between", gap = 8 }, {
      ui.label({ text = "Murottal Al-Qur'an", fontSize = 16, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
      ui.button({ glyph = "close", onClick = "onClose" }),
    }),
    ui.column({ gap = 8 }, {
      ui.label({ text = "Qari", fontWeight = "medium", color = "on_surface_variant" }),
      ui.select({ options = reciterOptions(), selectedIndex = reciterIndex, onChange = "onReciter" }),
    }),
    ui.column({ gap = 8 }, {
      ui.label({ text = "Surah", fontWeight = "medium", color = "on_surface_variant" }),
      ui.select({ options = surahOptions(), selectedIndex = surahIndex, onChange = "onSurah" }),
    }),
    ui.label({ text = playing and ("Playing: " .. (status.name or "")) or "Paused", color = playing and "primary" or "on_surface_variant" }),
    ui.row({ gap = 8, justify = "center" }, {
      ui.button({ glyph = "player-skip-back-filled", onClick = "onPrev" }),
      ui.button({ glyph = playing and "player-pause-filled" or "player-play-filled", variant = "primary", onClick = "onToggle" }),
      ui.button({ glyph = "player-skip-forward-filled", onClick = "onNext" }),
      ui.button({ glyph = isFav(status.surahId, status.reciterId) and "star-filled" or "star", onClick = "onToggleFav" }),
    }),
    ui.column({ gap = 8 }, {
      ui.label({ text = "Volume: " .. tostring(status.volume or 65) .. "%", fontWeight = "medium", color = "on_surface_variant" }),
      ui.slider({ min = 0, max = 100, step = 5, value = status.volume or 65, onChange = "onVolume" }),
    }),
    ui.label({ text = "Favorites: " .. tostring(#favorites), color = "on_surface_variant" }),
  }))
end

function onOpen(_context)
  loadFavorites()
  syncIndices()
  render()
end

function onClose()
  panel.close()
end

function onReciter(index, _text)
  local i = (tonumber(index) or 0) + 1
  if reciters[i] then
    req("setReciter", { reciterId = reciters[i].id })
    status.reciterId = reciters[i].id
    render()
  end
end

function onSurah(index, _text)
  local i = (tonumber(index) or 0) + 1
  if surahs[i] then
    req("setSurah", { surahId = surahs[i].id })
    status.surahId = surahs[i].id
    render()
  end
end

function onToggle()
  req("toggle")
end

function onPrev()
  req("prev")
end

function onNext()
  req("next")
end

function onVolume(value)
  local v = math.floor(tonumber(value) or 0)
  req("volume", { volume = v })
end

function onToggleFav()
  toggleFav(status.surahId, status.reciterId)
end
