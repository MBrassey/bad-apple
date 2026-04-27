-- JSAB-style obstacles with high-illumination borders.
-- Three-layer language for every obstacle:
--   1) soft outer glow halos (large, low alpha, additive feel)
--   2) bright pulsing WHITE border ring -- the visible danger edge
--   3) filled rounded core in the accent colour -- the actual hit zone
-- Hit detection always matches the visible core (NOT the glow halo).
local M = {}
M.list = {}

local function clamp(v, lo, hi) if v<lo then return lo end if v>hi then return hi end return v end

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

-- Border breathing tied to song time so danger-edges pulse on beat.
-- Driver feeds in the current audio_t each frame via M.setBeatTime.
local _beat_t = 0
function M.setBeatTime(t) _beat_t = t or 0 end

local function bpulse(speed, base, amp)
  return base + amp * math.abs(math.sin(_beat_t * speed))
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

-- ─── Bullet ───────────────────────────────────────────────────────────
local Bullet = {}
Bullet.__index = Bullet

function M.bullet(opts)
  local o = setmetatable({}, Bullet)
  o.x, o.y = opts.x, opts.y
  o.dx, o.dy = opts.dx, opts.dy
  o.speed = opts.speed or 700
  o.r = opts.r or 14
  o.fire_t = opts.fire_t or 0.50
  o.life   = opts.life or 4.0
  o.elapsed = 0
  o.warn_len = opts.warn_len or 1800
  o.color = opts.color
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
  local c = self.color or accent
  local cr, cg, cb = c[1], c[2], c[3]
  if self.elapsed < self.fire_t then
    local k = self.elapsed / self.fire_t
    -- accelerating telegraph pulse: faster as fire approaches
    local pulse = 0.4 + 0.6 * math.abs(math.sin(self.elapsed * (10 + 18 * k)))
    -- faint dotted guideline -- a hint, NOT an obstacle. Was previously
    -- drawn as a solid pulsing line and players read it as a hot beam.
    love.graphics.setColor(cr, cg, cb, 0.07 * pulse)
    love.graphics.setLineWidth(1)
    local dash_len, gap_len = 8, 12
    local total = self.warn_len
    local d = 0
    while d < total do
      local x1 = self.x + self.dx * d
      local y1 = self.y + self.dy * d
      local d2 = math.min(d + dash_len, total)
      love.graphics.line(x1, y1, self.x + self.dx * d2, self.y + self.dy * d2)
      d = d + dash_len + gap_len
    end
    -- expanding outline ring previewing the bullet's actual footprint
    love.graphics.setColor(1, 1, 1, 0.75 * pulse)
    love.graphics.setLineWidth(2 + 3 * k)
    love.graphics.circle("line", self.x, self.y, self.r * (0.35 + 0.85 * k))
    love.graphics.setLineWidth(1)
  else
    -- hot bullet: layered glow + pulsing white border + accent core + sparkle
    -- soft outer glow (additive feel via stacked low-alpha)
    for i = 8, 1, -1 do
      love.graphics.setColor(cr, cg, cb, 0.06)
      love.graphics.circle("fill", self.x, self.y, self.r + i * 4)
    end
    -- pulsing illuminated border
    local b = bpulse(8, 0.85, 0.15)
    love.graphics.setColor(1, 1, 1, b)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", self.x, self.y, self.r + 1)
    -- accent fill (the hit zone)
    love.graphics.setColor(cr, cg, cb, 0.95)
    love.graphics.circle("fill", self.x, self.y, self.r - 1)
    -- white inner highlight
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.circle("fill", self.x, self.y, self.r * 0.45)
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

-- ─── Burst ─────────────────────────────────────────────────────────────
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
      color = opts.color,
    })
  end
end

-- ─── Beam ──────────────────────────────────────────────────────────────
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
  o.color = opts.color
  return M.add(o)
end

function Beam:update(dt, t) self.elapsed = self.elapsed + dt end

