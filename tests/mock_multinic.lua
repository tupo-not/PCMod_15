-- Two Ethernet adapters: each keeps its own DHCP lease, and outbound traffic
-- picks the interface that owns the destination subnet.
PCMod = {
	Msg = function() end,
	Cfg = { DefaultTTL = 64, WirelessRange = 0 },
	Data = {},
	DeriveSubsystem = function() return {} end,
	DHCPClient = {},
	IPv6 = {
		IsLoopback = function( a ) return (a == "127.0.0.1") || (a == "::1") end,
		IsIPv6 = function( a ) return (type( a ) == "string") && (string.find( a, ":", 1, true ) != nil) end,
		Hierarchy = function( a )
			if (a == "fd00:2:0:2::9") then return { bb = 2, lan = 2, iid = 9 } end
			if (a == "fd00:1:0:1::9") then return { bb = 1, lan = 1, iid = 9 } end
			return nil
		end,
		Format = function( g )
			return "fd00:" .. tostring( g[ 2 ] ) .. ":0:" .. tostring( g[ 4 ] ) .. "::" .. tostring( g[ 8 ] )
		end,
		LANPrefix = function( bb, sub )
			return "fd00:" .. tostring( bb ) .. ":0:" .. tostring( sub ) .. "::/64"
		end,
		BackbonePrefix = function( bb )
			return "fd00:" .. tostring( bb ) .. "::/32"
		end,
		Gateway = function( prefix ) return "gw:" .. tostring( prefix ) end,
		LinkLocal = function( v6 ) return "ll:" .. tostring( v6 ) end,
	},
	IPv4 = {
		SameLan = function( a, b, bits )
			local pa = string.match( a, "^(%d+%.%d+%.%d+)%." )
			local pb = string.match( b, "^(%d+%.%d+%.%d+)%." )
			return (pa != nil) && (pa == pb)
		end,
		ParseLan = function( ip )
			local a, b, c, d = string.match( ip, "^(%d+)%.(%d+)%.(%d+)%.(%d+)$" )
			if (!a) then return nil end
			return { a = tonumber( a ), b = tonumber( b ), c = tonumber( c ), d = tonumber( d ), sub = tonumber( c ), add = tonumber( d ) }
		end,
		IsBackbone = function() return false end,
	},
	Net = { BroadcastIP = "255.255.255.255", DHCPServerPort = 67 },
}
SERVER = true
CLIENT = false

dofile( "pcmod_subsystem_network.lua" )

local function assertEq( a, b, m )
	if (a != b) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end
local function assertTrue( v, m )
	if (not v) then error( "FAILED: " .. m, 2 ) end
end

local ports = {
	[ 1 ] = { Type = "network", Connected = true },
	[ 2 ] = { Type = "network", Connected = true },
}
local sent = nil
local ent = {}
function ent:IsValid() return true end
function ent:EntIndex() return 7 end
function ent:Ports() return ports end
function ent:Data() return { IP = {} } end
function ent:IsAddressedTo() return false end
function ent:GetSourceAddress( dest ) return dest end
function ent:SendPacket( portid, dest, port, body, ttl, src )
	sent = { portid = portid, dest = dest, src = src }
	return 0
end
function ent:EnsureInterfaceMAC( port ) return "MAC" .. tostring( port ) end

local drv = {}
for k, v in pairs( SUBSYSTEM ) do drv[ k ] = v end
drv.Entity = ent
drv.NetworkPorts = { 1, 2 }
drv.NetworkPort = 1
drv.DHCPByPort = {
	[ 1 ] = { Lease = { ip = "192.168.1.2", maskbits = 24, server = 10, upbb = 1, lanid = 1 } },
	[ 2 ] = { Lease = { ip = "10.0.0.2", maskbits = 24, server = 11, upbb = 2, lanid = 2 } },
}
drv.WirelessConnected = function() return false end
drv.PacketRecieved = function() end

drv:SendPacket( "192.168.1.9", 0, { "payload" } )
assertEq( sent.portid, 1, "traffic to the first subnet leaves adapter 1" )
assertEq( sent.src, "192.168.1.2", "source is adapter 1's lease" )

drv:SendPacket( "10.0.0.9", 0, { "payload" } )
assertEq( sent.portid, 2, "traffic to the second subnet leaves adapter 2" )
assertEq( sent.src, "10.0.0.2", "source is adapter 2's lease" )

drv:SendPacket( "10.0.0.9", 0, { "payload" }, nil, "10.0.0.2" )
assertEq( sent.portid, 2, "a reply sourced from adapter 2's address uses adapter 2" )

drv:SendPacket( "fd00:2:0:2::9", 0, { "payload" } )
assertEq( sent.portid, 2, "IPv6 traffic follows the matching /64 to adapter 2" )

