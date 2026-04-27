-- Bad Apple // Beat Dash
-- Just-Shapes-and-Beats-style dodge game played on top of the original Bad Apple
-- shadow-art video. The silhouette plays as the background and is itself a
-- deadly obstacle: any pixel of the silhouette overlapping the player deals
-- damage. On top of that, bullets / waves / beams / rings / spinners / chasers
-- spawn on real beat / kick / snare / hat events extracted from the audio.
--
-- Death lifecycle:
--   alive -> dying  ("IT'S OVER" fade-in, body shatters into shards)
--   dying -> revive ("IT'S NOT OVER" hit, screen ripple, body reforms)
--   revive -> play  (resume from the exact death point with full HP and i-frames)
--
-- Achievements, FX, and lobby presence are emitted via [[LOVEWEB_*]] magic
-- prints per the integration guide.
local Video      = require "src.video"
local Collision  = require "src.collision"
local Beats      = require "src.beats"
local Player     = require "src.player"
local Obstacles  = require "src.obstacles"
local Director   = require "src.director"
local Glow       = require "src.glow"
local Save       = require "src.save"
local Net        = require "src.multiplayer"
local SFX        = require "src.sfx"
local Mosaic     = require "src.mosaic"
local Apples     = require "src.apples"
local Lobby      = require "src.lobby"
local Character  = require "src.character"

local DESIGN_W, DESIGN_H = 1920, 1080

-- Player colour palette. The first 4 are free; the others unlock as you
-- complete the song. Save.state.completions is the gate.
local PLAYER_PALETTE = {
  { name = "neon pink",  rgb = { 1.00, 0.40, 0.72 }, unlock_at = 0 },
  { name = "cyan",       rgb = { 0.30, 0.92, 1.00 }, unlock_at = 0 },
  { name = "violet",     rgb = { 0.80, 0.55, 1.00 }, unlock_at = 0 },
  { name = "amber",      rgb = { 1.00, 0.80, 0.40 }, unlock_at = 0 },
  { name = "lime",       rgb = { 0.55, 1.00, 0.50 }, unlock_at = 1 },
  { name = "ember",      rgb = { 1.00, 0.50, 0.35 }, unlock_at = 2 },
  { name = "sky",        rgb = { 0.55, 0.85, 1.00 }, unlock_at = 3 },
  { name = "ivory",      rgb = { 0.95, 0.95, 0.95 }, unlock_at = 4 },
  { name = "void",       rgb = { 0.30, 0.20, 0.55 }, unlock_at = 5 },
  { name = "blood",      rgb = { 0.90, 0.10, 0.20 }, unlock_at = 6 },
  { name = "phantom",    rgb = { 0.60, 1.00, 0.85 }, unlock_at = 7 },
  { name = "gold",       rgb = { 1.00, 0.85, 0.10 }, unlock_at = 8 },
}

local function paletteUnlocked(idx)
  local p = PLAYER_PALETTE[idx]
  if not p then return false end
  return (Save.state.completions or 0) >= (p.unlock_at or 0)
end

-- Auras: extra visual rings you can equip from the character room. Unlock by
-- completing the song. Equipped via Save.state.aura_id (1 = default).
local AURAS = {
  { id = "default", name = "Default Halo",   unlock_at = 0 },
  { id = "ring",    name = "Spinning Ring",  unlock_at = 2 },
  { id = "twin",    name = "Twin Echoes",    unlock_at = 4 },
  { id = "starlit", name = "Starlit Halo",   unlock_at = 6 },
}

local function auraUnlocked(idx)
  local a = AURAS[idx]
  if not a then return false end
  return (Save.state.completions or 0) >= (a.unlock_at or 0)
end

local function playerColor()
  local idx = (Save and Save.state and Save.state.player_color) or 1
  -- guard: if the saved index is somehow locked, fall back to the first
  if Save and Save.state and not paletteUnlocked(idx) then idx = 1 end
  local p = PLAYER_PALETTE[idx] or PLAYER_PALETTE[1]
  return p.rgb
end

-- ─── globals ──────────────────────────────────────────────────────────
local world          -- offscreen canvas at design resolution
local source         -- audio source (Bad Apple ogg)
local audio_t = 0    -- current audio time in seconds
local state = "boot" -- boot | loading | menu | play | paused | dying | reviving | dead | win
local boot_progress = 0
local boot_msg = "loading bad apple..."
local font_huge, font_big, font_med, font_small, font_hud
local checkpoint_time = 0
local last_save_t = 0
local shake_t, shake_mag = 0, 0
local flash_t, flash_color = 0, {1,1,1,1}
local accent = {1.0, 0.40, 0.72}
local bg_pulse = 0
local sil_glow = 0
local kick_pulse = 0
local elapsed_play = 0
local LOOP = false
local sil_dx, sil_dy, sil_dw, sil_dh, sil_scale = 0,0,0,0,1
local victory_shown = false

-- SFX cache (synthesized at boot)
local snd_dash, snd_hit, snd_tick, snd_revive, snd_death

-- hit-stop / dt scaling for impact frames
local hit_stop_t = 0
-- screen-edge tint pulses (red on hit, cyan on close-call)
local edge_tint_r = 0
local edge_tint_c = 0
-- music duck during dying (0..1, music volume multiplier)
local music_duck = 1.0

-- death sequence timers
local dying_t   = 0   -- "IT'S OVER" duration
local revive_t  = 0   -- "IT'S NOT OVER" duration
local death_pos = { x = 0, y = 0 }
local death_audio_t = 0
local _last_mood_t = nil
local revives_remaining = 1

-- shop state
local shop_idx = 1

-- character / wardrobe preview avatar
local preview_player = nil
local function refreshPreviewPlayer()
  local hp_bonus = (Save.state.upgrades and Save.state.upgrades.hp) and 1 or 0
  preview_player = Player.new(DESIGN_W * 0.5, DESIGN_H * 0.5 + 40, nil, hp_bonus)
  if Save.state.upgrades and Save.state.upgrades.sparkles then preview_player.sparkle_boost = true end
  if Save.state.upgrades and Save.state.upgrades.halo then preview_player.halo_boost = true end
  local aidx = Save.state.aura_id or 1
  preview_player.aura_id = (AURAS[aidx] and AURAS[aidx].id) or "default"
end
local SHOP_ITEMS = {
  { key="sparkles",   title="Bigger Sparkle Trail", desc="Doubles trail density + life",        cost=8  },
  { key="halo",       title="Brighter Aura",        desc="Larger glow halo around the body",    cost=10 },
  { key="dash",       title="Quicker Dash",         desc="25% shorter dash cooldown",           cost=15 },
  { key="magnet",     title="Apple Magnet",         desc="Apples drift toward you",             cost=18 },
  { key="hp",         title="Extra Heart",          desc="One additional HP fragment",          cost=25 },
  { key="magnet2",    title="Greater Magnet",       desc="Apple pull range nearly doubles",     cost=20 },
  { key="revive2",    title="Second Wind",          desc="One additional auto-revive per run",  cost=30 },
  { key="score",      title="Sharper Score",        desc="+25% score on every run",             cost=35 },
  { key="apple_rate", title="Orchard's Bounty",     desc="Apples spawn 30% more often",         cost=40 },
}

