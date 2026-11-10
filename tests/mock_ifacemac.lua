-- Per-interface MAC addresses for multi-NIC hosts.
function string.Trim( s )
	return (string.gsub( s, "^%s*(.-)%s*$", "%1" ))
end
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
function istable( v ) return type( v ) == "table" end
function AddCSLuaFile() end
SERVER = true
CLIENT = false

PCMod = { Data = {}, Msg = function() end, Warning = function() end, Cfg = {} }
dofile( "pcmod_sh_common.lua" )
PCMod.Msg = function() end

ENT = {}
dofile( "pcmod_shared.lua" )

local ent = setmetatable( {}, { __index = ENT } )
ent.IsComputer = true
function ent:EntIndex() return 1 end
function ent:IsValid() return true end
function ent:SetNWString() end
PCMod.Data[ 1 ] = {
	HardDrive = {},
	IP = { LAN = false, WAN = false, Extra = {} },
	MAC = "AA:BB:CC:DD:EE:01",
	Ports = {
		{ Type = "network" },
		{ Type = "network" },
		{ Type = "vga" },
	},
}

local function assertEq( a, b, msg )
	if (a != b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function assertTrue( v, msg )
	if (not v) then error( "FAILED: " .. msg, 2 ) end
end
local function validMAC( mac )
	return ((type( mac ) == "string") && (string.match( mac, "^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$" ) != nil))
end

-- The lowest wired port keeps the legacy identity; other interfaces differ.
local m1 = ent:EnsureInterfaceMAC( 1 )
assertEq( m1, "AA:BB:CC:DD:EE:01", "first wired port keeps the legacy MAC" )
local m2 = ent:EnsureInterfaceMAC( 2 )
assertTrue( validMAC( m2 ), "second wired port gets a valid MAC" )
assertTrue( m2 != m1, "the two Ethernet ports do not share a MAC" )
local m0 = ent:EnsureInterfaceMAC( 0 )
assertTrue( validMAC( m0 ), "Wi-Fi gets a valid MAC" )
assertTrue( (m0 != m1) && (m0 != m2), "Wi-Fi does not share a wired MAC" )
assertEq( ent:EnsureInterfaceMAC( 2 ), m2, "interface MACs are stable" )
assertTrue( ent:GetInterfaceMACs()[ 0 ] == m0, "interface MAC table exposes every port" )

-- Every recorded interface address is reachable, even when another NIC owns
-- the primary identity.
PCMod.Data[ 1 ].IP.Interfaces = { [ 1 ] = { Port = 1, IPv4 = "192.168.0.2" } }
assertTrue( ent:IsAddressedTo( "192.168.0.2" ), "per-interface IPv4 is addressed to us" )

-- Changing the primary MAC moves the interface that owned it.
ent:SetMAC( "AA:BB:CC:DD:EE:99" )
assertEq( ent:EnsureInterfaceMAC( 1 ), "AA:BB:CC:DD:EE:99", "primary port follows SetMAC" )
assertEq( ent:EnsureInterfaceMAC( 2 ), m2, "secondary port keeps its MAC" )

-- Interface MACs survive a world save/load.
local saved = ent:OnSave()
assertTrue( istable( saved.ifacemacs ), "save stores interface MACs" )
PCMod.Data[ 1 ].InterfaceMACs = nil
ent:OnRestore( saved )
assertEq( ent:EnsureInterfaceMAC( 1 ), "AA:BB:CC:DD:EE:99", "primary MAC restored" )
assertEq( ent:EnsureInterfaceMAC( 2 ), m2, "secondary MAC restored" )

-- A duplicated entity gets fresh addresses for every interface.
ent:RandomizeIdentity()
assertTrue( PCMod.Data[ 1 ].InterfaceMACs == nil, "clone drops the old interface MACs" )
local n1 = ent:EnsureInterfaceMAC( 1 )
local n2 = ent:EnsureInterfaceMAC( 2 )
assertEq( n1, PCMod.Data[ 1 ].MAC, "new primary uses the new legacy MAC" )
assertTrue( n1 != "AA:BB:CC:DD:EE:99", "clone primary is fresh" )
assertTrue( (n2 != m2) && (n2 != n1), "clone secondary is fresh and distinct" )

print( "ALL INTERFACE MAC TESTS PASSED" )
