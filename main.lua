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

local DESIGN_W, DESIGN_H = 1920, 1080

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

-- death sequence timers
local dying_t   = 0   -- "IT'S OVER" duration
local revive_t  = 0   -- "IT'S NOT OVER" duration
local death_pos = { x = 0, y = 0 }
local death_audio_t = 0

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
  player = Player.new(DESIGN_W * 0.5, DESIGN_H * 0.5, playBounds())
  startSongAt(fromTime or 0)
  Save.state.runs = (Save.state.runs or 0) + 1
  Save.write()
  state = "play"
  checkpoint_time = math.max(checkpoint_time, fromTime or 0)
  combo = 0
  score = 0
  victory_shown = false
end

-- Begin a soft revive: keep player position, full HP, brief i-frames, song
-- resumes from where they died.
local function revive()
  player:revive(death_pos.x, death_pos.y)
  startSongAt(math.max(0, death_audio_t - 0.25))
  state = "play"
  combo = 0
  ach("second_chance")
  fxRipple("#ffffff", death_pos.x / DESIGN_W, death_pos.y / DESIGN_H, 850)
  fxFlash("#ffffff", 260)
end

local DEBUG_AUTORUN = (os.getenv and os.getenv("BADAPPLE_AUTORUN")) or nil
local DEBUG_QUIT_AT = tonumber((os.getenv and os.getenv("BADAPPLE_QUIT_AT")) or "")
local _wall_t0

function love.load()
  love.graphics.setDefaultFilter("linear", "linear", 1)
  love.window.setMode(1280, 720, { resizable = true, vsync = 1, msaa = 0, highdpi = true, minwidth = 640, minheight = 360 })
  love.window.setTitle("Bad Apple // Beat Dash")

  world = love.graphics.newCanvas(DESIGN_W, DESIGN_H)
  world:setFilter("linear", "linear")
  Glow.load(DESIGN_W, DESIGN_H)
  glitch_shader = love.graphics.newShader(glitch_shader_code)

  font_huge  = love.graphics.newFont(150)
  font_big   = love.graphics.newFont(96)
  font_med   = love.graphics.newFont(40)
  font_small = love.graphics.newFont(22)
  font_hud   = love.graphics.newFont(28)

  Save.load()
  if Save.state.volume == nil then Save.state.volume = 0.85 end
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
    boot_progress = 1.0; _boot.phase = 6; return true
  end
  return true
end

-- ─── input ───────────────────────────────────────────────────────────
function love.keypressed(key)
  if state == "menu" then
    if     key == "return" or key == "space" then newRun(0)
    elseif key == "c" and (Save.state.last_checkpoint or 0) > 5 then newRun(Save.state.last_checkpoint)
    elseif key == "l" then LOOP = not LOOP
    elseif key == "m" then
      if Net.enabled then Net.leave() else Net.tryJoinPublic() end
    elseif key == "-" or key == "kp-" then
      Save.state.volume = math.max(0, (Save.state.volume or 0.85) - 0.05); Save.write()
    elseif key == "=" or key == "+" or key == "kp+" then
      Save.state.volume = math.min(1, (Save.state.volume or 0.85) + 0.05); Save.write()
    elseif key == "escape" then love.event.quit() end
  elseif state == "play" then
    if key == "space" or key == "lshift" or key == "rshift" then
      if player:tryDash() then
        ach("first_dash")
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
    elseif key == "escape" then state = "menu" end
  elseif state == "win" then
    if key == "return" or key == "space" then
      if LOOP then run_loops = run_loops + 1; if run_loops >= 1 then ach("loop_lover") end; newRun(0) else state = "menu" end
    elseif key == "escape" then state = "menu"
    elseif key == "l" then LOOP = not LOOP end
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

local function silhouetteHit(t)
  if sil_scale <= 0 then return false end
  local r = (player.size * 0.40)
  local x0, y0 = player.x - r, player.y - r
  local x1, y1 = player.x + r, player.y + r
  local vx0 = (x0 - sil_dx) / sil_scale
  local vy0 = (y0 - sil_dy) / sil_scale
  local vx1 = (x1 - sil_dx) / sil_scale
  local vy1 = (y1 - sil_dy) / sil_scale
  if vx1 < 0 or vy1 < 0 or vx0 > 480 or vy0 > 360 then return false end
  if vx0 < 0 then vx0 = 0 end
  if vy0 < 0 then vy0 = 0 end
  if vx1 > 480 then vx1 = 480 end
  if vy1 > 360 then vy1 = 360 end
  local frame = Video.frameAt(t)
  return Collision.boxHits(frame, vx0, vy0, vx1, vy1)
