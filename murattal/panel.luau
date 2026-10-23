--!nonstrict
-- Murattal panel: searchable qari/surah dropdowns, playback card, favorites.
local ready = false
local render

local reciters = noctalia.state.get("quran_reciters") or {}
local surahs = noctalia.state.get("quran_surahs") or {}
local status = noctalia.state.get("quran_status") or {
  playing = false, name = "", reciterId = "", surahId = 1, volume = 65, url = "",
  repeatOne = false, shuffle = false, speed = 1.0, sleepUntil = 0, position = 0, duration = 0,
}
local favorites = noctalia.state.get("quran_favorites") or {}

local favPath = noctalia.pluginDataDir() .. "/favorites.json"

local function reciterById(id)
  for _, r in ipairs(reciters) do
    if tostring(r.id) == tostring(id) then return r end
  end
end

local function surahById(id)
  for _, s in ipairs(surahs) do
    if tonumber(s.id) == tonumber(id) then return s end
  end
end

local function reciterName(id)
  local r = reciterById(id)
  return r and (r.name or tostring(id)) or tostring(id)
end

local function surahNameById(id)
  local s = surahById(id)
  return s and (s.name or ("Surah " .. tostring(id))) or ("Surah " .. tostring(id))
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

local function refresh()
  if ready and render then render() end
end

local function toggleFav(surahId, reciterId)
  for i, f in ipairs(favorites) do
    if tonumber(f.surahId) == tonumber(surahId) and tostring(f.reciterId) == tostring(reciterId) then
      table.remove(favorites, i)
      saveFavorites()
      refresh()
      return
    end
  end
  table.insert(favorites, {
    surahId = tonumber(surahId),
    reciterId = tostring(reciterId),
    reciterName = reciterName(reciterId),
    surahName = surahNameById(surahId),
  })
  saveFavorites()
  refresh()
end

noctalia.state.watch("quran_reciters", function(v)
  reciters = v or reciters
  refresh()
end)
noctalia.state.watch("quran_surahs", function(v)
  surahs = v or surahs
  refresh()
end)
noctalia.state.watch("quran_status", function(v)
  if type(v) == "table" then
    status = v
    status.repeatOne = status.repeatOne == true
    status.shuffle = status.shuffle == true
    status.speed = tonumber(status.speed) or 1.0
    status.sleepUntil = tonumber(status.sleepUntil) or 0
    status.position = tonumber(status.position) or 0
    status.duration = tonumber(status.duration) or 0
  end
  refresh()
end)
noctalia.state.watch("quran_favorites", function(v)
  if type(v) == "table" then favorites = v end
  refresh()
end)

local qariOpen, surahOpen = false, false
local qariQuery, surahQuery = "", ""
local speedIndex, sleepIndex = 1, 0

local speedValues = {0.75, 1.0, 1.25, 1.5}
local speedLabels = {"0.75x", "1.0x", "1.25x", "1.5x"}
local sleepLabels = {"Off", "15 min", "30 min", "45 min", "60 min"}
local sleepValues = {0, 15, 30, 45, 60}

local function req(action, extra)
  local prev = noctalia.state.get("quran_request")
  local seq = 0
  if type(prev) == "table" and tonumber(prev.seq) then seq = tonumber(prev.seq) end
  local r = { seq = seq + 1, action = action }
  if type(extra) == "table" then
    for k, v in pairs(extra) do r[k] = v end
  end
  noctalia.state.set("quran_request", r)
end

local function filterReciters(q)
  q = (q or ""):lower()
  local out = {}
  for _, r in ipairs(reciters) do
    local label = (r.label or r.name or ""):lower()
    if q == "" or label:find(q, 1, true) or tostring(r.id):lower():find(q, 1, true) then
      table.insert(out, r)
      if #out >= 40 then break end
    end
  end
  return out
end

local function filterSurahs(q)
  q = (q or ""):lower()
  local out = {}
  for _, s in ipairs(surahs) do
    local name = (s.name or ""):lower()
    if q == "" or tostring(s.id):find(q, 1, true) or name:find(q, 1, true) then
      table.insert(out, s)
      if #out >= 40 then break end
    end
  end
  return out
end

local function currentReciterLabel()
  local r = reciterById(status.reciterId)
  return r and (r.label or r.name or tostring(r.id)) or "Pilih qari"
end

local function currentSurahLabel()
  local s = surahById(status.surahId)
  if not s then return "Pilih surah" end
  return string.format("%d. %s", tonumber(s.id) or 0, s.name or "")
