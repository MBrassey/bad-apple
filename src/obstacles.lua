-- JSAB-style obstacles. All accept a beat-time spawn and self-update on song time.
-- Each obstacle exposes:
--   :update(dt, t)           -> updates state
--   :draw(accent)            -> renders
--   :hits(px, py, pr)        -> returns true if circle (px,py,pr) collides with hot zone
--   :alive()                 -> false to remove
local M = {}
M.list = {}

local function clamp(v, lo, hi) if v<lo then return lo end if v>hi then return hi end return v end
local function lerp(a, b, k) return a + (b - a) * k end

-- Add an obstacle to the live pool.
function M.add(o) table.insert(M.list, o); return o end

function M.reset() M.list = {} end

function M.updateAll(dt, t)
  for i = #M.list, 1, -1 do
    local o = M.list[i]
    o:update(dt, t)
    if not o:alive() then table.remove(M.list, i) end
  end
end

function M.drawAll(accent)
  for _, o in ipairs(M.list) do o:draw(accent) end
end

function M.checkHit(px, py, pr)
  for _, o in ipairs(M.list) do
    if o:hits(px, py, pr) then return o end
  end
  return nil
end

----------------------------------------------------------------------
-- Bullet: warning telegraph then a fast straight projectile.
----------------------------------------------------------------------
local Bullet = {}
Bullet.__index = Bullet

function M.bullet(opts)
  local o = setmetatable({}, Bullet)
  o.x, o.y = opts.x, opts.y
  o.dx, o.dy = opts.dx, opts.dy
  o.speed = opts.speed or 900
  o.r = opts.r or 14
  o.fire_t = opts.fire_t or 0.45
  o.life   = opts.life or 4.0
  o.elapsed = 0
  o.warn_len = opts.warn_len or 1800
  return M.add(o)
end

function Bullet:update(dt, t)
  self.elapsed = self.elapsed + dt
  if self.elapsed > self.fire_t then
    self.x = self.x + self.dx * self.speed * dt
    self.y = self.y + self.dy * self.speed * dt
  end
end

function Bullet:draw(accent)
  if self.elapsed < self.fire_t then
    local k = self.elapsed / self.fire_t
    local pulse = 0.4 + 0.5 * math.abs(math.sin(self.elapsed * 16))
    love.graphics.setColor(accent[1], accent[2], accent[3], 0.25 * pulse)
    love.graphics.setLineWidth(2 + 2 * k)
    love.graphics.line(self.x, self.y, self.x + self.dx * self.warn_len, self.y + self.dy * self.warn_len)
    love.graphics.setColor(1, 0.55, 0.85, 0.9 * pulse)
    love.graphics.circle("line", self.x, self.y, self.r * (0.5 + 0.5 * k))
  else
    -- bullet body w/ glow
    for i = 4, 1, -1 do
      love.graphics.setColor(1, 0.4, 0.7, 0.10)
      love.graphics.circle("fill", self.x, self.y, self.r + i * 4)
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("fill", self.x, self.y, self.r)
  end
end

function Bullet:hits(px, py, pr)
  if self.elapsed < self.fire_t then return false end
  local dx, dy = px - self.x, py - self.y
  return dx*dx + dy*dy < (self.r + pr) * (self.r + pr)
end

function Bullet:alive()
  if self.elapsed > self.life then return false end
  return self.x > -200 and self.x < 2120 and self.y > -200 and self.y < 1280
end

----------------------------------------------------------------------
-- Burst: ring of bullets fired outward from a point.
----------------------------------------------------------------------
function M.burst(opts)
  local n = opts.count or 12
  local angle0 = opts.angle or 0
  for i = 0, n-1 do
    local a = angle0 + i * (math.pi * 2 / n)
    M.bullet({
      x = opts.x, y = opts.y,
      dx = math.cos(a), dy = math.sin(a),
      speed = opts.speed or 700,
      r = opts.r or 11,
      fire_t = opts.fire_t or 0.35,
      life = opts.life or 3.5,
    })
  end
end

----------------------------------------------------------------------
-- Beam: telegraphed laser beam across screen, fires for fire_t seconds.
----------------------------------------------------------------------
local Beam = {}
Beam.__index = Beam

function M.beam(opts)
  local o = setmetatable({}, Beam)
  o.ax, o.ay = opts.ax, opts.ay
  o.bx, o.by = opts.bx, opts.by
  o.warn   = opts.warn or 0.7
  o.fire   = opts.fire or 0.35
  o.thick  = opts.thick or 28
  o.elapsed = 0
  return M.add(o)
end