function Beam:draw(accent)
  local c = self.color or accent
  local cr, cg, cb = c[1], c[2], c[3]
  local e, w, f = self.elapsed, self.warn, self.fire
  if e < w then
    local k = e / w
    -- accelerating throb: starts subtle, slams in just before fire
    local pulse = 0.4 + 0.6 * math.abs(math.sin(e * (8 + 24 * k)))
    -- thin coloured rail through the path
    love.graphics.setColor(cr, cg, cb, 0.40 * pulse)
    love.graphics.setLineWidth(2 + 4 * k)
    love.graphics.line(self.ax, self.ay, self.bx, self.by)
    -- preview capsule expands to fire thickness as the warn elapses --
    -- you can see the impending beam swelling into shape
    love.graphics.setColor(cr, cg, cb, 0.30 * pulse * k)
    drawCapsule(self.ax, self.ay, self.bx, self.by, self.thick * (0.30 + 0.65 * k))
    -- bright white edge band that intensifies as fire nears, makes the
    -- final fraction of a second unmistakable
    love.graphics.setColor(1, 1, 1, 0.65 * pulse * k * k)
    love.graphics.setLineWidth(3)
    love.graphics.line(self.ax, self.ay, self.bx, self.by)
    love.graphics.setLineWidth(1)
  elseif e < w + f then
    local k = 1 - (e - w) / f
    -- decorative outer aura
    love.graphics.setColor(cr, cg, cb, 0.16 * k)
    drawCapsule(self.ax, self.ay, self.bx, self.by, self.thick * 2.0)
    love.graphics.setColor(cr, cg, cb, 0.30 * k)
    drawCapsule(self.ax, self.ay, self.bx, self.by, self.thick * 1.4)
    -- bright illuminated border (capsule slightly larger than core)
    love.graphics.setColor(1, 1, 1, k)
    drawCapsule(self.ax, self.ay, self.bx, self.by, self.thick + 6)
    -- accent hot core
    love.graphics.setColor(cr, cg, cb, 0.95 * k)
    drawCapsule(self.ax, self.ay, self.bx, self.by, self.thick)
    -- bright white centre line
    love.graphics.setColor(1, 1, 1, k)
    drawCapsule(self.ax, self.ay, self.bx, self.by, self.thick * 0.40)
  end
end

function Beam:hits(px, py, pr)
  local e, w, f = self.elapsed, self.warn, self.fire
  if e < w or e > w + f then return false end
  local d2 = pointSegDist2(px, py, self.ax, self.ay, self.bx, self.by)
  local r = self.thick * 0.5 + pr
  return d2 < r * r
end

function Beam:alive() return self.elapsed < self.warn + self.fire end

-- ─── Wave ──────────────────────────────────────────────────────────────
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
  o.color = opts.color
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

local function drawIlluminatedSlab(x, y, w, h, accent, alpha)
  local cr, cg, cb = accent[1], accent[2], accent[3]
  local rad = math.min(w, h) * 0.30
  -- decorative outer glow halos
  for i = 5, 1, -1 do
    love.graphics.setColor(cr, cg, cb, 0.06 * alpha)
    love.graphics.rectangle("fill", x - i * 4, y - i * 4, w + i * 8, h + i * 8,
                            rad + i * 3, rad + i * 3)
  end
  -- bright pulsing white border (filled rect just outside the core)
  local b = bpulse(7, 0.88, 0.12)
  love.graphics.setColor(1, 1, 1, b * alpha)
  love.graphics.rectangle("fill", x - 3, y - 3, w + 6, h + 6, rad + 1.5, rad + 1.5)
  -- accent filled core (the hit zone)
  love.graphics.setColor(cr, cg, cb, 0.94 * alpha)
  love.graphics.rectangle("fill", x, y, w, h, rad, rad)
  -- inner highlight band running along the long axis
  if w > h then
    love.graphics.setColor(1, 1, 1, 0.45 * alpha)
    love.graphics.rectangle("fill", x + 6, y + h * 0.18, w - 12, h * 0.10, h * 0.05, h * 0.05)
  else
    love.graphics.setColor(1, 1, 1, 0.45 * alpha)
    love.graphics.rectangle("fill", x + w * 0.18, y + 6, w * 0.10, h - 12, w * 0.05, w * 0.05)
  end
end

