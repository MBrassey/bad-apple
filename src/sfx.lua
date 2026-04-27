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

-- Lobby ambient pad. Slow synthwave-ish loop tuned for the menu / lobby --
-- chord pad in i-VI-III-VII (Am, F, C, G), a gentle sub-bass following the
-- root, soft kick on 1, brushy hi-hat ride, and a slow arpeggio. Designed
-- to sit *underneath* the player's attention rather than punch through, so
-- the wardrobe / lobby chrome feels like a vibe instead of a gym.
function M.makeLobbyLoop()
  local bpm = 88                          -- slower, more atmospheric
  local beat_s = 60 / bpm                 -- ~0.682 s
  local bars = 4
  local total = bars * 4 * beat_s         -- 16 beats, ~10.9 s
  local n = math.floor(total * RATE)
  local sd = love.sound.newSoundData(n, RATE, 16, 1)

  -- chord progression: Am -- F -- C -- G, one per bar.
  -- frequencies for chord tones (Hz) -- root, third, fifth, seventh
  local CHORDS = {
    { root = 110.00, tones = { 110.00, 130.81, 164.81, 196.00 } },  -- Am7
    { root =  87.31, tones = {  87.31, 110.00, 130.81, 164.81 } },  -- Fmaj7
    { root =  65.41, tones = { 130.81, 164.81, 196.00, 246.94 } },  -- C
    { root =  98.00, tones = {  98.00, 123.47, 146.83, 196.00 } },  -- G
  }

  -- arpeggio pattern over the bar (8 sixteenths of triplets)
  local ARP_INDEX = { 1, 2, 3, 4, 3, 2, 4, 3 }
  -- 1-pole high-pass state for the hat noise
  local hp_a = 0.93
  local hp_prev_in, hp_prev_out = 0, 0

  for i = 0, n - 1 do
    local t = i / RATE
    local global_beat = t / beat_s
    local bar_idx = math.floor(global_beat / 4) % #CHORDS
    local chord = CHORDS[bar_idx + 1]
    local beat_in_bar = global_beat - math.floor(global_beat / 4) * 4
    local beat_idx = math.floor(beat_in_bar)
    local frac = beat_in_bar - beat_idx
    local s = 0

    -- chord pad: sustained sines on all four chord tones, slow vibrato
    -- via a low-rate amplitude wobble so the pad breathes
    local pad_env = 0.5 + 0.5 * math.sin(t * 0.6)        -- 0..1 slow swell
    local pad_amp = (0.10 + 0.05 * pad_env)
    for _, f in ipairs(chord.tones) do
      s = s + math.sin(2 * math.pi * f * t) * pad_amp
      -- octave-up shimmer at lower amplitude
      s = s + math.sin(2 * math.pi * f * 2 * t) * pad_amp * 0.18
    end

    -- crossfade between chords during the last 0.5 s of each bar so it
    -- doesn't snap. Fade-out current, fade-in next.
    do
      local bar_pos = (global_beat / 4) - math.floor(global_beat / 4)
      if bar_pos > 0.875 then
        local cf = (bar_pos - 0.875) / 0.125
        local nxt = CHORDS[((bar_idx + 1) % #CHORDS) + 1]
        for _, f in ipairs(nxt.tones) do
          s = s + math.sin(2 * math.pi * f * t) * pad_amp * cf
        end
      end
    end

    -- soft kick on beat 1 of each bar
    if beat_idx == 0 and frac < 0.18 then
      local k = frac / 0.18
      local env = math.exp(-7 * k)
      s = s + math.sin(2 * math.pi * (95 - 55 * k) * t) * env * 0.40
    end

    -- brushy hat on every off-beat (8th notes)
    if frac > 0.45 and frac < 0.52 then
      local k = (frac - 0.45) / 0.07
      local env = math.exp(-22 * k)
      local x  = (love.math.random() - 0.5) * 2
      local y  = hp_a * (hp_prev_out + x - hp_prev_in)
      hp_prev_in, hp_prev_out = x, y
      s = s + y * env * 0.06
    end

    -- sub-bass following the chord root, half-time pulse
    if (beat_idx % 2) == 0 and frac < 0.55 then
      local k = frac / 0.55
      local env = math.exp(-2.5 * k)
      s = s + math.sin(2 * math.pi * chord.root * 0.5 * t) * env * 0.16
    end

    -- arpeggio: pluck on each 8th-note step through ARP_INDEX, picking a
    -- chord tone. Soft sine with a quick decay envelope.
    do
      local step = math.floor(beat_in_bar * 2) + 1   -- 1..8
      local step_frac = (beat_in_bar * 2) - math.floor(beat_in_bar * 2)
      if step_frac < 0.30 then
        local k = step_frac / 0.30
        local env = math.exp(-9 * k)
        local tone_idx = ARP_INDEX[((step - 1) % #ARP_INDEX) + 1]
        local f = chord.tones[tone_idx] * 2          -- octave up for arp
        s = s + math.sin(2 * math.pi * f * t) * env * 0.06
      end
    end

    if s >  1 then s =  1 end
    if s < -1 then s = -1 end
    sd:setSample(i, s)
  end

  local src = love.audio.newSource(sd, "static")
  src:setLooping(true)
  src:setVolume(0.42)
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