function Beam:update(dt, t) self.elapsed = self.elapsed + dt end

function Beam:draw(accent)
  local e, w, f = self.elapsed, self.warn, self.fire
  if e < w then
    local k = e / w
    local pulse = 0.5 + 0.5 * math.abs(math.sin(e * 22))
    love.graphics.setColor(accent[1], accent[2], accent[3], 0.18 * pulse)
    love.graphics.setLineWidth(2)
    love.graphics.line(self.ax, self.ay, self.bx, self.by)
    love.graphics.setColor(1, 0.4, 0.7, 0.35 * pulse)
    love.graphics.setLineWidth(self.thick * 0.25 * k)
    love.graphics.line(self.ax, self.ay, self.bx, self.by)
  elseif e < w + f then
    local k = 1 - (e - w) / f
    for i = 5, 1, -1 do
      love.graphics.setColor(1, 0.55, 0.85, 0.18 * k)
      love.graphics.setLineWidth(self.thick * (0.6 + i * 0.4) * k)
      love.graphics.line(self.ax, self.ay, self.bx, self.by)
    end
    love.graphics.setColor(1, 1, 1, k)
    love.graphics.setLineWidth(self.thick * 0.35 * k)
    love.graphics.line(self.ax, self.ay, self.bx, self.by)
  end
  love.graphics.setLineWidth(1)
end

local function pointSegDist2(px, py, ax, ay, bx, by)
  local vx, vy = bx - ax, by - ay
  local wx, wy = px - ax, py - ay
  local d = vx*vx + vy*vy
  if d < 1e-6 then return wx*wx + wy*wy end
  local k = (wx*vx + wy*vy) / d
  if k < 0 then k = 0 end
  if k > 1 then k = 1 end
  local cx, cy = ax + vx*k, ay + vy*k
  local dx, dy = px - cx, py - cy
  return dx*dx + dy*dy
end

function Beam:hits(px, py, pr)
  local e, w, f = self.elapsed, self.warn, self.fire
  if e < w or e > w + f then return false end
  local d2 = pointSegDist2(px, py, self.ax, self.ay, self.bx, self.by)
  local r = self.thick * 0.5 + pr
  return d2 < r * r
end

function Beam:alive() return self.elapsed < self.warn + self.fire end

----------------------------------------------------------------------
-- Wave: moving wall with a gap. Slides across screen at fixed speed.
----------------------------------------------------------------------
local Wave = {}
Wave.__index = Wave

function M.wave(opts)
  local o = setmetatable({}, Wave)
  o.dir = opts.dir or "right"               -- left|right|up|down
  o.thick = opts.thick or 60
  o.gap_y = opts.gap_y or 540
  o.gap_h = opts.gap_h or 240
  o.speed = opts.speed or 700
  o.x = (o.dir == "right") and -o.thick or 1920
  o.y = (o.dir == "down")  and -o.thick or 1080
  o.warn = opts.warn or 0.4
  o.elapsed = 0
  o.dead = false
  return M.add(o)
end

function Wave:update(dt, t)
  self.elapsed = self.elapsed + dt
  if self.elapsed < self.warn then return end
  if self.dir == "right" then
    self.x = self.x + self.speed * dt
    if self.x > 1920 then self.dead = true end
  elseif self.dir == "left" then
    self.x = self.x - self.speed * dt
    if self.x < -self.thick - 10 then self.dead = true end
  elseif self.dir == "down" then
    self.y = self.y + self.speed * dt
    if self.y > 1080 then self.dead = true end
  elseif self.dir == "up" then
    self.y = self.y - self.speed * dt
    if self.y < -self.thick - 10 then self.dead = true end
  end
end

