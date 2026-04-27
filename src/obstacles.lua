-- Just-Shapes-and-Beats-style obstacles. Every obstacle has three layers:
--
--   1) decorative outer glow halos (low alpha, large) -- never hurts
--   2) crisp glowing border ring -- the visible hot-zone edge
--   3) filled rounded core -- the actual collision area
--
-- Hit detection always matches the *core* size, so you only ever take damage
-- by touching what looks like a solid colored shape. The glow is candy.
local M = {}
M.list = {}

local function clamp(v, lo, hi) if v<lo then return lo end if v>hi then return hi end return v end
local function lerp(a, b, k) return a + (b - a) * k end

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
-- Bullet: telegraph with a faint trail line, then a glowing rounded
-- projectile. Hit is the visible coloured disk, NOT the soft glow.
----------------------------------------------------------------------
local Bullet = {}
Bullet.__index = Bullet

function M.bullet(opts)
  local o = setmetatable({}, Bullet)
  o.x, o.y = opts.x, opts.y
  o.dx, o.dy = opts.dx, opts.dy
  o.speed = opts.speed or 700
  o.r = opts.r or 14            -- this IS the collision radius
  o.fire_t = opts.fire_t or 0.50
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
  local cr, cg, cb = accent[1], accent[2], accent[3]
  if self.elapsed < self.fire_t then
    local k = self.elapsed / self.fire_t
    local pulse = 0.45 + 0.55 * math.abs(math.sin(self.elapsed * 14))
    -- trail telegraph
    love.graphics.setColor(cr, cg, cb, 0.20 * pulse)
    love.graphics.setLineWidth(2 + 4 * k)
    love.graphics.line(self.x, self.y, self.x + self.dx * self.warn_len, self.y + self.dy * self.warn_len)
    -- expanding outline ring previewing the bullet's footprint
    love.graphics.setColor(1, 1, 1, 0.55 * pulse)
    love.graphics.setLineWidth(2 + 2 * k)
    love.graphics.circle("line", self.x, self.y, self.r * (0.4 + 0.7 * k))
    love.graphics.setLineWidth(1)
  else
    -- soft outer glow (decorative)
    for i = 6, 1, -1 do
      love.graphics.setColor(cr, cg, cb, 0.07)
      love.graphics.circle("fill", self.x, self.y, self.r + i * 5)
    end
    -- bright glowing border (the visible hot-zone edge)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", self.x, self.y, self.r)
    -- filled core (the hit zone itself)
    love.graphics.setColor(cr, cg, cb, 0.95)
    love.graphics.circle("fill", self.x, self.y, self.r - 2)
    love.graphics.setLineWidth(1)
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
-- Burst: ring of bullets fired outward from a focal point.
----------------------------------------------------------------------
function M.burst(opts)
  local n = opts.count or 10
  local angle0 = opts.angle or 0
  for i = 0, n-1 do
    local a = angle0 + i * (math.pi * 2 / n)
    M.bullet({
      x = opts.x, y = opts.y,
      dx = math.cos(a), dy = math.sin(a),
      speed = opts.speed or 480,
      r = opts.r or 11,
      fire_t = opts.fire_t or 0.50,
      life = opts.life or 4.0,
    })
  end
end

----------------------------------------------------------------------
-- Beam: rounded-end laser. Telegraph is a thin pulsing line; fire is a
-- thick rounded capsule with bright border. Hit detection uses the
-- visible thickness exactly.
----------------------------------------------------------------------
local Beam = {}
Beam.__index = Beam

function M.beam(opts)
  local o = setmetatable({}, Beam)
  o.ax, o.ay = opts.ax, opts.ay
  o.bx, o.by = opts.bx, opts.by
  o.warn   = opts.warn or 0.55
  o.fire   = opts.fire or 0.30
  o.thick  = opts.thick or 26
  o.elapsed = 0
  return M.add(o)
end

function Beam:update(dt, t) self.elapsed = self.elapsed + dt end

local function drawCapsule(ax, ay, bx, by, thick)
  local dx, dy = bx - ax, by - ay
  local len = math.sqrt(dx*dx + dy*dy)
  if len < 1 then return end
  love.graphics.push()
  love.graphics.translate(ax, ay)
  love.graphics.rotate(math.atan2(dy, dx))
  love.graphics.rectangle("fill", 0, -thick * 0.5, len, thick, thick * 0.5, thick * 0.5)
  love.graphics.pop()
end

