-- Control-aware font fitting and cache behaviour.
PCMod = {
	Gui = {
		Fonts = {},
		GetFontSize = function() return 20 end,
	},
}
local fonts = {
	pcmod_3d2d = { size = 20, weight = 400 },
	pcmod15_button = { size = 20, weight = 700 },
}
local current = fonts.pcmod_3d2d
local createCount = 0
surface = {
	CreateFont = function( name, data )
		fonts[ name ] = data
		createCount = createCount + 1
	end,
	SetFont = function( name ) current = fonts[ name ] end,
	GetTextSize = function( text )
		if (!current) then return nil end
		return math.floor( (#tostring( text ) * current.size * 0.6) + 0.5 ), current.size
	end,
}
dofile( "cl_textfit.lua" )
PCMod.Gui.InitTextFitFonts()

local function assertEq( a, b, msg )
	if (a ~= b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function assertTrue( v, msg ) if (!v) then error( "FAILED: " .. msg, 2 ) end end

local text = "Set PCMod 1.5 Theme"
local initializedCount = createCount
assertEq( PCMod.Gui.GetFittedFont( text, "pcmod15_button", 400, 30 ), "pcmod15_button", "large rect keeps the theme font" )
assertEq( createCount, initializedCount, "large rect creates no font during paint" )

local fitted = PCMod.Gui.GetFittedFont( text, "pcmod15_button", 180, 14 )
assertEq( fitted, "pcmod_fit_pcmod15_button_14", "label shrinks to fit its rect" )
assertEq( fonts[ fitted ].weight, 700, "PCMod 1.5 bold weight is preserved" )
assertEq( PCMod.Gui.Fonts[ fitted ], true, "fitted font is registered for draw" )
local afterFit = createCount
assertEq( PCMod.Gui.GetFittedFont( text, "pcmod15_button", 180, 14 ), fitted, "identical rect uses cache" )
assertEq( createCount, afterFit, "cache hit creates no font" )

local smaller = PCMod.Gui.GetFittedFont( text, "pcmod_3d2d", 100, 10 )
assertTrue( fonts[ smaller ] && fonts[ smaller ].size <= 10, "smaller rect selects a smaller font" )
assertEq( fonts[ smaller ].weight, 400, "stock font weight is preserved" )
PCMod.Gui.ResetTextFitCache()
local afterReset = createCount
assertEq( PCMod.Gui.GetFittedFont( text, "pcmod15_button", 180, 14 ), fitted, "reset only clears measurement cache" )
assertEq( createCount, afterReset, "font objects are not recreated after cache reset" )
assertEq( PCMod.Gui.GetFittedFont( text, "pcmod15_button", 0, 14 ), "pcmod15_button", "invalid rect falls back safely" )

print( "mock_textfit PASSED" )
