-- Synthesized SFX. Generated programmatically at boot so we don't ship
-- audio samples. Each call returns a Source you can :play() repeatedly
-- via :stop() then :play(), or use :clone() for overlapping playback.
local M = {}

local RATE = 44100

local function newBuffer(seconds)
  local n = math.floor(seconds * RATE)
  return love.sound.newSoundData(n, RATE, 16, 1), n
end

-- Dash whoosh -- short downward freq sweep with exponential decay.
function M.makeDash()
  local sd, n = newBuffer(0.16)
  for i = 0, n - 1 do
    local k = i / (n - 1)
    local f = 720 * (1 - k * 0.55)                  -- 720 Hz -> ~325 Hz
    local env = math.exp(-3.0 * k)
    local s = math.sin(2 * math.pi * f * (i / RATE)) * env * 0.55
    -- pinch of high-noise dust
    s = s + (love.math.random() - 0.5) * env * 0.18
    if s > 1 then s = 1 elseif s < -1 then s = -1 end
    sd:setSample(i, s)
  end
  local src = love.audio.newSource(sd, "static")
  src:setVolume(0.65)
  return src
end

-- Hit shatter -- band-passed noise burst with a quick low-thump.
function M.makeHit()
  local sd, n = newBuffer(0.32)
  -- carry one sample of state for a 1-pole high-pass on the noise so it cracks
  local prev_in, prev_out = 0, 0
  local hp_a = 0.92
  for i = 0, n - 1 do
    local k = i / (n - 1)
    local env = math.exp(-7.5 * k)
    -- high-pass white noise crackle
    local x = (love.math.random() - 0.5) * 2
    local y = hp_a * (prev_out + x - prev_in)
    prev_in, prev_out = x, y
    -- low thump (140 Hz, fast decay)
    local thump = math.sin(2 * math.pi * 140 * (i / RATE)) * math.exp(-22 * k) * 0.55
    local s = (y * 0.55 + thump) * env
    if s > 1 then s = 1 elseif s < -1 then s = -1 end
    sd:setSample(i, s)
  end
  local src = love.audio.newSource(sd, "static")
  src:setVolume(0.85)
  return src
end

-- UI confirm tick -- short pure tone.
function M.makeTick()
  local sd, n = newBuffer(0.06)
  for i = 0, n - 1 do
    local k = i / (n - 1)
    local env = math.exp(-12 * k)
    local s = math.sin(2 * math.pi * 880 * (i / RATE)) * env * 0.4
    sd:setSample(i, s)
  end
  local src = love.audio.newSource(sd, "static")
  src:setVolume(0.55)
  return src
end

-- Revive stinger -- ascending harmonic swell.
function M.makeRevive()
  local sd, n = newBuffer(0.55)
  for i = 0, n - 1 do
    local k = i / (n - 1)
    local f = 220 + 660 * k                          -- rising
    local env = (1 - math.exp(-9 * k)) * math.exp(-1.5 * k)
    local s = (math.sin(2 * math.pi * f * (i / RATE))
            +  math.sin(2 * math.pi * f * 2 * (i / RATE)) * 0.45
            +  math.sin(2 * math.pi * f * 3 * (i / RATE)) * 0.25) * env * 0.30
    if s > 1 then s = 1 elseif s < -1 then s = -1 end
    sd:setSample(i, s)
  end
  local src = love.audio.newSource(sd, "static")
  src:setVolume(0.70)
  return src
end

-- Death stinger -- descending detuned tone.
function M.makeDeath()
  local sd, n = newBuffer(0.70)
  for i = 0, n - 1 do
    local k = i / (n - 1)
    local f = 320 * (1 - k * 0.6)
    local env = math.exp(-2.0 * k)
    local s = (math.sin(2 * math.pi * f * (i / RATE))
            +  math.sin(2 * math.pi * (f * 1.012) * (i / RATE)) * 0.6) * env * 0.32
    if s > 1 then s = 1 elseif s < -1 then s = -1 end
    sd:setSample(i, s)
  end
  local src = love.audio.newSource(sd, "static")
  src:setVolume(0.65)
  return src
