-- mock_notify.lua: layout math of the Dynamic Island notification capsule
-- (PCMod.Gui.CalcNotifyLayout in cl_vgui.lua) for all install messages at
-- 1280x720 and 1920x1080: capsule fits the text, min/max width, height, and
-- the text stays inside the capsule.
function table.Copy(t) if type(t)~='table' then return t end local o={} for k,v in pairs(t) do o[k]=table.Copy(v) end return o end
function math.Clamp(v,a,b) if v<a then return a end if v>b then return b end return v end
function Color(r,g,b,a) return {r=r,g=g,b=b,a=a or 255} end
function Vector(x,y,z) return {x=x or 0,y=y or 0,z=z or 0} end
function Matrix() return { Translate=function() end, Scale=function() end, Rotate=function() end } end
PCMod = { Msg=function() end, Warning=function() end, Gui={}, Beam={} }
surface = {
	SetFont=function() end,
	-- deterministic fake font metrics: 7 px per char, 16 px line height
	GetTextSize=function(s) return #tostring(s)*7, 16 end,
	SetDrawColor=function() end, SetTexture=function() end, DrawTexturedRect=function() end,
	PlaySound=function() end,
}
draw = { SimpleText=function() end, RoundedBox=function() end, NoTexture=function() end }
vgui = { Register=function() end, Create=function() return { SetPos=function() end, SetSize=function() end } end }
concommand = { Add=function() end }
hook = { Add=function() end, Remove=function() end }
net = { Start=function() end, Send=function() end, SendToServer=function() end, Receive=function() end, WriteEntity=function() end, WriteTable=function() end }
usermessage = { Hook=function() end }
file = { Find=function() return {} end, Exists=function() return false end }
cvars = {}
RunConsoleCommand = function() end
ScrW = function() return 1920 end
ScrH = function() return 1080 end
CurTime = function() return 0 end
RealTime = function() return 0 end
FrameTime = function() return 0 end
IsValid = function() return false end
LocalPlayer = function() return nil end
cam = { Start2D=function() end, End2D=function() end, PushModelMatrix=function() end, PopModelMatrix=function() end }
render = { PushFilterMag=function() end, PushFilterMin=function() end, PopFilterMag=function() end, PopFilterMin=function() end }
TEXFILTER = { ANISOTROPIC = 3 }
gui = { MouseX=function() return 0 end, MouseY=function() return 0 end }
input = { IsMouseDown=function() return false end }
MOUSE_LEFT = 1
TEXT_ALIGN_LEFT = 0
TEXT_ALIGN_CENTER = 1
TEXT_ALIGN_TOP = 3

dofile( "cl_vgui.lua" )

local function assertTrue(v,m) if not v then error('FAILED: '..m,2) end end

local messages = {
	"Installed", "Already installed", "Incompatible device",
	"No operating system", "Invalid program", "No program selected",
	"Aim at a PC", "Too far",
}
local resolutions = { {1280,720}, {1920,1080}, {2560,1440} }
local progresses = { 0.05, 0.3, 0.7, 1.0 } -- start, mid-expand, mid-collapse, full size

-- 1) layout: capsule fits the message, min/max width, height follows font
for _, res in ipairs( resolutions ) do
	local scrW = res[1]
	for _, msg in ipairs( messages ) do
		local w, h, tw, th = PCMod.Gui.CalcNotifyLayout( msg, scrW )
		assertTrue( w >= 90, "min width, "..msg.." @"..scrW )
		assertTrue( w <= scrW * 0.6 + 0.001, "max width 60% of screen, "..msg.." @"..scrW )
		assertTrue( h >= 30 and (h >= th + 12 - 0.001 or h == 30), "height fits font, "..msg.." @"..scrW )
		if (w < scrW * 0.6) then
			assertTrue( w >= tw + 35 - 0.001, "capsule fits text+indicator+padding, "..msg.." @"..scrW )
		end
	end
end

-- 2) final transformed geometry of every element (NotifyGeometry) at every
--    animation progress: text must stay inside the capsule, indicator left of
--    text, vertical centering, equal padding
for _, res in ipairs( resolutions ) do
	local scrW, scrH = res[1], res[2]
	for _, msg in ipairs( messages ) do
		PCMod.Gui.Notify( msg, false ) -- builds NotifyState via the real entry point
		local st = PCMod.Gui.NotifyState
		assertTrue( st.Active and st.Message == msg, "state active for "..msg )
		for _, p in ipairs( progresses ) do
			local capL, capR, capT, capB, dotL, dotR, textL, textR, textT, textB =
				PCMod.Gui.NotifyGeometry( st, scrW, scrH, p )
			local tag = msg.." @"..scrW.."x"..scrH.." p="..p
			assertTrue( capL < capR and capT < capB, "capsule has area, "..tag )
			assertTrue( textL >= capL - 0.001, "text left inside capsule, "..tag )
			assertTrue( textR <= capR + 0.001, "text right inside capsule (regression: old panel code overflowed here), "..tag )
			assertTrue( dotL >= capL - 0.001 and dotR <= textL + 0.001, "indicator left of text, inside capsule, "..tag )
			assertTrue( math.abs( (textT + textB) - (capT + capB) ) < 0.01, "text vertically centered in capsule, "..tag )
			local padR = (st.W - 10 - 7 - 8 - st.TextW) * p -- right padding (min-width aware)
			assertTrue( math.abs( (capR - textR) - padR ) < 0.01, "right padding consistent, "..tag )
			assertTrue( math.abs( (textL - dotR) - 8 * p ) < 0.01, "indicator-text gap = 8*p, "..tag )
		end
	end
end

-- 3) repeated notification overwrites state cleanly (no leftovers, no overlap)
PCMod.Gui.Notify( "Installed", false )
local st1 = PCMod.Gui.NotifyState
PCMod.Gui.Notify( "No operating system", true )
local st2 = PCMod.Gui.NotifyState
assertTrue( st2.Message == "No operating system" and st2.IsError == true, "re-notify updates message+error flag" )
assertTrue( st2.W > st1.W, "longer message gets wider capsule" )

-- 4) long message stays within the max-width clamp
local w = PCMod.Gui.CalcNotifyLayout( "A very long notification message that would overflow", 1280 )
assertTrue( w <= 1280 * 0.6 + 0.001, "long message clamped to 60% of 1280" )

print( "ALL NOTIFY GEOMETRY TESTS PASSED" )
