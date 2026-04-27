-- The lobby IS the hub. The centre of the screen is a roam-able play space
-- where you walk around as your square and see other connected players. The
-- four HUD panels around the play area show your handle, your current
-- customisations, the unlocks you've earned, and the level intro. Walking
-- through the glowing gate on the right side starts the song.
local M = {}
local Wardrobe = require "src.wardrobe"

local DESIGN_W, DESIGN_H = 1920, 1080

-- HUD layout (sophisticated chrome around a central play box)
local TOP_H    = 130
local BOTTOM_H = 120
local SIDE_W   = 380

-- play box (where the player roams)
local PLAY = {
  x = SIDE_W,
  y = TOP_H,
  w = DESIGN_W - SIDE_W * 2,
  h = DESIGN_H - TOP_H - BOTTOM_H,
}

-- glowing gate (on the right edge of the play box)
local GATE = {
  x = PLAY.x + PLAY.w - 90,
  y = PLAY.y + PLAY.h * 0.5,
  w = 96,
  h = 240,
  trigger_r = 60,
}

M.PLAY = PLAY
M.GATE = GATE
M.player = nil
M.shader = nil
M.gate_armed = false
M._t = 0

-- Hit-rects updated on every draw so love.mousepressed can route clicks.
-- Each entry: { x, y, w, h, kind = "color"|"aura"|"trail"|"shape", idx }
M.hitrects = {}

local floor_code = [[
extern vec2 player_;
extern vec3 accent_;

// Floor: stable dark blue-grey grid. Accent only contributes to the soft
// pool of light beneath the player's square -- the rest of the canvas
// stays a calm dark theme regardless of what colour is in motion.
vec4 effect(vec4 col, Image t, vec2 uv, vec2 sc) {
  vec2 g = abs(fract(uv * 28.0) - 0.5);
  float line = smoothstep(0.46, 0.50, max(g.x, g.y));
  vec2 dp = (uv - player_) * vec2(1.0, 0.5625);
  float r = length(dp);
  float pool = smoothstep(0.30, 0.0, r) * 0.55;
  vec3 base = vec3(0.014, 0.014, 0.022)
             + vec3(0.40, 0.42, 0.55) * line * 0.10
             + accent_ * pool * 0.45;
  return vec4(base, 1.0) * col;
}
]]

function M.load()
  M.shader = love.graphics.newShader(floor_code)
end

function M.enter(player)
  M.player = player
  if M.player then
    M.player.bounds = PLAY
    M.player.x = PLAY.x + 160
    M.player.y = PLAY.y + PLAY.h * 0.5
  end
  M._t = 0
  M.gate_armed = false
end

function M.update(dt)
  M._t = M._t + dt
  if M.player and M.player.update then
    M.player.bounds = PLAY
    M.player:update(dt)
  end
  -- gate proximity: arm if player walks into the gate's trigger zone
  if M.player then
    local dx = M.player.x - GATE.x
    local dy = M.player.y - GATE.y
    local d2 = dx*dx + dy*dy
    M.gate_armed = d2 < (GATE.trigger_r * GATE.trigger_r)
  end
end

-- Returns true if the player is in the gate's trigger zone (driver should
-- transition state to play).
function M.shouldEnterLevel()
  return M.gate_armed
end

------------------------------------------------------------------
-- HUD
------------------------------------------------------------------

-- Panel chrome -- subtle, neutral, professional. Glassy fills, hairline rims,
-- accent only on the corner ticks (kept stable so the eye can rest).
local CHROME_TICK  = { 0.65, 0.78, 0.95 }
local CHROME_RIM_A = 0.32
local PANEL_TOP    = { 0.040, 0.050, 0.075, 0.92 }
local PANEL_BOT    = { 0.018, 0.020, 0.034, 0.92 }

