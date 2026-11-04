-- Router DHCP leases and /16-/24 host encoding (plain Lua after translation).
PCMod = {
    Msg = function() end,
    Cfg = { MaxNetworkPid = 500, MaxNetworkPass = 10, WirelessRange = 0, LanNetmask = 24, DHCPStart = 2, DHCPEnd = 5 },
    Network = { Packets = {} },
    DeriveDriver = function() return {} end,
}

dofile( "pcmod_sh_common.lua" )
dofile( "pcmod_drv_router.lua" )

local function assertEq( a, b, m )
    if (a ~= b) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end
local function assertTrue( v, m )
    if (not v) then error( "FAILED: " .. m, 2 ) end
end

local routerEnt = {}
function routerEnt:Data() return { IP = { UpBB = 3, LanID = 5 } } end
function routerEnt:GetClass() return "pcmod_router" end
function routerEnt:GetBSubnet() return 3 end
DRV.Entity = routerEnt

local function mkPC( idx )
    local o = { idx = idx, sub = false, ip = false, upbb = false, lanid = false }
    function o:IsValid() return true end
    function o:EntIndex() return self.idx end
    function o:SetSubnet( s ) self.sub = s end
    function o:SetIP( h ) self.ip = h end
    function o:SetUpBB( b ) self.upbb = b end
    function o:SetLanID( n ) self.lanid = n end
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

-- /16: the host spans the third and fourth octets.
PCMod.Cfg.LanNetmask = 16
PCMod.Cfg.DHCPStart = 300
PCMod.Cfg.DHCPEnd = 300
DRV.Leases = {}
local big = mkPC( 30 )
assertEq( DRV:AssignLease( big ), 300, "host 300 from a /16 pool" )
assertEq( big.sub, 1, "/16 host 300 -> third octet 1" )
assertEq( big.ip, 44, "/16 host 300 -> fourth octet 44" )

print( "ALL LEASE TESTS PASSED" )