function Beam:draw(accent)
  local cr, cg, cb = accent[1], accent[2], accent[3]
  local e, w, f = self.elapsed, self.warn, self.fire
  if e < w then
    local k = e / w
    local pulse = 0.4 + 0.6 * math.abs(math.sin(e * 18))
    -- thin guideline
    love.graphics.setColor(cr, cg, cb, 0.30 * pulse)
    love.graphics.setLineWidth(2 + 4 * k)
    love.graphics.line(self.ax, self.ay, self.bx, self.by)
    -- preview capsule growing toward fire thickness
    love.graphics.setColor(cr, cg, cb, 0.18 * pulse)
    drawCapsule(self.ax, self.ay, self.bx, self.by, self.thick * 0.55 * k)
    love.graphics.setLineWidth(1)
  elseif e < w + f then
    local k = 1 - (e - w) / f
    -- decorative outer glow capsule
    love.graphics.setColor(cr, cg, cb, 0.18 * k)
    drawCapsule(self.ax, self.ay, self.bx, self.by, self.thick * 1.8)
    love.graphics.setColor(cr, cg, cb, 0.30 * k)
    drawCapsule(self.ax, self.ay, self.bx, self.by, self.thick * 1.3)
    -- hot capsule
    love.graphics.setColor(cr, cg, cb, k)
    drawCapsule(self.ax, self.ay, self.bx, self.by, self.thick)
    -- white core
    love.graphics.setColor(1, 1, 1, k)
    drawCapsule(self.ax, self.ay, self.bx, self.by, self.thick * 0.45)
  end
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
-- Wave: rounded slab with a gap. Slow, friendly, well-telegraphed.
----------------------------------------------------------------------
local Wave = {}
Wave.__index = Wave

function M.wave(opts)
  local o = setmetatable({}, Wave)
  o.dir = opts.dir or "right"
  o.thick = opts.thick or 56
  o.gap_y = opts.gap_y or 540
  o.gap_h = opts.gap_h or 360
  o.speed = opts.speed or 460
  o.x = (o.dir == "right") and -o.thick or 1920
  o.y = (o.dir == "down")  and -o.thick or 1080
  o.warn = opts.warn or 0.55
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

local function drawRoundedSlab(x, y, w, h, accent, alpha, glow)
  local cr, cg, cb = accent[1], accent[2], accent[3]
  local rad = math.min(w, h) * 0.30
  -- decorative outer glow
  if glow then
    for i = 5, 1, -1 do
      love.graphics.setColor(cr, cg, cb, 0.06 * alpha)
      love.graphics.rectangle("fill", x - i * 4, y - i * 4, w + i * 8, h + i * 8,
                              rad + i * 3, rad + i * 3)
    end
  end
  -- bright border
  love.graphics.setColor(1, 1, 1, alpha)
  love.graphics.setLineWidth(3)
  love.graphics.rectangle("line", x, y, w, h, rad, rad)
  love.graphics.setLineWidth(1)
  -- filled core
  love.graphics.setColor(cr, cg, cb, 0.92 * alpha)
  love.graphics.rectangle("fill", x + 2, y + 2, w - 4, h - 4, rad - 1, rad - 1)
end

function Wave:draw(accent)
  if self.elapsed < self.warn then
    local pulse = 0.45 + 0.55 * math.abs(math.sin(self.elapsed * 18))
    love.graphics.setColor(accent[1], accent[2], accent[3], 0.18 * pulse)
    if self.dir == "right" or self.dir == "left" then
      love.graphics.rectangle("fill", 0, 0, 1920, self.gap_y - self.gap_h*0.5, 16, 16)
      love.graphics.rectangle("fill", 0, self.gap_y + self.gap_h*0.5, 1920,
                              1080 - (self.gap_y + self.gap_h*0.5), 16, 16)
    else
      love.graphics.rectangle("fill", 0, 0, self.gap_y - self.gap_h*0.5, 1080, 16, 16)
      love.graphics.rectangle("fill", self.gap_y + self.gap_h*0.5, 0,
                              1920 - (self.gap_y + self.gap_h*0.5), 1080, 16, 16)
    end
    return
  end

  if self.dir == "right" or self.dir == "left" then
    local x = self.x
    local topH = self.gap_y - self.gap_h*0.5
    local botY = self.gap_y + self.gap_h*0.5
    drawRoundedSlab(x, 0,    self.thick, topH,            accent, 1.0, true)
    drawRoundedSlab(x, botY, self.thick, 1080 - botY,     accent, 1.0, true)
  else
    local y = self.y
    local leftW = self.gap_y - self.gap_h*0.5
    local rightX = self.gap_y + self.gap_h*0.5
    drawRoundedSlab(0,      y, leftW,        self.thick, accent, 1.0, true)
    drawRoundedSlab(rightX, y, 1920 - rightX, self.thick, accent, 1.0, true)
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
-- Ring: expanding hollow circle. Hit zone is the bright band only.
----------------------------------------------------------------------
local Ring = {}
Ring.__index = Ring

