
// ---------------------------------------------------------------------------------------------------------
// cl_gui.lua - Revision 1
// Client-Side
// Controls drawing operations on the client
// ---------------------------------------------------------------------------------------------------------

// ---------------------------------------------------------------------------------------------------------
// Define our library
// ---------------------------------------------------------------------------------------------------------

PCMod.Gui = PCMod.Gui or {}
PCMod.Gui.Version = "1.0"
PCMod.SelEntity = 0

PCMod.Gui.MouseDown = false

PCMod.Gui.DebugBoxes = {}
PCMod.Gui.Themes = {}

PCMod.Gui.CamLocked = false
PCMod.Gui.CamLockID = 0

PCMod.Msg( "Gui Library Loaded (V" .. PCMod.Gui.Version .. ")", true )


// ---------------------------------------------------------------------------------------------------------
// Load all themes
// ---------------------------------------------------------------------------------------------------------

function PCMod.LoadTheme( id )
	THEME = {}
	local fn = "pcmod/themes/" .. id
	THEME.FileName = fn
	THEME.Name = "base"
	THEME.Description = "Base theme"
	THEME.Author = "[GU]thomasfn"
	include( fn )
	PCMod.Gui.Themes[ THEME.Name ] = table.Copy( THEME )
	PCMod.Msg( "Theme '" .. THEME.Name .. "' loaded!", true )
end

