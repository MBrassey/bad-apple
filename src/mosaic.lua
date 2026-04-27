-- Mosaic colorizer shader for the silhouette video.
-- Takes the monochrome silhouette mask (R=G=B=luminance, 1=silhouette,
-- 0=background) and outputs a multi-coloured flowing gradient. The
-- silhouette pixels glow with a hue that drifts across the frame and
-- pulses with the music; the background gets a subtle complementary
-- tint so the screen never goes flat black.
local M = {}

local code = [[
extern number time_;
extern number pulse;
extern number hue_off;
extern vec2 size_;

vec3 palette4(float t) {
  // four anchor colours -- pink / cyan / violet / amber -- looped
  vec3 c1 = vec3(1.00, 0.45, 0.72);
  vec3 c2 = vec3(0.40, 0.90, 1.00);
  vec3 c3 = vec3(0.80, 0.55, 1.00);
  vec3 c4 = vec3(1.00, 0.80, 0.45);
  t = fract(t);
  if (t < 0.25) return mix(c1, c2,  t          / 0.25);
  if (t < 0.50) return mix(c2, c3, (t - 0.25) / 0.25);
  if (t < 0.75) return mix(c3, c4, (t - 0.50) / 0.25);
  return                mix(c4, c1, (t - 0.75) / 0.25);
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  float lum = Texel(tex, uv).r;

  // hue drifts across the frame; the dominant axis sweeps with time
  // hue_off adds a per-run rotation so each play feels different
  float ang = uv.x * 1.6 + uv.y * 1.1 + time_ * 0.10;
  float hue = 0.5 + 0.5 * sin(ang) + 0.18 * sin(uv.y * 4.0 - time_ * 0.27);
  vec3 col = palette4(hue + hue_off);

  // silhouette glow: the bright pixels get the colour at full saturation,
  // boosted by the kick pulse. The interior (very bright) stays almost white
  // so the silhouette form is still legible.
  float k = smoothstep(0.55, 0.95, lum);                // strong silhouette = nearly white core
  vec3 sil = mix(col * (0.75 + 0.55 * pulse), vec3(1.0), k * 0.55);

  // background: deep dark with a faint tint so the canvas breathes.
  vec3 bg  = vec3(0.04, 0.02, 0.08) + col * 0.05 * (0.6 + 0.4 * pulse);

  // soft scanline texture so the mosaic reads as luminous, not flat
  float scan = 0.94 + 0.06 * sin(uv.y * size_.y * 3.14159 * 0.5);

  vec3 outc = mix(bg, sil, lum) * scan;
  // gentle vignette
  vec2 r = uv - 0.5;
  float vig = 1.0 - dot(r, r) * 0.7;
  outc *= vig;

  return vec4(outc, 1.0) * color;
}
]]

local shader
local hue_offset = 0

function M.load()
  shader = love.graphics.newShader(code)
end

function M.setHueOffset(o) hue_offset = o or 0 end
function M.hueOffset() return hue_offset end

function M.send(time_, pulse, intensity, w, h)
  shader:send("time_", time_)
  shader:send("pulse", math.min(1.5, pulse or 0))
  shader:send("hue_off", hue_offset)
  shader:send("size_", { w or 1, h or 1 })
end

function M.shader() return shader end

return M