function Wave:draw(accent)
  local c = self.color or accent
  if self.elapsed < self.warn then
    local k = self.elapsed / self.warn
    local pulse = 0.45 + 0.55 * math.abs(math.sin(self.elapsed * (12 + 18 * k)))
    love.graphics.setColor(c[1], c[2], c[3], 0.22 * pulse)
    if self.dir == "right" or self.dir == "left" then
      love.graphics.rectangle("fill", 0, 0, 1920, self.gap_y - self.gap_h*0.5, 16, 16)
      love.graphics.rectangle("fill", 0, self.gap_y + self.gap_h*0.5, 1920,
                              1080 - (self.gap_y + self.gap_h*0.5), 16, 16)
    else
      love.graphics.rectangle("fill", 0, 0, self.gap_y - self.gap_h*0.5, 1080, 16, 16)
      love.graphics.rectangle("fill", self.gap_y + self.gap_h*0.5, 0,
                              1920 - (self.gap_y + self.gap_h*0.5), 1080, 16, 16)
    end
    love.graphics.setColor(1, 1, 1, 0.55 * pulse)
    love.graphics.setLineWidth(3)
    if self.dir == "right" or self.dir == "left" then
      love.graphics.line(0, self.gap_y - self.gap_h*0.5, 1920, self.gap_y - self.gap_h*0.5)
      love.graphics.line(0, self.gap_y + self.gap_h*0.5, 1920, self.gap_y + self.gap_h*0.5)
    else
      love.graphics.line(self.gap_y - self.gap_h*0.5, 0, self.gap_y - self.gap_h*0.5, 1080)
      love.graphics.line(self.gap_y + self.gap_h*0.5, 0, self.gap_y + self.gap_h*0.5, 1080)
    end
    love.graphics.setLineWidth(1)
    return
  end

  if self.dir == "right" or self.dir == "left" then
    local x = self.x
    local topH = self.gap_y - self.gap_h*0.5
    local botY = self.gap_y + self.gap_h*0.5
    drawIlluminatedSlab(x, 0,    self.thick, topH,            c, 1.0)
    drawIlluminatedSlab(x, botY, self.thick, 1080 - botY,     c, 1.0)
  else
    local y = self.y
    local leftW = self.gap_y - self.gap_h*0.5
    local rightX = self.gap_y + self.gap_h*0.5
    drawIlluminatedSlab(0,      y, leftW,        self.thick, c, 1.0)
    drawIlluminatedSlab(rightX, y, 1920 - rightX, self.thick, c, 1.0)
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

-- ─── Ring ──────────────────────────────────────────────────────────────
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
  o.color = opts.color
  return M.add(o)
end

function Ring:update(dt, t)
  self.elapsed = self.elapsed + dt
  if self.elapsed >= self.warn then
    self.r = self.r + self.speed * dt
  end
end

function Ring:draw(accent)
  local c = self.color or accent
  local cr, cg, cb = c[1], c[2], c[3]
  if self.elapsed < self.warn then
    local k = self.elapsed / self.warn
    local pulse = 0.4 + 0.6 * math.abs(math.sin(self.elapsed * (16 + 22 * k)))
    love.graphics.setColor(cr, cg, cb, 0.55 * pulse)
    love.graphics.setLineWidth(2 + 5 * k)
    love.graphics.circle("line", self.x, self.y, 18 + 110 * k)
    love.graphics.setColor(1, 1, 1, 0.45 * pulse * k)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", self.x, self.y, 14 + 110 * k)
    love.graphics.setLineWidth(1)
    return
  end
  -- soft outer glow band
  for i = 6, 1, -1 do
    love.graphics.setColor(cr, cg, cb, 0.07)
    love.graphics.setLineWidth(self.thick + i * 6)
    love.graphics.circle("line", self.x, self.y, self.r)
  end
  -- pulsing illuminated borders (outer + inner edges of the band)
  local b = bpulse(7, 0.92, 0.08)
  love.graphics.setColor(1, 1, 1, b)
  love.graphics.setLineWidth(3)
  love.graphics.circle("line", self.x, self.y, self.r + self.thick * 0.5 + 1)
  love.graphics.circle("line", self.x, self.y, self.r - self.thick * 0.5 - 1)
  -- accent band (the actual hit zone)
  love.graphics.setColor(cr, cg, cb, 0.95)
  love.graphics.setLineWidth(self.thick - 2)
  love.graphics.circle("line", self.x, self.y, self.r)
  -- bright thin centre stripe
  love.graphics.setColor(1, 1, 1, 0.45)
  love.graphics.setLineWidth(2)
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

-- ─── Chaser ────────────────────────────────────────────────────────────
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
  o.color = opts.color
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
  local c = self.color or accent
  local cr, cg, cb = c[1], c[2], c[3]
  if self.elapsed < self.warn then
    local k = self.elapsed / self.warn
    local pulse = 0.4 + 0.6 * math.abs(math.sin(self.elapsed * (16 + 22 * k)))
    love.graphics.setColor(cr, cg, cb, 0.45 * pulse)
    love.graphics.setLineWidth(2 + 4 * k)
    love.graphics.circle("line", self.x, self.y, self.r + 22 - 16 * k)
    love.graphics.setColor(cr, cg, cb, 0.20 * pulse)
    love.graphics.circle("fill", self.x, self.y, self.r * 0.7)
    love.graphics.setLineWidth(1)
    return
  end
  -- outer glow halos
  for i = 7, 1, -1 do
    love.graphics.setColor(cr, cg, cb, 0.07)
    love.graphics.circle("fill", self.x, self.y, self.r + i * 5)
  end
  -- pulsing white border
  local b = bpulse(7, 0.88, 0.12)
  love.graphics.setColor(1, 1, 1, b)
  love.graphics.setLineWidth(3)
  love.graphics.circle("line", self.x, self.y, self.r + 1)
  -- accent core
  love.graphics.setColor(cr, cg, cb, 0.95)
  love.graphics.circle("fill", self.x, self.y, self.r - 1)
  -- white inner sparkle
  love.graphics.setColor(1, 1, 1, 0.85)
  love.graphics.circle("fill", self.x, self.y, self.r * 0.45)
  love.graphics.setLineWidth(1)
