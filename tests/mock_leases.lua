-- Router DHCP leases and /16-/24 host encoding (plain Lua after translation).
PCMod = {
    Msg = function() end,
    Cfg = { MaxNetworkPid = 500, MaxNetworkPass = 10, WirelessRange = 0, LanNetmask = 24, DHCPStart = 2, DHCPEnd = 5 },
    Network = { Packets = {} },
    DeriveDriver = function() return {} end,
}
math.Clamp = function( v, a, b ) if (v < a) then return a end if (v > b) then return b end return v end
function istable( v ) return type( v ) == "table" end
CurTime = CurTime or function() return 0 end

dofile( "pcmod_sh_common.lua" )
dofile( "pcmod_sh_dhcp.lua" )
dofile( "pcmod_sh_netproto.lua" )
dofile( "pcmod_sh_dhcp_server.lua" )
dofile( "pcmod_sh_dhcp_client.lua" )
dofile( "pcmod_sh_arp.lua" )
dofile( "pcmod_sh_routing.lua" )
dofile( "pcmod_drv_router.lua" )

local function assertEq( a, b, m )
    if (a ~= b) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end
local function assertTrue( v, m )
    if (not v) then error( "FAILED: " .. m, 2 ) end
end

local routData = { IP = { UpBB = 3, LanID = 5 } }
local routerEnt = {}
function routerEnt:Data() return routData end
function routerEnt:GetClass() return "pcmod_router" end
function routerEnt:GetBSubnet() return 3 end
function routerEnt:EntIndex() return 1 end
// The real entity re-syncs its address text here; the mock just records it.
function routerEnt:SetSubnet( s ) routData.IP.Sub = s end
function routerEnt:SetIP( h ) routData.IP.Add = h end
DRV.Entity = routerEnt

