-- Backbone distance-vector routing: a 3-backbone path must route end-to-end.
PCMod = {
    Msg = function() end,
    Warning = function() end,
    Notice = function() end,
    DeriveSubsystem = function() return {} end,
    Data = {},
    Cfg = { MaxNetworkPid = 500, DHCPStart = 2, DHCPEnd = 254, LanNetmask = 24 },
}
dofile( "pcmod_network.lua" )
dofile( "pcmod_subsystem_router.lua" )

local function assertTrue( v, m )
    if (not v) then error( "FAILED: " .. m, 2 ) end
end
function istable( v ) return type( v ) == "table" end

local function makeBackbone( idx, bb )
    local o = { Idx = idx, BB = bb }
    function o:IsValid() return true end
    function o:EntIndex() return self.Idx end
    function o:GetClass() return "pcmod_brouter" end
    function o:GetBSubnet() return self.BB end
    return o
end

local b1, b2, b3 = makeBackbone( 11, 1 ), makeBackbone( 12, 2 ), makeBackbone( 13, 3 )

local function makeDrv( ent )
    local d = {}
    for k, v in pairs( SUBSYSTEM ) do d[ k ] = v end
    d.Entity = ent
    d.Neighbors = {}
    d.Routes = {}
    return d
end

local d1, d2, d3 = makeDrv( b1 ), makeDrv( b2 ), makeDrv( b3 )

-- Links: 1 -- 2 -- 3
d1.Neighbors[ 2 ] = { ConEnt = b2 }
d2.Neighbors[ 1 ] = { ConEnt = b1 }
d2.Neighbors[ 3 ] = { ConEnt = b3 }
d3.Neighbors[ 2 ] = { ConEnt = b2 }

PCMod.Data[ 11 ] = { Subsystems = { router = d1 } }
PCMod.Data[ 12 ] = { Subsystems = { router = d2 } }
PCMod.Data[ 13 ] = { Subsystems = { router = d3 } }
PCMod.Network.Backbones = { [1] = { Ent = b1 }, [2] = { Ent = b2 }, [3] = { Ent = b3 } }

PCMod.Network.Reconverge()

-- BB1 reaches BB3 through BB2.
assertTrue( d1.Routes[ 3 ] ~= nil, "BB1 has a route to /32 3" )
assertTrue( d1.Routes[ 3 ].via == 2, "BB1 routes /32 3 via BB2" )
assertTrue( d1:RouteForBB( 3 ) ~= nil, "BB1 resolves a next-hop port" )
assertTrue( d2.Routes[ 1 ].via == 1, "BB2 routes /32 1 via BB1" )
assertTrue( d2.Routes[ 3 ].via == 3, "BB2 routes /32 3 via BB3" )
assertTrue( d3.Routes[ 1 ].via == 2, "BB3 routes /32 1 via BB2" )

-- Removing the 2--3 link must drop multi-hop routes.
d2.Neighbors[ 3 ] = nil
d3.Neighbors[ 2 ] = nil
PCMod.Network.Reconverge()
assertTrue( d1.Routes[ 3 ] == nil, "BB1 loses the route to /32 3 after link removal" )
assertTrue( d1.Routes[ 2 ] ~= nil, "BB1 still routes to its direct neighbour /32 2" )

print( "ALL ROUTING TESTS PASSED" )