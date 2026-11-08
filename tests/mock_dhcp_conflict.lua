-- DHCP safety: a station must never apply another station's answer, the server
-- must not offer an address something already uses, and stale lease rows must
-- not be shown as active.
function string.Trim( s )
	return (string.gsub( s, "^%s*(.-)%s*$", "%1" ))
end
function istable( v ) return type( v ) == "table" end
math.Clamp = function( v, a, b ) if (v < a) then return a end if (v > b) then return b end return v end
PCMod = {
	Msg = function() end,
	Cfg = { DHCPStart = 2, DHCPEnd = 254 },
	Network = {},
	DeriveDriver = function() return {} end,
}

dofile( "pcmod_sh_common.lua" )
dofile( "pcmod_sh_netproto.lua" )
dofile( "pcmod_sh_dhcp_server.lua" )
dofile( "pcmod_sh_dhcp_client.lua" )

local function assertEq( a, b, m )
	if (a ~= b) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end
local function assertTrue( v, m )
	if (not v) then error( "FAILED: " .. m, 2 ) end
end

-- A LAN router stub with a 192.168.5.0/24 pool starting at host 2.
local cfgData = {
	IP = { UpBB = 7, LanID = 12 },
	RouterCfg = { DHCPStart = 2, DHCPEnd = 10, Leases = {}, LanStaticLeases = {}, StaticLeases = {} },
}
local rent = {}
function rent:GetBSubnet() return nil end
function rent:GetClass() return "pcmod_router" end
function rent:EntIndex() return 1 end
function rent:Data() return cfgData end
function rent:PushData() return 2 end
local router = { Entity = rent, NPorts = { 1 }, OPorts = {} }
function router:GetCfg() return cfgData.RouterCfg end
function router:GetLanBase() return 5 * 256 end
function router:IsBackbone() return false end
function router:InterfaceIP() return "192.168.5.1" end

-- Another device on the wire answers ARP for .2 (for example a static host or
-- a client of a second DHCP server), so the allocator must skip it.
local inUse = { [ "192.168.5.2" ] = true }
PCMod.ARP = {
	Resolve = function( r, ip )
		if (inUse[ ip ]) then return { ip = ip, mac = "AA:BB:CC:DD:EE:02" } end
		return nil
	end,
}

assertEq( PCMod.DHCPServer.AllocHost( router, "lan", "AA:BB:CC:DD:EE:10" ), 3, "ARP-conflicting address is skipped" )

-- A live lease also blocks its host; the next free address wins.
cfgData.RouterCfg.Leases[ "AA:BB:CC:DD:EE:20" ] = {
	mac = "AA:BB:CC:DD:EE:20", scope = "lan", host = 3, ip = "192.168.5.3",
	offered = false, expires = PCMod.Net.Now() + 3600,
}
assertEq( PCMod.DHCPServer.AllocHost( router, "lan", "AA:BB:CC:DD:EE:10" ), 4, "live leases and ARP conflicts are both skipped" )

-- Offers carry the station MAC so a broadcast answer cannot be applied by the
-- wrong machine.
local rec = PCMod.DHCPServer.Offer( router, "lan", "AA:BB:CC:DD:EE:10", 77, 1 )
assertEq( rec.ip, "192.168.5.4", "offer uses the first fully free address" )
assertEq( PCMod.DHCPServer.Config( router, rec ).mac, "AA:BB:CC:DD:EE:10", "offer names the target MAC" )

-- Expired rows disappear from the lease listing instead of looking active.
cfgData.RouterCfg.Leases[ "AA:BB:CC:DD:EE:30" ] = {
	mac = "AA:BB:CC:DD:EE:30", scope = "lan", host = 30, ip = "192.168.5.30",
	offered = false, expires = PCMod.Net.Now() - 10,
}
for _, l in ipairs( PCMod.DHCPServer.List( router, "lan" ) ) do
	assertTrue( l.mac ~= "AA:BB:CC:DD:EE:30", "expired lease is not listed" )
end

-- Client-side guard: ignore an answer whose lease MAC is not ours.
local applied = nil
local owner = {
	Entity = { IsValid = function() return true end },
	DHCPState = {
		xid = 42,
		mac = "AA:BB:CC:DD:EE:01",
		send = function() end,
		apply = function( cfg ) applied = cfg end,
	},
}
PCMod.DHCPClient.Handle( owner, PCMod.Net.DHCPAck( 42, 1, { ip = "192.168.5.9", mac = "AA:BB:CC:DD:EE:02", scope = "lan" } ) )
assertTrue( applied == nil, "ack for another MAC is ignored" )
PCMod.DHCPClient.Handle( owner, PCMod.Net.DHCPAck( 42, 1, { ip = "192.168.5.9", mac = "AA:BB:CC:DD:EE:01", scope = "lan" } ) )
assertTrue( applied ~= nil, "ack for our MAC is applied" )
assertEq( applied.ip, "192.168.5.9", "accepted address" )

print( "mock_dhcp_conflict PASSED" )