end

local function selectReciter(r)
  if not r then return end
  req("setReciter", { reciterId = r.id })
  status.reciterId = r.id
  qariOpen = false
  qariQuery = ""
  refresh()
end

local function selectSurah(s)
  if not s then return end
  req("setSurah", { surahId = s.id })
  status.surahId = s.id
  surahOpen = false
  surahQuery = ""
  refresh()
end

local function fmtTime(sec)
  sec = math.floor(tonumber(sec) or 0)
  if sec < 0 then sec = 0 end
  local m = math.floor(sec / 60)
  local s = sec % 60
  return string.format("%02d:%02d", m, s)
end

local function dropdown(props)
  local children = {
    ui.button({
      key = props.key .. "-trigger",
      text = props.current .. "   " .. (props.open and "▴" or "▾"),
      contentAlign = "start",
      variant = "outline",
      onClick = props.onToggle,
    }),
  }
  if props.open then
    children[#children + 1] = ui.input({
      key = props.key .. "-search",
      value = props.query,
      placeholder = props.placeholder,
      focus = true,
      onChange = props.onQuery,
      onSubmit = function()
        if props.items[1] then props.onPick(props.items[1]) end
      end,
    })
    local rows = {}
    if #props.items == 0 then
      rows[1] = ui.label({ text = "Tidak ada hasil", color = "on_surface_variant", fontSize = 11 })
    else
      for _, item in ipairs(props.items) do
        rows[#rows + 1] = ui.button({
          text = props.label(item),
          contentAlign = "start",
          controlSize = "sm",
          variant = props.isSelected(item) and "secondary" or "ghost",
          onClick = function() props.onPick(item) end,
        })
      end
    end
    children[#children + 1] = ui.scroll({ height = 180, gap = 2 }, rows)
  end
  return ui.column({ gap = 6 }, children)
end

render = function()
  local playing = status.playing == true
  local pos = tonumber(status.position) or 0
  local dur = tonumber(status.duration) or 0
  local curReciter = reciterById(status.reciterId)
  local curSurah = surahById(status.surahId)

  local sp = tonumber(status.speed) or 1.0
  speedIndex = 0
  for i, v in ipairs(speedValues) do
    if math.abs(v - sp) < 0.01 then speedIndex = i - 1 end
  end

  local qariItems = filterReciters(qariQuery)
  local surahItems = filterSurahs(surahQuery)

  local favRows = {}
  for _, f in ipairs(favorites) do
    local title = (f.surahName or surahNameById(f.surahId)) .. " — " .. (f.reciterName or reciterName(f.reciterId))
    favRows[#favRows + 1] = ui.row({ gap = 6, align = "center" }, {
      ui.label({ text = title, flexGrow = 1, fontSize = 11, maxLines = 1 }),
      ui.button({ glyph = "player-play", controlSize = "sm", tooltip = "Play", onClick = function() req("play", { reciterId = f.reciterId, surahId = f.surahId }) end }),
      ui.button({ glyph = "trash", controlSize = "sm", tooltip = "Remove", onClick = function() toggleFav(f.surahId, f.reciterId) end }),
    })
  end
  if #favRows == 0 then
    favRows[1] = ui.label({ text = "Belum ada favorit", color = "on_surface_variant", fontSize = 11 })
  end

  panel.render(ui.scroll({ flexGrow = 1, gap = 12 }, {
    ui.row({ align = "center", justify = "space_between", gap = 8 }, {
      ui.label({ text = "Murottal Al-Qur'an", fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
      ui.button({ glyph = "close", onClick = function() panel.close() end }),
    }),

    ui.column({ gap = 6, padding = 12, radius = 10, fill = "surface_variant/0.35" }, {
      ui.label({ text = curSurah and (curSurah.name or "") or "Belum ada surah", fontSize = 14, fontWeight = "bold" }),
      ui.label({ text = curReciter and (curReciter.name or "") or "Pilih qari", fontSize = 11, color = "on_surface_variant", maxLines = 1 }),
      ui.slider({
        min = 0,
        max = math.max(1, dur),
        step = 1,
        value = math.min(pos, math.max(1, dur)),
        onChange = function(v) req("seek", { seconds = tonumber(v) or 0 }) end,
      }),
      ui.row({ justify = "space_between" }, {
        ui.label({ text = fmtTime(pos) .. " / " .. fmtTime(dur), fontSize = 10, color = "on_surface_variant" }),
        ui.label({ text = playing and "Playing" or "Paused", fontSize = 10, color = playing and "primary" or "on_surface_variant" }),
      }),
      ui.row({ gap = 8, justify = "center" }, {
        ui.button({ glyph = "player-skip-back-filled", onClick = function() req("prev") end }),
        ui.button({ glyph = playing and "player-pause-filled" or "player-play-filled", variant = "primary", onClick = function() req("toggle") end }),
        ui.button({ glyph = "player-skip-forward-filled", onClick = function() req("next") end }),
        ui.button({ glyph = isFav(status.surahId, status.reciterId) and "star-filled" or "star", onClick = function() toggleFav(status.surahId, status.reciterId) end }),
      }),
    }),

    ui.row({ gap = 10, align = "center" }, {
      ui.label({ text = "Volume", fontSize = 11, color = "on_surface_variant", width = 52 }),
      ui.slider({
        flexGrow = 1,
        min = 0,
        max = 100,
        step = 5,
        value = tonumber(status.volume) or 65,
        onChange = function(v) req("volume", { volume = math.floor(tonumber(v) or 0) }) end,
      }),
      ui.label({ text = tostring(status.volume or 65) .. "%", fontSize = 11, color = "on_surface_variant", width = 40, textAlign = "end" }),
    }),

    ui.separator({}),

    dropdown({
      key = "qari",
      open = qariOpen,
      query = qariQuery,
      current = currentReciterLabel(),
      placeholder = "Cari qari...",
      items = qariItems,
      label = function(r) return r.label or r.name or tostring(r.id) end,
      isSelected = function(r) return tostring(r.id) == tostring(status.reciterId) end,
      onToggle = function()
        qariOpen = not qariOpen
        if qariOpen then surahOpen = false end
        refresh()
      end,
      onQuery = function(v) qariQuery = tostring(v or ""); refresh() end,
      onPick = function(r) selectReciter(r) end,
    }),

    dropdown({
      key = "surah",
      open = surahOpen,
      query = surahQuery,
      current = currentSurahLabel(),
      placeholder = "Cari surah...",
      items = surahItems,
      label = function(s) return string.format("%d. %s", tonumber(s.id) or 0, s.name or "") end,
      isSelected = function(s) return tonumber(s.id) == tonumber(status.surahId) end,
      onToggle = function()
        surahOpen = not surahOpen
        if surahOpen then qariOpen = false end
        refresh()
      end,
      onQuery = function(v) surahQuery = tostring(v or ""); refresh() end,
      onPick = function(s) selectSurah(s) end,
    }),

    ui.separator({}),

    ui.row({ gap = 8 }, {
      ui.button({ text = status.repeatOne and "Repeat: On" or "Repeat: Off", flexGrow = 1, onClick = function() req("repeat") end }),
      ui.button({ text = status.shuffle and "Shuffle: On" or "Shuffle: Off", flexGrow = 1, onClick = function() req("shuffle") end }),
    }),

    ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = "Kecepatan", fontSize = 11, color = "on_surface_variant", width = 70 }),
      ui.select({
        options = speedLabels,
        selectedIndex = speedIndex,
        flexGrow = 1,
        onChange = function(index)
          local i = (tonumber(index) or 0) + 1
          if speedValues[i] then
            req("speed", { speed = speedValues[i] })
            status.speed = speedValues[i]
            refresh()
          end
        end,
      }),
      ui.label({ text = "Sleep", fontSize = 11, color = "on_surface_variant", width = 40 }),
      ui.select({
        options = sleepLabels,
        selectedIndex = sleepIndex,
        flexGrow = 1,
        onChange = function(index)
          local i = (tonumber(index) or 0) + 1
          sleepIndex = i - 1
          req("sleep", { minutes = sleepValues[i] or 0 })
          refresh()
        end,
      }),
    }),

    ui.separator({}),

    ui.column({ gap = 6 }, {
      ui.row({ justify = "space_between", align = "center" }, {
        ui.label({ text = "Favorites", fontSize = 12, fontWeight = "medium", color = "on_surface_variant" }),
        ui.label({ text = tostring(#favorites) .. " item", fontSize = 10, color = "on_surface_variant" }),
      }),
      ui.scroll({ height = 150, gap = 4 }, favRows),
    }),
  }))
end

function onOpen(_context)
  loadFavorites()
  refresh()
end

function onClose()
  panel.close()
end

ready = true
