-- Hardcoded cable attachment points: port order, click snapping, fallbacks.
-- Expected coordinates come from the anchor table itself, so re-measuring a
-- model never breaks the mapping tests.
PCMod = {}
function Vector( x, y, z ) return { x = x, y = y, z = z } end

dofile( "pcmod_sh_portanchors.lua" )

local anchors = PCMod.PortAnchors

local function assertEq( a, b, m )
	if (a ~= b) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end
local function assertTrue( v, m )
	if (not v) then error( "FAILED: " .. m, 2 ) end
end
local function nearAnchor( v, a, m )
	local ok = (v != nil) && (math.abs( v.x - a[ 1 ] ) < 0.001) && (math.abs( v.y - a[ 2 ] ) < 0.001) && (math.abs( v.z - a[ 3 ] ) < 0.001)
	if (not ok) then
		error( "FAILED: " .. m .. " (got " .. tostring( v and v.x ) .. "," .. tostring( v and v.y ) .. "," .. tostring( v and v.z ) .. ")", 2 )
	end
end
local function anchor( model, i )
	return anchors.Models[ model ][ i ]
end

local function makeEnt( model, class, nports )
	local e = { Model = model, Class = class, PortCount = nports or 0 }
	function e:GetModel() return self.Model end
	function e:GetClass() return self.Class end
	function e:Ports()
		local p = {}
		for i = 1, self.PortCount do p[ i ] = { Type = "network" } end
		return p
	end
	return e
end

local HDD = "models/props_lab/harddrive02.mdl"
local CASE = "models/props/cs_office/computer_case.mdl"
local EEEPC = "models/pcmod/eeepc.mdl"
local RECD = "models/props_lab/reciever01d.mdl"
local WRT = "models/pcmod/wrt54g.mdl"
local RECA = "models/props_lab/reciever01a.mdl"

-- The two tower models map their seven logical ports onto the measured ones.
local tower = makeEnt( HDD, "pcmod_tower", 7 )
nearAnchor( anchors.Get( tower, 1 ), anchor( HDD, 1 ), "tower port 1 is VGA" )
nearAnchor( anchors.Get( tower, 2 ), anchor( HDD, 2 ), "tower port 2 is PS/2" )
nearAnchor( anchors.Get( tower, 3 ), anchor( HDD, 3 ), "tower port 3 is eth 1" )
nearAnchor( anchors.Get( tower, 4 ), anchor( HDD, 4 ), "tower port 4 is eth 2" )
nearAnchor( anchors.Get( tower, 5 ), anchor( HDD, 5 ), "tower port 5 is USB 1" )
nearAnchor( anchors.Get( tower, 7 ), anchor( HDD, 7 ), "tower port 7 is the mini jack" )

local office = makeEnt( CASE, "pcmod_tower", 7 )
nearAnchor( anchors.Get( office, 1 ), anchor( CASE, 4 ), "office tower port 1 is VGA" )
nearAnchor( anchors.Get( office, 2 ), anchor( CASE, 1 ), "office tower port 2 is PS/2" )
nearAnchor( anchors.Get( office, 3 ), anchor( CASE, 5 ), "office tower port 3 is eth 1" )
nearAnchor( anchors.Get( office, 4 ), anchor( CASE, 6 ), "office tower port 4 is eth 2" )
nearAnchor( anchors.Get( office, 5 ), anchor( CASE, 2 ), "office tower port 5 is USB 1" )

-- Laptop: network, USB, minijack.
local laptop = makeEnt( EEEPC, "pcmod_laptop", 3 )
nearAnchor( anchors.Get( laptop, 1 ), anchor( EEEPC, 1 ), "laptop network port" )
nearAnchor( anchors.Get( laptop, 2 ), anchor( EEEPC, 3 ), "laptop USB port" )
nearAnchor( anchors.Get( laptop, 3 ), anchor( EEEPC, 6 ), "laptop minijack port" )

-- I/O device uses the measured back port, not the front knobs.
local io = makeEnt( RECD, "pcmod_iodevice", 1 )
nearAnchor( anchors.Get( io, 1 ), anchor( RECD, 9 ), "I/O device uses its back port" )

-- A model with exactly as many anchors as ports maps one-to-one.
local router = makeEnt( WRT, "pcmod_router", 5 )
nearAnchor( anchors.Get( router, 1 ), anchor( WRT, 1 ), "wrt54g WAN is port 1" )
nearAnchor( anchors.Get( router, 5 ), anchor( WRT, 5 ), "wrt54g last LAN is port 5" )

-- Unknown model: no anchor, callers keep the raw click.
assertTrue( anchors.Get( makeEnt( "models/unknown.mdl", "pcmod_tower", 7 ), 1 ) == nil, "unknown model has no anchor" )
assertTrue( anchors.Snap( makeEnt( "models/unknown.mdl", "pcmod_tower", 7 ), { x = 0, y = 0, z = 0 } ) == nil, "unknown model does not snap" )

-- Single-anchor models snap from anywhere on the model.
local MON = "models/props_lab/monitor01a.mdl"
local monitor = makeEnt( MON, "pcmod_monitor", 1 )
nearAnchor( anchors.Snap( monitor, { x = 500, y = 500, z = 500 } ), anchor( MON, 1 ), "monitor snaps to its only port" )

-- Multi-anchor models snap only within range of a measured connector.
local switch = makeEnt( RECA, "pcmod_switch", 8 )
assertTrue( anchors.Get( switch, 1 ) == nil, "an ambiguous model has no fixed order" )
local target = anchor( RECA, 5 )
local hit = anchors.Snap( switch, { x = target[ 1 ] + 0.1, y = target[ 2 ], z = target[ 3 ] } )
nearAnchor( hit, target, "a nearby click snaps to the closest connector" )
assertTrue( anchors.Snap( switch, { x = -100, y = -100, z = -100 } ) == nil, "a distant click is left alone" )

-- Resolve prefers the fixed port, then the nearest connector.
nearAnchor( anchors.Resolve( tower, 4, { x = 0, y = 0, z = 0 } ), anchor( HDD, 4 ), "resolve uses the fixed port order" )
nearAnchor( anchors.Resolve( switch, 1, { x = target[ 1 ] + 0.1, y = target[ 2 ], z = target[ 3 ] } ), target, "resolve falls back to nearest connector" )

print( "ALL PORTANCHOR TESTS PASSED" )
