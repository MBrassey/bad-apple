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
  -- 0..1 ramp shaped to the song. Bad Apple structure (beat-extracted): intro
  -- ~0-13s soft, first verse ~13-46s, build ~46-78s, chorus ~78-110s,
  -- second verse ~110-142s, big chorus ~142-180s, outro ~180-end.
  if t < 8       then return 0.05 end
  if t < 22      then return 0.20 + 0.15 * ((t - 8) / 14) end
  if t < 50      then return 0.40 + 0.10 * ((t - 22) / 28) end
  if t < 80      then return 0.55 + 0.20 * ((t - 50) / 30) end
  if t < 115     then return 0.75 + 0.10 * ((t - 80) / 35) end
  if t < 145     then return 0.85 + 0.05 * ((t - 115) / 30) end
  if t < 180     then return 0.95 + 0.05 * ((t - 145) / 35) end
  if t < 205     then return 1.00 end
  return 0.50
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
  if r < 0.55 or I < 0.3 then
    -- 1-3 bullets from edges aimed at center
    local n = 1
    if I > 0.4 then n = 2 end
    if I > 0.75 then n = 3 end
    for i = 1, n do
      local x, y = edgePoint()
      local dx, dy = dirToCenter(x + rand(-160,160), y + rand(-100,100))
      Obs.bullet({ x=x, y=y, dx=dx, dy=dy, speed=820 + I * 220, fire_t=0.35 - I * 0.1, r=12 })
    end
  elseif r < 0.85 then
    -- expanding ring from a spot offset from center
    local x = CENTER_X + rand(-380, 380)
    local y = CENTER_Y + rand(-220, 220)
    Obs.ring({ x=x, y=y, maxr=900, speed=620 + I * 240, thick=14 + I * 6, warn=0.30 - I*0.10 })
  else
    -- burst of bullets from a focal point
    local x = rand(280, PLAY_W-280)
    local y = rand(180, PLAY_H-180)
    local n = 10 + math.floor(I * 8)
    Obs.burst({ x=x, y=y, count=n, speed=560 + I*220, r=10, fire_t=0.42 - I*0.1, angle=rand(0, math.pi) })
  end
end

local function onSnare(t, ev, target)
  local I = intensity(t)
  local r = love.math.random()
  if I < 0.35 then
    -- light: a couple of bullets
    local x, y = edgePoint()
    local dx, dy = dirToCenter(x, y)
    Obs.bullet({ x=x, y=y, dx=dx, dy=dy, speed=720, r=10 })
    return
  end
  if r < 0.45 then
    -- spinner
    local x = CENTER_X + rand(-220, 220)
    local y = CENTER_Y + rand(-160, 160)
    Obs.spinner({
      x=x, y=y,
      angle = rand(0, math.pi),
      spin = (love.math.random() < 0.5 and -1 or 1) * (1.4 + I * 1.4),
      length = 720,
      thick  = 18 + I * 6,
      arms   = (I > 0.7) and 3 or 2,
      life   = 1.6 + I * 0.6,
      warn   = 0.45 - I*0.1,
    })
  elseif r < 0.78 then
    -- horizontal or vertical wave
    local horiz = love.math.random() < 0.6
    if horiz then
      Obs.wave({
        dir = (love.math.random() < 0.5) and "right" or "left",
        thick = 70,
        gap_y = rand(280, 800),
        gap_h = math.max(170, 280 - I * 80),
        speed = 700 + I * 200,
        warn = 0.35,
      })
    else
      Obs.wave({
        dir = (love.math.random() < 0.5) and "down" or "up",
        thick = 70,
        gap_y = rand(420, 1500),
        gap_h = math.max(180, 280 - I * 80),
        speed = 700 + I * 200,
        warn = 0.35,
      })
    end
  else
    -- beam laser
    local horiz = love.math.random() < 0.6
    if horiz then
      local y = rand(160, PLAY_H - 160)
      Obs.beam({ ax=-20, ay=y, bx=PLAY_W+20, by=y, warn=0.55, fire=0.30, thick=24 + I*8 })
    else
      local x = rand(160, PLAY_W - 160)
      Obs.beam({ ax=x, ay=-20, bx=x, by=PLAY_H+20, warn=0.55, fire=0.30, thick=24 + I*8 })
    end
  end
end

local function onHat(t, ev, target)
  local I = intensity(t)
  if I < 0.55 then return end
  if love.math.random() < 0.30 + I * 0.3 then
    -- twinkly small bullet from random edge
    local x, y = edgePoint()
    local dx, dy = dirToCenter(x + rand(-120, 120), y + rand(-80, 80))
    Obs.bullet({ x=x, y=y, dx=dx, dy=dy, speed=950, r=7, fire_t=0.18, life=2.5 })
  end
end

local function onChorusBeat(t, ev, target)
  -- 4-bar boundary effects: spawn a chaser occasionally during high intensity
  if intensity(t) > 0.75 and love.math.random() < 0.18 then
    Obs.chaser({
      x = (love.math.random() < 0.5) and -80 or PLAY_W + 80,
      y = rand(80, PLAY_H - 80),
      speed = 230 + intensity(t) * 80,
      r = 18,
      life = 8,
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
