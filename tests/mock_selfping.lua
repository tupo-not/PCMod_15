-- Self-addressed packets are delivered locally (a host can ping itself).
PCMod = {
	Msg = function() end,
	Cfg = { DefaultTTL = 64, WirelessRange = 0 },
	Data = {},
	DeriveDriver = function() return {} end,
	IPv6 = {
		IsLoopback = function( a ) return (a == "127.0.0.1") || (a == "::1") end,
	},
}
SERVER = true
CLIENT = false

dofile( "pcmod_drv_network.lua" )

local function assertEq( a, b, m )
	if (a != b) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end
local function assertTrue( v, m )
	if (not v) then error( "FAILED: " .. m, 2 ) end
end

local delivered = {}
local wired = nil
local ent = {}
function ent:IsValid() return true end
function ent:EntIndex() return 1 end
function ent:IsAddressedTo( a )
	return (a == "192.168.5.20") || (a == "fd00:1:0:5::20") || (a == "10.0.1.4")
end
function ent:GetSourceAddress( dest ) return dest end
function ent:GetFullIP() return "192.168.5.20" end
function ent:GetIPv6() return "fd00:1:0:5::20" end
function ent:Data() return { IP = {} } end
function ent:SendPacket( portid, dest, port, body, ttl, src )
	wired = { portid = portid, dest = dest, port = port, body = body }
	return 0
end

local drv = {}
for k, v in pairs( DRV ) do drv[ k ] = v end
drv.Entity = ent
drv.NetworkPort = 1
drv.WirelessConnected = function() return false end
drv.PacketRecieved = function( self, pk ) delivered[ #delivered + 1 ] = pk end

-- Pinging our own IPv4 address is delivered locally, never put on the wire.
drv:SendPacket( "192.168.5.20", 0, { "netPing", "nettools" } )
assertEq( #delivered, 1, "self IPv4 ping delivered locally" )
assertEq( delivered[ 1 ].Dest, "192.168.5.20", "local packet destination" )
assertEq( delivered[ 1 ].Source, "192.168.5.20", "local packet source identity" )
assertEq( delivered[ 1 ].Body[ 1 ], "netPing", "local packet body" )
assertTrue( delivered[ 1 ].Delivered == true, "local packet marked delivered" )
assertTrue( wired == nil, "self IPv4 ping did not hit the wire" )

-- The emulated IPv6 form of our own address behaves the same.
drv:SendPacket( "fd00:1:0:5::20", 0, { "netPing", "nettools" } )
assertEq( #delivered, 2, "self IPv6 ping delivered locally" )
assertTrue( wired == nil, "self IPv6 ping did not hit the wire" )

-- Loopback (127.0.0.1 / ::1) is still handled.
drv:SendPacket( "127.0.0.1", 0, { "netPing", "nettools" } )
assertEq( #delivered, 3, "IPv4 loopback delivered" )
drv:SendPacket( "::1", 0, { "netPing", "nettools" } )
assertEq( #delivered, 4, "IPv6 loopback delivered" )

-- A remote address still goes out the network port.
drv:SendPacket( "192.168.5.99", 0, { "netPing", "nettools" } )
assertEq( #delivered, 4, "remote packet not delivered locally" )
assertTrue( wired != nil and wired.dest == "192.168.5.99", "remote packet leaves the host" )
assertEq( wired.portid, 1, "remote packet uses the network port" )

-- Unplugging the last cable drops a leased identity, so the old address is not
-- left on screen for a replacement device that gets it next.
local ipdata = {
	LAN = "192.168.5.20", WanBB = 1, WanHost = 4,
	Extra = { { IPv4 = "192.168.6.9" } }, Router = 5,
	Mask = "255.255.255.0", MaskBits = 24, Gateway = "192.168.5.1",
}
local ent2 = {}
function ent2:IsValid() return true end
function ent2:Data() return { IP = ipdata } end
function ent2:SetLanAddress( v ) ipdata.LAN = v or false end
function ent2:SetBSubnet( v ) ipdata.WanBB = v or false end
function ent2:SetBIP( v ) ipdata.WanHost = v or false end
drv.Entity = ent2
drv.HasNetworkLink = function() return false end
drv:CallEvent( { Event = "unlinked" } )
assertTrue( ipdata.LAN == false, "unlink clears the leased LAN address" )
assertTrue( ipdata.WanBB == false and ipdata.WanHost == false, "unlink clears the leased WAN address" )
assertEq( #ipdata.Extra, 0, "unlink clears secondary leases" )
assertTrue( ipdata.Router == false, "unlink forgets the lease owner" )

-- A static address is configured, not leased, and survives the unplug.
ipdata.Static = "192.168.5.50"
ipdata.LAN = "192.168.5.50"
drv:CallEvent( { Event = "unlinked" } )
assertEq( ipdata.LAN, "192.168.5.50", "static address survives an unlink" )

print( "ALL SELFPING TESTS PASSED" )