end

function Chaser:hits(px, py, pr)
  if self.elapsed < self.warn then return false end
  local dx, dy = px - self.x, py - self.y
  return dx*dx + dy*dy < (self.r + pr) * (self.r + pr)
end

function Chaser:alive() return self.elapsed < self.life end

-- ─── Spinner ───────────────────────────────────────────────────────────
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
  o.color = opts.color
  return M.add(o)
end

function Spinner:update(dt, t)
  self.elapsed = self.elapsed + dt
  if self.elapsed >= self.warn then
    self.angle = self.angle + self.spin * dt
  end
end

function Spinner:draw(accent)
  local c = self.color or accent
  local cr, cg, cb = c[1], c[2], c[3]
  local x, y, L, thk = self.x, self.y, self.length, self.thick
  local active = self.elapsed >= self.warn
  if not active then
    local k = self.elapsed / self.warn
    local pulse = 0.4 + 0.6 * math.abs(math.sin(self.elapsed * (16 + 24 * k)))
    love.graphics.setColor(cr, cg, cb, 0.55 * pulse)
    love.graphics.setLineWidth(2 + 6 * k)
    for i = 0, self.arms - 1 do
      local a = self.angle + (math.pi / self.arms) * i
      love.graphics.line(x - math.cos(a)*L, y - math.sin(a)*L, x + math.cos(a)*L, y + math.sin(a)*L)
    end
    -- pulsing white centre marker
    love.graphics.setColor(1, 1, 1, 0.65 * pulse)
    love.graphics.circle("fill", x, y, 4 + 3 * k)
    love.graphics.setLineWidth(1)
    return
  end
  for i = 0, self.arms - 1 do
    local a = self.angle + (math.pi / self.arms) * i
    local x2, y2 = x + math.cos(a)*L, y + math.sin(a)*L
    local x1, y1 = x - math.cos(a)*L, y - math.sin(a)*L
    -- outer aura
    love.graphics.setColor(cr, cg, cb, 0.10)
    drawCapsule(x1, y1, x2, y2, thk * 1.9)
    -- bright pulsing white border (capsule slightly larger than core)
    local b = bpulse(8, 0.90, 0.10)
    love.graphics.setColor(1, 1, 1, b)
    drawCapsule(x1, y1, x2, y2, thk + 5)
    -- accent core (the hit zone)
    love.graphics.setColor(cr, cg, cb, 0.95)
    drawCapsule(x1, y1, x2, y2, thk)
    -- bright white centre stripe
    love.graphics.setColor(1, 1, 1, 0.95)
    drawCapsule(x1, y1, x2, y2, thk * 0.40)
  end
  -- pivot
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.circle("fill", x, y, 6)
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

-- ─── Bar (JSAB sweeping plank) ────────────────────────────────────────
-- A rounded thin bar that slides across the screen at a fixed angle. Use
-- M.bar({ x, y, dir_x, dir_y, length, thick, speed, life, color })
local Bar = {}
Bar.__index = Bar

function M.bar(opts)
  local o = setmetatable({}, Bar)
  o.x, o.y = opts.x, opts.y
  o.dir_x, o.dir_y = opts.dir_x or 1, opts.dir_y or 0
  o.length = opts.length or 800
  o.thick  = opts.thick or 26
  o.speed  = opts.speed or 460
  o.warn   = opts.warn or 0.55
  o.life   = opts.life or 2.8
  o.elapsed = 0
  o.color = opts.color
  return M.add(o)
end

function Bar:_endpoints()
  -- bar lies perpendicular to its travel direction
  local nx, ny = -self.dir_y, self.dir_x   -- perp
  local hx, hy = nx * self.length * 0.5, ny * self.length * 0.5
  return self.x - hx, self.y - hy, self.x + hx, self.y + hy
end

function Bar:update(dt, t)
  self.elapsed = self.elapsed + dt
  if self.elapsed >= self.warn then
    self.x = self.x + self.dir_x * self.speed * dt
    self.y = self.y + self.dir_y * self.speed * dt
  end
end

