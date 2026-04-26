-- Beat / onset event stream loader.
-- assets/beats.txt format:
--   # bpm=NNN
--   # duration=SSS
--   <type>\t<seconds>\t<strength>
local M = {}

M.bpm = 138
M.duration = 0
M.events = {}        -- all sorted by time
M.beats  = {}        -- type=='beat'
M.kicks  = {}
M.snares = {}
M.hats   = {}
M.onsets = {}

function M.load()
  local s = love.filesystem.read("assets/beats.txt")
  if not s then return end
  for line in s:gmatch("[^\n]+") do
    local bpm = line:match("^# bpm=([%d%.]+)")
    if bpm then M.bpm = tonumber(bpm) end
    local dur = line:match("^# duration=([%d%.]+)")
    if dur then M.duration = tonumber(dur) end
    local typ, t, str = line:match("^(%a+)\t([%d%.]+)\t([%d%.]+)$")
    if typ then
      local ev = { type = typ, t = tonumber(t), s = tonumber(str) }
      table.insert(M.events, ev)
      if typ == "beat"  then table.insert(M.beats, ev)
      elseif typ == "kick"  then table.insert(M.kicks, ev)
      elseif typ == "snare" then table.insert(M.snares, ev)
      elseif typ == "hat"   then table.insert(M.hats, ev)
      elseif typ == "onset" then table.insert(M.onsets, ev) end
    end
  end
  table.sort(M.events, function(a,b) return a.t < b.t end)
end

-- Iterator state: `cursor` = next-event index to consider, advanced as time progresses.
local cursor = 1

function M.reset(t)
  cursor = 1
  if not t or t <= 0 then return end
  -- skip events that already happened
  while cursor <= #M.events and M.events[cursor].t < t do
    cursor = cursor + 1
  end
end

-- Pre-roll: emit events up to LOOKAHEAD seconds ahead of the playhead so an
-- obstacle's warn phase finishes on the beat (visible/danger moment lands on
-- the music) rather than starting on the beat.
M.LOOKAHEAD = 0.50

function M.fire(t, cb)
  local horizon = t + M.LOOKAHEAD
  while cursor <= #M.events and M.events[cursor].t <= horizon do
    cb(M.events[cursor])
    cursor = cursor + 1
  end
end

-- Return strength of nearest event of given type within window seconds (for pulsing).
function M.proximity(list, t, window)
  -- linear scan from a hint -- list is small enough; bisect optional
  local best = 0
  local lo, hi = 1, #list
  while lo <= hi do
    local m = math.floor((lo + hi) / 2)
    if list[m].t < t - window then lo = m + 1
    elseif list[m].t > t + window then hi = m - 1
    else
      -- found in range, scan neighbours for nearest
      local i = m
      while i >= 1 and list[i].t >= t - window do
        local d = math.abs(list[i].t - t)
        local f = (1 - d / window) * list[i].s
        if f > best then best = f end
        i = i - 1
      end
      i = m + 1
      while i <= #list and list[i].t <= t + window do
        local d = math.abs(list[i].t - t)
        local f = (1 - d / window) * list[i].s
        if f > best then best = f end
        i = i + 1
      end
      break
    end
  end
  return best
end

return M
