-- Director: spawns obstacles in response to beat/onset events from src/beats.lua.
-- Difficulty ramps over song time so the experience builds.
local Obs = require "src.obstacles"

local function pickColour()
  if M and M.colourFor then return M.colourFor() end
  return nil
end

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

-- Presence over difficulty. Climax peaks at 0.12 -- another -50% cut on
-- top of the previous tuning. Most spawns are atmospheric.
local function intensity(t)
  if t < 6       then return 0.020 end                                  -- micro-intro
  if t < 13      then return 0.012 end                                  -- intro
  if t < 46      then return 0.025 + 0.020 * ((t - 13) / 33) end        -- verse 1
  if t < 78      then return 0.050 + 0.030 * ((t - 46) / 32) end        -- chorus 1
  if t < 111     then return 0.065 + 0.020 * ((t - 78) / 33) end        -- verse 2
  if t < 144     then return 0.085 + 0.035 * ((t - 111) / 33) end       -- chorus 2
  if t < 177     then return math.max(0.055, 0.120 - 0.050 * ((t-144)/33)) end -- bridge
  if t < 210     then return 0.105 + 0.015 * ((t - 177) / 33) end       -- final chorus
  return 0.045
end

-- Deterministic gate -- accept every Nth event by intensity. Cut another
-- 50 % from the previous tuning. Cap = 0.28, base multiplier softened.
local _gate_count = { kick = 0, snare = 0, hat = 0, beat = 0 }
local function spawnGate(typ, I, base)
  _gate_count[typ] = (_gate_count[typ] or 0) + 1
  local rate = math.min(0.28, base * (0.10 + 0.95 * I))
  if rate <= 0 then return false end
  local interval = math.max(1, math.floor(1 / rate + 0.5))
  return (_gate_count[typ] % interval) == 0
end

function M.resetGate()
  for k in pairs(_gate_count) do _gate_count[k] = 0 end
end

M.intensity = intensity

local function rand(a, b) return a + love.math.random() * (b - a) end

local function dirToCenter(x, y)
  local dx, dy = CENTER_X - x, CENTER_Y - y
  local m = math.sqrt(dx*dx + dy*dy)
  if m < 0.01 then return 0, 1 end
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
  if not spawnGate("kick", I, 0.45) then return end
  local r = love.math.random()
  -- expanded pool: bullets, triangles, rings, bursts, rain (multi-bullet
  -- curtain), and small bar combs at higher intensity.
  if r < 0.40 or I < 0.20 then
    local x, y = edgePoint()
    local dx, dy = dirToCenter(x + rand(-260,260), y + rand(-180,180))
    if love.math.random() < 0.45 then
      Obs.triangle({ x=x, y=y, dx=dx, dy=dy, speed=200 + I*70, fire_t=0.65, r=13, color=pickColour() })
    else
      Obs.bullet({ x=x, y=y, dx=dx, dy=dy, speed=190 + I*60, fire_t=0.65, r=12, color=pickColour() })
    end
  elseif r < 0.58 then
    local x = CENTER_X + rand(-340, 340)
    local y = CENTER_Y + rand(-210, 210)
    Obs.ring({ x=x, y=y, maxr=720, speed=160 + I*70, thick=14, warn=0.65, color=pickColour() })
  elseif r < 0.72 then
    local x = rand(360, PLAY_W-360)
    local y = rand(260, PLAY_H-260)
    local n = 4 + math.floor(I * 2)
    Obs.burst({ x=x, y=y, count=n, speed=140 + I*70, r=11, fire_t=0.65, angle=rand(0, math.pi), color=pickColour() })
  elseif r < 0.86 then
    Obs.rain({ count=8 + math.floor(I*3), gap_w=380 - I*60,
               gap_x=rand(360, PLAY_W-360),
               speed=210 + I*80, r=8, warn=0.70, color=pickColour() })
  else
    Obs.bar_comb({
      count = 3 + math.floor(I * 1.5),
      horizontal = love.math.random() < 0.55,
      speed = 240 + I * 80,
      thick = 26,
      stagger = 280,
      gap_idx = love.math.random(2, 3),
      from_dir = (love.math.random() < 0.5) and 1 or -1,
      warn = 0.85,
      life = 3.5,
      color = pickColour(),
    })
  end
