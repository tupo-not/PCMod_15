-- Switch entity: MAC generation/persistence and frame forwarding.
SERVER = true
CLIENT = false

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
}

// Load the base entity, then layer the switch entity on top of it (in-game
// this is what ENT.Base = "pcmod_base" does).
ENT = {}
dofile( "pcmod_shared.lua" )
local BaseENT = ENT
ENT = setmetatable( {}, { __index = BaseENT } )
dofile( "pcmod_switch.lua" )

local nw = {}
local function makeSwitch( idx )
	local ent = setmetatable( {}, { __index = ENT } )
	function ent:EntIndex() return idx end
	function ent:IsValid() return true end
	function ent:SetNWString( k, v ) nw[ idx ] = nw[ idx ] or {}; nw[ idx ][ k ] = v end
	PCMod.Data[ idx ] = { Drivers = {}, HardDrive = {}, EHooks = {} }
	return ent
end

local function assertEq( a, b, msg )
	if (a != b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function assertTrue( v, msg )
	if (!v) then error( "FAILED: " .. msg, 2 ) end
end
local function count( t )
	local n = 0
	for _ in pairs( t ) do n = n + 1 end
	return n
end

local MAC_PATTERN = "^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$"

-- Default configuration: Ethernet (network) ports + randomized MACs.
local sw = makeSwitch( 1 )
sw:Setup( nil )
local dt = PCMod.Data[ 1 ]
assertEq( dt.Mode, "ethernet", "default mode is ethernet" )
assertEq( #dt.Ports, sw.PortCount, "default port count" )
for i = 1, sw.PortCount do
	assertEq( dt.Ports[ i ].Type, "network", "ethernet port type" )
end
assertTrue( string.match( dt.MAC, MAC_PATTERN ) != nil, "base MAC is randomized and formatted" )
assertEq( #dt.PortMACs, sw.PortCount, "one MAC per port" )
assertEq( nw[ 1 ][ "MAC" ], dt.MAC, "MAC is networked" )
local seen = {}
for i = 1, sw.PortCount do
	assertTrue( string.match( dt.PortMACs[ i ], MAC_PATTERN ) != nil, "port MAC is formatted" )
	assertTrue( !seen[ dt.PortMACs[ i ] ], "port MACs are distinct" )
	seen[ dt.PortMACs[ i ] ] = true
	assertEq( sw:GetPortMAC( i ), dt.PortMACs[ i ], "GetPortMAC returns the port MAC" )
end
assertEq( sw:GetMAC(), dt.MAC, "GetMAC returns the base MAC" )

-- Optical configuration.
local opt = makeSwitch( 2 )
opt:Setup( { Mode = "optic" } )
assertEq( PCMod.Data[ 2 ].Mode, "optic", "optical mode selected" )
for i = 1, opt.PortCount do
	assertEq( PCMod.Data[ 2 ].Ports[ i ].Type, "optic", "optical port type" )
end

-- Unknown mode falls back to Ethernet.
local bad = makeSwitch( 3 )
bad:Setup( { Mode = "wifi" } )
assertEq( PCMod.Data[ 3 ].Mode, "ethernet", "unknown mode falls back to ethernet" )

-- Different spawns get different MACs.
assertTrue( dt.MAC != PCMod.Data[ 2 ].MAC, "switches get independent base MACs" )

-- Duplicator clones get fresh base + per-port MACs; two copies on one segment
-- must not share hardware addresses.
local info = sw:BuildDupeInfo()
assertEq( info.mac, dt.MAC, "dupe info saves the base MAC" )
assertTrue( info.portmacs == dt.PortMACs, "dupe info saves the port MACs" )

local sourceMAC, sourcePorts = dt.MAC, dt.PortMACs
sw:OnDuplicated()
assertTrue( dt.MAC != sourceMAC, "clone gets a fresh base MAC" )
assertTrue( dt.PortMACs != sourcePorts, "clone gets a fresh port MAC table" )
for i = 1, sw.PortCount do
	assertTrue( dt.PortMACs[ i ] != sourcePorts[ i ], "clone port " .. i .. " MAC is fresh" )
end
local cloneMAC, clonePorts = dt.MAC, dt.PortMACs
sw:ApplyDupeInfo( nil, sw, info, function() return nil end )
assertEq( dt.MAC, cloneMAC, "paste keeps the fresh clone MAC" )
assertTrue( dt.PortMACs == clonePorts, "paste keeps the fresh clone port MACs" )

-- Plain map save/load hooks keep the MACs as well.
local saved = sw:OnSave()
assertEq( saved.mac, cloneMAC, "OnSave stores the base MAC" )
assertTrue( saved.portmacs == clonePorts, "OnSave stores the port MACs" )
PCMod.Data[ 1 ].MAC = nil
PCMod.Data[ 1 ].PortMACs = nil
sw:OnRestore( saved )
assertEq( PCMod.Data[ 1 ].MAC, cloneMAC, "OnRestore restores the base MAC" )
assertTrue( PCMod.Data[ 1 ].PortMACs == clonePorts, "OnRestore restores the port MACs" )

-- Forwarding: a frame is repeated to every port except the ingress.
local fwd = makeSwitch( 4 )
fwd:Setup( { Mode = "ethernet" } )
for i, p in pairs( PCMod.Data[ 4 ].Ports ) do p.Connected = true end
local sent = {}
function fwd:PushData( port, data )
	sent[ port ] = data
	return 0
end

local frame = { "sendpacket", { "192.168.0.2", "192.168.0.3", 80, "hi" } }
fwd:DataRecieved( 1, frame )
assertTrue( frame[ 3 ] && frame[ 3 ].switchframe, "sendpacket frame gets a loop token" )
assertEq( count( sent ), fwd.PortCount - 1, "frame is flooded to every other port" )
assertTrue( sent[ 1 ] == nil, "frame is not sent back out of the ingress port" )

-- The same frame returning round a loop is dropped.
local before = count( sent )
fwd:DataRecieved( 2, frame )
assertEq( count( sent ), before, "looped sendpacket frame is dropped" )

-- A new frame gets a new token and is forwarded again.
local macA = frame[ 4 ].SourceMAC
sent = {}
local frame2 = { "sendpacket", { "192.168.0.9", "192.168.0.3", 80, "again" } }
fwd:DataRecieved( 2, frame2 )
assertEq( count( sent ), fwd.PortCount - 1, "new sendpacket frame is forwarded" )

-- Once a MAC/IP has been learned the switch unicasts to that port.
sent = {}
local reply = { "sendpacket", { "192.168.0.3", "192.168.0.2", 80, "reply" } }
fwd:DataRecieved( 3, reply )
assertEq( count( sent ), 1, "known destination is unicast" )
assertTrue( sent[ 1 ] != nil, "reply is sent to the port that owns the destination MAC" )
assertTrue( PCMod.MAC.Equal( reply[ 4 ].DestMAC, macA ), "frame carries the learned destination MAC" )

-- Deliver frames use the packet table as their identity.
PCMod.Network.Packets[ 1 ] = {}
sent = {}
fwd:DataRecieved( 1, { "deliver", 1, 0 } )
assertEq( count( sent ), fwd.PortCount - 1, "deliver frame is flooded" )
before = count( sent )
fwd:DataRecieved( 2, { "deliver", 1, 0 } )
assertEq( count( sent ), before, "looped deliver frame is dropped" )

-- A recycled packet slot (new packet object) is not mistaken for the old one.
PCMod.Network.Packets[ 1 ] = {}
sent = {}
fwd:DataRecieved( 2, { "deliver", 1, 0 } )
assertEq( count( sent ), fwd.PortCount - 1, "recycled deliver frame is forwarded" )

-- Unknown packets are not flooded.
sent = {}
fwd:DataRecieved( 1, { "deliver", 99, 0 } )
assertEq( count( sent ), 0, "unknown deliver frame is dropped" )

-- Topology relay: routers must learn about devices on other switch ports,
-- otherwise a switch breaks backbone/LAN prefix assignment.
local seg = makeSwitch( 5 )
seg:Setup( { Mode = "optic" } )
local events = {}
local function makeRouter( idx, cls )
	local r = { IsPCMod = true }
	local p = {}
	function r:IsValid() return true end
	function r:EntIndex() return idx end
	function r:GetClass() return cls end
	function r:Ports() return { [ 1 ] = p } end
	function r:FireEvent( ev ) table.insert( events, { Ent = idx, Ev = ev } ) end
	return r
end
local br = makeRouter( 80, "pcmod_brouter" )
local lr = makeRouter( 81, "pcmod_router" )
local segPorts = PCMod.Data[ 5 ].Ports
segPorts[ 1 ].Connected = true
segPorts[ 1 ].ConEnt = br
segPorts[ 2 ].Connected = true
segPorts[ 2 ].ConEnt = lr
br:Ports()[ 1 ].ConEnt = seg
lr:Ports()[ 1 ].ConEnt = seg

seg:NotifyBridgeLinked()
local function findEvent( entIdx, name, peer )
	for _, e in ipairs( events ) do
		if (e.Ent == entIdx && e.Ev[ 1 ] == name && e.Ev[ #e.Ev ] == peer) then return e end
	end
	return nil
end
assertTrue( findEvent( 80, "linked", lr ) != nil, "backbone router sees the LAN router behind the switch" )
assertTrue( findEvent( 81, "linked", br ) != nil, "LAN router sees the backbone router behind the switch" )
assertEq( findEvent( 80, "linked", lr ).Ev[ 2 ], 1, "far-side link carries the router's own port index" )

-- Unplugging the LAN router tells the backbone it is gone, and vice versa.
segPorts[ 2 ].Connected = false
segPorts[ 2 ].ConEnt = nil
events = {}
seg:NotifyBridgeUnlinked( lr )
assertTrue( findEvent( 80, "unlinked", lr ) != nil, "backbone router is told the LAN router left" )
assertTrue( findEvent( 81, "unlinked", br ) != nil, "removed router is told about the remaining peer" )

-- A computer on the backbone segment is also announced to the backbone router,
-- so it can be given a 10.x host address.
local pc = makeRouter( 82, "pcmod_tower" )
pc.IsComputer = true
pc:Ports()[ 1 ].ConEnt = seg
segPorts[ 3 ].Connected = true
segPorts[ 3 ].ConEnt = pc
events = {}
seg:NotifyBridgeLinked()
assertTrue( findEvent( 80, "linked", pc ) != nil, "backbone router sees a computer behind the switch/modem" )

print( "mock_switch PASSED" )
