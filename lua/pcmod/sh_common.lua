
// ---------------------------------------------------------------------------------------------------------
// sh_common.lua - Revision 1
// Shared
// Loads basic shared common functions
// ---------------------------------------------------------------------------------------------------------


// ---------------------------------------------------------------------------------------------------------
// Require the modules we need
// ---------------------------------------------------------------------------------------------------------

--require( "datastream" )


// ---------------------------------------------------------------------------------------------------------
// Add some common files not added by sv_core
// ---------------------------------------------------------------------------------------------------------

//if (SERVER) then AddCSLuaFile( "pcmod/sh_json.lua" ) end
//include( "sh_json.lua" )

PCMod.GM = GM or GAMEMODE

PCMod.MsgDebugBuffer = {}
PCMod.MsgBuffer = {}
PCMod.WarningBuffer = {}
PCMod.ErrorBuffer = {}
PCMod.BufferI = { 1, 1, 1, 1 }

// ---------------------------------------------------------------------------------------------------------
// Msg - Prints a PCMod message to console
// ---------------------------------------------------------------------------------------------------------
function PCMod.Msg( msgtext, isdebug )
	if ((isdebug == true) && (PCMod.Cfg.DebugMode == false)) then return end
	if (isdebug == true) then
		table.insert(PCMod.MsgDebugBuffer, { PCMod.BufferI[1], msgtext })
		PCMod.BufferI[1] = PCMod.BufferI[1] + 1
		// Round 34 (M-45): the buffer was only trimmed in PCMod.SaveLog - with
		// the logging switched off it grew without a limit.
		if (table.Count( PCMod.MsgDebugBuffer ) > 500) then
			for i = 1, 100 do table.remove( PCMod.MsgDebugBuffer, 1 ) end
		end
	else
		table.insert(PCMod.MsgBuffer, { PCMod.BufferI[2], msgtext })
		PCMod.BufferI[2] = PCMod.BufferI[2] + 1
		if (table.Count( PCMod.MsgBuffer ) > 500) then
			for i = 1, 100 do table.remove( PCMod.MsgBuffer, 1 ) end
		end
	end
	Msg( "PCMod2: " )
	Msg( msgtext )
	Msg( "\n" )
end

// ---------------------------------------------------------------------------------------------------------
// Warning - Prints a PCMod warning to console
// ---------------------------------------------------------------------------------------------------------
function PCMod.Warning( msgtext )
	table.insert(PCMod.WarningBuffer, { PCMod.BufferI[3], msgtext })
	PCMod.BufferI[3] = PCMod.BufferI[3] + 1
	ErrorNoHalt( "PCMod2: " .. msgtext .. "\n" )
end

// ---------------------------------------------------------------------------------------------------------
// Error - Prints a PCMod error to console
// ---------------------------------------------------------------------------------------------------------
function PCMod.Error( msgtext )
	table.insert(PCMod.ErrorBuffer, { PCMod.BufferI[4], msgtext })
	PCMod.BufferI[4] = PCMod.BufferI[4] + 1
	Error( "PCMod2: " .. msgtext .. "\n" )
end

// ---------------------------------------------------------------------------------------------------------
// Notice - Prints a sandbox notice
// ---------------------------------------------------------------------------------------------------------
function PCMod.Notice( msgtext, ply )
	if (CLIENT) then
		PCMod.Msg( msgtext )
		GAMEMODE:AddNotify( msgtext, NOTIFY_GENERIC, 5 )
	end
	if (SERVER) then
		if (ply && ply:IsValid()) then
			umsg.Start( "pcmod_notice", ply )
				umsg.String( msgtext )
			umsg.End()
		end
	end
end
if (CLIENT) then usermessage.Hook( "pcmod_notice", function( um ) PCMod.Notice( um:ReadString() ) end ) end

// ---------------------------------------------------------------------------------------------------------
// GMsg - Prints a message to all players
// ---------------------------------------------------------------------------------------------------------
function PCMod.GMsg( msgtext )
	if (CLIENT) then return end
	PrintMessage( HUD_PRINTTALK, msgtext )
end

// ---------------------------------------------------------------------------------------------------------
// EnforceJson - SECURITY (stage 1, fix 1.1): the legacy UseJson=false RunString codec was removed.
//               Forces JSON once (keeps encoder and decoder in sync) and warns the operator.
// ---------------------------------------------------------------------------------------------------------
function PCMod.EnforceJson()
	if (PCMod.Cfg.UseJson) then return end
	PCMod.Cfg.UseJson = true
	ErrorNoHalt( "PCMod: UseJson=false is no longer supported (legacy RunString codec removed for security); switching to JSON. Old non-JSON data files will not load - delete them.\n" )
end

