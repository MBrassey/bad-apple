-- Multiplayer ghosts via the portal's [[LOVEWEB_NET]] magic-print bridge.
-- Latency is ~750ms so this is presence + ghost positions, not authoritative
-- play. Each peer broadcasts (x, y, hp, dashing) every 250ms; remote ghosts
-- are smoothed toward last-known position. Connection is best-effort: if the
-- portal is not present (running under stock LÖVE), all calls are silent.
local json = require "lib.json"

local M = {}

M.enabled = false                       -- becomes true after lobby join
M.room    = nil
M.identity = { signedIn = false, handle = "anon" }
M.ghosts  = {}                          -- map: peer_id -> { x, y, hp, dashing, t }
M.send_t  = 0
M.SEND_HZ = 4

local function emit(line) print(line) end

local function readJsonOrNil(path)
  if not love.filesystem.getInfo(path) then return nil end
  local s = love.filesystem.read(path)
  if not s then return nil end
  local ok, data = pcall(json.decode, s)
  if ok then return data end
  return nil
end

function M.load()
  local id = readJsonOrNil("__loveweb__/identity.json")
  if id then M.identity = id end
end

function M.tryJoinPublic()
  emit("[[LOVEWEB_NET]]create lobby Bad Apple // Beat Dash")
  M.enabled = true
end

function M.leave()
  if not M.enabled then return end
  emit("[[LOVEWEB_NET]]leave")
  M.enabled = false
  M.ghosts = {}
end

function M.broadcast(player, dt)
  if not M.enabled then return end
  M.send_t = M.send_t + dt
  if M.send_t < 1 / M.SEND_HZ then return end
  M.send_t = 0
  local payload = {
    x = math.floor(player.x),
    y = math.floor(player.y),
    hp = player.hp,
    d = player:dashing() and 1 or 0,
  }
  emit("[[LOVEWEB_NET]]send pos " .. json.encode(payload))
end

-- Pull inbox events (delivered by portal as JSON lines).
function M.poll()
  if not M.enabled then return end
  local path = "__loveweb__/net/inbox.jsonl"
  if not love.filesystem.getInfo(path) then return end
  local s = love.filesystem.read(path)
  if not s then return end
  for line in s:gmatch("[^\n]+") do
    local ok, ev = pcall(json.decode, line)
    if ok and type(ev) == "table" then
      if ev.kind == "event" and ev.verb == "pos" and ev.from and ev.payload then
        local p = ev.payload
        local g = M.ghosts[ev.from] or {}
        g.tx, g.ty = p.x, p.y
        if not g.x then g.x, g.y = p.x, p.y end
        g.hp = p.hp or 4
        g.dashing = (p.d or 0) == 1
        g.t = love.timer.getTime()
        g.handle = ev.handle or "?"
        M.ghosts[ev.from] = g
      elseif ev.kind == "leave" and ev.from then
        M.ghosts[ev.from] = nil
      end
    end
  end
end

function M.update(dt)
  for id, g in pairs(M.ghosts) do
    if g.tx and g.ty and g.x and g.y then
      g.x = g.x + (g.tx - g.x) * math.min(1, dt * 6)
      g.y = g.y + (g.ty - g.y) * math.min(1, dt * 6)
    end
    -- expire stale ghosts after 4 s of silence
    if g.t and (love.timer.getTime() - g.t) > 4 then
      M.ghosts[id] = nil
    end
  end
end

function M.draw()
  for _, g in pairs(M.ghosts) do
    if g.x and g.y then
      local sz = 22 + (g.hp or 4) * 3.5
      love.graphics.setColor(0.7, 0.85, 1.0, 0.18)
      love.graphics.rectangle("fill", g.x - sz*0.7, g.y - sz*0.7, sz*1.4, sz*1.4, sz*0.3, sz*0.3)
      love.graphics.setColor(0.9, 1.0, 1.0, g.dashing and 0.55 or 0.35)
      love.graphics.rectangle("fill", g.x - sz*0.5, g.y - sz*0.5, sz, sz, sz*0.22, sz*0.22)
      if g.handle then
        love.graphics.setColor(1, 1, 1, 0.55)
        love.graphics.printf(g.handle, g.x - 80, g.y - sz - 24, 160, "center")
      end
    end
  end
end

return M
