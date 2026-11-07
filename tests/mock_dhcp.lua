-- Direct tests for the extracted DHCP/IP mechanics (pcmod/sh_dhcp.lua).
-- The module is exercised without loading the router driver.
PCMod = {
	Msg = function() end,
	Warning = function() end,
	Cfg = { MaxNetworkPid = 500, MaxNetworkPass = 10, WirelessRange = 0, LanNetmask = 24, DHCPStart = 2, DHCPEnd = 254 },
	Network = { Packets = {} },
	DeriveDriver = function() return {} end,
}
math.Clamp = function( v, a, b ) if (v < a) then return a end if (v > b) then return b end return v end
function string.Trim( s )
	return (string.gsub( s, "^%s*(.-)%s*$", "%1" ))
end

dofile( "pcmod_sh_common.lua" )
dofile( "pcmod_sh_dhcp.lua" )

local function assertEq( a, b, m )
	if (a != b) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end
local function assertTrue( v, m )
	if (!v) then error( "FAILED: " .. m, 2 ) end
end

-- Minimal router interface used by PCMod.DHCP. LAN base is 192.168.5.0/24,
-- backbone is 10.0.7.0/24.
local routData = {
	IP = { UpBB = 3, LanID = 5 },
	RouterCfg = { DHCPStart = 2, DHCPEnd = 10, WanDHCPStart = 12, WanDHCPEnd = 20 },
}
local rent = {}
function rent:GetBSubnet() return 7 end
function rent:GetClass() return "pcmod_brouter" end
function rent:EntIndex() return 1 end
function rent:Data() return routData end

local router = { Entity = rent, Leases = {}, BLeases = {}, BLeasePort = {} }
function router:GetCfg() return routData.RouterCfg end
function router:LanBlockSize() return 256 end
function router:GetLanBase() return 5 * 256 end
function router:ComputeLanBase() return 5 * 256 end
function router:IsBackbone() return true end

local function mkPC( idx, mac )
	local o = { idx = idx, mac = mac, ipdata = { Extra = {}, LAN = false, WAN = false } }
	function o:IsValid() return true end
	function o:EntIndex() return self.idx end
	function o:GetMAC() return self.mac end
	function o:Data() return { IP = self.ipdata } end
	function o:SetLanAddress( addr ) self.ipdata.LAN = addr end
	function o:SetSubnet( s )
		self.sub = s
		if (s == false) then self.ipdata.LAN = false
		else self.ipdata.LAN = "192.168." .. tostring( s ) .. "." .. tostring( self.ip or 1 ) end
	end
	function o:SetIP( h )
		self.ip = h
		if (h == false) then self.ipdata.LAN = false
		else self.ipdata.LAN = "192.168." .. tostring( self.sub or 0 ) .. "." .. tostring( h ) end
	end
	function o:SetUpBB( b ) self.upbb = b end
	function o:SetLanID( n ) self.lanid = n end
	function o:SetBSubnet( b ) self.ipdata.WanBB = b end
	function o:SetBIP( h ) self.ipdata.WanHost = h end
	function o:GetBSubnet() return self.ipdata.WanBB end
	function o:AddExtraIP( addr, ub, lid, r )
		self.ipdata.Extra[ #self.ipdata.Extra + 1 ] = { IPv4 = addr, UpBB = ub, LanID = lid, Router = r }
	end
	function o:ReleaseExtraIP( addr )
		for i, ex in ipairs( self.ipdata.Extra ) do
			if (ex.IPv4 == addr) then table.remove( self.ipdata.Extra, i ) return true end
		end
		return false
	end
	return o
end

-- LAN scope: same pool mechanics, private address.
local lan = mkPC( 10 )
assertEq( PCMod.DHCP.Assign( router, "lan", lan ), 2, "LAN lease host" )
assertEq( lan.ipdata.LAN, "192.168.5.2", "LAN lease address" )
assertTrue( PCMod.DHCP.Has( router, "lan", lan ), "LAN lease visible through the module" )
assertEq( PCMod.DHCP.LeaseHost( router, "lan", lan ), 2, "LAN lease lookup" )
local first, last = PCMod.DHCP.PoolRange( router, "lan" )
assertEq( first, "192.168.5.2", "LAN pool first address" )
assertEq( last, "192.168.5.10", "LAN pool last address" )

-- WAN scope: same allocator, 10.x host.
local wan = mkPC( 11 )
assertEq( PCMod.DHCP.Assign( router, "wan", wan ), 12, "WAN lease host" )
assertEq( wan.ipdata.WanBB, 7, "WAN lease backbone id" )
assertEq( wan.ipdata.WanHost, 11, "WAN lease host slot" )
assertEq( wan.ipdata.LAN, false, "WAN lease clears the private address" )
assertTrue( router.BLeasePort[ 11 ] == nil, "port is optional for a WAN lease" )
local wfirst, wlast = PCMod.DHCP.PoolRange( router, "wan" )
assertEq( wfirst, "10.0.7.12", "WAN pool first address" )
assertEq( wlast, "10.0.7.20", "WAN pool last address" )

-- Static IP <-> MAC reservation wins over the dynamic pool.
assertTrue( PCMod.DHCP.AddStaticLease( router, "10.0.7.20", "AA:BB:CC:DD:EE:20" ), "static lease stored" )
local pinned = mkPC( 12, "AA:BB:CC:DD:EE:20" )
assertEq( PCMod.DHCP.Assign( router, "wan", pinned, 4 ), 20, "pinned MAC gets its reservation" )
assertEq( pinned.ipdata.WanHost, 19, "pinned host slot" )
assertEq( router.BLeasePort[ 12 ], 4, "WAN lease records its port" )

-- The dynamic pool skips a reserved host.
router.BLeases = {}
assertTrue( PCMod.DHCP.AddStaticLease( router, "10.0.7.12", "AA:BB:CC:DD:EE:12" ), "second reservation stored" )
local dyn = mkPC( 13, "AA:BB:CC:DD:EE:99" )
assertEq( PCMod.DHCP.Assign( router, "wan", dyn ), 13, "dynamic lease skips pinned host 12" )

-- Releasing returns the host and clears the WAN address.
assertEq( PCMod.DHCP.Release( router, "wan", dyn ), 13, "WAN release host" )
assertTrue( dyn.ipdata.WanBB == false, "WAN id cleared on release" )

-- Port cleanup drops the leases behind that port.
router.BLeases = {}
router.BLeasePort = {}
local p1 = mkPC( 14, "AA:BB:CC:DD:EE:14" )
PCMod.DHCP.Assign( router, "wan", p1, 3 )
assertTrue( router.BLeases[ 13 ] == p1, "lease before port cleanup" )
PCMod.DHCP.ReleaseOnPort( router, "wan", 3 )
assertTrue( router.BLeases[ 13 ] == nil, "port cleanup released the lease" )
assertTrue( p1.ipdata.WanBB == false, "port cleanup cleared the address" )

print( "mock_dhcp PASSED" )
