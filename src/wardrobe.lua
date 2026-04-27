-- Wardrobe panel: scrollable grid of icon tiles for the lobby's APPEARANCE
-- column. Each tile renders a small inline preview via Player.drawIcon and
-- is clickable. Locked tiles are darkened with a padlock badge.
local Player = require "src.player"

local M = {}

M.scroll_y = 0      -- pixels of scroll offset (clamped each frame)
M.max_scroll = 0
M.bounds = { x = 0, y = 0, w = 0, h = 0 }
M.hitrects = {}     -- { x, y, w, h, kind, idx, locked }

local TILE      = 70
local TILE_GAP  = 10
local SECTION_H = 56

local function drawSwatchTile(x, y, sz, rgb, sel, locked)
  if sel and not locked then
    for g = 4, 1, -1 do
      love.graphics.setColor(rgb[1], rgb[2], rgb[3], 0.10)
      love.graphics.rectangle("fill", x - g*3, y - g*3, sz + g*6, sz + g*6, 8 + g*2, 8 + g*2)
    end
  end
  love.graphics.setColor(0.045, 0.05, 0.075, 1.0)
  love.graphics.rectangle("fill", x, y, sz, sz, 8, 8)
  if locked then
    local g = (rgb[1] + rgb[2] + rgb[3]) / 6
    love.graphics.setColor(g, g, g, 0.6)
  else
    love.graphics.setColor(rgb[1], rgb[2], rgb[3], 1.0)
  end
  local pad = 8
  love.graphics.rectangle("fill", x + pad, y + pad, sz - pad*2, sz - pad*2, 6, 6)
  if sel then
    love.graphics.setColor(1, 1, 1, 1.0)
    love.graphics.setLineWidth(2.5)
    love.graphics.rectangle("line", x + 1, y + 1, sz - 2, sz - 2, 8, 8)
    love.graphics.setLineWidth(1)
  else
    love.graphics.setColor(1, 1, 1, locked and 0.10 or 0.30)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, sz - 1, sz - 1, 8, 8)
  end
end

local function drawIconTile(x, y, sz, kind, item, sel, locked, accent)
  if sel and not locked then
    for g = 4, 1, -1 do
      love.graphics.setColor(accent[1], accent[2], accent[3], 0.10)
      love.graphics.rectangle("fill", x - g*3, y - g*3, sz + g*6, sz + g*6, 8 + g*2, 8 + g*2)
    end
  end
  love.graphics.setColor(0.045, 0.05, 0.075, 1.0)
  love.graphics.rectangle("fill", x, y, sz, sz, 8, 8)
  -- preview icon
  local cx, cy, r = x + sz * 0.5, y + sz * 0.5, sz * 0.36
  Player.drawIcon(kind, item.id, cx, cy, r, locked and { 0.5, 0.5, 0.6 } or accent)
  if locked then
    -- darken + padlock
    love.graphics.setColor(0, 0, 0, 0.62)
    love.graphics.rectangle("fill", x, y, sz, sz, 8, 8)
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.setLineWidth(2)
    love.graphics.arc("line", "open", x + sz - 16, y + sz - 18, 5, math.pi, math.pi * 2)
    love.graphics.rectangle("fill", x + sz - 21, y + sz - 18, 10, 8, 1, 1)
    love.graphics.setLineWidth(1)
  end
  if sel then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(2.5)
    love.graphics.rectangle("line", x + 1, y + 1, sz - 2, sz - 2, 8, 8)
    love.graphics.setLineWidth(1)
  else
    love.graphics.setColor(1, 1, 1, locked and 0.10 or 0.30)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, sz - 1, sz - 1, 8, 8)
  end
end

local function recordHit(kind, idx, x, y, w, h, locked)
  table.insert(M.hitrects, { kind = kind, idx = idx, x = x, y = y, w = w, h = h, locked = locked })
end

-- Compute layout + draw the wardrobe inside (px, py, pw, ph).
-- ctx fields used: palette, color_idx, paletteUnlocked,
--   auras, aura_idx, auraUnlocked,
--   trails, trail_idx, trailUnlocked,
--   shapes, shape_idx, shapeUnlocked
function M.draw(px, py, pw, ph, ctx, accent, fonts)
  M.hitrects = {}
  M.bounds = { x = px, y = py, w = pw, h = ph }
  -- inner padded area
  local ix = px + 18
  local iy = py + 22
  local iw = pw - 36
  local content_top = iy
  local cols = math.floor((iw + TILE_GAP) / (TILE + TILE_GAP))
  if cols < 4 then cols = 4 end

  -- clip to panel bounds while drawing tiles
  love.graphics.setScissor(px, py, pw, ph)

  local function section(title, kind, items, sel_idx, isUnlocked)
    -- header
    love.graphics.setFont(fonts.med)
    love.graphics.setColor(accent[1], accent[2], accent[3], 1)
    love.graphics.print(title, ix, iy - M.scroll_y)
    iy = iy + 36
    -- selected name caption
    if items[sel_idx] then
      love.graphics.setFont(fonts.small)
      love.graphics.setColor(1, 1, 1, 0.65)
      love.graphics.print(items[sel_idx].name, ix, iy - M.scroll_y)
      iy = iy + 22
    end
    -- grid
    for i, item in ipairs(items) do
      local col = (i - 1) % cols
      local row = math.floor((i - 1) / cols)
      local tx = ix + col * (TILE + TILE_GAP)
      local ty = iy + row * (TILE + TILE_GAP) - M.scroll_y
      local sel = (i == sel_idx)
      local locked = not isUnlocked(i)
      if kind == "color" then
        drawSwatchTile(tx, ty, TILE, item.rgb, sel, locked)
      else
        drawIconTile(tx, ty, TILE, kind, item, sel, locked, accent)
      end
      recordHit(kind, i, tx, ty, TILE, TILE, locked)
    end
    local rows = math.ceil(#items / cols)
    iy = iy + rows * (TILE + TILE_GAP) + 28
  end

  section("COLOUR",  "color", ctx.palette, ctx.color_idx, ctx.paletteUnlocked)
  section("AURA",    "aura",  ctx.auras,   ctx.aura_idx,  ctx.auraUnlocked)
  section("TRAIL",   "trail", ctx.trails,  ctx.trail_idx, ctx.trailUnlocked)
  section("SHAPE",   "shape", ctx.shapes,  ctx.shape_idx, ctx.shapeUnlocked)

  love.graphics.setScissor()

  -- track total content height for scroll clamp
  local content_bottom = iy
  M.max_scroll = math.max(0, (content_bottom - content_top) - ph + 30)
  M.scroll_y = math.max(0, math.min(M.scroll_y, M.max_scroll))

  -- scrollbar (subtle vertical)
  if M.max_scroll > 0 then
    local trk_x = px + pw - 8
    local trk_y = py + 8
    local trk_h = ph - 16
    love.graphics.setColor(1, 1, 1, 0.08)
    love.graphics.rectangle("fill", trk_x, trk_y, 4, trk_h, 2, 2)
    local visible_ratio = ph / (ph + M.max_scroll)
    local thumb_h = math.max(28, trk_h * visible_ratio)
    local thumb_y = trk_y + (trk_h - thumb_h) * (M.scroll_y / M.max_scroll)
    love.graphics.setColor(accent[1], accent[2], accent[3], 0.85)
    love.graphics.rectangle("fill", trk_x, thumb_y, 4, thumb_h, 2, 2)
  end
end

-- Mouse-wheel pump from main.lua's love.wheelmoved.
function M.scroll(dy)
  M.scroll_y = math.max(0, math.min(M.max_scroll, M.scroll_y - dy * 36))
end

return M
