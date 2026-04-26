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

-- Aligned to the actual song structure. Verses are sparse, chorus 1 brings
-- the first real wave of obstacles, the bridge cools off, and the final
-- chorus is the real climax. The outro is celebratory not punishing.
local function intensity(t)
  if t < 13      then return 0.04 end                                  -- intro: a whisper of activity
  if t < 46      then return 0.10 + 0.10 * ((t - 13) / 33) end         -- verse 1
  if t < 78      then return 0.22 + 0.16 * ((t - 46) / 32) end         -- chorus 1
  if t < 111     then return 0.30 + 0.10 * ((t - 78) / 33) end         -- verse 2
  if t < 144     then return 0.40 + 0.18 * ((t - 111) / 33) end        -- chorus 2 (heavy)
  if t < 177     then return math.max(0.22, 0.50 - 0.18 * ((t-144)/33)) end -- bridge cools off
  if t < 210     then return 0.45 + 0.10 * ((t - 177) / 33) end        -- final chorus (climax)
  return 0.20                                                          -- outro
end

-- Deterministic event gate: accept every Nth event of a given type. Phrasing
-- stays musical because every accepted event still lands exactly on a beat.
-- Random jitter is gone, so density is steady -- no dead-air swings.
local _gate_count = { kick = 0, snare = 0, hat = 0, beat = 0 }
local function spawnGate(typ, I, base)
  _gate_count[typ] = (_gate_count[typ] or 0) + 1
  -- effective rate scales with intensity: 0.4 at I=0, 1.0 at I=0.6+
  local rate = math.min(1.0, base * (0.45 + 1.05 * I))
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
  if not spawnGate("kick", I, 0.55) then return end
  local r = love.math.random()
  if r < 0.78 or I < 0.30 then
    -- single slow bullet from an edge aimed loosely at center
    local x, y = edgePoint()
    local dx, dy = dirToCenter(x + rand(-200,200), y + rand(-130,130))
    Obs.bullet({ x=x, y=y, dx=dx, dy=dy, speed=380 + I * 120, fire_t=0.50, r=10 })
  elseif r < 0.92 then
    -- expanding ring with a long warn
    local x = CENTER_X + rand(-360, 360)
    local y = CENTER_Y + rand(-220, 220)
    Obs.ring({ x=x, y=y, maxr=820, speed=300 + I * 130, thick=12, warn=0.50 })
  else
    -- small burst
    local x = rand(280, PLAY_W-280)
    local y = rand(180, PLAY_H-180)
    local n = 6 + math.floor(I * 4)
    Obs.burst({ x=x, y=y, count=n, speed=280 + I*120, r=10, fire_t=0.50, angle=rand(0, math.pi) })
  end
end

local function onSnare(t, ev, target)
  local I = intensity(t)
  if I < 0.20 then return end
  if not spawnGate("snare", I, 0.45) then return end
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
    -- wide-gap wave moving slowly. gap_y now respects playable bounds; the
    -- earlier 460..1460 range for vertical waves could spawn unreachable gaps.
    local horiz = love.math.random() < 0.6
    if horiz then
      Obs.wave({
        dir = (love.math.random() < 0.5) and "right" or "left",
        thick = 50,
        gap_y = rand(280, 820),                            -- inside [60..1080]
        gap_h = math.max(320, 460 - I * 80),
        speed = 360 + I * 100,
        warn = 0.65,
      })
    else
      Obs.wave({
        dir = (love.math.random() < 0.5) and "down" or "up",
        thick = 50,
        gap_y = rand(360, 1560),                           -- inside [60..1860]
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
      Obs.beam({ ax=-20, ay=y, bx=PLAY_W+20, by=y, warn=0.55, fire=0.24, thick=20 + I*5 })
    else
      local x = rand(160, PLAY_W - 160)
      Obs.beam({ ax=x, ay=-20, bx=x, by=PLAY_H+20, warn=0.55, fire=0.24, thick=20 + I*5 })
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