local function panelFrame(x, y, w, h)
  -- subtle vertical gradient fill via two stacked rects with alpha bands
  love.graphics.setColor(PANEL_TOP[1], PANEL_TOP[2], PANEL_TOP[3], PANEL_TOP[4])
  love.graphics.rectangle("fill", x, y, w, h * 0.55, 10, 10)
  love.graphics.setColor(PANEL_BOT[1], PANEL_BOT[2], PANEL_BOT[3], PANEL_BOT[4])
  love.graphics.rectangle("fill", x, y + h * 0.45, w, h * 0.55, 10, 10)
  -- soft 1-pixel inner highlight along the top edge for a glassy lift
  love.graphics.setColor(1, 1, 1, 0.06)
  love.graphics.line(x + 12, y + 1, x + w - 12, y + 1)
  -- hairline rim
  love.graphics.setColor(CHROME_TICK[1], CHROME_TICK[2], CHROME_TICK[3], CHROME_RIM_A)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 10, 10)
  -- accent corner ticks (slightly brighter, very small)
  love.graphics.setColor(CHROME_TICK[1], CHROME_TICK[2], CHROME_TICK[3], 0.85)
  love.graphics.setLineWidth(2)
  local t = 18
  love.graphics.line(x, y + t, x + t, y); love.graphics.line(x + w - t, y, x + w, y + t)
  love.graphics.line(x, y + h - t, x + t, y + h); love.graphics.line(x + w - t, y + h, x + w, y + h - t)
  love.graphics.setLineWidth(1)
end

local function recordHit(kind, idx, x, y, w, h, locked)
  table.insert(M.hitrects, { kind = kind, idx = idx, x = x, y = y, w = w, h = h, locked = locked })
end

local function drawSwatch(x, y, sz, rgb, selected, locked)
  if selected and not locked then
    for g = 5, 1, -1 do
      love.graphics.setColor(rgb[1], rgb[2], rgb[3], 0.10)
      local s = sz + g * 6
      love.graphics.rectangle("fill", x + sz*0.5 - s*0.5, y + sz*0.5 - s*0.5,
                              s, s, s*0.30, s*0.30)
    end
  end
  love.graphics.setColor(1, 1, 1, selected and 1.0 or (locked and 0.18 or 0.45))
  love.graphics.rectangle("fill", x - 2, y - 2, sz + 4, sz + 4, 6, 6)
  if locked then
    local g = (rgb[1] + rgb[2] + rgb[3]) / 6
    love.graphics.setColor(g, g, g, 0.55)
    love.graphics.rectangle("fill", x, y, sz, sz, 4, 4)
    love.graphics.setColor(0.05, 0.05, 0.10, 0.7)
    love.graphics.rectangle("fill", x, y, sz, sz, 4, 4)
    -- padlock
    local cx, cy = x + sz * 0.5, y + sz * 0.5
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.setLineWidth(2)
    love.graphics.arc("line", "open", cx, cy + 1, 6, math.pi, math.pi * 2)
    love.graphics.rectangle("fill", cx - 6, cy + 1, 12, 8, 2, 2)
    love.graphics.setLineWidth(1)
  else
    love.graphics.setColor(rgb[1], rgb[2], rgb[3], 1)
    love.graphics.rectangle("fill", x, y, sz, sz, 4, 4)
    if selected then
      love.graphics.setColor(1, 1, 1, 0.55)
      love.graphics.rectangle("fill", x + 4, y + 4, sz - 8, sz - 8, 3, 3)
    end
  end
end

local function drawTopBar(accent, fonts, ctx)
  panelFrame(20, 20, DESIGN_W - 40, TOP_H - 40)
  -- handle
  love.graphics.setFont(fonts.med)
  love.graphics.setColor(accent[1], accent[2], accent[3], 1)
  love.graphics.print(ctx.handle or "guest", 50, 38)
  -- subtitle
  love.graphics.setFont(fonts.small)
  love.graphics.setColor(1, 1, 1, 0.55)
  love.graphics.print("CHARACTER HOME  //  CYBER LOBBY", 50, 80)
  -- centre: completion ring + counter (uses player's chosen colour, NOT a
  -- drifting accent, so the chrome stays calm)
  local cx = DESIGN_W * 0.5
  local cy = 65
  local pct = math.min(1, (ctx.completions or 0) / 8.0)
  love.graphics.setColor(1, 1, 1, 0.20)
  love.graphics.setLineWidth(4)
  love.graphics.arc("line", "open", cx, cy, 28, -math.pi*0.5, math.pi * 1.5)
  love.graphics.setColor(accent[1], accent[2], accent[3], 1)
  love.graphics.arc("line", "open", cx, cy, 28, -math.pi*0.5, -math.pi*0.5 + pct * math.pi * 2)
  love.graphics.setLineWidth(1)
  love.graphics.setFont(fonts.small)
  love.graphics.setColor(1, 1, 1, 0.95)
  love.graphics.printf(string.format("LEVELS CLEARED  %d", ctx.completions or 0),
                       cx - 120, cy + 38, 240, "center")
  -- right: peer count
  love.graphics.setFont(fonts.small)
  love.graphics.setColor(0.7, 0.95, 1.0, 1)
  love.graphics.printf(string.format("LOBBY  %d", ctx.peers or 0),
                       DESIGN_W - 250, 50, 200, "right")
  love.graphics.setColor(1, 1, 1, 0.55)
  love.graphics.printf(ctx.signed_in and "signed in" or "guest profile",
                       DESIGN_W - 250, 80, 200, "right")
