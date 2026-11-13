-- Five optical switches in series must still flood one broadcast end to end.
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
	function ent:GetClass() return "pcmod_switch" end
	function ent:SetNWString( k, v ) nw[ idx ] = nw[ idx ] or {}; nw[ idx ][ k ] = v end
	PCMod.Data[ idx ] = { Subsystems = {}, HardDrive = {}, EHooks = {} }
	return ent
end

local function assertEq( a, b, msg )
	if (a != b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function count( t )
	local n = 0
	for _ in pairs( t ) do n = n + 1 end
	return n
end

-- Chain: SINK <- sw1 <- sw2 <- sw3 <- sw4 <- sw5
local N = 5
local switches = {}
for i = 1, N do
	local sw = makeSwitch( i )
	sw:Setup( { Mode = "optic" } )
	local ports = PCMod.Data[ i ].Ports
	-- Only ports 1 and 2 are cabled in the chain.
	for k in pairs( ports ) do ports[ k ].Connected = false end
	local sent = {}
	function sw:PushData( port, data )
		local p = self:Ports()[ port ]
		if ((!p) || (!p.Connected) || (!p.ConEnt)) then return 2 end
		sent[ #sent + 1 ] = tostring( port )
		return p.ConEnt:GivenData( p.RemotePort, data )
	end
	sw.Sent = sent
	switches[ i ] = sw
end

-- sink entity at the far end
local sink = {
	Entries = {},
}
function sink:IsValid() return true end
function sink:EntIndex() return 999 end
function sink:GivenData( port, data ) self.Entries[ #self.Entries + 1 ] = { port = port, data = data } return 0 end

-- Wire the chain: switch i port 2 -> switch i+1 port 1, and switch N port 2 -> sink.
local function link( a, ap, b, bp )
	local pa = PCMod.Data[ a:EntIndex() ].Ports[ ap ]
	pa.Connected = true
	pa.ConEnt = b
	pa.RemotePort = bp
	local pb = PCMod.Data[ b:EntIndex() ].Ports[ bp ]
	pb.Connected = true
	pb.ConEnt = a
	pb.RemotePort = ap
end
for i = 1, N - 1 do link( switches[ i ], 2, switches[ i + 1 ], 1 ) end
local last = PCMod.Data[ switches[ N ]:EntIndex() ].Ports[ 2 ]
last.Connected = true
last.ConEnt = sink
last.RemotePort = 1

-- Feed a broadcast frame at switch 1 port 1 (the router side).
local frame = { "sendpacket", { "10.0.1.1", "10.0.2.1", 0, { "hello" } }, nil, { SourceMAC = "AA:BB:CC:00:00:01", DestMAC = PCMod.MAC.BROADCAST } }
switches[ 1 ]:DataRecieved( 1, frame )

assertEq( #sink.Entries, 1, "broadcast crosses all five switches" )
assertEq( sink.Entries[ 1 ].port, 1, "broadcast arrives on the sink port" )

-- Each switch in the chain forwarded exactly once.
for i = 1, N do
	assertEq( #switches[ i ].Sent, 1, "switch " .. i .. " forwarded the frame once" )
end

-- A second identical frame (new token) crosses again.
switches[ 1 ]:DataRecieved( 1, { "sendpacket", { "10.0.1.1", "10.0.2.1", 0, { "hello2" } }, nil, { SourceMAC = "AA:BB:CC:00:00:01", DestMAC = PCMod.MAC.BROADCAST } } )
assertEq( #sink.Entries, 2, "a new frame crosses all five switches" )

print( "mock_switch_chain PASSED" )