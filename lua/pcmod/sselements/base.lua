/*
	***************************
	* PCMod 2 SS Device Element *
	***************************
	
	 Element: BASE ELEMENT

*/

local PANEL = {}

function PANEL:OnCreate()
	self.X = 0
	self.Y = 0
	self.W = 0
	self.H = 0
	self.MX = 0
	self.MY = 0
	self.Theme = "basic"
	self.Valid = true
	self:Initialize()
end

function PANEL:OnDestroy()
	self.Valid = false
end

function PANEL:SetTheme( th )
	self.Theme = th
	PCMod.Msg( "Setting theme to '" .. th .. "'...", true )
end

function PANEL:GetTheme()
	return self.Theme
end

function PANEL:SetLayout( x, y, w, h )
	self.X = x or 0
	self.Y = y or 0
	self.W = w or 0
	self.H = h or 0
	self.MX = x + (w*0.5)
	self.MY = y + (h*0.5)
end

function PANEL:Paint()

end

function PANEL:Initialize()

end

function PANEL:OnClick()
	
	self:DoClick()
end

function PANEL:DoClick()

end

function PANEL:OnKeyPress( key, txt )

	self:DoKeyPress( key, txt )
end

function PANEL:DoKeyPress( key, txt )

end

function PANEL:OnQuickType( text )

end

function PANEL:CallThemeHook( ... )
	return PCMod.Gui.ThemeDraw( self:GetTheme(), ... )
end

local white = Color( 255, 255, 255 )
function PANEL:GetCol( id )
	return PCMod.Gui.GetThemeColour( self:GetTheme(), id ) or white
end

// PCMOD15 E2b: themes may declare a Font_Button key. Themes
// without the key keep the stock font - byte-identical behaviour.
// FIX (Step B regression, in-game 2026-10-23): the desktop paints BEFORE any
// window hook runs, and label drawing is NOT gated by HighQuality - so a
// theme font returned here could reach draw.SimpleText unregistered
// ("pcmod15_button isn't a valid font"). Contract now: a theme that declares
// Font_Button MUST also provide an idempotent THEME:EnsureFonts() that
// registers its fonts (surface.CreateFont); the helper calls it HERE, so
// the font is guaranteed to exist before the name is used. A Font_Button
// without EnsureFonts falls back to the stock font - a stale look is always
// safer than crashing the renderer.
function PANEL:GetThemeFont()
	local th = PCMod.Gui.Themes[ self:GetTheme() ]
	if (th && th.Font_Button && th.EnsureFonts) then
		th:EnsureFonts()
		return th.Font_Button
	end
	return "pcmod_3d2d"
end

function PANEL:GetStruct()
	// Refresh the cached struct every call: buttons are drawn through theme
	// hooks that read struct.X/Y, and TranslateWindow() moves live elements
	// during a window drag. A struct captured once would leave the button
	// backgrounds behind while the window frame moved.
	local tmp = self.Struct
	if (!tmp) then
		tmp = {}
		self.Struct = tmp
	end
	tmp.X = self.X
	tmp.Y = self.Y
	tmp.W = self.W
	tmp.H = self.H
	return tmp
end

function PANEL:CursorInside( cx, cy )
	return ((cx > self.X) && (cx < (self.X+self.W)) && (cy > self.Y) && (cy < (self.Y+self.H)))
end

function PANEL:IsValid()
	return self.Valid
end

function PANEL:Remove()
	PCMod.SSEL.Destroy( self )
end

function PANEL:SetFunc( funcname, func )
	self[ funcname ] = func
end

PCMod.SSEL.RegisterBase( PANEL )