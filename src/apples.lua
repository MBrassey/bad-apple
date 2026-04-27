-- Glowing apple pickups. Spawn on a slow timer during play, drift gently,
-- pulse with a soft glow, fade after 12 s. Touching one with the player
-- adds 1 to the persistent apple count and triggers a sparkle pop.
local M = {}

M.list = {}
M._spawn_acc = 0

local SPAWN_PERIOD_BASE = 5.5     -- seconds between spawns at low intensity
local SPAWN_PERIOD_MIN  = 3.2     -- at full intensity
local LIFE              = 12
local R                 = 16      -- pickup hit radius

local PLAY = { x = 80, y = 100, w = 1920 - 160, h = 1080 - 200 }

local function rand(a, b) return a + love.math.random() * (b - a) end

function M.reset()
  M.list = {}
  M._spawn_acc = 0
end

function M.spawn(x, y)
  local a = love.math.random() * math.pi * 2
  table.insert(M.list, {
    x = x or rand(PLAY.x, PLAY.x + PLAY.w),
    y = y or rand(PLAY.y, PLAY.y + PLAY.h),
    vx = math.cos(a) * 18,
    vy = math.sin(a) * 18,
    age = 0,
    bob = love.math.random() * math.pi * 2,
    collected = false,
    pop = 0,
  })
end

M.magnet  = false   -- apples drift toward player when true
M.magnet2 = false   -- doubled magnet range
M.spawn_boost = false  -- 30 % faster spawn cadence
M.player_ref = nil

function M.update(dt, intensity)
  -- spawn timer
  local period = SPAWN_PERIOD_BASE
                  + (SPAWN_PERIOD_MIN - SPAWN_PERIOD_BASE) * math.min(1, intensity * 1.4)
  if M.spawn_boost then period = period * 0.70 end
  M._spawn_acc = M._spawn_acc + dt
  if M._spawn_acc >= period then
    M._spawn_acc = 0
    M.spawn()
  end

  for i = #M.list, 1, -1 do
    local a = M.list[i]
    a.age = a.age + dt
    a.bob = a.bob + dt * 2.6
    if not a.collected then
      a.x = a.x + a.vx * dt
      a.y = a.y + a.vy * dt
      a.vx = a.vx * (1 - dt * 0.6)
      a.vy = a.vy * (1 - dt * 0.6)
      if M.magnet and M.player_ref then
        local range = M.magnet2 and 820 or 480
        local strength = M.magnet2 and 320 or 220
        local dx, dy = M.player_ref.x - a.x, M.player_ref.y - a.y
        local d = math.sqrt(dx*dx + dy*dy)
        if d > 1 and d < range then
          local pull = strength * (1 - d / range)
          a.vx = a.vx + (dx/d) * pull * dt
          a.vy = a.vy + (dy/d) * pull * dt
        end
      end
      if a.x < PLAY.x then a.vx = a.vx + 30 * dt end
      if a.x > PLAY.x + PLAY.w then a.vx = a.vx - 30 * dt end
      if a.y < PLAY.y then a.vy = a.vy + 30 * dt end
      if a.y > PLAY.y + PLAY.h then a.vy = a.vy - 30 * dt end
    else
      a.pop = a.pop + dt
    end
    if a.age >= LIFE or (a.collected and a.pop > 0.55) then
      table.remove(M.list, i)
    end
  end
end

-- Collect any apples touched by the player. Returns the number collected.
function M.collect(player)
  local n = 0
  for _, a in ipairs(M.list) do
    if not a.collected then
      local dx, dy = player.x - a.x, player.y - a.y
      if dx*dx + dy*dy < (R + player.size * 0.35) * (R + player.size * 0.35) then
        a.collected = true
        a.pop = 0
        n = n + 1
      end
    end
  end
  return n
end

function M.draw()
  for _, a in ipairs(M.list) do
    local fade = 1
    if a.age > LIFE - 2 then fade = (LIFE - a.age) / 2 end
    if a.collected then
      -- pop animation: expand and fade
      local k = 1 - a.pop / 0.55
      local s = R * (1 + (1 - k) * 1.6)
      love.graphics.setColor(0.95, 0.45, 0.65, 0.55 * k)
      love.graphics.circle("fill", a.x, a.y, s * 1.3)
      love.graphics.setColor(1, 1, 1, k)
      love.graphics.circle("line", a.x, a.y, s)
    else
      local bob_y = a.y + math.sin(a.bob) * 4
      -- outer glow halos
      for i = 6, 1, -1 do
        love.graphics.setColor(1.0, 0.45, 0.55, 0.06 * fade)
        love.graphics.circle("fill", a.x, bob_y, R + i * 5)
      end
      -- pulsing white border
      local pulse = 0.85 + 0.15 * math.sin(a.bob * 2.8)
      love.graphics.setColor(1, 1, 1, pulse * fade)
      love.graphics.setLineWidth(3)
      love.graphics.circle("line", a.x, bob_y, R + 1)
      -- red apple body
      love.graphics.setColor(1.0, 0.30, 0.45, fade)
      love.graphics.circle("fill", a.x, bob_y, R - 1)
      -- white shine
      love.graphics.setColor(1, 1, 1, 0.85 * fade)
      love.graphics.circle("fill", a.x - R * 0.32, bob_y - R * 0.32, R * 0.22)
      -- stem
      love.graphics.setColor(0.5, 0.30, 0.18, fade)
      love.graphics.setLineWidth(3)
      love.graphics.line(a.x + 1, bob_y - R + 1, a.x + 5, bob_y - R - 6)
      -- leaf
      love.graphics.setColor(0.50, 0.85, 0.45, fade)
      love.graphics.circle("fill", a.x + 8, bob_y - R - 4, 4)
      love.graphics.setLineWidth(1)
    end
  end
end

return M