end

local function checkAchievements()
  if not _claimed["intro_clear"]    and audio_t > 30  then ach("intro_clear")    end
  if not _claimed["halfway"]        and audio_t > 110 then ach("halfway")        end
  if not _claimed["chorus_survivor"] and audio_t > 150 then ach("chorus_survivor") end
  if not _claimed["flawless_intro"]  and audio_t > 30 and player.hits == 0 then ach("flawless_intro") end
  if not _claimed["unbroken"] and combo >= 30 then ach("unbroken") end
  if not _claimed["lobby_visitor"] and Net.enabled and next(Net.ghosts) then ach("lobby_visitor") end
end

local function detectCloseCall()
  -- if player is dashing and within 36px of a live obstacle hot zone, count a close call
  if not player:dashing() then return end
  local hit = Obstacles.checkHit(player.x, player.y, player.size * 0.95)
  if hit then
    close_calls = close_calls + 1
    if close_calls == 1 then ach("close_call") end
  end
end

function love.update(dt)
  if DEBUG_QUIT_AT and (love.timer.getTime() - _wall_t0) > DEBUG_QUIT_AT then
    love.event.quit()
  end

  Net.poll()
  Net.update(dt)

  if state == "loading" then
    if loadStep() then
      state = "menu"
      if DEBUG_AUTORUN then newRun(tonumber(DEBUG_AUTORUN) or 0) end
    end
    return
  end

  if state == "menu" then
    audio_t = audio_t + dt * 0.30
    bg_pulse = math.max(0, bg_pulse - dt * 1.5)
    sil_glow = 0.35
    return
  end

  if state == "paused" then
    return
  end

  if state == "dying" then
    dying_t = dying_t + dt
    bg_pulse = math.max(0, bg_pulse - dt * 0.6)
    shake_t = math.max(0, shake_t - dt)
    if player then player:update(dt) end           -- shards keep flying
    if dying_t > 1.6 then
      state = "reviving"; revive_t = 0
      fxShatter(0.7, 600)
    end
    return
  end

  if state == "reviving" then
    revive_t = revive_t + dt
    if revive_t > 1.4 then
      revive()
    end
    return
  end

  if state == "play" then
    audio_t = audioTime()
    elapsed_play = elapsed_play + dt

    -- end of song
    local dur = (Beats.duration > 0 and Beats.duration or Video.duration())
    if audio_t >= dur - 0.10 then
      state = "win"
      Save.state.completed = true
      if not victory_shown then
        Save.state.best_time = math.max(Save.state.best_time or 0, audio_t)
        Save.write()
        ach("apple_complete")
        if player.hits == 0 then ach("untouched") end
        if player.dashes == 0 then ach("pacifist") end
        victory_shown = true
        fxFlash("#ffffff", 800)
        fxShake(1.0, 800)
      end
      return
    end

    Beats.fire(audio_t, fireEvent)
    Obstacles.updateAll(dt, audio_t)
    player:update(dt)
    Video.update(audio_t, 0.6)         -- prefetch upcoming sheet

    Net.broadcast(player, dt)

    detectCloseCall()

    -- collision: silhouette + obstacles
    local got_hit = false
    if not player:invincible() then
      if silhouetteHit(audio_t) then
        if player:hit() then got_hit = "silhouette" end
      else
        local h = Obstacles.checkHit(player.x, player.y, player.size * 0.40)
        if h and player:hit() then got_hit = "obstacle" end
      end
    end

    if got_hit then
      shake_t, shake_mag = 0.40, 22
      flash_t, flash_color = 0.22, {1, 0.55, 0.85, 1}
      fxShake(0.7, 320)
      fxFlash(colorHex(accent[1], accent[2], accent[3]), 220)
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
      if source then source:pause() end
      fxShake(1.0, 700)
      fxShatter(1.0, 700)
      fxFlash("#000000", 220)
      return
    end

    -- score: time alive + dash bonus
    score = math.floor(audio_t * 10 + player.dashes * 5 + best_combo * 2)

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
    sil_glow   = math.min(1, 0.30 + Beats.proximity(Beats.kicks, audio_t, 0.18) * 0.8)
    shake_t    = math.max(0, shake_t - dt)
    flash_t    = math.max(0, flash_t - dt)

    -- mood drift across song
    local I = Director.intensity(audio_t)
    accent[1] = 0.95
    accent[2] = 0.30 + 0.20 * (1 - I)
    accent[3] = 0.55 + 0.30 * I

    checkAchievements()
  elseif state == "win" then
    if source and source:isPlaying() then audio_t = audioTime() end
    bg_pulse = math.max(0, bg_pulse - dt * 1.5)
    kick_pulse = math.max(0, kick_pulse - dt * 4)
    shake_t = math.max(0, shake_t - dt)
    flash_t = math.max(0, flash_t - dt)
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
  local glow = 0.55 + 0.45 * sil_glow
  local cr, cg, cb = accent[1], accent[2], accent[3]

  -- coloured aura halos behind silhouette (additive)
  love.graphics.setBlendMode("add", "alphamultiply")
  for i = 4, 1, -1 do
    local s = 1 + i * 0.012
    local a = 0.08 * glow / i
    -- centre the scaled silhouette around the eventual draw rect
    local rs, dw, dh = Video.fitRect(DESIGN_W, DESIGN_H)
    local cx = DESIGN_W * 0.5
    local cy = DESIGN_H * 0.5
    Video.draw(t, cx - dw * s * 0.5, cy - dh * s * 0.5, dw * s, dh * s, cr, cg, cb, a)
  end
  love.graphics.setBlendMode("alpha")

  -- crisp silhouette on top, white tinted toward accent at high intensity
  local mix = 0.18 + 0.30 * sil_glow
  local r = 1 - (1 - cr) * mix
  local g = 1 - (1 - cg) * mix
  local b = 1 - (1 - cb) * mix
  sil_dx, sil_dy, sil_dw, sil_dh, sil_scale = Video.draw(t, 0, 0, DESIGN_W, DESIGN_H, r, g, b, 1.0)
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

