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
  -- 0..1 ramp shaped to song structure. Eased in the early sections so new
  -- players get a runway, and the climax stops short of full saturation.
  if t < 10      then return 0.00 end
  if t < 28      then return 0.10 + 0.15 * ((t - 10) / 18) end
  if t < 60      then return 0.28 + 0.12 * ((t - 28) / 32) end
  if t < 95      then return 0.42 + 0.18 * ((t - 60) / 35) end
  if t < 130     then return 0.60 + 0.12 * ((t - 95) / 35) end
  if t < 165     then return 0.72 + 0.10 * ((t - 130) / 35) end
  if t < 195     then return 0.82 + 0.08 * ((t - 165) / 30) end
  if t < 215     then return 0.90 end
  return 0.45
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
  local r = love.math.random()
  if r < 0.65 or I < 0.35 then
    -- 1-2 bullets from edges aimed at center (cap at 2 even at high intensity)
    local n = 1
    if I > 0.55 then n = 2 end
    for i = 1, n do
      local x, y = edgePoint()
      local dx, dy = dirToCenter(x + rand(-180,180), y + rand(-110,110))
      Obs.bullet({ x=x, y=y, dx=dx, dy=dy, speed=720 + I * 200, fire_t=0.55 - I * 0.10, r=11 })
    end
  elseif r < 0.88 then
    -- expanding ring from a spot offset from center
    local x = CENTER_X + rand(-380, 380)
    local y = CENTER_Y + rand(-220, 220)
    Obs.ring({ x=x, y=y, maxr=850, speed=540 + I * 220, thick=12 + I * 5, warn=0.45 - I*0.10 })
  else
    -- burst of bullets from a focal point
    local x = rand(280, PLAY_W-280)
    local y = rand(180, PLAY_H-180)
    local n = 8 + math.floor(I * 6)
    Obs.burst({ x=x, y=y, count=n, speed=480 + I*200, r=10, fire_t=0.55 - I*0.10, angle=rand(0, math.pi) })
  end
end

local function onSnare(t, ev, target)
  local I = intensity(t)
  local r = love.math.random()
  if I < 0.40 then
    -- light section: skip most snares, only an occasional drift bullet
    if r < 0.45 then
      local x, y = edgePoint()
      local dx, dy = dirToCenter(x, y)
      Obs.bullet({ x=x, y=y, dx=dx, dy=dy, speed=620, r=10, fire_t=0.55 })
    end
    return
  end
  if r < 0.40 then
    -- spinner
    local x = CENTER_X + rand(-220, 220)
    local y = CENTER_Y + rand(-160, 160)
    Obs.spinner({
      x=x, y=y,
      angle = rand(0, math.pi),
      spin = (love.math.random() < 0.5 and -1 or 1) * (1.1 + I * 1.2),
      length = 720,
      thick  = 16 + I * 5,
      arms   = (I > 0.78) and 3 or 2,
      life   = 1.4 + I * 0.5,
      warn   = 0.55 - I*0.10,
    })
  elseif r < 0.78 then
    -- horizontal or vertical wave with a generous gap
    local horiz = love.math.random() < 0.6
    if horiz then
      Obs.wave({
        dir = (love.math.random() < 0.5) and "right" or "left",
        thick = 60,
        gap_y = rand(300, 780),
        gap_h = math.max(220, 360 - I * 90),
        speed = 600 + I * 180,
        warn = 0.50,
      })
    else
      Obs.wave({
        dir = (love.math.random() < 0.5) and "down" or "up",
        thick = 60,
        gap_y = rand(440, 1480),
        gap_h = math.max(230, 360 - I * 90),
        speed = 600 + I * 180,
        warn = 0.50,
      })
    end
  else
    -- beam laser with a long telegraph
    local horiz = love.math.random() < 0.6
    if horiz then
      local y = rand(160, PLAY_H - 160)
      Obs.beam({ ax=-20, ay=y, bx=PLAY_W+20, by=y, warn=0.75, fire=0.28, thick=22 + I*7 })
    else
      local x = rand(160, PLAY_W - 160)
      Obs.beam({ ax=x, ay=-20, bx=x, by=PLAY_H+20, warn=0.75, fire=0.28, thick=22 + I*7 })
    end
  end
end

local function onHat(t, ev, target)
  local I = intensity(t)
  if I < 0.62 then return end
  if love.math.random() < 0.18 + I * 0.22 then
    -- twinkly small bullet from random edge
    local x, y = edgePoint()
    local dx, dy = dirToCenter(x + rand(-140, 140), y + rand(-90, 90))
    Obs.bullet({ x=x, y=y, dx=dx, dy=dy, speed=820, r=7, fire_t=0.32, life=2.5 })
  end
end

local function onChorusBeat(t, ev, target)
  -- spawn a chaser only sparsely during the climax
  if intensity(t) > 0.82 and love.math.random() < 0.10 then
    Obs.chaser({
      x = (love.math.random() < 0.5) and -80 or PLAY_W + 80,
      y = rand(80, PLAY_H - 80),
      speed = 200 + intensity(t) * 70,
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
