
------------------------------------------------------------------------------------
-- PCMod 1.5 Theme (prototype, v2) -- PCMOD15 Stage E/F, Sessions 2-3
--
-- ISOLATED PROTOTYPE. This file lives in _development\PCMOD15\prototype\ and is
-- NOT loaded by the game (the theme loaders only glob lua\pcmod\themes\cl_*).
-- Nothing in lua\ was modified to add it. To integrate later (separate session,
-- after in-game verification of Round 36 Modern, see THEME_15_PROTOTYPE.md 6
-- and VISUAL_UPGRADE.md 7):
--   1. copy this file to lua\pcmod\themes\cl_pcmod15.lua
--   2. re-run the gates (glua_syntax_check 131 -> test_pcmod15 -> tree_diff
--      -> verify_release; update the expected file counts where the gates
--      document them)
--   3. run the V-checklist (V-07..V-12 + V-13..V-19) before any publish decision.
-- Backout: delete the copied file. Classic and Modern are untouched either way.
--
-- v2 (Session 3, Stage F) extends v1 with visual HIERARCHY work, not just color:
--   * hierarchy  : bold caption font for window titles / section frames
--                  (theme-created, drawn AND measured only by this theme, so
--                  no base file needs to change and no hit-testing is affected);
--   * readability: palette re-tuned to pass WCAG contrast math - every text
--                  pair >= 4.5:1, every accent detail >= 3:1 (verified for
--                  real, computed from this file by test_visual_upgrade.py);
--                  list selection is now "bright accent text on a darker row"
--                  instead of "accent bar" (the accent bar could not reach
--                  4.5:1 even with pure white text);
--   * depth      : 1px inset shadow at the bottom of windows, 1px shadow line
--                  inside text fields, 2px accent edge on buttons, 3px accent
--                  rail on menus, 1px accent hairline on the taskbar;
--   * states     : defines ButtonBG_Hover / Icon_Tint / Font_Button for the
--                  planned renderer extensions E4/E2/E2b (see EXTENSIONS.md).
--                  Until those patches are applied the keys are inert - no
--                  existing code reads them.
--
-- Design language ("substantially modernized, still PCMod, not Windows"):
--   * same square geometry, same layout fractions, same widget set, same input
--     paths - hit-testing, layout, windows and networking are 100% unchanged;
--   * deep graphite surfaces, ONE teal accent family (bright for content,
--     dim for chrome details);
--   * quiet window chrome: dark elevated title strip + 2px accent underline
--     (Modern used a solid accent title bar).
--
-- Contract (verified in ssdevices\base.lua and cl_gui.lua, same as Modern):
--   * every color key read by ANY GetThemeColour call site MUST be defined
--     (missing key -> nil -> render crash), so all 20 required keys are set;
--   * THEME:Draw must return true for ids it fully owns:
--       window/error/frame -> theme draws the caption/title/text itself;
--       button/listbox/textbox/textentry -> theme draws ONLY the background,
--       base code draws labels/rows/caret on top;
--     "text" additionally returns true here and draws all lines itself
--     (allowed by the hook contract since Round 33 M-08; fixes the F-1
--     black-text-on-dark readability class for every RenderText window).
--   * ids "startmenu" and "taskbar" are handled HERE but are only CALLED after
--     the optional renderer extensions E5/E7 are applied (EXTENSIONS.md).
--     Before that they are dead branches - harmless.
--   * draw hooks only run when PCMod.Cfg.HighQuality is true (cl_gui.lua:76);
--     Low Quality mode falls back to the base renderer + the 20 color keys.
--   * no per-frame table allocations in Draw (Round 19 A-04 spirit): varargs
--     are unpacked into locals, fonts are created lazily exactly once.
--   * NOTE (needs in-game check, V-14): the caption font is created lazily on
--     the first window paint (surface.CreateFont inside the 3D2D block). If
--     that misbehaves in the live renderer, replace self.CaptionFont with
--     "pcmod_3d2d" - one line, no other change.
------------------------------------------------------------------------------------

