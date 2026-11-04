-- Browser program: URL parsing + navigation command (plain Lua after translation).
function string.Trim( s )
	return (string.gsub( s, "^%s*(.-)%s*$", "%1" ))
end
function string.Left( s, n ) return string.sub( s, 1, n ) end
function string.Right( s, n ) return string.sub( s, math.max( 1, #s - n + 1 ) ) end
function string.Explode( sep, str )
	local out = {}
	if (str == nil) then return out end
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
function table.Copy( t )
	if (type( t ) ~= "table") then return t end
	local o = {}
	for k, v in pairs( t ) do o[ k ] = table.Copy( v ) end
	return o
end
function CurTime() return 0 end

PCMod = {
	Msg = function() end,
	Data = {},
	Cfg = {},
	IPv6 = { IsIP = function( addr ) return (addr == "192.168.0.1") end },
}
util = { Compress = function( s ) return s end }

local sent = {}
local os = {}
function os:OpenNetPort() end
function os:CloseNetPort() end
function os:SendNetMessage( addr, port, body ) sent = { addr = addr, port = port, body = body } end

PROG = {}
dofile( "pcmod_base.lua" )
local base = table.Copy( PROG )
PROG = table.Copy( base )
dofile( "pcmod_browser.lua" )
local prog = table.Copy( PROG )
prog.DeviceData = {}
prog.UpdateSS = function() end
prog.GetOS = function() return os end

local function assertEq( a, b, m )
	if (a ~= b) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end

local addr, path = prog:ParseUrl( "http://192.168.0.1/status" )
assertEq( addr, "192.168.0.1", "scheme stripped" )
assertEq( path, "/status", "path kept" )

addr, path = prog:ParseUrl( "  fd00:1:0:1::1  " )
assertEq( addr, "fd00:1:0:1::1", "whitespace trimmed" )
assertEq( path, "", "no path" )

addr, path = prog:ParseUrl( "https://192.168.0.1" )
assertEq( addr, "192.168.0.1", "https stripped to address only" )

prog:DoCommand( "go", { "192.168.0.1" } )
assertEq( sent.addr, "192.168.0.1", "go sends to address" )
assertEq( sent.port, 80, "go uses port 80" )
assertEq( sent.body[1], "http", "go sends an http request" )

prog:DoCommand( "go", { "10.0.0.9" } ) -- not validated as routable by the stub
assertEq( prog.DeviceData.Status, "Invalid address.", "unknown address rejected" )

-- Relative links resolve against the last-visited address.
prog:DoCommand( "go", { "?wireless=0" } )
assertEq( sent.addr, "192.168.0.1", "relative link resolves to current address" )
assertEq( sent.body[2], "?wireless=0", "relative query preserved" )

prog:ProcessPacket( 80, { "http-response", "hello world" }, {} )
assertEq( prog.DeviceData.Content, "hello world", "response content stored" )

print( "ALL BROWSER TESTS PASSED" )