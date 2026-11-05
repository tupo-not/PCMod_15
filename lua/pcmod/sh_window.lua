// ---------------------------------------------------------------------------------------------------------
// sh_window.lua - Shared
// One geometry model for program windows and screen-space window devices.
//
// The wire format stays exactly X/Y/W/H (viewport fractions). This module only
// centralises the clamping/minimum/maximum rules so the server program and the
// client device cannot disagree about them.
// ---------------------------------------------------------------------------------------------------------

PCMod.Window = {}
local Window = PCMod.Window

Window.DefaultW = 0.62
Window.DefaultH = 0.72
Window.DefaultMinW = 0.5
Window.DefaultMinH = 0.6
Window.DefaultMaxW = 4
Window.DefaultMaxH = 4
Window.Taskbar = 0.94

local MT = { __index = Window }

function Window.New( x, y, w, h, minW, minH )
	local o = setmetatable( {}, MT )
	o:Set( x, y, w, h )
	o:SetMin( minW, minH )
	return o
end

function Window:Set( x, y, w, h )
	if (x != nil) then self.X = tonumber( x ) or self.X or 0 end
	if (y != nil) then self.Y = tonumber( y ) or self.Y or 0 end
	if (w != nil) then self.W = tonumber( w ) or self.W or Window.DefaultW end
	if (h != nil) then self.H = tonumber( h ) or self.H or Window.DefaultH end
	return self
end

function Window:Get()
	return self.X or 0, self.Y or 0, self.W or Window.DefaultW, self.H or Window.DefaultH
end

function Window:SetMin( minW, minH )
	self.MinW = math.Clamp( tonumber( minW ) or Window.DefaultMinW, 0.05, 1 )
	self.MinH = math.Clamp( tonumber( minH ) or Window.DefaultMinH, 0.05, 1 )
	return self
end

function Window:SetMax( maxW, maxH )
	self.MaxW = tonumber( maxW ) or Window.DefaultMaxW
	self.MaxH = tonumber( maxH ) or Window.DefaultMaxH
	return self
end

// Clamp a requested size. maxW/maxH default to the instance limits. When the
// caller's available space is below the nominal minimum (a window dragged into
// a corner), the minimum is reduced to the available space instead of pushing
// the window past the edge.
function Window:ClampSize( w, h, maxW, maxH )
	local mw = self.MinW or Window.DefaultMinW
	local mh = self.MinH or Window.DefaultMinH
	local xw = tonumber( maxW ) or self.MaxW or Window.DefaultMaxW
	local xh = tonumber( maxH ) or self.MaxH or Window.DefaultMaxH
	local loW = math.min( mw, xw )
	local loH = math.min( mh, xh )
	return math.Clamp( tonumber( w ) or self.W or loW, loW, xw ),
		math.Clamp( tonumber( h ) or self.H or loH, loH, xh )
end

function Window:SetSize( w, h, maxW, maxH )
	self.W, self.H = self:ClampSize( w, h, maxW, maxH )
	return self
end

// Clamp a position for the visible window size (already multiplied by GUI
// scale). The taskbar reserves the bottom of the viewport.
function Window:ClampPosition( x, y, visW, visH, taskbar )
	local vw = tonumber( visW ) or self.W or 0
	local vh = tonumber( visH ) or self.H or 0
	local tb = tonumber( taskbar ) or self.Taskbar or 0.94
	local nx = math.Clamp( tonumber( x ) or self.X or 0, 0, math.max( 0, 1 - vw ) )
	local ny = math.Clamp( tonumber( y ) or self.Y or 0, 0, math.max( 0, tb - vh ) )
	return nx, ny
end

function Window:SetPosition( x, y, visW, visH, taskbar )
	self.X, self.Y = self:ClampPosition( x, y, visW, visH, taskbar )
	return self
end

// The server intentionally only keeps program positions in absolute bounds;
// GUI scale is client-side and may legitimately put a scaled window nearer
// the edge than 1 - W.
function Window:ClampAbsolute( x, y )
	return math.Clamp( tonumber( x ) or self.X or 0, 0, 1 ),
		math.Clamp( tonumber( y ) or self.Y or 0, 0, 1 )
end

function Window:SetFromDevice( dev )
	if ((!dev) || (type( dev ) != "table")) then return self end
	return self:Set( dev.X, dev.Y, dev.W, dev.H )
end

function Window:SetToDevice( dev )
	if ((!dev) || (type( dev ) != "table")) then return self end
	dev.X, dev.Y, dev.W, dev.H = self:Get()
	return self
end
