-- Glowy square. WASD/arrows to move, Shift/Space to dash.
local M = {}
M.__index = M

-- JSAB-tuned constants. Movement is snappy (high accel, no inertia carry on
-- release), dash is short and granted i-frames for its full duration plus a
-- short tail, and the cooldown is short enough to chain through dense waves.
local SPEED         = 580
local DASH_SPEED    = 2400
local DASH_TIME     = 0.22
local DASH_COOLDOWN = 0.36
local IFRAME_HIT    = 1.30        -- post-hit invuln (was 1.80 -- felt unkillable)
local IFRAME_DASH   = 0.40        -- DASH_TIME + comfortable tail
local DASH_BUFFER   = 0.18        -- queue dash if pressed during cooldown
local SIZE_MAX      = 40
local SIZE_MIN      = 18
local MAX_HP        = 8           -- eight chunks before death

function M.new(x, y, bounds)
  local p = setmetatable({}, M)
  p.x, p.y = x, y
  p.vx, p.vy = 0, 0
  p.bounds = bounds                            -- {x,y,w,h}
  p.dash_t = 0
  p.dash_cd = 0
  p.dash_dx, p.dash_dy = 0, 0
  p.iframes = 1.5
  p.hp = MAX_HP                                -- 4 -> body intact, 0 -> dead
  p.size = SIZE_MAX
  p.alive = true
  p.trail = {}
  p.trail_max = 22
  p.dashes = 0
  p.hits = 0
  p.flash_t = 0
  p.shards = {}                                -- chunks that fly off on hit
  p.angle = 0                                  -- visual rotation (spins on dash + hit)
  p.spin = 0
  p.death_t = 0
  p.dash_buffer = 0                            -- decays toward 0; >0 means a queued dash
  return p
end

local function targetSize(hp)
  if hp <= 0 then return 0 end
  -- linear shrink: hp4=36 hp3=30 hp2=24 hp1=18, then 0
  local k = hp / MAX_HP
  return SIZE_MIN + (SIZE_MAX - SIZE_MIN) * k
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function M:dashing()
  return self.dash_t > 0
end

function M:invincible()
  return self.iframes > 0 or self:dashing()
end

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
    -- queue the press; it will fire as soon as cooldown expires
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
  self.spin = (ix < 0 or iy < 0) and -22 or 22
  return true
end

function M:hit()
  if self:invincible() then return false end
  self.hp = self.hp - 1
  self.iframes = IFRAME_HIT
  self.hits = self.hits + 1
  self.flash_t = 0.28
  -- spawn shards: chunks of body break off and fly outward
  local n = 6 + love.math.random(0, 2)
  for i = 1, n do
    local a = love.math.random() * math.pi * 2
    local sp = 240 + love.math.random() * 380
    local sz = 4 + love.math.random() * 8
    table.insert(self.shards, {
      x = self.x + math.cos(a) * self.size * 0.4,
      y = self.y + math.sin(a) * self.size * 0.4,
      vx = math.cos(a) * sp,
      vy = math.sin(a) * sp,
      size = sz,
      rot = love.math.random() * math.pi * 2,
      drot = (love.math.random() - 0.5) * 18,
      life = 0.55 + love.math.random() * 0.35,
      age = 0,
    })
  end
  -- knockback in current input direction (or random)
  local kx, ky = self:input()
  if kx == 0 and ky == 0 then
    local a = love.math.random() * math.pi * 2
    kx, ky = math.cos(a), math.sin(a)
  end
  self.x = self.x - kx * 26
  self.y = self.y - ky * 26
  -- spin pulse
  self.spin = (love.math.random() < 0.5 and -1 or 1) * 14
  if self.hp <= 0 then
    self.alive = false
    self.death_t = 0
  end
  return true
end

-- Health getter for HUD compat -- behaves like prior `lives` field.
function M:livesLeft() return math.max(0, self.hp) end

function M:update(dt)
  -- visual decays always run (so death animation continues after alive=false)
  self.flash_t = math.max(0, self.flash_t - dt)
  self.spin = self.spin * math.max(0, 1 - dt * 6)
  self.angle = self.angle + self.spin * dt

  -- shards keep updating regardless of alive state
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

  -- size lerps toward target (shrinks as hp drops)
  local target = targetSize(self.hp)
  self.size = self.size + (target - self.size) * math.min(1, dt * 9)

  if not self.alive then
    self.death_t = self.death_t + dt
    return
  end

  self.dash_cd  = math.max(0, self.dash_cd - dt)
  self.dash_t   = math.max(0, self.dash_t  - dt)
  self.iframes  = math.max(0, self.iframes - dt)
  self.dash_buffer = math.max(0, self.dash_buffer - dt)
  -- consume buffered dash as soon as cooldown clears
  if self.dash_buffer > 0 and self.dash_cd <= 0 and self.dash_t <= 0 then
    self:tryDash()
  end

  -- snappy JSAB-like control: instant velocity, no inertia from previous frame.
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

  -- trail (denser when dashing)
  local seg_step = self:dashing() and 0.005 or 0.018
  table.insert(self.trail, 1, {x=self.x, y=self.y, t=0, dashing=self:dashing()})
  for i = #self.trail, 1, -1 do
    self.trail[i].t = self.trail[i].t + dt
    if self.trail[i].t > 0.50 or i > self.trail_max then
      table.remove(self.trail, i)
    end
  end
