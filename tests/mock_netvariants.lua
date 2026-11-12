-- Router/Modem entity variants: port roles and media conversion.
SERVER = true
CLIENT = false

function table.Copy( t )
	if (type( t ) ~= "table") then return t end
	local o = {}
	for k, v in pairs( t ) do o[ k ] = table.Copy( v ) end
	return o
end
function table.Count( t )
	local n = 0
	for _ in pairs( t ) do n = n + 1 end
	return n
end
function istable( v ) return type( v ) == "table" end
function AddCSLuaFile() end
function IsValid( v ) return v ~= nil end
function Msg() end
function ErrorNoHalt() end
util = {
	TableToJSON = function( t ) return t end,
	JSONToTable = function( s ) return s end,
}

PCMod = {}
PCMod.Data = {}
PCMod.Cfg = {}
PCMod.Msg = function() end
PCMod.Warning = function() end
PCMod.TableToString = function( t ) return t end
PCMod.StringToTable = function( s ) return s end

dofile( "pcmod_sh_common.lua" )
PCMod.Msg = function() end

PCMod.Wiring = {
	TypeToName = function( t ) return t end,
	CanWireSameType = function() return false end,
}
PCMod.Network = {
	NextSwitchFrame = 0,
	Packets = {},
	RegisterRouter = function() return true end,
	UnRegisterRouter = function() end,
}
PCMod.Subsystems = {}
PCMod.Subsystems[ "router" ] = {
	Initialize = function() end,
	ApplyLanAddress = function() end,
}

local function assertEq( a, b, msg )
	if (a != b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function assertTrue( v, msg )
	if (!v) then error( "FAILED: " .. msg, 2 ) end
end

local BaseENT = nil
local SwitchENT = nil
local RouterENT = nil

ENT = {}
dofile( "pcmod_shared.lua" )
BaseENT = ENT

local function makeEnt( idx, prototype )
	local ent = setmetatable( {}, { __index = prototype } )
	ent.Entity = ent
	function ent:EntIndex() return idx end
	function ent:IsValid() return true end
	function ent:SetNWString() end
	function ent:SetGVar() end
	PCMod.Data[ idx ] = { Subsystems = {}, HardDrive = {}, EHooks = {} }
	return ent
end

-- Modem: inherits the switch bridge, but exposes one fibre uplink and four
-- Ethernet ports.
ENT = setmetatable( {}, { __index = BaseENT } )
dofile( "pcmod_switch.lua" )
SwitchENT = ENT

ENT = setmetatable( {}, { __index = SwitchENT } )
dofile( "pcmod_modem.lua" )
local modem = makeEnt( 1, ENT )
assertEq( modem.PrintName, "Modem", "modem name" )
assertTrue( modem.IsModem, "modem marker" )
assertTrue( modem.IsSwitch, "modem bridges like a switch" )
modem:Setup()
local mports = PCMod.Data[ 1 ].Ports
assertEq( #mports, 2, "modem has two ports" )
assertEq( mports[ 1 ].Type, "optic", "modem uplink is fibre" )
assertEq( mports[ 2 ].Type, "network", "modem has one Ethernet link" )
assertTrue( PCMod.MAC.IsValid( PCMod.Data[ 1 ].MAC ), "modem gets a MAC" )
assertEq( #PCMod.Data[ 1 ].PortMACs, 2, "modem gets one MAC per port" )

-- Router variant: same LAN behaviour as the LAN modem, but the WAN port is an
-- Ethernet port flagged for the router subsystem.
ENT = setmetatable( {}, { __index = BaseENT } )
dofile( "pcmod_router.lua" )
RouterENT = ENT

ENT = setmetatable( {}, { __index = RouterENT } )
dofile( "pcmod_erouter.lua" )
local erouter = makeEnt( 2, ENT )
assertEq( erouter.PrintName, "Router", "Ethernet router name" )
assertEq( erouter.WanType, "network", "Ethernet WAN type" )
erouter:Setup( { Wireless = false } )
local rports = PCMod.Data[ 2 ].Ports
assertEq( #rports, 5, "router still has five ports" )
assertEq( rports[ 1 ].Type, "network", "WAN port is Ethernet" )
assertTrue( rports[ 1 ].WAN, "port 1 is the flagged WAN uplink" )
for i = 2, 5 do
	assertEq( rports[ i ].Type, "network", "LAN port " .. i .. " is Ethernet" )
	assertTrue( !rports[ i ].WAN, "LAN port " .. i .. " is not the WAN uplink" )
end

-- The LAN modem keeps the fibre WAN, still on port 1.
local lanmodem = makeEnt( 3, RouterENT )
assertEq( lanmodem.PrintName, "LAN Modem", "LAN modem name" )
assertEq( lanmodem.WanType, "optic", "LAN modem WAN type" )
lanmodem:Setup( { Wireless = false } )
local lports = PCMod.Data[ 3 ].Ports
assertEq( lports[ 1 ].Type, "optic", "LAN modem WAN is fibre on port 1" )
assertTrue( !lports[ 1 ].WAN, "fibre WAN does not need the Ethernet flag" )

-- The merged spawn tool can pick the uplink medium for the same base entity.
local switchable = makeEnt( 4, RouterENT )
switchable:Setup( { Wireless = false, Uplink = "network" } )
local sports = PCMod.Data[ 4 ].Ports
assertEq( sports[ 1 ].Type, "network", "selected Ethernet WAN medium" )
assertTrue( sports[ 1 ].WAN, "selected Ethernet WAN is flagged for the subsystem" )
for i = 2, 5 do assertEq( sports[ i ].Type, "network", "remaining ports stay LAN Ethernet" ) end

-- Shared class helpers treat both LAN router variants alike.
assertTrue( PCMod.IsLanRouterClass( "pcmod_router" ), "fibre LAN router helper" )
assertTrue( PCMod.IsLanRouterClass( "pcmod_erouter" ), "Ethernet LAN router helper" )
assertTrue( PCMod.IsRouterClass( "pcmod_brouter" ), "backbone router helper" )
assertTrue( !PCMod.IsLanRouterClass( "pcmod_brouter" ), "backbone is not a LAN router" )
assertTrue( !PCMod.IsRouterClass( "pcmod_switch" ), "switch is not a router" )

print( "NETWORK VARIANTS TESTS PASSED" )
