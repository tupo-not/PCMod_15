function table.Copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k,v in pairs(t) do o[k] = table.Copy(v) end
  return o
end
local function assertTrue(v,m) if not v then error("FAILED: "..m,2) end end
local function assertEq(a,b,m) if a ~= b then error("FAILED: "..m.." got "..tostring(a).." want "..tostring(b),2) end end

math.Clamp = function(v,a,b) if v<a then return a end if v>b then return b end return v end
PCMod = { Msg=function() end, Cfg={}, SDraw={CFrame=0} }
CurTime=function() return 0 end
PROG = {}
dofile("prog_base.lua")

local os = { Progs={}, ProgFocus="", ZCounter=nil }
local function mkprog(name)
  local p = table.Copy(PROG)
  p.Name = name
  p.OS = "personal"
  p.State = 0
  p.SimpleMode = false
  p.Updates = 0
  p.GetOS = function() return os end
  p.UpdateSS = function(self) self.Updates = self.Updates + 1 end
  p.GetScreenSpace = function() return nil end
  os.Progs[name] = p
  return p
end

local a = mkprog("a")
a:GetDimensions()
assertTrue(a.WinW ~= nil and a.WinW < 1, "window not fullscreen")
assertEq(a.WinX, 0.02, "first window x")
assertEq(a.WinY, 0.03, "first window y")
a:Start()
assertEq(a.State, 1, "started")
local z1 = a.ZOrder
assertTrue(z1 and z1 > 0, "z assigned")

-- Reopening a running app only raises it, does not reset the program.
local updates = a.Updates
a:Start()
assertEq(a.State, 1, "still running")
assertTrue(a.ZOrder > z1, "raise increases z order")
assertTrue(a.Updates > updates, "raise updates screen priority")

local b = mkprog("b")
b:GetDimensions()
assertTrue(b.WinX ~= a.WinX or b.WinY ~= a.WinY, "new window cascades")
b:Start()
assertTrue(b.ZOrder > a.ZOrder, "newer app on top")

-- Click-focus raises an older window.
a:RequestFocus(false)
assertTrue(a.ZOrder > b.ZOrder, "focus raises")
assertEq(os.ProgFocus, "a", "focus name")
a:GetDimensions()
local oldx = a.WinX
a:ProcessCommand("win_move", { "0.3", "0.1" })
assertTrue(a.WinX > oldx, "window moved")
a:GetDimensions()
assertTrue(a.WinX <= (1 - a.WinW) + 0.0001, "window clamped")
a:ProcessCommand("win_resize", { "0.5", "0.6" })
assertTrue(a.WinW == 0.5 and a.WinH == 0.6, "window resized")
assertTrue(a.WinX + a.WinW <= 1.0001, "resize stays on screen")
-- GUI scale is client-side, so the client may place a visually-scaled window
-- past 1-WinW; the server must not snap it back to an invisible border.
a.WinW, a.WinH = 0.62, 0.72
a:ProcessCommand("win_move", { "0.69", "0.2" })
assertTrue(math.abs(a.WinX - 0.69) < 0.0001, "scaled drag not clamped to 1-W")
a:ProcessCommand("win_resize", { "1.6", "1.0" })
assertTrue(math.abs(a.WinW - 1.6) < 0.0001, "scaled resize not clamped to 1-W")
b:Exit()
a:Exit()
assertEq(a.State, 0, "exit")

-- ---------------------------------------------------------------------------
-- SS device window dragging
-- ---------------------------------------------------------------------------
DEV = {}
dofile("ss_base.lua")
local d = table.Copy(DEV)
d.WindowDrag = true
d.WindowResize = true
d.ProgName = "notepad"
d.win_x, d.win_y, d.win_w, d.win_h = 100, 100, 800, 600
d.SSDevice = { X=0.1, Y=0.2, W=0.4, H=0.5 }
d.Listboxes = { lb = { X=110, Y=120, W=100, H=50 } }
d.Textboxes = { tb = { BX=120, TX=100, TMX=110, Y=130, MY=135 } }
local movedTo
local sent
d.Elements = { el = { X=130, Y=140, W=50, H=20, SetLayout=function(self,x,y,w,h) self.X=x self.Y=y self.W=w self.H=h end, CursorInside=function(self,cx,cy) return cx>self.X and cx<self.X+self.W and cy>self.Y and cy<self.Y+self.H end } }
d.RunProgCommand = function(self, prog, com, x, y)
  sent = sent or {}
  table.insert(sent, {prog=prog, com=com, x=x, y=y})
  if (com ~= "focus") then movedTo = {prog=prog, com=com, x=x, y=y} end
end

assertTrue(d:CanStartWindowDrag(0.5, 0.02), "title bar can drag")
assertTrue(not d:CanStartWindowDrag(0.5, 0.2), "body does not drag")
assertTrue(d:CanStartWindowResize(0.98, 0.98), "corner can resize")
assertTrue(not d:CanStartWindowResize(0.5, 0.5), "body does not resize")
d.Elements.el.X, d.Elements.el.Y = 480, 100
assertTrue(not d:CanStartWindowDrag(0.5, 0.02), "title bar button not dragged")