// ---------------------------------------------------------------------------------------------------------
// TableToString - Converts a table into a string
// ---------------------------------------------------------------------------------------------------------
function PCMod.TableToString( tbl )
	PCMod.EnforceJson()
	if (PCMod.Cfg.UseJson) then
		 local result = util.TableToJSON( tbl )
		 return result
	end
	local str = "{"
	local allnum = table.AllNumerical( tbl )
	if (allnum) then
		local cnt
		for i=1, table.maxn( tbl ) do
			local v = tbl[ i ]
			if (v) then
				local val = ""
				if (type( v ) == "string") then val = "\"" .. v .. "\"" end
				if (type( v ) == "boolean") then val = tostring(v) end
				if (type( v ) == "number") then val = tostring(v) end
				if (type( v ) == "table") then val = PCMod.TableToString( v ) end
				str = str .. val .. ","
			end
		end
	else
		for k, v in pairs( tbl ) do
			local val = ""
			local key = ""
			if (type( v ) == "string") then val = "\"" .. PCMod.CleanString( v ) .. "\"" end
			if (type( v ) == "boolean") then val = tostring(v) end
			if (type( v ) == "number") then val = tostring(v) end
			if (type( v ) == "table") then val = PCMod.TableToString( v ) end
			if (type( k ) == "string") then key = "[\"" .. k .. "\"]" end
			if (type( k ) == "number") then key = "[" .. tostring(k) .. "]" end
			str = str .. key .. "=" .. val .. ","
		end
	end
	str = string.Replace( str, "\n", "#>" )
	local fstr = str .. "}"
	// PCMod.Msg( "Final Conversion: " .. fstr, true )
	return fstr
end

// ---------------------------------------------------------------------------------------------------------
// BTN - Converts a bool to number
// ---------------------------------------------------------------------------------------------------------
function PCMod.BTN( bool )
	if (bool) then return 1 else return 0 end
end

// ---------------------------------------------------------------------------------------------------------
// CleanString - Cleans a string, ready to be added into a RunString command
// ---------------------------------------------------------------------------------------------------------
function PCMod.CleanString( str )
	str = string.Replace( str, "\n", "#>" )
	str = string.Replace( str, "\"", "#@" )
	return str
end

// ---------------------------------------------------------------------------------------------------------
// RestoreString - Restores a cleaned string
// ---------------------------------------------------------------------------------------------------------
function PCMod.RestoreString( str )
	str = string.Replace( str, "#>", "\n" )
	str = string.Replace( str, "#@", "\"" )
	return str
end

// ---------------------------------------------------------------------------------------------------------
// StringToTable - Converts a string back into a table
// ---------------------------------------------------------------------------------------------------------
function PCMod.StringToTable( str )
	if (type( str ) != "string") then
		PCMod.Msg( "Tried to convert non-string value to table!", true )
		return {}
	end
	// SECURITY (stage 1, fix 1.1): the legacy RunString decoder was removed.
	// Always decode as JSON (EnforceJson keeps encoder and decoder in sync).
	PCMod.EnforceJson()
	local result = util.JSONToTable( str )
	return result
end

// ---------------------------------------------------------------------------------------------------------
// RestoreTable - Restores all strings in a table, and subtables, back to proper state
// ---------------------------------------------------------------------------------------------------------
function PCMod.RestoreTable( tbl )
	local tmp = table.Copy( tbl )
	for k, v in pairs( tbl ) do
		local t = type( v )
		if (t == "table") then
			tmp[ k ] = PCMod.RestoreTable( v )
		end
		if (t == "string") then
			tmp[ k ] = PCMod.RestoreString( v )
		end
	end
	return tmp
end