end

-- Reset to full HP at given position (used for the "IT'S NOT OVER" revive).
function M:revive(x, y)
  self.hp = MAX_HP
  self.size = SIZE_MAX
  self.alive = true
  self.death_t = 0
  self.shards = {}
  self.iframes = 2.0
  self.flash_t = 0
  self.dash_t = 0
  self.dash_cd = 0
  self.angle = 0
  self.spin = 0
  if x then self.x, self.y = x, y end
  self.trail = {}
end

local function drawRoundedSquare(cx, cy, sz, angle, fillR, fillG, fillB, fillA, cornerR)
  cornerR = cornerR or sz * 0.22
  love.graphics.push()
  love.graphics.translate(cx, cy)
  love.graphics.rotate(angle or 0)
  love.graphics.setColor(fillR, fillG, fillB, fillA)
  love.graphics.rectangle("fill", -sz*0.5, -sz*0.5, sz, sz, cornerR, cornerR)
  love.graphics.pop()
end

function M:draw(accent)
  local ax, ay, az = accent[1], accent[2], accent[3]
  -- trail glow (rounded squares with fading alpha)
  for i, p in ipairs(self.trail) do
    local k = 1 - (p.t / 0.50)
    if k > 0 then
      local s = self.size * (0.55 + 0.55 * k)
      local a = (p.dashing and 0.18 or 0.10) * k
      love.graphics.setColor(ax, ay, az, a)
      love.graphics.rectangle("fill", p.x - s*0.5, p.y - s*0.5, s, s, s*0.22, s*0.22)
    end
  end

  -- shards (always drawn so they survive into death state)
  for _, s in ipairs(self.shards) do
    local k = 1 - s.age / s.life
    if k > 0 then
      love.graphics.push()
      love.graphics.translate(s.x, s.y)
      love.graphics.rotate(s.rot)
      love.graphics.setColor(ax, ay, az, 0.22 * k)
      love.graphics.rectangle("fill", -s.size*1.2, -s.size*1.2, s.size*2.4, s.size*2.4, s.size*0.4, s.size*0.4)
      love.graphics.setColor(1, 1, 1, 0.95 * k)
      love.graphics.rectangle("fill", -s.size*0.5, -s.size*0.5, s.size, s.size, s.size*0.25, s.size*0.25)
      love.graphics.pop()
    end
  end

  if not self.alive then return end           -- body gone, only shards remain

  -- hit-flash whitens the player briefly
  local fx = self.flash_t / 0.28
  if fx < 0 then fx = 0 end
  local cr = ax + (1 - ax) * fx
  local cg = ay + (1 - ay) * fx
  local cb = az + (1 - az) * fx

  -- outer glow halos -- pulse with iframe blink
  local blink = 1
  if self.iframes > 0 and not self:dashing() then
    blink = (math.floor(love.timer.getTime() * 22) % 2 == 0) and 0.45 or 1.0
  end
  for i = 6, 1, -1 do
    local s = self.size + i * 16
    love.graphics.setColor(cr, cg, cb, 0.055 * blink)
    love.graphics.rectangle("fill", self.x - s*0.5, self.y - s*0.5, s, s, s*0.22, s*0.22)
  end

  -- accent ring (slightly larger, partial alpha)
  drawRoundedSquare(self.x, self.y, self.size + 8, self.angle, cr, cg, cb, 0.55 * blink, (self.size+8)*0.22)

  -- core body (rounded, accent-tinted)
  drawRoundedSquare(self.x, self.y, self.size, self.angle, cr, cg, cb, blink, self.size*0.22)

  -- bright outline ring so the player stays legible against the silhouette
  drawRoundedSquare(self.x, self.y, self.size + 4, self.angle, 1, 1, 1, 0.85 * blink, (self.size+4)*0.22)
  drawRoundedSquare(self.x, self.y, self.size,     self.angle, cr, cg, cb, blink,        self.size*0.22)

  -- inner white core, scaled by hp ratio
  local inner = self.size * (0.42 + 0.16 * (self.hp / MAX_HP))
  drawRoundedSquare(self.x, self.y, inner, self.angle, 1, 1, 1, blink, inner*0.28)
end

return M
