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

PCMod = { Data = { [1] = { Password = "old", HardDrive = {} } }, Msg = function() end, Cfg = { WirelessRange = 1024 } }
util = { Compress = function( s ) return s end }
local ent = {}
function ent:EntIndex() return 1 end
function ent:IsValid() return true end

-- Wireless scan helpers: two fake routers in range (FindInSphere is chosen
-- because cfg.WirelessRange > 0).
local VecMT = { __sub = function() return { Length = function() return 120 end } end }
local function Vec() return setmetatable( {}, VecMT ) end
function ent:GetPos() return Vec() end
local function makeWireless( idx, cls, wireless )
    local o = { IsPCMod = true, Idx = idx, Cls = cls, Wl = wireless }
    function o:IsValid() return true end
    function o:EntIndex() return self.Idx end
    function o:GetClass() return self.Cls end
    function o:Data() return { IsWireless = self.Wl } end
    function o:GetPos() return Vec() end
    return o
end
ents = {
    FindInSphere = function() return { makeWireless( 11, "pcmod_router", true ), makeWireless( 12, "pcmod_router", false ), makeWireless( 13, "pcmod_router", true ) } end,
    FindByClass = function() return {} end,
}

-- Wi-Fi connect machinery: a fake network driver on the PC and a fake wireless
-- router the Control Panel can connect to.
local netDrv = { WirelessEnt = nil, WirelessPass = "" }
function netDrv:DisconnectWireless()
    if (self.WirelessEnt) then
        local r = PCMod.Data[ self.WirelessEnt:EntIndex() ].Drivers.webgr_router
        if (r and r.RemoveWirelessClient) then r:RemoveWirelessClient( ent ) end
    end
    self.WirelessEnt = nil
    self.WirelessPass = ""
    self.WirelessIPv4 = nil
end
local routerDrv = {}
local regResult = "assigned"
function routerDrv:AddWirelessClient( pc ) self.Added = pc return regResult end
function routerDrv:RemoveWirelessClient( pc ) self.Added = nil end
PCMod.Data[ 1 ].Drivers = { gen_network = netDrv }
PCMod.Data[ 50 ] = { Drivers = { webgr_router = routerDrv } }
local wifi = { IsPCMod = true }
function wifi:IsValid() return true end
function wifi:EntIndex() return 50 end
function wifi:GetClass() return "pcmod_router" end
function wifi:Data() return { IsWireless = true, WirePass = "123" } end
ents.GetByIndex = function( idx ) if (idx == 50) then return wifi end return nil end

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
assertEq( #prog.DeviceData.Wireless, 2, "only wireless routers in range returned" )
assertEq( prog.DeviceData.Wireless[ 1 ].Distance, 120, "wireless distance" )
assertEq( prog.DeviceData.Wireless[ 1 ].Signal, 88, "wireless signal percentage" )
assertEq( prog.DeviceData.Wireless[ 1 ].Class, "pcmod_router", "wireless router class" )

-- Wi-Fi connect: reject a wrong password, accept the default, then disconnect.
prog:DoCommand( "connect_wifi", { "50", "wrong" } )
assertTrue( prog.DeviceData.Wifi.BadPass, "wrong Wi-Fi password flagged" )
assertTrue( netDrv.WirelessEnt == nil, "wrong password leaves no link" )
prog:DoCommand( "connect_wifi", { "50", "123" } )
assertTrue( prog.DeviceData.Wifi.Connected, "Wi-Fi connected" )
assertEq( prog.DeviceData.Wifi.EntIndex, 50, "Wi-Fi router index" )
assertTrue( netDrv.WirelessEnt == wifi, "network driver holds the link" )
assertTrue( routerDrv.Added == ent, "router recorded the wireless client" )
prog:DoCommand( "disconnect_wifi", {} )
assertTrue( !prog.DeviceData.Wifi.Connected, "Wi-Fi disconnected" )
assertTrue( netDrv.WirelessEnt == nil, "network driver cleared the link" )

-- Full DHCP pool: still connected, but marked IPv6-only instead of refused.
regResult = "full"
prog:DoCommand( "connect_wifi", { "50", "123" } )
assertTrue( prog.DeviceData.Wifi.Connected, "full pool still connects" )
assertTrue( prog.DeviceData.Wifi.NoIPv4, "full pool client is IPv6-only" )
regResult = "assigned"
prog:DoCommand( "disconnect_wifi", {} )

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
