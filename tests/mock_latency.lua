-- Link latency and Wi-Fi loss model.
function istable( v ) return type( v ) == "table" end
PCMod = { Cfg = {}, Msg = function() end }
dofile( "pcmod_sh_latency.lua" )

local function assertEq( a, b, msg )
	if (a != b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end

local function assertTrue( v, msg )
	if (not v) then error( "FAILED: " .. msg, 2 ) end
end

-- Deterministic jitter: the midpoint of the configured range.
local randValue = 0.5
function math.Rand( lo, hi ) return lo + ((hi - lo) * randValue) end

local L = PCMod.Latency
assertEq( L.Profile( "wired" ), 3, "wired base delay" )
assertEq( L.Delay( "wired" ), 3, "wired delay has no jitter at midpoint" )
assertEq( L.Delay( "optic" ), 2, "fibre delay" )
assertEq( L.Delay( "wireless" ), 12, "wireless delay at the AP" )
assertEq( L.WirelessRatio( 50, 100 ), 0.5, "distance ratio at half range" )
assertEq( L.Delay( "wireless", 50, 100 ), 24.5, "wireless delay grows with distance" )
assertEq( L.Delay( "wireless", 100, 100 ), 37, "wireless delay at the edge of range" )
assertEq( L.Delay( "wireless", 500, 100 ), 37, "distance is clamped to the range" )
assertEq( L.KindForPort( { Type = "optic" } ), "optic", "fibre port uses the optic profile" )
assertEq( L.KindForPort( { Type = "network" } ), "wired", "Ethernet port uses the wired profile" )
assertTrue( L.KindForPort( { Type = "vga" } ) == nil, "non-network ports are not simulated" )
assertTrue( L.KindForPort( nil ) == nil, "unknown port is not simulated" )

-- Loss only applies to Wi-Fi, and grows toward the edge of range.
PCMod.Cfg.WirelessLoss = 0.02
PCMod.Cfg.WirelessDistanceLoss = 0.10
randValue = 0.01
assertTrue( L.Dropped( "wireless" ), "a roll below the loss threshold drops a Wi-Fi frame" )
assertTrue( not L.Dropped( "wired" ), "wired frames are never dropped" )
assertTrue( not L.Dropped( "optic" ), "fibre frames are never dropped" )
randValue = 0.06
assertTrue( (not L.Dropped( "wireless", 0, 100 )), "near the AP the base loss applies" )
assertTrue( L.Dropped( "wireless", 50, 100 ), "at half range the distance loss applies" )
randValue = 0.5
assertTrue( not L.Dropped( "wireless" ), "a roll above the loss threshold is delivered" )

-- timer.Simple schedules the frame for the emulated delay.
local scheduled = {}
timer = {
	Simple = function( seconds, fn )
		table.insert( scheduled, { seconds = seconds, fn = fn } )
	end,
}
randValue = 0.5
local called = false
assertTrue( L.Deliver( function() called = true end, "wireless" ), "scheduled frame reports success" )
assertEq( #scheduled, 1, "one frame scheduled" )
assertTrue( not called, "frame is not delivered immediately" )
assertTrue( scheduled[ 1 ].seconds > 0.01, "wireless delay is applied in seconds" )
scheduled[ 1 ].fn()
assertTrue( called, "scheduled callback delivers the frame" )

-- Wired/fibre delays are sub-tick: they advance the delay chain of the current
-- dispatch and deliver in the same tick instead of waiting for timer.Simple.
PCMod.Cfg.WiredLatency = 3
PCMod.Cfg.OpticLatency = 2
PCMod.Cfg.LatencyJitter = 0
scheduled = {}
local wiredCalled = false
local wiredNow
local before = L.Now()
assertTrue( L.Deliver( function() wiredCalled = true; wiredNow = L.Now() end, "wired" ), "wired frame reports success" )
assertTrue( wiredCalled, "wired frame is delivered immediately" )
assertEq( #scheduled, 0, "wired frame does not use a timer" )
assertTrue( wiredNow > before, "wired frame advances the delay chain during dispatch" )
assertTrue( math.abs( L.Now() - before ) < 1e-9, "delay chain resets after the dispatch" )

-- Nested deliveries accumulate inside one dispatch, then reset together.
local nestedNow
local outer = L.Now()
assertTrue( L.Deliver( function()
	assertTrue( L.Deliver( function() nestedNow = L.Now() end, "optic" ), "nested fibre frame reports success" )
end, "wired" ), "outer wired frame reports success" )
assertTrue( nestedNow > outer + 0.004, "nested frame includes both link delays" )
assertTrue( math.abs( L.Now() - outer ) < 1e-9, "outer dispatch resets the chain" )

-- A large topology must not recurse once per hop. The iterative queue keeps
-- the whole dispatch in the same tick and does not defer to timers.
scheduled = {}
local deepDone = false
local function deep( n )
	if (n <= 0) then deepDone = true return end
	assertTrue( L.Deliver( function() deep( n - 1 ) end, "wired" ), "deep frame reports success" )
end
deep( 5000 )
assertTrue( deepDone, "5000-hop chain completes in one dispatch" )
assertEq( #scheduled, 0, "deep chain does not use timers" )
assertTrue( math.abs( L.Now() - outer ) < 1e-9, "deep dispatch resets the chain" )

-- A dropped frame is neither scheduled nor delivered.
scheduled = {}
called = false
randValue = 0.01
assertTrue( not L.Deliver( function() called = true end, "wireless" ), "dropped frame reports failure" )
assertEq( #scheduled, 0, "dropped frame is not scheduled" )
assertTrue( not called, "dropped frame is not delivered" )

-- Without the timer library the frame goes through immediately.
scheduled = {}
called = false
timer = nil
randValue = 0.5
assertTrue( L.Deliver( function() called = true end, "wired" ), "immediate frame reports success" )
assertTrue( called, "no-timer fallback delivers immediately" )

-- The whole simulation can be switched off.
timer = { Simple = function( seconds, fn ) table.insert( scheduled, { seconds = seconds, fn = fn } ) end }
PCMod.Cfg.NetLatency = false
scheduled = {}
called = false
assertTrue( L.Deliver( function() called = true end, "wireless" ), "disabled latency still delivers" )
assertTrue( called, "disabled latency is immediate" )
assertEq( #scheduled, 0, "disabled latency schedules nothing" )
PCMod.Cfg.NetLatency = true

print( "ALL LATENCY TESTS PASSED" )
