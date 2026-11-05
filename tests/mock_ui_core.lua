-- Shared UI geometry, declarative window payload and widget registry.
function table.Copy( t )
	if (type( t ) ~= "table") then return t end
	local o = {}
	for k, v in pairs( t ) do o[ k ] = table.Copy( v ) end
	return o
end

math.Clamp = function( v, a, b ) if (v < a) then return a end if (v > b) then return b end return v end

local function assertTrue( v, m ) if (not v) then error( "FAILED: " .. m, 2 ) end end
local function near( a, b ) return math.abs( a - b ) < 0.0001 end
local function assertNear( a, b, m )
	if (not near( a, b )) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end

PCMod = { Msg = function() end, Cfg = {}, DeviceData = {} }

dofile( "sh_ui_layout.lua" )
dofile( "sh_window.lua" )
dofile( "sv_window_payload.lua" )
dofile( "cl_ui_widgets.lua" )

local UI = PCMod.UI
local r = UI.Rect( 10, 20, 100, 50 )
assertNear( r.x, 10, "rect x" )
assertNear( r.y, 20, "rect y" )
assertNear( r.w, 100, "rect w" )
assertNear( r.h, 50, "rect h" )

local b = UI.Box( r, 0.25, 0.5, 0.5, 0.25 )
assertNear( b.x, 35, "box x" )
assertNear( b.y, 45, "box y" )
assertNear( b.w, 50, "box w" )
assertNear( b.h, 12.5, "box h" )

local rows = UI.SplitRows( r, { 1, 3 }, 0.1 )
assertNear( rows[ 1 ].y, 20, "split row 1 y" )
assertNear( rows[ 1 ].h, 11.25, "split row 1 h" )
assertNear( rows[ 2 ].y, 36.25, "split row 2 y" )
assertNear( rows[ 2 ].h, 33.75, "split row 2 h" )

local cols = UI.SplitColumns( r, 2, 0.2 )
assertNear( cols[ 1 ].w, 40, "equal column 1" )
assertNear( cols[ 2 ].x, 70, "equal column 2 x" )

local inset = UI.Inset( r, 0.1, 0.2, 0.1, 0.2 )
assertNear( inset.x, 20, "inset x" )
assertNear( inset.y, 30, "inset y" )
assertNear( inset.w, 80, "inset w" )
assertNear( inset.h, 30, "inset h" )

-- Window geometry -----------------------------------------------------------
local win = PCMod.Window.New( 0.1, 0.1, 0.62, 0.72, 0.5, 0.6 )
assertNear( win.MinW, 0.5, "window min width" )
assertNear( win.MinH, 0.6, "window min height" )
local w, h = win:ClampSize( 0.1, 0.1 )
assertNear( w, 0.5, "window size min width" )
assertNear( h, 0.6, "window size min height" )
w, h = win:ClampSize( 9, 9, 4, 4 )
assertNear( w, 4, "window size max width" )
assertNear( h, 4, "window size max height" )
local x, y = win:ClampPosition( 5, 5, 0.5, 0.6 )
assertNear( x, 0.5, "window position right clamp" )
assertNear( y, 0.34, "window position taskbar clamp" )
x, y = win:ClampAbsolute( -1, 2 )
assertNear( x, 0, "absolute x clamp" )
assertNear( y, 1, "absolute y clamp" )

win:SetFromDevice( { X = 0.2, Y = 0.3, W = 0.4, H = 0.5 } )
assertNear( win.X, 0.2, "window from device x" )
local dev = {}
win:SetToDevice( dev )
assertNear( dev.W, 0.4, "window to device w" )

-- Declarative payload -------------------------------------------------------
local prog = {
	Name = "demo",
	OS = "personal",
	DeviceLink = "window_demo",
	DeviceName = "window_demo",
	DeviceData = {},
	GetMinWindowSize = function() return 0.55, 0.65 end,
	GetDimensions = function() return { x = 0.1, y = 0.2, w = 0.55, h = 0.65 } end,
	GetPriority = function() return 12 end
}
local payload = PCMod.WindowPayload.Build( prog, {
	Prepare = function( p, data ) data.Hello = "world" end
} )
assertEq = function( a, b, m )
	if (a ~= b) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end
assertEq( payload.Type, "window_demo", "payload type" )
assertEq( payload.Key, "window_demo", "payload key" )
assertEq( payload.Data.Hello, "world", "payload prepare ran" )
assertEq( payload.Data.ProgName, "demo", "payload prog name" )
assertEq( payload.Data.WindowDrag, true, "payload drag" )
assertEq( payload.Data.WindowResize, true, "payload resize" )
assertNear( payload.Data.MinW, 0.55, "payload min width" )
assertNear( payload.X, 0.1, "payload x" )
assertEq( payload.Priority, 12, "payload priority" )
assertTrue( payload.Children == nil, "payload does not carry a GUI tree" )

local server = table.Copy( prog )
server.OS = "server"
local sp = PCMod.WindowPayload.Build( server, {} )
assertEq( sp.Data.WindowDrag, false, "server windows do not drag" )
assertEq( sp.Data.WindowResize, false, "server windows do not resize" )

-- Widget registry -----------------------------------------------------------
local W = PCMod.UI.Widgets
local set = W.NewSet()
local a = { Name = "a" }
local c = { Name = "c" }
W.Add( set, "textbox", a )
W.Add( set, "element", c )
local seen = {}
W.Each( set, { "element", "textbox" }, function( kind, ctrl ) table.insert( seen, kind .. ":" .. ctrl.Name ) end )
assertEq( #seen, 2, "widget each count" )
assertEq( seen[ 1 ], "element:c", "widget order element first" )
assertEq( seen[ 2 ], "textbox:a", "widget order textbox second" )
W.Remove( set, "textbox", a )
assertEq( #set.textbox, 0, "widget remove" )

local painted = false
W.Register( "fake", { Paint = function( d, ctrl ) painted = true end } )
W.Paint( nil, "fake", {} )
assertTrue( painted, "widget paint dispatch" )

print( "UI CORE TESTS PASSED" )
