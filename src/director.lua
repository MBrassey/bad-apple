-- Director: spawns obstacles in response to beat/onset events from src/beats.lua.
-- Difficulty ramps over song time so the experience builds.
local Obs = require "src.obstacles"

local M = {}

local PLAY_W, PLAY_H = 1920, 1080
local CENTER_X, CENTER_Y = 960, 540

-- shuffled-bag state for variety on burst pattern picks
local bag = {}
local function pickBag(items)
  if #bag == 0 then
    for _, v in ipairs(items) do table.insert(bag, v) end
    -- fisher-yates
    for i = #bag, 2, -1 do
      local j = love.math.random(i)
      bag[i], bag[j] = bag[j], bag[i]
    end
  end
  return table.remove(bag)
end

local function intensity(t)
  -- Heavily eased ramp -- climax tops out around 0.45. Combined with the
  -- spawn-skip gate below this means the average load is roughly a third
  -- of the original tuning, while every spawn that does happen still
  -- lands on a real beat.
  if t < 12      then return 0.00 end
  if t < 32      then return 0.05 + 0.07 * ((t - 12) / 20) end
  if t < 70      then return 0.12 + 0.08 * ((t - 32) / 38) end
  if t < 110     then return 0.20 + 0.10 * ((t - 70) / 40) end
  if t < 150     then return 0.30 + 0.07 * ((t - 110) / 40) end
  if t < 195     then return 0.37 + 0.08 * ((t - 150) / 45) end
  if t < 215     then return 0.45 end
  return 0.20
end

-- Probability that an incoming event actually spawns something. Beat sync
-- is preserved on the events we DO take; we just take fewer of them.
local function spawnGate(I, base)
  return love.math.random() < (base * (0.5 + I))
end

M.intensity = intensity

local function rand(a, b) return a + love.math.random() * (b - a) end

local function dirToCenter(x, y)
  local dx, dy = CENTER_X - x, CENTER_Y - y
  local m = math.sqrt(dx*dx + dy*dy)
  return dx/m, dy/m
end

-- Edge spawn
local function edgePoint()
  local side = love.math.random(4)
  if side == 1 then return rand(60, PLAY_W-60), -20, 0, 1
  elseif side == 2 then return rand(60, PLAY_W-60), PLAY_H+20, 0, -1
  elseif side == 3 then return -20, rand(60, PLAY_H-60), 1, 0
  else return PLAY_W+20, rand(60, PLAY_H-60), -1, 0 end
end

----------------------------------------------------------------------
-- Pattern handlers, keyed by event type. Each picks behavior based on
-- intensity and current bag context.
----------------------------------------------------------------------

local function onKick(t, ev, target)
  local I = intensity(t)
  if not spawnGate(I, 0.55) then return end          -- ~half of kicks fire at low I
  local r = love.math.random()
  if r < 0.78 or I < 0.30 then
    -- single slow bullet from an edge aimed loosely at center
    local x, y = edgePoint()
    local dx, dy = dirToCenter(x + rand(-200,200), y + rand(-130,130))
    Obs.bullet({ x=x, y=y, dx=dx, dy=dy, speed=380 + I * 120, fire_t=0.65, r=10 })
  elseif r < 0.92 then
    -- expanding ring with a long warn
    local x = CENTER_X + rand(-360, 360)
    local y = CENTER_Y + rand(-220, 220)
    Obs.ring({ x=x, y=y, maxr=820, speed=300 + I * 130, thick=12, warn=0.55 })
  else
    -- small burst
    local x = rand(280, PLAY_W-280)
    local y = rand(180, PLAY_H-180)
    local n = 6 + math.floor(I * 4)
    Obs.burst({ x=x, y=y, count=n, speed=280 + I*120, r=10, fire_t=0.70, angle=rand(0, math.pi) })
  end
end

local function onSnare(t, ev, target)
  local I = intensity(t)
  if I < 0.20 then return end
  if not spawnGate(I, 0.40) then return end          -- snares fire sparsely
  local r = love.math.random()
  if r < 0.30 then
    -- spinner, slow rotation
    local x = CENTER_X + rand(-220, 220)
    local y = CENTER_Y + rand(-160, 160)
    Obs.spinner({
      x=x, y=y,
      angle = rand(0, math.pi),
      spin = (love.math.random() < 0.5 and -1 or 1) * (0.55 + I * 0.55),
      length = 720,
      thick  = 14 + I * 4,
      arms   = 2,
      life   = 1.2 + I * 0.4,
      warn   = 0.65,
    })
  elseif r < 0.75 then
    -- wide-gap wave moving slowly
    local horiz = love.math.random() < 0.6
    if horiz then
      Obs.wave({
        dir = (love.math.random() < 0.5) and "right" or "left",
        thick = 50,
        gap_y = rand(320, 760),
        gap_h = math.max(320, 460 - I * 80),
        speed = 360 + I * 100,
        warn = 0.65,
      })
    else
      Obs.wave({
        dir = (love.math.random() < 0.5) and "down" or "up",
        thick = 50,
        gap_y = rand(460, 1460),
        gap_h = math.max(330, 460 - I * 80),
        speed = 360 + I * 100,
        warn = 0.65,
      })
    end
  else
    -- beam laser, long telegraph
    local horiz = love.math.random() < 0.6
    if horiz then
      local y = rand(160, PLAY_H - 160)
      Obs.beam({ ax=-20, ay=y, bx=PLAY_W+20, by=y, warn=0.95, fire=0.24, thick=20 + I*5 })
    else
      local x = rand(160, PLAY_W - 160)
      Obs.beam({ ax=x, ay=-20, bx=x, by=PLAY_H+20, warn=0.95, fire=0.24, thick=20 + I*5 })
    end
  end
end

local function onHat(t, ev, target)
  -- hats are off in the easy tuning -- they used to add density that
  -- overwhelmed players in the chorus
  return
end

local function onChorusBeat(t, ev, target)
  -- one slow chaser only in the very late climax
  if intensity(t) >= 0.45 and love.math.random() < 0.04 then
    Obs.chaser({
      x = (love.math.random() < 0.5) and -80 or PLAY_W + 80,
      y = rand(80, PLAY_H - 80),
      speed = 130,
      r = 18,
      life = 7,
      target = target,
    })
  end
end

----------------------------------------------------------------------
-- Public entry points
----------------------------------------------------------------------

function M.handle(ev, t, target)
  if ev.type == "kick"  then onKick(t, ev, target)
  elseif ev.type == "snare" then onSnare(t, ev, target)
  elseif ev.type == "hat"   then onHat(t, ev, target)
  elseif ev.type == "beat"  then onChorusBeat(t, ev, target) end
end

return M
