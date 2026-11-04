function table.Copy(t) if type(t)~='table' then return t end local o={} for k,v in pairs(t) do o[k]=table.Copy(v) end return o end
function table.Count(t) local n=0 for _ in pairs(t) do n=n+1 end return n end
function istable(v) return type(v)=='table' end
function math.Clamp(v,a,b) if v<a then return a end if v>b then return b end return v end
function math.Mid(a,b,t) return a+(b-a)*t end
function math.MidAngle(a,b,t) return a end
function Color(r,g,b,a) return {r=r,g=g,b=b,a=a} end
local function assertTrue(v,m) if not v then error('FAILED: '..m,2) end end
local function assertEq(a,b,m) if a~=b then error('FAILED: '..m..' got '..tostring(a)..' want '..tostring(b),2) end end
PCMod={Msg=function() end, Warning=function() end, Cfg={GuiScale=0.75, SightRange=9999}, Gui={}, SDraw={}}
file={Find=function() return {} end, Exists=function() return false end}
function Vector(x,y,z) return {x=x or 0,y=y or 0,z=z or 0} end
function table.Merge(a,b) if b then for k,v in pairs(b) do a[k]=v end end return a end
PCMod.SDraw.GetGuiScale=function() return 0.75 end
surface={SetDrawColor=function() end,DrawLine=function() end,DrawRect=function() end,DrawTexturedRect=function() end,SetTexture=function() end,SetFont=function() end,GetTextSize=function() return 1,1 end,CreateFont=function() end}
draw={SimpleText=function() end}
TEXT_ALIGN_LEFT=0; TEXT_ALIGN_TOP=1; TEXT_ALIGN_CENTER=1
hook={Add=function() end}; concommand={Add=function() end}; usermessage={Hook=function() end}; net={Receive=function() end,Start=function() end,Send=function() end,SendToServer=function() end,WriteTable=function() end}
cvars={}; RunConsoleCommand=function() end
gui={MouseX=function() return 260 end, MouseY=function() return 146.25 end}
ScrW=function() return 1600 end
ScrH=function() return 900 end
input={IsMouseDown=function() return false end}
MOUSE_LEFT=1
dofile('cl2d3d.lua')
local ent={IsValid=function() return true end,EntIndex=function() return 1 end}
PCMod.Gui.CamLocked=true; PCMod.Gui.CamLockID=1
PCMod.SDraw.UIScale=0.75; PCMod.SDraw.UIOffX=200; PCMod.SDraw.UIOffY=112.5
local x,y=PCMod.SDraw.CalcCursor(ent)
assertEq(x,260/1600,"raw cursor x")
assertEq(y,146.25/900,"raw cursor y")

-- GUI scale applies to program windows and the Start menus, not the desktop.
PCMod.SDraw.WindowScale = 0.5
local dx,dy,dw,dh,ds = PCMod.SDraw.GetDeviceVisualRect({ ProgName="notepad", Type="window_notepad", X=0.1, Y=0.2, W=0.4, H=0.5 }, 1, 1)
assertEq(ds,0.5,"program window scale")
assertEq(dx,0.1,"program window x")
assertEq(dy,0.2,"program window y")
assertEq(dw,0.2,"program window width")
assertEq(dh,0.25,"program window height")

local _,_,ddw,ddh,dds = PCMod.SDraw.GetDeviceVisualRect({ Type="desktop", X=0, Y=0, W=1, H=1 }, 1, 1)
assertEq(dds,1,"desktop stays native")
assertEq(ddw,1,"desktop width")
assertEq(ddh,1,"desktop height")

-- Start menu scales but stays anchored on the taskbar (its bottom edge).
local mx0,my0,mw0,mh0,mds0 = PCMod.SDraw.GetDeviceVisualRect({ Type="menu_start", X=0, Y=0.4, W=0.4, H=0.54 }, 1, 1)
assertEq(mds0,0.5,"start menu scale")
assertEq(mw0,0.2,"start menu width")
assertEq(mh0,0.27,"start menu height")
assertTrue(math.abs(my0 - (0.94 - 0.27)) < 1e-9, "start menu bottom anchored")
assertEq(mx0,0,"start menu left")

