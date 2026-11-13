-- Beam transport: entity data broadcasts explicitly, and small/large payloads
-- use the correct delivery path.
SERVER = true
CLIENT = false
util = { AddNetworkString = function() end }
net = {
	log = {},
	Start = function( name ) net.channel = name end,
	WriteString = function() end,
	WriteUInt = function() end,
	Send = function( ply )
		net.sent = ply
		table.insert( net.log, { name = net.channel, ply = ply } )
	end,
	Broadcast = function()
		net.broadcast = true
		table.insert( net.log, { name = net.channel, ply = nil } )
	end,
}
umsg = {
	log = {},
	Start = function( name, ply ) table.insert( umsg.log, { name = name, ply = ply } ) end,
	String = function() end,
	Short = function() end,
	End = function() end,
}
player = { GetAll = function() return {} end }
hook = { Add = function() end }
concommand = { Add = function() end }
timer = { Simple = function() end }
PCMod = {
	Msg = function() end,
	Warning = function() end,
	Cfg = {},
	TableToString = function() return "json" end,
	SplitString = function( str, size )
		local out = {}
		for i = 1, #str do table.insert( out, string.sub( str, i, i ) ) end
		return out
	end,
}

dofile( "pcmod_sh_beam.lua" )

local function assertEq( a, b, msg )
	if (a ~= b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function assertTrue( v, msg )
	if (not v) then error( "FAILED: " .. msg, 2 ) end
end

-- Entity data is global: setting it must broadcast, not silently target nil.
net.broadcast = false
net.sent = nil
PCMod.Beam.SetEntData( 7, "wireless", true )
assertTrue( net.broadcast, "SetEntData broadcasts to every client" )
assertEq( net.sent, nil, "SetEntData does not target a single player" )
assertEq( PCMod.EntData[ 7 ].wireless, true, "entity data stored" )

-- An unchanged value is not sent again.
net.broadcast = false
PCMod.Beam.SetEntData( 7, "wireless", true )
assertTrue( not net.broadcast, "unchanged entity data is not resent" )

-- Clearing it also broadcasts.
net.broadcast = false
PCMod.Beam.ClearEntData( 7 )
assertTrue( net.broadcast, "ClearEntData broadcasts" )
assertEq( PCMod.EntData[ 7 ].wireless, nil, "entity data cleared" )

-- A targeted string goes only to that player.
net.broadcast = false
net.sent = nil
PCMod.Beam.BeamString( "player1", "tag", "hello" )
assertEq( net.channel, "pcmod_stringhook", "small strings use the net channel" )
assertEq( net.sent, "player1", "small strings target one player" )
assertTrue( not net.broadcast, "small targeted strings do not broadcast" )

-- Large strings use the chunked net path (start + segments), not usermsg.
PCMod.Beam.MaxString = 1
net.log = {}
net.broadcast = false
PCMod.Beam.BeamString( nil, "tag", "ab" )
assertEq( #net.log, 2, "a 2-chunk payload emits start + one segment" )
assertEq( net.log[ 1 ].name, "pcmod_stringstart", "chunked start channel" )
assertEq( net.log[ 2 ].name, "pcmod_stringseg", "chunked segment channel" )
assertEq( net.log[ 1 ].ply, nil, "chunked broadcast has no recipient" )
assertTrue( net.broadcast, "chunked payload broadcasts" )

print( "mock_beam PASSED" )
