
------------------------------------------------------------------------------------
-- Modern Theme for PCMod 1.5 (PCMOD15, Round 36)
--
-- Additive, opt-in theme: selectable in the Control Panel next to "Basic";
-- persisted per-PC via the existing sys_settheme path (PCData.Theme).
-- Classic themes are untouched. Design language: flat colors, single teal
-- accent, no fake-3D bevels -- but the same layout, fonts and widgets, so it
-- stays PCMod (not a Windows clone).
--
-- Contract (verified in lua/pcmod/ssdevices/base.lua and cl_gui.lua):
--   * every color key used by ANY GetThemeColour call site MUST be defined
--     (a missing key returns nil and crashes rendering), and
--   * THEME:Draw must return true for the ids it handles; for window/error/
--     frame the theme draws the text itself, for button/listbox/textbox/
--     textentry only the background (base code draws the rest).
------------------------------------------------------------------------------------

THEME.Name = "modern"
THEME.Description = "Modern flat theme for PCMod 1.5"
THEME.NiceName = "Modern"
THEME.Author = "PCMod 1.5"

-- Window / desktop
THEME.Primary = Color( 45, 48, 54, 255 )		-- window body (dark slate)
THEME.Secondary = Color( 32, 34, 38, 255 )	-- desktop background
THEME.Bar = Color( 0, 122, 112, 255 )		-- title bar (teal accent)
THEME.Bar_Text = Color( 240, 242, 245, 255 )
THEME.Border = Color( 70, 74, 82, 255 )
THEME.Border_Locked = Color( 58, 60, 66, 255 )

-- Buttons
THEME.ButtonBG = Color( 60, 64, 72, 255 )
THEME.ButtonBG_Active = Color( 0, 102, 94, 255 )
THEME.Button_Text = Color( 230, 232, 236, 255 )
THEME.Button_Text_Locked = Color( 120, 124, 130, 255 )

-- Text fields
THEME.TextboxBG = Color( 38, 40, 45, 255 )
THEME.Textbox_Text = Color( 220, 222, 226, 255 )

-- Listboxes
THEME.ListboxBG = Color( 38, 40, 45, 255 )
THEME.Listbox_Text = Color( 220, 222, 226, 255 )
THEME.Listbox_SelBG = Color( 0, 122, 112, 255 )
THEME.Listbox_SelText = Color( 245, 246, 248, 255 )

-- Errors
THEME.ErrorBG = Color( 176, 58, 46, 255 )
THEME.Error_Text = Color( 255, 240, 238, 255 )

-- Shell
THEME.TaskBar = Color( 28, 30, 34, 255 )
THEME.StartMenuBG = Color( 40, 43, 48, 255 )

-- 3D sub-tables: unused by Modern (Draw handles every id) but defined so no
-- other code path can ever see a nil color table.
THEME.ButtonCol = {
	UpperOuter = THEME.Border,
	LowerOuter = THEME.Border,
	UpperMid = THEME.ButtonBG,
	LowerMid = THEME.ButtonBG,
	BG = THEME.ButtonBG,
	Text = THEME.Button_Text,
	Outline = THEME.Border
}

THEME.ListboxCol = {
	UpperOuter = THEME.Border,
	LowerOuter = THEME.Border,
	UpperMid = THEME.ListboxBG,
	LowerMid = THEME.ListboxBG,
	BG = THEME.ListboxBG,
	Text = THEME.Listbox_Text,
	Outline = THEME.Border
}

THEME.TextboxCol = {
	UpperOuter = THEME.Border,
	LowerOuter = THEME.Border,
	UpperMid = THEME.TextboxBG,
	LowerMid = THEME.TextboxBG,
	BG = THEME.TextboxBG,
	Text = THEME.Textbox_Text,
	Outline = THEME.Border
}

------------------------------------------------------------------------------------

function THEME:SetCol( col )
	surface.SetDrawColor( col.r, col.g, col.b, col.a )
end

function THEME:Draw( id, ... )
	local args = { ... }
	if (id == "window") then
		-- Base code skips its own paint entirely, so we draw caption too.
		local x, y, w, h, caption, ch = args[1], args[2], args[3], args[4], args[5], args[6]
		self:SetCol( self.Primary )
		surface.DrawRect( x, y, w, h )
		self:SetCol( self.Bar )
		surface.DrawRect( x, y, w, ch )
		draw.SimpleText( caption, "pcmod_3d2d", x + 4, y + (ch/2), self.Bar_Text, TEXT_ALIGN_LEFT, 1 )
		self:SetCol( self.Border )
		surface.DrawOutline( x, y, w, h )
		surface.DrawLine( x, y + ch, x + w, y + ch )
		return true
	end
	if (id == "error") then
		local x, y, text = args[1], args[2], args[3]
		surface.SetFont( "pcmod_3d2d" )
		local w, h = surface.GetTextSize( text )
		self:SetCol( self.ErrorBG )
		surface.DrawRect( x - (w/2), y - (h/2), w, h )
		draw.SimpleText( text, "pcmod_3d2d", x, y, self.Error_Text, 1, 1 )
		self:SetCol( self.Border )
		surface.DrawOutline( x - (w/2), y - (h/2), w, h )
		return true
	end
	if (id == "frame") then
		local title, x, y, w, h, color = args[1], args[2], args[3], args[4], args[5], args[6]
		surface.SetFont( "pcmod_3d2d" )
		local tw = surface.GetTextSize( title )
		self:SetCol( self.Border )
		surface.DrawLine( x, y, x, y + h )
		surface.DrawLine( x, y + h, x + w, y + h )
		surface.DrawLine( x + w, y, x + w, y + h )
		surface.DrawLine( x, y, x + ((w*0.5)-(tw*0.5)), y )
		surface.DrawLine( x + ((w*0.5)+(tw*0.5)), y, x + w, y )
		draw.SimpleText( title, "pcmod_3d2d", x + (w*0.5), y, color, 1, 1 )
		return true
	end
	if (id == "button") then
		-- Background only; base code draws the label on top.
		local struct = args[1]
		self:SetCol( self.ButtonBG )
		surface.DrawRect( struct.X, struct.Y, struct.W, struct.H )
		self:SetCol( self.Border )
		surface.DrawOutline( struct.X, struct.Y, struct.W, struct.H )
		return true
	end
	if (id == "listbox") then
		local lb = args[1]
		self:SetCol( self.ListboxBG )
		surface.DrawRect( lb.X, lb.Y, lb.W, lb.H )
		self:SetCol( self.Border )
		surface.DrawOutline( lb.X, lb.Y, lb.W, lb.H )
		return true
	end
	if (id == "textbox") then
		-- Non-entry textbox: background + label box (matches base geometry).
		local tb = args[1]
		self:SetCol( self.TextboxBG )
		surface.DrawRect( tb.BX, tb.Y, tb.BW, tb.H )
		self:SetCol( self.Border )
		surface.DrawOutline( tb.BX, tb.Y, tb.BW, tb.H )
		return true
	end
	if (id == "textentry") then
		local tb = args[1]
		self:SetCol( self.TextboxBG )
		surface.DrawRect( tb.X, tb.Y, tb.W, tb.H )
		self:SetCol( self.Border )
		surface.DrawOutline( tb.X, tb.Y, tb.W, tb.H )
		return true
	end
	-- "text" and any unknown id: return nil so the base fallback draws it.
end
