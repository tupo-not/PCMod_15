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

-- ShowLockFrame: dark device-menu redesign (header + icon rows + footer + X)
local function assertTrue( v, m ) if (not v) then error( "FAILED: " .. m, 2 ) end end
local createdPanels = {}
local function mockMenuPanel( class )
	local p = { class = class, _valid = true, W = 300, H = 200, children = {} }
	function p:SetPos( x, y ) self.X, self.Y = x, y end
	function p:SetSize( w, h ) self.W, self.H = w, h end
	function p:SetTitle( t ) self.Title = t end
	function p:SetDraggable( b ) self.Draggable = b end
	function p:ShowCloseButton( b ) end
	function p:SetParent( par ) table.insert( par.children, self ) self.parent = par end
	function p:SetText( t ) self.Text = t end
	function p:GetWide() return self.W end
	function p:GetTall() return self.H end
	function p:Remove() self._valid = false end
	function p:IsValid() return self._valid end
	function p:IsHovered() return false end
	return p
end
vgui.Create = function( class ) local p = mockMenuPanel( class ) table.insert( createdPanels, p ) return p end

function math.Clamp( v, a, b ) if (v < a) then return a end if (v > b) then return b end return v end
TEXT_ALIGN_LEFT = 0
TEXT_ALIGN_CENTER = 1
function RunConsoleCommand() end
function LocalPlayer() return {} end
PCMod.SDraw = { KeyboardEntID = 0 }
PCMod.Beam = { UnlockCam = function() end }
local laptopEnt = { _valid = true, GetClass = function() return "pcmod_laptop" end }
local towerEnt = { _valid = true, GetClass = function() return "pcmod_tower" end }
ents = { GetByIndex = function( i ) return ents._cur end }
function IsValid( e ) return (e != nil) and (e._valid == true) end
surface.DrawOutlinedRect = function() end
local menuTexts = {}
draw.SimpleText = function( txt, ... ) table.insert( menuTexts, tostring( txt ) ) end
draw.RoundedBox = function() end

-- laptop: Clipboard + Toggle Power rows; X button; header/footer texts
ents._cur = laptopEnt
PCMod.Gui.CamLockID = 5
PCMod.Gui.ShowLockFrame( true )
local frame = PCMod.Gui.LFrame
assert( frame ~= nil, "lock frame created" )
assertEq( frame.Title, "", "no legacy title bar (custom header)" )
assertTrue( frame.Draggable == true, "lock frame is draggable" )
assertEq( #frame.children, 3, "X button + 2 rows on a laptop" )
menuTexts = {}
frame:Paint( frame.W, frame.H )
assertTrue( table.concat( menuTexts, "|" ):find( "PCMod", 1, true ) ~= nil, "header title is PCMod" )
assertTrue( table.concat( menuTexts, "|" ):find( "PCMod 1.5", 1, true ) == nil, "no version suffix in title" )
assertTrue( table.concat( menuTexts, "|" ):find( "Computer controls", 1, true ) ~= nil, "header subtitle" )
assertTrue( table.concat( menuTexts, "|" ):find( "Device menu", 1, true ) ~= nil, "footer label" )
menuTexts = {}
for _, ch in ipairs( frame.children ) do if (ch.Paint and ch.class == "DButton" and ch ~= frame.children[ 1 ]) then ch:Paint( ch.W, ch.H ) end end
local rowText = table.concat( menuTexts, "|" )
assertTrue( rowText:find( "Clipboard", 1, true ) ~= nil, "clipboard row" )
assertTrue( rowText:find( "Toggle Power", 1, true ) ~= nil, "power row on laptop" )
-- X button is first child
assertTrue( frame.children[ 1 ].DoClick ~= nil, "X close button has a handler" )
-- hide removes the frame
PCMod.Gui.ShowLockFrame( false )
assertTrue( PCMod.Gui.LFrame == nil, "frame removed on hide" )
assertTrue( frame._valid == false, "frame panel removed" )

-- tower: only the Clipboard row
ents._cur = towerEnt
PCMod.Gui.ShowLockFrame( true )
assertEq( #PCMod.Gui.LFrame.children, 2, "X + Clipboard row only on a tower" )
PCMod.Gui.ShowLockFrame( false )

print( "HACKYCLICKY TESTS PASSED" )
