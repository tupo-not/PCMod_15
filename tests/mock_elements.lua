-- SS element geometry: theme-drawn buttons must follow window dragging.
PCMod = {
    Msg = function() end,
    SDraw = { CFrame = 0, Cursor = nil },
    Cfg = {},
    Gui = {
        Themes = {},
        ThemeDraw = function() return false end,
        GetThemeColour = function( theme, key, default ) return default or Color( 0, 0, 0, 255 ) end,
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
    SetDrawColor = function( r, g, b, a )
        lastColor = { r = r, g = g, b = b, a = a }
        table.insert( colorHistory, lastColor )
    end,
    DrawRect = function( x, y, w, h )
        table.insert( paintedRects, { x = x, y = y, w = w, h = h } )
    end,
    DrawOutline = function() end,
    SetTexture = function() end,
    DrawTexturedRect = function( x, y, w, h )
        lastIcon = { x = x, y = y, w = w, h = h }
    end,
}
paintedRects = {}
draw = { SimpleText = function( text, font, x, y, col, align )
    lastLabel = { text = text, font = font, x = x, y = y, col = col, align = align }
end }
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

-- Labels are fitted against the live rect without changing its hit-box.
local fitArgs
PCMod.Gui.GetFittedFont = function( text, font, maxW, maxH )
    fitArgs = { text = text, font = font, maxW = maxW, maxH = maxH }
    return "fitted-font"
end
btn:SetLayout( 90, 110, 100, 30 )
btn:Paint()
assertTrue( fitArgs ~= nil, "button asks the shared fitter for its label" )
assertEq( fitArgs.maxW, 96, "button leaves horizontal padding" )
assertEq( fitArgs.maxH, 28, "button leaves vertical padding" )
assertEq( lastLabel.font, "fitted-font", "button draws with the fitted font" )
assertEq( btn.W, 100, "font fitting does not change button width" )
assertEq( btn.H, 30, "font fitting does not change button height" )

-- Taskbar-specific rendering: left icon/label, active rail and dim minimized text.
colorHistory = {}
PCMod.Res = { Mats = { [ "gui/icons/ico_app" ] = 1 } }
btn.HasIcon = true
btn.Icon = "app"
btn.TaskbarRole = "running"
btn.Active = true
btn.TaskMinimized = false
btn:SetLayout( 10, 20, 100, 30 )
btn:Paint()
assertEq( lastLabel.x, 42, "taskbar label sits after the icon" )
assertEq( lastLabel.align, TEXT_ALIGN_LEFT, "taskbar label is left aligned" )
assertTrue( lastIcon ~= nil and lastIcon.x == 12 and lastIcon.y == 22 and lastIcon.w == 26 and lastIcon.h == 26, "taskbar icon uses a compact padded square" )
local iconTint = colorHistory[ #colorHistory - 1 ]
assertEq( iconTint.r, 255, "icon tint falls back to white instead of Basic black text" )
assertEq( iconTint.g, 255, "icon tint fallback stays neutral" )
assertEq( iconTint.b, 255, "white icon fallback is not derived from button text" )
local rail = paintedRects[ #paintedRects ]
assertTrue( rail ~= nil and rail.y == 48 and rail.h == 2 and rail.w == 100, "active taskbar button has a bottom accent rail" )
PCMod.Gui.GetThemeColour = function( theme, key, default )
    if key == "Button_Text_Locked" then return { r = 111, g = 112, b = 113, a = 255 } end
    if key == "Icon_Tint" then return default end
    return Color( 0, 0, 0, 255 )
end
btn.TaskMinimized = true
btn:Paint()
assertEq( lastLabel.col.r, 111, "minimized label uses the locked/dim text colour" )
iconTint = colorHistory[ #colorHistory - 1 ]
assertEq( iconTint.r, 111, "minimized icon is dimmed independently of normal icon tint" )
btn.TaskbarRole = nil
btn.TaskMinimized = false
btn:Paint()
assertEq( lastColor.r, 255, "ordinary All Programs icons also use the white fallback" )

print( "ELEMENT GEOMETRY TESTS PASSED" )