function Bar:draw(accent)
  local c = self.color or accent
  local cr, cg, cb = c[1], c[2], c[3]
  local ax, ay, bx, by = self:_endpoints()
  if self.elapsed < self.warn then
    local k = self.elapsed / self.warn
    local pulse = 0.4 + 0.6 * math.abs(math.sin(self.elapsed * (10 + 22 * k)))
    -- preview rail with faint expanding capsule
    love.graphics.setColor(cr, cg, cb, 0.30 * pulse)
    love.graphics.setLineWidth(2 + 4 * k)
    love.graphics.line(ax, ay, bx, by)
    love.graphics.setColor(cr, cg, cb, 0.18 * pulse * k)
    drawCapsule(ax, ay, bx, by, self.thick * (0.30 + 0.65 * k))
    love.graphics.setLineWidth(1)
    return
  end
  -- decorative outer aura
  love.graphics.setColor(cr, cg, cb, 0.16)
  drawCapsule(ax, ay, bx, by, self.thick * 1.85)
  -- bright pulsing white border
  local b = bpulse(7, 0.90, 0.10)
  love.graphics.setColor(1, 1, 1, b)
  drawCapsule(ax, ay, bx, by, self.thick + 5)
  -- accent core
  love.graphics.setColor(cr, cg, cb, 0.95)
  drawCapsule(ax, ay, bx, by, self.thick)
  -- white centre stripe
  love.graphics.setColor(1, 1, 1, 0.95)
  drawCapsule(ax, ay, bx, by, self.thick * 0.40)
end

function Bar:hits(px, py, pr)
  if self.elapsed < self.warn then return false end
  local ax, ay, bx, by = self:_endpoints()
  local d2 = pointSegDist2(px, py, ax, ay, bx, by)
  local r = self.thick * 0.5 + pr
  return d2 < r * r
end

function Bar:alive()
  if self.elapsed >= self.warn + self.life then return false end
  -- cull when fully off-canvas
  return self.x > -800 and self.x < 2720 and self.y > -800 and self.y < 1880
end

-- ─── Fan (rotating sweep arc) ──────────────────────────────────────────
-- A pivot with a sector that rotates around. The sector is the hot zone.
-- M.fan({ x, y, angle, sweep, spin, length, life, warn, color })
local Fan = {}
Fan.__index = Fan

function M.fan(opts)
  local o = setmetatable({}, Fan)
  o.x, o.y = opts.x, opts.y
  o.angle = opts.angle or 0
  o.sweep = opts.sweep or (math.pi / 3)    -- arc width in radians
  o.spin  = opts.spin or 1.6
  o.length = opts.length or 520
  o.life  = opts.life or 1.6
  o.warn  = opts.warn or 0.55
  o.elapsed = 0
  o.color = opts.color
  return M.add(o)
end

function Fan:update(dt, t)
  self.elapsed = self.elapsed + dt
  if self.elapsed >= self.warn then
    self.angle = self.angle + self.spin * dt
  end
end

local function drawSector(x, y, len, a0, a1, segs)
  segs = segs or 18
  local pts = { x, y }
  for i = 0, segs do
    local a = a0 + (a1 - a0) * (i / segs)
    table.insert(pts, x + math.cos(a) * len)
    table.insert(pts, y + math.sin(a) * len)
  end
  love.graphics.polygon("fill", pts)
end

function Fan:draw(accent)
  local c = self.color or accent
  local cr, cg, cb = c[1], c[2], c[3]
  local a0 = self.angle - self.sweep * 0.5
  local a1 = self.angle + self.sweep * 0.5
  if self.elapsed < self.warn then
    local k = self.elapsed / self.warn
    local pulse = 0.4 + 0.6 * math.abs(math.sin(self.elapsed * (10 + 22 * k)))
    -- arc outline preview
    love.graphics.setColor(cr, cg, cb, 0.40 * pulse)
    love.graphics.setLineWidth(2 + 5 * k)
    love.graphics.arc("line", "open", self.x, self.y, self.length, a0, a1)
    love.graphics.line(self.x, self.y, self.x + math.cos(a0) * self.length,
                                       self.y + math.sin(a0) * self.length)
    love.graphics.line(self.x, self.y, self.x + math.cos(a1) * self.length,
                                       self.y + math.sin(a1) * self.length)
    love.graphics.setLineWidth(1)
    return
  end
  -- soft outer glow
  for i = 4, 1, -1 do
    love.graphics.setColor(cr, cg, cb, 0.07)
    drawSector(self.x, self.y, self.length + i * 8, a0, a1)
  end
  -- accent fill
  love.graphics.setColor(cr, cg, cb, 0.85)
  drawSector(self.x, self.y, self.length, a0, a1)
  -- bright pulsing arc edge
  local b = bpulse(8, 0.88, 0.12)
  love.graphics.setColor(1, 1, 1, b)
  love.graphics.setLineWidth(3)
  love.graphics.arc("line", "open", self.x, self.y, self.length, a0, a1)
  love.graphics.line(self.x, self.y, self.x + math.cos(a0) * self.length,
                                     self.y + math.sin(a0) * self.length)
  love.graphics.line(self.x, self.y, self.x + math.cos(a1) * self.length,
                                     self.y + math.sin(a1) * self.length)
  -- pivot
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.circle("fill", self.x, self.y, 6)
  love.graphics.setLineWidth(1)