-- gameplay metrics
local combo = 0       -- consecutive obstacle dodges
local best_combo = 0
local score = 0
local run_loops = 0
local close_calls = 0

-- achievements claimed this session (avoid spam)
local _claimed = {}
local function ach(key)
  if _claimed[key] then return end
  _claimed[key] = true
  print("[[LOVEWEB_ACH]]unlock " .. key)
end

-- ─── runtime FX magic-prints ─────────────────────────────────────────
local function fxFlash(color, ms) print(string.format("[[LOVEWEB_FX]]flash %s %d", color, math.min(2500, ms))) end
local function fxShake(intensity, ms) print(string.format("[[LOVEWEB_FX]]shake %.2f %d", math.min(1.0, intensity), math.min(2500, ms))) end
local function fxMood(color, intensity) print(string.format("[[LOVEWEB_FX]]mood %s %.2f", color, math.min(1.0, intensity))) end
local function fxRipple(color, x01, y01, ms) print(string.format("[[LOVEWEB_FX]]ripple %s %.2f %.2f %d", color, x01, y01, math.min(2500, ms))) end
local function fxShatter(intensity, ms) print(string.format("[[LOVEWEB_FX]]shatter %.2f %d", math.min(1.0, intensity), math.min(2500, ms))) end

local function colorHex(r, g, b)
  return string.format("#%02x%02x%02x", math.floor(r*255), math.floor(g*255), math.floor(b*255))
end

-- ─── glitch shader ───────────────────────────────────────────────────
local glitch_shader_code = [[
extern number amount;     // 0..1
extern number time_;
vec4 effect(vec4 c, Image t, vec2 uv, vec2 sc) {
  float band = step(0.96, fract(uv.y * 12.0 + time_ * 0.7));
  float ox = (band * (sin(uv.y * 80.0 + time_ * 8.0) * 0.5)) * amount * 0.06;
  float r = Texel(t, uv + vec2(ox + amount * 0.012, 0.0)).r;
  float g = Texel(t, uv).g;
  float b = Texel(t, uv - vec2(ox + amount * 0.012, 0.0)).b;
  return vec4(r, g, b, 1.0) * c;
}
]]
local glitch_shader

-- ─── audio sync helpers ──────────────────────────────────────────────
local function audioTime()
  if not source then return 0 end
  local ok, t = pcall(source.tell, source, "seconds")
  if ok and t then return t end
  return 0
end

local function startSongAt(fromTime)
  fromTime = fromTime or 0
  if source:isPlaying() then source:stop() end
  pcall(source.seek, source, fromTime, "seconds")
  source:setVolume(Save.state.volume or 0.85)
  source:play()
  audio_t = fromTime
  Beats.reset(fromTime)
  Obstacles.reset()
  elapsed_play = 0
end

-- ─── lifecycle ───────────────────────────────────────────────────────
local player

local function playBounds()
  return { x = 60, y = 60, w = DESIGN_W - 120, h = DESIGN_H - 120 }
end

local function newRun(fromTime)
  local hp_bonus = (Save.state.upgrades and Save.state.upgrades.hp) and 1 or 0
  player = Player.new(DESIGN_W * 0.5, DESIGN_H * 0.5, playBounds(), hp_bonus)
  startSongAt(fromTime or 0)
  Save.state.runs = (Save.state.runs or 0) + 1
  Save.write()
  state = "play"
  checkpoint_time = math.max(checkpoint_time, fromTime or 0)
  combo = 0
  score = 0
  victory_shown = false
  -- per-run variation: shuffle the random seed and the mosaic hue offset so
  -- every run looks and plays slightly different even though it's the same
  -- song / same beat events.
  love.math.setRandomSeed(os.time() + Save.state.runs * 9973)
  Mosaic.setHueOffset(love.math.random())
  Apples.reset()
  Apples.player_ref = player
  Apples.magnet = Save.state.upgrades and Save.state.upgrades.magnet or false
  Apples.magnet2 = Save.state.upgrades and Save.state.upgrades.magnet2 or false
  Apples.spawn_boost = Save.state.upgrades and Save.state.upgrades.apple_rate or false
  -- second-wind upgrade: two revives per run instead of one
  revives_remaining = (Save.state.upgrades and Save.state.upgrades.revive2) and 2 or 1
  if Save.state.upgrades and Save.state.upgrades.dash then
    player.dash_cooldown_mul = 0.75
  end
  if Save.state.upgrades and Save.state.upgrades.sparkles then
    player.sparkle_boost = true
  end
  if Save.state.upgrades and Save.state.upgrades.halo then
    player.halo_boost = true
  end
  -- equipped aura cosmetic (id string fed straight into Player draw)
  local aidx = Save.state.aura_id or 1
  player.aura_id = (AURAS[aidx] and AURAS[aidx].id) or "default"
end

-- Begin a soft revive: keep player position, full HP, brief i-frames, song
-- resumes from where they died.
local function revive()
  player:revive(death_pos.x, death_pos.y)
  -- rewind 0.6 s so the player has runway to react after revive; this is
  -- larger than the maximum obstacle warn (0.65) plus a small margin so
  -- events that already fired pre-death aren't re-fired on resume
  startSongAt(math.max(0, death_audio_t - 0.6))
  music_duck = 1.0
  if source then source:setVolume(Save.state.volume or 0.85) end
  Director.resetGate()
  state = "play"
  combo = 0
  ach("second_chance")
  SFX.play(snd_revive)
  fxRipple("#ffffff", death_pos.x / DESIGN_W, death_pos.y / DESIGN_H, 850)
  fxFlash("#ffffff", 260)
end

local DEBUG_AUTORUN = (os.getenv and os.getenv("BADAPPLE_AUTORUN")) or nil
local DEBUG_QUIT_AT = tonumber((os.getenv and os.getenv("BADAPPLE_QUIT_AT")) or "")
local _wall_t0

