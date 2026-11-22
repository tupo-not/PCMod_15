-- All Programs toggles an existing menu closed instead of replaying entrance.
PCMod = { Msg = function() end }
function table.Copy( t )
	if (type( t ) != "table") then return t end
	local out = {}
	for k, v in pairs( t ) do out[ k ] = table.Copy( v ) end
	return out
end
OS = {}
dofile( "pcmod_os_personal.lua" )

local function assertEq( a, b, msg )
	if (a ~= b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function assertTrue( v, msg ) if (!v) then error( "FAILED: " .. msg, 2 ) end end

local timers = {}
timer = {
	Create = function( id, delay, repetitions, fn )
		timers[ id ] = { delay = delay, fn = fn, removed = false }
	end,
	Remove = function( id )
		if (timers[ id ]) then timers[ id ].removed = true end
	end,
}
local ss = { Data = {} }
function ss:GetDevice( name ) return self.Data[ name ] end
function ss:AddDevice( name, dev )
	dev.Rev = (dev.Rev || 0) + 1
	self.Data[ name ] = dev
end
function ss:RemoveDevice( name ) self.Data[ name ] = nil end
function ss:MakeDevice( kind, x, y, w, h, data, priority )
	return { Type = kind, X = x, Y = y, W = w, H = h, Priority = priority, Data = data }
end
local display = {}
function display:GetScreen() return ss end
function display:SetScreen( value ) ss = value end

local os = {}
for k, v in pairs( OS ) do os[ k ] = v end
os.State = 10
os.Progs = {}
os.PCData = {}
local ent = {}
function ent:IsValid() return true end
function ent:EntIndex() return 42 end
function ent:GetOS() return os end
os.Entity = ent
function os:Display() return display end
function os:GetAllProgs() return { { "app", "Files", "sys_openprog files" } } end
function os:GetTheme() return "basic" end

os:RunCommand( "progmenu_open", {} )
local dev = ss:GetDevice( "menu_allprogs" )
assertTrue( dev != nil, "first command opens All Programs" )
assertTrue( dev.Closing != true, "first open is not closing" )
local firstRev = dev.Rev

os:RunCommand( "progmenu_open", {} )
assertTrue( ss:GetDevice( "menu_allprogs" ) == dev, "second command keeps the existing device" )
assertEq( dev.Closing, true, "second command starts the closing slide" )
assertTrue( dev.Rev > firstRev, "closing state is sent to the client" )
local tid = "pcmod_progmenuexit_42"
assertTrue( timers[ tid ] && timers[ tid ].fn, "closing schedules removal" )
assertEq( timers[ tid ].delay, 0.3, "closing waits for the slide" )

-- A click during the exit slide cancels removal and reopens the same device.
os:RunCommand( "progmenu_open", {} )
assertEq( dev.Closing, false, "click during close cancels Closing" )
assertEq( timers[ tid ].removed, true, "click during close removes the timer" )
assertTrue( ss:GetDevice( "menu_allprogs" ) == dev, "cancel close does not recreate the menu" )

-- Close again and let the timer finish: the device is removed for real.
os:RunCommand( "progmenu_open", {} )
assertEq( dev.Closing, true, "next click starts closing again" )
local completion = timers[ tid ].fn
completion()
assertEq( ss:GetDevice( "menu_allprogs" ), nil, "completed close removes the device" )
assertEq( timers[ tid ].removed, true, "direct close cleans up its timer" )

-- After removal the same command performs a fresh open.
os:RunCommand( "progmenu_open", {} )
assertTrue( ss:GetDevice( "menu_allprogs" ) != nil, "closed menu can be opened again" )
assertTrue( ss:GetDevice( "menu_allprogs" ) != dev, "fresh open creates a fresh device" )

-- Closing Start closes both menus with the same transition, including the X
-- command. Reopening Start never revives All Programs.
os:RunCommand( "startmenu_open", {} )
local startDev = ss:GetDevice( "menu_start" )
local allDev = ss:GetDevice( "menu_allprogs" )
assertTrue( startDev && allDev, "Start and All Programs are open" )
os:RunCommand( "startmenu_open", {} )
assertEq( startDev.Closing, true, "Start begins its closing slide" )
assertEq( allDev.Closing, true, "All Programs begins closing together with Start" )
local startTid = "pcmod_menuexit_42"
assertTrue( timers[ startTid ] && timers[ startTid ].fn, "Start close has a completion timer" )
assertTrue( timers[ tid ] && timers[ tid ].fn, "All Programs close has a completion timer" )
timers[ startTid ].fn()
assertEq( ss:GetDevice( "menu_start" ), nil, "Start is removed after the shared close" )
assertEq( ss:GetDevice( "menu_allprogs" ), nil, "All Programs is removed with Start" )

os:RunCommand( "startmenu_open", {} )
assertTrue( ss:GetDevice( "menu_start" ) != nil, "Start can open on its own" )
assertEq( ss:GetDevice( "menu_allprogs" ), nil, "opening Start does not reopen All Programs" )
os:RunCommand( "progmenu_open", {} )
startDev = ss:GetDevice( "menu_start" )
allDev = ss:GetDevice( "menu_allprogs" )
os:RunCommand( "startmenu_close", {} )
assertEq( startDev.Closing, true, "X also starts closing Start" )
assertEq( allDev.Closing, true, "X also starts closing All Programs" )
local startCloseTimer = timers[ startTid ]
local allCloseTimer = timers[ tid ]
os:RunCommand( "startmenu_close", {} )
assertTrue( timers[ startTid ] == startCloseTimer && !startCloseTimer.removed, "repeated X does not cancel the Start timer" )
assertTrue( timers[ tid ] == allCloseTimer && !allCloseTimer.removed, "repeated X does not cancel the All Programs timer" )
os:RunCommand( "startmenu_open", {} )
assertEq( startDev.Closing, false, "reopen cancels Start closing" )
assertEq( allDev.Closing, true, "reopening Start does not revive All Programs" )
assertEq( timers[ startTid ].removed, true, "reopen cancels only the Start timer" )
assertEq( timers[ tid ].removed, false, "All Programs close still completes" )
timers[ tid ].fn()
assertTrue( ss:GetDevice( "menu_start" ) != nil, "Start remains open after All Programs closes" )
assertEq( ss:GetDevice( "menu_allprogs" ), nil, "All Programs does not return with Start" )

print( "mock_progmenu PASSED" )
