-- Entity dual-stack + IPv6 subnet integration test (plain Lua after translation).
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

SERVER = true
CLIENT = false

dofile( "pcmod_sh_common.lua" )

// The shared module redefines PCMod.Msg; use a no-op so the entity helpers can
// log without needing table.Count / the global Msg in the plain-Lua harness.
PCMod.Msg = function() end

ENT = {}
dofile( "pcmod_shared.lua" )

local ent = setmetatable( {}, { __index = ENT } )
local nw = {}
function ent:EntIndex() return 1 end
function ent:IsValid() return true end
function ent:SetNWString( k, v ) nw[ k ] = v end
PCMod.Data[ 1 ] = {
	HardDrive = {},
	IP = {
		Add = false, Sub = false, Full = false, V6 = false,
		Back = { Add = false, Sub = false, Full = false, V6 = false },
	},
}

local function assertEq( a, b, msg )
	if (a ~= b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function assertTrue( v, msg )
	if (not v) then error( "FAILED: " .. msg, 2 ) end
end

-- Private LAN under backbone 3, /64 net 5, host 2 -> fd00:3:0:5::2.
ent:SetSubnet( 0 )
ent:SetUpBB( 3 )
ent:SetLanID( 5 )
ent:SetIP( 2 )
assertEq( ent:GetFullIP(), "192.168.0.2", "IPv4 LAN address" )
assertEq( ent:GetIPv6(), "fd00:3:0:5::2", "emulated IPv6 LAN address" )
assertEq( ent:GetIPv6Prefix(), "fd00:3:0:5::/64", "LAN /64 prefix" )
assertEq( ent:GetIPv6Gateway(), "fd00:3:0:5::1", "LAN gateway" )
assertEq( ent:GetIPv6LinkLocal(), "fe80::2", "LAN link-local" )
assertEq( nw[ "IP" ], "192.168.0.2", "IPv4 NW string" )
assertEq( nw[ "IPv6" ], "fd00:3:0:5::2", "IPv6 NW string" )
assertEq( nw[ "IPv6.Prefix" ], "fd00:3:0:5::/64", "IPv6 prefix NW string" )
assertEq( nw[ "IPv6.LinkLocal" ], "fe80::2", "IPv6 link-local NW string" )

-- Backbone: BIP 1 -> host .2 (16-bit backbone id 3 -> 10.0.3.0/24).
ent:SetBSubnet( 3 )
ent:SetBIP( 1 )
assertEq( ent:GetFullBIP(), "10.0.3.2", "IPv4 backbone address" )
assertEq( ent:GetBIPv6(), "fd00:3::2", "emulated IPv6 backbone address" )
assertEq( ent:GetBIPv6Prefix(), "fd00:3::/32", "backbone /32 prefix" )
assertEq( ent:GetBIPv6Gateway(), "fd00:3::1", "backbone gateway" )
assertEq( ent:GetBIPv6LinkLocal(), "fe80::2", "backbone link-local" )

-- Brouter gateway: BIP 0 clamps to host .1.
ent:SetBIP( 0 )
assertEq( ent:GetFullBIP(), "10.0.3.1", "backbone gateway IPv4" )
assertEq( ent:GetBIPv6(), "fd00:3::1", "backbone gateway IPv6" )
ent:SetBIP( 1 )

-- Exact-address matching accepts every supported representation.
assertTrue( ent:IsAddressedTo( "192.168.0.2" ), "LAN IPv4 matches" )
assertTrue( ent:IsAddressedTo( "fd00:3:0:5::2" ), "LAN IPv6 matches" )
assertTrue( ent:IsAddressedTo( "fd00:3:0:5:0:0:0:2" ), "expanded LAN IPv6 matches" )
assertTrue( ent:IsAddressedTo( "[fd00:3:0:5::2]" ), "bracketed LAN IPv6 matches" )
assertTrue( ent:IsAddressedTo( "::ffff:192.168.0.2" ), "mapped LAN IPv4 matches" )
assertTrue( ent:IsAddressedTo( "10.0.3.2" ), "backbone IPv4 matches" )
assertTrue( ent:IsAddressedTo( "fd00:3::2" ), "backbone IPv6 matches" )
assertTrue( not ent:IsAddressedTo( "192.168.0.3" ), "other LAN host rejected" )
assertTrue( not ent:IsAddressedTo( "fd00:3:0:5::4" ), "other LAN IPv6 host rejected" )
assertTrue( not ent:IsAddressedTo( "::1" ), "loopback is not this entity" )
assertTrue( not ent:IsAddressedTo( nil ), "nil rejected" )

-- Subnet membership (what a router uses for on-link decisions).
assertTrue( ent:IsInIPv6Subnet( "fd00:3:0:5::99" ), "LAN prefix contains other host" )
assertTrue( not ent:IsInIPv6Subnet( "fd00:3:0:6::3" ), "other LAN subnet rejected" )
assertTrue( not ent:IsInIPv6Subnet( "fd00:3:0:9::1" ), "sibling LAN outside this /64 rejected" )
assertTrue( ent:IsInIPv6Subnet( "fd00:3:0:9::1", true ), "backbone /32 contains sibling LAN" )

-- Lazy derivation for a data slot made before these fields existed.
PCMod.Data[ 1 ].IP.V6 = nil
PCMod.Data[ 1 ].IP.V6Prefix = nil
PCMod.Data[ 1 ].IP.V6Link = nil
assertEq( ent:GetIPv6(), "fd00:3:0:5::2", "lazy IPv6 derivation" )
assertEq( ent:GetIPv6Prefix(), "fd00:3:0:5::/64", "lazy prefix derivation" )
assertEq( ent:GetIPv6LinkLocal(), "fe80::2", "lazy link-local derivation" )
PCMod.Data[ 1 ].IP.Back.V6 = nil
PCMod.Data[ 1 ].IP.Back.V6Prefix = nil
PCMod.Data[ 1 ].IP.Back.V6Link = nil
assertEq( ent:GetBIPv6(), "fd00:3::2", "lazy backbone IPv6 derivation" )
assertEq( ent:GetBIPv6Prefix(), "fd00:3::/32", "lazy backbone prefix" )

-- Router-style host .1 becomes the ::1 gateway.
ent:SetIP( 1 )
assertEq( ent:GetFullIP(), "192.168.0.1", "IPv4 gateway address" )
assertEq( ent:GetIPv6(), "fd00:3:0:5::1", "IPv6 gateway address" )

-- Clearing an address must clear every derived field.
ent:SetIP( false )
assertEq( ent:GetIPv6(), false, "cleared IPv6" )
assertEq( ent:GetIPv6Prefix(), false, "cleared prefix" )
assertEq( ent:GetIPv6Gateway(), false, "cleared gateway" )
assertEq( ent:GetIPv6LinkLocal(), false, "cleared link-local" )
assertEq( nw[ "IPv6" ], "", "cleared IPv6 NW string" )
assertEq( nw[ "IPv6.Prefix" ], "", "cleared prefix NW string" )

-- Duplicator save/restore round-trip (BuildDupeInfo / ApplyDupeInfo).
PCMod.TableToString = function( t ) return t end
PCMod.StringToTable = function( s ) return s end
local dump = { ["/mydocs/x.txt"] = { ItemType = "file", ItemContent = "hello" } }
PCMod.Data[1].HardDrive = dump
PCMod.Data[1].IsOn = true
PCMod.Data[1].Password = "1234"
PCMod.Data[1].IP = { Add = 5, Sub = 0, Full = "192.168.0.5", V6 = false, Back = { Add = false, Sub = false, Full = false, V6 = false } }
ent.IsComputer = true
ent.IsNetworkDevice = false
local booted = false
ent.TurnOn = function( self ) booted = true end

local dinfo = ent:BuildDupeInfo()
assertTrue( dinfo.harddrive == dump, "dupe saves harddrive" )
assertTrue( dinfo.ison == true, "dupe saves on state" )
assertTrue( dinfo.password == "1234", "dupe saves password" )
assertTrue( dinfo.ip.Add == 5, "dupe saves IP" )

-- Restore into a wiped slot.
PCMod.Data[1].HardDrive = {}
PCMod.Data[1].IsOn = false
PCMod.Data[1].Password = ""
PCMod.Data[1].IP = { Add = 1, Sub = 0, Back = { Add = false, Sub = false, Full = false, V6 = false } }
ent:ApplyDupeInfo( nil, ent, dinfo, nil )
assertTrue( PCMod.Data[1].HardDrive == dump, "dupe restores harddrive" )
assertTrue( PCMod.Data[1].Password == "1234", "dupe restores password" )
assertTrue( PCMod.Data[1].IP.Add == 5, "dupe restores IP" )
assertTrue( booted == true, "dupe reboots a computer that was on" )

-- Router config save/restore.
ent.IsComputer = false
ent.IsNetworkDevice = true
local rc = { Firewall = true, Forwards = { ["72"] = { ip = "192.168.0.2", port = 72 } } }
PCMod.Data[1].RouterCfg = rc
PCMod.Data[1].WirePass = "wifi"
PCMod.Data[1].IsWireless = true
local rinfo = ent:BuildDupeInfo()
assertTrue( rinfo.routercfg == rc and rinfo.wirepass == "wifi" and rinfo.iswireless == true, "dupe saves router config" )
PCMod.Data[1].RouterCfg = {}
PCMod.Data[1].WirePass = ""
PCMod.Data[1].IsWireless = false
ent:ApplyDupeInfo( nil, ent, rinfo, nil )
assertTrue( PCMod.Data[1].RouterCfg == rc and PCMod.Data[1].WirePass == "wifi" and PCMod.Data[1].IsWireless == true, "dupe restores router config" )

-- Wiring re-link: port links are saved and re-established on paste.
local fakePeer = { IsValid = function() return true end, IsPCMod = true, EntIndex = function() return 42 end }
PCMod.Data[1].Ports = { [1] = { Connected = true, ConEnt = fakePeer, RemotePort = 3 } }
ent.IsComputer = false
ent.IsNetworkDevice = false
local rec = nil
PCMod.Wiring = { LinkPorts = function( srcent, srcprt, destent, destprt, rt, ct ) rec = { srcprt = srcprt, destent = destent, destprt = destprt } end }
local linfo = ent:BuildDupeInfo()
assertTrue( linfo.links ~= nil and #linfo.links == 1 and linfo.links[1].port == 1 and linfo.links[1].peer == 42 and linfo.links[1].remote == 3, "dupe saves port links" )
local pastedPeer = { IsValid = function() return true end, IsPCMod = true }
ent:ApplyDupeInfo( nil, ent, linfo, function( id ) if (id == 42) then return pastedPeer end end )
assertTrue( rec ~= nil and rec.srcprt == 1 and rec.destprt == 3 and rec.destent == pastedPeer, "dupe re-links ports via LinkPorts" )

print( "ALL ENTITY IPV6 TESTS PASSED" )