// ---------------------------------------------------------------------------------------------------------
// IsIP - Returns true if the string represents an IP address
// ---------------------------------------------------------------------------------------------------------
function string.IsIP( str )
	// Round 23: IsIP is called with raw user input (p2pchat/chatserv/nettools),
	// so it must never compare a non-number: tonumber() returns nil for a
	// non-numeric part and "nil < 0" raised a Lua error (sh_common.lua:213).
	if (type( str ) != "string") then return false end
	local c = string.Count( str, "." )
	if (c != 3) then return false end
	local es = string.Explode( ".", str )
	if (#es != 4) then return false end
	local cnt
	for cnt=1, 4 do
		local v = tonumber( es[ cnt ] )
		if (!v) then return false end
		if ((v < 0) || (v > 255)) then return false end
	end
	return true
end

// ---------------------------------------------------------------------------------------------------------
// IPv6 "Emulation"
// ---------------------------------------------------------------------------------------------------------
// PCMod's network is IPv4 based. To let programs be written and tested against
// IPv6, every PC also gets a deterministic unique-local address. The emulation
// follows real hierarchical subnetting:
//
//   * the whole internet is one ULA /16:            fd00::/16
//   * each backbone router owns one /32:            fd00:<bb>::/32
//   * each LAN router owns one /64 of that /32:     fd00:<bb>:0:<subnet>::/64
//   * the router/gateway of a /64 is ::1, hosts are ::2, ::3, ...
//
// A standalone LAN (not connected to a backbone) uses fd00:0:0:<subnet>::/64,
// so a LAN never needs to know about the wider network to get an address.
//
// The normal IPv4 addresses keep working, and the standard IPv4-mapped form
// (::ffff:192.168.5.2 and ::ffff:c0a8:0502) plus ::1/localhost/link-local
// addresses are understood everywhere an address is accepted. Routers match
// IPv6 destinations against their /64 LAN and /32 backbone prefixes and
// translate the result back to IPv4 for delivery.
//
// This block also provides the prefix helpers (BackbonePrefix, LANPrefix,
// GetPrefix, InSubnet, Gateway, LinkLocal, AddressType) used by routers,
// programs and the entity class.
PCMod.IPv6 = PCMod.IPv6 or {}

// Split one textual group and validate it (1-4 hex digits).
local function V6Group( part )
	if ((!part) || (type( part ) != "string")) then return nil end
	if (!string.match( part, "^%x+$" )) then return nil end
	if (string.len( part ) > 4) then return nil end
	local n = tonumber( part, 16 )
	if ((!n) || (n < 0) || (n > 65535)) then return nil end
	return n
end

// Expand an IPv6 literal into eight 16-bit groups. Accepts "::" compression,
// brackets, a zone id (fe80::1%eth0), a trailing dotted IPv4 part
// (::ffff:192.168.5.2) and the full uncompressed form.
function PCMod.IPv6.Expand( addr )
	if (type( addr ) != "string") then return nil end
	addr = PCMod.IPv6.Normalize( addr )
	if ((!addr) || (addr == "")) then return nil end
	if (!string.find( addr, ":", 1, true )) then return nil end

	// A trailing dotted quad is really two 16-bit groups.
	local dotted = string.match( addr, "(%d+%.%d+%.%d+%.%d+)$" )
	if (dotted) then
		local a, b, c, d = string.match( dotted, "^(%d+)%.(%d+)%.(%d+)%.(%d+)$" )
		a, b, c, d = tonumber( a ), tonumber( b ), tonumber( c ), tonumber( d )
		if ((!a) || (!b) || (!c) || (!d)) then return nil end
		if ((a > 255) || (b > 255) || (c > 255) || (d > 255)) then return nil end
		local hi, lo = (a * 256) + b, (c * 256) + d
		addr = string.sub( addr, 1, string.len( addr ) - string.len( dotted ) ) .. string.format( "%x:%x", hi, lo )
	end

	local function Split( text )
		local out = {}
		if ((text == nil) || (text == "")) then return out end
		for part in string.gmatch( text, "[^:]+" ) do
			local n = V6Group( part )
			if (!n) then return nil end
			table.insert( out, n )
		end
		return out
	end

	local left, right = string.match( addr, "^(.-)::(.*)$" )
	local groups = {}
	if (left != nil) then
		// Exactly one "::" is valid. A leading/trailing single colon in
		// either half means there was a second empty group, which is invalid.
		if ((string.Right( left, 1 ) == ":") || (string.Left( right, 1 ) == ":")) then return nil end
		if (string.find( right, "::", 1, true )) then return nil end
		local lg = Split( left )
		local rg = Split( right )
		if ((!lg) || (!rg)) then return nil end
		local fill = 8 - #lg - #rg
		if (fill < 0) then return nil end
		for _, v in ipairs( lg ) do table.insert( groups, v ) end
		for i = 1, fill do table.insert( groups, 0 ) end
		for _, v in ipairs( rg ) do table.insert( groups, v ) end
	else
		if ((string.Left( addr, 1 ) == ":") || (string.Right( addr, 1 ) == ":")) then return nil end
		groups = Split( addr )
		if ((!groups) || (#groups != 8)) then return nil end
	end
	if (#groups != 8) then return nil end
	return groups
end

// Compress eight 16-bit groups back into canonical text form. The longest run
// of zero groups (at least two) becomes "::".
function PCMod.IPv6.Format( groups )
	if ((!groups) || (type( groups ) != "table") || (#groups != 8)) then return nil end
	for i = 1, 8 do
		local v = tonumber( groups[ i ] )
		if ((!v) || (v < 0) || (v > 65535)) then return nil end
		groups[ i ] = math.floor( v )
	end
	local bestStart, bestLen = nil, 0
	local i = 1
	while (i <= 8) do
		if (groups[ i ] == 0) then
			local j = i
			while ((j <= 8) && (groups[ j ] == 0)) do j = j + 1 end
			local len = j - i
			if ((len >= 2) && (len > bestLen)) then
				bestStart = i
				bestLen = len
			end
			i = j
		else
			i = i + 1
		end
	end
	if (!bestStart) then
		local out = {}
		for k = 1, 8 do out[ k ] = string.format( "%x", groups[ k ] ) end
		return table.concat( out, ":" )
	end
	local l, r = {}, {}
	for k = 1, bestStart - 1 do table.insert( l, string.format( "%x", groups[ k ] ) ) end
	for k = bestStart + bestLen, 8 do table.insert( r, string.format( "%x", groups[ k ] ) ) end
	local ls, rs = table.concat( l, ":" ), table.concat( r, ":" )
	if ((ls == "") && (rs == "")) then return "::" end
	if (ls == "") then return "::" .. rs end
	if (rs == "") then return ls .. "::" end
	return ls .. "::" .. rs
end

// Strip [] used by URL style IPv6 literals, a zone id, and lower-case.
function PCMod.IPv6.Normalize( addr )
	if (type( addr ) != "string") then return nil end
	addr = string.Trim( addr )
	addr = string.gsub( addr, "^%[", "" )
	addr = string.gsub( addr, "%]$", "" )
	addr = string.gsub( addr, "%%[%w_%-%.]+$", "" )
	return string.lower( addr )
end

// Hierarchical allocation helpers. The whole PCMod internet is one ULA /16:
//   * one /32 per backbone router:  fd00:<bb>::/32
//   * one /64 per LAN router:       fd00:<bb>:0:<subnet>::/64
// LANs only know their own /64 (they know nothing about the WAN / backbones);
// a standalone LAN (no backbone) uses fd00:0:0:<subnet>::/64.
function PCMod.IPv6.BackbonePrefix( bb )
	return PCMod.IPv6.Format( { 0xfd00, bb, 0, 0, 0, 0, 0, 0 } ) .. "/32"
end

function PCMod.IPv6.LANPrefix( bb, subnet )
	return PCMod.IPv6.Format( { 0xfd00, bb, 0, subnet, 0, 0, 0, 0 } ) .. "/64"
end

// Split a PCMod ULA into { bb, lan, iid } (backbone /32 id, LAN /64 id,
// interface id). Returns nil for addresses outside the hierarchy.
function PCMod.IPv6.Hierarchy( addr )
	local g = PCMod.IPv6.Expand( addr )
	if ((!g) || (g[1] != 0xfd00)) then return nil end
	return { bb = g[2], lan = g[4], iid = g[8] }
end

// Build the emulated IPv6 address for an IPv4 address string. Only the backbone
// (10.<hi>.<lo>.<host>) and loopback have a stateless mapping; a LAN's /64
// depends on its upstream backbone, so LAN addresses are stored rather than
// derived here.
function PCMod.IPv6.FromIPv4( ip )
	if (type( ip ) != "string") then return nil end
	local a, b, c, d = string.match( ip, "^(%d+)%.(%d+)%.(%d+)%.(%d+)$" )
	if (!a) then return nil end
	a, b, c, d = tonumber( a ), tonumber( b ), tonumber( c ), tonumber( d )
	if ((!a) || (!b) || (!c) || (!d)) then return nil end
	if ((a > 255) || (b > 255) || (c > 255) || (d > 255)) then return nil end
	if ((a == 127) && (b == 0) && (c == 0) && (d == 1)) then return "::1" end
	if (a == 10) then
		// 10.<hi>.<lo>.<host> is a /32 within the 16-bit backbone <bb> (hi*256+lo),
		// mirroring the backbone host fd00:<bb>::<host>.
		return PCMod.IPv6.Format( { 0xfd00, (b * 256) + c, 0, 0, 0, 0, 0, d } )
	end
	// Any other IPv4 address is represented in the standard mapped form.
	return PCMod.IPv6.Format( { 0, 0, 0, 0, 0, 0xffff, (a * 256) + b, (c * 256) + d } )
end

// Translate any supported address (IPv4, emulated IPv6, IPv4-mapped IPv6,
// ::1/localhost) into the IPv4 address the network core routes on. Returns
// nil for addresses that cannot be represented in PCMod's address space.
function PCMod.IPv6.ToIPv4( addr )
	if (type( addr ) != "string") then return nil end
	addr = PCMod.IPv6.Normalize( addr )
	if (!addr) then return nil end
	if ((addr == "::1") || (addr == "localhost") || (addr == "ip6-localhost")) then return "127.0.0.1" end
	if (string.match( addr, "^%d+%.%d+%.%d+%.%d+$" )) then
		if (string.IsIP( addr )) then return addr end
		return nil
	end
	local g = PCMod.IPv6.Expand( addr )
	if (!g) then return nil end
	// Standard mapped form (::ffff:a.b.c.d).
	if ((g[1] == 0) && (g[2] == 0) && (g[3] == 0) && (g[4] == 0) && (g[5] == 0) && (g[6] == 0xffff)) then
		return string.format( "%d.%d.%d.%d", math.floor( g[7] / 256 ), g[7] % 256, math.floor( g[8] / 256 ), g[8] % 256 )
	end
	if (g[1] == 0xfd00) then
		local bb = g[2]
		local subnet = g[4]
		if ((g[5] == 0) && (g[6] == 0) && (g[7] == 0)) then
			if ((g[3] == 0) && (subnet == 0)) then
				// Backbone host fd00:<bb>::<iid> -> 10.<hi>.<lo>.<iid>
				if ((g[8] >= 1) && (g[8] <= 255)) then
					return string.format( "10.%d.%d.%d", math.floor( bb / 256 ), bb % 256, g[8] )
				end
			elseif ((g[3] == 0) && (subnet >= 1) && (subnet <= 255) && (g[8] <= 255)) then
				// LAN host fd00:<bb>:0:<subnet>::<iid> -> 192.168.<subnet>.<iid>
				return string.format( "192.168.%d.%d", subnet, g[8] )
			end
		end
	end
	return nil
end

// True when the string is a valid IPv4 or supported IPv6 address.
function PCMod.IPv6.IsIP( addr )
	if (type( addr ) != "string") then return false end
	local norm = PCMod.IPv6.Normalize( addr )
	if ((!norm) || (norm == "")) then return false end
	if ((norm == "localhost") || (norm == "ip6-localhost")) then return true end
	if (!string.find( norm, ":", 1, true )) then return string.IsIP( norm ) end
	return (PCMod.IPv6.Expand( norm ) != nil)
end

// True when the string is a valid IPv6 literal.
function PCMod.IPv6.IsIPv6( addr )
	if (type( addr ) != "string") then return false end
	local norm = PCMod.IPv6.Normalize( addr )
	if ((!norm) || (!string.find( norm, ":", 1, true ))) then return false end
	return (PCMod.IPv6.Expand( norm ) != nil)
end

// True when the string is a valid dotted IPv4 address.
function PCMod.IPv6.IsIPv4( addr )
	if (type( addr ) != "string") then return false end
	return string.IsIP( PCMod.IPv6.Normalize( addr ) )
end

// True when the address is the IPv6 loopback.
function PCMod.IPv6.IsLoopback( addr )
	if (type( addr ) != "string") then return false end
	local norm = PCMod.IPv6.Normalize( addr )
	if ((!norm) || (norm == "")) then return false end
	if ((norm == "::1") || (norm == "localhost") || (norm == "ip6-localhost")) then return true end
	local g = PCMod.IPv6.Expand( norm )
	if (!g) then return (PCMod.IPv6.ToIPv4( norm ) == "127.0.0.1") end
	for i = 1, 7 do
		if (g[ i ] != 0) then return false end
	end
	return (g[8] == 1)
end

// True when both strings are the same address (compressed or expanded).
function PCMod.IPv6.Equal( a, b )
	if ((type( a ) != "string") || (type( b ) != "string")) then return false end
	local ga = PCMod.IPv6.Expand( a )
	local gb = PCMod.IPv6.Expand( b )
	if ((!ga) || (!gb)) then return false end
	for i = 1, 8 do
		if (ga[ i ] != gb[ i ]) then return false end
	end
	return true
end

// Compare an address (IPv4 or IPv6) with a stored IPv4 and/or IPv6 address.
function PCMod.IPv6.Matches( addr, ipv4, ipv6 )
	if (type( addr ) != "string") then return false end
	if (ipv4 && (PCMod.IPv6.ToIPv4( addr ) == ipv4)) then return true end
	if (ipv6 && PCMod.IPv6.Equal( addr, ipv6 )) then return true end
	return false
end

// Parse "addr/len", "addr", or an (addr, len) pair. Returns a table with the
// original Address, the prefix Length and the masked Groups, or nil.
function PCMod.IPv6.ParsePrefix( prefix, len )
	if ((prefix == nil) || (type( prefix ) != "string")) then return nil end
	local addr, bits = prefix, len
	if (bits == nil) then
		local a, l = string.match( prefix, "^(.-)/(%d+)$" )
		if (a) then
			addr, bits = a, tonumber( l )
		else
			bits = 128
		end
	end
	bits = tonumber( bits )
	if ((!bits) || (bits < 0) || (bits > 128) || (bits != math.floor( bits ))) then return nil end
	local g = PCMod.IPv6.Expand( addr )
	if (!g) then
		// Allow an IPv4 address as a prefix source: map it first.
		local v6 = PCMod.IPv6.FromIPv4( addr )
		if (!v6) then return nil end
		g = PCMod.IPv6.Expand( v6 )
	end
	if (!g) then return nil end
	local remaining = bits
	local masked = {}
	for i = 1, 8 do
		local keep = math.min( 16, math.max( 0, remaining ) )
		if (keep == 0) then
			masked[ i ] = 0
		elseif (keep == 16) then
			masked[ i ] = g[ i ]
		else
			local scale = 2 ^ (16 - keep)
			masked[ i ] = math.floor( g[ i ] / scale ) * scale
		end
		remaining = remaining - 16
	end
	return { Address = PCMod.IPv6.Format( masked ), Length = bits, Groups = masked }
end

// Return the network prefix for an address, e.g. GetPrefix( ip, 64 )
// -> "fd00:c0:a8:5::/64". A bare address defaults to /128.
function PCMod.IPv6.GetPrefix( addr, len )
	local p = PCMod.IPv6.ParsePrefix( addr, len )
	if (!p) then return nil end
	return p.Address .. "/" .. tostring( p.Length )
end

// Network address without the "/len" suffix.
function PCMod.IPv6.Network( addr, len )
	local p = PCMod.IPv6.ParsePrefix( addr, len )
	if (!p) then return nil end
	return p.Address
end

// Alias used by code that thinks in subnet terms.
function PCMod.IPv6.SubnetOf( addr, len )
	return PCMod.IPv6.GetPrefix( addr, len )
end

// Is addr inside prefix? prefix can be "addr/len" or an (addr, len) pair.
function PCMod.IPv6.InSubnet( addr, prefix, len )
	local p = PCMod.IPv6.ParsePrefix( prefix, len )
	if (!p) then return false end
	local g = PCMod.IPv6.Expand( addr )
	if (!g) then
		local v6 = PCMod.IPv6.FromIPv4( addr )
		if (v6) then g = PCMod.IPv6.Expand( v6 ) end
	end
	if (!g) then return false end
	local remaining = p.Length
	for i = 1, 8 do
		local bits = math.min( 16, math.max( 0, remaining ) )
		if (bits > 0) then
			local scale = 2 ^ (16 - bits)
			if (math.floor( g[ i ] / scale ) != math.floor( p.Groups[ i ] / scale )) then return false end
		end
		remaining = remaining - 16
	end
	return true
end

// The gateway address (::1) for a prefix, or nil when ::1 is outside it.
function PCMod.IPv6.Gateway( prefix, len )
	local p = PCMod.IPv6.ParsePrefix( prefix, len )
	if (!p) then return nil end
	local g = {}
	for i = 1, 8 do g[ i ] = p.Groups[ i ] end
	g[8] = 1
	local addr = PCMod.IPv6.Format( g )
	if (!PCMod.IPv6.InSubnet( addr, p.Address .. "/" .. tostring( p.Length ) )) then return nil end
	return addr
end

// A deterministic link-local address (fe80::/64) for an interface. When given
// a global IPv6 address its interface identifier is reused, otherwise the seed
// (an entindex or any number) is expanded into the low 32 bits.
function PCMod.IPv6.LinkLocal( seed )
	local g = nil
	if (type( seed ) == "string") then
		if (!string.find( seed, ":", 1, true )) then
			seed = PCMod.IPv6.FromIPv4( seed ) or seed
		end
		g = PCMod.IPv6.Expand( seed )
	end
	if (g) then
		return PCMod.IPv6.Format( { 0xfe80, 0, 0, 0, g[5], g[6], g[7], g[8] } )
	end
	local n = tonumber( seed ) or 0
	n = math.floor( math.abs( n ) )
	return PCMod.IPv6.Format( { 0xfe80, 0, 0, 0, 0, 0, math.floor( n / 65536 ) % 65536, n % 65536 } )
end

// Human readable address category (useful for program UIs).
function PCMod.IPv6.AddressType( addr )
	if (!PCMod.IPv6.IsIP( addr )) then return "invalid" end
	if (PCMod.IPv6.IsLoopback( addr )) then return "loopback" end
	if (!string.find( PCMod.IPv6.Normalize( addr ), ":", 1, true )) then return "ipv4" end
	local g = PCMod.IPv6.Expand( addr )
	if (!g) then return "invalid" end
	if ((g[1] == 0) && (g[2] == 0) && (g[3] == 0) && (g[4] == 0) && (g[5] == 0) && (g[6] == 0xffff)) then return "ipv4-mapped" end
	if ((g[1] >= 0xfc00) && (g[1] <= 0xfdff)) then return "unique-local" end
	if ((g[1] >= 0xfe80) && (g[1] <= 0xfebf)) then return "link-local" end
	return "global"
end

// ---------------------------------------------------------------------------------------------------------
// IPv4 hierarchical addressing (mirrors PCMod.IPv6):
//   * the whole internet is one private /8:       10.0.0.0/8
//   * each backbone router owns one /16 block:     10.<hi>.<lo>.0/24
//     (8 global bits + 16 backbone-id bits; hi and lo are the two octets of the
//     16-bit backbone id seen in fd00:<bb>::/32)
//   * each LAN router owns one /32 of that block: 10.<hi>.<lo>.<host>/32
// The /32 is the router's public NAT address: its private LAN (192.168.x.x) is
// hidden behind it, and 10.x traffic routes across the backbones so one router
// can reach another router's /32 (source and/or destination NAT'ed at the edge).
// The 192.168 address space stays LAN-local and overlapping; only 10.x routes.
// ---------------------------------------------------------------------------------------------------------
PCMod.IPv4 = PCMod.IPv4 or {}

// Split a 16-bit backbone id into its two octets (high, low).
function PCMod.IPv4.BackboneOctets( bb )
	local n = tonumber( bb ) or 0
	return math.floor( n / 256 ), n % 256
end

// The IPv4 block of one backbone: 10.<hi>.<lo>.0/24.
function PCMod.IPv4.BackbonePrefix( bb )
	local hi, lo = PCMod.IPv4.BackboneOctets( bb )
	return "10." .. tostring( hi ) .. "." .. tostring( lo ) .. ".0/24"
end

// A single /32 within backbone bb: 10.<hi>.<lo>.<host>. host 1 is the backbone
// router itself (gateway); attached LAN routers get host 2, 3, ...
function PCMod.IPv4.BackboneAddress( bb, host )
	local hi, lo = PCMod.IPv4.BackboneOctets( bb )
	host = tonumber( host ) or 1
	if (host < 1) then host = 1 end
	return "10." .. tostring( hi ) .. "." .. tostring( lo ) .. "." .. tostring( host )
end

// Parse a 10.x backbone IPv4 into { bb = 16-bit backbone id, host = 4th octet }.
// Returns nil for any address not in 10.0.0.0/8.
function PCMod.IPv4.Parse( addr )
	if (type( addr ) != "string") then return nil end
	local a, b, c, d = string.match( addr, "^(%d+)%.(%d+)%.(%d+)%.(%d+)$" )
	if (!a) then return nil end
	a, b, c, d = tonumber( a ), tonumber( b ), tonumber( c ), tonumber( d )
	if ((!a) || (!b) || (!c) || (!d)) then return nil end
	if (a != 10) then return nil end
	return { bb = (b * 256) + c, host = d }
end

// True when addr is in the backbone 10.0.0.0/8 space (routable across backbones).
function PCMod.IPv4.IsBackbone( addr )
	return (PCMod.IPv4.Parse( addr ) != nil)
end

// ---------------------------------------------------------------------------------------------------------
// Count - Returns a count of total characters found in a string
// ---------------------------------------------------------------------------------------------------------
function string.Count( str, char )
	local i
	local s = string.Explode( "", str )
	local r = 0
	for i=1, #s do
		if (s[i] == char) then r = r + 1 end
	end
	return r
end

// ---------------------------------------------------------------------------------------------------------
// AllNumerical - Determines if all keys of a table are numerical or not
// ---------------------------------------------------------------------------------------------------------
function table.AllNumerical( tbl )
	for k, v in pairs( tbl ) do
		if (type(k) != "number") then return false end
	end
	return true
end

// ---------------------------------------------------------------------------------------------------------
// HasKey - Determines if a table has a key or not
// ---------------------------------------------------------------------------------------------------------
function table.HasKey( tbl, key )
	for k, v in pairs( tbl ) do
		if (k == key) then return true end
	end
	return false
end

// ---------------------------------------------------------------------------------------------------------
// MaxVal - Determines the highest numerical value in a table
// ---------------------------------------------------------------------------------------------------------
function table.MaxVal( tbl )
	if (#tbl == 0) then return 0 end
	if (#tbl == 1) then return tbl[1] end
	local vl = tbl[1]
	for _, v in pairs( tbl ) do
		if (v > vl) then vl = v end
	end
	return vl
end

// ---------------------------------------------------------------------------------------------------------
// MinVal - Determines the lowest numerical value in a table
// ---------------------------------------------------------------------------------------------------------
function table.MinVal( tbl )
	if (#tbl == 0) then return 0 end
	if (#tbl == 1) then return tbl[1] end
	local vl = tbl[1]
	for _, v in pairs( tbl ) do
		if (v < vl) then vl = v end
	end
	return vl
end

// ---------------------------------------------------------------------------------------------------------
// TotalVal - Determines the total numerical value in a table
// ---------------------------------------------------------------------------------------------------------
function table.TotalVal( tbl )
	if (#tbl == 0) then return 0 end
	if (#tbl == 1) then return tbl[1] end
	local vl = 0
	for _, v in pairs( tbl ) do
		vl = vl + v
	end
	return vl
end

// ---------------------------------------------------------------------------------------------------------
// PartialVal - Determines the total numerical value in a table up to a point
// ---------------------------------------------------------------------------------------------------------
function table.PartialVal( tbl, upto )
	local cnt = 0
	local res = 0
	if (!upto) then upto = #tbl end
	for cnt=1, upto do
		local v = tbl[ cnt ]
		if (type(v) == "number") then
			res = res + v
		else
			res = res + string.len( tostring( v ) )
		end
	end
	return res
end

// ---------------------------------------------------------------------------------------------------------
// AlphaFlash - Returns a number between two other numbers, smoothly alternating over a time period
// ---------------------------------------------------------------------------------------------------------
function math.AlphaFlash( a, b, tperiod )
	local deca = (CurTime()%tperiod)/tperiod
	local decb = deca
	if (decb>0.5) then decb = 1-decb end
	return math.Mid( a, b, math.Clamp( decb, 0, 1 ) )
end

// ---------------------------------------------------------------------------------------------------------
// Mid - Returns a number between two other numbers, with a certain ratio (rat = 0.5 will get the average)
// ---------------------------------------------------------------------------------------------------------
function math.Mid( old, target, rat )
	return old + ((target-old)*rat)
end

// ---------------------------------------------------------------------------------------------------------
// MidAngle - Returns an angle between two other angles, accounting for wrap (going backwards)
// ---------------------------------------------------------------------------------------------------------
function math.MidAngle( old, target, rat )
	return math.Mid( old:Forward(), target:Forward(), rat ):Angle()
end

// ---------------------------------------------------------------------------------------------------------
// IsOnScreen - Determines if an x,y position is onscreen
// ---------------------------------------------------------------------------------------------------------
function math.IsOnScreen( tbl )
	if ((!tbl.x) || (!tbl.y)) then return false end
	return ((tbl.x > -1) && (tbl.x < ScrW()) && (tbl.y > -1) && (tbl.y < ScrH()))
end

// ---------------------------------------------------------------------------------------------------------
// ViewModelPos - Calculates the view model's position and angles
// ---------------------------------------------------------------------------------------------------------
function PCMod.ViewModelPos( hide, origin, angles )
	if (!hide) then
		local wep = LocalPlayer():GetActiveWeapon()
		if ((!wep) || (!wep:IsValid())) then return { origin, angles } end
		if (!wep.GetViewModelPosition) then return { origin, angles } end
		return { wep:GetViewModelPosition( origin, angles ) } -- Ironsights compatability
	end
	if (PCMod.Gui.Switch_Dir == "to") then
		return { PCMod.Gui.TargetPos + ((PCMod.Gui.TargetAng*-128):Forward()), PCMod.Gui.TargetAng*-1 }
	else
		return { PCMod.Gui.OldPos + ((PCMod.Gui.OldAng*-128):Forward()), PCMod.Gui.OldAng*-1 }
	end
end

// ---------------------------------------------------------------------------------------------------------
// CanQuickType - Can quick type be used or not?
// ---------------------------------------------------------------------------------------------------------
function PCMod.CanQuickType( kb )
	local qt = PCMod.Cfg.QuickType
	if ((!qt) || (qt == 0)) then return false end
	if (qt == 1) then return PCMod.Cfg.DebugMode end
	if (qt == 2) then return PCMod.Cfg.DebugMode || kb end
	if (qt == 3) then return true end
end

// ---------------------------------------------------------------------------------------------------------
// SplitString - Splits a string into equal sized chunks, with a different sized firstchunk
// ---------------------------------------------------------------------------------------------------------
function PCMod.SplitString( str, chunksize, firstchunk )
	// Round 29 (M-13): the undefined global `ca` is gone (it was inserted
	// into the result as the first element - table.insert(t, nil) only sets
	// t[1] = nil, so the result was correct BY ACCIDENT) and the first chunk
	// really has the size `firstchunk` now - before it was only used for the
	// length check. A chunksize below 1 produced an EMPTY result and crashed
	// the caller (umsg.String(nil)).
	if (!str) then return {} end
	if (!chunksize || (chunksize < 1)) then chunksize = 1 end
	if (!firstchunk || (firstchunk < 1)) then firstchunk = chunksize end
	local len = string.len( str )
	if (len < (firstchunk+1)) then
		return { str }
	end
	local tmp = {}
	// the first chunk can have its own size
	table.insert( tmp, string.sub( str, 1, firstchunk ) )
	local pos = firstchunk + 1
	while (pos <= len) do
		table.insert( tmp, string.sub( str, pos, (pos + chunksize - 1) ) )
		pos = pos + chunksize
	end
	// Return it
	return tmp
end

// ---------------------------------------------------------------------------------------------------------
// CompareString - Compares a string against a COMP_ enum
// ---------------------------------------------------------------------------------------------------------
COMP_NUMBER = "1234567890-."
COMP_TEXT = "abcdefghijklmnopqrstuvwxyz"
COMP_NORMAL_CHARS = "()!�$%^&*-_=,./';[]{}#~|`+"
COMP_SPECIAL_CHARS = "\\\"\n"
COMP_ALGEBRA = "+-/*%^"
COMP_TEXT_AND_NUMBERS = COMP_TEXT .. COMP_NUMBER
COMP_TEXT_AND_CHARS = COMP_TEXT .. COMP_NORMAL_CHARS
COMP_TEXT_AND_CHARS_AND_NUMBERS = COMP_TEXT_AND_CHARS .. COMP_NUMBER
function PCMod.CompareString( str, comp )
	local cmp = string.Explode( "", comp )
	local txt = string.Explode( "", str )
	local cnt
	for cnt=1,#txt do
		if (!table.HasValue( cmp, txt[cnt] )) then return false end
	end
	return true
end