function love.load()
  love.graphics.setDefaultFilter("linear", "linear", 1)
  love.window.setMode(1280, 720, { resizable = false, vsync = 1, msaa = 0, highdpi = true })
  love.window.setTitle("Bad Apple // Beat Dash")

  world = love.graphics.newCanvas(DESIGN_W, DESIGN_H)
  world:setFilter("linear", "linear")
  Glow.load(DESIGN_W, DESIGN_H)
  Mosaic.load()
  Lobby.load()
  glitch_shader = love.graphics.newShader(glitch_shader_code)

  font_huge  = love.graphics.newFont(150)
  font_big   = love.graphics.newFont(96)
  font_med   = love.graphics.newFont(40)
  font_small = love.graphics.newFont(22)
  font_hud   = love.graphics.newFont(28)

  Save.load()
  if Save.state.volume == nil then Save.state.volume = 0.85 end
  if Save.state.player_color == nil then Save.state.player_color = 1 end
  if Save.state.apples == nil then Save.state.apples = 0 end
  if Save.state.completions == nil then Save.state.completions = 0 end
  if Save.state.aura_id == nil then Save.state.aura_id = 1 end
  if Save.state.last_unlock == nil then Save.state.last_unlock = nil end
  if Save.state.upgrades == nil then Save.state.upgrades = {} end
  -- ensure each upgrade key exists with a default; prevents nil-deref if a
  -- save predates a newly-added upgrade
  for _, k in ipairs({ "sparkles","halo","dash","magnet","hp",
                       "magnet2","revive2","score","apple_rate" }) do
    if Save.state.upgrades[k] == nil then Save.state.upgrades[k] = false end
  end
  Net.load()
  _wall_t0 = love.timer.getTime()
  state = "loading"
end

local _boot
local function loadStep()
  _boot = _boot or { phase = 1 }
  if _boot.phase == 1 then
    boot_msg = "decoding beats..."
    Beats.load(); _boot.phase = 2; boot_progress = 0.05; return false
  elseif _boot.phase == 2 then
    boot_msg = "loading silhouette mask..."
    Collision.load(); _boot.phase = 3; boot_progress = 0.10; return false
  elseif _boot.phase == 3 then
    boot_msg = "loading frames..."
    Video.beginLoad()
    _boot.phase = 4; return false
  elseif _boot.phase == 4 then
    -- load 2 sheets per frame -> ~0.5s total, screen stays responsive
    local done = Video.loadStep(2)
    boot_progress = 0.10 + 0.85 * Video.loadProgress()
    if done then _boot.phase = 5 end
    return false
  elseif _boot.phase == 5 then
    boot_msg = "tuning audio..."
    source = love.audio.newSource("assets/badapple.ogg", "stream")
    source:setLooping(false)
    source:setVolume(Save.state.volume or 0.85)
    _boot.phase = 6; return false
  elseif _boot.phase == 6 then
    boot_msg = "synthesizing sfx..."
    snd_dash   = SFX.makeDash()
    snd_hit    = SFX.makeHit()
    snd_tick   = SFX.makeTick()
    snd_revive = SFX.makeRevive()
    snd_death  = SFX.makeDeath()
    boot_progress = 1.0; _boot.phase = 7; return true
  end
  return true
end

