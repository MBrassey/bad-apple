-- 1-bit packed collision mask reader.
-- File: assets/collision.bin -- raw monob frames at 80x60, MSB-first within byte.
-- Frame stride = 60 rows * 10 bytes = 600 bytes.
local M = {}

local W, H = 80, 60
local ROW_BYTES   = W / 8                 -- 10
local FRAME_BYTES = ROW_BYTES * H         -- 600
M.W, M.H = W, H

-- Sheets render at 240x180 (see src/video.lua FRAME_W/FRAME_H). The collision
-- mask covers the same silhouette area at 80x60. Callers pass coordinates in
-- the sheet's video-space (0..240, 0..180) and we scale to collision cells.
local VIDEO_W, VIDEO_H = 240, 180
M.VIDEO_W, M.VIDEO_H = VIDEO_W, VIDEO_H

local data = nil
local total_frames = 0

-- Pre-baked masks: index 0..7 -> 128, 64, 32, 16, 8, 4, 2, 1
local MASKS = { 128, 64, 32, 16, 8, 4, 2, 1 }

-- Per-frame polarity. Bad Apple includes both "white silhouette on black"
-- and "black silhouette on white" sections (and full-screen flashes), so
-- the figure isn't always the same bit value. We pick the *minority* bit
-- per frame as the figure -- that's the silhouette of an object on a
-- backdrop. Frames that are nearly all-bright or all-dark are flagged
-- inactive so they can't punish the player on transition flashes.
-- _figure_bit[f] = 1 or 0 (which bit value represents the silhouette)
-- _active[f]     = true when the frame has a meaningful silhouette
local _figure_bit = {}
local _active     = {}

local POPCOUNT = {}
do
  for i = 0, 255 do
    local c, x = 0, i
    for _ = 1, 8 do
      if x % 2 == 1 then c = c + 1 end
      x = math.floor(x / 2)
    end
    POPCOUNT[i] = c
  end
end

local CELLS_PER_FRAME = 4800   -- 80 * 60
local BLANK_LO        = 80     -- < this many set bits = essentially empty
local BLANK_HI        = 4720   -- > this many = essentially full

function M.load()
  local raw, size = love.filesystem.read("assets/collision.bin")
  data = raw
  total_frames = math.floor(size / FRAME_BYTES)
  -- detect figure polarity per frame from the data we just loaded
  for f = 0, total_frames - 1 do
    local set = 0
    local off = f * FRAME_BYTES
    for i = 1, FRAME_BYTES do
      set = set + POPCOUNT[string.byte(data, off + i)]
    end
    if set < BLANK_LO or set > BLANK_HI then
      _active[f]     = false
      _figure_bit[f] = 1   -- value doesn't matter; sample() will short-circuit
    else
      _active[f]     = true
      -- minority bit = the silhouette / figure
      _figure_bit[f] = (set < (CELLS_PER_FRAME / 2)) and 1 or 0
    end
  end
end

function M.frameActive(frame) return _active[frame] == true end
function M.figureBit(frame)   return _figure_bit[frame] end

function M.totalFrames() return total_frames end

-- Sample silhouette presence at integer mask coords (cx in 0..W-1, cy in 0..H-1).
-- Returns true if the pixel is part of the figure for this frame, where the
-- figure bit is determined dynamically per frame (minority bit of the mask).
function M.sample(frame, cx, cy)
  if frame < 0 or frame >= total_frames then return false end
  if not _active[frame] then return false end
  if cx < 0 or cx >= W or cy < 0 or cy >= H then return false end
  local off = frame * FRAME_BYTES + cy * ROW_BYTES + math.floor(cx / 8) + 1
  local byte = string.byte(data, off)
  if not byte then return false end
  local mask = MASKS[(cx % 8) + 1]
  local set = (math.floor(byte / mask) % 2) == 1
  if _figure_bit[frame] == 1 then return set else return not set end
end

-- Sample at floating-point video-space coords (0..240, 0..180).
function M.sampleVideoSpace(frame, vx, vy)
  if not _active[frame] then return false end
  local cx = math.floor(vx * W / VIDEO_W)
  local cy = math.floor(vy * H / VIDEO_H)
  return M.sample(frame, cx, cy)
end

-- Test a small box (in video-space coords 0..240 / 0..180) for any
-- silhouette pixel.
function M.boxHits(frame, vx0, vy0, vx1, vy1)
  if not _active[frame] then return false end
  local fig_set = _figure_bit[frame] == 1
  local cx0 = math.max(0, math.floor(vx0 * W / VIDEO_W))
  local cy0 = math.max(0, math.floor(vy0 * H / VIDEO_H))
  local cx1 = math.min(W - 1, math.floor(vx1 * W / VIDEO_W))
  local cy1 = math.min(H - 1, math.floor(vy1 * H / VIDEO_H))
  for cy = cy0, cy1 do
    local row = frame * FRAME_BYTES + cy * ROW_BYTES + 1
    for cx = cx0, cx1 do
      local byte = string.byte(data, row + math.floor(cx / 8))
      local mask = MASKS[(cx % 8) + 1]
      local set = byte and (math.floor(byte / mask) % 2) == 1
      if set == fig_set then return true end
    end
  end
  return false
end

-- True if the box contains BOTH bright (silhouette) and dark (background)
-- pixels -- i.e. the box straddles the silhouette edge. This is what we use
-- to determine whether the player is on the silhouette boundary; lingering
-- inside the silhouette interior or outside in the backdrop does NOT
-- straddle (returns false), so neither hurts.
function M.boxStraddles(frame, vx0, vy0, vx1, vy1)
  if not _active[frame] then return false end
  local cx0 = math.max(0, math.floor(vx0 * W / VIDEO_W))
  local cy0 = math.max(0, math.floor(vy0 * H / VIDEO_H))
  local cx1 = math.min(W - 1, math.floor(vx1 * W / VIDEO_W))
  local cy1 = math.min(H - 1, math.floor(vy1 * H / VIDEO_H))
  local saw_set, saw_unset = false, false
  for cy = cy0, cy1 do
    local row = frame * FRAME_BYTES + cy * ROW_BYTES + 1
    for cx = cx0, cx1 do
      local byte = string.byte(data, row + math.floor(cx / 8))
      local mask = MASKS[(cx % 8) + 1]
      local set = byte and (math.floor(byte / mask) % 2) == 1
      if set then saw_set = true else saw_unset = true end
      if saw_set and saw_unset then return true end
    end
  end
  return false
end

return M
