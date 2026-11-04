-- Notepad font settings: client-side family/scale + font registration.
PCMod = {
    Msg = function() end,
    NP = {},
    Gui = {
        GetFontSize = function( base ) return base end,
    },
}
function math.Clamp( v, lo, hi )
    if (v < lo) then return lo end
    if (v > hi) then return hi end
    return v
end
function CurTime() return 1 end
local created = {}
surface = {
    CreateFont = function( name, info ) created[ name ] = info end,
}
DEV = {}
function DEV:Int_Reinitialize() end
dofile( "pcmod_notepad_ui.lua" )

local function assertEq( a, b, m )
    if (a ~= b) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end
local function assertTrue( v, m )
    if (not v) then error( "FAILED: " .. m, 2 ) end
end

assertEq( DEV:GetFontFamily(), "Tahoma", "default notepad font family" )
assertEq( DEV:GetFontScale(), 100, "default notepad font scale" )

PCMod.NP.FontFamily = "Courier New"
PCMod.NP.FontScale = 150
assertEq( DEV:GetFontFamily(), "Courier New", "configured family" )
assertEq( DEV:GetFontScale(), 150, "configured scale" )

PCMod.NP.FontFamily = "Not A Font"
assertEq( DEV:GetFontFamily(), "Tahoma", "unknown family falls back" )

PCMod.NP.FontScale = 5
assertEq( DEV:GetFontScale(), 50, "scale clamps low" )
PCMod.NP.FontScale = 999
assertEq( DEV:GetFontScale(), 300, "scale clamps high" )

local name = DEV:GetEditorFontName()
assertTrue( created[ name ] ~= nil, "editor font registered" )
assertEq( created[ name ].font, "Tahoma", "fallback family registered" )
assertEq( created[ name ].size, 60, "font size follows scale" )
assertEq( DEV:GetEditorFontName(), name, "font name is reused" )

-- The browse button is square and the filename textbox ends before it.
local fl = DEV:GetFilenameRowLayout( 0, 0, 1000, 600 )
assertEq( fl.BtnW, fl.BtnH, "browse button is square" )
assertTrue( (fl.TbX + (fl.TbW * 0.5)) <= fl.BtnX, "filename textbox ends before browse button" )
assertTrue( (fl.BtnX + fl.BtnW) <= 1000 * (1 - 0.035), "browse button stays left of the resize grip" )
assertTrue( fl.TbX - (fl.TbW * 0.5) >= 0, "filename textbox stays inside the window" )

-- A failed save must not replace the editor with the last-saved server data.
local values = { txtMain = "unsaved text", txtFilename = "newname.txt" }
DEV.Textboxes = { txtMain = {}, txtFilename = {} }
function DEV:SetTextboxFont() end
function DEV:SetTextboxText( name, text ) values[ name ] = text end
DEV.SaveFailed = true
DEV.TC = "old saved text"
DEV.FN = "oldname.txt"
DEV.St = 6
DEV:OnUpdate()
assertEq( values.txtMain, "unsaved text", "failed save preserves editor text" )
assertEq( values.txtFilename, "newname.txt", "failed save preserves filename" )
assertEq( DEV.Status, "Save failed: file or folder is locked.", "failed save status" )
DEV.SaveFailed = false
DEV:OnUpdate()
assertEq( values.txtMain, "old saved text", "normal update applies server text" )
assertEq( values.txtFilename, "oldname.txt", "normal update applies server filename" )

print( "ALL NOTEPAD UI TESTS PASSED" )