local ax0,ay0,aw0,ah0,ads0 = PCMod.SDraw.GetDeviceVisualRect({ Type="menu_allprogs", X=0.4, Y=0, W=0.4, H=0.94 }, 1, 1)
assertEq(ads0,0.5,"all programs scale")
assertEq(ax0,0.2,"all programs sits next to start menu")
assertTrue(math.abs(ay0 - (0.94 - 0.47)) < 1e-9, "all programs bottom anchored")
assertEq(aw0,0.2,"all programs width")
assertEq(ah0,0.47,"all programs height")
-- Stale/oversized windows are clamped into the viewport for draw and clicks.
local edx,edy,edw,edh,eds = PCMod.SDraw.GetDeviceVisualRect({ ProgName="x", Type="window_x", X=0.9, Y=0.9, W=1.5, H=1.5 }, 1, 1)
assertEq(eds,0.5,"clamped window scale")
assertEq(edw,0.75,"clamped window width")
assertEq(edh,0.75,"clamped window height")
assertTrue(math.abs(edx - (1 - 0.75)) < 1e-9, "window x clamped to right edge")
assertTrue(math.abs(edy - (0.94 - 0.75)) < 1e-9, "window y clamped above taskbar")
local odx,ody,odw,odh = PCMod.SDraw.GetDeviceVisualRect({ ProgName="x", Type="window_x", X=0.5, Y=0.5, W=3, H=3 }, 1, 1)
assertEq(odw,1,"oversized window capped to viewport width")
assertEq(odh,0.94,"oversized window capped to taskbar height")
assertEq(odx,0,"oversized window pinned left")
assertEq(ody,0,"oversized window pinned top")
PCMod.SDraw.WindowScale = 1

-- DrawSpace marks only the topmost device under the cursor for element hover.
PCMod.SDraw.CFrame = 0
local painted = {}
PCMod.SDraw.DrawDevice = function( device )
    table.insert( painted, { dev = device.DevID, hover = PCMod.SDraw.Cursor.HoverDevID } )
end
local tick = function() end
ents = { GetByIndex = function() return {} end }
PCMod.SDraw.DevMap = { bg = { Tick = tick }, low = { Tick = tick }, high = { Tick = tick } }
local ss = {
    bg = { Type = "desktop", X = 0, Y = 0, W = 1, H = 1, Priority = 1, DevID = "bg" },
    low = { Type = "window_a", ProgName = "a", X = 0.1, Y = 0.1, W = 0.5, H = 0.5, Priority = 10, DevID = "low" },
    high = { Type = "window_b", ProgName = "b", X = 0.2, Y = 0.2, W = 0.3, H = 0.3, Priority = 20, DevID = "high" },
}
PCMod.SDraw.Cursor = { Ent = 1, Frame = 0 }
PCMod.SDraw.Cursor.X, PCMod.SDraw.Cursor.Y = 0.25 * 1600, 0.25 * 900
PCMod.SDraw.DrawSpace( ss, 0, 0, 1600, 900, 1 )
assertEq(PCMod.SDraw.Cursor.HoverDevID, "high", "hover top window")
-- A lower window is drawn first; it must already know the window above it wins.
for _, p in ipairs( painted ) do
    assertEq(p.hover, "high", "device sees topmost hover at paint time (" .. p.dev .. ")")
end
painted = {}
PCMod.SDraw.Cursor.X, PCMod.SDraw.Cursor.Y = 0.15 * 1600, 0.15 * 900
PCMod.SDraw.DrawSpace( ss, 0, 0, 1600, 900, 1 )
assertEq(PCMod.SDraw.Cursor.HoverDevID, "low", "hover uncovered window")
PCMod.SDraw.Cursor.X, PCMod.SDraw.Cursor.Y = 0.95 * 1600, 0.95 * 900
PCMod.SDraw.DrawSpace( ss, 0, 0, 1600, 900, 1 )
assertEq(PCMod.SDraw.Cursor.HoverDevID, "bg", "hover desktop outside windows")

-- Grab picks the topmost device only.
local order={}
local low={X=0,Y=0,W=1,H=1,Priority=5,DevID='low',WindowDrag=true}
local high={X=0,Y=0,W=1,H=1,Priority=20,DevID='high',WindowDrag=true}
PCMod.SDraw.DevMap={low={TryStartWindowGrab=function(self,mx,my) table.insert(order,'low'); return true end}, high={TryStartWindowGrab=function(self,mx,my) table.insert(order,'high'); return true end}}
gui.MouseX=function() return 300 end; gui.MouseY=function() return 200 end
local down=false
input.IsMouseDown=function() return down end
PCMod.SDraw.LastMouseDown=false
down=true
PCMod.SDraw.UpdateWindowGrab({low=low,high=high},300,200)
assertEq(#order,1,"only one grab starts")
assertEq(order[1],'high',"topmost device grabbed")
down=false
PCMod.SDraw.UpdateWindowGrab({low=low,high=high},300,200)
assertEq(#order,1,"release does not start a grab")

-- 25%/50% presets are valid; lower values clamp to 25%.
PCMod.Cfg.GuiScale=0.25
assertEq(PCMod.SDraw.GetGuiScale(),0.25,"25% scale")
PCMod.Cfg.GuiScale=0.5
assertEq(PCMod.SDraw.GetGuiScale(),0.5,"50% scale")
PCMod.Cfg.GuiScale=0.1
assertEq(PCMod.SDraw.GetGuiScale(),0.25,"scale floor")
print("UI SCALE TESTS PASSED")
