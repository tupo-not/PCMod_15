-- Control Panel server data and legacy command compatibility.
SERVER = true
CLIENT = false
function string.Left( s, n ) return string.sub( s, 1, n ) end
function string.Right( s, n ) return string.sub( s, math.max( 1, #s - n + 1 ) ) end
function string.Explode( sep, str )
    local out = {}
    local start = 1
    while true do
        local a, b = string.find( str, sep, start, true )
        if (not a) then
            table.insert( out, string.sub( str, start ) )
            break
        end
        table.insert( out, string.sub( str, start, a - 1 ) )
        start = b + 1
    end
    return out
end
function table.Copy( t )
    if (type( t ) ~= "table") then return t end
    local o = {}
    for k, v in pairs( t ) do o[ k ] = table.Copy( v ) end
    return o
end

PCMod = { Data = { [1] = { Password = "old", HardDrive = {} } }, Msg = function() end, Cfg = {} }
util = { Compress = function( s ) return s end }
local ent = {}
function ent:EntIndex() return 1 end
function ent:IsValid() return true end

local os = {}
function os:GetIP() return 2 end
function os:GetFullIP() return "192.168.1.2" end
function os:GetIPv6() return "fd00:c0:a8:1::2" end
function os:GetIPv6Prefix() return "fd00:c0:a8:1::/64" end
function os:GetIPv6Gateway() return "fd00:c0:a8:1::1" end
function os:GetIPv6LinkLocal() return "fe80::2" end
function os:RefreshUSBData() self.Refreshed = true end
function os:GetUSBDevicePorts() return { 1, 2, 4 } end
function os:GetUSBData( port )
    if (port == 1) then return { HasIdent = true, DeviceType = "Printer" } end
    if (port == 2) then return { HasIdent = false } end
    return { HasIdent = true }
end
function os:RunCommand( cmd ) self.LastCommand = cmd end

PROG = {}
dofile( "pcmod_base.lua" )
local base = table.Copy( PROG )
PROG = table.Copy( base )
dofile( "pcmod_mycomp_prog.lua" )
local prog = table.Copy( PROG )
prog.Entity = ent
prog.DeviceData = {}
prog.UpdateSS = function() end
prog.GetOS = function() return os end

local function assertEq( a, b, m )
    if (a ~= b) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end
local function assertTrue( v, m )
    if (not v) then error( "FAILED: " .. m, 2 ) end
end

assertEq( PROG.Name, "mycomputer", "internal program name remains compatible" )
assertEq( PROG.Title, "Control Panel", "new menu title" )
prog:OnStart()
assertEq( prog.DeviceData.Net.IPv4, "192.168.1.2", "IPv4 full address data (not host octet)" )
assertEq( prog.DeviceData.Net.Prefix, "fd00:c0:a8:1::/64", "IPv6 prefix data" )
assertEq( prog.DeviceData.Net.Gateway, "fd00:c0:a8:1::1", "gateway data" )
assertEq( #prog.DeviceData.Dvs, 2, "only identified USB devices returned" )
assertTrue( os.Refreshed, "USB data refreshed" )

prog:DoCommand( "changepass", { "wrong", "new" } )
assertEq( PCMod.Data[ 1 ].Password, "old", "wrong old password rejected" )
assertEq( prog.DeviceData.PWE, 1, "wrong password status" )
prog:DoCommand( "changepass", { "old", "new" } )
assertEq( PCMod.Data[ 1 ].Password, "new", "password changed" )
assertEq( prog.DeviceData.PWE, 2, "password success status" )
prog:DoCommand( "open_devman", {} )
assertEq( os.LastCommand, "sys_openprog deviceman", "legacy Device Manager command" )
prog:DoCommand( "open_nettools", {} )
assertEq( os.LastCommand, "sys_openprog nettools", "legacy Network Tools command" )

print( "CONTROL PANEL PROGRAM TESTS PASSED" )