end

function Fan:hits(px, py, pr)
  if self.elapsed < self.warn then return false end
  local dx, dy = px - self.x, py - self.y
  local d = math.sqrt(dx*dx + dy*dy)
  if d > self.length + pr then return false end
  if d < 4 then return true end
  local pa = math.atan2(dy, dx)
  -- normalise angle delta
  local da = (pa - self.angle + math.pi) % (math.pi * 2) - math.pi
  return math.abs(da) <= self.sweep * 0.5
end

function Fan:alive() return self.elapsed < self.warn + self.life end

-- ─── Spikes (saw-row rising from an edge) ─────────────────────────────
-- A row of N triangular spikes along one edge. Each spike rises during
-- warn, holds during fire, retracts after.
-- M.spikes({ edge = "top|bottom|left|right", count, w, h, gap, life, warn, color })
local Spikes = {}
Spikes.__index = Spikes

function M.spikes(opts)
  local o = setmetatable({}, Spikes)
  o.edge   = opts.edge or "bottom"
  o.count  = opts.count or 12
  o.w      = opts.w or 110           -- spike base width
  o.h      = opts.h or 130           -- spike height (extension)
  o.gap    = opts.gap or 30
  o.life   = opts.life or 0.55       -- hot duration after rise
  o.warn   = opts.warn or 0.55
  o.elapsed = 0
  o.color = opts.color
  return M.add(o)
end

local function spikeTriangle(edge, base_x, base_y, half_w, ext)
  -- returns 6 points (3 vertices) for a triangle pointing inward along edge
  if edge == "bottom" then
    return base_x - half_w, base_y, base_x + half_w, base_y, base_x, base_y - ext
  elseif edge == "top" then
    return base_x - half_w, base_y, base_x + half_w, base_y, base_x, base_y + ext
  elseif edge == "left" then
    return base_x, base_y - half_w, base_x, base_y + half_w, base_x + ext, base_y
  else  -- right
    return base_x, base_y - half_w, base_x, base_y + half_w, base_x - ext, base_y
  end
end

function Spikes:_extension()
  if self.elapsed < self.warn then
    -- preview at very low extension
    return self.h * 0.10 * (self.elapsed / self.warn)
  elseif self.elapsed < self.warn + self.life then
    local k = (self.elapsed - self.warn) / self.life
    -- ease in / out: rise quickly, hold, retract
    if k < 0.20 then return self.h * (k / 0.20) end
    if k < 0.80 then return self.h end
    return self.h * (1 - (k - 0.80) / 0.20)
  end
  return 0
end

function Spikes:_iter()
  -- yields each spike's base position via a callback
  local total_w = self.count * self.w + (self.count - 1) * self.gap
  local start
  local fn = function(idx)
    local center = start + (idx - 0.5) * (self.w + self.gap) - self.gap * 0.5
    return center
  end
  if self.edge == "top" then
    start = (1920 - total_w) * 0.5
    return function(i)
      local cx = start + (i - 1) * (self.w + self.gap) + self.w * 0.5
      return cx, 0
    end
  elseif self.edge == "bottom" then
    start = (1920 - total_w) * 0.5
    return function(i)
      local cx = start + (i - 1) * (self.w + self.gap) + self.w * 0.5
      return cx, 1080
    end
  elseif self.edge == "left" then
    start = (1080 - total_w) * 0.5
    return function(i)
      local cy = start + (i - 1) * (self.w + self.gap) + self.w * 0.5
      return 0, cy
    end
  else  -- right
    start = (1080 - total_w) * 0.5
    return function(i)
      local cy = start + (i - 1) * (self.w + self.gap) + self.w * 0.5
      return 1920, cy
    end
  end
end

function Spikes:update(dt, t) self.elapsed = self.elapsed + dt end

