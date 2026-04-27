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
-- cooldown must exceed IFRAME_DASH so dash spam can't grant permanent invuln
local DASH_COOLDOWN = 0.52
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

function M.new(x, y, bounds, hp_bonus)
  local p = setmetatable({}, M)
  p.x, p.y = x, y
  p.vx, p.vy = 0, 0
  p.size = BODY_SIZE                            -- stable; main.lua scales hit r off this
  p.bounds = bounds
  p.dash_t = 0
  p.dash_cd = 0
  p.dash_dx, p.dash_dy = 0, 0
  p.iframes = 1.5
  p.hp_bonus = hp_bonus or 0
  p.hp = MAX_HP + p.hp_bonus
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
  self.dash_cd = DASH_COOLDOWN * (self.dash_cooldown_mul or 1)
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
  self.hp = MAX_HP + (self.hp_bonus or 0)        -- preserve HP upgrade across revives
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
  local boost = self.sparkle_boost and 2.0 or 1.0
  local rate = SPARKLE_HZ * (self:dashing() and 3.0 or 1.0) * boost
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

local function regPoly(cx, cy, n, r, rot)
  local pts = {}
  for i = 0, n - 1 do
    local a = (rot or -math.pi * 0.5) + i * math.pi * 2 / n
    table.insert(pts, cx + math.cos(a) * r)
    table.insert(pts, cy + math.sin(a) * r)
  end
  return pts
end

local function starPoly(cx, cy, points, r_outer, r_inner, rot)
  local pts = {}
  for i = 0, points * 2 - 1 do
    local a = (rot or -math.pi * 0.5) + i * math.pi / points
    local r = (i % 2 == 0) and r_outer or r_inner
    table.insert(pts, cx + math.cos(a) * r)
    table.insert(pts, cy + math.sin(a) * r)
  end
  return pts
end

local function heartPoly(cx, cy, sz)
  -- 24-sample classic heart parametric
  local pts = {}
  local s = sz * 0.058
  for i = 0, 23 do
    local t = i * (math.pi * 2) / 24
    local x = 16 * math.sin(t) ^ 3
    local y = -(13 * math.cos(t) - 5 * math.cos(2*t) - 2 * math.cos(3*t) - math.cos(4*t))
    table.insert(pts, cx + x * s)
    table.insert(pts, cy + y * s)
  end
  return pts
end

local function drawShape(cx, cy, sz, fillR, fillG, fillB, fillA, shape, rot)
  shape = shape or "square"
  love.graphics.setColor(fillR, fillG, fillB, fillA)
  if shape == "diamond" then
    love.graphics.push(); love.graphics.translate(cx, cy)
    love.graphics.rotate((rot or 0) + math.pi * 0.25)
    love.graphics.rectangle("fill", -sz*0.5, -sz*0.5, sz, sz, sz*0.18, sz*0.18)
    love.graphics.pop()
  elseif shape == "hex" then
    love.graphics.polygon("fill", regPoly(cx, cy, 6, sz * 0.55, rot))
  elseif shape == "triangle" then
    love.graphics.polygon("fill", regPoly(cx, cy, 3, sz * 0.62, rot))
  elseif shape == "circle" then
    love.graphics.circle("fill", cx, cy, sz * 0.50)
  elseif shape == "heart" then
    love.graphics.polygon("fill", heartPoly(cx, cy, sz))
  elseif shape == "star" then
    love.graphics.polygon("fill", starPoly(cx, cy, 5, sz * 0.58, sz * 0.26, rot))
  elseif shape == "cross" then
    local s = sz * 0.30
    love.graphics.rectangle("fill", cx - sz*0.5, cy - s*0.5, sz, s, s*0.3, s*0.3)
    love.graphics.rectangle("fill", cx - s*0.5, cy - sz*0.5, s, sz, s*0.3, s*0.3)
  elseif shape == "octagon" then
    love.graphics.polygon("fill", regPoly(cx, cy, 8, sz * 0.52, (rot or 0) + math.pi / 8))
  elseif shape == "pentagon" then
    love.graphics.polygon("fill", regPoly(cx, cy, 5, sz * 0.55, rot))
  else
    love.graphics.rectangle("fill", cx - sz*0.5, cy - sz*0.5, sz, sz, sz*0.25, sz*0.25)
  end
end