gui = { MouseX = function() return 300 end, MouseY = function() return 250 end }
local down = true
input = { IsMouseDown = function() return down end }
MOUSE_LEFT = 1
ScrW = function() return 1600 end
ScrH = function() return 900 end

d:StartWindowDrag(0.5, 0.02)
assertEq(d.SSDevice.Priority, 150, "drag raises window locally")
gui.MouseX = function() return 400 end
gui.MouseY = function() return 300 end
d:UpdateWindowDrag()
assertTrue(d.SSDevice.X > 0.1, "drag moved x")
assertTrue(d.Listboxes.lb.X > 110, "controls moved")
assertTrue(d.Textboxes.tb.BX > 120, "textbox moved")
assertTrue(d.Elements.el.X > 480, "element moved")

down = false
d:UpdateWindowDrag()
assertTrue(not d.WindowDragging, "drag released")
assertTrue(movedTo and movedTo.com == "win_move", "move sent to program")
assertTrue(tonumber(movedTo.x) ~= nil, "rounded x sent")
assertTrue(sent and sent[#sent] and sent[#sent].com == "focus", "drag raises server-side")

d.win_x, d.win_y = 100, 100
d.SSDevice.X, d.SSDevice.Y = 0.01, 0.01
d:TranslateWindow(10, 20)
assertEq(d.win_x, 110, "translate window x")
-- Resize the window from the bottom-right grip.
movedTo = nil
d.win_x, d.win_y, d.win_w, d.win_h = 100, 100, 800, 600
d.SSDevice.W, d.SSDevice.H = 0.5, 0.667
gui.MouseX = function() return 500 end
gui.MouseY = function() return 400 end
d:StartWindowResize(0.98, 0.98)
assertEq(d.SSDevice.Priority, 150, "resize raises window locally")
gui.MouseX = function() return 620 end
gui.MouseY = function() return 450 end
down = true
d:UpdateWindowResize()
assertTrue(d.win_w > 800 and d.win_h > 600, "resize grew window")
assertTrue(d.SSDevice.W > 0.5, "device width grew")
down = false
d:UpdateWindowResize()
assertTrue(movedTo and movedTo.com == "win_resize", "resize sent to program")

-- Scaled windows must reach the real screen/taskbar edges, not the unscaled
-- W/H limits (that caused the invisible drag borders).
PCMod.SDraw.WindowScale = 0.5
d.win_x, d.win_y = 100, 100
d.SSDevice.X, d.SSDevice.Y = 0.1, 0.2
d.SSDevice.W, d.SSDevice.H = 0.4, 0.5
gui.MouseX = function() return 300 end
gui.MouseY = function() return 250 end
down = true
d:StartWindowDrag(0.5, 0.02)
gui.MouseX = function() return 5000 end
gui.MouseY = function() return 5000 end
d:UpdateWindowDrag()
assertTrue(math.abs(d.SSDevice.X - (1 - (0.4 * 0.5))) < 0.002, "scaled drag reaches right edge")
assertTrue(math.abs(d.SSDevice.Y - (0.94 - (0.5 * 0.5))) < 0.002, "scaled drag reaches taskbar")
down = false
d:UpdateWindowDrag()

-- Same for resizing: the visible right/bottom edge may reach the viewport.
d.win_x, d.win_y, d.win_w, d.win_h = 100, 100, 400, 300
d.SSDevice.W, d.SSDevice.H = 0.5, 0.667
gui.MouseX = function() return 200 end
gui.MouseY = function() return 200 end
down = true
d:StartWindowResize(0.98, 0.98)
gui.MouseX = function() return 5000 end
gui.MouseY = function() return 5000 end
d:UpdateWindowResize()
assertTrue(d.win_x + (d.SSDevice.W * 1600 * 0.5) <= 1600.5, "scaled resize reaches right edge")
assertTrue(d.win_y + (d.SSDevice.H * 900 * 0.5) <= (0.94 * 900) + 0.5, "scaled resize reaches taskbar")
down = false
d:UpdateWindowResize()

-- Resizing in a screen corner must not push the window past the edge.
PCMod.SDraw.WindowScale = 0.5
d.win_x, d.win_y, d.win_w, d.win_h = 1500, 800, 40, 30
d.SSDevice.W, d.SSDevice.H = 0.05, 0.033
gui.MouseX = function() return 1500 end
gui.MouseY = function() return 800 end
down = true
d:StartWindowResize(0.98, 0.98)
gui.MouseX = function() return 9999 end
gui.MouseY = function() return 9999 end
d:UpdateWindowResize()
assertTrue(d.win_x + (d.SSDevice.W * 1600 * 0.5) <= 1600.5, "corner resize stays inside right edge")
assertTrue(d.win_y + (d.SSDevice.H * 900 * 0.5) <= (0.94 * 900) + 0.5, "corner resize stays above taskbar")
down = false
d:UpdateWindowResize()
PCMod.SDraw.WindowScale = 1
print("WINDOW TESTS PASSED")