THEME.Name = "pcmod15"
THEME.Description = "PCMod 1.5 interface (graphite + teal, prototype v2)"
THEME.NiceName = "PCMod 1.5"
THEME.Author = "PCMod 1.5"

-- == Required contract keys (all 20, enumerated from GetThemeColour sites) ==

-- Window / desktop
THEME.Primary = Color( 38, 41, 48, 255 )		-- window body (graphite)
THEME.Secondary = Color( 24, 26, 31, 255 )	-- desktop background (deep slate)
THEME.Bar = Color( 52, 56, 64, 255 )		-- title strip (elevated graphite)
THEME.Bar_Text = Color( 235, 238, 242, 255 )
THEME.Border = Color( 64, 68, 76, 255 )
THEME.Border_Locked = Color( 52, 54, 58, 255 )

-- Buttons
THEME.ButtonBG = Color( 48, 52, 60, 255 )
THEME.ButtonBG_Active = Color( 0, 150, 138, 255 )
THEME.Button_Text = Color( 228, 231, 236, 255 )
THEME.Button_Text_Locked = Color( 122, 126, 134, 255 )	-- disabled text (WCAG-exempt state)

-- Text fields
THEME.TextboxBG = Color( 28, 30, 35, 255 )
THEME.Textbox_Text = Color( 216, 220, 226, 255 )

-- Listboxes
THEME.ListboxBG = Color( 28, 30, 35, 255 )
THEME.Listbox_Text = Color( 216, 220, 226, 255 )
THEME.Listbox_SelBG = Color( 14, 20, 24, 255 )	-- darker-than-panel selection row
THEME.Listbox_SelText = Color( 86, 214, 196, 255 )	-- bright accent selection text

-- Errors
THEME.ErrorBG = Color( 178, 52, 46, 255 )
THEME.Error_Text = Color( 255, 238, 236, 255 )

-- Shell
THEME.TaskBar = Color( 20, 22, 26, 255 )
THEME.StartMenuBG = Color( 33, 36, 42, 255 )

-- == Own extra keys (never read by base code today; Accent*/Body_Text/
--    Field_Shadow are used by this file's Draw, the rest are read only after
--    the optional extensions from EXTENSIONS.md are applied) ==

THEME.Accent = Color( 0, 190, 174, 255 )		-- bright accent (selection text)
THEME.Accent_Dim = Color( 0, 150, 138, 255 )	-- chrome details (>=3:1 on all surfaces)
THEME.Body_Text = Color( 216, 220, 226, 255 )	-- normalized RenderText color
THEME.Field_Shadow = Color( 18, 19, 23, 255 )	-- 1px inset lines

THEME.ButtonBG_Hover = Color( 58, 64, 74, 255 )	-- E4: hover tile (8.4:1 with Button_Text)
THEME.Icon_Tint = Color( 220, 226, 232, 255 )	-- E2: icon tint (white before E2)
THEME.Font_Button = "pcmod15_button"		-- E2b: bold label font (must be registered by EnsureFonts - the base helper calls it)

-- == Legacy 3D sub-tables: unused by this theme (Draw handles every id) but
--    defined so no code path (e.g. classic Draw3DBox in Low Quality mode)
--    can ever see a nil color table. Same safety pattern as cl_modern.lua. ==

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

-- Lazy font creation: exactly once per theme table copy. The fonts are only
-- used by this theme's own Draw paths (window captions, frame titles, and -
-- after E2b - button labels), so nothing else measures or hit-tests with them.
-- E2b CONTRACT (fix 2026-10-23, Step B regression): PANEL:GetThemeFont() calls
-- THIS method before returning Font_Button - a theme that declares a custom
-- font MUST provide this idempotent EnsureFonts() so the font is guaranteed
-- REGISTERED before draw.SimpleText ever sees the name. The old lazy-only
-- scheme broke on the desktop (first button painted before any window hook
-- ran) and under HighQuality=false (theme hooks never run at all).
function THEME:EnsureFonts()
	local size = 20
	if (PCMod.Gui && PCMod.Gui.GetFontSize) then size = PCMod.Gui.GetFontSize( 20 ) end
	// Recreate when the GUI scale / viewport changed. The font names stay the
	// same so every cached reference (Font_Button, CaptionFont) keeps working.
	if ((!self.CaptionFont) || (self.CaptionSize != size)) then
		surface.CreateFont( "pcmod15_caption", { font = "Tahoma", size = size, weight = 700 } )
		surface.CreateFont( "pcmod15_button", { font = "Tahoma", size = size, weight = 700 } )
		self.CaptionFont = "pcmod15_caption"
		self.CaptionSize = size
	end
