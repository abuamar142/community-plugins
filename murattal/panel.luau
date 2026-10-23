--!nonstrict
local reciters = noctalia.state.get("quran_reciters") or {}
local surahs = noctalia.state.get("quran_surahs") or {}
local status = noctalia.state.get("quran_status") or { playing = false, name = "", reciterId = "", surahId = 1, volume = 65, url = "", repeatOne = false, speed = 1.0, sleepUntil = 0 }
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
  if type(v) == "table" then
    status = v
    status.repeatOne = status.repeatOne == true
    status.speed = tonumber(status.speed) or 1.0
    status.sleepUntil = tonumber(status.sleepUntil) or 0
  end
  render()
end)
noctalia.state.watch("quran_favorites", function(v)
  if type(v) == "table" then favorites = v end
  render()
end)

local reciterIndex = 0
local surahIndex = 0
local favIndex = 0
local speedIndex = 1
local sleepIndex = 0
local surahQuery = ""
local qariQuery = ""

local function syncIndices()
  reciterIndex = 0
  for i, r in ipairs(filteredReciters()) do
    if tostring(r.id) == tostring(status.reciterId) then reciterIndex = i - 1 end
  end
  surahIndex = 0
  for i, su in ipairs(filteredSurahs()) do
    if tonumber(su.id) == tonumber(status.surahId) then surahIndex = i - 1 end
  end
  local sp = tonumber(status.speed) or 1.0
  local speeds = {0.75, 1.0, 1.25, 1.5}
  speedIndex = 1
  for i, v in ipairs(speeds) do if math.abs(v - sp) < 0.01 then speedIndex = i - 1 end end
  if favIndex >= #favorites then favIndex = math.max(0, #favorites - 1) end
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
  for _, r in ipairs(filteredReciters()) do table.insert(out, r.label or r.name) end
  if #out == 0 then table.insert(out, "Memuat qari...") end
  return out
end

local function surahOptions()
  local out = {}
  for _, su in ipairs(filteredSurahs()) do table.insert(out, tostring(su.id) .. ". " .. (su.name or "")) end
  if #out == 0 then table.insert(out, "Memuat surah...") end
  return out
end

local speedValues = {0.75, 1.0, 1.25, 1.5}
local speedLabels = {"0.75x", "1.0x", "1.25x", "1.5x"}
local sleepLabels = {"Off", "15 min", "30 min", "45 min", "60 min"}
local sleepValues = {0, 15, 30, 45, 60}

local function favOptions()
  local out = {}
  for _, f in ipairs(favorites) do
    table.insert(out, (f.surahName or "Surah " .. tostring(f.surahId)) .. " — " .. (f.reciterName or reciterName(f.reciterId)))
  end
  if #out == 0 then table.insert(out, "No favorites") end
  return out
end

local function filteredReciters()
  local out = {}
  local q = (qariQuery or ""):lower()
  for _, r in ipairs(reciters) do
    if q == "" or (r.label or r.name or ""):lower():find(q, 1, true) or tostring(r.id):lower():find(q, 1, true) then
      table.insert(out, r)
    end
  end
  if #out == 0 then out = reciters end
  return out
end

local function filteredSurahs()
  local out = {}
  local q = (surahQuery or ""):lower()
  for _, su in ipairs(surahs) do
    if q == "" or tostring(su.id):find(q, 1, true) or (su.name or ""):lower():find(q, 1, true) then
      table.insert(out, su)
    end
  end
  if #out == 0 then out = surahs end
  return out
end