local function drawMenu()
  love.graphics.clear(0.03, 0.01, 0.05, 1)
  -- preview the silhouette midway
  local previewT = (love.timer.getTime() * 0.5) % math.max(1, Video.duration())
  Video.draw(previewT, DESIGN_W*0.5 - 720, DESIGN_H*0.5 - 540, 1440, 1080, 0.6, 0.4, 0.7, 0.55)
  love.graphics.setColor(0,0,0,0.55)
  love.graphics.rectangle("fill", 0, 0, DESIGN_W, DESIGN_H)
  love.graphics.setFont(font_big)
  love.graphics.setColor(1, 0.85, 0.95, 1)
  love.graphics.printf("BAD  APPLE", 0, 220, DESIGN_W, "center")
  love.graphics.setFont(font_med)
  love.graphics.setColor(1, 0.55, 0.85, 1)
  love.graphics.printf("BEAT  DASH", 0, 340, DESIGN_W, "center")
  love.graphics.setFont(font_small)
  love.graphics.setColor(1,1,1,0.85)
  local lines = {
    "ENTER  / SPACE   start from beginning",
    ((Save.state.last_checkpoint or 0) > 5)
      and string.format("C   continue from %d:%02d", math.floor(Save.state.last_checkpoint/60), Save.state.last_checkpoint%60)
      or  "(checkpoints save every 12s during play)",
    string.format("L   replay-on-win  [%s]", LOOP and "ON" or "OFF"),
    string.format("M   lobby ghosts   [%s]", Net.enabled and "ON" or "OFF"),
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

local function drawWin()
  love.graphics.setColor(0,0,0,0.55)
  love.graphics.rectangle("fill", 0, 0, DESIGN_W, DESIGN_H)
  love.graphics.setFont(font_big)
  love.graphics.setColor(0.85, 1.0, 0.95, 1)
  love.graphics.printf("APPLE  CONSUMED", 0, 220, DESIGN_W, "center")
  love.graphics.setFont(font_med)
  love.graphics.setColor(1, 0.85, 0.95, 1)
  love.graphics.printf(string.format("score %07d   hits %d   dashes %d   best combo x%d",
    score, player and player.hits or 0, player and player.dashes or 0, math.floor(best_combo)),
    0, 380, DESIGN_W, "center")
  love.graphics.setFont(font_small)
  love.graphics.setColor(1,1,1,0.85)
  love.graphics.printf("ENTER  " .. (LOOP and "play again" or "back to menu"),
    0, 500, DESIGN_W, "center")
  love.graphics.printf(string.format("L  replay-on-win  [%s]", LOOP and "ON" or "OFF"),
    0, 540, DESIGN_W, "center")
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
  else
    drawSilhouetteWithGlow(audio_t)
    Net.draw()
    Obstacles.drawAll(accent)
    if player then player:draw(accent) end
    drawHUD()
    drawScreenFlash()
    if state == "paused"   then drawPaused()        end
    if state == "dying"    then drawOverScreen()    end
    if state == "reviving" then drawNotOverScreen() end
    if state == "win"      then drawWin()           end
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
