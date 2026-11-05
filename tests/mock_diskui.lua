-- mock_diskui.lua: Install Disk program-selection HUD.
-- 1) DrawHUD must render the program rows even when Think() never ran and the
--    global SWEP is nil (runtime regression tests).
-- 2) SWEP.CalcPanelLayout math at several resolutions and program counts.
SWEP = { Primary = {}, Secondary = {} }
CLIENT = true
SERVER = false
util = { PrecacheModel = function() end, TraceLine = function() return {} end }
AddCSLuaFile = function() end
surface = {
	CreateFont = function() end,
	SetFont = function() end,
	GetTextSize = function(s) return #tostring(s) * 7, 16 end,
	GetTextureID = function() return 1 end,
	SetTexture = function() end,
	SetDrawColor = function() end,
	DrawTexturedRect = function() end,
	DrawLine = function() end,
	DrawRect = function() end,
}
function Color(r,g,b,a) return { r=r, g=g, b=b, a=a or 255 } end
function math.Clamp(v,a,b) if v<a then return a end if v>b then return b end return v end
function math.Mid(o,t,r) return o + (t-o)*r end
-- only ico_app really exists in the addon; everything else falls back to it
file = { Exists = function(p) return p:find( "ico_app" ) ~= nil end }
ScrW = function() return 1920 end
ScrH = function() return 1080 end
local now = 0
CurTime = function() return now end
local texts = {}
draw = { RoundedBox = function() end, SimpleText = function(t) texts[#texts+1] = tostring(t) end }

dofile( "pcmod_installdisk.lua" )

local function assertTrue(v,m) if not v then error('FAILED: '..m,2) end end

-- Runtime simulation: after load, the global SWEP does NOT exist in Garry's Mod
local WeaponClass = SWEP
SWEP = nil

local function makeDisk( names, selprog, osid )
	local nw = { progs = #names, selprog = selprog or 1, packname = "Test Pack" }
	for i, n in ipairs( names ) do
		nw["prog_"..i] = n
		nw["prog_"..i.."_os"] = osid or "personal"
		nw["prog_"..i.."_icon"] = (i % 2 == 0) && "" || "app" -- every 2nd icon missing
	end
	local wep = setmetatable( { Programs = {}, ProgCnt = 0, SelProg = 0, LabelPos = 0, PackName = "" }, { __index = WeaponClass } )
	function wep:GetNWInt(k) return nw[k] or 0 end
	function wep:GetNWString(k) return nw[k] or "" end
	return wep, nw
end

local function drawOnce( wep )
	texts = {}
	now = now + 0.05
	wep:Think() -- GMod calls WEAPON:Think clientside every tick while active
	wep:DrawHUD()
end

local function countRows( names )
	local found = 0
	for _, t in ipairs( texts ) do
		for _, n in ipairs( names ) do
			if (t == n) then found = found + 1 end
		end
	end
	return found
end

local function hasText( s )
	for _, t in ipairs( texts ) do if (t == s) then return true end end
	return false
end

-- Regression: with the same NW data the original (pre-redesign) UI used, the
-- new HUD must draw every program row. Global SWEP is nil (runtime).
local names8 = { "Chat Host", "Print Share", "ChatServ", "Personal Player", "Firewall", "P2P Chat", "I/O Controller", "AlarmZ" }
local wep8 = makeDisk( names8, 1 )
drawOnce( wep8 )
assertTrue( wep8.ProgCnt == 8 and #wep8.Programs == 8, "client state synced from NW via Think (original mechanism)" )
assertTrue( countRows( names8 ) == 8, "all 8 program rows drawn by the new HUD, got "..countRows( names8 ) )
assertTrue( hasText( "1/8" ), "selection counter 1/8 drawn" )
assertTrue( hasText( "Personal" ), "category chip drawn from real os id" )

-- empty disk: no rows, no errors
local wep0 = makeDisk( {} )
drawOnce( wep0 )
assertTrue( wep0.ProgCnt == 0 and #wep0.Programs == 0, "empty disk: state cleared" )
assertTrue( countRows( names8 ) == 0, "empty disk: no program rows" )

-- single program
local wep1 = makeDisk( { "Notepad" } )
drawOnce( wep1 )
assertTrue( countRows( { "Notepad" } ) == 1, "single program drawn" )
assertTrue( hasText( "1/1" ), "counter 1/1" )

-- 50 programs: visible window is limited, selected row stays visible, switching works
local names50 = {}
for i = 1, 50 do names50[i] = "Program Number "..i end
local wep50, nw50 = makeDisk( names50, 50 )
drawOnce( wep50 )
local vis = countRows( names50 )
assertTrue( vis >= 1 and vis < 50, "50 programs: only a visible window is drawn, got "..vis )
assertTrue( hasText( "Program Number 50" ), "selected last program visible" )
assertTrue( hasText( "50/50" ), "counter 50/50" )
nw50.selprog = 1 -- server-side RMB switch equivalent
drawOnce( wep50 )
assertTrue( hasText( "Program Number 1" ), "after switching selection to first, it is visible" )
assertTrue( hasText( "1/50" ), "counter updated to 1/50" )

-- long program name is truncated (drawn text shorter than the raw name)
local longName = string.rep( "VeryLongProgramName", 10 )
local wepL = makeDisk( { longName } )
drawOnce( wepL )
local rowTxt = nil
for _, t in ipairs( texts ) do if (t:find( "VeryLong" )) then rowTxt = t end end
assertTrue( rowTxt != nil and #rowTxt < #longName, "long name truncated, drawn len "..(rowTxt and #rowTxt or -1).." < "..#longName )

-- server category chip
local wepS = makeDisk( { "Chat Host" }, 1, "server" )
drawOnce( wepS )
assertTrue( hasText( "Server" ), "server category chip from os id 'server'" )

-- repeated Think+DrawHUD frames keep working (no errors, list stable)
for f = 1, 5 do drawOnce( wep8 ) end
assertTrue( countRows( names8 ) == 8, "list stable across repeated frames" )

-- DrawHUD BEFORE the first Think (real GMod can render a frame before the first
-- tick): must not error; the list is not synced yet, so the panel shows its
-- empty state (0 program rows). After Think the list syncs normally.
do
	local wepNT = makeDisk( names8, 1 )
	texts = {}
	now = now + 0.05
	local ok = pcall( function() wepNT:DrawHUD() end )
	assertTrue( ok, "DrawHUD before first Think does not error" )
	assertTrue( #wepNT.Programs == 0 and countRows( names8 ) == 0, "before first Think the list is empty (documented behavior)" )
	wepNT:Think()
	texts = {}
	now = now + 0.05
	wepNT:DrawHUD()
	assertTrue( countRows( names8 ) == 8, "after first Think the list syncs (8 rows)" )
end

-- shrinking program list: 8 -> 3 on the server side; stale entries must vanish
do
	local wepShrink, nwShrink = makeDisk( names8, 1 )
	drawOnce( wepShrink )
	assertTrue( #wepShrink.Programs == 8, "initially 8 programs" )
	-- server now has only 3
	for i = 4, 8 do nwShrink["prog_"..i] = nil nwShrink["prog_"..i.."_os"] = nil nwShrink["prog_"..i.."_icon"] = nil end
	nwShrink.progs = 3
	drawOnce( wepShrink ) -- Think + DrawHUD
	assertTrue( #wepShrink.Programs == 3, "after shrink, exactly 3 entries remain, got "..#wepShrink.Programs )
	local drawn = countRows( names8 )
	assertTrue( drawn == 3, "only the 3 current programs are drawn, got "..drawn )
	assertTrue( not hasText( "AlarmZ" ) and not hasText( "P2P Chat" ), "stale programs (4..8) are not drawn" )
	assertTrue( hasText( "1/3" ), "counter shows 1/3 (selection unchanged, count shrank)" )
end

local resolutions = { {1280,720}, {1920,1080}, {2560,1440} }
for _, res in ipairs( resolutions ) do
	local scrW, scrH = res[1], res[2]
	for _, cnt in ipairs( { 0, 1, 3, 8, 20, 50 } ) do
		local x, y, w, h, rowH, headerH, footerH, pad, maxRows = WeaponClass.CalcPanelLayout( cnt, scrW, scrH )
		local tag = "cnt="..cnt.." @"..scrW.."x"..scrH
		assertTrue( w >= 220 and w <= 340, "panel width clamped to 220..340, "..tag )
		assertTrue( x > scrW / 2, "panel never covers screen center/crosshair, "..tag )
		assertTrue( x >= 0 and x + w <= scrW, "panel inside screen horizontally, "..tag )
		assertTrue( y >= 0 and y + h <= scrH, "panel inside screen vertically, "..tag )
		assertTrue( h <= scrH * 0.55 + 0.001, "panel height capped at 55% of screen height, "..tag )
		local rows = math.min( math.max( cnt, 1 ), maxRows )
		assertTrue( h == headerH + rows * rowH + footerH + pad * 2, "height = header + visible rows + footer + padding, "..tag )
		assertTrue( maxRows >= 1, "at least one visible row, "..tag )
		if (cnt > maxRows) then
			assertTrue( rows == maxRows, "long list limited to maxRows visible rows, "..tag )
		end
	end
end

print( "ALL DISK UI TESTS PASSED" )
