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
local ss = { Data = devices }
function ss:MakeDevice( name, x, y, w, h, dat, prio )
	local d = { Name = name, Type = name, Data = dat, Priority = prio, X = x, Y = y, W = w, H = h }
	devices[ name ] = d
	return d
end
function ss:AddDevice( key, dev ) devices[ key ] = dev end
function ss:RemoveDevice( key ) devices[ key ] = nil end
function ss:GetDevice( key ) return devices[ key ] end

prog.GetScreenSpace = function() return ss end
prog.SetScreenSpace = function() end
prog.GetDimensions = function() return { x = 0.1, y = 0.1, w = 0.8, h = 0.8 } end
prog.GetOS = function()
	return {
		GetTheme = function() return "basic" end,
		OpenNetPort = function() end,
		CloseNetPort = function() end,
		SendNetMessage = function() end,
	}
end

-- The connection form keeps its own device key, but the window manager finds
-- the active window by its program owner, so it can be dragged.
prog:UpdateSS()
local connect = devices[ prog.ConnectKey ]
assertTrue( connect ~= nil, "connect window created with its own key" )
assertEq( connect.Type, "window_chatserv_connect", "connect window type" )
assertEq( connect.Data.ProgName, "chatserv", "connect window knows its program" )
assertTrue( connect.Data.WindowDrag, "connect window can be dragged" )
assertTrue( connect.Data.WindowResize, "connect window can be resized" )
local active = prog:GetWindowDevice()
assertTrue( active ~= nil, "window manager finds the connect window" )
assertEq( active.Type, "window_chatserv_connect", "active window is the connect form" )

prog.State = 2
prog:TriggerState( 2 )
local chat = devices[ prog.DeviceName ]
assertTrue( chat ~= nil, "chat window created" )
assertEq( chat.Type, "window_chatserv", "chat window type replaces the connect form" )
assertEq( chat.Data.ProgName, "chatserv", "chat window knows its program" )
assertTrue( chat.Data.WindowDrag, "chat window can be dragged" )
assertTrue( chat.Data.WindowResize, "chat window can be resized" )
assertEq( prog:GetWindowDevice().Type, "window_chatserv", "active window is the chat" )

-- Going back to the connection form must rebuild the connect device rather
-- than leaving the chat instance in place.
prog.State = 1
prog:TriggerState( 1 )
local reconnect = devices[ prog.ConnectKey ]
assertTrue( reconnect ~= nil, "connect window restored after disconnect" )
assertEq( reconnect.Type, "window_chatserv_connect", "connect type restored" )
assertEq( prog:GetWindowDevice().Type, "window_chatserv_connect", "active window is the connect form again" )

print( "CHATSERV TESTS PASSED" )