local function mkPC( idx )
    local o = { idx = idx, sub = false, ip = false, upbb = false, lanid = false, extras = {} }
    o.ipdata = { Extra = o.extras }
    function o:IsValid() return true end
    function o:EntIndex() return self.idx end
    function o:Data() return { IP = self.ipdata } end
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
    function o:AddExtraIP( addr, ub, lid, r )
        for _, ex in ipairs( self.extras ) do
            if (ex.IPv4 == addr) then return ex end
        end
        local ex = { IPv4 = addr, UpBB = ub or 0, LanID = lid or 0, Router = r }
        self.extras[ #self.extras + 1 ] = ex
        return ex
    end
    function o:ReleaseExtraIP( addr )
        for i, ex in ipairs( self.extras ) do
            if (ex.IPv4 == addr) then table.remove( self.extras, i ) return true end
        end
        return false
    end
    function o:UpdateExtraIPRouter( r, ub, lid )
        for _, ex in ipairs( self.extras ) do
            if (ex.Router == r) then ex.UpBB = ub or 0 ex.LanID = lid or 0 end
        end
    end
    return o
end

-- /24: hosts 2..5 from a 5-wide pool, then exhausted.
local pcs = {}
for i = 1, 4 do
    pcs[ i ] = mkPC( i )
    assertEq( DRV:AssignLease( pcs[ i ] ), i + 1, "lease " .. i )
end
assertEq( pcs[ 1 ].sub, 0, "private /24 subnet octet is 0" )
assertEq( pcs[ 1 ].ip, 2, "first /24 host" )
assertEq( pcs[ 1 ].upbb, 3, "upstream backbone propagated" )
assertEq( pcs[ 1 ].lanid, 5, "LAN /64 id propagated" )

assertEq( DRV:AssignLease( mkPC( 10 ) ), nil, "pool exhausted" )

-- Releasing a lease returns the host to the pool.
DRV:ReleaseLease( pcs[ 2 ] )
assertEq( DRV:AssignLease( mkPC( 20 ) ), 3, "released lease reused" )

-- The unified API drives the same LAN table.
DRV.Leases = {}
local direct = mkPC( 21 )
assertEq( DRV:AssignDHCP( "lan", direct ), 2, "unified LAN assignment" )
assertTrue( DRV:HasDHCPLease( "lan", direct ), "unified LAN lookup" )
assertEq( DRV:ReleaseDHCP( "lan", direct ), 2, "unified LAN release" )

-- /16: the host spans the third and fourth octets.
PCMod.Cfg.LanNetmask = 16
PCMod.Cfg.DHCPStart = 300
PCMod.Cfg.DHCPEnd = 300
routData.RouterCfg = {}
DRV.Leases = {}
local big = mkPC( 30 )
assertEq( DRV:AssignLease( big ), 300, "host 300 from a /16 pool" )
assertEq( big.sub, 1, "/16 host 300 -> third octet 1" )
assertEq( big.ip, 44, "/16 host 300 -> fourth octet 44" )

-- A PC with a configured static IP keeps it: the lease slot is still reserved
-- (so it counts against the pool) but the address itself is not overwritten.
local function mkStaticPC( idx, addr )
    local o = mkPC( idx )
    function o:Data() return { IP = { Static = addr } } end
    return o
end
PCMod.Cfg.LanNetmask = 24
PCMod.Cfg.DHCPStart = 2
PCMod.Cfg.DHCPEnd = 5
routData.RouterCfg = {}
DRV.Leases = {}
local stat = mkStaticPC( 40, "192.168.5.7" )
stat:SetSubnet( 5 )
stat:SetIP( 7 )
assertEq( DRV:AssignLease( stat ), 2, "static PC still reserves a lease slot" )
assertEq( stat.sub, 5, "static PC keeps its subnet" )
assertEq( stat.ip, 7, "static PC keeps its host" )
assertEq( stat.upbb, 3, "static PC still gets backbone info" )
DRV:ReleaseLease( stat )
assertEq( stat.sub, 5, "static subnet survives lease release" )
assertEq( stat.ip, 7, "static address survives lease release" )

-- A wired laptop joining Wi-Fi only registers the association; addressing is
-- DHCP's job and the wired lease is untouched.
DRV.Leases = {}
DRV.WirelessClients = {}
DRV.LAN = {}
local lap = mkPC( 50 )
function lap:GetMAC() return "AA:BB:CC:DD:EE:50" end
DRV.LAN[ 1 ] = { Connected = true, ConEnt = lap }
assertEq( DRV:AssignLease( lap ), 2, "wired lease" )
assertEq( lap.ip, 2, "wired address" )
assertEq( lap.ipdata.Router, 1, "primary lease owner recorded" )
assertTrue( DRV:AddWirelessClient( lap ), "wired client joins wi-fi" )
assertTrue( DRV:HasWirelessClient( lap ), "association is recorded" )
assertEq( lap.ip, 2, "joining wi-fi leaves the wired address alone" )
DRV:RemoveWirelessClient( lap )
assertTrue( DRV.Leases[ 2 ] == lap, "wired client keeps its lease after leaving wi-fi" )
assertEq( lap.ip, 2, "wired client keeps its address after leaving wi-fi" )

-- A pure Wi-Fi client's DHCP lease is released when it disconnects.
DRV.LAN[ 1 ] = nil
local air = mkPC( 51 )
function air:GetMAC() return "AA:BB:CC:DD:EE:51" end
local airCfg = PCMod.DHCPServer.Cfg( DRV )
airCfg.Leases[ "AA:BB:CC:DD:EE:51" ] = {
    mac = "AA:BB:CC:DD:EE:51", scope = "lan", host = 3,
    ip = "192.168.0.3", expires = PCMod.Net.Now() + 3600,
}
air:SetSubnet( 0 )
air:SetIP( 3 )
air.ipdata.Router = 1
assertTrue( DRV:AddWirelessClient( air ), "wi-fi-only client joins" )
DRV:RemoveWirelessClient( air )
assertTrue( airCfg.Leases[ "AA:BB:CC:DD:EE:51" ] == nil, "wi-fi-only lease released" )
assertEq( air.ip, false, "wi-fi-only address cleared" )

-- A device already leased on ANOTHER router gets a SECONDARY address here;
-- leaving our Wi-Fi removes only that secondary, its primary stays intact.
local roam = mkPC( 52 )
function roam:GetMAC() return "AA:BB:CC:DD:EE:52" end
roam:SetSubnet( 0 )
roam:SetIP( 9 )
roam.ipdata.Router = 777
airCfg.Leases[ "AA:BB:CC:DD:EE:52" ] = {
    mac = "AA:BB:CC:DD:EE:52", scope = "lan", host = 3,
    ip = "192.168.0.3", expires = PCMod.Net.Now() + 3600,
}
roam:AddExtraIP( "192.168.0.3", 3, 5, 1 )
assertTrue( DRV:AddWirelessClient( roam ), "roaming client joins" )
assertEq( roam.ip, 9, "roaming client keeps its primary address" )
assertEq( #roam.extras, 1, "roaming client keeps its secondary address" )
DRV:RemoveWirelessClient( roam )
assertTrue( airCfg.Leases[ "AA:BB:CC:DD:EE:52" ] == nil, "roaming lease bookkeeping dropped" )
assertEq( #roam.extras, 0, "roaming secondary address removed" )
assertEq( roam.ip, 9, "roaming primary address untouched" )

-- Netmask + third octet settings renumber existing leases onto the new
-- network, and the pool is clamped to the selected mask.
DRV.Leases = {}
DRV.WirelessClients = {}
DRV.LAN = {}
routData.RouterCfg = {}
PCMod.Cfg.LanNetmask = 24
PCMod.Cfg.DHCPStart = 2
PCMod.Cfg.DHCPEnd = 254
local nm = mkPC( 60 )
assertEq( DRV:AssignLease( nm ), 2, "lease on the default /24 network" )
assertEq( nm.sub, 0, "default third octet is 0" )
assertEq( nm.ip, 2, "default /24 host" )
DRV:SetLanNet( 7 )
assertEq( routData.RouterCfg.LanNet, 7, "third octet stored" )
assertEq( nm.sub, 7, "lease renumbered onto 192.168.7.0/24" )
assertEq( nm.ip, 2, "host id kept while renumbering" )
assertEq( DRV:GetLanPrefix(), "192.168.7.0/24", "LAN prefix reports the third octet" )
assertEq( DRV:GetLanNetmask(), 24, "netmask getter" )

DRV:SetLanNetmask( 16 )
assertEq( DRV:GetLanNetmask(), 16, "netmask switched to /16" )
assertEq( DRV:GetLanPrefix(), "192.168.0.0/16", "/16 prefix" )
routData.RouterCfg.DHCPStart = 300
routData.RouterCfg.DHCPEnd = 300
DRV:ReleaseLease( nm )
assertEq( DRV:AssignLease( nm ), 300, "lease from a /16 pool" )
assertEq( nm.sub, 1, "/16 host 300 -> third octet 1" )
assertEq( nm.ip, 44, "/16 host 300 -> fourth octet 44" )

-- Switching back to /24 clamps the pool and renumbers the leases.
routData.RouterCfg.DHCPStart = 2
routData.RouterCfg.DHCPEnd = 65534
DRV:SetLanNetmask( 24 )
assertEq( routData.RouterCfg.DHCPStart, 2, "pool start kept in /24 range" )
assertEq( routData.RouterCfg.DHCPEnd, 254, "pool end clamped into /24 range" )
assertEq( nm.sub, 7, "lease renumbered back onto the /24 network" )
assertEq( nm.ip, 2, "renumbered host id" )
assertEq( DRV:GetLanNet(), 7, "third octet kept while changing mask" )

-- Arbitrary masks in 16-32. /25 halves the block, /20 spans several /24s and
-- /30 leaves exactly one client address.
routData.RouterCfg = {}
DRV.Leases = {}
PCMod.Cfg.LanNetmask = 24
DRV:SetLanNetmask( 25 )
assertEq( DRV:GetLanNetmask(), 25, "/25 getter" )
assertEq( DRV:GetLanPrefix(), "192.168.0.0/25", "/25 prefix" )
assertEq( DRV:PoolMax(), 126, "/25 last host" )
routData.RouterCfg.DHCPStart = 2
routData.RouterCfg.DHCPEnd = 254
DRV:ClampDHCPPool()
assertEq( routData.RouterCfg.DHCPEnd, 126, "/25 pool clamps to the block" )
local m25 = mkPC( 70 )
assertEq( DRV:AssignLease( m25 ), 2, "/25 first lease" )
assertEq( m25.sub, 0, "/25 third octet" )
assertEq( m25.ip, 2, "/25 fourth octet" )

DRV.Leases = {}
routData.RouterCfg.DHCPStart = 2
routData.RouterCfg.DHCPEnd = 300
DRV:SetLanNetmask( 20 )
assertEq( DRV:GetLanNetmask(), 20, "/20 getter" )
assertEq( DRV:GetLanPrefix(), "192.168.0.0/20", "/20 prefix" )
assertEq( DRV:PoolMax(), 4094, "/20 last host" )
assertEq( routData.RouterCfg.DHCPEnd, 300, "/20 keeps a large pool" )
local m20 = mkPC( 71 )
assertEq( DRV:AssignLease( m20 ), 2, "/20 first lease" )
assertEq( m20.sub, 0, "/20 low third octet" )
assertEq( m20.ip, 2, "/20 low fourth octet" )

DRV.Leases = {}
routData.RouterCfg.DHCPStart = 2
routData.RouterCfg.DHCPEnd = 300
DRV:SetLanNetmask( 30 )
assertEq( DRV:GetLanNetmask(), 30, "/30 getter" )
assertEq( DRV:GetLanPrefix(), "192.168.0.0/30", "/30 prefix" )
assertEq( DRV:PoolMax(), 2, "/30 single client id" )
assertEq( routData.RouterCfg.DHCPEnd, 2, "/30 pool clamps to one client" )
local m30 = mkPC( 72 )
local m30b = mkPC( 73 )
assertEq( DRV:AssignLease( m30 ), 2, "/30 first lease" )
assertEq( m30.ip, 2, "/30 client address" )
assertEq( DRV:AssignLease( m30b ), nil, "/30 pool exhausted" )

-- Renew picks the scope from the attachment: a LAN client renews a LAN lease,
-- while a device that is not on a LAN interface must not be given one.
DRV.Leases = {}
DRV.WirelessClients = {}
DRV.LAN = {}
routData.RouterCfg = {}
PCMod.Cfg.LanNetmask = 24
PCMod.Cfg.DHCPStart = 2
PCMod.Cfg.DHCPEnd = 254
local renewClient = mkPC( 74 )
DRV.LAN[ 1 ] = { Connected = true, ConEnt = renewClient }
assertEq( DRV:RenewLease( renewClient ), 2, "LAN client renews a LAN lease" )
assertTrue( DRV:HasDHCPLease( "lan", renewClient ), "renewed client keeps a LAN lease" )
local stray = mkPC( 75 )
assertEq( DRV:RenewLease( stray ), nil, "non-LAN device gets no LAN lease" )
assertTrue( not DRV:HasDHCPLease( "lan", stray ), "non-LAN device is not added to the LAN table" )

print( "ALL LEASE TESTS PASSED" )