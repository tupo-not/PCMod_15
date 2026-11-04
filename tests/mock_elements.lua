-- SS element geometry: theme-drawn buttons must follow window dragging.
PCMod = {
    Msg = function() end,
    SDraw = { CFrame = 0, Cursor = nil },
    Cfg = {},
    Gui = {
        Themes = {},
        ThemeDraw = function() return false end,
        GetThemeColour = function() return Color( 0, 0, 0, 255 ) end,
    },
    SSEL = { Bases = {}, BaseLoaded = false },
}
PCMod.SSEL.RegisterBase = function( tbl )
    if PCMod.SSEL.BaseLoaded then return end
    PCMod.SSEL.Bases[ "base" ] = tbl
    PCMod.SSEL.BaseLoaded = true
end
PCMod.SSEL.Register = function( name, tbl )
    PCMod.SSEL.Bases[ name ] = tbl
end

function Color( r, g, b, a ) return { r = r, g = g, b = b, a = a or 255 } end
surface = {
    SetFont = function() end,
    GetTextSize = function( t ) return #tostring( t ) * 6, 10 end,
    SetDrawColor = function() end,
    DrawRect = function() end,
    DrawOutline = function() end,
    SetTexture = function() end,
    DrawTexturedRect = function() end,
}
draw = { SimpleText = function() end }
TEXT_ALIGN_CENTER = 1
TEXT_ALIGN_LEFT = 0

local function assertEq( a, b, m )
    if a ~= b then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end
local function assertTrue( v, m )
    if not v then error( "FAILED: " .. m, 2 ) end
end

dofile( "sselements_base.lua" )
dofile( "sselements_button.lua" )

-- Build a Button instance the same way PCMod.SSEL.Create does (base + subtype).
local btn = {}
for k, v in pairs( PCMod.SSEL.Bases[ "base" ] ) do btn[ k ] = v end
for k, v in pairs( PCMod.SSEL.Bases[ "Button" ] ) do btn[ k ] = v end
btn:OnCreate()
btn:SetTheme( "basic" )
btn:SetLayout( 10, 20, 100, 30 )

local st = btn:GetStruct()
assertEq( st.X, 10, "initial struct x" )
assertEq( st.Y, 20, "initial struct y" )
assertEq( st.W, 100, "initial struct w" )
assertEq( st.H, 30, "initial struct h" )

-- TranslateWindow() calls SetLayout with the moved rectangle.
btn:SetLayout( 50, 60, 100, 30 )
local st2 = btn:GetStruct()
assertTrue( st2 == st, "struct table is reused" )
assertEq( st2.X, 50, "moved struct x" )
assertEq( st2.Y, 60, "moved struct y" )

-- The theme hook must receive the live rectangle on every paint.
local seen
PCMod.Gui.ThemeDraw = function( theme, id, struct )
    if id == "button" then seen = struct end
    return true
end
btn:SetLayout( 90, 110, 100, 30 )
btn:Paint()
assertTrue( seen ~= nil, "theme button hook ran" )
assertEq( seen.X, 90, "theme sees moved x" )
assertEq( seen.Y, 110, "theme sees moved y" )

-- Hover only belongs to the topmost device under the cursor.
PCMod.SDraw.Cursor = { X = 100, Y = 120, Ent = 1, Frame = 0, HoverDevID = "high" }
btn.DEVICE = { EntID = 1, SSDevice = { DevID = "high" } }
btn:SetLayout( 90, 110, 100, 30 )
btn:Paint()
assertTrue( seen.Hover == true, "hover on top device" )
PCMod.SDraw.Cursor.HoverDevID = "low"
btn:Paint()
assertTrue( seen.Hover == false, "no hover through another window" )

print( "ELEMENT GEOMETRY TESTS PASSED" )
