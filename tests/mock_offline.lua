-- A powered-off computer must be silent on the network: no pings, ARP, DHCP,
-- or outbound traffic until it is turned back on.
SERVER = true
CLIENT = false
function istable( v ) return type( v ) == "table" end
PCMod = {
	Msg = function() end,
	Cfg = { DefaultTTL = 64, WirelessRange = 0 },
	Data = {},
	DeriveSubsystem = function() return {} end,
	GetSubsystem = function( data, name )
		if (!data || !data.Subsystems) then return nil end
		return data.Subsystems[ name ]
	end,
	IPv6 = {
		IsLoopback = function( a ) return (a == "127.0.0.1") || (a == "::1") end,
		IsIPv6 = function( a ) return (type( a ) == "string") && (string.find( a, ":", 1, true ) != nil) end,
	},
	Net = { BroadcastIP = "255.255.255.255", DHCPServerPort = 67 },
}

dofile( "pcmod_subsystem_network.lua" )

local function assertEq( a, b, msg )
	if (a != b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function assertTrue( v, msg )
	if (not v) then error( "FAILED: " .. msg, 2 ) end
end

local delivered = 0
local bios = { OS = { NetDataRecieved = function() delivered = delivered + 1 end } }
local data = { IsOn = false, Subsystems = { bios = bios } }
local sent = 0
local entity = {
	Data = function() return data end,
	IsValid = function() return true end,
	SendPacket = function() sent = sent + 1 end,
}
local net = {}
for k, v in pairs( SUBSYSTEM ) do net[ k ] = v end
net.Entity = entity

assertTrue( not net:IsPoweredOn(), "off host reports powered off" )
net:PacketRecieved( { Source = "1.2.3.4", Port = 0, Body = { "netPing" } } )
assertEq( delivered, 0, "off host ignores an incoming ping" )

local dhcp = 0
net.HandleDHCP = function() dhcp = dhcp + 1; return true end
net:DataRecieved( 1, { "sendpacket", { "1.2.3.4", "5.6.7.8", 0, { "dhcp" } } } )
assertEq( dhcp, 0, "off host ignores link-layer frames" )

net:SendPacket( "1.2.3.4", 0, { "netPing" } )
assertEq( sent, 0, "off host does not transmit" )

data.IsOn = true
assertTrue( net:IsPoweredOn(), "on host reports powered on" )
net:PacketRecieved( { Source = "1.2.3.4", Port = 0, Body = { "netPing" } } )
assertEq( delivered, 1, "on host answers a ping" )
net:DataRecieved( 1, { "sendpacket", { "1.2.3.4", "5.6.7.8", 0, { "dhcp" } } } )
assertEq( dhcp, 1, "on host handles link-layer frames" )

print( "ALL OFFLINE HOST TESTS PASSED" )