end

local function onSnare(t, ev, target)
  local I = intensity(t)
  if I < 0.18 then return end
  if not spawnGate("snare", I, 0.36) then return end
  local r = love.math.random()
  -- expanded pool: spinner, fan, spikes (saw row), wave, beam, spiral.
  if r < 0.18 then
    local x = CENTER_X + rand(-220, 220)
    local y = CENTER_Y + rand(-160, 160)
    Obs.spinner({
      x=x, y=y,
      angle = rand(0, math.pi),
      spin = (love.math.random() < 0.5 and -1 or 1) * (0.30 + I * 0.30),
      length = 540,
      thick  = 18 + I * 3,
      arms   = 2,
      life   = 0.8 + I * 0.3,
      warn   = 0.85,
      color  = pickColour(),
    })
  elseif r < 0.34 then
    local x = CENTER_X + rand(-280, 280)
    local y = CENTER_Y + rand(-180, 180)
    Obs.fan({
      x = x, y = y,
      angle = rand(0, math.pi * 2),
      sweep = math.pi * (0.16 + 0.12 * (1 - I)),
      spin  = (love.math.random() < 0.5 and -1 or 1) * (0.75 + I * 0.75),
      length = 540 + 160 * I,
      life = 1.1 + I * 0.4,
      warn = 0.85,
      color = pickColour(),
    })
  elseif r < 0.50 then
    local edges = { "top", "bottom", "left", "right" }
    Obs.spikes({
      edge = edges[love.math.random(#edges)],
      count = 6 + math.floor(I * 3),
      w = 110, h = 110 + math.floor(I * 50),
      gap = 60,
      life = 0.45 + I * 0.15,
      warn = 0.95,
      color = pickColour(),
    })
  elseif r < 0.66 then
    Obs.spiral({
      x = CENTER_X + rand(-220, 220), y = CENTER_Y + rand(-160, 160),
      arms = 2 + math.floor(I * 1.5),
      count = 3 + math.floor(I * 1.5),
      speed = 160 + I * 80,
      r = 9, warn = 0.70,
      color = pickColour(),
    })
  elseif r < 0.78 then
    local horiz = love.math.random() < 0.6
    if horiz then
      Obs.wave({
        dir = (love.math.random() < 0.5) and "right" or "left",
        thick = 56,
        gap_y = rand(340, 740),
        gap_h = math.max(460, 600 - I * 80),
        speed = 200 + I * 60,
        warn = 0.95,
        color = pickColour(),
      })
    else
      Obs.wave({
        dir = (love.math.random() < 0.5) and "down" or "up",
        thick = 56,
        gap_y = rand(460, 1460),
        gap_h = math.max(460, 600 - I * 80),
        speed = 200 + I * 60,
        warn = 0.95,
        color = pickColour(),
      })
    end
  else
    local horiz = love.math.random() < 0.6
    if horiz then
      local y = rand(180, PLAY_H - 180)
      Obs.beam({ ax=-20, ay=y, bx=PLAY_W+20, by=y, warn=1.50, fire=0.30, thick=20 + I*3, color=pickColour() })
    else
      local x = rand(180, PLAY_W - 180)
      Obs.beam({ ax=x, ay=-20, bx=x, by=PLAY_H+20, warn=1.50, fire=0.30, thick=20 + I*3, color=pickColour() })
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
      warn = 0.55,
      target = target,
      color = pickColour(),
    })
  end
end

----------------------------------------------------------------------
-- Public entry points
----------------------------------------------------------------------

-- Optional colour picker injected by main.lua so each spawn gets a unique
-- per-obstacle hue from the world palette.
M.colourFor = nil

function M.handle(ev, t, target)
  if ev.type == "kick"  then onKick(t, ev, target)
  elseif ev.type == "snare" then onSnare(t, ev, target)
  elseif ev.type == "hat"   then onHat(t, ev, target)
  elseif ev.type == "beat"  then onChorusBeat(t, ev, target) end
end

return M
