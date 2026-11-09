-- Entity look-at overlay: IPv4 + matching IPv6, no duplicate addresses.
function string.Trim( s )
	return (string.gsub( s, "^%s*(.-)%s*$", "%1" ))
end
function string.Left( s, n ) return string.sub( s, 1, n ) end
function string.Right( s, n ) return string.sub( s, math.max( 1, #s - n + 1 ) ) end
function string.Explode( sep, str )
	local out = {}
	if (str == nil) then return out end
	if (sep == "") then
		for i = 1, #str do table.insert( out, string.sub( str, i, i ) ) end
		return out
	end
	local start = 1
	while true do
		local a, b = string.find( str, sep, start, true )
		if (not a) then
			table.insert( out, string.sub( str, start ) )
			break
		end
		table.insert( out, string.sub( str, start, a - 1 ) )
		start = b + 1
	end
	return out
end
function string.Count( str, char )
	local r = 0
	for i = 1, #str do if (string.sub( str, i, i ) == char) then r = r + 1 end end
	return r
end
function table.Copy( t )
	if (type( t ) ~= "table") then return t end
	local o = {}
	for k, v in pairs( t ) do o[ k ] = table.Copy( v ) end
	return o
end
function table.HasValue( t, v )
	for _, x in pairs( t ) do if (x == v) then return true end end
	return false
end
function istable( v ) return type( v ) == "table" end

PCMod = {}
PCMod.Data = {}
PCMod.Msg = function() end
PCMod.Warning = function() end
PCMod.Cfg = {}
function AddCSLuaFile() end
function Color( r, g, b, a ) return { r = r, g = g, b = b, a = a } end

RENDERGROUP_OPAQUE = 0
SERVER = true
CLIENT = false

dofile( "pcmod_sh_common.lua" )

// The shared module redefines PCMod.Msg; use a no-op so the entity helpers can
// log without needing table.Count / the global Msg in the plain-Lua harness.
PCMod.Msg = function() end

// Load the entity with both halves available: the server half registers the
// address setters, the client half holds DrawInfo/GetOverlayAddresses.
CLIENT = true
ENT = {}
dofile( "pcmod_shared.lua" )

local function assertEq( a, b, msg )
	if (a ~= b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function assertList( got, want, msg )
	assertEq( #got, #want, msg .. " (count)" )
	for i = 1, #want do
		assertEq( got[ i ], want[ i ], msg .. " [line " .. i .. "]" )
	end
end

local nextIndex = 0
local function newEnt()
	nextIndex = nextIndex + 1
	local nw = {}
	local ent = setmetatable( {}, { __index = ENT } )
	local id = nextIndex
	function ent:EntIndex() return id end
	function ent:IsValid() return true end
	function ent:SetNWString( k, v ) nw[ k ] = v end
	function ent:GetNWString( k ) return nw[ k ] or "" end
	function ent:GetGVar() return false end
	function ent:Data() return PCMod.Data[ id ] end
	PCMod.Data[ id ] = {
		HardDrive = {},
		IP = {
			LAN = false, WAN = false, WanBB = false, WanHost = false,
			Extra = {}, V6 = false, WanV6 = false,
		},
	}
	return ent
end

-- A LAN PC/device: private IPv4 plus its emulated IPv6.
local pc = newEnt()
pc:SetSubnet( 0 )
pc:SetUpBB( 3 )
pc:SetLanID( 5 )
pc:SetIP( 2 )
assertList( pc:GetOverlayAddresses(), { "192.168.0.2", "fd00:3:0:5::2" }, "LAN device overlay" )

-- A LAN router: both interfaces, each with its matching IPv6.
local router = newEnt()
router:SetSubnet( 0 )
router:SetUpBB( 3 )
router:SetLanID( 5 )
router:SetIP( 1 )
router:SetBSubnet( 3 )
router:SetBIP( 0 )
assertList( router:GetOverlayAddresses(), {
	"192.168.0.1", "fd00:3:0:5::1", "100.0.3.1", "fd00:3::1",
}, "LAN router overlay" )

-- A backbone router has no LAN: its primary NW address is the WAN IPv4, so
-- the old overlay printed the same IPv4 twice. It must show that IPv4 once,
-- followed by its IPv6.
local brouter = newEnt()
brouter:SetBSubnet( 3 )
brouter:SetBIP( 0 )
assertList( brouter:GetOverlayAddresses(), { "100.0.3.1", "fd00:3::1" }, "backbone router overlay" )

-- A WAN-only PC (behind a modem) behaves the same way.
local wanpc = newEnt()
wanpc:SetLanAddress( false )
wanpc:SetBSubnet( 4 )
wanpc:SetBIP( 5 )
assertList( wanpc:GetOverlayAddresses(), { "100.0.4.6", "fd00:4::6" }, "WAN-only overlay" )

-- DrawInfo puts the heading first, then the interface addresses, and still
-- flags hardware failures.
local lines
PCMod.Gui = {
	DrawWirelessLinks = function() end,
	DrawLabel = function( x, y, font, text ) lines = text end,
}
brouter.PrintName = "Backbone Router"
brouter:DrawInfo( { x = 0, y = 0 } )
assertList( lines, { "Backbone Router", "100.0.3.1", "fd00:3::1" }, "backbone router DrawInfo" )

print( "ALL OVERLAY TESTS PASSED" )
