// ---------------------------------------------------------------------------------------------------------
// sh_latency.lua - emulated link latency and Wi-Fi packet loss
//
// Every frame crosses one or more links. Each link adds a configurable delay
// (with jitter); wireless links add more delay and may drop the frame. The
// simulation runs server-side and is intentionally small: a queue-free model
// built on timer.Simple, so the normal synchronous path stays intact when the
// timer library is unavailable (tests, early startup).
// ---------------------------------------------------------------------------------------------------------

PCMod = PCMod or {}
PCMod.Latency = PCMod.Latency or {}

local Latency = PCMod.Latency

local function cfgValue( key, default )
	local c = PCMod.Cfg
	if ((!c) || (c[ key ] == nil)) then return default end
	return c[ key ]
end

local function randFloat( lo, hi )
	if (math.Rand) then return math.Rand( lo, hi ) end
	return lo + (math.random() * (hi - lo))
end

// Latency is on by default; setting cfg.NetLatency = false makes every link
// instant again (useful for debugging).
function Latency.Enabled()
	return cfgValue( "NetLatency", true ) != false
end

// Base delay and jitter in milliseconds for a link kind: "wireless", "optic"
// or "wired".
function Latency.Profile( kind )
	if (kind == "wireless") then
		return tonumber( cfgValue( "WirelessLatency", 12 ) ) or 12,
			tonumber( cfgValue( "WirelessJitter", 6 ) ) or 6
	elseif (kind == "optic") then
		return tonumber( cfgValue( "OpticLatency", 1 ) ) or 1,
			tonumber( cfgValue( "LatencyJitter", 1 ) ) or 1
	end
	return tonumber( cfgValue( "WiredLatency", 1 ) ) or 1,
		tonumber( cfgValue( "LatencyJitter", 1 ) ) or 1
end

// 0 at the AP, 1 at the edge of its range. Unlimited range (or an unknown
// position) keeps the base profile.
function Latency.WirelessRatio( distance, range )
	local r = tonumber( range ) or 0
	local d = tonumber( distance )
	if ((r <= 0) || (!d)) then return 0 end
	local ratio = d / r
	if (ratio < 0) then return 0 end
	if (ratio > 1) then return 1 end
	return ratio
end

// Distance between two entities when both expose a position.
function Latency.DistanceBetween( a, b )
	if ((!a) || (!b) || (!a.GetPos) || (!b.GetPos)) then return nil end
	local ok, posA = pcall( function() return a:GetPos() end )
	local ok2, posB = pcall( function() return b:GetPos() end )
	if ((!ok) || (!ok2) || (!posA) || (!posB)) then return nil end
	local ok3, len = pcall( function() return (posA - posB):Length() end )
	if ((!ok3) || (!len)) then return nil end
	return len
end

// Emulated one-way delay for a link, in milliseconds. Wireless links get
// slower toward the edge of the AP's range.
function Latency.Delay( kind, distance, range )
	if (!Latency.Enabled()) then return 0 end
	local base, jitter = Latency.Profile( kind )
	if (kind == "wireless") then
		local ratio = Latency.WirelessRatio( distance, range )
		base = base + (ratio * (tonumber( cfgValue( "WirelessDistanceLatency", 25 ) ) or 25))
		jitter = jitter + (ratio * (tonumber( cfgValue( "WirelessDistanceJitter", 5 ) ) or 5))
	end
	local ms = base
	if ((jitter) && (jitter > 0)) then ms = ms + randFloat( -jitter, jitter ) end
	if (ms < 0) then ms = 0 end
	return ms
end

// Wi-Fi is lossy, and more so at the edge of range; wired and fibre links are
// lossless.
function Latency.Dropped( kind, distance, range )
	if ((!Latency.Enabled()) || (kind != "wireless")) then return false end
	local loss = tonumber( cfgValue( "WirelessLoss", 0.02 ) ) or 0
	loss = loss + (Latency.WirelessRatio( distance, range ) * (tonumber( cfgValue( "WirelessDistanceLoss", 0.10 ) ) or 0.10))
	if (loss <= 0) then return false end
	if (loss >= 1) then return true end
	return randFloat( 0, 1 ) < loss
end

// Link kind for a physical port table. Only network/fibre links are simulated;
// VGA, USB, audio and PS/2 ports stay instant so input and sound feel normal.
function Latency.KindForPort( port )
	if (!istable( port )) then return nil end
	if (port.Type == "optic") then return "optic" end
	if (port.Type == "network") then return "wired" end
	return nil
end

// Deliver one frame after the emulated delay. Returns false when the frame
// was dropped, true when it was scheduled (or delivered immediately).
function Latency.Deliver( fn, kind, distance, range )
	if (type( fn ) != "function") then return false end
	if (Latency.Dropped( kind, distance, range )) then return false end
	local ms = Latency.Delay( kind, distance, range )
	if ((ms <= 0) || (!timer) || (!timer.Simple)) then
		fn()
		return true
	end
	timer.Simple( ms / 1000, fn )
	return true
end