local function fmtTime(sec)
  sec = math.floor(tonumber(sec) or 0)
  if sec < 0 then sec = 0 end
  local m = math.floor(sec / 60)
  local s = sec % 60
  return string.format("%02d:%02d", m, s)
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
      ui.input({ value = qariQuery, placeholder = "Search qari...", onChange = "onQariSearch" }),
      ui.select({ options = reciterOptions(), selectedIndex = reciterIndex, onChange = "onReciter" }),
    }),
    ui.column({ gap = 8 }, {
      ui.label({ text = "Surah", fontWeight = "medium", color = "on_surface_variant" }),
      ui.input({ value = surahQuery, placeholder = "Search surah...", onChange = "onSurahSearch" }),
      ui.select({ options = surahOptions(), selectedIndex = surahIndex, onChange = "onSurah" }),
    }),
    ui.label({ text = playing and ("Playing: " .. (status.name or "")) or "Paused", color = playing and "primary" or "on_surface_variant" }),
    ui.column({ gap = 4 }, {
      ui.slider({ min = 0, max = math.max(1, tonumber(status.duration) or 0), step = 1, value = tonumber(status.position) or 0, onChange = "onSeek" }),
      ui.label({ text = fmtTime(status.position) .. " / " .. fmtTime(status.duration), color = "on_surface_variant" }),
    }),
    ui.row({ gap = 8, justify = "center" }, {
      ui.button({ glyph = "player-skip-back-filled", onClick = "onPrev" }),
      ui.button({ glyph = playing and "player-pause-filled" or "player-play-filled", variant = "primary", onClick = "onToggle" }),
      ui.button({ glyph = "player-skip-forward-filled", onClick = "onNext" }),
      ui.button({ glyph = isFav(status.surahId, status.reciterId) and "star-filled" or "star", onClick = "onToggleFav" }),
      ui.button({ text = status.shuffle and "Shuffle: On" or "Shuffle: Off", onClick = "onShuffle" }),
    }),
    ui.column({ gap = 8 }, {
      ui.label({ text = "Volume: " .. tostring(status.volume or 65) .. "%", fontWeight = "medium", color = "on_surface_variant" }),
      ui.slider({ min = 0, max = 100, step = 5, value = status.volume or 65, onChange = "onVolume" }),
    }),
    ui.row({ gap = 8, justify = "space_between" }, {
      ui.button({ text = status.repeatOne and "Repeat: On" or "Repeat: Off", onClick = "onRepeat" }),
      ui.select({ options = speedLabels, selectedIndex = speedIndex, onChange = "onSpeed" }),
      ui.select({ options = sleepLabels, selectedIndex = sleepIndex, onChange = "onSleep" }),
    }),
    ui.column({ gap = 8 }, {
      ui.label({ text = "Favorites", fontWeight = "medium", color = "on_surface_variant" }),
      ui.select({ options = favOptions(), selectedIndex = favIndex, onChange = "onFavSelect" }),
      ui.row({ gap = 8 }, {
        ui.button({ text = "Play favorite", onClick = "onPlayFav" }),
        ui.button({ text = "Remove favorite", onClick = "onRemoveFav" }),
      }),
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
  local list = filteredReciters()
  local i = (tonumber(index) or 0) + 1
  if list[i] then
    req("setReciter", { reciterId = list[i].id })
    status.reciterId = list[i].id
    render()
  end
end

function onSurah(index, _text)
  local list = filteredSurahs()
  local i = (tonumber(index) or 0) + 1
  if list[i] then
    req("setSurah", { surahId = list[i].id })
    status.surahId = list[i].id
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

function onRepeat()
  req("repeat")
end

function onSpeed(index, _text)
  local i = (tonumber(index) or 0) + 1
  if speedValues[i] then
    req("speed", { speed = speedValues[i] })
    status.speed = speedValues[i]
    render()
  end
end

function onSleep(index, _text)
  local i = (tonumber(index) or 0) + 1
  sleepIndex = i - 1
  local m = sleepValues[i] or 0
  req("sleep", { minutes = m })
  render()
end

function onFavSelect(index, _text)
  favIndex = tonumber(index) or 0
  render()
end

function onPlayFav()
  if #favorites == 0 then return end
  local i = favIndex + 1
  if favorites[i] then
    req("play", { reciterId = favorites[i].reciterId, surahId = favorites[i].surahId })
  end
end

function onRemoveFav()
  if #favorites == 0 then return end
  local i = favIndex + 1
  if favorites[i] then
    toggleFav(favorites[i].surahId, favorites[i].reciterId)
  end
end

function onQariSearch(value)
  qariQuery = tostring(value or "")
  render()
end

function onSurahSearch(value)
  surahQuery = tostring(value or "")
  render()
end

function onShuffle()
  req("shuffle")
end

function onSeek(value)
  local sec = tonumber(value)
  if sec then req("seek", { seconds = sec }) end
end

function onToggleFav()
  toggleFav(status.surahId, status.reciterId)
end