end

local function drawLeftPanel(accent, fonts, ctx)
  local x, y, w, h = 20, TOP_H, SIDE_W - 40, DESIGN_H - TOP_H - BOTTOM_H
  panelFrame(x, y, w, h)
  -- All wardrobe content (sections + swatch grid + aura/trail/shape tiles)
  -- lives in src/wardrobe.lua. The legacy inline swatch grid was removed --
  -- it was double-drawing on top of the wardrobe tiles.
  Wardrobe.draw(x, y, w, h - 28, ctx, accent, fonts)
  love.graphics.setFont(fonts.small)
  love.graphics.setColor(1, 1, 1, 0.45)
  love.graphics.printf("scroll to browse", x, y + h - 24, w, "center")
end

local function drawRightPanel(accent, fonts, ctx)
  local x = DESIGN_W - SIDE_W + 20
  local y = TOP_H
  local w = SIDE_W - 40
  local h = DESIGN_H - TOP_H - BOTTOM_H
  panelFrame(x, y, w, h)
  love.graphics.setFont(fonts.med)
  love.graphics.setColor(accent[1], accent[2], accent[3], 1)
  love.graphics.print("PROFILE", x + 22, y + 22)
  love.graphics.setFont(fonts.small)
  love.graphics.setColor(1, 1, 1, 0.85)
  local lines = {
    string.format("levels cleared   %d", ctx.completions or 0),
    string.format("runs             %d", ctx.runs or 0),
    string.format("deaths           %d", ctx.deaths or 0),
    string.format("hits taken       %d", ctx.hits or 0),
    string.format("best time        %s", ctx.best_time and string.format("%d:%02d",
       math.floor((ctx.best_time or 0)/60), (ctx.best_time or 0) % 60) or "0:00"),
  }
  for i, line in ipairs(lines) do
    love.graphics.print(line, x + 22, y + 80 + (i - 1) * 30)
  end
  -- recent unlock
  if ctx.last_unlock then
    love.graphics.setFont(fonts.med)
    love.graphics.setColor(accent[1], accent[2], accent[3], 1)
    love.graphics.print("LATEST UNLOCK", x + 22, y + 280)
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.printf(ctx.last_unlock, x + 22, y + 320, w - 44, "left")
  end
  -- gate prompt
  love.graphics.setFont(fonts.med)
  love.graphics.setColor(accent[1], accent[2], accent[3], 1)
  love.graphics.print("THE LEVEL", x + 22, y + h - 200)
  love.graphics.setFont(fonts.small)
  love.graphics.setColor(1, 1, 1, 0.85)
  love.graphics.printf("Walk into the glowing gate on the right to begin the song. Survive the silhouette and the shapes that arrive on every beat.",
                       x + 22, y + h - 160, w - 44, "left")
end

local function drawBottomBar(accent, fonts, ctx)
  panelFrame(20, DESIGN_H - BOTTOM_H + 20, DESIGN_W - 40, BOTTOM_H - 40)
  love.graphics.setFont(fonts.small)
  love.graphics.setColor(1, 1, 1, 0.85)
  love.graphics.printf("WASD / arrows  move    SPACE / SHIFT  dash    " ..
                       "click swatches to equip    walk into the GATE to begin    ESC  exit",
                       0, DESIGN_H - BOTTOM_H + 50, DESIGN_W, "center")
end

