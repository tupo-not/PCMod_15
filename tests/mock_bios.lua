-- BIOS state transitions: BSOD must clear the screen through the real API.
PCMod = {
    Msg = function() end,
    DeriveDriver = function() return {} end,
}
function CurTime() return 10 end
function IsValid( value ) return value ~= nil end
dofile( "pcmod_drv_bios.lua" )

local function assertEq( a, b, m )
    if (a ~= b) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end

local function assertTrue( v, m )
	if (not v) then error( "FAILED: " .. m, 2 ) end
end

local drv = {}
for k, v in pairs( DRV ) do drv[ k ] = v end
drv.Data = { State = 0 }
function drv:EnableCursor() end
function drv:BootDelay( seconds ) return seconds end

local cleared = 0
local added
local ss = {}
function ss:ClearAll() cleared = cleared + 1 end
function ss:MakeDevice( kind, x, y, w, h, data, priority )
    return { Type = kind, X = x, Y = y, W = w, H = h, Data = data, Priority = priority }
end
function ss:AddDevice( name, dev ) added = { Name = name, Dev = dev } end
local display = {}
function display:GetScreen() return ss end
function drv:GetOSDriver( name )
    if (name == "gen_display") then return display end
end

drv:SetState( 8 )
assertEq( drv.Data.State, 8, "BIOS entered BSOD state" )
assertEq( cleared, 1, "BSOD cleared the old screen" )
assertEq( added.Name, "win_bsod", "BSOD device installed" )
assertEq( added.Dev.Type, "bsod", "BSOD device type" )
assertEq( added.Dev.W, 1, "BSOD width" )
assertEq( added.Dev.H, 1, "BSOD height" )

-- Destructive/debug input is admin-only; boot commands remain public.
local admin = { IsAdmin = function() return true end }
local user = { IsAdmin = function() return false end }
drv.OS = { Present = true }
drv:CallEvent( { Event = "player_input", user, { "clear_os" } } )
assertTrue( drv.OS.Present == true, "non-admin cannot clear the OS" )
drv:CallEvent( { Event = "player_input", admin, { "clear_os" } } )
assertEq( drv.OS, nil, "admin can clear the OS" )
drv.Data.State = 4
drv:CallEvent( { Event = "player_input", user, { "force_bsod" } } )
assertEq( drv.Data.State, 4, "non-admin cannot force BSOD" )
local executed
function drv:Exec( command ) executed = command end
drv:CallEvent( { Event = "player_input", user, { "bios_command", "os:launch" } } )
assertEq( executed, "os:launch", "public boot command still works" )
executed = nil
drv:CallEvent( { Event = "player_input", admin, { "bios_command", "os:instance" } } )
assertEq( executed, "os:instance", "public OS instance command still works" )
executed = nil
drv:CallEvent( { Event = "player_input", admin, { "bios_command", "exec system/custom.sys" } } )
assertEq( executed, nil, "arbitrary BIOS exec is rejected" )

print( "ALL BIOS TESTS PASSED" )