local function drawFrag(cx, cy, sz, cr, cg, cb, alpha, shape)
  for i = 3, 1, -1 do
    local s = sz + i * 5
    love.graphics.setColor(cr, cg, cb, 0.10 * alpha)
    drawShape(cx, cy, s, cr, cg, cb, 0.10 * alpha, shape)
  end
  local bs = sz + 3
  drawShape(cx, cy, bs, 1, 1, 1, 0.95 * alpha, shape)
  drawShape(cx, cy, sz, cr, cg, cb, alpha, shape)
  local inner = sz * 0.45
  drawShape(cx, cy, inner, 1, 1, 1, 0.85 * alpha, shape)
end

function M:draw(accent)
  local ax, ay, az = accent[1], accent[2], accent[3]

  -- 1) trail / tracer (under everything). Style depends on equipped trail_id
  local trail_id = self.trail_id or "sparkle"
  local function drawTrailParticle(s, k)
    local id = trail_id
    if id == "comet" then
      love.graphics.setColor(ax, ay, az, 0.30 * k)
      love.graphics.circle("fill", s.x, s.y, s.size * 1.8)
      love.graphics.setColor(1, 1, 1, 0.85 * k)
      love.graphics.circle("fill", s.x, s.y, s.size * 0.8)
    elseif id == "ember" then
      love.graphics.setColor(1.0, 0.55 + 0.3 * k, 0.20, 0.55 * k)
      love.graphics.circle("fill", s.x, s.y, s.size * 1.4)
      love.graphics.setColor(1, 1, 0.6, 0.85 * k)
      love.graphics.circle("fill", s.x, s.y, s.size * 0.55)
    elseif id == "ghost" then
      love.graphics.setColor(ax, ay, az, 0.20 * k)
      love.graphics.rectangle("fill", s.x - s.size*1.2, s.y - s.size*1.2,
                              s.size*2.4, s.size*2.4, s.size*0.6, s.size*0.6)
      love.graphics.setColor(0.9, 0.95, 1.0, 0.55 * k)
      love.graphics.rectangle("line", s.x - s.size*0.6, s.y - s.size*0.6,
                              s.size*1.2, s.size*1.2, s.size*0.3, s.size*0.3)
    elseif id == "matrix" then
      love.graphics.setColor(0.20, 1.00, 0.45, 0.85 * k)
      local h = s.size * 1.6
      love.graphics.rectangle("fill", s.x - 1.5, s.y - h, 3, h * 2)
      love.graphics.setColor(0.85, 1.0, 0.85, k)
      love.graphics.rectangle("fill", s.x - 1.5, s.y - 1, 3, 3)
    elseif id == "stardust" then
      love.graphics.setColor(1, 1, 0.9, 0.65 * k)
      love.graphics.polygon("fill", starPoly(s.x, s.y, 4, s.size * 1.3, s.size * 0.45, 0))
    elseif id == "vapor" then
      for i = 3, 1, -1 do
        love.graphics.setColor(0.85, 0.90, 1.0, 0.10 * k)
        love.graphics.circle("fill", s.x, s.y, s.size * (1 + i * 0.6))
      end
    elseif id == "bolt" then
      love.graphics.setColor(0.85, 0.95, 1.0, 0.9 * k)
      love.graphics.setLineWidth(2)
      local a = math.atan2(s.vy, s.vx)
      local nx, ny = -math.sin(a), math.cos(a)
      local L = s.size * 2.2
      love.graphics.line(
        s.x - math.cos(a)*L*0.5, s.y - math.sin(a)*L*0.5,
        s.x + nx * L * 0.20,     s.y + ny * L * 0.20,
        s.x + math.cos(a)*L*0.0, s.y + math.sin(a)*L*0.0,
        s.x - nx * L * 0.18,     s.y - ny * L * 0.18,
        s.x + math.cos(a)*L*0.5, s.y + math.sin(a)*L*0.5)
      love.graphics.setLineWidth(1)
    elseif id == "confetti" then
      local hue = (s.x + s.y) % 6
      local cols = {{1,0.4,0.5},{1,0.85,0.4},{0.5,1,0.6},{0.4,0.9,1},{0.85,0.6,1},{1,0.6,0.4}}
      local c = cols[math.floor(hue) + 1]
      love.graphics.setColor(c[1], c[2], c[3], 0.90 * k)
      love.graphics.push(); love.graphics.translate(s.x, s.y); love.graphics.rotate(s.rot)
      love.graphics.rectangle("fill", -s.size*0.7, -s.size*0.4, s.size*1.4, s.size*0.8, 1, 1)
      love.graphics.pop()
    elseif id == "pixel" then
      love.graphics.setColor(ax, ay, az, 0.85 * k)
      local sz = s.size * 1.6
      love.graphics.rectangle("fill", math.floor(s.x - sz*0.5), math.floor(s.y - sz*0.5), sz, sz)
    elseif id == "snow" then
      love.graphics.setColor(1, 1, 1, 0.85 * k)
      love.graphics.circle("fill", s.x, s.y, s.size * 0.6)
      for i = 0, 5 do
        local a = i * math.pi / 3
        love.graphics.line(s.x, s.y, s.x + math.cos(a) * s.size, s.y + math.sin(a) * s.size)
      end
    elseif id == "plasma" then
      love.graphics.setColor(0.55, 0.80, 1.0, 0.45 * k)
      love.graphics.circle("fill", s.x, s.y, s.size * 1.6)
      love.graphics.setColor(1, 1, 1, k)
      love.graphics.circle("fill", s.x, s.y, s.size * 0.45)
    elseif id == "petal" then
      love.graphics.setColor(1.0, 0.55, 0.85, 0.80 * k)
      love.graphics.push(); love.graphics.translate(s.x, s.y); love.graphics.rotate(s.rot)
      love.graphics.ellipse("fill", 0, 0, s.size * 1.3, s.size * 0.55)
      love.graphics.pop()
    elseif id == "aurora" then
      love.graphics.setColor(0.55, 1.0, 0.80, 0.35 * k)
      love.graphics.setLineWidth(s.size * 0.9)
      local L = s.size * 1.8
      local a = math.atan2(s.vy, s.vx) + math.sin(s.age * 8) * 0.4
      love.graphics.line(s.x - math.cos(a)*L, s.y - math.sin(a)*L,
                         s.x + math.cos(a)*L, s.y + math.sin(a)*L)
      love.graphics.setLineWidth(1)
    elseif id == "solar" then
      love.graphics.setColor(1, 0.85, 0.30, 0.55 * k)
      love.graphics.circle("fill", s.x, s.y, s.size * 1.8)
      love.graphics.setColor(1, 1, 0.60, k)
      love.graphics.circle("fill", s.x, s.y, s.size * 0.7)
    elseif id == "void" then
      love.graphics.setColor(0, 0, 0, 0.85 * k)
      love.graphics.circle("fill", s.x, s.y, s.size * 1.4)
      love.graphics.setColor(0.55, 0.40, 1.0, k)
      love.graphics.circle("line", s.x, s.y, s.size * 1.4)
    else  -- glint / sparkle
      local a = (s.dash and 0.30 or 0.20) * k
      love.graphics.setColor(ax, ay, az, a)
      local h = s.size * 1.7
      love.graphics.rectangle("fill", s.x - h*0.5, s.y - h*0.5, h, h, h*0.4, h*0.4)
      love.graphics.setColor(1, 1, 1, 0.9 * k)
      love.graphics.rectangle("fill", s.x - s.size*0.5, s.y - s.size*0.5,
                              s.size, s.size, s.size*0.35, s.size*0.35)
    end
  end
  for _, s in ipairs(self.sparkles) do
    local k = 1 - s.age / s.life
    if k > 0 then drawTrailParticle(s, k) end
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
  local halo_n = self.halo_boost and 9 or 5
  local halo_step = self.halo_boost and 18 or 16
  local halo_a = self.halo_boost and 0.07 or 0.05
  for i = halo_n, 1, -1 do
    local s = BODY_SIZE + i * halo_step
    love.graphics.setColor(cr, cg, cb, halo_a * blink)
    love.graphics.rectangle("fill", self.x - s*0.5, self.y - s*0.5, s, s, s*0.28, s*0.28)
  end

  -- 3b) equipped aura cosmetic
  local rt = love.timer.getTime()
  local aura = self.aura_id or "default"
  if aura == "ring" then
    love.graphics.setColor(cr, cg, cb, 0.85 * blink)
    love.graphics.setLineWidth(3)
    local r = BODY_SIZE * 0.95 + math.sin(rt * 4) * 4
    love.graphics.circle("line", self.x, self.y, r)
    for i = 0, 3 do
      local a = rt * 1.4 + i * math.pi * 0.5
      love.graphics.setColor(1, 1, 1, blink)
      love.graphics.circle("fill", self.x + math.cos(a)*r, self.y + math.sin(a)*r, 4)
    end
    love.graphics.setLineWidth(1)
  elseif aura == "twin" then
    love.graphics.setColor(cr, cg, cb, 0.55 * blink)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", self.x, self.y, BODY_SIZE * 0.85 + math.sin(rt * 3) * 6)
    love.graphics.circle("line", self.x, self.y, BODY_SIZE * 1.15 - math.sin(rt * 3) * 6)
    love.graphics.setLineWidth(1)
  elseif aura == "starlit" then
    love.graphics.setColor(1, 1, 1, 0.75 * blink)
    for i = 0, 5 do
      local a = rt * 0.8 + i * math.pi / 3
      local rr = BODY_SIZE * 1.05 + math.sin(rt * 2 + i) * 4
      love.graphics.rectangle("fill", self.x + math.cos(a)*rr - 2, self.y + math.sin(a)*rr - 2, 4, 4)
    end
  elseif aura == "halo" then
    -- warm wide halo with soft gold tint
    for i = 6, 1, -1 do
      love.graphics.setColor(1.0, 0.85, 0.45, 0.07 * blink)
      love.graphics.circle("fill", self.x, self.y, BODY_SIZE * 0.7 + i * 8)
    end
    love.graphics.setColor(1, 1, 0.85, 0.55 * blink)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", self.x, self.y, BODY_SIZE * 1.05 + math.sin(rt * 1.5) * 3)
    love.graphics.setLineWidth(1)
  elseif aura == "pulse" then
    -- 3 concentric rings each with its own breathing phase
    for i = 1, 3 do
      local r = BODY_SIZE * (0.95 + i * 0.18 + math.sin(rt * 2 + i * 1.2) * 0.06)
      love.graphics.setColor(cr, cg, cb, 0.45 * blink / i)
      love.graphics.setLineWidth(2)
      love.graphics.circle("line", self.x, self.y, r)
    end
    love.graphics.setLineWidth(1)
  elseif aura == "plasma" then
    -- jittery electric ring with random arc breaks
    love.graphics.setColor(0.55, 0.85, 1.0, 0.85 * blink)
    love.graphics.setLineWidth(2)
    local r = BODY_SIZE * 1.0
    local segs = 24
    for i = 0, segs - 1 do
      if (i + math.floor(rt * 12)) % 4 ~= 0 then
        local a0 = i * math.pi * 2 / segs + math.sin(rt * 6 + i) * 0.04
        local a1 = a0 + math.pi * 2 / segs * 0.85
        love.graphics.arc("line", "open", self.x, self.y, r, a0, a1)
      end
    end
    love.graphics.setLineWidth(1)
  elseif aura == "orbit" then
    local a = rt * 2.4
    local r = BODY_SIZE * 1.20
    local px = self.x + math.cos(a) * r
    local py = self.y + math.sin(a) * r
    for i = 4, 1, -1 do
      love.graphics.setColor(cr, cg, cb, 0.10 * blink)
      love.graphics.circle("fill", px, py, 4 + i * 4)
    end
    love.graphics.setColor(1, 1, 1, blink)
    love.graphics.circle("fill", px, py, 6)
  elseif aura == "shock" then
    -- expanding rings emitted on a cycle
    for i = 0, 2 do
      local age = (rt + i * 0.4) % 1.2
      local k = age / 1.2
      local r = BODY_SIZE * (0.7 + 1.6 * k)
      love.graphics.setColor(cr, cg, cb, 0.55 * (1 - k) * blink)
      love.graphics.setLineWidth(3 * (1 - k))
      love.graphics.circle("line", self.x, self.y, r)
    end
    love.graphics.setLineWidth(1)
  elseif aura == "phantom" then
    -- delayed echoes: faded copies trailing the player at recent positions
    local count = math.min(#self.trail, 5)
    for i = 1, count do
      local p = self.trail[math.floor((#self.trail / count) * i)]
      if p then
        love.graphics.setColor(cr, cg, cb, 0.18 * (1 - i / (count + 1)) * blink)
        love.graphics.rectangle("fill", p.x - BODY_SIZE * 0.45, p.y - BODY_SIZE * 0.45,
                                BODY_SIZE * 0.9, BODY_SIZE * 0.9, BODY_SIZE * 0.18, BODY_SIZE * 0.18)
      end
    end
  end

  -- 4) attached fragments
  local shape = self.shape_id or "square"
  for _, f in ipairs(self.frags) do
    if f.attached then
      drawFrag(self.x + f.gx * FRAG_STRIDE,
               self.y + f.gy * FRAG_STRIDE,
               FRAG_SIZE, cr, cg, cb, blink, shape)
    end
  end

  -- 5) the central core (always drawn while alive)
  drawFrag(self.x, self.y, CORE_SIZE, cr, cg, cb, blink, shape)
end

-- Lobby preview helper: draw a small icon for a given customisation kind
-- and id at (cx, cy) within radius r. Used to render the wardrobe tiles.
function M.drawIcon(kind, id, cx, cy, r, accent)
  local ax, ay, az = accent[1], accent[2], accent[3]
  if kind == "shape" then
    drawShape(cx, cy, r * 1.6, ax, ay, az, 1.0, id, 0)
  elseif kind == "aura" then
    -- faux body + aura ring sample
    drawShape(cx, cy, r * 0.85, ax, ay, az, 1.0, "square", 0)
    if id == "ring" then
      love.graphics.setColor(1, 1, 1, 0.85)
      love.graphics.setLineWidth(2)
      love.graphics.circle("line", cx, cy, r * 0.95)
      for i = 0, 3 do
        local a = i * math.pi * 0.5
        love.graphics.circle("fill", cx + math.cos(a)*r*0.95, cy + math.sin(a)*r*0.95, 2.5)
      end
      love.graphics.setLineWidth(1)
    elseif id == "twin" then
      love.graphics.setColor(ax, ay, az, 0.7); love.graphics.setLineWidth(2)
      love.graphics.circle("line", cx, cy, r * 0.80)
      love.graphics.circle("line", cx, cy, r * 1.05)
      love.graphics.setLineWidth(1)
    elseif id == "starlit" then
      love.graphics.setColor(1,1,1,1)
      for i = 0, 5 do
        local a = i * math.pi / 3
        love.graphics.rectangle("fill", cx + math.cos(a)*r*0.95 - 1.5,
                                cy + math.sin(a)*r*0.95 - 1.5, 3, 3)
      end
    elseif id == "halo" then
      for i = 4, 1, -1 do
        love.graphics.setColor(1.0, 0.85, 0.45, 0.10)
        love.graphics.circle("fill", cx, cy, r * 0.65 + i * 4)
      end
    elseif id == "pulse" then
      love.graphics.setColor(ax, ay, az, 0.7); love.graphics.setLineWidth(2)
      for i = 1, 3 do love.graphics.circle("line", cx, cy, r * (0.55 + i * 0.18)) end
      love.graphics.setLineWidth(1)
    elseif id == "plasma" then
      love.graphics.setColor(0.55, 0.85, 1.0, 0.95); love.graphics.setLineWidth(2)
      for i = 0, 11 do
        if i % 3 ~= 0 then
          local a = i * math.pi / 6
          love.graphics.arc("line", "open", cx, cy, r * 0.95, a, a + math.pi/9)
        end
      end
      love.graphics.setLineWidth(1)
    elseif id == "orbit" then
      love.graphics.setColor(1, 1, 1, 0.5)
      love.graphics.circle("line", cx, cy, r * 1.0)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.circle("fill", cx + r * 1.0, cy, 4)
    elseif id == "shock" then
      love.graphics.setColor(ax, ay, az, 0.85); love.graphics.setLineWidth(2)
      love.graphics.circle("line", cx, cy, r * 0.7)
      love.graphics.setColor(ax, ay, az, 0.45)
      love.graphics.circle("line", cx, cy, r * 1.0)
      love.graphics.setLineWidth(1)
    elseif id == "phantom" then
      for i = 0, 3 do
        love.graphics.setColor(ax, ay, az, 0.18)
        love.graphics.rectangle("fill", cx - r*0.55 - i * 4, cy - r*0.45,
                                r*1.1, r*0.9, r*0.2, r*0.2)
      end
    end
  elseif kind == "trail" then
    -- mock trail: 4 sample particles, faded toward the back
    local function particle(px, py, k)
      local s = { x = px, y = py, size = r * 0.20, vx = -1, vy = 0, age = 0, life = 1, rot = 0 }
      local kk = k                       -- alpha factor
      if id == "comet" then
        love.graphics.setColor(ax, ay, az, 0.5 * kk); love.graphics.circle("fill", px, py, r * 0.30)
        love.graphics.setColor(1, 1, 1, kk); love.graphics.circle("fill", px, py, r * 0.14)
      elseif id == "ember" then
        love.graphics.setColor(1, 0.6, 0.2, 0.7 * kk); love.graphics.circle("fill", px, py, r * 0.22)
        love.graphics.setColor(1, 1, 0.5, kk); love.graphics.circle("fill", px, py, r * 0.10)
      elseif id == "ghost" then
        love.graphics.setColor(0.9, 0.95, 1.0, 0.55 * kk); love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", px - r*0.2, py - r*0.2, r*0.4, r*0.4, 4, 4)
        love.graphics.setLineWidth(1)
      elseif id == "matrix" then
        love.graphics.setColor(0.2, 1.0, 0.45, 0.85 * kk)
        love.graphics.rectangle("fill", px - 1.5, py - r*0.35, 3, r*0.7)
      elseif id == "stardust" then
        love.graphics.setColor(1, 1, 0.85, 0.85 * kk)
        love.graphics.polygon("fill", starPoly(px, py, 4, r*0.30, r*0.10, 0))
      elseif id == "vapor" then
        love.graphics.setColor(0.85, 0.90, 1.0, 0.30 * kk)
        love.graphics.circle("fill", px, py, r * 0.40)
      elseif id == "bolt" then
        love.graphics.setColor(0.85, 0.95, 1.0, kk); love.graphics.setLineWidth(2)
        love.graphics.line(px - r*0.3, py, px - r*0.1, py - r*0.18, px + r*0.1, py + r*0.18, px + r*0.3, py)
        love.graphics.setLineWidth(1)
      elseif id == "confetti" then
        local cols = {{1,0.4,0.5},{1,0.85,0.4},{0.5,1,0.6},{0.4,0.9,1}}
        local c = cols[((math.floor(px) % 4) + 1)]
        love.graphics.setColor(c[1], c[2], c[3], 0.95 * kk)
        love.graphics.rectangle("fill", px - r*0.18, py - r*0.10, r*0.36, r*0.20)
      elseif id == "pixel" then
        love.graphics.setColor(ax, ay, az, kk)
        love.graphics.rectangle("fill", math.floor(px - r*0.20), math.floor(py - r*0.20), r*0.40, r*0.40)
      elseif id == "snow" then
        love.graphics.setColor(1, 1, 1, kk); love.graphics.circle("fill", px, py, r * 0.12)
        for j = 0, 5 do
          local a = j * math.pi / 3
          love.graphics.line(px, py, px + math.cos(a) * r * 0.22, py + math.sin(a) * r * 0.22)
        end
      elseif id == "plasma" then
        love.graphics.setColor(0.55, 0.85, 1.0, 0.55 * kk)
        love.graphics.circle("fill", px, py, r * 0.30)
        love.graphics.setColor(1, 1, 1, kk); love.graphics.circle("fill", px, py, r * 0.10)
      elseif id == "petal" then
        love.graphics.setColor(1.0, 0.55, 0.85, 0.85 * kk)
        love.graphics.ellipse("fill", px, py, r * 0.30, r * 0.13)
      elseif id == "aurora" then
        love.graphics.setColor(0.55, 1, 0.80, 0.55 * kk); love.graphics.setLineWidth(3)
        love.graphics.line(px - r*0.30, py + r*0.05, px + r*0.30, py - r*0.05)
        love.graphics.setLineWidth(1)
      elseif id == "solar" then
        love.graphics.setColor(1, 0.85, 0.30, 0.55 * kk)
        love.graphics.circle("fill", px, py, r * 0.36)
        love.graphics.setColor(1, 1, 0.6, kk); love.graphics.circle("fill", px, py, r * 0.16)
      elseif id == "void" then
        love.graphics.setColor(0, 0, 0, 0.85 * kk); love.graphics.circle("fill", px, py, r * 0.30)
        love.graphics.setColor(0.55, 0.40, 1.0, kk); love.graphics.circle("line", px, py, r * 0.30)
      else  -- glint
        love.graphics.setColor(ax, ay, az, 0.40 * kk)
        love.graphics.rectangle("fill", px - r*0.20, py - r*0.20, r*0.40, r*0.40, r*0.10, r*0.10)
        love.graphics.setColor(1, 1, 1, kk)
        love.graphics.rectangle("fill", px - r*0.10, py - r*0.10, r*0.20, r*0.20, r*0.05, r*0.05)
      end
    end
    -- four particles, alpha fades from front to back
    for i = 0, 3 do
      particle(cx + (i - 1.5) * r * 0.45, cy, 1 - i * 0.20)
    end
  end
end

return M
