-- Direct tests for the MAC-keyed DHCP engine (pcmod/sh_dhcp_server.lua) and
-- the entity release path (pcmod/sh_dhcp_client.lua). No router driver needed.
function string.Trim( s )
	return (string.gsub( s, "^%s*(.-)%s*$", "%1" ))
end
function istable( v ) return type( v ) == "table" end
math.Clamp = function( v, a, b ) if (v < a) then return a end if (v > b) then return b end return v end
PCMod = {
	Msg = function() end,
	Cfg = { DHCPStart = 2, DHCPEnd = 10, LanNetmask = 24 },
	Data = {},
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
local function assertNil( v, m )
	if (v ~= nil) then error( "FAILED: " .. m .. " got " .. tostring( v ), 2 ) end
end

-- Router stub: LAN is 192.168.5.0/24, backbone 100.0.7.0/24.
local cfgData = {
	IP = { UpBB = 3, LanID = 5 },
	RouterCfg = { DHCPStart = 2, DHCPEnd = 10, WanDHCPStart = 12, WanDHCPEnd = 20 },
}
local rent = {}
function rent:GetBSubnet() return 7 end
function rent:GetClass() return "pcmod_brouter" end
function rent:EntIndex() return 1 end
function rent:Data() return cfgData end
function rent:GetFullIP() return "192.168.5.1" end
function rent:GetFullBIP() return "100.0.7.1" end
local router = { Entity = rent }
function router:GetCfg() return cfgData.RouterCfg end
local function lanBase( octet ) return (192 * 16777216) + (168 * 65536) + (octet * 256) end
function router:GetLanBase() return lanBase( 5 ) end
function router:LanBlockSize() return 256 end
function router:PoolMax() return 254 end
function router:IsBackbone() return true end
function router:GetLanNetmask() return 24 end

-- LAN lease: allocated from the pool and keyed by MAC.
local mac1 = "AA:BB:CC:DD:EE:01"
local rec1 = PCMod.DHCPServer.Lease( router, "lan", mac1 )
assertTrue( rec1 ~= nil, "LAN lease created" )
assertEq( rec1.host, 2, "first LAN host" )
assertEq( rec1.ip, "192.168.5.2", "first LAN address" )
assertEq( rec1.scope, "lan", "LAN scope recorded" )
assertTrue( PCMod.DHCPServer.Find( router, "lan", mac1 ) == rec1, "lease is keyed by MAC" )

local rec2 = PCMod.DHCPServer.Lease( router, "lan", "AA:BB:CC:DD:EE:02" )
assertEq( rec2.host, 3, "second LAN host is distinct" )
assertTrue( rec2.ip ~= rec1.ip, "two leases never share an address" )

-- Static LAN reservation wins over the dynamic pool.
assertTrue( PCMod.DHCPServer.AddStatic( router, "lan", "192.168.5.7", "AA:BB:CC:DD:EE:07" ), "static LAN reservation stored" )
local pinned = PCMod.DHCPServer.Lease( router, "lan", "AA:BB:CC:DD:EE:07" )
assertEq( pinned.host, 7, "pinned MAC gets its reservation" )
assertTrue( pinned.static == true, "reservation is marked static" )
local dyn = PCMod.DHCPServer.Lease( router, "lan", "AA:BB:CC:DD:EE:08" )
assertEq( dyn.host, 4, "dynamic lease skips the reserved host" )

-- WAN lease: only a backbone serves the backbone pool.
local recW = PCMod.DHCPServer.Lease( router, "wan", "AA:BB:CC:DD:EE:20", 4 )
assertEq( recW.host, 12, "first WAN host" )
assertEq( recW.ip, "100.0.7.12", "first WAN address" )
assertEq( recW.bb, 7, "WAN lease records the backbone" )
assertEq( recW.port, 4, "WAN lease records its ingest port" )
assertTrue( PCMod.DHCPServer.AddStatic( router, "wan", "100.0.7.20", "AA:BB:CC:DD:EE:21" ), "static WAN reservation stored" )
assertEq( PCMod.DHCPServer.Lease( router, "wan", "AA:BB:CC:DD:EE:21" ).host, 20, "pinned WAN MAC gets its reservation" )

-- A non-backbone router cannot hand out backbone addresses.
local lanRouter = { Entity = rent }
function lanRouter:GetCfg() return { WanDHCPStart = 12, WanDHCPEnd = 20 } end
function lanRouter:IsBackbone() return false end
assertNil( PCMod.DHCPServer.Lease( lanRouter, "wan", "AA:BB:CC:DD:EE:22" ), "LAN router has no WAN pool" )

-- Release by MAC, and release everything that arrived on a port.
assertTrue( PCMod.DHCPServer.Release( router, mac1 ), "lease released" )
assertNil( PCMod.DHCPServer.Find( router, "lan", mac1 ), "released lease is gone" )
PCMod.DHCPServer.ReleasePort( router, "wan", 4 )
assertNil( PCMod.DHCPServer.Find( router, "wan", "AA:BB:CC:DD:EE:20" ), "port cleanup released the WAN lease" )

-- Readdress recomputes the cached address after the LAN network moves.
local before = PCMod.DHCPServer.Find( router, "lan", "AA:BB:CC:DD:EE:02" )
assertEq( before.ip, "192.168.5.3", "address before the move" )
function router:GetLanBase() return lanBase( 6 ) end
PCMod.DHCPServer.Readdress( router, "lan" )
assertEq( before.ip, "192.168.6.3", "address after the move" )
assertEq( before.host, 3, "host id is stable across a move" )
function router:GetLanBase() return lanBase( 5 ) end
PCMod.DHCPServer.Readdress( router, "lan" )

-- The DORA config names the target MAC and carries the interface settings.
local cfg = PCMod.DHCPServer.Config( router, PCMod.DHCPServer.Find( router, "lan", "AA:BB:CC:DD:EE:02" ) )
assertEq( cfg.mac, "AA:BB:CC:DD:EE:02", "config names the target MAC" )
assertEq( cfg.gateway, "192.168.5.1", "config carries the gateway" )
assertEq( cfg.maskbits, 24, "config carries the prefix length" )
assertEq( cfg.netmask, "255.255.255.0", "config carries the netmask" )

-- Entity release: a primary we own is cleared.
local function mkPC( idx )
	local o = { idx = idx, ipdata = { Extra = {}, LAN = false } }
	function o:IsValid() return true end
	function o:EntIndex() return self.idx end
	function o:Data() return { IP = self.ipdata } end
	function o:SetSubnet( s ) self.ipdata.LAN = s and ("192.168." .. tostring( s ) .. ".2") or false end
	function o:SetIP( h ) self.ipdata.LAN = h and ("192.168.5." .. tostring( h )) or false end
	function o:SetBSubnet( b ) self.ipdata.WanBB = b or false end
	function o:SetBIP( h ) self.ipdata.WanHost = h or false end
	function o:GetBSubnet() return self.ipdata.WanBB end
	function o:AddExtraIP( addr, ub, lid, r ) self.ipdata.Extra[ #self.ipdata.Extra + 1 ] = { IPv4 = addr, UpBB = ub, LanID = lid, Router = r } end
	function o:ReleaseExtraIP( addr )
		for i, ex in ipairs( self.ipdata.Extra ) do
			if (ex.IPv4 == addr) then table.remove( self.ipdata.Extra, i ) return true end
		end
		return false
	end
	return o
end

local own = mkPC( 10 )
own.ipdata.Router = 1
own.ipdata.LAN = "192.168.5.3"
PCMod.DHCPClient.ReleaseHost( own, "lan", before, 1 )
assertEq( own.ipdata.LAN, false, "primary address cleared" )
assertEq( own.ipdata.Router, false, "lease owner forgotten" )

local other = mkPC( 11 )
other.ipdata.Router = 999
other.ipdata.LAN = "192.168.9.2"
other.ipdata.Extra[ 1 ] = { IPv4 = "192.168.5.3", Router = 1 }
PCMod.DHCPClient.ReleaseHost( other, "lan", before, 1 )
assertEq( other.ipdata.LAN, "192.168.9.2", "primary owned by another router is untouched" )
assertEq( #other.ipdata.Extra, 0, "only our secondary is removed" )

local stat = mkPC( 12 )
stat.ipdata.Static = "192.168.5.9"
stat.ipdata.LAN = "192.168.5.9"
PCMod.DHCPClient.ReleaseHost( stat, "lan", before, 1 )
assertEq( stat.ipdata.LAN, "192.168.5.9", "static address survives a release" )

-- A WAN lease clears the backbone identity only when it matches.
local wanPC = mkPC( 13 )
wanPC.ipdata.WanBB = 7
wanPC.ipdata.WanHost = 11
PCMod.DHCPClient.ReleaseHost( wanPC, "wan", recW, 1 )
assertEq( wanPC.ipdata.WanBB, false, "WAN backbone cleared on release" )
assertEq( wanPC.ipdata.WanHost, false, "WAN host cleared on release" )

-- Reflow: after the pool shrinks, an out-of-range dynamic lease moves to the
-- first free host, and is dropped when there is no room left.
local rc = PCMod.DHCPServer.Cfg( router )
rc.Leases = {}
cfgData.RouterCfg.DHCPStart = 2
cfgData.RouterCfg.DHCPEnd = 3
rc.Leases[ "AA:BB:CC:DD:EE:40" ] = {
	mac = "AA:BB:CC:DD:EE:40", scope = "lan", host = 9, ip = "192.168.5.9",
	offered = false, expires = PCMod.Net.Now() + 3600,
}
local moved = PCMod.DHCPServer.Reflow( router, "lan" )
assertEq( #moved, 0, "out-of-pool lease was moved" )
assertEq( rc.Leases[ "AA:BB:CC:DD:EE:40" ].host, 2, "moved to the first free host" )
rc.Leases[ "AA:BB:CC:DD:EE:41" ] = {
	mac = "AA:BB:CC:DD:EE:41", scope = "lan", host = 3, ip = "192.168.5.3",
	offered = false, expires = PCMod.Net.Now() + 3600,
}
rc.Leases[ "AA:BB:CC:DD:EE:42" ] = {
	mac = "AA:BB:CC:DD:EE:42", scope = "lan", host = 8, ip = "192.168.5.8",
	offered = false, expires = PCMod.Net.Now() + 3600,
}
local dropped = PCMod.DHCPServer.Reflow( router, "lan" )
assertEq( #dropped, 1, "lease dropped when the pool is full" )
assertEq( dropped[ 1 ].mac, "AA:BB:CC:DD:EE:42", "the out-of-range lease is the one dropped" )
assertNil( rc.Leases[ "AA:BB:CC:DD:EE:42" ], "dropped lease is removed" )

-- A static reservation stays pinned even if the dynamic pool shrinks below it.
rc.Leases[ "AA:BB:CC:DD:EE:43" ] = {
	mac = "AA:BB:CC:DD:EE:43", scope = "lan", host = 7, ip = "192.168.5.7",
	offered = false, static = true, expires = PCMod.Net.Now() + 3600,
}
PCMod.DHCPServer.Reflow( router, "lan" )
assertEq( rc.Leases[ "AA:BB:CC:DD:EE:43" ].host, 7, "static reservation is not reflowed" )

print( "mock_dhcp PASSED" )
