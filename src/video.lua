-- Bad Apple silhouette playback with lazy spritesheet loading.
--
-- Source video unpacked into N small monochrome spritesheets:
--   - frame size:    240 x 180 (FRAME_W x FRAME_H)
--   - tile layout:   8 cols x 8 rows -> 64 frames per sheet
--   - sheet size:    1920 x 1440  (~11 MB GPU once decoded to RGBA8)
--
-- Sheets are streamed on demand. Only `CACHE_LIMIT` sheets stay resident at
-- any moment, so peak VRAM is bounded regardless of total song length. The
-- next sheet is prefetched a beat ahead of the playhead so crossings are
-- seamless.
local M = {}

local SHEET_COLS = 8
local SHEET_ROWS = 8
local FRAME_W    = 240
local FRAME_H    = 180
local FPS        = 30
local FRAMES_PER_SHEET = SHEET_COLS * SHEET_ROWS  -- 64
local CACHE_LIMIT = 4

M.fps      = FPS
M.frame_w  = FRAME_W
M.frame_h  = FRAME_H

local files = {}
local cache = {}                               -- sheetIdx -> { img = Image, used = monotonic }
local cache_use = 0
local quads = {}
local sheet_w, sheet_h = 0, 0
local total_frames = 0
local total_duration = 0

local function evictIfNeeded()
  local count = 0
  for _ in pairs(cache) do count = count + 1 end
  while count > CACHE_LIMIT do
    local lru, lru_idx = math.huge, nil
    for idx, entry in pairs(cache) do
      if entry.used < lru then lru, lru_idx = entry.used, idx end
    end
    if not lru_idx then break end
    if cache[lru_idx].img and cache[lru_idx].img.release then
      cache[lru_idx].img:release()             -- release Image GPU memory
    end
    cache[lru_idx] = nil
    count = count - 1
  end
end

-- Synchronously load one sheet by index (1-based) into the cache.
local function ensureSheet(idx)
  if cache[idx] then
    cache[idx].used = cache_use; cache_use = cache_use + 1
    return cache[idx].img
  end
  local path = "assets/sheets/" .. files[idx]
  if not path then return nil end
  local ok, img = pcall(love.graphics.newImage, path)
  if not ok or not img then return nil end
  img:setFilter("linear", "linear")
  if sheet_w == 0 then
    sheet_w, sheet_h = img:getDimensions()
    -- build quads now that we know sheet pixel dims
    for q = 0, FRAMES_PER_SHEET - 1 do
      local cx = q % SHEET_COLS
      local cy = math.floor(q / SHEET_COLS)
      quads[q] = love.graphics.newQuad(cx * FRAME_W, cy * FRAME_H, FRAME_W, FRAME_H, sheet_w, sheet_h)
    end
  end
  cache[idx] = { img = img, used = cache_use }
  cache_use = cache_use + 1
  evictIfNeeded()
  return img
end

-- Public API ---------------------------------------------------------------

function M.totalFrames() return total_frames end
function M.duration()    return total_duration end
function M.fps()         return FPS end

-- Initialize file list and totals. No GPU work done here.
function M.init()
  files = love.filesystem.getDirectoryItems("assets/sheets")
  table.sort(files)
  total_frames   = #files * FRAMES_PER_SHEET
  total_duration = total_frames / FPS
end

-- Compatibility shims for the old Video.beginLoad / loadStep / loadProgress
-- contract that main.lua still drives during boot. With lazy loading the boot
-- only needs to read the directory and warm the first one or two sheets so
-- the menu has something to render.
local _boot
function M.beginLoad()
  M.init()
  _boot = { i = 0, target = math.min(2, #files) }
end

function M.loadStep(n)
  if not _boot then return true end
  n = n or 1
  for _ = 1, n do
    if _boot.i >= _boot.target then break end
    _boot.i = _boot.i + 1
    ensureSheet(_boot.i)
  end
  if _boot.i >= _boot.target then _boot = nil; return true end
  return false
end

function M.loadProgress()
  if not _boot or _boot.target == 0 then return 1 end
  return _boot.i / _boot.target
end

-- Old synchronous load entry point still works (used by tests / scripts).
function M.load(progress_cb)
  M.beginLoad()
  while not M.loadStep(1) do
    if progress_cb and _boot then progress_cb(_boot.i, _boot.target) end
  end
end

-- Convert an audio time to the corresponding frame index (0-based).
function M.frameAt(t)
  local f = math.floor(t * FPS)
  if f < 0 then f = 0 end
  if f >= total_frames then f = total_frames - 1 end
  return f
end

-- Fit transform of source (FRAME_W x FRAME_H) inside (w,h) target.
function M.fitRect(w, h)
  local scale = math.min(w / FRAME_W, h / FRAME_H)
  local dw = FRAME_W * scale
  local dh = FRAME_H * scale
  return scale, dw, dh
end

-- Draw the silhouette frame for time `t` filling target rect (x,y,w,h).
function M.draw(t, x, y, w, h, r, g, b, a)
  local f = M.frameAt(t)
  local sheetIdx = math.floor(f / FRAMES_PER_SHEET) + 1
  local localIdx = f % FRAMES_PER_SHEET

  -- ensure the active sheet is loaded; this can stall ~10-20 ms on the
  -- frame we cross a sheet boundary -- prefetch in M.update mitigates that.
  local img = ensureSheet(sheetIdx)
  if not img then return end
  local q = quads[localIdx]
  if not q then return end

  local scale = math.min(w / FRAME_W, h / FRAME_H)
  local dw = FRAME_W * scale
  local dh = FRAME_H * scale
  local dx = x + (w - dw) * 0.5
  local dy = y + (h - dh) * 0.5

  love.graphics.setColor(r or 1, g or 1, b or 1, a or 1)
  love.graphics.draw(img, q, dx, dy, 0, scale, scale)
  return dx, dy, dw, dh, scale
end

-- Call from love.update. Looks ahead `lookahead` seconds and ensures the next
-- sheet is loaded so playback never stalls on a fresh sheet.
function M.update(t, lookahead)
  lookahead = lookahead or 0.5
  local f = math.floor((t + lookahead) * FPS)
  if f < 0 then f = 0 end
  if f >= total_frames then return end
  local sheetIdx = math.floor(f / FRAMES_PER_SHEET) + 1
  if sheetIdx <= #files then ensureSheet(sheetIdx) end
end

return M
