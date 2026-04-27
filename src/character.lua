-- Character / wardrobe screen.
-- A focused customisation room where the player sees their square as it will
-- appear in-game (correct colour, sparkle trail, halo if unlocked) and can
-- swap between palette colours. All choices live in save.json so the
-- character persists across sessions on the same profile.
local M = {}

local DESIGN_W, DESIGN_H = 1920, 1080

M.ghost_t = 0          -- preview animation clock

function M.update(dt) M.ghost_t = M.ghost_t + dt end

local function drawSwatchRow(palette, idx, sx0, sy, sw_size, sw_gap, is_unlocked)
  for i, p in ipairs(palette) do
    local x = sx0 + (i - 1) * (sw_size + sw_gap)
    local sel = (i == idx)
    local unlocked = is_unlocked(i)
    if sel and unlocked then
      for g = 5, 1, -1 do
        love.graphics.setColor(p.rgb[1], p.rgb[2], p.rgb[3], 0.10)
        local s = sw_size + g * 8
        love.graphics.rectangle("fill", x + sw_size*0.5 - s*0.5, sy + sw_size*0.5 - s*0.5,
                                s, s, s*0.30, s*0.30)
      end
    end
    love.graphics.setColor(1, 1, 1, sel and 1.0 or (unlocked and 0.50 or 0.20))
    love.graphics.rectangle("fill", x - 2, sy - 2, sw_size + 4, sw_size + 4, 8, 8)
    if unlocked then
      love.graphics.setColor(p.rgb[1], p.rgb[2], p.rgb[3], 1.0)
    else
      -- desaturated locked swatch
      local g = (p.rgb[1] + p.rgb[2] + p.rgb[3]) / 6
      love.graphics.setColor(g, g, g, 0.55)
    end
    love.graphics.rectangle("fill", x, sy, sw_size, sw_size, 6, 6)
    if sel and unlocked then
      love.graphics.setColor(1, 1, 1, 0.55)
      love.graphics.rectangle("fill", x + 4, sy + 4, sw_size - 8, sw_size - 8, 4, 4)
    elseif not unlocked then
      -- lock icon: a tiny padlock-like rectangle with a bow
      local cx, cy = x + sw_size * 0.5, sy + sw_size * 0.5
      love.graphics.setColor(0.05, 0.05, 0.10, 0.70)
      love.graphics.rectangle("fill", x, sy, sw_size, sw_size, 6, 6)
      love.graphics.setColor(1, 1, 1, 0.85)
      love.graphics.setLineWidth(3)
      love.graphics.arc("line", "open", cx, cy + 2, 9, math.pi, math.pi * 2)
      love.graphics.rectangle("fill", cx - 9, cy + 2, 18, 12, 2, 2)
      love.graphics.setLineWidth(1)
    end
  end
end

