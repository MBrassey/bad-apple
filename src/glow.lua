-- Two-pass separable Gaussian blur for bloom highlights.
-- We render the bright pass to a half-res canvas, blur horizontally then
-- vertically into another half-res canvas, then additively composite onto
-- the world canvas.
local M = {}

local code_bright = [[
extern number threshold;
vec4 effect(vec4 c, Image t, vec2 uv, vec2 sc) {
  vec4 px = Texel(t, uv) * c;
  float l = dot(px.rgb, vec3(0.299, 0.587, 0.114));
  float k = smoothstep(threshold, threshold + 0.18, l);
  return vec4(px.rgb * k, px.a);
}
]]

local code_blur = [[
extern vec2 step;
extern number sigma;
vec4 effect(vec4 c, Image t, vec2 uv, vec2 sc) {
  vec3 acc = vec3(0.0);
  float wsum = 0.0;
  for (int i = -6; i <= 6; i++) {
    float fi = float(i);
    float w = exp(-(fi*fi) / (2.0 * sigma * sigma));
    acc += Texel(t, uv + step * fi).rgb * w;
    wsum += w;
  }
  return vec4(acc / wsum, 1.0) * c;
}
]]

local bright, blur
local hi, blurA, blurB
local W, H

function M.load(w, h)
  W, H = w, h
  bright = love.graphics.newShader(code_bright)
  blur   = love.graphics.newShader(code_blur)
  hi     = love.graphics.newCanvas(math.floor(w/2), math.floor(h/2))
  blurA  = love.graphics.newCanvas(math.floor(w/2), math.floor(h/2))
  blurB  = love.graphics.newCanvas(math.floor(w/2), math.floor(h/2))
  hi:setFilter("linear","linear")
  blurA:setFilter("linear","linear")
  blurB:setFilter("linear","linear")
end

-- Apply bloom: takes a source canvas, draws back to the active target additively.
-- threshold: brightness cutoff (0..1). intensity: bloom amount (0..2).
-- sigma: blur kernel sigma.
function M.apply(srcCanvas, threshold, intensity, sigma)
  local prev = love.graphics.getCanvas()
  local cw, ch = srcCanvas:getDimensions()

  -- bright pass into hi
  love.graphics.push("all")
  love.graphics.setCanvas(hi)
  love.graphics.clear(0,0,0,0)
  love.graphics.setShader(bright)
  bright:send("threshold", threshold)
  love.graphics.setColor(1,1,1,1)
  love.graphics.draw(srcCanvas, 0, 0, 0, hi:getWidth()/cw, hi:getHeight()/ch)

  -- horizontal blur hi -> blurA
  love.graphics.setCanvas(blurA)
  love.graphics.clear(0,0,0,0)
  love.graphics.setShader(blur)
  blur:send("step", { 1.0 / hi:getWidth(), 0.0 })
  blur:send("sigma", sigma)
  love.graphics.draw(hi, 0, 0)

  -- vertical blur blurA -> blurB
  love.graphics.setCanvas(blurB)
  love.graphics.clear(0,0,0,0)
  blur:send("step", { 0.0, 1.0 / blurA:getHeight() })
  blur:send("sigma", sigma)
  love.graphics.draw(blurA, 0, 0)

  -- composite back on prev canvas additively
  love.graphics.setShader()
  love.graphics.setCanvas(prev)
  love.graphics.setBlendMode("add", "alphamultiply")
  love.graphics.setColor(intensity, intensity, intensity, 1)
  love.graphics.draw(blurB, 0, 0, 0, cw / blurB:getWidth(), ch / blurB:getHeight())
  love.graphics.setBlendMode("alpha")
  love.graphics.pop()
end

return M
