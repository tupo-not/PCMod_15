-- Packet id recycling must never overwrite an in-flight packet.
PCMod = {
    Msg = function() end,
    Cfg = { MaxNetworkPid = 3 },
    IPv6 = {
        ToIPv4 = function( addr ) return addr end,
        FromIPv4 = function() return nil end,
        GetPrefix = function() return nil end,
    },
}
function IsValid() return false end
dofile( "pcmod_network.lua" )

local function assertEq( a, b, m )
    if (a ~= b) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end
local function assertTrue( v, m )
    if (not v) then error( "FAILED: " .. m, 2 ) end
end

local net = PCMod.Network
assertEq( net.CreatePacket( 1, 2, 58, "one" ), 1, "first packet id" )
assertEq( net.CreatePacket( 1, 2, 58, "two" ), 2, "second packet id" )
assertEq( net.CreatePacket( 1, 2, 58, "three" ), 3, "third packet id" )
assertEq( net.FindFreePacketSlot( 3, 1 ), nil, "full in-flight table has no slot" )

local original = net.Packets[ 1 ]
assertEq( net.CreatePacket( 1, 2, 58, "overflow" ), nil, "overflow is backpressured" )
assertTrue( net.Packets[ 1 ] == original, "in-flight packet was not replaced" )
assertEq( net.Packets[ 1 ].Body, "one", "in-flight body preserved" )

net.Packets[ 2 ].Delivered = true
assertEq( net.CreatePacket( 1, 2, 58, "recycled" ), 2, "delivered slot is recycled" )
assertEq( net.Packets[ 2 ].Body, "recycled", "recycled slot holds new packet" )

net.Packets[ 1 ] = nil
assertEq( net.CreatePacket( 1, 2, 58, "free" ), 1, "empty slot is reused" )

print( "ALL NETWORK TESTS PASSED" )