-- Renders the wardrobe.
-- args:
--   palette       -- list of {name, rgb}
--   color_idx     -- which palette index is selected
--   upgrades      -- Save.state.upgrades table
--   stats         -- table with apples, runs, deaths, hits, completed, best_time
--   player        -- a Player instance positioned offscreen for preview drawing
--   handle        -- portal-auth handle (or "guest" / "you")
--   fonts         -- { huge, big, med, small, hud }
function M.draw(palette, color_idx, upgrades, stats, player, handle, fonts,
                paletteUnlocked, auras, aura_idx, auraUnlocked)
  -- backdrop
  love.graphics.clear(0.04, 0.02, 0.07, 1)
  -- soft accent rim
  local accent = palette[color_idx].rgb
  for i = 6, 1, -1 do
    love.graphics.setColor(accent[1], accent[2], accent[3], 0.04)
    love.graphics.rectangle("fill", 60 - i * 6, 60 - i * 6,
                            DESIGN_W - 120 + i * 12, DESIGN_H - 120 + i * 12,
                            24 + i * 4, 24 + i * 4)
  end
  -- header
  love.graphics.setFont(fonts.big)
  love.graphics.setColor(1, 0.85, 0.95, 1)
  love.graphics.printf("CHARACTER", 0, 80, DESIGN_W, "center")
  love.graphics.setFont(fonts.small)
  love.graphics.setColor(1, 1, 1, 0.65)
  love.graphics.printf("LEFT / RIGHT  pick colour     ENTER  begin     ESC  menu",
                       0, 200, DESIGN_W, "center")
  -- handle banner
  love.graphics.setFont(fonts.med)
  love.graphics.setColor(accent[1], accent[2], accent[3], 1)
  love.graphics.printf(handle or "guest", 0, 240, DESIGN_W, "center")

  -- preview pedestal: pulse on a slow sine + a faint shadow disk
  local px = DESIGN_W * 0.5
  local py = DESIGN_H * 0.5 + 40
  if player then
    -- shadow disk under the character
    love.graphics.setColor(0, 0, 0, 0.25)
    love.graphics.ellipse("fill", px, py + 80, 90, 18)
    -- update the preview character: synthetic motion so the sparkle trail kicks in
    local r = 60
    local ax = math.cos(M.ghost_t * 0.8) * r
    local ay = math.sin(M.ghost_t * 1.6) * (r * 0.4)
    player.x = px + ax
    player.y = py + ay
    player.vx = -math.sin(M.ghost_t * 0.8) * r * 0.8
    player.vy =  math.cos(M.ghost_t * 1.6) * r * 0.4 * 1.6
    player:draw(accent)
  end

  -- swatch row
  local n = #palette
  local sw_size = 50
  local sw_gap  = 12
  local total_w = n * sw_size + (n - 1) * sw_gap
  local sx0 = (DESIGN_W - total_w) * 0.5
  local sy  = 720
  drawSwatchRow(palette, color_idx, sx0, sy, sw_size, sw_gap, paletteUnlocked or function() return true end)
  love.graphics.setFont(fonts.small)
  love.graphics.setColor(1, 1, 1, 0.85)
  local sel = palette[color_idx]
  if paletteUnlocked and not paletteUnlocked(color_idx) then
    love.graphics.printf(string.format("%s  (locked -- %d more wins)",
                         sel.name, math.max(0, (sel.unlock_at or 0) - (stats.completions or 0))),
                         0, sy + sw_size + 12, DESIGN_W, "center")
  else
    love.graphics.printf(sel.name, 0, sy + sw_size + 12, DESIGN_W, "center")
  end

  -- aura row (separate strip below the colour row)
  if auras and aura_idx then
    local ay = sy + sw_size + 60
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(1, 1, 1, 0.55)
    love.graphics.printf("AURA  (UP / DOWN)", 0, ay, DESIGN_W, "center")
    local an = #auras
    local asize = 38
    local agap = 14
    local at = an * asize + (an - 1) * agap
    local axs = (DESIGN_W - at) * 0.5
    for i, a in ipairs(auras) do
      local ax = axs + (i - 1) * (asize + agap)
      local ay2 = ay + 32
      local sela = (i == aura_idx)
      local unlocked = auraUnlocked and auraUnlocked(i) or true
      love.graphics.setColor(1, 1, 1, sela and 1.0 or (unlocked and 0.45 or 0.18))
      love.graphics.rectangle("fill", ax - 2, ay2 - 2, asize + 4, asize + 4, 7, 7)
      love.graphics.setColor(0.10, 0.07, 0.18, 1)
      love.graphics.rectangle("fill", ax, ay2, asize, asize, 5, 5)
      if unlocked then
        love.graphics.setColor(accent[1], accent[2], accent[3], 1)
        love.graphics.circle("line", ax + asize*0.5, ay2 + asize*0.5, asize*0.32)
      else
        love.graphics.setColor(1, 1, 1, 0.45)
        love.graphics.print("X", ax + asize*0.5 - 5, ay2 + asize*0.5 - 8)
      end
    end
    local seleda = auras[aura_idx]
    if seleda then
      love.graphics.setColor(1, 1, 1, 0.85)
      if auraUnlocked and not auraUnlocked(aura_idx) then
        love.graphics.printf(string.format("%s  (locked -- %d more wins)",
                             seleda.name, math.max(0, (seleda.unlock_at or 0) - (stats.completions or 0))),
                             0, ay + 90, DESIGN_W, "center")
      else
        love.graphics.printf(seleda.name, 0, ay + 90, DESIGN_W, "center")
      end
    end
  end

  -- unlocked-upgrades panel (left pane)
  local panel_x = 120
  local panel_y = 380
  love.graphics.setFont(fonts.med)
  love.graphics.setColor(1, 0.85, 0.95, 1)
  love.graphics.printf("UNLOCKED", panel_x, panel_y, 460, "left")
  love.graphics.setFont(fonts.small)
  local rows = {
    { key = "sparkles",   label = "Bigger Sparkle Trail" },
    { key = "halo",       label = "Brighter Aura"        },
    { key = "dash",       label = "Quicker Dash"         },
    { key = "magnet",     label = "Apple Magnet"         },
    { key = "magnet2",    label = "Greater Magnet"       },
    { key = "hp",         label = "Extra Heart"          },
    { key = "revive2",    label = "Second Wind"          },
    { key = "score",      label = "Sharper Score"        },
    { key = "apple_rate", label = "Orchard's Bounty"     },
  }
  for i, r in ipairs(rows) do
    local y = panel_y + 60 + (i - 1) * 32
    local owned = upgrades and upgrades[r.key]
    if owned then
      love.graphics.setColor(0.55, 1.00, 0.65, 1)
      love.graphics.print("[+]", panel_x, y)
      love.graphics.setColor(1, 1, 1, 0.95)
    else
      love.graphics.setColor(1, 1, 1, 0.30)
      love.graphics.print("[ ]", panel_x, y)
    end
    love.graphics.print(r.label, panel_x + 50, y)
  end

  -- profile / stats panel (right pane)
  local stats_x = DESIGN_W - 580
  love.graphics.setFont(fonts.med)
  love.graphics.setColor(1, 0.85, 0.95, 1)
  love.graphics.printf("PROFILE", stats_x, panel_y, 460, "left")
  love.graphics.setFont(fonts.small)
  love.graphics.setColor(1, 1, 1, 0.9)
  local lines = {
    string.format("apples eaten   %d", stats.apples or 0),
    string.format("runs           %d", stats.runs or 0),
    string.format("deaths         %d", stats.deaths or 0),
    string.format("hits taken     %d", stats.hits or 0),
    string.format("completed      %s", stats.completed and "yes" or "no"),
    string.format("best time      %s", stats.best_time and string.format("%d:%02d",
       math.floor((stats.best_time or 0)/60), (stats.best_time or 0) % 60) or "0:00"),
  }
  for i, line in ipairs(lines) do
    love.graphics.print(line, stats_x, panel_y + 60 + (i - 1) * 32)
  end

  -- footer help
  love.graphics.setFont(fonts.small)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.printf("B  apple shop      M  cyber lobby      L  replay-on-win",
                       0, DESIGN_H - 60, DESIGN_W, "center")
end

return M