function Spikes:draw(accent)
  local c = self.color or accent
  local cr, cg, cb = c[1], c[2], c[3]
  local ext = self:_extension()
  local at = self:_iter()
  local active = self.elapsed >= self.warn
  for i = 1, self.count do
    local bx, by = at(i)
    if not active then
      local pulse = 0.4 + 0.6 * math.abs(math.sin(self.elapsed * 16))
      love.graphics.setColor(cr, cg, cb, 0.35 * pulse)
      local x1, y1, x2, y2, x3, y3 = spikeTriangle(self.edge, bx, by, self.w * 0.45, ext)
      love.graphics.setLineWidth(2)
      love.graphics.polygon("line", x1, y1, x2, y2, x3, y3)
      love.graphics.setLineWidth(1)
    else
      -- soft outer glow
      love.graphics.setColor(cr, cg, cb, 0.10)
      local x1, y1, x2, y2, x3, y3 = spikeTriangle(self.edge, bx, by, self.w * 0.55, ext * 1.10)
      love.graphics.polygon("fill", x1, y1, x2, y2, x3, y3)
      -- bright border
      local b = bpulse(8, 0.90, 0.10)
      x1, y1, x2, y2, x3, y3 = spikeTriangle(self.edge, bx, by, self.w * 0.50, ext * 1.04)
      love.graphics.setColor(1, 1, 1, b)
      love.graphics.polygon("fill", x1, y1, x2, y2, x3, y3)
      -- accent core
      x1, y1, x2, y2, x3, y3 = spikeTriangle(self.edge, bx, by, self.w * 0.45, ext)
      love.graphics.setColor(cr, cg, cb, 0.95)
      love.graphics.polygon("fill", x1, y1, x2, y2, x3, y3)
    end
  end
end

local function pointInTri(px, py, x1, y1, x2, y2, x3, y3)
  -- barycentric-ish: sign of cross products
  local d1 = (px - x2) * (y1 - y2) - (x1 - x2) * (py - y2)
  local d2 = (px - x3) * (y2 - y3) - (x2 - x3) * (py - y3)
  local d3 = (px - x1) * (y3 - y1) - (x3 - x1) * (py - y1)
  local has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
  local has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
  return not (has_neg and has_pos)
end

function Spikes:hits(px, py, pr)
  if self.elapsed < self.warn then return false end
  local ext = self:_extension()
  if ext < 4 then return false end
  local at = self:_iter()
  for i = 1, self.count do
    local bx, by = at(i)
    -- inflate triangle by player radius for circle-vs-triangle approx
    local x1, y1, x2, y2, x3, y3 = spikeTriangle(self.edge, bx, by, self.w * 0.45 + pr, ext + pr)
    if pointInTri(px, py, x1, y1, x2, y2, x3, y3) then return true end
  end
  return false
end

function Spikes:alive() return self.elapsed < self.warn + self.life + 0.1 end

-- ─── Triangle bullet (oriented projectile) ─────────────────────────────
-- A small triangular projectile that travels point-first. Hit detection is
-- a circle for fairness; the triangle is purely visual.
local Triangle = {}
Triangle.__index = Triangle

function M.triangle(opts)
  local o = setmetatable({}, Triangle)
  o.x, o.y = opts.x, opts.y
  o.dx, o.dy = opts.dx, opts.dy
  o.speed = opts.speed or 360
  o.r = opts.r or 13
  o.fire_t = opts.fire_t or 0.50
  o.life = opts.life or 4.0
  o.elapsed = 0
  o.color = opts.color
  return M.add(o)
end

function Triangle:update(dt, t)
  self.elapsed = self.elapsed + dt
  if self.elapsed > self.fire_t then
    self.x = self.x + self.dx * self.speed * dt
    self.y = self.y + self.dy * self.speed * dt
  end
end

local function triPoints(cx, cy, dx, dy, r)
  -- equilateral-ish triangle pointing along (dx,dy)
  local nx, ny = -dy, dx           -- perp
  local fx, fy = cx + dx * r * 1.3, cy + dy * r * 1.3
  local b1x = cx - dx * r * 0.6 + nx * r * 0.95
  local b1y = cy - dy * r * 0.6 + ny * r * 0.95
  local b2x = cx - dx * r * 0.6 - nx * r * 0.95
  local b2y = cy - dy * r * 0.6 - ny * r * 0.95
  return fx, fy, b1x, b1y, b2x, b2y
end

