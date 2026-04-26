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

local _load = nil  -- incremental loader state

-- Begin an incremental load. Returns immediately. Call M.loadStep(n) until it
-- returns true to load `n` sheets per call (keeps the boot screen responsive).
function M.beginLoad()
  local files = love.filesystem.getDirectoryItems("assets/sheets")
  table.sort(files)
  _load = { files = files, i = 0 }
end

function M.loadStep(n)
  n = n or 2
  if not _load then return true end
  for _ = 1, n do
    _load.i = _load.i + 1
    if _load.i > #_load.files then break end
    local img = love.graphics.newImage("assets/sheets/" .. _load.files[_load.i])
    img:setFilter("linear", "linear")
    sheets[_load.i] = img
  end
  if _load.i >= #_load.files then
    -- finalize: build quads and totals
    local sw, sh = sheets[1]:getDimensions()
    for q = 0, FRAMES_PER_SHEET - 1 do
      local cx = q % SHEET_COLS
      local cy = math.floor(q / SHEET_COLS)
      quads[q] = love.graphics.newQuad(cx * FRAME_W, cy * FRAME_H, FRAME_W, FRAME_H, sw, sh)
    end
    total_frames = #sheets * FRAMES_PER_SHEET
    total_duration = total_frames / FPS
    _load = nil
    return true
  end
  return false
end

function M.loadProgress()
  if not _load then return 1 end
  return _load.i / #_load.files
end

-- Synchronous load kept for parity but routes through the incremental path.
function M.load(progress_cb)
  M.beginLoad()
  while not M.loadStep(8) do
    if progress_cb then progress_cb(_load.i, #_load.files) end
  end
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
