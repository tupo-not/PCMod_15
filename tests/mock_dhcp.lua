-- DHCP allocation on a LAN subnet: distinct leases, pool exhaustion -> IPv6-only.
PCMod = {
    Msg = function() end,
    Warning = function() end,
    Notice = function() end,
    Cfg = { MaxNetworkPid = 500, DHCPStart = 2, DHCPEnd = 5 },
}
dofile( "pcmod_network.lua" )

local net = PCMod.Network
net.Subnets[ 5 ] = {} -- an existing LAN router record

local function assertEq( a, b, m )
    if (a ~= b) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end
local function assertTrue( v, m )
    if (not v) then error( "FAILED: " .. m, 2 ) end
end

local function mkEnt( idx )
    local o = { idx = idx, sub = false, ip = false }
    function o:EntIndex() return self.idx end
    function o:SetSubnet( s ) self.sub = s end
    function o:SetIP( h ) self.ip = h end
    return o
end

local clients = {}
for i = 1, 4 do
    local e = mkEnt( i )
    clients[ i ] = e
    assertEq( net.RegisterPC( e, 5, false ), "assigned", "client " .. i .. " gets a lease" )
end
assertEq( clients[ 1 ].ip, 2, "first lease is .2" )
assertEq( clients[ 4 ].ip, 5, "fourth lease is .5" )

-- Pool is full: the next client is admitted but gets no IPv4 lease.
local fifth = mkEnt( 10 )
assertEq( net.RegisterPC( fifth, 5, false ), "full", "5th client is IPv6-only" )
assertTrue( fifth.ip == false, "IPv6-only client has no IPv4" )
assertTrue( fifth.sub == false, "IPv6-only client has no subnet" )

-- Already-registered clients are not double-counted.
assertEq( net.RegisterPC( clients[ 1 ], 5, false ), "exists", "duplicate rejected" )

-- Releasing a lease returns it to the pool (smallest free is reused).
net.UnRegisterPC( clients[ 2 ], 5, false )
local reuse = mkEnt( 20 )
assertEq( net.RegisterPC( reuse, 5, false ), "assigned", "lease reused" )
assertEq( reuse.ip, 3, "smallest freed lease (.3) reused" )

-- Unknown subnets are rejected outright.
assertEq( net.RegisterPC( mkEnt( 30 ), 99, false ), "invalid", "unknown subnet rejected" )

print( "ALL DHCP TESTS PASSED" )