end

-- Cyber lobby beat -- a short procedurally-generated loop that plays in the
-- menu / lobby / character / shop states. Made to be neutral background music
-- so it doesn't compete with the Bad Apple track during gameplay.
function M.makeLobbyLoop()
  local bpm = 124
  local beat_s = 60 / bpm                 -- ~0.484 s
  local bars = 2
  local total = bars * 4 * beat_s         -- 8 beats, ~3.87 s
  local n = math.floor(total * RATE)
  local sd = love.sound.newSoundData(n, RATE, 16, 1)

  -- 1-pole high-pass state for the hi-hat noise burst
  local hp_a = 0.94
  local hp_prev_in, hp_prev_out = 0, 0

  -- arp note progression (each beat picks one) -- minor 7th-ish
  local notes = { 220.0, 261.6, 329.6, 261.6, 220.0, 196.0, 261.6, 293.7 }

  for i = 0, n - 1 do
    local t = i / RATE
    local beat_pos = t / beat_s             -- absolute beat count
    local frac = beat_pos - math.floor(beat_pos)
    local beat_idx = math.floor(beat_pos) % 8
    local s = 0

    -- kick on every quarter (4-on-the-floor)
    if frac < 0.12 then
      local k = frac / 0.12
      local env = math.exp(-9 * k)
      s = s + math.sin(2 * math.pi * (130 - 80 * k) * t) * env * 0.55
      -- a soft thump tail
      s = s + math.sin(2 * math.pi * (60) * t) * env * env * 0.18
    end

    -- snap on every other beat (counts 2 and 4)
    if (beat_idx % 2) == 1 and frac < 0.06 then
      local k = frac / 0.06
      local env = math.exp(-22 * k)
      local x  = (love.math.random() - 0.5) * 2
      local y  = hp_a * (hp_prev_out + x - hp_prev_in)
      hp_prev_in, hp_prev_out = x, y
      s = s + y * env * 0.28
    else
      -- keep filter state moving smoothly
      local x  = (love.math.random() - 0.5) * 0.05
      local y  = hp_a * (hp_prev_out + x - hp_prev_in)
      hp_prev_in, hp_prev_out = x, y
    end

    -- hi-hat on the off-beat 8th
    if frac > 0.50 and frac < 0.55 then
      local k = (frac - 0.50) / 0.05
      local env = math.exp(-32 * k)
      s = s + (love.math.random() - 0.5) * env * 0.20
    end

    -- bass on each beat -- tight pluck following the note progression
    if frac < 0.40 then
      local k = frac / 0.40
      local env = math.exp(-4 * k)
      local f = notes[beat_idx + 1] * 0.5      -- octave below for sub
      s = s + math.sin(2 * math.pi * f * t) * env * 0.20
    end

    -- arp pluck on the off 16th of each beat -- adds a bit of melody
    if frac > 0.72 and frac < 0.82 then
      local k = (frac - 0.72) / 0.10
      local env = math.exp(-14 * k)
      local f = notes[beat_idx + 1]
      local f2 = notes[((beat_idx + 2) % 8) + 1]
      s = s + (math.sin(2 * math.pi * f * t)
            +  math.sin(2 * math.pi * f2 * t) * 0.55) * env * 0.10
    end

    if s >  1 then s =  1 end
    if s < -1 then s = -1 end
    sd:setSample(i, s)
  end

  local src = love.audio.newSource(sd, "static")
  src:setLooping(true)
  src:setVolume(0.40)
  return src
end

-- Helpers for one-shot polyphonic playback.
function M.play(src)
  if not src then return end
  if src:isPlaying() then
    local c = src:clone()
    c:play()
  else
    src:play()
  end
end

return M