drv:SendPacket( "fd00:1:0:1::9", 0, { "payload" } )
assertEq( sent.portid, 1, "IPv6 traffic follows the matching /64 to adapter 1" )

-- A discover pinned to one adapter must leave through that adapter.
drv:SendPacket( PCMod.Net.BroadcastIP or "255.255.255.255", 67, { "dhcp" }, nil, "0.0.0.0", nil, 1 )
assertEq( sent.portid, 1, "a pinned DHCP discover stays on adapter 1" )

-- Wi-Fi is another interface (port 0), not a preferred uplink. Traffic to its
-- subnet must use it; traffic to an Ethernet subnet must not.
local wifiSent = nil
drv.WirelessEnt = { DataRecieved = function( self, port, data ) wifiSent = { port = port, data = data } end }
drv.WirelessConnected = function() return true end
drv.DHCPByPort[ 0 ] = { Lease = { ip = "192.168.50.2", maskbits = 24, server = 12, upbb = 5, lanid = 5 } }
assertTrue( drv:HasOtherInterface( 2 ), "an adapter sees the Wi-Fi link as another interface" )
assertTrue( drv:HasOtherInterface( 0 ), "Wi-Fi sees the wired link as another interface" )
sent = nil
wifiSent = nil
drv:SendPacket( "192.168.50.9", 0, { "payload" } )
assertTrue( sent == nil, "Wi-Fi subnet traffic does not use an Ethernet adapter" )
assertEq( wifiSent.port, 0, "Wi-Fi subnet traffic leaves through the wireless interface" )
assertEq( wifiSent.data[ 2 ][ 1 ], "192.168.50.2", "Wi-Fi traffic sources from the Wi-Fi lease" )

sent = nil
wifiSent = nil
drv:SendPacket( "10.0.0.9", 0, { "payload" } )
assertEq( sent.portid, 2, "Ethernet subnet traffic still uses its adapter" )
assertTrue( wifiSent == nil, "Ethernet traffic does not jump to Wi-Fi" )

-- Replies follow the link they arrived on.
sent = nil
wifiSent = nil
drv:SendPacket( "192.168.50.9", 0, { "payload" }, nil, nil, true )
assertEq( wifiSent.port, 0, "Wi-Fi-originated reply leaves over Wi-Fi" )
assertTrue( sent == nil, "Wi-Fi reply does not use Ethernet" )

sent = nil
wifiSent = nil
drv:SendPacket( "10.0.0.9", 0, { "payload" }, nil, nil, false )
assertEq( sent.portid, 2, "wired reply leaves over its cable" )
assertTrue( wifiSent == nil, "wired reply does not jump to Wi-Fi" )

-- Every interface records its own full status, so the control panel can show
-- a separate block per adapter instead of one shared set of fields.
drv.DHCPByPort[ 1 ].Lease.netmask = "255.255.255.0"
drv.DHCPByPort[ 1 ].Lease.gateway = "192.168.1.1"
local info = drv:InterfaceInfo( 1, drv.DHCPByPort[ 1 ].Lease )
assertEq( info.Port, 1, "interface record keeps its port" )
assertEq( info.MAC, "MAC1", "interface record carries its own MAC" )
assertEq( info.Mask, "255.255.255.0", "interface record carries the netmask" )
assertEq( info.Gateway4, "192.168.1.1", "interface record carries the IPv4 gateway" )
assertEq( info.IPv6Prefix, "fd00:1:0:1::/64", "interface record carries its /64" )
assertEq( info.IPv6Gateway, "gw:fd00:1:0:1::/64", "interface record carries its IPv6 gateway" )
assertTrue( string.find( info.IPv6LinkLocal, "ll:", 1, true ) == 1, "interface record carries a link-local address" )

-- Losing one cable releases only that adapter's lease.
local released = nil
PCMod.DHCPClient.ReleaseHost = function( e, scope, rec, server )
	released = { scope = scope, rec = rec, server = server }
end
PCMod.DHCPClient.ApplyHost = function() end
drv.DHCPByPort[ 1 ].LastDHCP = { address = "192.168.1.2" }
drv.DHCPByPort[ 2 ].LastDHCP = { address = "10.0.0.2" }
ports[ 1 ].Connected = false
drv:ReleasePort( 1 )
assertTrue( released != nil, "unplugging adapter 1 releases its lease" )
assertEq( released.rec.ip, "192.168.1.2", "only the unplugged adapter's lease is released" )
assertTrue( drv.DHCPByPort[ 2 ].Lease != nil, "adapter 2 keeps its lease" )

-- Both ports are recognized as network interfaces.
assertEq( #drv:LinkedNetworkPorts(), 1, "only the still-linked adapter remains" )

print( "ALL MULTINIC TESTS PASSED" )
