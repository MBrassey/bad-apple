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

function M.load()
  local raw, size = love.filesystem.read("assets/collision.bin")
  data = raw
  total_frames = math.floor(size / FRAME_BYTES)
end

function M.totalFrames() return total_frames end

-- Sample silhouette presence at integer mask coords (cx in 0..W-1, cy in 0..H-1).
-- Returns true if pixel is part of the bright silhouette (bit == 1).
function M.sample(frame, cx, cy)
  if frame < 0 or frame >= total_frames then return false end
  if cx < 0 or cx >= W or cy < 0 or cy >= H then return false end
  local off = frame * FRAME_BYTES + cy * ROW_BYTES + math.floor(cx / 8) + 1
  local byte = string.byte(data, off)
  if not byte then return false end
  local mask = MASKS[(cx % 8) + 1]
  return (math.floor(byte / mask) % 2) == 1
end

-- Sample at floating-point video-space coords (0..240, 0..180).
function M.sampleVideoSpace(frame, vx, vy)
  local cx = math.floor(vx * W / VIDEO_W)
  local cy = math.floor(vy * H / VIDEO_H)
  return M.sample(frame, cx, cy)
end

-- Test a small box (in video-space coords 0..240 / 0..180) for any
-- silhouette pixel.
function M.boxHits(frame, vx0, vy0, vx1, vy1)
  local cx0 = math.max(0, math.floor(vx0 * W / VIDEO_W))
  local cy0 = math.max(0, math.floor(vy0 * H / VIDEO_H))
  local cx1 = math.min(W - 1, math.floor(vx1 * W / VIDEO_W))
  local cy1 = math.min(H - 1, math.floor(vy1 * H / VIDEO_H))
  for cy = cy0, cy1 do
    local row = frame * FRAME_BYTES + cy * ROW_BYTES + 1
    for cx = cx0, cx1 do
      local byte = string.byte(data, row + math.floor(cx / 8))
      local mask = MASKS[(cx % 8) + 1]
      if byte and (math.floor(byte / mask) % 2) == 1 then return true end
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
  local cx0 = math.max(0, math.floor(vx0 * W / VIDEO_W))
  local cy0 = math.max(0, math.floor(vy0 * H / VIDEO_H))
  local cx1 = math.min(W - 1, math.floor(vx1 * W / VIDEO_W))
  local cy1 = math.min(H - 1, math.floor(vy1 * H / VIDEO_H))
  local saw_bright, saw_dark = false, false
  for cy = cy0, cy1 do
    local row = frame * FRAME_BYTES + cy * ROW_BYTES + 1
    for cx = cx0, cx1 do
      local byte = string.byte(data, row + math.floor(cx / 8))
      local mask = MASKS[(cx % 8) + 1]
      local set = byte and (math.floor(byte / mask) % 2) == 1
      if set then saw_bright = true else saw_dark = true end
      if saw_bright and saw_dark then return true end
    end
  end
  return false
end

return M