function Wave:draw(accent)
  if self.elapsed < self.warn then
    local pulse = 0.4 + 0.6 * math.abs(math.sin(self.elapsed * 22))
    if self.dir == "right" or self.dir == "left" then
      love.graphics.setColor(1, 0.4, 0.7, 0.22 * pulse)
      love.graphics.rectangle("fill", 0, 0, 1920, self.gap_y - self.gap_h*0.5)
      love.graphics.rectangle("fill", 0, self.gap_y + self.gap_h*0.5, 1920, 1080 - (self.gap_y + self.gap_h*0.5))
    else
      love.graphics.setColor(1, 0.4, 0.7, 0.22 * pulse)
      love.graphics.rectangle("fill", 0, 0, self.gap_y - self.gap_h*0.5, 1080)
      love.graphics.rectangle("fill", self.gap_y + self.gap_h*0.5, 0, 1920 - (self.gap_y + self.gap_h*0.5), 1080)
    end
    return
  end

  if self.dir == "right" or self.dir == "left" then
    local x = self.x
    -- top piece
    for g = 5,1,-1 do
      love.graphics.setColor(1, 0.45, 0.75, 0.10)
      love.graphics.rectangle("fill", x - g*3, -10, self.thick + g*6, self.gap_y - self.gap_h*0.5 + 10)
      love.graphics.rectangle("fill", x - g*3, self.gap_y + self.gap_h*0.5, self.thick + g*6, 1080 - (self.gap_y + self.gap_h*0.5) + 10)
    end
    love.graphics.setColor(1,1,1,1)
    love.graphics.rectangle("fill", x, 0, self.thick, self.gap_y - self.gap_h*0.5)
    love.graphics.rectangle("fill", x, self.gap_y + self.gap_h*0.5, self.thick, 1080 - (self.gap_y + self.gap_h*0.5))
  else
    local y = self.y
    for g = 5,1,-1 do
      love.graphics.setColor(1, 0.45, 0.75, 0.10)
      love.graphics.rectangle("fill", -10, y - g*3, self.gap_y - self.gap_h*0.5 + 10, self.thick + g*6)
      love.graphics.rectangle("fill", self.gap_y + self.gap_h*0.5, y - g*3, 1920 - (self.gap_y + self.gap_h*0.5) + 10, self.thick + g*6)
    end
    love.graphics.setColor(1,1,1,1)
    love.graphics.rectangle("fill", 0, y, self.gap_y - self.gap_h*0.5, self.thick)
    love.graphics.rectangle("fill", self.gap_y + self.gap_h*0.5, y, 1920 - (self.gap_y + self.gap_h*0.5), self.thick)
  end
end

local function rectHits(px, py, pr, x, y, w, h)
  local cx = clamp(px, x, x+w)
  local cy = clamp(py, y, y+h)
  local dx, dy = px - cx, py - cy
  return dx*dx + dy*dy < pr*pr
end

function Wave:hits(px, py, pr)
  if self.elapsed < self.warn then return false end
  if self.dir == "right" or self.dir == "left" then
    if rectHits(px, py, pr, self.x, 0, self.thick, self.gap_y - self.gap_h*0.5) then return true end
    if rectHits(px, py, pr, self.x, self.gap_y + self.gap_h*0.5, self.thick, 1080 - (self.gap_y + self.gap_h*0.5)) then return true end
  else
    if rectHits(px, py, pr, 0, self.y, self.gap_y - self.gap_h*0.5, self.thick) then return true end
    if rectHits(px, py, pr, self.gap_y + self.gap_h*0.5, self.y, 1920 - (self.gap_y + self.gap_h*0.5), self.thick) then return true end
  end
  return false
end

function Wave:alive() return not self.dead end

----------------------------------------------------------------------
-- Ring: expanding circle from a point. Hits on outer band.
----------------------------------------------------------------------
local Ring = {}
Ring.__index = Ring

function M.ring(opts)
  local o = setmetatable({}, Ring)
  o.x, o.y = opts.x, opts.y
  o.r = 0
  o.maxr = opts.maxr or 700
  o.speed = opts.speed or 720
  o.thick = opts.thick or 18
  o.warn = opts.warn or 0.25
  o.elapsed = 0
  return M.add(o)
end

function Ring:update(dt, t)
  self.elapsed = self.elapsed + dt
  if self.elapsed >= self.warn then
    self.r = self.r + self.speed * dt
  end
end

function Ring:draw(accent)
  if self.elapsed < self.warn then
    local k = self.elapsed / self.warn
    local pulse = 0.4 + 0.6 * math.abs(math.sin(self.elapsed * 28))
    love.graphics.setColor(accent[1], accent[2], accent[3], 0.5 * pulse)
    love.graphics.setLineWidth(2 + 4 * k)
    love.graphics.circle("line", self.x, self.y, 18 + 80 * k)
    return
  end
  for i = 5, 1, -1 do
    love.graphics.setColor(1, 0.4, 0.75, 0.09)
    love.graphics.setLineWidth(self.thick + i * 6)
    love.graphics.circle("line", self.x, self.y, self.r)
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setLineWidth(self.thick)
  love.graphics.circle("line", self.x, self.y, self.r)
  love.graphics.setLineWidth(1)
end

function Ring:hits(px, py, pr)
  if self.elapsed < self.warn then return false end
  local dx, dy = px - self.x, py - self.y
  local d = math.sqrt(dx*dx + dy*dy)
  return math.abs(d - self.r) < self.thick * 0.5 + pr
