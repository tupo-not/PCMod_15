/*
	***************************
	* PCMod 2 SS Device Element *
	***************************
	
	 Element: Button

*/

local PANEL = {}

function PANEL:Initialize()
	self.Locked = false
	self.Active = false
	self.HasIcon = false
	self.Icon = ""
	self.Text = "Button"
end

function PANEL:Paint()
	local c_bor = self:GetCol( "Border" )
	local c_btbg = self:GetCol( "ButtonBG" )
	local c_bt_txt = self:GetCol( "Button_Text" )
	if (self.Locked) then
		c_bor = self:GetCol( "Border_Locked" )
		c_bt_txt = self:GetCol( "Button_Text_Locked" )
	end
	if (self.Active) then
		c_btbg = self:GetCol( "ButtonBG_Active" )
	end
	// PCMOD15 E4b (M-61): resolve hover from the per-frame cursor
	// cache (E4a) and expose Hover/Active/Locked to the theme hook.
	// Themes that ignore the fields are unaffected; the fallback
	// below only changes for themes that define ButtonBG_Hover.
	local cur = PCMod.SDraw.Cursor
	local hovered = false
	if ((cur) && (cur.Frame == PCMod.SDraw.CFrame) && (self.DEVICE) && (cur.Ent == self.DEVICE.EntID)) then
		// Only the topmost device under the cursor may hover; otherwise a
		// window that is covered by another one still lights its buttons up.
		local devid = self.DEVICE.SSDevice and self.DEVICE.SSDevice.DevID
		if (devid && (cur.HoverDevID == devid)) then
			hovered = self:CursorInside( cur.X, cur.Y )
		end
	end
	if (hovered) then
		c_btbg = PCMod.Gui.GetThemeColour( self:GetTheme(), "ButtonBG_Hover", c_btbg )
	end
	local st = self:GetStruct()
	st.Hover = hovered
	st.Active = self.Active
	st.Locked = self.Locked
	if (!self:CallThemeHook( "button", st )) then
		surface.SetDrawColor( c_btbg.r, c_btbg.g, c_btbg.b, c_btbg.a )
		surface.DrawRect( self.X, self.Y, self.W, self.H )
		surface.DrawOutline( self.X, self.Y, self.W, self.H, c_bor )
	end
	// PCMOD15 E2b: label font is theme-selectable (Font_Button);
	// hit-testing is rect-based, so only the paint changes.
	draw.SimpleText( self.Text, self:GetThemeFont(), self.MX, self.MY, c_bt_txt, 1, 1 )
	if (self.HasIcon) then
		local ico = self.Icon
		local fn = "gui/icons/ico_" .. ico
		local sid = PCMod.Res.Mats[ fn ]
		surface.SetTexture( sid )
		// PCMOD15 E2: icons may be tinted by the theme (Icon_Tint).
		// GetCol falls back to white, so themes without the key
		// render exactly as before.
		local c_ico = self:GetCol( "Icon_Tint" )
		surface.SetDrawColor( c_ico.r, c_ico.g, c_ico.b, c_ico.a )
		surface.DrawTexturedRect( self.X, self.Y, self.H, self.H ) -- Yes, self.H is repeated on purpose
	end
end

function PANEL:SetText( txt )
	self.Text = txt
end

function PANEL:SetIcon( ico )
	self.Icon = ico
	if ((ico) && (ico != "")) then self.HasIcon = true end
end

PCMod.SSEL.Register( "Button", PANEL )