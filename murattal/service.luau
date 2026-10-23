--!nonstrict
-- Service: owns mpv playback and mp3quran.net catalog.
-- State channels:
--   quran_reciters = [ {id,name,label,server,surahs=[1..114]} ]
--   quran_surahs   = [ {id,name} ]
--   quran_status   = { playing, name, reciterId, surahId, volume, url }
--   quran_request  = { seq, action, reciterId?, surahId?, volume? }

local dataDir = noctalia.pluginDataDir()
local SOCK = dataDir .. "/mpv.sock"
local PIDFILE = dataDir .. "/mpv.pid"

local volume = tonumber(noctalia.getConfig("default_volume")) or 65
local mpvBin = noctalia.getConfig("mpv_bin") or "mpv"
local hasSocat = noctalia.commandExists("socat")

local reciters = {}
local surahs = {}
local status = { playing = false, name = "", reciterId = "", surahId = 1, volume = volume, url = "" }
local lastSeq = -1
local launchedAt = 0
local deadStreak = 0
local playGen = 0
local queue, queueBusy, queueSince = {}, false, 0

local function publish()
  noctalia.state.set("quran_status", {
    playing = status.playing,
    name = status.name,
    reciterId = status.reciterId,
    surahId = status.surahId,
    volume = status.volume,
    url = status.url,
  })
end

local function sq(s)
  return "'" .. string.gsub(s or "", "'", "'\\''") .. "'"
end

local function pad(n)
  return string.format("%03d", tonumber(n) or 0)
end

local function findReciter(id)
  for _, r in ipairs(reciters) do
    if tostring(r.id) == tostring(id) then
      return r
    end
  end
  return nil
end

local function findSurah(id)
  for _, s in ipairs(surahs) do
    if tonumber(s.id) == tonumber(id) then
      return s
    end
  end
  return nil
end

local function aliveCheck(onResult)
  local cmd = "test -S " .. sq(SOCK) .. " && test -f " .. sq(PIDFILE)
    .. " && p=$(tail -n 1 " .. sq(PIDFILE) .. ") && case \"$p\" in *[!0-9]*) exit 1 ;; esac && kill -0 \"$p\" 2>/dev/null"
    .. " && grep -qa mpv /proc/\"$p\"/cmdline 2>/dev/null"
  noctalia.runAsync(cmd, function(res)
    onResult(res.exitCode == 0)
  end)
end

local function mpvCmd(payload)
  noctalia.writeFile(dataDir .. "/mpvcmd.json", payload .. "\n")
  return "(socat - " .. sq(SOCK) .. " < " .. sq(dataDir .. "/mpvcmd.json") .. " >/dev/null 2>&1 || true)"
end

local function killRecorded(signal)
  local guard = "grep -qa mpv /proc/\"$p\"/cmdline 2>/dev/null && grep -qaF -- "
    .. sq(dataDir) .. " /proc/\"$p\"/cmdline 2>/dev/null"
  return "while read -r p; do case \"$p\" in ''|*[!0-9]*) continue ;; esac; "
    .. "if " .. guard .. "; then kill " .. signal .. " \"$p\" >/dev/null 2>&1 || true; fi; done < "
    .. sq(PIDFILE)
end

local function sweepStray(signal)
  local comm = string.match(mpvBin, "([^/]+)$") or "mpv"
  return "for f in $(grep -laF -- " .. sq(SOCK) .. " /proc/[0-9]*/cmdline 2>/dev/null); do "
    .. "p=${f#/proc/}; p=${p%/cmdline}; "
    .. "[ \"$(cat /proc/$p/comm 2>/dev/null)\" = " .. sq(comm) .. " ] || continue; "
    .. "kill " .. signal .. " \"$p\" >/dev/null 2>&1 || true; done"
end

local function killStrays(signal)
  return "if [ -f " .. sq(PIDFILE) .. " ]; then " .. killRecorded(signal) .. "; fi; "
    .. sweepStray(signal)
end

local function stopMpv(onDone)
  local parts = {}
  if hasSocat then
    table.insert(parts, mpvCmd('{"command":["quit"]}'))
  end
  table.insert(parts, "sleep 0.3")
  table.insert(parts, killStrays(""))
  table.insert(parts, "sleep 0.4")
  table.insert(parts, killStrays("-9"))
  table.insert(parts, "rm -f " .. sq(SOCK) .. " " .. sq(PIDFILE))
  noctalia.runAsync(table.concat(parts, "; "), function()
    if onDone then onDone() end
  end)
end