end

function THEME:SetCol( col )
	surface.SetDrawColor( col.r, col.g, col.b, col.a )
end

function THEME:Draw( id, ... )
	-- No table packing: varargs are unpacked into locals, nothing is
	-- allocated per frame (a screen can call this dozens of times per frame).
	local a1, a2, a3, a4, a5, a6 = ...

	if (id == "window") then
		-- Base code skips its own paint entirely, so we draw the caption too.
		local x, y, w, h, caption, ch = a1, a2, a3, a4, a5, a6
		self:EnsureFonts()
		self:SetCol( self.Primary )
		surface.DrawRect( x, y, w, h )
		self:SetCol( self.Bar )
		surface.DrawRect( x, y, w, ch )
		-- Signature detail: 2px accent underline between title strip and body.
		self:SetCol( self.Accent_Dim )
		surface.DrawRect( x, y + ch - 2, w, 2 )
		-- Hierarchy: bold caption (drawn AND measured only by this theme).
		draw.SimpleText( caption, self.CaptionFont, x + 4, y + (ch / 2), self.Bar_Text, TEXT_ALIGN_LEFT, 1 )
		self:SetCol( self.Border )
		surface.DrawOutline( x, y, w, h )
		-- Depth: 1px inset shadow along the bottom edge ("sits on the desktop").
		self:SetCol( self.Field_Shadow )
		surface.DrawRect( x, (y + h) - 1, w, 1 )
		return true
	end

	if (id == "text") then
		-- RenderText call sites pass their own hardcoded black/white Color;
		-- on this dark palette everything is normalized to Body_Text.
		-- Geometry and StatusCodes mapping replicate ssdevices\base.lua
		-- RenderText exactly (behavior-identical, only the color changes).
		local x, y, text, col, align = a1, a2, a3, a4, a5
		if (not text) or (not text[1]) then return end
		surface.SetFont( "pcmod_3d2d" )
		local tw, th = surface.GetTextSize( text[1] )
		local codes = (PCMod.Cfg and PCMod.Cfg.StatusCodes) or {}
		for k, txt in pairs( text ) do
			local ty = y + ((k - 1) * th)
			local t = tostring( txt )
			if (type( txt ) == "number") then t = codes[ txt ] end
			if (not t) then t = "Invalid Statuscode!" end
			draw.SimpleText( t, "pcmod_3d2d", x, ty, self.Body_Text, align, TEXT_ALIGN_TOP )
		end
		return true
	end

	if (id == "error") then
		local x, y, text = a1, a2, a3
		surface.SetFont( "pcmod_3d2d" )
		local w, h = surface.GetTextSize( text )
		self:SetCol( self.ErrorBG )
		surface.DrawRect( x - (w / 2), y - (h / 2), w, h )
		draw.SimpleText( text, "pcmod_3d2d", x, y, self.Error_Text, 1, 1 )
		self:SetCol( self.Border )
		surface.DrawOutline( x - (w / 2), y - (h / 2), w, h )
		return true
	end

	if (id == "frame") then
		-- Callers always pass white; normalize to the chrome text color.
		-- Bold title = section headers read as structure, not body text.
		local title, x, y, w, h, color = a1, a2, a3, a4, a5, a6
		self:EnsureFonts()
		surface.SetFont( self.CaptionFont )
		local tw = surface.GetTextSize( title )
		self:SetCol( self.Border )
		surface.DrawLine( x, y, x, y + h )
		surface.DrawLine( x, y + h, x + w, y + h )
		surface.DrawLine( x + w, y, x + w, y + h )
		surface.DrawLine( x, y, x + ((w * 0.5) - (tw * 0.5)), y )
		surface.DrawLine( x + ((w * 0.5) + (tw * 0.5)), y, x + w, y )
		draw.SimpleText( title, self.CaptionFont, x + (w * 0.5), y, self.Bar_Text, 1, 1 )
		return true
	end

	if (id == "button") then
		-- Background only; base code draws the label on top.
		-- Static styling until E4 lands: the hook receives no hover/active/
		-- locked state today (sselements\button.lua passes only the rect -
		-- M-61). After E4 the struct carries Hover/Active/Locked; this branch
		-- can then paint self.ButtonBG_Hover when struct.Hover is set.
		local struct = a1
		self:SetCol( self.ButtonBG )
		surface.DrawRect( struct.X, struct.Y, struct.W, struct.H )
		-- 2px accent edge: pure paint, hit-testing rect is unchanged.
		self:SetCol( self.Accent_Dim )
		surface.DrawRect( struct.X, struct.Y, 2, struct.H )
		if (struct.Hover) then
			self:SetCol( self.ButtonBG_Hover )
			surface.DrawRect( struct.X + 2, struct.Y, (struct.W - 2), struct.H )
		end
		self:SetCol( self.Border )
		surface.DrawOutline( struct.X, struct.Y, struct.W, struct.H )
		return true
	end

	if (id == "listbox") then
		-- Background only; rows, selection bar and scrollbar come from base
		-- code using the Listbox_* / ButtonBG / Border keys.
		local lb = a1
		self:SetCol( self.ListboxBG )
		surface.DrawRect( lb.X, lb.Y, lb.W, lb.H )
		self:SetCol( self.Border )
		surface.DrawOutline( lb.X, lb.Y, lb.W, lb.H )
		return true
	end

	if (id == "textbox") then
		-- Non-entry textbox: background + label box (matches base geometry).
		local tb = a1
		self:SetCol( self.TextboxBG )
		surface.DrawRect( tb.BX, tb.Y, tb.BW, tb.H )
		self:SetCol( self.Field_Shadow )
		surface.DrawRect( tb.BX, tb.Y, tb.BW, 1 )
		self:SetCol( self.Border )
		surface.DrawOutline( tb.BX, tb.Y, tb.BW, tb.H )
		return true
	end

	if (id == "textentry") then
		local tb = a1
		self:SetCol( self.TextboxBG )
		surface.DrawRect( tb.X, tb.Y, tb.W, tb.H )
		self:SetCol( self.Field_Shadow )
		surface.DrawRect( tb.X, tb.Y, tb.W, 1 )
		self:SetCol( self.Border )
		surface.DrawOutline( tb.X, tb.Y, tb.W, tb.H )
		return true
	end

	if (id == "startmenu") then
		-- Only called once the optional extension E5 is applied
		-- (EXTENSIONS.md). Same panel language as buttons: flat dark panel,
		-- accent rail on the leading edge, 1px border.
		local x, y, w, h = a1, a2, a3, a4
		self:SetCol( self.StartMenuBG )
		surface.DrawRect( x, y, w, h )
		self:SetCol( self.Accent_Dim )
		surface.DrawRect( x, y, 3, h )
		self:SetCol( self.Border )
		surface.DrawOutline( x, y, w, h )
		return true
	end

	if (id == "taskbar") then
		-- Only called once the optional extension E7 is applied. The start
		-- button itself is a Button element and is painted by self:Draw().
		local x, bary, w, bh = a1, a2, a3, a4
		self:SetCol( self.TaskBar )
		surface.DrawRect( x, bary, w, bh )
		self:SetCol( self.Accent_Dim )
		surface.DrawRect( x, bary, w, 1 )
		return true
	end

	-- Unknown ids: return nil so the base fallback draws them.
end
