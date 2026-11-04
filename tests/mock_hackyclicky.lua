-- HackyClicky click-catcher layout: the panel must cover the whole screen
-- unless the on-screen keyboard is actually visible.
local registered = {}
vgui = {
    Register = function( name, panel, base ) registered[ name ] = panel end,
    Create = function() return nil end,
}
concommand = { Add = function() end }
hook = { Add = function() end }
usermessage = { Hook = function() end }
PCMod = { Msg = function() end, Gui = {} }
function Color( r, g, b, a ) return { r = r, g = g, b = b, a = a or 255 } end
surface = {
    SetTexture = function() end, SetDrawColor = function() end,
    DrawTexturedRect = function() end, DrawRect = function() end,
    DrawLine = function() end,
}
draw = { SimpleText = function() end }
math.Mid = function( a, b, t ) return a + (b - a) * t end
ScrW = function() return 1600 end
ScrH = function() return 900 end

local function assertEq( a, b, m )
    if a ~= b then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end

dofile( "cl_vgui.lua" )

local PANEL = registered[ "HackyClicky" ]
assert( PANEL and PANEL.PerformLayout, "HackyClicky registered" )

local p = {}
function p:SetSize( w, h ) self.W, self.H = w, h end
function p:SetPos( x, y ) self.X, self.Y = x, y end
function p:SetText() end

-- Hidden keyboard: full-screen click-catcher (taskbar / Start clickable).
PCMod.Gui.KeyBoard = {
    IsVisible = function() return false end,
    GetTall = function() return 184 end,
}
PANEL.PerformLayout( p )
assertEq( p.W, 1600, "hidden keyboard width" )
assertEq( p.H, 900, "hidden keyboard height covers taskbar" )
assertEq( p.X, 0, "hidden keyboard x" )
assertEq( p.Y, 0, "hidden keyboard y" )

-- Visible keyboard: reserve its height so keys keep receiving clicks.
PCMod.Gui.KeyBoard.IsVisible = function() return true end
PANEL.PerformLayout( p )
assertEq( p.H, 900 - 184, "visible keyboard height" )

-- No keyboard panel at all (partial reload): still full screen.
PCMod.Gui.KeyBoard = nil
PANEL.PerformLayout( p )
assertEq( p.H, 900, "missing keyboard height" )

print( "HACKYCLICKY TESTS PASSED" )
