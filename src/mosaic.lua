-- Silhouette colorizer with strong edge outlines.
--
-- Goal: the silhouette boundary is ALWAYS clearly visible so the player
-- knows exactly where the danger zone ends. The interior of the silhouette
-- is rendered as a deep matte shadow (darker than the backdrop). The edge
-- gets a bright accent outline via a 4-tap luminance gradient. The
-- background outside the silhouette stays near-black so obstacles and the
-- player both pop.
local M = {}

local code = [[
extern number time_;
extern number pulse;
extern number hue_off;
extern vec2 size_;

vec3 palette4(float t) {
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

vec4 effect(vec4 col, Image tex, vec2 uv, vec2 sc) {
  float lum = Texel(tex, uv).r;

  // 4-tap luminance gradient = silhouette edge mask
  float dx = 1.0 / size_.x;
  float dy = 1.0 / size_.y;
  float l_l = Texel(tex, uv + vec2(-dx, 0.0)).r;
  float l_r = Texel(tex, uv + vec2( dx, 0.0)).r;
  float l_t = Texel(tex, uv + vec2(0.0, -dy)).r;
  float l_b = Texel(tex, uv + vec2(0.0,  dy)).r;
  float gx = abs(l_l - l_r);
  float gy = abs(l_t - l_b);
  float edge = max(gx, gy);
  edge = smoothstep(0.20, 0.80, edge);

  // running palette hue per-frame, plus a per-run offset
  float ang = uv.x * 1.4 + uv.y * 0.9 + time_ * 0.08;
  float hue = 0.5 + 0.5 * sin(ang);
  vec3 accent = palette4(hue + hue_off);

  // backdrop: very dark with a barely-perceivable accent wash
  vec3 bg = vec3(0.020, 0.012, 0.040) + accent * 0.018 * (0.6 + 0.4 * pulse);

  // silhouette body: matte shadow that sits *darker* than the backdrop so
  // the player and obstacles always pop on top of it
  vec3 sil = vec3(0.005, 0.000, 0.020) + accent * 0.025;

  // mix backdrop and silhouette body by luminance, then layer the bright
  // edge outline on top so the boundary is always crystal clear
  vec3 outc = mix(bg, sil, lum);
  vec3 outline = accent * (1.10 + 0.50 * pulse);
  outc = mix(outc, outline, edge);

  // gentle vignette so the corners darken
  vec2 r = uv - 0.5;
  float vig = 1.0 - dot(r, r) * 0.55;
  outc *= vig;

  return vec4(outc, 1.0) * col;
}
]]

local shader
local hue_offset = 0

function M.load() shader = love.graphics.newShader(code) end
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
