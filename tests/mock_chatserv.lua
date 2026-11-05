-- ChatServ window-manager payload test.
function table.Copy( t )
	if (type( t ) ~= "table") then return t end
	local o = {}
	for k, v in pairs( t ) do o[ k ] = table.Copy( v ) end
	return o
end

math.Clamp = function( v, a, b ) if (v < a) then return a end if (v > b) then return b end return v end

local function assertTrue( v, m ) if (not v) then error( "FAILED: " .. m, 2 ) end end
local function assertEq( a, b, m )
	if (a ~= b) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end

PCMod = { Msg = function() end, Cfg = { StatusCodes = {} } }
dofile( "sh_window.lua" )
dofile( "sv_window_payload.lua" )

PROG = {}
dofile( "pcmod_base.lua" )
dofile( "pcmod_chatserv.lua" )

local prog = table.Copy( PROG )
prog.Name = "chatserv"
prog.OS = "personal"
prog.State = 1
prog.ZOrder = 10
prog.DeviceData = {}

local devices = {}
local ss = {}
function ss:MakeDevice( name, x, y, w, h, dat, prio )
	local d = { Name = name, Data = dat, Priority = prio }
	devices[ name ] = d
	return d
end
function ss:AddDevice( key, dev ) devices[ key ] = dev end
function ss:RemoveDevice( key ) devices[ key ] = nil end

prog.GetScreenSpace = function() return ss end
prog.SetScreenSpace = function() end
prog.GetDimensions = function() return { x = 0.1, y = 0.1, w = 0.8, h = 0.8 } end
prog.GetOS = function() return { GetTheme = function() return "basic" end } end

prog:UpdateSS()
assertTrue( devices.window_chatserv_connect ~= nil, "connect window created" )
assertEq( devices.window_chatserv_connect.Data.ProgName, "chatserv", "connect window knows its program" )
assertTrue( devices.window_chatserv_connect.Data.WindowDrag, "connect window can be dragged" )
assertTrue( devices.window_chatserv_connect.Data.WindowResize, "connect window can be resized" )

prog.State = 2
prog:UpdateSS()
assertTrue( devices.window_chatserv ~= nil, "chat window created" )
assertEq( devices.window_chatserv.Data.ProgName, "chatserv", "chat window knows its program" )
assertTrue( devices.window_chatserv.Data.WindowDrag, "chat window can be dragged" )
assertTrue( devices.window_chatserv.Data.WindowResize, "chat window can be resized" )

print( "CHATSERV TESTS PASSED" )