function Triangle:draw(accent)
  local c = self.color or accent
  local cr, cg, cb = c[1], c[2], c[3]
  if self.elapsed < self.fire_t then
    local k = self.elapsed / self.fire_t
    local pulse = 0.4 + 0.6 * math.abs(math.sin(self.elapsed * (10 + 18 * k)))
    -- expanding triangle outline at spawn point
    love.graphics.setColor(1, 1, 1, 0.75 * pulse)
    love.graphics.setLineWidth(2 + 3 * k)
    local fx, fy, b1x, b1y, b2x, b2y =
      triPoints(self.x, self.y, self.dx, self.dy, self.r * (0.35 + 0.85 * k))
    love.graphics.polygon("line", fx, fy, b1x, b1y, b2x, b2y)
    love.graphics.setLineWidth(1)
  else
    -- soft outer glow (slightly larger triangle, low alpha)
    love.graphics.setColor(cr, cg, cb, 0.18)
    local fx, fy, b1x, b1y, b2x, b2y =
      triPoints(self.x, self.y, self.dx, self.dy, self.r * 1.55)
    love.graphics.polygon("fill", fx, fy, b1x, b1y, b2x, b2y)
    -- bright border
    local b = bpulse(8, 0.92, 0.08)
    love.graphics.setColor(1, 1, 1, b)
    fx, fy, b1x, b1y, b2x, b2y = triPoints(self.x, self.y, self.dx, self.dy, self.r * 1.10)
    love.graphics.polygon("fill", fx, fy, b1x, b1y, b2x, b2y)
    -- accent core
    love.graphics.setColor(cr, cg, cb, 0.97)
    fx, fy, b1x, b1y, b2x, b2y = triPoints(self.x, self.y, self.dx, self.dy, self.r)
    love.graphics.polygon("fill", fx, fy, b1x, b1y, b2x, b2y)
  end
end

function Triangle:hits(px, py, pr)
  if self.elapsed < self.fire_t then return false end
  local dx, dy = px - self.x, py - self.y
  return dx*dx + dy*dy < (self.r + pr) * (self.r + pr)
end

function Triangle:alive()
  if self.elapsed > self.life then return false end
  return self.x > -200 and self.x < 2120 and self.y > -200 and self.y < 1280
end

-- ─── Director helpers: composite spawns ───────────────────────────────

-- Comb of N parallel bars marching in formation (with optional gap_idx
-- left empty so the player can slip through).
function M.bar_comb(opts)
  local n = opts.count or 4
  local horizontal = opts.horizontal ~= false
  local speed = opts.speed or 460
  local thick = opts.thick or 28
  local life  = opts.life or 2.6
  local warn  = opts.warn or 0.65
  local color = opts.color
  local stagger = opts.stagger or 240
  local gap_idx = opts.gap_idx                 -- 1..n, that bar is omitted
  local from_dir = opts.from_dir or 1          -- +1 left->right, -1 right->left
  if horizontal then
    for i = 1, n do
      if i ~= gap_idx then
        M.bar({
          x = (from_dir > 0) and -100 - (i - 1) * stagger or 2020 + (i - 1) * stagger,
          y = 540,
          dir_x = from_dir, dir_y = 0,
          length = 1140, thick = thick,
          speed = speed, warn = warn, life = life,
          color = color,
        })
      end
    end
  else
    for i = 1, n do
      if i ~= gap_idx then
        M.bar({
          x = 960,
          y = (from_dir > 0) and -100 - (i - 1) * stagger or 1180 + (i - 1) * stagger,
          dir_x = 0, dir_y = from_dir,
          length = 1700, thick = thick,
          speed = speed, warn = warn, life = life,
          color = color,
        })
      end
    end
  end
end

-- Rain: a horizontal curtain of small bullets falling from the top of
-- the screen with a small gap centred on opts.gap_x so the player can
-- thread through.
function M.rain(opts)
  local n = opts.count or 14
  local gap_w = opts.gap_w or 220
  local gap_x = opts.gap_x or 960
  local speed = opts.speed or 380
  local r     = opts.r or 9
  local warn  = opts.warn or 0.55
  local color = opts.color
  local span  = 1860
  local x0    = 30
  for i = 1, n do
    local x = x0 + (span / (n - 1)) * (i - 1)
    if math.abs(x - gap_x) > gap_w * 0.5 then
      M.bullet({
        x = x, y = -20, dx = 0, dy = 1,
        speed = speed, r = r, fire_t = warn, life = 5.0,
        color = color,
      })
    end
  end
end

-- Spiral: bullets emerging from a centre point in a slowly rotating
-- spiral pattern. arms = how many parallel arms; emit_count = bullets
-- per arm; emit_dt is staggered within fire_t so the arms unfurl.
function M.spiral(opts)
  local cx, cy = opts.x or 960, opts.y or 540
  local arms   = opts.arms or 3
  local count  = opts.count or 6
  local speed  = opts.speed or 280
  local r      = opts.r or 9
  local warn   = opts.warn or 0.50
  local color  = opts.color
  for i = 1, count do
    for a = 0, arms - 1 do
      local angle = (a / arms) * math.pi * 2 + (i / count) * (math.pi * 0.55)
      local stagger_warn = warn + (i - 1) * 0.12
      M.bullet({
        x = cx, y = cy,
        dx = math.cos(angle), dy = math.sin(angle),
        speed = speed, r = r,
        fire_t = stagger_warn, life = 4.5,
        color = color,
      })
    end
  end
end

return M
