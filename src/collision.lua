-- 1-bit packed collision mask reader.
-- File: assets/collision.bin -- raw monob frames at 80x60, MSB-first within byte.
-- Frame stride = 60 rows * 10 bytes = 600 bytes.
local M = {}

local W, H = 80, 60
local ROW_BYTES   = W / 8                 -- 10
local FRAME_BYTES = ROW_BYTES * H         -- 600
M.W, M.H = W, H

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

-- Sample at floating-point video-space coords (0..480, 0..360).
function M.sampleVideoSpace(frame, vx, vy)
  local cx = math.floor(vx * W / 480)
  local cy = math.floor(vy * H / 360)
  return M.sample(frame, cx, cy)
end

-- Test a small box (in video-space coords) for any silhouette pixel.
-- vx0, vy0, vx1, vy1: bounding rect in 0..480 / 0..360 coords.
function M.boxHits(frame, vx0, vy0, vx1, vy1)
  local cx0 = math.max(0, math.floor(vx0 * W / 480))
  local cy0 = math.max(0, math.floor(vy0 * H / 360))
  local cx1 = math.min(W - 1, math.floor(vx1 * W / 480))
  local cy1 = math.min(H - 1, math.floor(vy1 * H / 360))
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

return M
