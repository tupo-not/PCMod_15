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
dofile( "pcmod_sh_netproto.lua" )
dofile( "pcmod_sh_l2.lua" )
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

-- A known destination MAC is unicast back to the port it was learned on.
sent = {}
local reply = { "sendpacket", { "192.168.0.3", "192.168.0.9", 80, "reply" } }
reply[ 4 ] = { SourceMAC = "AA:BB:CC:DD:EE:03", DestMAC = frame2[ 4 ].SourceMAC }
fwd:DataRecieved( 3, reply )
assertEq( count( sent ), 1, "known destination MAC is unicast" )
assertTrue( sent[ 2 ] != nil, "reply is sent to the port that owns the destination MAC" )

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

-- Pure L2: no router relay and no IP awareness. The switch only learns MACs.
assertTrue( sw.CollectSegment == nil, "switch has no topology walk" )
assertTrue( sw.GetBridgePeers == nil, "switch does not expose devices to routers" )
assertTrue( fwd.IPTable == nil, "switch keeps no IP table" )
assertTrue( fwd.MacTable != nil, "switch learns MACs" )

print( "mock_switch PASSED" )
