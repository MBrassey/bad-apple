-- Bad Apple silhouette playback.
-- Source video extracted to 75 monochrome spritesheets, 8x11 frames at 480x360 each.
-- Sheet index: floor(frame / 88). Quad position within sheet: (frame % 88).
local M = {}

local SHEET_COLS = 8
local SHEET_ROWS = 11
local FRAME_W    = 480
local FRAME_H    = 360
local FPS        = 30
local FRAMES_PER_SHEET = SHEET_COLS * SHEET_ROWS  -- 88

M.fps      = FPS
M.frame_w  = FRAME_W
M.frame_h  = FRAME_H

local sheets = {}
local quads  = {}
local total_frames = 0
local total_duration = 0

function M.load(progress_cb)
  local files = love.filesystem.getDirectoryItems("assets/sheets")
  table.sort(files)
  for i, name in ipairs(files) do
    local img = love.graphics.newImage("assets/sheets/" .. name)
    img:setFilter("linear", "linear")
    sheets[i] = img
    if progress_cb then progress_cb(i, #files) end
  end
  -- prebuild quads (one per local index 0..87)
  local sw, sh = sheets[1]:getDimensions()
  for q = 0, FRAMES_PER_SHEET - 1 do
    local cx = q % SHEET_COLS
    local cy = math.floor(q / SHEET_COLS)
    quads[q] = love.graphics.newQuad(cx * FRAME_W, cy * FRAME_H, FRAME_W, FRAME_H, sw, sh)
  end
  total_frames = #sheets * FRAMES_PER_SHEET
  total_duration = total_frames / FPS
end

function M.totalFrames() return total_frames end
function M.duration()    return total_duration end

function M.frameAt(t)
  local f = math.floor(t * FPS)
  if f < 0 then f = 0 end
  if f >= total_frames then f = total_frames - 1 end
  return f
end

-- Draw the silhouette frame for time `t` filling target rect (x,y,w,h).
-- Source aspect 4:3 fitted into target with letterbox (centered horizontally).
function M.draw(t, x, y, w, h, r, g, b, a)
  local f = M.frameAt(t)
  local sheetIdx = math.floor(f / FRAMES_PER_SHEET) + 1
  local localIdx = f % FRAMES_PER_SHEET
  local img = sheets[sheetIdx]
  if not img then return end
  local q = quads[localIdx]

  local scale = math.min(w / FRAME_W, h / FRAME_H)
  local dw = FRAME_W * scale
  local dh = FRAME_H * scale
  local dx = x + (w - dw) * 0.5
  local dy = y + (h - dh) * 0.5

  love.graphics.setColor(r or 1, g or 1, b or 1, a or 1)
  love.graphics.draw(img, q, dx, dy, 0, scale, scale)
  return dx, dy, dw, dh, scale
end

-- Compute the destination transform a draw() call would use without drawing.
function M.fitRect(w, h)
  local scale = math.min(w / FRAME_W, h / FRAME_H)
  local dw = FRAME_W * scale
  local dh = FRAME_H * scale
  return scale, dw, dh
end

return M
