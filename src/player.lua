-- Glowy fragmented square. Just-Shapes-and-Beats-style:
--   - body is built from a 3x3 grid of small rounded fragments + a central
--     core. Each hit literally detaches one fragment from the grid; the
--     piece flies off as a chunky shard. The visible body shrinks by the
--     loss, not by a generic scale-down.
--   - movement spawns a stream of glowing mini-square sparkles trailing
--     behind. Dashes spawn them at ~3x density.
--
-- Hit detection in main.lua uses a small fixed-radius circle around the
-- centre of the body, so only direct contact with an obstacle's hot-zone
-- can hurt -- never the soft glow.
local M = {}
M.__index = M

local SPEED         = 580
local DASH_SPEED    = 2400
local DASH_TIME     = 0.22
local DASH_COOLDOWN = 0.36
local IFRAME_HIT    = 1.30
local IFRAME_DASH   = 0.40
local DASH_BUFFER   = 0.18

-- Body geometry
local FRAG_SIZE   = 12
local FRAG_GAP    = 2
local FRAG_STRIDE = FRAG_SIZE + FRAG_GAP        -- 14
local CORE_SIZE   = 14
local BODY_SIZE   = 3 * FRAG_STRIDE             -- 42 (visual span)
local MAX_HP      = 8                           -- 8 outer fragments

-- Sparkle trail
local SPARKLE_HZ      = 32
local SPARKLE_LIFE    = 0.55
local SPARKLE_MAX     = 90
local MOVE_THRESHOLD  = 60

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function rand(a, b) return a + love.math.random() * (b - a) end

local FRAG_OFFSETS = {
  {-1,-1}, {0,-1}, {1,-1},
  {-1, 0},         {1, 0},
  {-1, 1}, {0, 1}, {1, 1},
}

function M.new(x, y, bounds)
  local p = setmetatable({}, M)
  p.x, p.y = x, y
  p.vx, p.vy = 0, 0
  p.size = BODY_SIZE                            -- stable; main.lua scales hit r off this
  p.bounds = bounds
  p.dash_t = 0
  p.dash_cd = 0
  p.dash_dx, p.dash_dy = 0, 0
  p.iframes = 1.5
  p.hp = MAX_HP
  p.alive = true
  p.dashes = 0
  p.hits = 0
  p.flash_t = 0
  p.spin = 0
  p.angle = 0
  p.death_t = 0
  p.dash_buffer = 0
  -- fragmented body
  p.frags = {}
  for _, off in ipairs(FRAG_OFFSETS) do
    table.insert(p.frags, { gx = off[1], gy = off[2], attached = true })
  end
  -- particle pools
  p.shards   = {}
  p.sparkles = {}
  p.sparkle_acc = 0
  return p
end

function M:dashing()   return self.dash_t > 0 end
function M:invincible() return self.iframes > 0 or self:dashing() end

function M:input()
  local ix, iy = 0, 0
  if love.keyboard.isDown("left", "a")  then ix = ix - 1 end
  if love.keyboard.isDown("right", "d") then ix = ix + 1 end
  if love.keyboard.isDown("up", "w")    then iy = iy - 1 end
  if love.keyboard.isDown("down", "s")  then iy = iy + 1 end
  local m = math.sqrt(ix*ix + iy*iy)
  if m > 0 then ix, iy = ix/m, iy/m end
  return ix, iy
end

function M:tryDash()
  if self.dash_cd > 0 or self.dash_t > 0 then
    self.dash_buffer = DASH_BUFFER
    return false
  end
  local ix, iy = self:input()
  if ix == 0 and iy == 0 then return false end
  self.dash_dx, self.dash_dy = ix, iy
  self.dash_t = DASH_TIME
  self.dash_cd = DASH_COOLDOWN
  self.iframes = math.max(self.iframes, IFRAME_DASH)
  self.dashes = self.dashes + 1
  self.dash_buffer = 0
  return true
end

function M:livesLeft() return math.max(0, self.hp) end

local function attachedFrags(self)
  local list = {}
  for i, f in ipairs(self.frags) do if f.attached then table.insert(list, i) end end
  return list
end