end

function Ring:alive() return self.r < self.maxr end

----------------------------------------------------------------------
-- Chaser: slow homing orb that chases the player.
----------------------------------------------------------------------
local Chaser = {}
Chaser.__index = Chaser

function M.chaser(opts)
  local o = setmetatable({}, Chaser)
  o.x, o.y = opts.x, opts.y
  o.r = opts.r or 18
  o.speed = opts.speed or 220
  o.life = opts.life or 8
  o.elapsed = 0
  o.target = opts.target          -- {x,y} read each frame
  return M.add(o)
end

function Chaser:update(dt, t)
  self.elapsed = self.elapsed + dt
  local tx, ty = self.target.x, self.target.y
  local dx, dy = tx - self.x, ty - self.y
  local d = math.sqrt(dx*dx + dy*dy)
  if d > 0.01 then
    self.x = self.x + (dx/d) * self.speed * dt
    self.y = self.y + (dy/d) * self.speed * dt
  end
end

function Chaser:draw(accent)
  for i = 6, 1, -1 do
    love.graphics.setColor(1, 0.4, 0.7, 0.07)
    love.graphics.circle("fill", self.x, self.y, self.r + i * 6)
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.circle("fill", self.x, self.y, self.r)
  love.graphics.setColor(0.9, 0.3, 0.6, 1)
  love.graphics.circle("line", self.x, self.y, self.r + 2)
end

function Chaser:hits(px, py, pr)
  local dx, dy = px - self.x, py - self.y
  return dx*dx + dy*dy < (self.r + pr) * (self.r + pr)
end

function Chaser:alive() return self.elapsed < self.life end

----------------------------------------------------------------------
-- Spinner: rotating crossed beams around a pivot.
----------------------------------------------------------------------
local Spinner = {}
Spinner.__index = Spinner

function M.spinner(opts)
  local o = setmetatable({}, Spinner)
  o.x, o.y = opts.x, opts.y
  o.angle = opts.angle or 0
  o.spin = opts.spin or 1.6
  o.length = opts.length or 600
  o.thick  = opts.thick or 22
  o.arms = opts.arms or 2
  o.life = opts.life or 3.0
  o.warn = opts.warn or 0.4
  o.elapsed = 0
  return M.add(o)
end

function Spinner:update(dt, t)
  self.elapsed = self.elapsed + dt
  if self.elapsed >= self.warn then
    self.angle = self.angle + self.spin * dt
  end
end

function Spinner:draw(accent)
  local x, y = self.x, self.y
  local L = self.length
  local active = self.elapsed >= self.warn
  if not active then
    local k = self.elapsed / self.warn
    love.graphics.setColor(accent[1], accent[2], accent[3], 0.35 * (0.5 + 0.5 * math.sin(self.elapsed*22)))
    love.graphics.setLineWidth(2 + 6 * k)
    for i = 0, self.arms - 1 do
      local a = self.angle + (math.pi / self.arms) * i
      love.graphics.line(x - math.cos(a)*L, y - math.sin(a)*L, x + math.cos(a)*L, y + math.sin(a)*L)
    end
    love.graphics.setLineWidth(1)
    return
  end
  for i = 0, self.arms - 1 do
    local a = self.angle + (math.pi / self.arms) * i
    local x2, y2 = x + math.cos(a)*L, y + math.sin(a)*L
    local x1, y1 = x - math.cos(a)*L, y - math.sin(a)*L
    for g = 5, 1, -1 do
      love.graphics.setColor(1, 0.4, 0.7, 0.10)
      love.graphics.setLineWidth(self.thick + g * 6)
      love.graphics.line(x1, y1, x2, y2)
    end
    love.graphics.setColor(1,1,1,1)
    love.graphics.setLineWidth(self.thick)
    love.graphics.line(x1, y1, x2, y2)
  end
  love.graphics.setLineWidth(1)
end

function Spinner:hits(px, py, pr)
  if self.elapsed < self.warn then return false end
  local x, y = self.x, self.y
  local L = self.length
  for i = 0, self.arms - 1 do
    local a = self.angle + (math.pi / self.arms) * i
    local x2, y2 = x + math.cos(a)*L, y + math.sin(a)*L
    local x1, y1 = x - math.cos(a)*L, y - math.sin(a)*L
    local d2 = pointSegDist2(px, py, x1, y1, x2, y2)
    local r = self.thick * 0.5 + pr
    if d2 < r * r then return true end
  end
  return false
end

function Spinner:alive() return self.elapsed < self.warn + self.life end

return M
