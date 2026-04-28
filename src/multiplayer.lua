-- Multiplayer ghosts via the portal's [[LOVEWEB_NET]] magic-print bridge.
-- Latency is ~750ms so this is presence + ghost positions, not authoritative
-- play. Each peer broadcasts (x, y, hp, dashing) every 250ms; remote ghosts
-- are smoothed toward last-known position. Connection is best-effort: if the
-- portal is not present (running under stock LÖVE), all calls are silent.
local json = require "lib.json"

local M = {}

M.enabled = false                       -- becomes true after lobby join
M.room    = nil                         -- whatever __loveweb__/net/room.json reports
M.identity = { signedIn = false, handle = "anon", userId = nil }
M.ghosts  = {}                          -- map: peer_id -> { x, y, hp, dashing, handle, avatar, t }
M.send_t  = 0
M.SEND_HZ = 4
M._roster_t = 0                         -- accumulator for roster polling

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

-- Open the public Bad Apple lobby. The portal handles routing -- if a
-- public room with this name is already live, the create verb folds into
-- joining it rather than creating a fresh one (so two players who both
-- click M end up in the same room).
function M.tryJoinPublic()
  emit("[[LOVEWEB_NET]]create lobby Bad Apple // Beat Dash")
  M.enabled = true
  M._inbox_cursor = 0
  M._roster_t = 0
  M.ghosts = {}
end

-- Reload identity (the portal may write/update it after auth completes).
local function refreshIdentity()
  local id = readJsonOrNil("__loveweb__/net/identity.json")
              or readJsonOrNil("__loveweb__/identity.json")
  if id then M.identity = id end
end

-- Read the current room metadata. Lets us know which roomId we're in and
-- expose it to the UI for sharing.
local function refreshRoom()
  local r = readJsonOrNil("__loveweb__/net/room.json")
            or readJsonOrNil("__loveweb__/room.json")
  if r then M.room = r end
end

-- Pull the roster: every peer currently in the same room. Each entry
-- arrives with { userId, handle, avatar } at minimum. Peers from the
-- roster are added to M.ghosts immediately so the lobby shows a body
-- for everyone present, even before they've sent a `pos` event.
local function refreshRoster()
  local roster = readJsonOrNil("__loveweb__/net/roster.json")
                  or readJsonOrNil("__loveweb__/roster.json")
  if not roster then return end
  local peers = roster.peers or roster.members or roster
  if type(peers) ~= "table" then return end
  -- normalise into a list of peer entries
  local list = (peers.peers or peers.members) or peers
  for _, peer in ipairs(list) do
    local uid = peer.userId or peer.user_id or peer.id
    if uid and uid ~= (M.identity and M.identity.userId) then
      local g = M.ghosts[uid] or {}
      g.handle = peer.handle or g.handle or "?"
      g.avatar = peer.avatar or g.avatar
      if not g.x then
        -- place fresh peers at a random spot inside the lobby play area
        -- until their first `pos` arrives -- so the room never looks empty
        local hash = 0
        for i = 1, #tostring(uid) do hash = (hash * 31 + tostring(uid):byte(i)) % 1024 end
        g.x = 540 + (hash % 700)
        g.y = 280 + ((hash * 7) % 360)
        g.tx, g.ty = g.x, g.y
      end
      g.t = love.timer.getTime()
      M.ghosts[uid] = g
    end
  end
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
      -- the new spec wraps every event with userId / verb / payload (plus
      -- handle, avatar, ts). We handle both the new shape and the legacy
      -- {kind, from, payload, ...} so older portal builds keep working.
      local from   = ev.userId or ev.from
      local verb   = ev.verb or (ev.kind == "event" and "pos") or ev.kind
      local payload = ev.payload or {}
      local handle = ev.handle
      local avatar = ev.avatar
      if from and from ~= (M.identity and M.identity.userId) then
        if verb == "pos" and payload then
          local p = payload
          local g = M.ghosts[from] or {}
          g.tx, g.ty = p.x, p.y
          if not g.x then g.x, g.y = p.x, p.y end
          g.hp = p.hp or 4
          g.dashing = (p.d or 0) == 1
          g.t = love.timer.getTime()
          g.handle = handle or g.handle or "?"
          g.avatar = avatar or g.avatar
          if p.c and #p.c == 3 then
            g.color = { p.c[1] / 255, p.c[2] / 255, p.c[3] / 255 }
          end
          if p.u then
            g.halo = (p.u.h or 0) == 1
            g.sparkles = (p.u.s or 0) == 1
          end
          g.trail = g.trail or {}
          if g.was_dashing or g.dashing then
            table.insert(g.trail, 1, { x = g.x, y = g.y, t = 0 })
            while #g.trail > 30 do table.remove(g.trail) end
          end
          g.was_dashing = g.dashing
          M.ghosts[from] = g
        elseif verb == "join" or verb == "presence" then
          -- presence ping -- create the ghost if we haven't seen them yet
          local g = M.ghosts[from] or {}
          g.handle = handle or g.handle or "?"
          g.avatar = avatar or g.avatar
          if not g.x then g.x = 720 + love.math.random(0, 480); g.y = 360 + love.math.random(0, 240) end
          g.t = love.timer.getTime()
          M.ghosts[from] = g
        elseif verb == "leave" then
          M.ghosts[from] = nil
        end
      end
    end
  end
end

function M.update(dt)
  -- poll roster + room every ~0.75 s so newly-joined peers appear quickly
  M._roster_t = M._roster_t + dt
  if M.enabled and M._roster_t > 0.75 then
    M._roster_t = 0
    refreshIdentity()
    refreshRoom()
    refreshRoster()
  end
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
    -- expire stale ghosts: 12 s without any presence/pos signal -> drop
    if g.t and (love.timer.getTime() - g.t) > 12 then
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
