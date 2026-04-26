-- Save / checkpoint state.
-- One file: save.json
--   { best_time = number, last_checkpoint = number, runs = int, deaths = int,
--     dashes = int, hits_taken = int, completed = bool, version = 1 }
local json = require "lib.json"

local M = {}

M.path = "save.json"
M.state = {
  best_time = 0,
  last_checkpoint = 0,
  runs = 0,
  deaths = 0,
  dashes = 0,
  hits_taken = 0,
  completed = false,
  version = 1,
}

function M.load()
  if not love.filesystem.getInfo(M.path) then return end
  local s = love.filesystem.read(M.path)
  if not s then return end
  local ok, data = pcall(json.decode, s)
  if ok and type(data) == "table" then
    for k, v in pairs(data) do M.state[k] = v end
  end
end

function M.write()
  love.filesystem.write(M.path, json.encode(M.state))
end

return M