-- pick the fragment most "facing" direction (kx,ky) -- so when you get hit on
-- the right, the right-side piece flies off. Falls back to random if no input.
local function pickFragInDirection(self, kx, ky)
  local list = attachedFrags(self)
  if #list == 0 then return nil end
  if kx == 0 and ky == 0 then
    return list[love.math.random(#list)]
  end
  local best, bestScore = nil, -math.huge
  for _, idx in ipairs(list) do
    local f = self.frags[idx]
    -- normalise the grid offset to unit vector for fair scoring
    local fl = math.sqrt(f.gx*f.gx + f.gy*f.gy)
    if fl < 0.01 then fl = 1 end
    local fx, fy = f.gx/fl, f.gy/fl
    local score = fx * kx + fy * ky + (love.math.random() - 0.5) * 0.3
    if score > bestScore then best, bestScore = idx, score end
  end
  return best
end

local function spawnShard(self, x, y, dirx, diry, size, lifeMul)
  table.insert(self.shards, {
    x = x, y = y,
    vx = dirx + (love.math.random() - 0.5) * 80,
    vy = diry + (love.math.random() - 0.5) * 80,
    size = size,
    rot = love.math.random() * math.pi * 2,
    drot = (love.math.random() - 0.5) * 16,
    life = (0.65 + love.math.random() * 0.40) * (lifeMul or 1),
    age = 0,
  })
end

function M:hit()
  if self:invincible() then return false end
  -- detach the fragment most aligned with the hit direction (use input as proxy
  -- for impact direction; reverse it so the back of the ship loses a piece)
  local kx, ky = self:input()
  local idx = pickFragInDirection(self, -kx, -ky)
  if idx then
    local f = self.frags[idx]
    f.attached = false
    local fx = self.x + f.gx * FRAG_STRIDE
    local fy = self.y + f.gy * FRAG_STRIDE
    -- main chunk: the detached fragment itself
    local nx = (f.gx == 0 and 0 or (f.gx > 0 and 1 or -1)) + (love.math.random() - 0.5) * 0.4
    local ny = (f.gy == 0 and 0 or (f.gy > 0 and 1 or -1)) + (love.math.random() - 0.5) * 0.4
    local nm = math.sqrt(nx*nx + ny*ny); if nm < 0.01 then nm = 1 end
    nx, ny = nx/nm, ny/nm
    local sp = 320 + love.math.random() * 380
    spawnShard(self, fx, fy, nx * sp, ny * sp, FRAG_SIZE, 1.2)
    -- a few dust pieces
    for _ = 1, 5 do
      local da = math.atan2(ny, nx) + (love.math.random() - 0.5) * 1.4
      local dsp = 220 + love.math.random() * 260
      spawnShard(self, fx, fy, math.cos(da) * dsp, math.sin(da) * dsp,
                 3 + love.math.random() * 4, 0.7)
    end
  end

  self.hp = self.hp - 1
  self.iframes = IFRAME_HIT
  self.hits = self.hits + 1
  self.flash_t = 0.28
  -- knockback opposite the input direction so the player gets pushed off the
  -- thing that hit them
  local kkx, kky = self:input()
  if kkx == 0 and kky == 0 then
    local r = love.math.random() * math.pi * 2
    kkx, kky = math.cos(r), math.sin(r)
  end
  self.x = self.x - kkx * 26
  self.y = self.y - kky * 26
  self.spin = (love.math.random() < 0.5 and -1 or 1) * 12

  if self.hp <= 0 then
    self.alive = false
    self.death_t = 0
    -- core shatters: extra debris
    for _ = 1, 14 do
      local a = love.math.random() * math.pi * 2
      local sp = 220 + love.math.random() * 380
      spawnShard(self, self.x, self.y, math.cos(a) * sp, math.sin(a) * sp,
                 5 + love.math.random() * 6, 1.1)
    end
  end
  return true
end

function M:revive(x, y)
  self.hp = MAX_HP
  self.alive = true
  self.death_t = 0
  for _, f in ipairs(self.frags) do f.attached = true end
  self.shards = {}
  self.sparkles = {}
  self.iframes = 2.0
  self.flash_t = 0
  self.dash_t = 0
  self.dash_cd = 0
  self.dash_buffer = 0
  self.angle = 0
  self.spin = 0
  if x then self.x, self.y = x, y end
end

local function spawnSparkles(self, dt)
  local mv = math.sqrt(self.vx*self.vx + self.vy*self.vy)
  if mv < MOVE_THRESHOLD then return end
  local rate = SPARKLE_HZ * (self:dashing() and 3.0 or 1.0)
  self.sparkle_acc = self.sparkle_acc + dt * rate
  while self.sparkle_acc >= 1 do
    self.sparkle_acc = self.sparkle_acc - 1
    local nx, ny = -self.vx / mv, -self.vy / mv
    local px, py = -ny, nx
    local off = (love.math.random() - 0.5) * (BODY_SIZE * 0.55)
    local sx = self.x + nx * (BODY_SIZE * 0.35) + px * off
    local sy = self.y + ny * (BODY_SIZE * 0.35) + py * off
    local sp = 40 + love.math.random() * 80
    table.insert(self.sparkles, {
      x = sx, y = sy,
      vx = nx * sp * 0.3 + (love.math.random() - 0.5) * 50,
      vy = ny * sp * 0.3 + (love.math.random() - 0.5) * 50,
      size = 3 + love.math.random() * 4,
      rot = love.math.random() * math.pi * 2,
      drot = (love.math.random() - 0.5) * 6,
      life = SPARKLE_LIFE * (0.55 + 0.55 * love.math.random()),
      age = 0,
      dash = self:dashing(),
    })
  end
  while #self.sparkles > SPARKLE_MAX do table.remove(self.sparkles, 1) end
end

function M:update(dt)
  -- visual decays always run
  self.flash_t = math.max(0, self.flash_t - dt)
  self.spin = self.spin * math.max(0, 1 - dt * 6)
  self.angle = self.angle + self.spin * dt

  -- shards
  for i = #self.shards, 1, -1 do
    local s = self.shards[i]
    s.age = s.age + dt
    s.x = s.x + s.vx * dt
    s.y = s.y + s.vy * dt
    s.vx = s.vx * (1 - dt * 1.6)
    s.vy = s.vy * (1 - dt * 1.6)
    s.rot = s.rot + s.drot * dt
    if s.age >= s.life then table.remove(self.shards, i) end
  end

  -- sparkles
  for i = #self.sparkles, 1, -1 do
    local s = self.sparkles[i]
    s.age = s.age + dt
    s.x = s.x + s.vx * dt
    s.y = s.y + s.vy * dt
    s.vx = s.vx * (1 - dt * 1.4)
    s.vy = s.vy * (1 - dt * 1.4)
    s.rot = s.rot + s.drot * dt
    if s.age >= s.life then table.remove(self.sparkles, i) end
  end

  if not self.alive then
    self.death_t = self.death_t + dt
    return
  end

  self.dash_cd     = math.max(0, self.dash_cd - dt)
  self.dash_t      = math.max(0, self.dash_t  - dt)
  self.iframes     = math.max(0, self.iframes - dt)
  self.dash_buffer = math.max(0, self.dash_buffer - dt)
  if self.dash_buffer > 0 and self.dash_cd <= 0 and self.dash_t <= 0 then
    self:tryDash()
  end

  local vx, vy
  if self:dashing() then
    vx = self.dash_dx * DASH_SPEED
    vy = self.dash_dy * DASH_SPEED
  else
    local ix, iy = self:input()
    vx = ix * SPEED
    vy = iy * SPEED
  end
  self.vx, self.vy = vx, vy
  self.x = self.x + vx * dt
  self.y = self.y + vy * dt

  if self.bounds then
    local b = self.bounds
    local r = self.size * 0.5
    self.x = clamp(self.x, b.x + r, b.x + b.w - r)
    self.y = clamp(self.y, b.y + r, b.y + b.h - r)
  end

  spawnSparkles(self, dt)
end

local function drawRoundedSquare(cx, cy, sz, fillR, fillG, fillB, fillA, cornerR)
  cornerR = cornerR or sz * 0.25
  love.graphics.setColor(fillR, fillG, fillB, fillA)
  love.graphics.rectangle("fill", cx - sz*0.5, cy - sz*0.5, sz, sz, cornerR, cornerR)
end

local function drawFrag(cx, cy, sz, cr, cg, cb, alpha)
  -- soft outer glow
  for i = 3, 1, -1 do
    local s = sz + i * 5
    love.graphics.setColor(cr, cg, cb, 0.10 * alpha)
    love.graphics.rectangle("fill", cx - s*0.5, cy - s*0.5, s, s, s*0.30, s*0.30)
  end
  -- bright white border
  local bs = sz + 3
  love.graphics.setColor(1, 1, 1, 0.95 * alpha)
  love.graphics.rectangle("fill", cx - bs*0.5, cy - bs*0.5, bs, bs, bs*0.28, bs*0.28)
  -- accent fill
  drawRoundedSquare(cx, cy, sz, cr, cg, cb, alpha, sz*0.28)
  -- white inner sparkle
  local inner = sz * 0.45
  love.graphics.setColor(1, 1, 1, 0.85 * alpha)
  love.graphics.rectangle("fill", cx - inner*0.5, cy - inner*0.5, inner, inner, inner*0.30, inner*0.30)
end

function M:draw(accent)
  local ax, ay, az = accent[1], accent[2], accent[3]

  -- 1) sparkle trail (under everything)
  for _, s in ipairs(self.sparkles) do
    local k = 1 - s.age / s.life
    if k > 0 then
      local a = (s.dash and 0.30 or 0.20) * k
      love.graphics.setColor(ax, ay, az, a)
      local h = s.size * 1.7
      love.graphics.rectangle("fill", s.x - h*0.5, s.y - h*0.5, h, h, h*0.4, h*0.4)
      love.graphics.setColor(1, 1, 1, 0.9 * k)
      love.graphics.rectangle("fill", s.x - s.size*0.5, s.y - s.size*0.5,
                              s.size, s.size, s.size*0.35, s.size*0.35)
    end
  end

  -- 2) flying shards (stay alive into death state)
  for _, s in ipairs(self.shards) do
    local k = 1 - s.age / s.life
    if k > 0 then
      love.graphics.push()
      love.graphics.translate(s.x, s.y)
      love.graphics.rotate(s.rot)
      love.graphics.setColor(ax, ay, az, 0.22 * k)
      love.graphics.rectangle("fill", -s.size*1.1, -s.size*1.1, s.size*2.2, s.size*2.2,
                              s.size*0.4, s.size*0.4)
      love.graphics.setColor(1, 1, 1, 0.95 * k)
      love.graphics.rectangle("fill", -s.size*0.5, -s.size*0.5, s.size, s.size,
                              s.size*0.30, s.size*0.30)
      love.graphics.pop()
    end
  end

  if not self.alive then return end

  -- hit-flash whitens the body briefly
  local fx = self.flash_t / 0.28
  if fx < 0 then fx = 0 end
  local cr = ax + (1 - ax) * fx
  local cg = ay + (1 - ay) * fx
  local cb = az + (1 - az) * fx

  local blink = 1
  if self.iframes > 0 and not self:dashing() then
    blink = (math.floor(love.timer.getTime() * 20) % 2 == 0) and 0.5 or 1.0
  end

  -- 3) collective body glow halo (only while body has fragments)
  for i = 5, 1, -1 do
    local s = BODY_SIZE + i * 16
    love.graphics.setColor(cr, cg, cb, 0.05 * blink)
    love.graphics.rectangle("fill", self.x - s*0.5, self.y - s*0.5, s, s, s*0.28, s*0.28)
  end

  -- 4) attached fragments
  for _, f in ipairs(self.frags) do
    if f.attached then
      drawFrag(self.x + f.gx * FRAG_STRIDE,
               self.y + f.gy * FRAG_STRIDE,
               FRAG_SIZE, cr, cg, cb, blink)
    end
  end

  -- 5) the central core (always drawn while alive)
  drawFrag(self.x, self.y, CORE_SIZE, cr, cg, cb, blink)
end

return M