local function drawGate(accent)
  local x, y, w, h = GATE.x - GATE.w*0.5, GATE.y - GATE.h*0.5, GATE.w, GATE.h
  local t = M._t
  local pulse = 0.55 + 0.45 * math.abs(math.sin(t * 3.5))
  -- outer glow halos
  for i = 7, 1, -1 do
    love.graphics.setColor(accent[1], accent[2], accent[3], 0.06 * pulse)
    love.graphics.rectangle("fill", x - i * 5, y - i * 5,
                            w + i * 10, h + i * 10,
                            14 + i * 2, 14 + i * 2)
  end
  -- gate body (translucent rectangle)
  love.graphics.setColor(accent[1], accent[2], accent[3], 0.30 * pulse)
  love.graphics.rectangle("fill", x, y, w, h, 12, 12)
  -- bright pulsing border
  love.graphics.setColor(1, 1, 1, pulse)
  love.graphics.setLineWidth(4)
  love.graphics.rectangle("line", x, y, w, h, 12, 12)
  love.graphics.setLineWidth(1)
  -- vertical scan lines inside the gate
  for i = 0, 4 do
    local ly = y + 20 + (h - 40) * (i / 4) + math.sin(t * 2 + i) * 3
    love.graphics.setColor(1, 1, 1, 0.30 * pulse)
    love.graphics.line(x + 6, ly, x + w - 6, ly)
  end
  -- label
  love.graphics.setColor(1, 1, 1, pulse)
  love.graphics.printf("ENTER", x - 60, y + h + 12, w + 120, "center")
  -- armed indicator (when player is in trigger range)
  if M.gate_armed then
    love.graphics.setColor(accent[1], accent[2], accent[3], 0.55 * pulse)
    love.graphics.setLineWidth(6)
    love.graphics.rectangle("line", x - 8, y - 8, w + 16, h + 16, 16, 16)
    love.graphics.setLineWidth(1)
  end
end

local function drawFloor(accent)
  if not M.shader then return end
  if M.player then
    M.shader:send("player_", { (M.player.x - PLAY.x) / PLAY.w,
                               (M.player.y - PLAY.y) / PLAY.h })
  else
    M.shader:send("player_", { 0.5, 0.5 })
  end
  M.shader:send("accent_", { accent[1], accent[2], accent[3] })
  local prev = love.graphics.getShader()
  love.graphics.setShader(M.shader)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", PLAY.x, PLAY.y, PLAY.w, PLAY.h)
  love.graphics.setShader(prev)
  -- play-area frame
  love.graphics.setColor(accent[1], accent[2], accent[3], 0.85)
  love.graphics.setLineWidth(3)
  love.graphics.rectangle("line", PLAY.x, PLAY.y, PLAY.w, PLAY.h, 8, 8)
  love.graphics.setLineWidth(1)
end

-- main entry: ctx must contain
--   handle, signed_in, peers, completions, runs, deaths, hits, best_time,
--   last_unlock, palette, color_idx, paletteUnlocked,
--   auras, aura_idx, auraUnlocked
function M.draw(accent, ctx, fonts)
  -- reset click hit-rects for this frame
  M.hitrects = {}
  -- backdrop
  love.graphics.clear(0.020, 0.012, 0.040, 1)
  drawFloor(accent)
  drawGate(accent)
  -- Bad Apple banner (small silhouette frame) in the top-right
  if ctx.bannerFrame then
    local bx, by, bw, bh = DESIGN_W - 220, 100, 180, 160
    love.graphics.setColor(0.04, 0.05, 0.08, 0.90)
    love.graphics.rectangle("fill", bx, by, bw, bh, 10, 10)
    ctx.bannerFrame(bx + 4, by + 4, bw - 8, bh - 8, accent)
    love.graphics.setColor(1, 1, 1, 0.45)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", bx + 0.5, by + 0.5, bw - 1, bh - 1, 10, 10)
    love.graphics.setLineWidth(1)
  end
  -- handle floats above your own square
  if M.player and ctx.handle then
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.printf(ctx.handle, M.player.x - 200, M.player.y - 56, 400, "center")
  end
  -- HUD frames
  drawTopBar(accent, fonts, ctx)
  drawLeftPanel(accent, fonts, ctx)
  drawRightPanel(accent, fonts, ctx)
  drawBottomBar(accent, fonts, ctx)
end

return M