-- ─── input ───────────────────────────────────────────────────────────
function love.keypressed(key)
  if state == "menu" then
    if     key == "return" or key == "space" then SFX.play(snd_tick); newRun(0)
    elseif key == "c" and (Save.state.last_checkpoint or 0) > 5 then SFX.play(snd_tick); newRun(Save.state.last_checkpoint)
    elseif key == "l" then SFX.play(snd_tick); LOOP = not LOOP
    elseif key == "left"  or key == "a" then
      SFX.play(snd_tick)
      Save.state.player_color = ((Save.state.player_color - 2) % #PLAYER_PALETTE) + 1
      Save.write()
    elseif key == "right" or key == "d" then
      SFX.play(snd_tick)
      Save.state.player_color = (Save.state.player_color % #PLAYER_PALETTE) + 1
      Save.write()
    elseif key == "b" then SFX.play(snd_tick); state = "shop"; shop_idx = 1
    elseif key == "m" then
      SFX.play(snd_tick)
      if not Net.enabled then Net.tryJoinPublic() end
      -- enter the cyber lobby state with a fresh player avatar
      local hp_bonus = (Save.state.upgrades and Save.state.upgrades.hp) and 1 or 0
      player = Player.new(DESIGN_W * 0.5, DESIGN_H * 0.5,
                          { x = 80, y = 100, w = DESIGN_W - 160, h = DESIGN_H - 200 },
                          hp_bonus)
      if Save.state.upgrades and Save.state.upgrades.sparkles then player.sparkle_boost = true end
      if Save.state.upgrades and Save.state.upgrades.halo then player.halo_boost = true end
      if Save.state.upgrades and Save.state.upgrades.dash then player.dash_cooldown_mul = 0.75 end
      Lobby.enter(player)
      state = "lobby"
    elseif key == "-" or key == "kp-" then
      Save.state.volume = math.max(0, (Save.state.volume or 0.85) - 0.05); Save.write()
    elseif key == "=" or key == "+" or key == "kp+" then
      Save.state.volume = math.min(1, (Save.state.volume or 0.85) + 0.05); Save.write()
    elseif key == "escape" then love.event.quit() end
  elseif state == "play" then
    if key == "space" or key == "lshift" or key == "rshift" then
      if player:tryDash() then
        ach("first_dash")
        SFX.play(snd_dash)
        fxRipple(colorHex(accent[1], accent[2], accent[3]), player.x / DESIGN_W, player.y / DESIGN_H, 320)
        if player.dashes >= 100 then ach("dasher") end
      end
    elseif key == "escape" or key == "p" then
      if source then source:pause() end
      state = "paused"
    end
  elseif state == "paused" then
    if key == "escape" or key == "p" then
      if source then source:play() end
      state = "play"
    elseif key == "q" then
      if source then source:stop() end
      state = "menu"
    end
  elseif state == "dying" then
    -- accept R/Enter to skip the over screen and revive immediately
    if key == "return" or key == "space" or key == "r" then
      state = "reviving"; revive_t = 0
    end
  elseif state == "reviving" then
    -- skip handled in update once timer elapses
  elseif state == "dead" then
    if key == "r" or key == "return" then newRun(checkpoint_time)
    elseif key == "n" then newRun(0)
    elseif key == "b" then state = "shop"; SFX.play(snd_tick)
    elseif key == "escape" then state = "menu" end
  elseif state == "win" then
    if key == "return" or key == "space" then
      if LOOP then run_loops = run_loops + 1; if run_loops >= 1 then ach("loop_lover") end; newRun(0) else state = "menu" end
    elseif key == "b" then state = "shop"; SFX.play(snd_tick)
    elseif key == "escape" then state = "menu"
    elseif key == "l" then LOOP = not LOOP end
  elseif state == "lobby" then
    if key == "space" or key == "lshift" or key == "rshift" then
      if player and player:tryDash() then SFX.play(snd_dash) end
    elseif key == "escape" or key == "m" then
      Net.leave()
      SFX.play(snd_tick)
      state = "menu"
    end
  elseif state == "character" then
    if key == "left" or key == "a" then
      SFX.play(snd_tick)
      -- skip locked palette entries
      local n, i = #PLAYER_PALETTE, Save.state.player_color
      for _ = 1, n do
        i = ((i - 2) % n) + 1
        if paletteUnlocked(i) then break end
      end
      Save.state.player_color = i
      Save.write()
    elseif key == "right" or key == "d" then
      SFX.play(snd_tick)
      local n, i = #PLAYER_PALETTE, Save.state.player_color
      for _ = 1, n do
        i = (i % n) + 1
        if paletteUnlocked(i) then break end
      end
      Save.state.player_color = i
      Save.write()
    elseif key == "up" or key == "w" then
      SFX.play(snd_tick)
      local n, i = #AURAS, Save.state.aura_id or 1
      for _ = 1, n do
        i = ((i - 2) % n) + 1
        if auraUnlocked(i) then break end
      end
      Save.state.aura_id = i; Save.write()
    elseif key == "down" or key == "s" then
      SFX.play(snd_tick)
      local n, i = #AURAS, Save.state.aura_id or 1
      for _ = 1, n do
        i = (i % n) + 1
        if auraUnlocked(i) then break end
      end
      Save.state.aura_id = i; Save.write()
    elseif key == "return" or key == "space" then
      SFX.play(snd_tick); newRun(0)
    elseif key == "b" then
      SFX.play(snd_tick); state = "shop"; shop_idx = 1
    elseif key == "m" then
      SFX.play(snd_tick)
      if not Net.enabled then Net.tryJoinPublic() end
      local hp_bonus = (Save.state.upgrades and Save.state.upgrades.hp) and 1 or 0
      player = Player.new(DESIGN_W * 0.5, DESIGN_H * 0.5,
                          { x = 80, y = 100, w = DESIGN_W - 160, h = DESIGN_H - 200 },
                          hp_bonus)
      if Save.state.upgrades and Save.state.upgrades.sparkles then player.sparkle_boost = true end
      if Save.state.upgrades and Save.state.upgrades.halo then player.halo_boost = true end
      if Save.state.upgrades and Save.state.upgrades.dash then player.dash_cooldown_mul = 0.75 end
      Lobby.enter(player)
      state = "lobby"
    elseif key == "l" then
      SFX.play(snd_tick); LOOP = not LOOP
    elseif key == "escape" then
      SFX.play(snd_tick); state = "menu"
    end
  elseif state == "shop" then
    if key == "up" or key == "w" then
      shop_idx = ((shop_idx - 2) % #SHOP_ITEMS) + 1; SFX.play(snd_tick)
    elseif key == "down" or key == "s" then
      shop_idx = (shop_idx % #SHOP_ITEMS) + 1; SFX.play(snd_tick)
    elseif key == "return" or key == "space" then
      local item = SHOP_ITEMS[shop_idx]
      if not Save.state.upgrades[item.key] and (Save.state.apples or 0) >= item.cost then
        Save.state.apples = Save.state.apples - item.cost
        Save.state.upgrades[item.key] = true
        Save.write()
        SFX.play(snd_revive)
        fxFlash("#ffffff", 220)
      end
    elseif key == "escape" or key == "b" then
      state = "menu"; SFX.play(snd_tick)
      if source then source:pause() end
    end
  end
end

-- ─── update ──────────────────────────────────────────────────────────
local function fireEvent(ev)
  if ev.type == "kick" then
    kick_pulse = math.min(1, kick_pulse + 0.6)
    bg_pulse   = math.min(1, bg_pulse + 0.5)
    if love.math.random() < 0.10 then fxShake(0.45, 200) end
  elseif ev.type == "snare" then
    bg_pulse = math.min(1, bg_pulse + 0.35)
  elseif ev.type == "beat" then
    bg_pulse = math.min(1, bg_pulse + 0.20)
  end
  Director.handle(ev, audio_t, player)
end

-- The silhouette is now atmosphere only -- it doesn't deal damage. Damage
-- only comes from the explicit beat-spawned obstacles (bullets, beams,
-- waves, rings, spinners, chasers). Collision.lua remains loaded in case
-- a future obstacle wants to align its hot-zones to the silhouette mask.

local function checkAchievements()
  if not _claimed["intro_clear"]    and audio_t > 30  then ach("intro_clear")    end
  if not _claimed["halfway"]        and audio_t > 110 then ach("halfway")        end
  if not _claimed["chorus_survivor"] and audio_t > 150 then ach("chorus_survivor") end
  if not _claimed["flawless_intro"]  and audio_t > 30 and player.hits == 0 then ach("flawless_intro") end
  if not _claimed["unbroken"] and combo >= 30 then ach("unbroken") end
  if not _claimed["lobby_visitor"] and Net.enabled and next(Net.ghosts) then ach("lobby_visitor") end
end

local _close_call_recent = 0
local function detectCloseCall(dt)
  _close_call_recent = math.max(0, _close_call_recent - dt)
  if not player:dashing() then return end
  -- detect a near-miss using a wider probe than the actual hit-circle
  local hit = Obstacles.checkHit(player.x, player.y, player.size * 0.55)
  if hit and _close_call_recent <= 0 then
    close_calls = close_calls + 1
    edge_tint_c = 1.0
    _close_call_recent = 0.30                       -- de-bounce
    if close_calls == 1 then ach("close_call") end
  end
end

-- Per-state update helpers. Splitting these out keeps love.update under the
-- Lua 5.1 60-upvalue closure limit.
local function update_loading(dt)
  if loadStep() then
    state = "menu"
    if DEBUG_AUTORUN then newRun(tonumber(DEBUG_AUTORUN) or 0) end
  end
end

local function update_menu(dt)
  audio_t = audio_t + dt * 0.30
  bg_pulse = math.max(0, bg_pulse - dt * 1.5)
  sil_glow = 0.35
end

local function update_shop()
  if source and source:isPlaying() then source:pause() end
end

local function update_character(dt)
  if preview_player then preview_player:update(dt) end
  Character.update(dt)
end

local function update_lobby(dt)
  Lobby.update(dt)
  Net.broadcast(player, dt, playerColor(), Save.state.upgrades)
  if not _last_mood_t or (love.timer.getTime() - _last_mood_t) > 0.5 then
    fxMood(colorHex(accent[1], accent[2], accent[3]), 0.25)
    _last_mood_t = love.timer.getTime()
  end
end

local function update_dying(dt)
  dying_t = dying_t + dt
  bg_pulse = math.max(0, bg_pulse - dt * 0.6)
  shake_t = math.max(0, shake_t - dt)
  if player then player:update(dt) end
  if dying_t > 1.6 then
    state = "reviving"; revive_t = 0
    fxShatter(0.7, 600)
  end
end

local function update_reviving(dt)
  revive_t = revive_t + dt
  if revive_t > 1.4 then revive() end
end

local function update_win(dt)
  if source and source:isPlaying() then audio_t = audioTime() end
  bg_pulse = math.max(0, bg_pulse - dt * 1.5)
  kick_pulse = math.max(0, kick_pulse - dt * 4)
  shake_t = math.max(0, shake_t - dt)
  flash_t = math.max(0, flash_t - dt)
end

local function update_play(dt)
    audio_t = audioTime()
    elapsed_play = elapsed_play + dt

    -- end of song
    local dur = (Beats.duration > 0 and Beats.duration or Video.duration())
    if audio_t >= dur - 0.10 then
      state = "win"
      Save.state.completed = true
      if not victory_shown then
        Save.state.best_time = math.max(Save.state.best_time or 0, audio_t)
        ach("apple_complete")
        if player.hits == 0 then ach("untouched") end
        if player.dashes == 0 then ach("pacifist") end
        victory_shown = true
        -- progression: bump completions and surface any new unlock so the
        -- win screen can announce it
        Save.state.completions = (Save.state.completions or 0) + 1
        local newly
        for _, p in ipairs(PLAYER_PALETTE) do
          if p.unlock_at == Save.state.completions then newly = "colour: " .. p.name; break end
        end
        if not newly then
          for _, a in ipairs(AURAS) do
            if a.unlock_at == Save.state.completions then newly = "aura: " .. a.name; break end
          end
        end
        Save.state.last_unlock = newly
        Save.write()
        fxFlash("#ffffff", 800)
        fxShake(1.0, 800)
      end
      return
    end

    Beats.fire(audio_t, fireEvent)
    Obstacles.setBeatTime(audio_t)
    Obstacles.updateAll(dt, audio_t)
    player:update(dt)
    Video.update(audio_t, 0.6)         -- prefetch upcoming sheet
    Apples.update(dt, Director.intensity(audio_t))
    do
      local n = Apples.collect(player)
      if n > 0 then
        Save.state.apples = (Save.state.apples or 0) + n
        SFX.play(snd_tick)
        Save.write()
      end
    end

    Net.broadcast(player, dt, playerColor(), Save.state.upgrades)

    detectCloseCall(dt)

    -- collision: only spawned obstacles deal damage
    local got_hit = false
    if not player:invincible() then
      local h = Obstacles.checkHit(player.x, player.y, player.size * 0.22)
      if h and player:hit() then got_hit = "obstacle" end
    end

    if got_hit then
      shake_t, shake_mag = 0.40, 22
      flash_t, flash_color = 0.22, {1, 0.55, 0.85, 1}
      hit_stop_t = 0.06                             -- short freeze for impact weight
      edge_tint_r = 1.0                             -- red screen-edge pulse
      fxShake(0.7, 320)
      fxFlash(colorHex(accent[1], accent[2], accent[3]), 220)
      SFX.play(snd_hit)
      Save.state.hits_taken = (Save.state.hits_taken or 0) + 1
      best_combo = math.max(best_combo, combo)
      combo = 0
      if not _claimed["first_blood"] then ach("first_blood") end
    else
      -- combo grows as obstacles age out without hitting us
      combo = combo + dt * 1.6
    end

    -- death detection
    if not player.alive and state == "play" then
      Save.state.deaths = (Save.state.deaths or 0) + 1
      Save.state.dashes = (Save.state.dashes or 0) + player.dashes
      Save.state.last_checkpoint = checkpoint_time
      Save.write()
      death_pos.x, death_pos.y = player.x, player.y
      death_audio_t = audio_t
      state = "dying"
      dying_t = 0
      music_duck = 0.20                             -- duck the song heavy on death
      if source then source:setVolume((Save.state.volume or 0.85) * music_duck) end
      fxShake(1.0, 700)
      fxShatter(1.0, 700)
      fxFlash("#000000", 220)
      SFX.play(snd_death)
      return
    end

    -- score: time alive + dash bonus
    local mul = (Save.state.upgrades and Save.state.upgrades.score) and 1.25 or 1.0
    score = math.floor((audio_t * 10 + player.dashes * 5 + best_combo * 2) * mul)

    -- live checkpoint advance
    if audio_t - checkpoint_time > 12 then
      checkpoint_time = math.floor(audio_t / 12) * 12
      Save.state.last_checkpoint = checkpoint_time
      if audio_t - last_save_t > 4 then
        Save.write()
        last_save_t = audio_t
      end
    end

    -- pulses decay
    bg_pulse   = math.max(0, bg_pulse  - dt * 3.0)
    kick_pulse = math.max(0, kick_pulse - dt * 4.0)
    -- silhouette breathes on the kick AND brightens whenever the player
    -- dashes through it -- makes the shadow feel like an antagonist that
    -- reacts to your defiance, not just decoration
    local target_glow = 0.30 + Beats.proximity(Beats.kicks, audio_t, 0.18) * 0.8
    if player and player:dashing() then target_glow = math.min(1, target_glow + 0.45) end
    sil_glow = sil_glow + (target_glow - sil_glow) * math.min(1, dt * 8)
    shake_t    = math.max(0, shake_t - dt)
    flash_t    = math.max(0, flash_t - dt)

    -- mood drift across song -- the player's accent and the portal mood drift
    -- together so the chrome and gameplay share a pulse.
    local I = Director.intensity(audio_t)
    accent[1] = 0.95
    accent[2] = 0.30 + 0.20 * (1 - I)
    accent[3] = 0.55 + 0.30 * I
    -- emit mood at most ~3 Hz to avoid stdout spam
    if not _last_mood_t or audio_t - _last_mood_t > 0.35 then
      fxMood(colorHex(accent[1], accent[2], accent[3]), 0.20 + 0.45 * I)
      _last_mood_t = audio_t
    end

    checkAchievements()
end

function love.update(dt)
  if DEBUG_QUIT_AT and (love.timer.getTime() - _wall_t0) > DEBUG_QUIT_AT then
    love.event.quit()
  end
  if hit_stop_t > 0 then
    hit_stop_t = math.max(0, hit_stop_t - love.timer.getDelta())
    dt = 0
  end
  edge_tint_r = math.max(0, edge_tint_r - love.timer.getDelta() * 2.5)
  edge_tint_c = math.max(0, edge_tint_c - love.timer.getDelta() * 2.5)

  Net.poll(); Net.update(dt)

  if     state == "loading"   then update_loading(dt)
  elseif state == "menu"      then update_menu(dt)
  elseif state == "paused"    then return
  elseif state == "shop"      then update_shop()
  elseif state == "character" then update_character(dt)
  elseif state == "lobby"     then update_lobby(dt)
  elseif state == "dying"     then update_dying(dt)
  elseif state == "reviving"  then update_reviving(dt)
  elseif state == "play"      then update_play(dt)
  elseif state == "win"       then update_win(dt)
  end
end

-- ─── draw helpers ────────────────────────────────────────────────────
local function drawBackdrop()
  local p = bg_pulse
  local r1 = 0.045 + 0.04 * p
  local g1 = 0.020 + 0.02 * p
  local b1 = 0.075 + 0.06 * p
  love.graphics.clear(r1, g1, b1, 1)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", 0, 0, DESIGN_W, 90)
  love.graphics.rectangle("fill", 0, DESIGN_H - 90, DESIGN_W, 90)
end

local function drawSilhouetteWithGlow(t)
  local _, dw, dh = Video.fitRect(DESIGN_W, DESIGN_H)
  -- send shader uniforms
  Mosaic.send(love.timer.getTime(), 0.4 + 0.8 * sil_glow,
              Director.intensity(audio_t or 0), dw, dh)
  local prev = love.graphics.getShader()
  love.graphics.setShader(Mosaic.shader())
  -- the shader maps the source mask -> mosaic palette; we draw at full size
  -- using a near-white tint so the shader receives unmodified luminance
  sil_dx, sil_dy, sil_dw, sil_dh, sil_scale = Video.draw(t, 0, 0, DESIGN_W, DESIGN_H, 1, 1, 1, 1)
  love.graphics.setShader(prev)
end

local function drawHearts()
  local hp = player and player:livesLeft() or 0
  for i = 1, hp do
    local x = 40 + (i - 1) * 38
    local y = 40
    love.graphics.setColor(accent[1], accent[2], accent[3], 0.95)
    love.graphics.rectangle("fill", x, y, 26, 26, 6, 6)
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.rectangle("fill", x + 6, y + 6, 14, 14, 4, 4)
  end
end

local function drawHUD()
  love.graphics.setFont(font_hud)
  drawHearts()

  -- progress bar
  local bx, by, bw, bh = DESIGN_W*0.5 - 460, 36, 920, 14
  love.graphics.setColor(1,1,1,0.10)
  love.graphics.rectangle("fill", bx, by, bw, bh, 4, 4)
  local dur = (Beats.duration > 0) and Beats.duration or Video.duration()
  local k = math.min(1, audio_t / dur)
  love.graphics.setColor(accent[1], accent[2], accent[3], 0.95)
  love.graphics.rectangle("fill", bx, by, bw * k, bh, 4, 4)
  love.graphics.setColor(1,1,1,1)
  love.graphics.setFont(font_small)
  love.graphics.printf(string.format("%01d:%05.2f", math.floor(audio_t/60), audio_t%60), bx, by + 18, bw, "center")

  -- dash cooldown pip
  love.graphics.setFont(font_hud)
  local cd = player and player.dash_cd or 0
  local maxcd = 0.45
  local x, y = DESIGN_W - 220, 40
  love.graphics.setColor(1,1,1,0.10)
  love.graphics.rectangle("fill", x, y, 160, 26, 4, 4)
  love.graphics.setColor(accent[1], accent[2], accent[3], 0.95)
  love.graphics.rectangle("fill", x, y, 160 * (1 - cd / maxcd), 26, 4, 4)
  love.graphics.setColor(1,1,1,0.85)
  love.graphics.printf("DASH", x, y + 1, 160, "center")

  -- score / combo
  love.graphics.setFont(font_hud)
  love.graphics.setColor(1,1,1,0.9)
  love.graphics.print(string.format("%07d", score), 40, DESIGN_H - 70)
  if combo > 1.5 then
    love.graphics.setColor(accent[1], accent[2], accent[3], 0.95)
    love.graphics.print(string.format("x%d", math.floor(combo)), 240, DESIGN_H - 70)
  end
  -- glowy apple counter
  local ax, ay = 40, 88
  love.graphics.setColor(1, 0.30, 0.45, 1)
  love.graphics.circle("fill", ax + 13, ay + 14, 10)
  love.graphics.setColor(1, 1, 1, 0.85)
  love.graphics.circle("fill", ax + 9, ay + 10, 3)
  love.graphics.setColor(1, 1, 1, 0.95)
  love.graphics.print(string.format("%d", Save.state.apples or 0), ax + 32, ay)

  -- lobby presence
  if Net.enabled then
    love.graphics.setFont(font_small)
    local n = 0
    for _ in pairs(Net.ghosts) do n = n + 1 end
    love.graphics.setColor(0.7, 0.9, 1.0, 0.85)
    love.graphics.print(string.format("LOBBY  %d", n), DESIGN_W - 160, DESIGN_H - 60)
  end
end

local function drawScreenFlash()
  if flash_t > 0 then
    local k = flash_t / 0.22
    love.graphics.setColor(flash_color[1], flash_color[2], flash_color[3], 0.45 * k)
    love.graphics.rectangle("fill", 0, 0, DESIGN_W, DESIGN_H)
  end
end

-- Soft tint along the screen edges -- red on hit, cyan on close-call dodge.
local function drawEdgeTints()
  local function band(r, g, b, a)
    local thick = 220
    -- top
    for i = 0, 6 do
      local k = (1 - i / 6)
      love.graphics.setColor(r, g, b, a * k * k)
      love.graphics.rectangle("fill", 0, i * thick / 6, DESIGN_W, thick / 6 + 1)
    end
    -- bottom
    for i = 0, 6 do
      local k = (1 - i / 6)
      love.graphics.setColor(r, g, b, a * k * k)
      love.graphics.rectangle("fill", 0, DESIGN_H - thick + i * thick / 6, DESIGN_W, thick / 6 + 1)
    end
    -- sides
    for i = 0, 6 do
      local k = (1 - i / 6)
      love.graphics.setColor(r, g, b, a * k * k)
      love.graphics.rectangle("fill", i * thick / 6, 0, thick / 6 + 1, DESIGN_H)
      love.graphics.rectangle("fill", DESIGN_W - thick + i * thick / 6, 0, thick / 6 + 1, DESIGN_H)
    end
  end
  if edge_tint_r > 0 then band(1.0, 0.20, 0.35, 0.55 * edge_tint_r) end
  if edge_tint_c > 0 then band(0.40, 0.95, 1.0, 0.40 * edge_tint_c) end
end

local function drawMenu()
  love.graphics.clear(0.03, 0.01, 0.05, 1)
  -- preview the silhouette midway
  local previewT = (love.timer.getTime() * 0.5) % math.max(1, Video.duration())
  Video.draw(previewT, DESIGN_W*0.5 - 720, DESIGN_H*0.5 - 540, 1440, 1080, 0.6, 0.4, 0.7, 0.55)
  love.graphics.setColor(0,0,0,0.55)
  love.graphics.rectangle("fill", 0, 0, DESIGN_W, DESIGN_H)
  love.graphics.setFont(font_big)
  love.graphics.setColor(1, 0.85, 0.95, 1)
  love.graphics.printf("BAD  APPLE", 0, 200, DESIGN_W, "center")
  love.graphics.setFont(font_med)
  love.graphics.setColor(1, 0.55, 0.85, 1)
  love.graphics.printf("BEAT  DASH", 0, 320, DESIGN_W, "center")
  love.graphics.setFont(font_small)
  love.graphics.setColor(1, 1, 1, 0.65)
  love.graphics.printf("dodge the shadow.  consume the apple.",
                       0, 410, DESIGN_W, "center")
  love.graphics.setFont(font_small)
  love.graphics.setColor(1,1,1,0.85)
  local lines = {
    "ENTER  / SPACE   enter your character room",
    ((Save.state.last_checkpoint or 0) > 5)
      and string.format("C   continue from %d:%02d", math.floor(Save.state.last_checkpoint/60), Save.state.last_checkpoint%60)
      or  "(checkpoints save every 12s during play)",
    "B   apple shop",
    string.format("M   cyber lobby   [%s]", Net.enabled and "ON" or "OFF"),
    string.format("L   replay-on-win  [%s]", LOOP and "ON" or "OFF"),
    string.format("- / +   volume  [%d%%]", math.floor((Save.state.volume or 0.85) * 100)),
    "ESC  quit",
  }
  for i, line in ipairs(lines) do
    love.graphics.printf(line, 0, 540 + (i-1) * 32, DESIGN_W, "center")
  end
  if Save.state.runs and Save.state.runs > 0 then
    love.graphics.setColor(1,1,1,0.55)
    love.graphics.printf(
      string.format("runs %d   deaths %d   hits %d   completed %s   best-time %s",
        Save.state.runs or 0, Save.state.deaths or 0, Save.state.hits_taken or 0,
        Save.state.completed and "yes" or "no",
        Save.state.best_time and string.format("%d:%02d", math.floor((Save.state.best_time or 0)/60), (Save.state.best_time or 0)%60) or "0:00"),
      0, DESIGN_H - 130, DESIGN_W, "center")
  end
  love.graphics.setColor(1,1,1,0.4)
  love.graphics.printf("WASD/arrows move    SPACE/SHIFT dash    silhouette is deadly",
    0, DESIGN_H - 80, DESIGN_W, "center")
end

local function drawPaused()
  love.graphics.setColor(0,0,0,0.55)
  love.graphics.rectangle("fill", 0, 0, DESIGN_W, DESIGN_H)
  love.graphics.setFont(font_big)
  love.graphics.setColor(1, 0.85, 0.95, 1)
  love.graphics.printf("PAUSED", 0, 360, DESIGN_W, "center")
  love.graphics.setFont(font_small)
  love.graphics.setColor(1,1,1,0.85)
  love.graphics.printf("ESC / P  resume    Q  back to menu", 0, 480, DESIGN_W, "center")
end

local function drawOverScreen()
  -- darken
  local k = math.min(1, dying_t / 0.6)
  love.graphics.setColor(0,0,0,0.5 * k + 0.25)
  love.graphics.rectangle("fill", 0, 0, DESIGN_W, DESIGN_H)
  -- "IT'S OVER" slams down
  love.graphics.setFont(font_huge)
  local y = -200 + math.min(1, dying_t / 0.45) * 600
  local sway = math.sin(dying_t * 4) * 4
  love.graphics.setColor(1, 0.35, 0.6, k)
  love.graphics.printf("IT'S OVER", 0, y + sway, DESIGN_W, "center")
  -- subtitle: where + how
  if dying_t > 0.7 then
    love.graphics.setFont(font_small)
    love.graphics.setColor(1,1,1,0.65)
    love.graphics.printf(string.format("at %d:%05.2f   --   hits taken %d",
      math.floor(death_audio_t/60), death_audio_t%60, player and player.hits or 0),
      0, y + 200, DESIGN_W, "center")
  end
end

local function drawNotOverScreen()
  local k = math.min(1, revive_t / 0.45)
  -- glitch full-screen for the duration
  love.graphics.setColor(0,0,0,0.45)
  love.graphics.rectangle("fill", 0, 0, DESIGN_W, DESIGN_H)
  -- big NOT OVER text bursting from centre
  love.graphics.setFont(font_huge)
  local pulse = 1.0 + 0.10 * math.sin(revive_t * 30)
  love.graphics.push()
  love.graphics.translate(DESIGN_W * 0.5, DESIGN_H * 0.5 - 30)
  love.graphics.scale(pulse, pulse)
  love.graphics.setColor(1, 0.95, 0.85, k)
  love.graphics.printf("IT'S NOT OVER", -DESIGN_W*0.5, -90, DESIGN_W, "center")
  love.graphics.pop()
  if revive_t > 0.6 then
    love.graphics.setFont(font_small)
    love.graphics.setColor(1,1,1,0.75)
    love.graphics.printf("resuming...", 0, DESIGN_H * 0.5 + 130, DESIGN_W, "center")
  end
end

local function drawShop()
  love.graphics.setColor(0.04, 0.02, 0.07, 0.95)
  love.graphics.rectangle("fill", 0, 0, DESIGN_W, DESIGN_H)
  love.graphics.setFont(font_big)
  love.graphics.setColor(1, 0.45, 0.55, 1)
  love.graphics.printf("APPLE  SHOP", 0, 110, DESIGN_W, "center")
  -- balance
  love.graphics.setFont(font_med)
  love.graphics.setColor(1, 0.85, 0.95, 1)
  love.graphics.printf(string.format("you have  %d  apples", Save.state.apples or 0),
                       0, 220, DESIGN_W, "center")
  -- items
  love.graphics.setFont(font_small)
  for i, item in ipairs(SHOP_ITEMS) do
    local y = 320 + (i - 1) * 86
    local owned = Save.state.upgrades[item.key]
    local affordable = (Save.state.apples or 0) >= item.cost
    local sel = (i == shop_idx)
    -- background card
    if sel then
      for g = 4, 1, -1 do
        love.graphics.setColor(1, 0.45, 0.55, 0.04)
        love.graphics.rectangle("fill", 380 - g*4, y - 8 - g*4, 1160 + g*8, 70 + g*8, 16, 16)
      end
      love.graphics.setColor(1, 1, 1, 0.85)
      love.graphics.rectangle("line", 380, y - 8, 1160, 70, 12, 12)
    else
      love.graphics.setColor(1, 1, 1, 0.10)
      love.graphics.rectangle("line", 380, y - 8, 1160, 70, 12, 12)
    end
    -- title + desc
    love.graphics.setFont(font_med)
    if owned then love.graphics.setColor(0.6, 1.0, 0.6, 1)
    elseif affordable then love.graphics.setColor(1, 1, 1, 1)
    else love.graphics.setColor(1, 1, 1, 0.45) end
    love.graphics.print(item.title, 410, y - 4)
    love.graphics.setFont(font_small)
    love.graphics.setColor(1, 1, 1, 0.65)
    love.graphics.print(item.desc, 410, y + 32)
    -- cost / status
    love.graphics.setFont(font_med)
    if owned then
      love.graphics.setColor(0.6, 1.0, 0.6, 1)
      love.graphics.printf("OWNED", 1340, y - 4, 200, "right")
    else
      if affordable then love.graphics.setColor(1, 0.85, 0.55, 1)
      else love.graphics.setColor(1, 1, 1, 0.45) end
      love.graphics.printf(tostring(item.cost), 1300, y - 4, 220, "right")
      love.graphics.setColor(1, 0.30, 0.45, affordable and 1 or 0.5)
      love.graphics.circle("fill", 1530, y + 12, 11)
      love.graphics.setColor(1, 1, 1, 0.85)
      love.graphics.circle("fill", 1527, y + 9, 3)
    end
  end
  -- footer
  love.graphics.setFont(font_small)
  love.graphics.setColor(1, 1, 1, 0.7)
  love.graphics.printf("UP / DOWN  pick     ENTER  buy     ESC / B  back",
                       0, DESIGN_H - 70, DESIGN_W, "center")
end

local function drawWin()
  love.graphics.setColor(0,0,0,0.55)
  love.graphics.rectangle("fill", 0, 0, DESIGN_W, DESIGN_H)
  love.graphics.setFont(font_big)
  love.graphics.setColor(0.85, 1.0, 0.95, 1)
  love.graphics.printf("APPLE  CONSUMED", 0, 200, DESIGN_W, "center")
  love.graphics.setFont(font_small)
  love.graphics.setColor(1, 0.85, 0.95, 0.9)
  love.graphics.printf("the shadow fades.", 0, 310, DESIGN_W, "center")
  love.graphics.setFont(font_med)
  love.graphics.setColor(1, 0.85, 0.95, 1)
  love.graphics.printf(string.format("score %07d   hits %d   dashes %d   best combo x%d",
    score, player and player.hits or 0, player and player.dashes or 0, math.floor(best_combo)),
    0, 380, DESIGN_W, "center")
  love.graphics.setFont(font_small)
  love.graphics.setColor(1,1,1,0.85)
  love.graphics.printf(string.format("you have eaten  %d  apples in total   |   completions  %d",
                       Save.state.apples or 0, Save.state.completions or 0),
    0, 460, DESIGN_W, "center")
  if Save.state.last_unlock then
    love.graphics.setColor(accent[1], accent[2], accent[3], 1)
    love.graphics.printf("UNLOCKED   " .. Save.state.last_unlock,
      0, 420, DESIGN_W, "center")
  end
  love.graphics.printf("ENTER  " .. (LOOP and "play again" or "back to menu") .. "     B  apple shop",
    0, 510, DESIGN_W, "center")
  love.graphics.printf(string.format("L  replay-on-win  [%s]", LOOP and "ON" or "OFF"),
    0, 545, DESIGN_W, "center")
end

-- ─── master draw ─────────────────────────────────────────────────────
function love.draw()
  if state == "loading" then
    love.graphics.clear(0.03, 0.01, 0.05, 1)
    local w, h = love.graphics.getDimensions()
    love.graphics.setFont(font_med)
    love.graphics.setColor(1, 0.85, 0.95, 1)
    love.graphics.printf(boot_msg, 0, h*0.45, w, "center")
    local bw = w * 0.5
    local bx = (w - bw) * 0.5
    local by = h * 0.55
    love.graphics.setColor(1,1,1,0.15)
    love.graphics.rectangle("fill", bx, by, bw, 14, 4, 4)
    love.graphics.setColor(1, 0.45, 0.75, 1)
    love.graphics.rectangle("fill", bx, by, bw * boot_progress, 14, 4, 4)
    return
  end

  -- world canvas
  love.graphics.push("all")
  love.graphics.setCanvas(world)
  drawBackdrop()
  if state == "menu" then
    drawMenu()
  elseif state == "character" then
    if not preview_player then refreshPreviewPlayer() end
    local handle = (Net.identity and Net.identity.handle) or "guest"
    if Net.identity and not Net.identity.signedIn then handle = "guest" end
    local stats = {
      apples    = Save.state.apples,
      runs      = Save.state.runs,
      deaths    = Save.state.deaths,
      hits      = Save.state.hits_taken,
      completed = Save.state.completed,
      best_time = Save.state.best_time,
    }
    stats.completions = Save.state.completions
    Character.draw(PLAYER_PALETTE, Save.state.player_color or 1,
                   Save.state.upgrades or {}, stats,
                   preview_player, handle,
                   { huge = font_huge, big = font_big, med = font_med,
                     small = font_small, hud = font_hud },
                   paletteUnlocked,
                   AURAS, Save.state.aura_id or 1,
                   auraUnlocked)
  elseif state == "lobby" then
    local handle = (Net.identity and Net.identity.handle) or "you"
    if Net.identity and not Net.identity.signedIn then handle = "guest" end
    Lobby.draw(playerColor(), Net.peerCount and Net.peerCount() or 0,
               "BAD APPLE  //  CYBER LOBBY", handle)
    Net.draw()
    if player then player:draw(playerColor()) end
  else
    drawSilhouetteWithGlow(audio_t)
    Net.draw()
    Apples.draw()
    Obstacles.drawAll(accent)
    if player then player:draw(playerColor()) end
    drawHUD()
    drawEdgeTints()
    drawScreenFlash()
    if state == "paused"   then drawPaused()        end
    if state == "dying"    then drawOverScreen()    end
    if state == "reviving" then drawNotOverScreen() end
    if state == "win"      then drawWin()           end
    if state == "shop"     then drawShop()          end
    if state == "lobby"    then
      -- override the silhouette + obstacles draw with the lobby scene
    end
  end
  love.graphics.setCanvas()
  love.graphics.pop()

  -- bloom pass
  love.graphics.push("all")
  love.graphics.setCanvas(world)
  Glow.apply(world, 0.55, 0.85 + 0.6 * kick_pulse, 4.5)
  love.graphics.setCanvas()
  love.graphics.pop()

  -- final blit with letterbox + screen shake (+ glitch shader during reviving)
  local sw, sh = love.graphics.getDimensions()
  local scale = math.min(sw / DESIGN_W, sh / DESIGN_H)
  local dx = (sw - DESIGN_W * scale) * 0.5
  local dy = (sh - DESIGN_H * scale) * 0.5
  if shake_t > 0 then
    dx = dx + (love.math.random() - 0.5) * shake_mag * shake_t / 0.40
    dy = dy + (love.math.random() - 0.5) * shake_mag * shake_t / 0.40
  end
  love.graphics.clear(0,0,0,1)
  love.graphics.setColor(1,1,1,1)
  if state == "reviving" or (state == "dying" and dying_t > 0.6) then
    glitch_shader:send("amount", state == "reviving" and (1.0 - revive_t / 1.4) or math.min(1, (dying_t - 0.6) / 0.8))
    glitch_shader:send("time_", love.timer.getTime())
    love.graphics.setShader(glitch_shader)
  end
  love.graphics.draw(world, dx, dy, 0, scale, scale)
  love.graphics.setShader()
end

function love.focus(f)
  if not f and state == "play" and source then
    source:pause()
    state = "paused"
  end
end

function love.quit()
  if Net.enabled then Net.leave() end
  Save.write()
end
