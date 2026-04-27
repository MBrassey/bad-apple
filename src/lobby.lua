-- Cyber lobby state. A neon grid floor where you and other connected
-- players can move and dash around, see each other's chosen colours,
-- handles, and customisations in real time. Uses [[LOVEWEB_NET]]
-- via src/multiplayer.lua so it all flows through the portal.
local M = {}

local DESIGN_W, DESIGN_H = 1920, 1080
local PLAY = { x = 80, y = 100, w = 1920 - 160, h = 1080 - 200 }

M.player = nil          -- a Player instance reused from gameplay
M.shader = nil          -- floor grid shader
M._t = 0

local floor_code = [[
extern number time_;
extern vec2 player_;
extern vec3 accent_;

vec4 effect(vec4 col, Image t, vec2 uv, vec2 sc) {
  // grid lines
  vec2 g = abs(fract(uv * 30.0) - 0.5);
  float line = smoothstep(0.46, 0.50, max(g.x, g.y));
  // soft radial glow under the player
  vec2 dp = (uv - player_) * vec2(1.0, 0.5625);   // 16:9 correction
  float r = length(dp);
  float pool = smoothstep(0.35, 0.0, r) * 0.55;
  // base dark with accent tint and pool glow
  vec3 base = vec3(0.025, 0.020, 0.060) + accent_ * (line * 0.18 + pool * 0.50);
  // moving scan band
  float band = smoothstep(0.92, 1.00, fract(uv.y * 4.0 - time_ * 0.2));
  base += accent_ * band * 0.10;
  return vec4(base, 1.0) * col;
}
]]

function M.load()
  M.shader = love.graphics.newShader(floor_code)
end

function M.enter(player)
  M.player = player
  M._t = 0
end

function M.update(dt)
  M._t = M._t + dt
  if M.player and M.player.update then
    -- move freely; clamp to play bounds
    M.player.bounds = PLAY
    M.player:update(dt)
  end
end

local function drawFloor(accent)
  if not M.shader then return end
  M.shader:send("time_", M._t)
  if M.player then
    M.shader:send("player_", { M.player.x / DESIGN_W, M.player.y / DESIGN_H })
  else
    M.shader:send("player_", { 0.5, 0.5 })
  end
  M.shader:send("accent_", { accent[1], accent[2], accent[3] })
  local prev = love.graphics.getShader()
  love.graphics.setShader(M.shader)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, DESIGN_W, DESIGN_H)
  love.graphics.setShader(prev)
end

function M.draw(accent, peerCount, lobbyName, myHandle)
  drawFloor(accent)
  -- title strip
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", 0, 0, DESIGN_W, 90)
  love.graphics.setColor(accent[1], accent[2], accent[3], 1)
  love.graphics.printf(lobbyName or "CYBER LOBBY", 0, 30, DESIGN_W, "center")
  love.graphics.setColor(1, 1, 1, 0.7)
  love.graphics.printf(string.format("connected: you + %d", peerCount or 0),
                       0, DESIGN_H - 70, DESIGN_W, "center")
  love.graphics.printf("WASD / arrows  move    SPACE / SHIFT  dash    ESC  leave",
                       0, DESIGN_H - 40, DESIGN_W, "center")
  -- authenticated handle floating above the player's own square
  if M.player and myHandle then
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.printf(myHandle, M.player.x - 200, M.player.y - 60, 400, "center")
  end
end

return M
