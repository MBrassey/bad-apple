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
  -- Identity moved under __loveweb__/net/ (canonical). The legacy path is
  -- still mirrored during the transition, so we read the new one first and
  -- fall back to the old.
  local id = readJsonOrNil("__loveweb__/net/identity.json")
              or readJsonOrNil("__loveweb__/identity.json")
  if id then M.identity = id end
end

function M.tryJoinPublic()
  emit("[[LOVEWEB_NET]]create lobby Bad Apple // Beat Dash")
  M.enabled = true
  M._inbox_cursor = 0
end

function M.leave()
  if not M.enabled then return end
  emit("[[LOVEWEB_NET]]leave")
  M.enabled = false
  M.ghosts = {}
end

function M.broadcast(player, dt, color, upgrades)
  if not M.enabled then return end
  M.send_t = M.send_t + dt
  if M.send_t < 1 / M.SEND_HZ then return end
  M.send_t = 0
  -- Custom verb 'pos' -- passes the ^[a-z][a-z0-9_]*$ rule and isn't in
  -- the reserved set {join, leave, presence, state, kick}, so the portal
  -- forwards the payload to every peer's net inbox unchanged.
  local payload = {
    x = math.floor(player.x),
    y = math.floor(player.y),
    hp = player.hp,
    d = player:dashing() and 1 or 0,
    c = color and { math.floor(color[1]*255), math.floor(color[2]*255), math.floor(color[3]*255) } or nil,
    u = upgrades and {
      h = upgrades.halo and 1 or 0,
      s = upgrades.sparkles and 1 or 0,
    } or nil,
  }
  emit("[[LOVEWEB_NET]]send pos " .. json.encode(payload))
end

-- Profile request -- result lands at __loveweb__/net/profiles/<userId>.json
-- (canonical). The legacy __loveweb__/profiles/<userId>.json is mirrored
-- during the transition. Useful if the lobby ever wants to surface a
-- peer's avatar / public stats; for now it's available as a helper.
function M.requestProfile(userId)
  if not userId then return end
  emit("[[LOVEWEB_NET]]profile " .. tostring(userId))
end

local function readJsonProfile(userId)
  if not userId then return nil end
  return readJsonOrNil("__loveweb__/net/profiles/" .. userId .. ".json")
      or readJsonOrNil("__loveweb__/profiles/" .. userId .. ".json")
end

function M.profile(userId) return readJsonProfile(userId) end

-- Pull inbox events (delivered by portal as JSON lines at the canonical
-- __loveweb__/net/inbox.jsonl). Each line is a full NetEvent JSON with
-- userId, verb, payload, plus id/roomId/handle/avatar/ts/target. We track
-- a byte cursor so we don't re-parse already-handled lines every frame.
M._inbox_cursor = 0

function M.poll()
  if not M.enabled then return end
  local path = "__loveweb__/net/inbox.jsonl"
  local info = love.filesystem.getInfo(path)
  if not info then return end
  if info.size <= M._inbox_cursor then return end
  -- LÖVE filesystem.read can take an offset+length on a File handle; we use
  -- the simpler full-read + slice path (file is small in practice).
  local s = love.filesystem.read(path)
  if not s then return end
  if #s < M._inbox_cursor then M._inbox_cursor = 0 end          -- file truncated
  local tail = s:sub(M._inbox_cursor + 1)
  M._inbox_cursor = #s
  for line in tail:gmatch("[^\n]+") do
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
        if p.c and #p.c == 3 then
          g.color = { p.c[1] / 255, p.c[2] / 255, p.c[3] / 255 }
        end
        if p.u then
          g.halo = (p.u.h or 0) == 1
          g.sparkles = (p.u.s or 0) == 1
        end
        -- maintain a short trail of the ghost's recent positions for sparkle FX
        g.trail = g.trail or {}
        if g.was_dashing or g.dashing then
          table.insert(g.trail, 1, { x = g.x, y = g.y, t = 0 })
          while #g.trail > 30 do table.remove(g.trail) end
        end
        g.was_dashing = g.dashing
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
    if g.trail then
      for i = #g.trail, 1, -1 do
        g.trail[i].t = g.trail[i].t + dt
        if g.trail[i].t > 0.45 then table.remove(g.trail, i) end
      end
    end
    if g.t and (love.timer.getTime() - g.t) > 4 then
      M.ghosts[id] = nil
    end
  end
end

function M.draw()
  for _, g in pairs(M.ghosts) do
    if g.x and g.y then
      local cr, cg, cb = 0.85, 0.95, 1.0
      if g.color then cr, cg, cb = g.color[1], g.color[2], g.color[3] end
      -- trail (during dashes)
      if g.trail then
        for _, p in ipairs(g.trail) do
          local k = 1 - p.t / 0.45
          if k > 0 then
            local s = 26 * (0.6 + 0.5 * k)
            love.graphics.setColor(cr, cg, cb, 0.18 * k)
            love.graphics.rectangle("fill", p.x - s*0.5, p.y - s*0.5, s, s, s*0.22, s*0.22)
          end
        end
      end
      -- glow halo (wider if peer has halo upgrade)
      local halo_n = g.halo and 6 or 3
      for i = halo_n, 1, -1 do
        local s = 36 + i * 14
        love.graphics.setColor(cr, cg, cb, 0.06)
        love.graphics.rectangle("fill", g.x - s*0.5, g.y - s*0.5, s, s, s*0.28, s*0.28)
      end
      -- bright white border
      local sz = 36 + math.max(0, math.min(8, (g.hp or 4))) * 0.4
      love.graphics.setColor(1, 1, 1, g.dashing and 1.0 or 0.85)
      love.graphics.rectangle("fill", g.x - sz*0.5 - 2, g.y - sz*0.5 - 2,
                              sz + 4, sz + 4, (sz+4)*0.22, (sz+4)*0.22)
      -- accent core
      love.graphics.setColor(cr, cg, cb, 1)
      love.graphics.rectangle("fill", g.x - sz*0.5, g.y - sz*0.5, sz, sz, sz*0.22, sz*0.22)
      -- inner white sparkle
      love.graphics.setColor(1, 1, 1, 0.85)
      local inner = sz * 0.42
      love.graphics.rectangle("fill", g.x - inner*0.5, g.y - inner*0.5, inner, inner,
                              inner*0.30, inner*0.30)
      -- handle label
      if g.handle then
        love.graphics.setColor(1, 1, 1, 0.75)
        love.graphics.printf(g.handle, g.x - 100, g.y - sz - 30, 200, "center")
      end
    end
  end
end

function M.peerCount()
  local n = 0
  for _ in pairs(M.ghosts) do n = n + 1 end
  return n
end

return M