function M.ring(opts)
  local o = setmetatable({}, Ring)
  o.x, o.y = opts.x, opts.y
  o.r = 0
  o.maxr = opts.maxr or 800
  o.speed = opts.speed or 380
  o.thick = opts.thick or 16
  o.warn = opts.warn or 0.50
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
  local cr, cg, cb = accent[1], accent[2], accent[3]
  if self.elapsed < self.warn then
    local k = self.elapsed / self.warn
    local pulse = 0.4 + 0.6 * math.abs(math.sin(self.elapsed * 24))
    love.graphics.setColor(cr, cg, cb, 0.55 * pulse)
    love.graphics.setLineWidth(2 + 5 * k)
    love.graphics.circle("line", self.x, self.y, 16 + 90 * k)
    love.graphics.setLineWidth(1)
    return
  end
  -- soft outer glow band
  for i = 5, 1, -1 do
    love.graphics.setColor(cr, cg, cb, 0.07)
    love.graphics.setLineWidth(self.thick + i * 6)
    love.graphics.circle("line", self.x, self.y, self.r)
  end
  -- bright outer + inner border
  love.graphics.setColor(1, 1, 1, 0.95)
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", self.x, self.y, self.r + self.thick * 0.5)
  love.graphics.circle("line", self.x, self.y, self.r - self.thick * 0.5)
  -- coloured band (hit zone)
  love.graphics.setColor(cr, cg, cb, 0.92)
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
-- Chaser: rounded orb that slowly homes after a 0.6 s ghost preview.
----------------------------------------------------------------------
local Chaser = {}
Chaser.__index = Chaser

function M.chaser(opts)
  local o = setmetatable({}, Chaser)
  o.x, o.y = opts.x, opts.y
  o.r = opts.r or 18
  o.speed = opts.speed or 130
  o.life = opts.life or 7
  o.warn = opts.warn or 0.60
  o.elapsed = 0
  o.target = opts.target
  return M.add(o)
end

function Chaser:update(dt, t)
  self.elapsed = self.elapsed + dt
  if self.elapsed < self.warn then return end
  local tx, ty = self.target.x, self.target.y
  local dx, dy = tx - self.x, ty - self.y
  local d = math.sqrt(dx*dx + dy*dy)
  if d > 0.01 then
    self.x = self.x + (dx/d) * self.speed * dt
    self.y = self.y + (dy/d) * self.speed * dt
  end
end

function Chaser:draw(accent)
  local cr, cg, cb = accent[1], accent[2], accent[3]
  if self.elapsed < self.warn then
    local k = self.elapsed / self.warn
    local pulse = 0.4 + 0.6 * math.abs(math.sin(self.elapsed * 22))
    love.graphics.setColor(cr, cg, cb, 0.45 * pulse)
    love.graphics.setLineWidth(2 + 4 * k)
    love.graphics.circle("line", self.x, self.y, self.r + 18 - 14 * k)
    love.graphics.setColor(cr, cg, cb, 0.18 * pulse)
    love.graphics.circle("fill", self.x, self.y, self.r * 0.65)
    love.graphics.setLineWidth(1)
    return
  end
  -- soft outer glow
  for i = 5, 1, -1 do
    love.graphics.setColor(cr, cg, cb, 0.07)
    love.graphics.circle("fill", self.x, self.y, self.r + i * 5)
  end
  -- bright glowing border
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setLineWidth(3)
  love.graphics.circle("line", self.x, self.y, self.r)
  -- coloured core
  love.graphics.setColor(cr, cg, cb, 0.95)
  love.graphics.circle("fill", self.x, self.y, self.r - 2)
  love.graphics.setLineWidth(1)
end

function Chaser:hits(px, py, pr)
  if self.elapsed < self.warn then return false end
  local dx, dy = px - self.x, py - self.y
  return dx*dx + dy*dy < (self.r + pr) * (self.r + pr)
end

function Chaser:alive() return self.elapsed < self.life end

----------------------------------------------------------------------
-- Spinner: slowly rotating capped beams from a pivot.
----------------------------------------------------------------------
local Spinner = {}
Spinner.__index = Spinner

function M.spinner(opts)
  local o = setmetatable({}, Spinner)
  o.x, o.y = opts.x, opts.y
  o.angle = opts.angle or 0
  o.spin = opts.spin or 0.9
  o.length = opts.length or 580
  o.thick  = opts.thick or 22
  o.arms = opts.arms or 2
  o.life = opts.life or 2.6
  o.warn = opts.warn or 0.55
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
  local cr, cg, cb = accent[1], accent[2], accent[3]
  local x, y, L, thk = self.x, self.y, self.length, self.thick
  local active = self.elapsed >= self.warn
  if not active then
    local k = self.elapsed / self.warn
    love.graphics.setColor(cr, cg, cb, 0.45 * (0.5 + 0.5 * math.sin(self.elapsed*22)))
    love.graphics.setLineWidth(2 + 5 * k)
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
    -- soft outer glow
    love.graphics.setColor(cr, cg, cb, 0.10)
    drawCapsule(x1, y1, x2, y2, thk * 1.8)
    -- coloured capsule
    love.graphics.setColor(cr, cg, cb, 0.95)
    drawCapsule(x1, y1, x2, y2, thk)
    -- bright white core
    love.graphics.setColor(1, 1, 1, 0.95)
    drawCapsule(x1, y1, x2, y2, thk * 0.40)
  end
  -- pivot dot
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.circle("fill", x, y, 5)
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
