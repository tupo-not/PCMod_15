// ---------------------------------------------------------------------------------------------------------
// cl_textfit.lua - Fit labels inside their current control rectangles
// ---------------------------------------------------------------------------------------------------------
PCMod.Gui = PCMod.Gui or {}

local MAX_CACHE = 512
local fitCache = {}
local fitCacheOrder = {}
local fitFonts = {}

local function CacheFont( key, font )
	if (!fitCache[ key ]) then table.insert( fitCacheOrder, key ) end
	fitCache[ key ] = font
	while (#fitCacheOrder > MAX_CACHE) do
		local old = table.remove( fitCacheOrder, 1 )
		fitCache[ old ] = nil
	end
	return font
end

function PCMod.Gui.ResetTextFitCache()
	fitCache = {}
	fitCacheOrder = {}
end

// Quantized sizes keep the font set bounded at every GUI scale.
local FIT_SIZES = { 6, 8, 10, 12, 14, 16, 18, 20, 24, 28, 32, 40, 48, 64, 80, 96, 128, 160, 192, 256 }

// Create the bounded font set during initialization, never in a render hook.
// Names include the pixel size, so GUI-scale changes simply add a new bounded set.
function PCMod.Gui.InitTextFitFonts()
	PCMod.Gui.Fonts = PCMod.Gui.Fonts or {}
	local baseSize = PCMod.Gui.GetFontSize( 20 )
	local variants = {
		{ font = "pcmod_3d2d", weight = 400 },
		{ font = "pcmod15_button", weight = 700 },
		{ font = "pcmod15_caption", weight = 700 },
	}
	for _, variant in ipairs( variants ) do
		for _, size in ipairs( FIT_SIZES ) do
			if (size <= baseSize) then
				local name = "pcmod_fit_" .. variant.font .. "_" .. tostring( size )
				if (!fitFonts[ name ]) then
					surface.CreateFont( name, { font = "Tahoma", size = size, weight = variant.weight } )
					fitFonts[ name ] = true
				end
				PCMod.Gui.Fonts[ name ] = true
			end
		end
	end
end

// Return the original font when it fits, or the largest smaller pre-created
// variant that fits both dimensions. Cache is bounded for live window resizes.
local function SmallestFit( font )
	for _, size in ipairs( FIT_SIZES ) do
		local name = "pcmod_fit_" .. tostring( font ) .. "_" .. tostring( size )
		if (fitFonts[ name ]) then return name end
	end
	return font
end

function PCMod.Gui.GetFittedFont( text, font, maxW, maxH )
	if ((text == nil) || (text == "")) then return font end
	font = font || "pcmod_3d2d"
	maxW = math.floor( tonumber( maxW ) || 0 )
	maxH = math.floor( tonumber( maxH ) || 0 )
	if ((maxW <= 0) || (maxH <= 0)) then return SmallestFit( font ) end

	local key = tostring( font ) .. "|" .. tostring( text ) .. "|" .. maxW .. "|" .. maxH
	local cached = fitCache[ key ]
	if (cached) then return cached end

	text = tostring( text )
	surface.SetFont( font )
	local tw, th = surface.GetTextSize( text )
	if ((tw != nil) && (th != nil) && (tw <= maxW) && (th <= maxH)) then
		return CacheFont( key, font )
	end

	local baseSize = PCMod.Gui.GetFontSize( 20 )
	local best
	for i = #FIT_SIZES, 1, -1 do
		local size = FIT_SIZES[ i ]
		if (size <= baseSize) then
			local name = "pcmod_fit_" .. tostring( font ) .. "_" .. tostring( size )
			if (fitFonts[ name ]) then
				surface.SetFont( name )
				local fw, fh = surface.GetTextSize( text )
				if ((fw != nil) && (fh != nil) && (fw <= maxW) && (fh <= maxH)) then
					best = name
					break
				end
			end
		end
	end

	// Extremely small controls use the smallest available variant, not the
	// original overflowing font.
	return CacheFont( key, best || SmallestFit( font ) )
end
