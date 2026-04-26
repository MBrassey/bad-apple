function love.conf(t)
  t.identity      = "bad_apple"
  t.version       = "11.5"
  t.console       = false
  t.window.title  = "Bad Apple // Beat Dash"
  t.window.width  = 1920
  t.window.height = 1080
  t.window.resizable = true
  t.window.vsync  = 1
  t.window.msaa   = 0
  t.window.highdpi = true
  t.modules.thread = false
  t.modules.video  = false
  t.modules.physics = false
end
