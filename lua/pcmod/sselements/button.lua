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
	// Running-program taskbar buttons use a compact icon+label layout. Other
	// buttons keep the original centered-label rendering.
	if (self.TaskbarRole == "running") then
		local textCol = c_bt_txt
		if (self.TaskMinimized) then textCol = self:GetCol( "Button_Text_Locked" ) end
		local textX = self.X + 4
		if (self.HasIcon) then textX = self.X + self.H + 2 end
		local font = self:GetThemeFont()
		if (PCMod.Gui.GetFittedFont) then
			font = PCMod.Gui.GetFittedFont( self.Text, font, (self.X + self.W) - textX - 4, self.H - 2 )
		end
		draw.SimpleText( self.Text, font, textX, self.MY, textCol, TEXT_ALIGN_LEFT, 1 )
		if (self.HasIcon) then
			local sid = PCMod.Res.Mats[ "gui/icons/ico_" .. self.Icon ]
			if (sid) then
				local iconCol = PCMod.Gui.GetThemeColour( self:GetTheme(), "Icon_Tint", Color( 255, 255, 255, 255 ) )
				if (self.TaskMinimized) then iconCol = self:GetCol( "Button_Text_Locked" ) end
				surface.SetTexture( sid )
				surface.SetDrawColor( iconCol.r, iconCol.g, iconCol.b, iconCol.a )
				surface.DrawTexturedRect( self.X + 2, self.Y + 2, self.H - 4, self.H - 4 )
			end
		end
		if (self.Active) then
			local accent = self:GetCol( "ButtonBG_Active" )
			surface.SetDrawColor( accent.r, accent.g, accent.b, accent.a )
			surface.DrawRect( self.X, self.Y + self.H - 2, self.W, 2 )
		end
		return
	end

	// Fit the label to the live button rect. Window resizing changes geometry,
	// but the stock/theme font itself is viewport-scaled and otherwise stays big.
	local font = self:GetThemeFont()
	if (PCMod.Gui.GetFittedFont) then
		local iconW = self.HasIcon && self.H || 0
		font = PCMod.Gui.GetFittedFont( self.Text, font, self.W - iconW - 4, self.H - 2 )
	end
	draw.SimpleText( self.Text, font, self.MX, self.MY, c_bt_txt, 1, 1 )
	if (self.HasIcon) then
		local ico = self.Icon
		local fn = "gui/icons/ico_" .. ico
		local sid = PCMod.Res.Mats[ fn ]
		// A missing icon material would make SetTexture(nil) raise inside
		// Paint and break the whole frame - skip the icon instead.
		if (sid) then
			surface.SetTexture( sid )
			// PCMOD15 E2: icons may be tinted by the theme (Icon_Tint).
			// GetThemeColour falls back to white, so themes without the key keep
			// readable icons even when their button text is black.
			local c_ico = PCMod.Gui.GetThemeColour( self:GetTheme(), "Icon_Tint", Color( 255, 255, 255, 255 ) )
			surface.SetDrawColor( c_ico.r, c_ico.g, c_ico.b, c_ico.a )
			surface.DrawTexturedRect( self.X, self.Y, self.H, self.H ) -- Yes, self.H is repeated on purpose
		end
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