local function launchMpv(url, name, onDone)
  local cmd = "rm -f " .. sq(SOCK) .. "; "
    .. "nohup " .. sq(mpvBin) .. " --no-video --input-ipc-server=" .. sq(SOCK)
    .. " --volume=" .. tostring(status.volume)
    .. " --title=" .. sq("quran: " .. name)
    .. " -- " .. sq(url) .. " >" .. sq(dataDir .. "/mpv.log") .. " 2>&1 & "
    .. "echo $! >> " .. sq(PIDFILE)
  noctalia.writeFile(dataDir .. "/lastcmd.txt", cmd)
  return noctalia.runAsync(cmd, function(res)
    if onDone then onDone(res) end
  end)
end

local function runNext()
  if queueBusy then return end
  local job = table.remove(queue, 1)
  if not job then return end
  queueBusy = true
  queueSince = os.time()
  local finished = false
  job(function()
    if finished then return end
    finished = true
    queueBusy = false
    runNext()
  end)
end

local function enqueue(job)
  table.insert(queue, job)
  runNext()
end

local function fetchReciters(attempt)
  attempt = attempt or 1
  noctalia.http({ url = "https://www.mp3quran.net/api/v3/reciters?language=id" }, function(res)
    if res and res.ok then
      local data = noctalia.json.decode(res.body)
      if type(data) == "table" and type(data.reciters) == "table" then
        local out = {}
        for _, q in ipairs(data.reciters) do
          for _, m in ipairs(q.moshaf or {}) do
            if m.server and tonumber(m.surah_total) == 114 then
              table.insert(out, { id = tostring(q.id) .. "-" .. tostring(m.id), name = q.name, label = q.name .. " — " .. (m.name or ""), server = m.server })
            end
          end
        end
        reciters = out
        noctalia.state.set("quran_reciters", reciters)
        if status.reciterId == "" and #reciters > 0 then
          status.reciterId = reciters[1].id
          publish()
        end
        noctalia.log("[quran] reciters: " .. tostring(#reciters))
        return
      end
    end
    noctalia.log("[quran] reciter fetch failed (attempt " .. tostring(attempt) .. ")")
    if attempt < 3 then
      fetchReciters(attempt + 1)
    end
  end)
end

local function fetchSuwar(attempt)
  attempt = attempt or 1
  noctalia.http({ url = "https://www.mp3quran.net/api/v3/suwar?language=id" }, function(res)
    if res and res.ok then
      local data = noctalia.json.decode(res.body)
      if type(data) == "table" and type(data.suwar) == "table" then
        local out = {}
        for _, s in ipairs(data.suwar) do
          table.insert(out, { id = tonumber(s.id), name = s.name })
        end
        surahs = out
        noctalia.state.set("quran_surahs", surahs)
        noctalia.log("[quran] surahs: " .. tostring(#surahs))
        return
      end
    end
    noctalia.log("[quran] suwar fetch failed (attempt " .. tostring(attempt) .. ")")
    if attempt < 3 then
      fetchSuwar(attempt + 1)
    else
      -- fallback so playback still works
      if #surahs == 0 then
        local out = {}
        for i = 1, 114 do table.insert(out, { id = i, name = "Surah " .. tostring(i) }) end
        surahs = out
        noctalia.state.set("quran_surahs", surahs)
        noctalia.log("[quran] using fallback surah list")
      end
    end
  end)
end

local function fetchCatalog()
  fetchReciters(1)
  fetchSuwar(1)
end

local function doPlay(reciterId, surahId)
  local r = findReciter(reciterId)
  local s = findSurah(surahId)
  if not r then
    noctalia.notifyError("Quran", "Qari tidak ditemukan")
    return
  end
  if not s then
    noctalia.notifyError("Quran", "Surah tidak ditemukan")
    return
  end
  local url = r.server .. pad(s.id) .. ".mp3"
  playGen = playGen + 1
  local gen = playGen
  status.reciterId = tostring(r.id)
  status.surahId = tonumber(s.id)
  status.name = s.name .. " — " .. r.name
  status.url = url
  status.playing = true
  publish()

  local dropped = false
  local function superseded()
    if gen == playGen then return false end
    if not dropped then
      dropped = true
      noctalia.log("[quran] play superseded")
    end
    return true
  end

  enqueue(function(done)
    if superseded() then done(); return end
    stopMpv(function()
      if superseded() then done(); return end
      launchMpv(url, status.name, function(res)
        local launched = (res == nil or res.exitCode == 0)
        noctalia.log("[quran] launched=" .. tostring(launched))
        if launched then
          launchedAt = os.time()
          deadStreak = 0
          publish()
        else
          noctalia.notifyError("Quran", "Gagal memutar mpv")
          status.playing = false
          publish()
        end
        done()
      end)
    end)
  end)
end

local function doStop()
  playGen = playGen + 1
  status.playing = false
  publish()
  enqueue(function(done)
    stopMpv(done)
  end)
end

local function doVolume(v)
  v = math.clamp(math.floor(tonumber(v) or status.volume), 0, 100)
  status.volume = v
  publish()
  if not status.playing then return end
  if hasSocat then
    enqueue(function(done)
      noctalia.runAsync(mpvCmd('{"command":["set_property","volume",' .. tostring(v) .. "]}"), function()
        done()
      end)
    end)
  else
    local url = status.url
    if url == "" then return end
    enqueue(function(done)
      if not status.playing or url ~= status.url then done(); return end
      stopMpv(function()
        if not status.playing or url ~= status.url then done(); return end
        launchMpv(url, status.name, function() done() end)
      end)
    end)
  end
end

local function handleRequest(req)
  if type(req) ~= "table" then return end
  local seq = tonumber(req.seq) or -1
  if seq <= lastSeq then return end
  lastSeq = seq
  noctalia.log("[quran] request action=" .. tostring(req.action))
  if req.action == "play" then
    doPlay(req.reciterId or status.reciterId, req.surahId or status.surahId)
  elseif req.action == "stop" then
    doStop()
  elseif req.action == "toggle" then
    if status.playing then doStop() else doPlay(status.reciterId, status.surahId) end
  elseif req.action == "volume" then
    doVolume(req.volume)
  elseif req.action == "next" then
    local i = 1
    for idx, s in ipairs(surahs) do
      if tonumber(s.id) == tonumber(status.surahId) then i = idx; break end
    end
    local nextId = surahs[(i % #surahs) + 1].id
    doPlay(status.reciterId, nextId)
  elseif req.action == "prev" then
    local i = 1
    for idx, s in ipairs(surahs) do
      if tonumber(s.id) == tonumber(status.surahId) then i = idx; break end
    end
    local prevId = surahs[((i - 2 + #surahs) % #surahs) + 1].id
    doPlay(status.reciterId, prevId)
  elseif req.action == "setReciter" then
    status.reciterId = tostring(req.reciterId)
    publish()
  elseif req.action == "setSurah" then
    status.surahId = tonumber(req.surahId) or status.surahId
    publish()
  end
end

noctalia.state.watch("quran_request", handleRequest)
local initial = noctalia.state.get("quran_request")
if initial ~= nil then handleRequest(initial) end

publish()
fetchCatalog()

noctalia.setUpdateInterval(2000)

function update()
  if queueBusy and os.time() - queueSince > 15 then
    noctalia.log("[quran] queue stuck, reset")
    queue, queueBusy = {}, false
  end
  if status.playing then
    if os.time() - launchedAt < 8 then return end
    aliveCheck(function(alive)
      if not status.playing then return end
      if alive then
        deadStreak = 0
        return
      end
      deadStreak = deadStreak + 1
      if deadStreak < 2 then return end
      deadStreak = 0
      local failedFast = os.time() - launchedAt < 30
      local name = status.name
      if failedFast then
        status.playing = false
        publish()
        noctalia.notifyError("Quran", "Gagal memutar (" .. name .. ")")
        noctalia.log("[quran] mpv died fast, see mpv.log")
      else
        -- natural end: advance to next surah
        local i = 1
        for idx, s in ipairs(surahs) do
          if tonumber(s.id) == tonumber(status.surahId) then i = idx; break end
        end
        if #surahs > 0 then
          local nextId = surahs[(i % #surahs) + 1].id
          doPlay(status.reciterId, nextId)
        else
          status.playing = false
          publish()
        end
      end
    end)
  end
end

function onConfigChanged()
  volume = math.clamp(math.floor(tonumber(noctalia.getConfig("default_volume")) or volume), 0, 100)
  mpvBin = noctalia.getConfig("mpv_bin") or mpvBin
  hasSocat = noctalia.commandExists("socat")
  if not status.playing then
    status.volume = volume
    publish()
  end
end

function onIpc(event, payload)
  noctalia.log("[quran] onIpc " .. tostring(event))
  if event == "play" and payload and payload ~= "" then
    local ok, data = pcall(function() return noctalia.json.decode(payload) end)
    if ok and type(data) == "table" then
      handleRequest({ seq = lastSeq + 1, action = "play", reciterId = data.reciterId, surahId = data.surahId })
    else
      handleRequest({ seq = lastSeq + 1, action = "play" })
    end
  elseif event == "stop" then
    handleRequest({ seq = lastSeq + 1, action = "stop" })
  elseif event == "toggle" then
    handleRequest({ seq = lastSeq + 1, action = "toggle" })
  elseif event == "volume" then
    local v = tonumber(payload)
    if v then handleRequest({ seq = lastSeq + 1, action = "volume", volume = v }) end
  elseif event == "next" then
    handleRequest({ seq = lastSeq + 1, action = "next" })
  elseif event == "prev" then
    handleRequest({ seq = lastSeq + 1, action = "prev" })
  elseif event == "refresh" then
    fetchCatalog()
  end
end

function onExit(signal, reason)
  doStop()
end