local ths = file.Find( "pcmod/themes/cl_*", "LUA")
if ((!ths) || (#ths == 0)) then
	PCMod.Warning( "No themes to load!" )
else
	for _, v in pairs( ths ) do
		THEME = {}
		PCMod.LoadTheme( v )
	end
end

// A client that only downloaded part of the addon (or a partial reload) can
// end up without the core themes. Load them explicitly so devices never paint
// with a nil colour table.
for _, fallback in ipairs( { "cl_basic.lua", "cl_server.lua" } ) do
	local name = string.gsub( fallback, "^cl_", "" )
	name = string.gsub( name, "%.lua$", "" )
	local theme = PCMod.Gui.Themes[ name ]
	if ((!theme || (theme.Secondary == nil)) && file.Exists( "pcmod/themes/" .. fallback, "LUA" )) then
		PCMod.LoadTheme( fallback )
	end
end

concommand.Add( "pc_theme_reload", function( pl, com, args )
	// SECURITY (stage 3, fix 2.5): validate the argument before include().
	// Note: the plan's "^[%w_]+$" would reject the real input ("cl_basic.lua") -
	// the same "%.lua" scheme as pc_prog_reload keeps working usage intact.
	local id = args[1]
	if (!id || !string.match( id, "^[%w_]+%.lua$")) then return end
	if (!file.Exists( "pcmod/themes/" .. id, "LUA" )) then return end
	PCMod.LoadTheme( id )
end )


// ---------------------------------------------------------------------------------------------------------
// GetThemeColour - Gets the colour value that a theme specifies
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.GetThemeColour( themename, key, default )
	local themes = PCMod.Gui.Themes
	if (themes) then
		local th = themes[ themename ]
		if (th && (th[ key ] != nil)) then return th[ key ] end
		// A theme may be missing (download/reload) - fall back to Basic so a
		// device never indexes a nil colour and spams the console.
		local base = themes[ "basic" ]
		if (base && (base[ key ] != nil)) then return base[ key ] end
	end
	return default or Color( 0, 0, 0, 255 )
end

// ---------------------------------------------------------------------------------------------------------
// ThemeDraw - Calls a theme draw hook
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.ThemeDraw( themename, ... )
	if (!PCMod.Cfg.HighQuality) then return end
	local themes = PCMod.Gui.Themes
	if (!themes) then return end
	if (!themes[ themename ]) then return end
	if (!themes[ themename ].Draw) then return end
	return themes[ themename ]:Draw( ... )
end

// ---------------------------------------------------------------------------------------------------------
// SURFACE: DrawOutline - Draws an unfilled box
// ---------------------------------------------------------------------------------------------------------
function surface.DrawOutline( x, y, w, h, col )
	if (col) then surface.SetDrawColor( col.r, col.g, col.b, col.a ) end
	surface.DrawLine( x, y, x+w, y ) -- Top Line
	surface.DrawLine( x, y+h, x+w, y+h ) -- Bottom Line
	surface.DrawLine( x, y, x, y+h ) -- Left Line
	surface.DrawLine( x+w, y, x+w, y+h ) -- Right Line
end

// ---------------------------------------------------------------------------------------------------------
// GUI scaling helpers
// ---------------------------------------------------------------------------------------------------------
// Returns the scaled pixel size for a font that was designed at `base` px for
// the original ~400px monitor. Fullscreen rendering scales by the viewport
// height, and cfg.GuiScale is the user multiplier (also used for geometry).
function PCMod.Gui.GetFontSize( base )
	base = base or 20
	local size = base
	if (PCMod.SDraw && PCMod.SDraw.Fullscreen) then
		local scale = 1
		if (PCMod.Cfg && (PCMod.Cfg.GuiScale != nil)) then
			scale = tonumber( PCMod.Cfg.GuiScale ) or 1
		end
		if (scale < 0.25) then scale = 0.25 end
		if (scale > 3) then scale = 3 end
		local h = ScrH() or 0
		if (h > 0) then
			scale = scale * math.max( 1, h / 400 )
		end
		size = math.floor( base * scale + 0.5 )
		if (size < 10) then size = 10 end
	end
	return size
end

// ---------------------------------------------------------------------------------------------------------
// InitFonts - Creates all the fonts we need
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.InitFonts()
	PCMod.Msg( "Creating fonts...", true )
	if (PCMod.Gui.ResetTextFitCache) then PCMod.Gui.ResetTextFitCache() end
	// Base size 20 is tuned for the ~400px tall monitor UI. The monitor itself
	// keeps that size; when the screen is shown fullscreen at native resolution
	// the font is scaled by the screen height (and cfg.GuiScale) so the UI keeps
	// the same relative size.
	local size = PCMod.Gui.GetFontSize( 20 )
	//surface.CreateFont( "Tahoma", 20, 400, true, false, "pcmod_3d2d" )
	local fontsToMake = {
		{ "pcmod_3d2d", size, 400 },
		{ "ScoreboardText", size, 400 },
		// device-menu (lock frame) fonts
		{ "PCModMenuTitle", math.max( 13, math.floor( size * 0.8 + 0.5 ) ), 700 },
		{ "PCModMenuRow", math.max( 12, math.floor( size * 0.7 + 0.5 ) ), 600 },
		{ "PCModMenuSub", math.max( 10, math.floor( size * 0.55 + 0.5 ) ), 400 },
		{ "PCModMenuFoot", 10, 400 },
	}
	for _, f in ipairs( fontsToMake ) do
		surface.CreateFont( f[ 1 ], { font = "Tahoma", size = f[ 2 ], weight = f[ 3 ] } )
		// Mark a font as valid only if it actually measures - a rejected
		// CreateFont must not end up in the registry (SetFont on it would spam
		// "isn't a valid font" warnings).
		surface.SetFont( f[ 1 ] )
		if (surface.GetTextSize( "X" )) then PCMod.Gui.Fonts[ f[ 1 ] ] = true end
	end
	if (PCMod.Gui.InitTextFitFonts) then PCMod.Gui.InitTextFitFonts() end
end
hook.Add( "Initialize", "PCMod.Gui.InitFonts", PCMod.Gui.InitFonts )

// ---------------------------------------------------------------------------------------------------------
// DrawSelEnt - Draws information for the selected entity to the screen
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.DrawSelEnt()
	if (PCMod.SelEntity == 0) then return end -- No entity = no draw
	local ent = ents.GetByIndex( PCMod.SelEntity ) -- Get the entity
	if ((!ent) || (!ent:IsValid())) then return end -- Check it's validness
	
	// Get the draw coords
	local origin = ent:GetPos():ToScreen()
	
	// Tell the ent to draw
	if (ent.DrawInfo) then ent:DrawInfo( origin ) end
	
	// Clear the stored entity
	PCMod.SelEntity = 0
end
hook.Add( "HUDPaint", "PCMod.Gui.DrawSelEnt", PCMod.Gui.DrawSelEnt )

// ---------------------------------------------------------------------------------------------------------
// DrawWirelessLinks - Draws lines between wireless entities
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.DrawWirelessLinks( ent )
	if (!PCMod.Cfg.WirelessInfo) then return end

	// Get all entities in range
	local range = PCMod.Cfg.WirelessRange
	local elist = {}
	if (range > 0) then
		elist = ents.FindInSphere( ent:GetPos(), range )
	else
		elist = ents.FindByClass( ent:GetClass() )
	end
	
	// Calculate starting position
	local startpos = ent:GetPos():ToScreen()
	
	// Cycle through and draw when needed
	local col = PCMod.Cfg.WirelessInfoDrawCol
	surface.SetDrawColor( col.r, col.g, col.b, col.a )
	local offs = 0
	for _, v in pairs( elist ) do
		if ((v) && (v:IsValid()) && (v.IsPCMod) && (v != ent)) then
			local wireless
			if (v.GetWirelessSSID) then
				wireless = (v:GetWirelessSSID() != nil)
			elseif (v.GetGVar) then
				wireless = (v:GetGVar( "wireless" ) == true)
			end
			if (wireless) then
				local endpos = v:GetPos():ToScreen()
				if (math.IsOnScreen( endpos )) then
					surface.DrawLine( startpos.x, startpos.y, endpos.x, endpos.y )
				else
					offs = offs + 1
				end
			end
		end
	end
	if (offs > 0) then
		// There are 'offs' many wireless links not drawn, what to do with this info??? -thomasfn
	end
end

// ---------------------------------------------------------------------------------------------------------
// EnableScreenClicker - Override, we don't want to turn off the mouse whilst we are locked!
// ---------------------------------------------------------------------------------------------------------
if (!gui.ESC) then
	gui.ESC = gui.EnableScreenClicker
	function gui.EnableScreenClicker( enabled )
		if ((PCMod) && (PCMod.Gui)) then
			if (PCMod.Gui.CamLocked) then enabled = true end
		end
		gui.ESC( enabled )
	end
end

// ---------------------------------------------------------------------------------------------------------
// ShowDocument - Shows a printed document on the screen
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.ShowDocument( str )
	PCMod.Msg( "Showing printed document! (" .. str .. ")", true )
	if (PCMod.Gui.PDoc) then
		PCMod.Gui.PDoc:Remove()
		PCMod.Gui.PDoc = nil
	end
	local pn = vgui.Create( "PrintedDoc" )
	if (!pn) then return end
	pn:SetText( str, "ScoreboardText" )
	pn:SetVisible( true )
	PCMod.Gui.PDoc = pn
	gui.EnableScreenClicker( true )
end
// Round 34 (M-40): the hook was registered a second time here (sh_beam.lua
// does it already) - every printed document was created and closed twice.


// ---------------------------------------------------------------------------------------------------------
// HideDocument - Hides a printed document on the screen
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.HideDocument()
	if (PCMod.Gui.PDoc) then
		PCMod.Gui.PDoc:Remove()
		PCMod.Gui.PDoc = nil
	end
	gui.EnableScreenClicker( false )
end

// ---------------------------------------------------------------------------------------------------------
// PopupNotice - Pops up a notice window
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.PopupNotice( title, text )
	if (PCMod.Gui.Popup) then
		PCMod.Gui.Popup:Remove()
		PCMod.Gui.Popup = nil
	end
	local pn = vgui.Create( "PopupWindow" )
	pn:SetTitle( title )
	pn:Setup( text )
	pn:MakePopup()
	PCMod.Gui.Popup = pn
end
usermessage.Hook( "pcmod_ppnot", function( um )
	PCMod.Gui.PopupNotice( um:ReadString(), um:ReadString() )
end )

// Fonts known to be valid: engine defaults + everything PCMod registered via
// InitFonts. Used to never call surface.SetFont with an invalid font (which
// spams "'X' isn't a valid font" warnings).
PCMod.Gui.Fonts = {
	Default = true, DefaultBold = true, DefaultSmall = true,
	DermaDefault = true, DermaDefaultBold = true, DermaLarge = true,
	Marlett = true, Trebuchet18 = true, Trebuchet24 = true,
}

function PCMod.Gui.FontOK( font )
	return (PCMod.Gui.Fonts[ font ] == true)
end

// ---------------------------------------------------------------------------------------------------------
// DrawLabel - Draws a label containing a single or multiple strings
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.DrawLabel( x, y, font, text, padding, bgcol, txtcol )
	if (PCMod.Gui.CamLocked) then return end
	if (!font) then font = "ScoreboardText" end
	// Never SetFont an unregistered font (the engine warns "'X' isn't a valid
	// font" and GetTextSize returns nil, which used to crash this function).
	// If the font is unknown, run InitFonts once (e.g. the Initialize hook was
	// missed); if it is still unknown, fall back to DermaDefault or skip.
	if (!PCMod.Gui.FontOK( font )) then
		if (PCMod.Gui.InitFonts) then PCMod.Gui.InitFonts() end
	end
	if (!PCMod.Gui.FontOK( font )) then
		if (PCMod.Gui.FontOK( "DermaDefault" )) then
			font = "DermaDefault"
		else
			return
		end
	end
	surface.SetFont( font )
	if (!surface.GetTextSize( "X" )) then return end
	local tmp_w = {}
	local tmp_h = {}
	local cnt
	for cnt=1, #text do
		local tw, th = surface.GetTextSize( text[ cnt ] )
		if ((!tw) || (!th)) then return end
		tmp_w[ cnt ] = tw
		tmp_h[ cnt ] = th
	end
	local w = table.MaxVal( tmp_w ) + padding
	local h = table.TotalVal( tmp_h ) + padding
	draw.RoundedBox( 6, x-(w*0.5), y, w, h, bgcol )
	local cy = 0
	for cnt=1, #text do
		local th = tmp_h[ cnt ]
		draw.SimpleText( text[ cnt ], font, x, y+(padding*0.5)+cy+(th*0.5), txtcol, 1, 1 )
		cy = cy + th
	end
end

// ---------------------------------------------------------------------------------------------------------
// AskForPort - Shows a menu asking for a port
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.AskForPort( entid, filter, cstatus )
	
	// Get the port data, validate it
	local pdata = PCMod.PortData[ entid ]	
	if (!pdata) then
		PCMod.Warning( "No port data!" )
		return
	end
	
	// Ensure cstatus is valid
	if (!cstatus) then cstatus = false end
	
	// Create the derma menu
	local dmXX = DermaMenu()
	local cnt = 0
	
	// Go through all ports, add them to menu
	for k, v in pairs( pdata ) do
		if (((filter) && (v.Type==filter)) || (!filter)) then -- Does the port match our filter?
			if (v.Connected == cstatus) then -- Does the port link status match our fiter?
			
				// Increase the counter, build the display string
				cnt = cnt + 1
				local vt = (v.Name && (v.Name != "")) and v.Name or v.Type
				if (!(v.Name && (v.Name != ""))) then
					for _, pt in pairs( PCMod.Cfg.WireTypes ) do
						if (pt.Name == v.Type) then vt = pt.ExtName end
					end
				end
				local str = tostring( k ) .. " - " .. vt
			
				// Add the item
				dmXX:AddOption( str, function( self )
					self.ID = k
					RunConsoleCommand( "pc_selport", entid, self.ID )
				end )
				
				// Tell the item what ID we are
				//local panels = dmXX.Choices;
				//local pn = panels[#panels];
				//if (pn) then pn.ID = k end
				
			end
		end
	end
	
	// Open the menu
	dmXX:Open()
	
	// Set the menu's position to where the entity is
	local ent = ents.GetByIndex( entid )
	if (ent) then
		local pos = LocalPlayer():GetShootPos()
		local ang = LocalPlayer():GetAimVector()
		local tracedata = {}
		tracedata.start = pos
		tracedata.endpos = pos+(ang*80)
		tracedata.filter = LocalPlayer()
		local trace = util.TraceLine(tracedata)
		local ps = trace.HitPos:ToScreen()
		dmXX:SetPos( ScrW()/2, ScrH()/2 )
	
	end
	
	// If we have no ports, cancel us
	if (cnt == 0) then
		
		// We have no ports shown!
		dmXX:Remove()
		gui.EnableScreenClicker( false )
		PCMod.Notice( "No ports!" )
	
	end
end

// ---------------------------------------------------------------------------------------------------------
// RegisterClick - Parses a click and checks if it needs to be processed
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.RegisterClick( mx, my, ent, right )
	// Window dragging/resizing consumes the mouse gesture globally; without
	// this, releasing a drag over another window could click its controls.
	if (PCMod.SDraw) then
		if (PCMod.SDraw.GrabActive) then return end
		if (PCMod.SDraw.SuppressClicksUntil && (CurTime() < PCMod.SDraw.SuppressClicksUntil)) then
			PCMod.SDraw.SuppressClicksUntil = 0
			return
		end
	end
	PCMod.Msg( "Mouse Clicked!", true )
	// Gonna comment this function, because it's long and complicated
	// Ignore mx and my, CalcCursor already knows these bits
	
	// Get the cursor position
	if ((!PCMod.Gui.CamLocked) && (!PCMod.Cfg.AdvancedMode)) then
		PCMod.Msg( "Cam is not locked!", true )
		return
	end
	if (!ent) then ent = ents.GetByIndex( PCMod.Gui.CamLockID ) end
	if ((!ent) || (!ent:IsValid())) then
		PCMod.Msg( "Entity is invalid! (" .. PCMod.Gui.CamLockID .. ")", true )
		return
	end
	local x, y = PCMod.SDraw.CalcCursor( ent )
	
	PCMod.Msg( "Position calculated!", true )
	
	// Get the screenspace for the entity
	local ss = PCMod.SDraw.SSpaces[ ent:EntIndex() ]
	if (ss == "nospace") then return end
	if (!ss) then
		PCMod.Msg( "Entity (" .. tostring( ent:EntIndex() ) .. ") has no screenspace!", true )
		PCMod.SDraw.SSpaces[ ent:EntIndex() ] = "nospace"
		return
	end
	ss = table.Copy( ss )
	
	// Cycle through every device, and 'tag' it if the mouse is potentially ontop of it
	for k, v in pairs( ss ) do
		if (type( v ) == "table") then
			ss[ k ].Tagged = false
			// Use the same visual rect (GUI scale / menu anchoring) as drawing.
			// noanim=true: tag by the settled rect, so a menu mid-slide does not
			// cover the taskbar in hit-testing (matches the taskbar repaint).
			local vx, vy, vw, vh = PCMod.SDraw.GetDeviceVisualRect( v, 1, 1, true )
			// Max edges are inclusive: CalcCursor clamps to exactly 1.0 on the
			// last pixel row/column, and a strict '<' left that edge untagged.
			if ((x >= vx) && (x <= (vx + vw)) && (y >= vy) && (y <= (vy + vh))) then ss[ k ].Tagged = true end
		end
	end
	
	// Now grab the device with the highest priority that is tagged
	local p = -1
	local devn = ""
	for k, v in pairs( ss ) do
		if (type( v ) == "table") then
			if (v.Tagged) then
				// >= like GetTopDeviceAt, so press-grab and release-click
				// break priority ties the same way.
				if (v.Priority >= p) then
					p = v.Priority
					devn = k
				end
			end
		end
	end
	
	// Obtain the device from storage
	local dev_name = tostring( ent:EntIndex() ) .. ":" .. devn
	if (!PCMod.SDraw.DevMap[ dev_name ]) then
		if (PCMod.Cfg.DebugHitbox) then
			PCMod.Msg( string.format( "REGCLICK x=%.3f y=%.3f -> NO DEVICE (devn='%s')", x, y, devn ) )
		end
		PCMod.Msg( "Clicked on unexistant device!", true )
		return
	end
	local device = ss[ devn ]
	
	// Calculate where abouts the click is on the device (same visual rect as draw;
	// noanim so a sliding menu is hit-tested at its settled position)
	local vx, vy, vw, vh = PCMod.SDraw.GetDeviceVisualRect( device, 1, 1, true )
	local dx = (x - vx) / vw
	local dy = (y - vy) / vh
	
	// Register the click and set the focus
	PCMod.SDraw.DevFocus = devn
	if (PCMod.Cfg.DebugHitbox) then
		PCMod.Msg( string.format( "REGCLICK x=%.3f y=%.3f dx=%.3f dy=%.3f dev=%s", x, y, dx, dy, devn ) )
	end
	PCMod.SDraw.DevMap[ dev_name ]:Int_DoClick( dx, dy, right )
	//PCMod.SDraw.DevMap[ dev_name ]:DoClick( dx, dy )
end

// ---------------------------------------------------------------------------------------------------------
// CalcTextWrap - Calculates how a paragraph should wrap (returns a table of wrapped text)
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.CalcTextWrap( text, font, w )
	local cx = 0
	surface.SetFont( font )
	local txt = string.Explode( "", text )
	local tmp = {}
	local cnt = 0
	local line = 1
	for cnt=1,#txt do
		if (!tmp[ line ]) then tmp[ line ] = "" end
		local char = txt[ cnt ]
		local cw, ch = surface.GetTextSize( char )
		cx = cx + cw
		if ((cx > w) || (char == "\n")) then
			line = line + 1
			if (!tmp[ line ]) then tmp[ line ] = "" end
			cx = 0
		end
		tmp[ line ] = tmp[ line ] .. char
	end
	return tmp
end

// ---------------------------------------------------------------------------------------------------------
// BindPress - Stops a bind being run in certain circumstances, and performs actions
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.BindPress( ply, bind )
	if (PCMod.Cfg.AdvancedMode) then
		if ((bind == "+attack") || (bind == "+attack2")) then
			local right = (bind == "+attack2")
			PCMod.Msg( "[BINDPRESS] Attack bind detected!", true )
			local ent = ply:GetEyeTrace().Entity
			if ((ent) && (ent:IsValid()) && (ent.IsScreen) && ((ent:GetPos()-ply:GetPos()):Length() < 64)) then
				local ss = PCMod.SDraw.SSpaces[ ent:EntIndex() ]
				if ((ss) && (ss.SC)) then
					PCMod.Gui.RegisterClick( gui.MouseX(), gui.MouseY(), ent, right )
					return true
				else
					PCMod.Msg( "[BINDPRESS] No ScreenSpace/Cursor!", true )
				end
			else
				PCMod.Msg( "[BINDPRESS] No entity!", true )
			end
		end
	end
end
hook.Add( "PlayerBindPress", "PCMod.BindPress2", PCMod.Gui.BindPress )


// ---------------------------------------------------------------------------------------------------------
// Include the vgui file
// ---------------------------------------------------------------------------------------------------------
include( "pcmod/cl_vgui.lua" )