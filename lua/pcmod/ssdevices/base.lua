
// PCMod ScreenSpace Device | BASE DEVICE \\

// Device name
DEV.Name = "base"

// Override functions
function DEV:Paint() end
function DEV:Kill() end
function DEV:KeyPress() end
function DEV:Initialize() end
function DEV:ButtonClick() end
function DEV:ListboxSelect() end
function DEV:ListboxBlankClick() end
function DEV:OnUpdate() end
function DEV:DataRecieved() end
function DEV:QuickType() end

// Input focus
DEV.TB_Focus = ""

// Default vars
DEV.win_x = 0
DEV.win_y = 0
DEV.win_w = 0
DEV.win_h = 0

// Multi-window support (opt-in through DeviceData.WindowDrag): a left drag on
// the title bar moves the window locally, then the final position is sent back
// to the owning program.
DEV.WindowDrag = false
DEV.WindowDragging = false
DEV.WindowResize = false
DEV.WindowResizing = false
DEV.DragBar = 0.06
DEV.ResizeGrip = 0.035

// Universal program-window minimum (viewport fractions). Controls are laid out
// proportionally, but their text keeps a fixed pixel size, so shrinking past
// this point makes labels and buttons overlap each other. Programs may override
// it by sending DeviceData.MinW / MinH.
DEV.MinW = 0.5
DEV.MinH = 0.6

// ------------------------------------------------------------------------------------------------------------------------------------------------
//	 Internal Functions
// ------------------------------------------------------------------------------------------------------------------------------------------------

	function DEV:OnCreate()
		self.Textboxes = {}
		self.Listboxes = {}
		self.Elements = {}
		self.Controls = ((PCMod.UI && PCMod.UI.Widgets && PCMod.UI.Widgets.NewSet) && PCMod.UI.Widgets.NewSet()) or nil
		self.TB_Focus = ""
		self.WindowDragging = false
		self.WindowResizing = false
	end

	function DEV:Int_Reinitialize( x, y, w, h )
		// The server moved/resized the window. Destroy the old elements and let
		// the device rebuild its layout at the new geometry (the DeviceData has
		// already been applied, so content survives). Local textbox edits are
		// also kept so a GUI-scale change cannot discard unsaved typing.
		local saved = {}
		for name, tb in pairs( self.Textboxes or {} ) do
			if ((tb) && (tb.Content)) then saved[ name ] = tb.Content end
		end
		local wasDragging = self.WindowDragging
		local wasResizing = self.WindowResizing
		for _, v in pairs( self.Elements or {} ) do
			if ((v) && (v.IsValid) && (v:IsValid())) then v:Remove() end
		end
		self:OnCreate()
		self.WindowDragging = wasDragging
		self.WindowResizing = wasResizing
		self:Int_Initialize( x, y, w, h )
		for name, content in pairs( saved ) do
			if (self.Textboxes[ name ]) then self:SetTextboxText( name, content ) end
		end
	end

	function DEV:Int_KeyPress( key, txt )
		for _, v in pairs( self.Elements ) do
			if ((v) && (v:IsValid())) then
				if (v:OnKeyPress( key, txt )) then return end
			end
		end
		self:KeyPress( key, txt )
	end

	function DEV:Int_QuickType( text )
		PCMod.Msg( "SS Device recieved quicktype!", true )
		for _, v in pairs( self.Elements ) do
			if ((v) && (v:IsValid())) then
				if (v:OnQuickType( text )) then return end
			end
		end
		if (self.Textboxes[ self.TB_Focus ]) then
			if (!self.Textboxes[ self.TB_Focus ].Content) then self.Textboxes[ self.TB_Focus ].Content = "" end
			self.Textboxes[ self.TB_Focus ].Content = self.Textboxes[ self.TB_Focus ].Content .. text
			self:CalcTextWrap( self.TB_Focus )
		else
			self:QuickType( text )
		end
	end

	function DEV:Int_DoClick( x, y, right )
		// The press edge starts grabs in PCMod.SDraw.UpdateWindowGrab(). A
		// release that belongs to that grab must not click through to a control.
		if (self.WindowDragging || self.WindowResizing) then
			self:FinishWindowGrab()
			return
		end
		if (self.SuppressClick && (CurTime() < self.SuppressClick)) then
			self.SuppressClick = 0
			return
		end
		// The resize grip wins over title-bar dragging and normal clicks.
		if ((!right) && self:CanStartWindowResize( x, y )) then
			self:StartWindowResize( x, y )
			return
		end
		// A drag on the title bar moves the window instead of clicking through
		// to a control. Focus is sent when the drag ends (one round-trip).
		if ((!right) && self:CanStartWindowDrag( x, y )) then
			self:StartWindowDrag( x, y )
			return
		end
		self:FocusWindow()
		self:DoClick( x, y, right )
	end

	function DEV:DoClick( x, y, right )
		self:ProcessClick( x, y, right )
	end

	function DEV:Int_Paint( x, y, w, h )
		self:UpdateWindowResize()
		self:UpdateWindowDrag()
		self:Paint( x, y, w, h )
		if (self.WindowResize) then self:DrawResizeGrip( x, y, w, h ) end
	end

	function DEV:Int_Initialize( x, y, w, h )
		self:Tick()
		self:Initialize( x, y, w, h )
		self.win_x = x
		self.win_y = y
		self.win_w = w
		self.win_h = h
	end

	function DEV:Int_Update()
		// We have recieved an update from server, but we are NOT 'fresh'
		self:OnUpdate()
	end
	
// ------------------------------------------------------------------------------------------------------------------------------------------------
//	 Element drawing functions
// ------------------------------------------------------------------------------------------------------------------------------------------------

	function DEV:DrawControlKind( kind )
		if ((!self.Controls) || (!PCMod.UI) || (!PCMod.UI.Widgets)) then return end
		local W = PCMod.UI.Widgets
		W.Each( self.Controls, { kind }, function( k, c ) W.Paint( self, k, c ) end )
	end

	function DEV:DrawTextboxes()
		self:DrawControlKind( "textbox" )
	end

	function DEV:DrawListboxes()
		self:DrawControlKind( "listbox" )
	end

	function DEV:DrawElements()
		self:DrawControlKind( "element" )
	end
	
// ------------------------------------------------------------------------------------------------------------------------------------------------
//	 Element clicking functions
// ------------------------------------------------------------------------------------------------------------------------------------------------

	function DEV:ClickControlKind( kind, x, y, right )
		if ((!self.Controls) || (!PCMod.UI) || (!PCMod.UI.Widgets)) then return end
		local W = PCMod.UI.Widgets
		local list = self.Controls[ kind ]
		if (!list) then return end
		for i = 1, #list do
			local c = list[ i ]
			if (W.Hit( self, kind, c, x, y )) then
				W.Click( self, kind, c, x, y, right )
				if (W.StopLayer( kind )) then return end
			end
		end
	end

	function DEV:ClickTextboxes( x, y )
		self:ClickControlKind( "textbox", x, y, false )
	end

	function DEV:ClickListboxes( x, y, right )
		self:ClickControlKind( "listbox", x, y, right )
	end

	function DEV:ClickElements( x, y )
		self:ClickControlKind( "element", x, y, false )
	end

// ------------------------------------------------------------------------------------------------------------------------------------------------
//	Textbox cursor functions
// ------------------------------------------------------------------------------------------------------------------------------------------------

	function DEV:MoveCursor( tbname, char, line )
		if (char) then self.Textboxes[ tbname ].Char = char end
		if (line) then self.Textboxes[ tbname ].Line = line end
		self.Textboxes[ tbname ].CursorX = self:CharToX( self.Textboxes[ tbname ].Content, "pcmod_3d2d", char )
		PCMod.Msg( "Moving cursor! (" .. char .. ":" .. line .. ") (" .. tbname .. ")", true )
	end

	function DEV:CUR_Forward( tbname )
		if (!tbname) then tbname = self.TB_Focus end
		local tb = self.Textboxes[ tbname ]
		if (!tb) then return end
		if (!tb.Char) then tb.Char = 0 end
		self:CUR_SetPos( tbname, tb.Char+1 )
	end

	function DEV:CUR_Back( tbname )
		if (!tbname) then tbname = self.TB_Focus end
		local tb = self.Textboxes[ tbname ]
		if (!tb) then return end
		if (!tb.Char) then tb.Char = 0 end
		self:CUR_SetPos( tbname, tb.Char-1 )
	end

	function DEV:CUR_ToEnd( tbname )
		if (!tbname) then tbname = self.TB_Focus end
		local tb = self.Textboxes[ tbname ]
		if (!tb) then return end
		if (!tb.Char) then tb.Char = 0 end
		// Round 24: the position after the last character is len(content),
		// not len-1 - the cursor used to land in front of the last character
		// (and every SetTextboxText moved it there).
		self:CUR_SetPos( tbname, string.len( tb.Content ) )
	end

	function DEV:CUR_ToStart( tbname )
		if (!tbname) then tbname = self.TB_Focus end
		local tb = self.Textboxes[ tbname ]
		if (!tb) then return end
		if (!tb.Char) then tb.Char = 0 end
		self:CUR_SetPos( tbname, 0 )
	end

	function DEV:CUR_SetPos( tbname, char )
		if (!tbname) then tbname = self.TB_Focus end
		local tb = self.Textboxes[ tbname ]
		if (!tb) then return end
		if (!tb.Content) then tb.Content = "" end
		if (!tb.Char) then tb.Char = 0 end
		// Round 24: 0 is a valid cursor position (in front of the first
		// character) - it must not be mistaken for "no position given",
		// otherwise CUR_ToStart (Home) and a click on the first character
		// were silently ignored.
		if (char == nil) then char = tb.Char end
		if (!tb.TEntry) then
			// tb.W = tb.BW
		end
		local tl = string.len( tb.Content )
		char = math.Clamp( char, 0, tl )
		tb.Char = char
		local pos = self:CUR_CalcPos( tb.Content, tb.W, char, self:GetTextboxFont( tbname ), tb.TEntry, tb.ScrollOffset )
		tb.CUR_X = pos.x
		tb.CUR_Y = pos.y
	end

	function DEV:CUR_CalcPos( text, width, char, font, multiline, offset )
		if (!offset) then offset = 0 end
		surface.SetFont( font )
		local tl = string.len( text )
		char = math.Clamp( char, 0, tl )
		local str = ""
		if (char > 0) then str = string.sub( text, 1, char ) end
		if (str == "") then return { x=0, y=0 } end
		local tbl
		local line = 0
		local txt
		if (multiline) then
			tbl = PCMod.Gui.CalcTextWrap( str, font, width )
			if (#tbl == 0) then return { x=0, y=0 } end
			line = #tbl
			txt = string.Replace( tbl[ line ], "\n", "" )
		else
			line = 1
			// Round 24: the cursor of a single line field has to be measured on
			// the text IN FRONT of the cursor (str), not on the whole content -
			// otherwise the cursor bar was always drawn at the end of the field
			// while the edit position moved with the arrow keys.
			txt = string.Replace( str, "\n", "" )
		end
		local tw, th = surface.GetTextSize( string.Replace( txt, "\n", "" ) )
		local y = th*((line-1)-offset)
		local x = tw
		return { x=x, y=y }
	end

	function DEV:KeyPressTextboxes( key, txt )
		if (!self.Textboxes[ self.TB_Focus ]) then return end
		if ((key == "ctrl") || (key == "shift") || (key == "alt")) then return end
		if (key == "arrow_left") then
			self:CUR_Back()
			return
		end
		if (key == "arrow_right") then
			self:CUR_Forward()
			return
		end
		local tb = self.Textboxes[ self.TB_Focus ]
		local oldtxt = tb.Content
		local char = tb.Char
		local left = ""
		local right = ""
		local f = false
		if (char>0) then left = string.sub( oldtxt, 1, char ) end
		if (char<string.len( oldtxt )) then right = string.sub( oldtxt, char+1, string.len( oldtxt ) ) end
		if (key == "<--") then
			if (string.len( left ) > 0) then left = string.sub( left, 1, string.len( left )-1 )	end
			f = true
		end
		if (key == "enter") then
			if (tb.TEntry) then
				left = left .. "\n"
			else
				self.TB_Focus = ""
				return
			end
			f = true
		end
		if (key == "tab") then txt = "	" end
		if (f == false) then left = left .. txt end
		self.Textboxes[ self.TB_Focus ].Content = left .. right
		if (key == "<--") then
			self:CUR_Back()
		else
			self:CUR_Forward()
		end
		self:CalcTextWrap( self.TB_Focus )
	end

	function DEV:CalcTextWrap( tbname )
		local tb = self.Textboxes[ tbname ]
		// Round 33 (M-22): the textbox may not exist (anymore) - the old code
		// raised "attempt to index a nil value (local 'tb')"
		if (!tb) then return end
		if (!tb.TEntry) then return end
		local txt = tb.Content
		if (!txt) then txt = "" end
		local w = tb.W
		local font = tb.Font or "pcmod_3d2d"
		surface.SetFont( font )
		local tw, th = surface.GetTextSize( "X" )
		if (tb.ScrollBar) then w = w - tw end
		self.Textboxes[ tbname ].ContentTbl = PCMod.Gui.CalcTextWrap( txt, font, w )
	end
	
// ------------------------------------------------------------------------------------------------------------------------------------------------
//	Element Control Functions
// ------------------------------------------------------------------------------------------------------------------------------------------------

	function DEV:AddControl( kind, ctrl )
		if ((!self.Controls) || (!PCMod.UI) || (!PCMod.UI.Widgets)) then return ctrl end
		return PCMod.UI.Widgets.Add( self.Controls, kind, ctrl )
	end

	function DEV:CreateElement( class, name, theme, x, y, w, h )
		PCMod.Msg( "Creating element '" .. class .. "' with name '" .. name .. "'!", true )
		local el = PCMod.SSEL.Create( class )
		if ((!el) || (!el:IsValid())) then
			PCMod.Msg( "Failed to create element '" .. class .. "'!", true )
			return
		end
		self.Elements[ name ] = el
		self:AddControl( "element", el )
		el:SetTheme( theme )
		el:SetLayout( x, y, w, h )
		el.DEVICE = self
		el.NAME = name
		return el
	end

	function DEV:GetElement( name )
		return self.Elements[ name ]
	end

	function DEV:RemoveElement( name )
		// Round 33 (M-22): the element may not exist (anymore) - the old code
		// raised "attempt to index a nil value"
		if (!self.Elements[ name ]) then return end
		local el = self.Elements[ name ]
		if ((self.Controls) && (PCMod.UI) && (PCMod.UI.Widgets)) then
			PCMod.UI.Widgets.Remove( self.Controls, "element", el )
		end
		el:Remove()
		self.Elements[ name ] = nil
	end
	
// ------------------------------------------------------------------------------------------------------------------------------------------------
//	Element Creation functions
// ------------------------------------------------------------------------------------------------------------------------------------------------

	function DEV:CreateButton( theme, name, x, y, text, padding )
		if (!padding) then padding = 0 end
		surface.SetFont( "pcmod_3d2d" )
		local tw, th = surface.GetTextSize( text )
		tw = tw + padding
		th = th + padding
		local btn = self:CreateElement( "Button", name, theme, x-(tw*0.5), y-(th*0.5), tw, th )
		btn:SetText( text )
		btn:SetFunc( "DoClick", function( self ) self.DEVICE:ButtonClick( self.NAME ) end )
		return btn
	end
	
	function DEV:CreateButton2( theme, name, x, y, w, h, text, ico )
		local btn = self:CreateElement( "Button", name, theme, x, y, w, h )
		btn:SetText( text )
		btn:SetIcon( ico )
		btn:SetFunc( "DoClick", function( self ) self.DEVICE:ButtonClick( self.NAME ) end )
		return btn
	end	

	function DEV:CreateListbox( theme, name, x, y, w, h )
		PCMod.Msg( "Creating listbox '" .. name .. "'!", true )
		local tmp = {}
			tmp.Name = name
			tmp.X = x
			tmp.Y = y
			tmp.W = w
			tmp.H = h
			tmp.MX = x+(w/2)
			tmp.Theme = theme
			tmp.List = {}
			tmp.Order = {}
			tmp.SelItem = ""
			tmp.ScrollBar = false
			tmp.ScrollOffset = 0
			self.Listboxes[ name ] = tmp
		self:AddControl( "listbox", tmp )
		return tmp
	end

	function DEV:CreateTextbox( theme, name, x, y, w, h, text )
		PCMod.Msg( "Creating textbox '" .. name .. "'!", true )
		local tmp = {}
			tmp.Name = name
			surface.SetFont( "pcmod_3d2d" )
			local tw, th = surface.GetTextSize( text .. " " )
			tmp.BX = x-(w/2)+tw
			tmp.TX = x-(w/2)
			tmp.TMX = x-(w/2)+(tw/2)
			tmp.Y = y-(h/2)
			tmp.BW = w-tw
			tmp.W = w
			tmp.H = h
			tmp.MX = x
			tmp.MY = y
			tmp.Text = text
			tmp.Theme = theme
			tmp.Content = ""
			tmp.Locked = false
			tmp.Char = 0
			tmp.CUR_X = 0
			tmp.CUR_Y = 0
			self.Textboxes[ name ] = tmp
		self:AddControl( "textbox", tmp )
		return tmp
	end

	function DEV:CreateTextEntry( theme, name, x, y, w, h )
		PCMod.Msg( "Creating text entry '" .. name .. "'!", true )
		local tmp = {}
			tmp.Name = name
			tmp.TEntry = true
			tmp.X = x
			tmp.Y = y
			tmp.W = w
			tmp.H = h
			tmp.ScrollBar = false
			tmp.ScrollOffset = 0
			tmp.Theme = theme
			tmp.Content = ""
			tmp.Locked = false
			self.Textboxes[ name ] = tmp
		return tmp
	end

	// Font used by a textbox's editable text. Defaults to the UI font; a
	// device (e.g. Notepad) can assign a custom one per textbox.
	function DEV:GetTextboxFont( tbname )
		local tb = self.Textboxes and self.Textboxes[ tbname ]
		if (tb && tb.Font) then return tb.Font end
		return "pcmod_3d2d"
	end

	function DEV:SetTextboxFont( tbname, font )
		local tb = self.Textboxes and self.Textboxes[ tbname ]
		if (!tb) then return end
		tb.Font = font or "pcmod_3d2d"
		self:CalcTextWrap( tbname )
		if (self.TB_Focus == tbname) then self:CUR_SetPos( tbname ) end
	end
	
// ------------------------------------------------------------------------------------------------------------------------------------------------
//	Element Properties
// ------------------------------------------------------------------------------------------------------------------------------------------------

	function DEV:SetTextboxLock( tbname, locked )
		if (!self.Textboxes[ tbname ]) then return end
		self.Textboxes[ tbname ].Locked = locked
	end

	function DEV:GetTextboxText( name )
		// Round 33 (M-22): the textbox may not exist (anymore)
		if (!self.Textboxes[ name ]) then return "" end
		return self.Textboxes[ name ].Content
	end

	function DEV:SetTextboxText( name, text )
		if (!text) then text = "" end
		// Round 33 (M-22): the textbox may not exist (anymore) - the old code
		// raised "attempt to index a nil value"
		if (!self.Textboxes[ name ]) then return end
		self.Textboxes[ name ].Content = text
		self:CUR_ToEnd( name )
		self:CalcTextWrap( name )
	end

	function DEV:AddListboxItem( name, itemname, text )
		local lb = self.Listboxes[ name ]
		if (!lb) then return end
		if (!lb.Order) then lb.Order = {} end
		if (lb.List[ itemname ] == nil) then table.insert( lb.Order, itemname ) end
		lb.List[ itemname ] = text
	end

	function DEV:ClearListbox( name )
		local lb = self.Listboxes[ name ]
		if (!lb) then return end
		lb.List = {}
		lb.Order = {}
	end

	// Rows are drawn and hit-tested in insertion order. Devices that write to
	// lb.List directly (older code) still work: any key missing from Order is
	// appended, so it is never lost.
	function DEV:GetListboxOrder( lb )
		local names = {}
		local seen = {}
		if (lb.Order) then
			for _, n in ipairs( lb.Order ) do
				if ((lb.List[ n ] != nil) && (!seen[ n ])) then
					table.insert( names, n )
					seen[ n ] = true
				end
			end
		end
		for n in pairs( lb.List ) do
			if (!seen[ n ]) then
				table.insert( names, n )
				seen[ n ] = true
			end
		end
		return names
	end

	function DEV:SetListboxSelRow( name, itemname )
		self.Listboxes[ name ].SelItem = itemname
	end

	function DEV:GetListboxSelRow( name )
		return self.Listboxes[ name ].SelItem
	end

	function DEV:RemoveTextbox( name )
		self.Textboxes[ name ] = nil
	end

	function DEV:RemoveListbox( name )
		self.Listboxes[ name ] = nil
	end
	
// ------------------------------------------------------------------------------------------------------------------------------------------------
//	Calculation functions
// ------------------------------------------------------------------------------------------------------------------------------------------------

	function DEV:MouseToChar( tbname, cx, cy )
		// cx, cy are actual coords relative to the textbox
		PCMod.Msg( "cx,cy="..cx..","..cy, true )
		local tb = self.Textboxes[ tbname ]
		local txt = {}
		local fline = ""
		if (tb.TEntry) then
			// Get the text table
			self:CalcTextWrap( tbname )
			txt = self.Textboxes[ tbname ].ContentTbl
			if (!txt) then return 0 end
			if (!txt[1]) then txt[1] = "" end
			fline = string.Replace( txt[1], "\n", "" )
			if ((!fline) || (fline == "")) then return 0 end
		else
			txt = { tb.Content }
			fline = string.Replace( tb.Content, "\n", "" )
		end
		
		if (PCMod.Cfg.DebugMode) then
			print( "BASE SSDEVICE: Attempting to figure out char..." )
			PrintTable( txt )
		end
		
		// Figure out what line we are on
		surface.SetFont( tb.Font or "pcmod_3d2d" )
		local tw, th = surface.GetTextSize( fline )
		local lineid = math.Clamp( math.ceil( cy/th ), 1, #txt )
		
		if (tb.ScrollBar) then lineid = lineid + tb.ScrollOffset end
		if (lineid > #txt) then lineid = #txt end
		
		PCMod.Msg( "=> LINE ID: " .. lineid, true )
		
		// Figure out what character we are on
		local ow = 0
		local cw = 0
		local text = txt[ lineid ]
		if ((!text) || (text == "")) then return 0 end
		PCMod.Msg( "=> TEXT: " .. text, true )
		local t = string.Explode( "", text )
		local cnt
		local charid = #t
		local tw, th = surface.GetTextSize( t[1] )
		if ((cx > ow) && (cx < 5)) then charid = 0 end
		for cnt=1, #t do
			local tw, th = surface.GetTextSize( t[ cnt ] )
			cw = cw + tw
			if ((cx > (ow+(cw*0.5))) && (cx < (cw+(cw*0.5)))) then
				charid = cnt
				break
			end
		end
		PCMod.Msg( "Real line,char: " .. lineid .. "," .. charid, true )
		// Round 33 (M-16): the condition read the GLOBAL `char` (it was
		// declared as a local only further down), so it was never true and
		// the global was polluted. The local is declared here now - the
		// branch itself stays as it is: the position of a click in a multi
		// line field does not count the line breaks at all, so switching it
		// on would move the cursor to a wrong place.
		local char
		if ((lineid>1) && (char == 0)) then
			charid = 1
		end
		
		// We have line and char, now we need to figure out exactly which character we are on
		char = table.PartialVal( txt, lineid-1 ) + charid
		return char
	end

// ------------------------------------------------------------------------------------------------------------------------------------------------
//	Rendering functions
// ------------------------------------------------------------------------------------------------------------------------------------------------

	function DEV:RenderWindow( theme, x, y, w, h, caption, ch )
		if (PCMod.Gui.ThemeDraw( theme, "window", x, y, w, h, caption, ch )) then return end
		local c_pri = PCMod.Gui.GetThemeColour( theme, "Primary" )
		local c_sec = PCMod.Gui.GetThemeColour( theme, "Secondary" )
		local c_bar = PCMod.Gui.GetThemeColour( theme, "Bar" )
		local c_bar_txt = PCMod.Gui.GetThemeColour( theme, "Bar_Text" )
		local c_bor = PCMod.Gui.GetThemeColour( theme, "Border" )
		surface.SetDrawColor( c_pri.r, c_pri.g, c_pri.b, c_pri.a )
		surface.DrawRect( x, y, w, h )
		surface.SetDrawColor( c_bar.r, c_bar.g, c_bar.b, c_bar.a )
		surface.DrawRect( x, y, w, ch )
		draw.SimpleText( caption, "pcmod_3d2d", x, y+(ch/2), c_bar_txt, TEXT_ALIGN_LEFT, 1 )
		surface.DrawOutline( x, y, w, h, c_bor )
		surface.DrawLine( x, y+ch, x+w, y+ch )
	end

	function DEV:RenderText( x, y, text, col, align )
		if ((!text) || (!text[1])) then return end
		// Round 33 (M-08): the function had no theme parameter, so the global
		// `theme` (always nil) was used - the custom text drawing of a theme
		// was never called and every other addon that uses the global name
		// could change the look of the PC. The devices all carry their theme
		// in self.Th (that is what the other render functions get as well).
		local theme = self.Th
		if (PCMod.Gui.ThemeDraw( theme, "text", x, y, text, col, align )) then return end
		surface.SetFont( "pcmod_3d2d" )
		local tw, th = surface.GetTextSize( text[1] )
		for k, txt in pairs( text ) do
			local ty = y + ((k-1)*th)
			local t = tostring( txt )
			if (type(txt) == "number") then t = PCMod.Cfg.StatusCodes[ txt ] end
			if (!t) then t = "Invalid Statuscode!" end
			draw.SimpleText( t, "pcmod_3d2d", x, ty, col, align, TEXT_ALIGN_TOP )
		end
	end

	function DEV:RenderError( theme, x, y, text )
		if (PCMod.Gui.ThemeDraw( theme, "error", x, y, text )) then return end
		surface.SetFont( "pcmod_3d2d" )
		local w, h = surface.GetTextSize( text )
		local c_err = PCMod.Gui.GetThemeColour( theme, "ErrorBG" )
		local c_err_txt = PCMod.Gui.GetThemeColour( theme, "Error_Text" )
		local c_bor = PCMod.Gui.GetThemeColour( theme, "Border" )
		surface.SetDrawColor( c_err.r, c_err.g, c_err.b, c_err.a )
		surface.DrawRect( x-(w/2), y-(h/2), w, h )
		draw.SimpleText( text, "pcmod_3d2d", x, y, c_err_txt, 1, 1 )
		surface.DrawOutline( x-(w/2), y-(h/2), w, h, c_bor )
	end

	function DEV:RenderTextbox( tb )
		local c_bor = PCMod.Gui.GetThemeColour( tb.Theme, "Border" )
		local c_tbbg = PCMod.Gui.GetThemeColour( tb.Theme, "TextboxBG" )
		local c_tb_txt = PCMod.Gui.GetThemeColour( tb.Theme, "Textbox_Text" )
		surface.SetDrawColor( c_tbbg.r, c_tbbg.g, c_tbbg.b, c_tbbg.a )
		local txt = string.Replace( tb.Content, "\n", "" ) -- This gets rid of all newlines which might happen to screw up GetTextSize. -thomasfn
		// Multi-line editors may use a per-textbox font (Notepad font settings).
		local font = "pcmod_3d2d"
		if (tb.TEntry) then font = tb.Font or "pcmod_3d2d" end
		surface.SetFont( font )
		local tw, th = surface.GetTextSize( txt )
		local odec = 0
		if (tb.TEntry) then
			if (!PCMod.Gui.ThemeDraw( tb.Theme, "textentry", tb )) then
				surface.DrawRect( tb.X, tb.Y, tb.W, tb.H )
				surface.DrawOutline( tb.X, tb.Y, tb.W, tb.H, c_bor )
			end
			local strs = tb.ContentTbl
			if (strs) then
				local cnt = 0
				local lpbox = math.floor( tb.H / th )
				if (tb.ScrollOffset > (#strs-lpbox)) then tb.ScrollOffset = #strs-lpbox end
				local o = tb.ScrollOffset
				local st = o+1
				local ed = lpbox+o
				// Round 33 (M-48): #strs - lpbox can be 0 -> 0/0 = NaN. NaN is
				// TRUTHY in Lua, so the scrollbar was drawn with NaN
				// coordinates.
				if ((#strs - lpbox) <= 0) then
					odec = 0
				else
					odec = o/(#strs-lpbox)
				end
				if (ed>#strs) then ed = #strs end
				if (#strs > lpbox) then
					tb.ScrollBar = true
				else
					tb.ScrollBar = false
					tb.ScrollOffset = 0
				end
				local i = -1
				for cnt=st,ed do
					if (strs[cnt]) then
						i = i + 1
						local text = string.Replace( strs[ cnt ], "\n", "" )
						local ypos = tb.Y + (i * th)
						draw.SimpleText( text, font, tb.X, ypos, c_tb_txt, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
					end
				end
			end
			if (tb.ScrollBar) then
				surface.SetFont( font )
				local tw, th = surface.GetTextSize( "XX" )
				local c_btbg = PCMod.Gui.GetThemeColour( tb.Theme, "ButtonBG" )
				local c_bt_txt = PCMod.Gui.GetThemeColour( tb.Theme, "Button_Text" )
				surface.SetDrawColor( c_btbg.r, c_btbg.g, c_btbg.b, c_btbg.a )
				local xpos = tb.X+(tb.W-tw)
				surface.DrawRect( xpos, tb.Y+1, tw, tb.H-2 )
				surface.SetDrawColor( c_bor.r, c_bor.g, c_bor.b, c_bor.a )
				surface.DrawLine( xpos, tb.Y, xpos, tb.Y+tb.H )
				surface.DrawLine( xpos, tb.Y+th, xpos+tw, tb.Y+th )
				surface.DrawLine( xpos, (tb.Y+tb.H)-th, xpos+tw, (tb.Y+tb.H)-th )
				if (odec) then
					local oy = tb.Y+th+((tb.H-(th*2))*odec)
					surface.DrawLine( xpos, oy, xpos+tw, oy )
				end
				draw.SimpleText( "^", font, xpos+(tw/2), tb.Y+(th/2), c_bt_txt, 1, 1 )
				draw.SimpleText( "v", font, xpos+(tw/2), (tb.Y+tb.H)-(th/2), c_bt_txt, 1, 1 )
			end
		else
			if (!PCMod.Gui.ThemeDraw( tb.Theme, "textbox", tb )) then
				surface.DrawRect( tb.BX, tb.Y, tb.BW, tb.H )
				surface.DrawOutline( tb.BX, tb.Y, tb.BW, tb.H, c_bor )
			end
			draw.SimpleText( tb.Text, font, tb.TX, tb.MY, c_tb_txt, TEXT_ALIGN_LEFT, 1 )
			draw.SimpleText( txt, font, tb.BX, tb.MY, c_tb_txt, TEXT_ALIGN_LEFT, 1 )
		end
		local ch = math.Clamp( th, 0, tb.H ) -- Cursor is not going to be bigger than the textbox! -thomasfn
		if ((self.TB_Focus == tb.Name) && (tb.CUR_Y >= 0) && ((tb.CUR_Y+ch) <= tb.H)) then -- Must be > 0, otherwise the cursor is scrolled off the screen -thomasfn
			local cx = (tb.CUR_X or 0)
			local cy = (tb.CUR_Y or 0) + tb.Y
			if (tb.TEntry) then cx = cx + tb.X; else cx = cx + tb.BX; end
			surface.SetDrawColor( c_tb_txt.r, c_tb_txt.g, c_tb_txt.b, c_tb_txt.a )
			if ((CurTime()%1)>=0.5) then surface.DrawLine( cx, cy, cx, cy+ch ) end
		end
		self.Textboxes[ tb.Name ] = tb
	end

	function DEV:RenderListbox( lb )
		local c_bor = PCMod.Gui.GetThemeColour( lb.Theme, "Border" )
		local c_lbbg = PCMod.Gui.GetThemeColour( lb.Theme, "ListboxBG" )
		local c_lb_txt = PCMod.Gui.GetThemeColour( lb.Theme, "Listbox_Text" )
		local c_lb_selbg = PCMod.Gui.GetThemeColour( lb.Theme, "Listbox_SelBG" )
		local c_lb_seltxt = PCMod.Gui.GetThemeColour( lb.Theme, "Listbox_SelText" )
		if (!PCMod.Gui.ThemeDraw( lb.Theme, "listbox", lb )) then
			surface.SetDrawColor( c_lbbg.r, c_lbbg.g, c_lbbg.b, c_lbbg.a )
			surface.DrawRect( lb.X, lb.Y, lb.W, lb.H )
			surface.DrawOutline( lb.X, lb.Y, lb.W, lb.H, c_bor )
		end
		local ypos = 0
		local odec = 0
		surface.SetFont( "pcmod_3d2d" )
		local sbw, sbh = surface.GetTextSize( "XX" )
		local tw = 0
		local th = 0
		for _, v in pairs( lb.List ) do
			tw, th = surface.GetTextSize( v )
			break
		end
		local cy = 0
		if (lb.List) then
			local cnt = table.Count( lb.List )
			local t_h = cnt * th
			if (t_h > lb.H) then
				lb.ScrollBar = true
			else
				lb.ScrollBar = false
				lb.ScrollOffset = 0
			end
			local o = lb.ScrollOffset
			if (!o) then o = 0 end
			local i = 0
			odec = o/(cnt-(math.floor( lb.H / th )))
			for _, name in ipairs( self:GetListboxOrder( lb ) ) do
				local text = lb.List[ name ]
				if (i >= o) then
					local tw, th = surface.GetTextSize( text )
					cy = cy + th
					if (cy < lb.H) then
						local tcol = c_lb_txt
						if (lb.SelItem == name) then
							surface.SetDrawColor( c_lb_selbg.r, c_lb_selbg.g, c_lb_selbg.b, c_lb_selbg.a )
							surface.DrawRect( lb.X+2, lb.Y + ypos + 1, lb.W-2, th - 1 )
							tcol = c_lb_seltxt
						end
						surface.SetDrawColor( c_bor.r, c_bor.g, c_bor.b, c_bor.a )
						surface.DrawLine( lb.X, lb.Y + ypos + th, lb.X + lb.W, lb.Y + ypos + th )
						local sa = 0
						if (lb.ScrollBar) then sa = sbw * 0.5 end
						if (lb.LeftAlign) then
							draw.SimpleText( text, "pcmod_3d2d", lb.X + 6, lb.Y + ypos + (th*0.5), tcol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
						else
							draw.SimpleText( text, "pcmod_3d2d", lb.MX-sa, lb.Y + ypos + (th*0.5), tcol, 1, 1 )
						end
						ypos = ypos + th
					end
				end
				i = i + 1
			end
		end
		if (lb.ScrollBar) then
			local tw = sbw
			local th = sbh
			local c_btbg = PCMod.Gui.GetThemeColour( lb.Theme, "ButtonBG" )
			local c_bt_txt = PCMod.Gui.GetThemeColour( lb.Theme, "Button_Text" )
			surface.SetDrawColor( c_btbg.r, c_btbg.g, c_btbg.b, c_btbg.a )
			local xpos = lb.X+(lb.W-tw)
			surface.DrawRect( xpos, lb.Y+1, tw, lb.H-2 )
			surface.SetDrawColor( c_bor.r, c_bor.g, c_bor.b, c_bor.a )
			surface.DrawLine( xpos, lb.Y, xpos, lb.Y+lb.H )
			surface.DrawLine( xpos, lb.Y+th, xpos+tw, lb.Y+th )
			surface.DrawLine( xpos, (lb.Y+lb.H)-th, xpos+tw, (lb.Y+lb.H)-th )
			if (odec) then
				local oy = lb.Y+th+((lb.H-(th*2))*odec)
				surface.DrawLine( xpos, oy, xpos+tw, oy )
			end
			draw.SimpleText( "^", "pcmod_3d2d", xpos+(tw/2), lb.Y+(th/2), c_bt_txt, 1, 1 )
			draw.SimpleText( "v", "pcmod_3d2d", xpos+(tw/2), (lb.Y+lb.H)-(th/2), c_bt_txt, 1, 1 )
		end
		if (lb.Name) then self.Listboxes[ lb.Name ] = lb end
	end

	function DEV:RenderFrame( theme, title, x, y, w, h, color )
		if (PCMod.Gui.ThemeDraw( theme, "frame", title, x, y, w, h, color )) then return end
		local c_bor = PCMod.Gui.GetThemeColour( theme, "Border" )
		surface.SetFont( "pcmod_3d2d" )
		local tw, th = surface.GetTextSize( title )
		surface.SetDrawColor( c_bor.r, c_bor.g, c_bor.b, c_bor.a )
		surface.DrawLine( x, y, x, y+h )
		surface.DrawLine( x, y+h, x+w, y+h )
		surface.DrawLine( x+w, y, x+w, y+h )
		surface.DrawLine( x, y, x+((w*0.5)-(tw*0.5)), y )
		surface.DrawLine( x+((w*0.5)+(tw*0.5)), y, x+w, y )
		draw.SimpleText( title, "pcmod_3d2d", x+(w*0.5), y, color, 1, 1 )
	end
	
// ------------------------------------------------------------------------------------------------------------------------------------------------
//	Click processing functions
// ------------------------------------------------------------------------------------------------------------------------------------------------

	function DEV:Int_ListboxClick( lbname, x, y, right )
		local lb = self.Listboxes[ lbname ]
		if (!lb) then return end
		surface.SetFont( "pcmod_3d2d" )
		local sbw, sbh = surface.GetTextSize( "XX" )
		local cx = self.win_x + (self.win_w*x)
		local cy = self.win_y + (self.win_h*y)
		local xpos = lb.X+(lb.W-sbw)
		if ((cx>xpos) && (cx<(lb.X+lb.W)) && (lb.ScrollBar)) then
			if (right) then return end
			local btn = { X = xpos, Y = lb.Y, W = sbw, H = sbh }
			if (y <= 0.5) then
				// Scroll up!
				PCMod.Msg( "Scrolling up!", true )
				lb.ScrollOffset = lb.ScrollOffset - 1
			end
			local btn = { X = xpos, Y = lb.Y+(lb.H-sbh), W = sbw, H = sbh }
			if (y > 0.5) then
				// Scroll down!
				PCMod.Msg( "Scrolling down!", true )
				lb.ScrollOffset = lb.ScrollOffset + 1
			end
			lb.ScrollOffset = math.Clamp( lb.ScrollOffset, 0, table.Count( lb.List ) - math.floor( lb.H / sbh ))
			// self:CUR_SetPos( name ) -- This will re-calc the position of the cursor
		else
			local tmp = {}
			local RowH = 0
			local ypos = 0
			local oh = 0
			local o = lb.ScrollOffset
			if ((!o) || (!lb.ScrollBar)) then o = 0 end
			for _, name in ipairs( self:GetListboxOrder( lb ) ) do
				local text = lb.List[ name ]
				local tw, th = surface.GetTextSize( text )
				RowH = th
				if (oh == 0) then oh = o*RowH end
				table.insert( tmp, { name, ypos - oh } )
				ypos = ypos + th
			end
			table.insert( tmp, { "", ypos } )
			local hit = false
			for i=1, #tmp-1 do
				local yn = tmp[ i+1 ]
				local yc = tmp[ i ]
				if ((yn) && (yc)) then
					// PCMod.Msg( "Checking (" .. cx .. "," .. cy .. ") v '" .. yn[2] .. "' & '" .. yc[2] .. "'...", true )
					if ((cy < (lb.Y+yn[2])) && (cy > (lb.Y+yc[2]))) then
						PCMod.Msg( "Listbox item selected! (" .. yn[1] .. ")", true )
						self.Listboxes[ lbname ].SelItem = yc[1]
						self:ListboxSelect( lbname, yc[1], right, x, y )
						hit = true
					end
				end
			end
			if (!hit) then
				self.Listboxes[ lbname ].SelItem = ""
				self:ListboxBlankClick( lbname, right, x, y )
			end
		end
		if (lb.Name) then self.Listboxes[ lb.Name ] = lb end
	end

	function DEV:Int_TextboxClick( name, x, y )
		local tb = self.Textboxes[ name ]
		if (!tb) then return end
		self.TB_Focus = name
		local cx = self.win_x + (self.win_w*x)
		local cy = self.win_y + (self.win_h*y)
		if (!tb.TEntry) then
			tb.X = tb.BX
		end
		surface.SetFont( self:GetTextboxFont( name ) )
		local tw, th = surface.GetTextSize( "XX" )
		local xpos = tb.X+(tb.W-tw)
		if ((cx>xpos) && (cx<(tb.X+tb.W)) && (tb.ScrollBar)) then
			local btn = { X = xpos, Y = tb.Y, W = tw, H = th }
			if (y <= 0.5) then
				// Scroll up!
				PCMod.Msg( "Scrolling up!", true )
				tb.ScrollOffset = tb.ScrollOffset - 1
				if (tb.ScrollOffset < 0) then tb.ScrollOffset = 0 end
			end
			local btn = { X = xpos, Y = tb.Y+(tb.H-th), W = tw, H = th }
			if (y > 0.5) then
				// Scroll down!
				PCMod.Msg( "Scrolling down!", true )
				tb.ScrollOffset = tb.ScrollOffset + 1
			end
			self:CUR_SetPos( name ) -- This will re-calc the position of the cursor
		else
			local char = self:MouseToChar( name, cx-tb.X, cy-tb.Y )
			PCMod.Msg( "Calculated char '" .. char .. "'!", true )
			self:CUR_SetPos( name, char )
		end
		self.Textboxes[ name ] = tb
	end

// ------------------------------------------------------------------------------------------------------------------------------------------------
//	Misc functions
// ------------------------------------------------------------------------------------------------------------------------------------------------

	function DEV:CursorInTextbox( tb, x, y )
		local cx = self.win_x + (self.win_w*x)
		local cy = self.win_y + (self.win_h*y)
		if (tb.TEntry) then
			return ((cx>tb.X) && (cx<(tb.X+tb.W)) && (cy>tb.Y) && (cy<(tb.Y+tb.H)))
		else
			return ((cx>tb.BX) && (cx<(tb.BX+tb.BW)) && (cy>tb.Y) && (cy<(tb.Y+tb.H)))
		end
	end

	function DEV:CursorInListbox( lb, x, y )
		local cx = self.win_x + (self.win_w*x)
		local cy = self.win_y + (self.win_h*y)
		return ((cx>lb.X) && (cx<(lb.X+lb.W)) && (cy>lb.Y) && (cy<(lb.Y+lb.H)))
	end

	function DEV:FocusWindow()
		if ((self.ProgName) && (self.ProgName != "")) then
			self:RunProgCommand( self.ProgName, "focus" )
		end
	end

	// Draw this window above the other program windows immediately, without a
	// server round-trip (used while dragging). Each grab takes the next priority
	// from the 150..239 band (above program windows 5..100, below file pickers
	// 240 / Start menu 254), so two windows never tie at the same z-order and
	// one cannot be dragged "through" the other. The real z-order is assigned by
	// FocusWindow() when the grab ends.
	function DEV:RaiseLocal()
		if ((self.ProgName) && (self.ProgName != "") && (self.SSDevice) && (PCMod.SDraw)) then
			local nextp = ((PCMod.SDraw.RaisePriority or 149) + 1)
			if (nextp > 239) then nextp = 150 end
			// Never reuse a priority that another locally-raised program window
			// already holds, even after the counter wraps. The dragged window
			// must stay above every other program window.
			local ss = nil
			if ((self.EntID) && (PCMod.SDraw.SSpaces)) then ss = PCMod.SDraw.SSpaces[ self.EntID ] end
			if (ss) then
				for _, v in pairs( ss ) do
					if ((type( v ) == "table") && (v != self.SSDevice) && ((v.Priority or 0) >= 150) && ((v.Priority or 0) < 240)) then
						if ((v.Priority or 0) >= nextp) then nextp = (v.Priority or 0) + 1 end
					end
				end
				if (nextp > 239) then
					// Compact the local raises so the new grab can still take
					// the top slot instead of tying with an older drag.
					local raised = {}
					for _, v in pairs( ss ) do
						if ((type( v ) == "table") && (v != self.SSDevice) && ((v.Priority or 0) >= 150) && ((v.Priority or 0) < 240)) then
							table.insert( raised, v )
						end
					end
					table.sort( raised, function( a, b ) return ((a.Priority or 0) < (b.Priority or 0)) end )
					local p = 150
					for _, v in ipairs( raised ) do
						v.Priority = p
						p = p + 1
						if (p > 239) then p = 239 end
					end
					nextp = p
					if (nextp > 239) then nextp = 239 end
				end
			end
			PCMod.SDraw.RaisePriority = nextp
			self.SSDevice.Priority = nextp
		end
	end

	function DEV:CanStartWindowDrag( x, y )
		if ((!self.WindowDrag) || (self.WindowDragging)) then return false end
		if ((!self.win_w) || (self.win_w <= 0) || (!self.win_h) || (self.win_h <= 0)) then return false end
		if ((y < 0) || (y > (self.DragBar or 0.06))) then return false end
		// Do not steal clicks from title-bar buttons (close, etc.).
		local cx = self.win_x + (self.win_w * x)
		local cy = self.win_y + (self.win_h * y)
		for _, v in pairs( self.Elements or {} ) do
			if ((v) && (v.CursorInside) && (v:CursorInside( cx, cy ))) then return false end
		end
		return true
	end

	function DEV:StartWindowDrag( x, y )
		self.WindowDragging = true
		self.SuppressClick = 0
		if (PCMod.SDraw) then PCMod.SDraw.GrabActive = true end
		self:RaiseLocal()
		self.DragUIScale = (PCMod.SDraw && PCMod.SDraw.WindowScale) or 1
		self.DragOffX = 0
		self.DragOffY = 0
		self.DragMouseX = gui.MouseX()
		self.DragMouseY = gui.MouseY()
		self.DragDevX = self.SSDevice and self.SSDevice.X or (self.win_x / math.max( 1, ScrW() ))
		self.DragDevY = self.SSDevice and self.SSDevice.Y or (self.win_y / math.max( 1, ScrH() ))
		self.DragDevW = self.SSDevice and self.SSDevice.W or (self.win_w / math.max( 1, ScrW() ))
		self.DragDevH = self.SSDevice and self.SSDevice.H or (self.win_h / math.max( 1, ScrH() ))
	end

	// Called by PCMod.SDraw.UpdateWindowGrab() on the actual mouse press.
	function DEV:TryStartWindowGrab( mx, my )
		if (!(self.WindowDrag || self.WindowResize)) then return false end
		local d = self.SSDevice
		if ((!d) || (!d.W) || (d.W <= 0) || (!d.H) || (d.H <= 0)) then return false end
		local sw, sh = ScrW(), ScrH()
		local S = (PCMod.SDraw && PCMod.SDraw.WindowScale) or 1
		if ((sw <= 0) || (sh <= 0)) then return false end
		local lx = (mx - (d.X * sw)) / (d.W * sw * S)
		local ly = (my - (d.Y * sh)) / (d.H * sh * S)
		if ((lx < 0) || (lx > 1) || (ly < 0) || (ly > 1)) then return false end
		if (self.WindowResize && self:CanStartWindowResize( lx, ly )) then
			self:StartWindowResize( lx, ly )
			return true
		end
		if (self.WindowDrag && self:CanStartWindowDrag( lx, ly )) then
			self:StartWindowDrag( lx, ly )
			return true
		end
		return false
	end

	function DEV:FinishWindowGrab()
		local move = self.WindowDragging
		local size = self.WindowResizing
		if ((!move) && (!size)) then return end
		self.WindowDragging = false
		self.WindowResizing = false
		// The release click is already swallowed by PCMod.SDraw.GrabActive in
		// RegisterClick (it stays true until this finishes, so the release can
		// never click through to a control). Do not set a long Suppress* window
		// here: a 0.3s one left a dead zone that ate the next legitimate click.
		self.SuppressClick = 0
		if (PCMod.SDraw) then
			PCMod.SDraw.GrabActive = false
			PCMod.SDraw.SuppressClicksUntil = 0
		end
		if ((self.ProgName) && (self.ProgName != "") && (self.SSDevice)) then
			if (move) then
				self:RunProgCommand( self.ProgName, "win_move", string.format( "%.4f", self.SSDevice.X ), string.format( "%.4f", self.SSDevice.Y ) )
			elseif (size) then
				self:RunProgCommand( self.ProgName, "win_resize", string.format( "%.4f", self.SSDevice.W or 0.62 ), string.format( "%.4f", self.SSDevice.H or 0.72 ) )
			end
		end
		// Raise the window for real after the move/resize, so the server's
		// screen update already carries the final geometry.
		self:FocusWindow()
	end

	// Minimum window size in viewport fractions. Returns safe defaults if a
	// malformed payload ever puts non-numeric values on the device.
	function DEV:GetMinWindowSize()
		local mw = tonumber( self.MinW ) or 0.5
		local mh = tonumber( self.MinH ) or 0.6
		return math.Clamp( mw, 0.05, 1 ), math.Clamp( mh, 0.05, 1 )
	end

	// Shared geometry model: SSDevice remains the wire-facing X/Y/W/H, while
	// the clamp/minimum rules come from PCMod.Window (same code as the server).
	function DEV:GetWindowModel()
		local win = self.WindowModel
		if ((!win) && (PCMod.Window)) then
			win = PCMod.Window.New()
			self.WindowModel = win
		end
		if (!win) then return nil end
		win:SetFromDevice( self.SSDevice )
		local mw, mh = self:GetMinWindowSize()
		win:SetMin( mw, mh )
		return win
	end

	function DEV:CanStartWindowResize( x, y )
		if ((!self.WindowResize) || (self.WindowResizing) || (self.WindowDragging)) then return false end
		if ((!self.win_w) || (self.win_w <= 0) || (!self.win_h) || (self.win_h <= 0)) then return false end
		local grip = self.ResizeGrip or 0.035
		return ((x >= (1 - grip)) && (y >= (1 - grip)))
	end

	function DEV:StartWindowResize( x, y )
		self.WindowResizing = true
		self.SuppressClick = 0
		if (PCMod.SDraw) then PCMod.SDraw.GrabActive = true end
		self:RaiseLocal()
		self.ResizeUIScale = (PCMod.SDraw && PCMod.SDraw.WindowScale) or 1
		self.ResizeOffX = 0
		self.ResizeOffY = 0
		self.ResizeMouseX = gui.MouseX()
		self.ResizeMouseY = gui.MouseY()
		self.ResizeStartW = self.win_w
		self.ResizeStartH = self.win_h
	end

	// Live resize: rebuild the control layout at the new pixel size while the
	// grip is dragged. Int_Reinitialize keeps the user's textbox contents.
	function DEV:UpdateWindowResize()
		if (!self.WindowResizing) then return end
		local down = false
		if (input && input.IsMouseDown) then down = input.IsMouseDown( MOUSE_LEFT ) end
		if (!down) then
			self:FinishWindowGrab()
			return
		end
		if ((!gui) || (!gui.MouseX) || (!ScrW) || (!ScrH)) then return end
		local sw, sh = ScrW(), ScrH()
		if ((sw <= 0) || (sh <= 0)) then return end
		local S = self.ResizeUIScale or 1
		local vw, vh = sw * S, sh * S
		// Pixel limits: the visible window may not leave the viewport/taskbar.
		// Near a corner the remaining space can be smaller than the nominal
		// minimum, so cap the minimum to it instead of pushing the window out.
		local maxW = math.max( 1, sw - self.win_x )
		local maxH = math.max( 1, (0.94 * sh) - self.win_y )
		local nw, nh
		local win = self:GetWindowModel()
		if (win) then
			local rawW = (self.ResizeStartW + (gui.MouseX() - self.ResizeMouseX)) / vw
			local rawH = (self.ResizeStartH + (gui.MouseY() - self.ResizeMouseY)) / vh
			nw, nh = win:ClampSize( rawW, rawH, maxW / vw, maxH / vh )
		else
			local minWf, minHf = self:GetMinWindowSize()
			local minW = math.min( minWf * vw, maxW )
			local minH = math.min( minHf * vh, maxH )
			local pxW = math.Clamp( self.ResizeStartW + (gui.MouseX() - self.ResizeMouseX), minW, maxW )
			local pxH = math.Clamp( self.ResizeStartH + (gui.MouseY() - self.ResizeMouseY), minH, maxH )
			nw = pxW / vw
			nh = pxH / vh
		end
		nw = tonumber( string.format( "%.4f", nw ) ) or nw
		nh = tonumber( string.format( "%.4f", nh ) ) or nh
		pxW = nw * vw
		pxH = nh * vh
		if ((math.abs( pxW - self.win_w ) < 2) && (math.abs( pxH - self.win_h ) < 2)) then return end
		if (self.SSDevice) then
			self.SSDevice.W = nw
			self.SSDevice.H = nh
		end
		self:Int_Reinitialize( self.win_x, self.win_y, pxW, pxH )
	end

	function DEV:DrawResizeGrip( x, y, w, h )
		local d = math.max( 5, math.min( w, h ) * 0.018 )
		local gx = x + w - 2
		local gy = y + h - 2
		surface.SetDrawColor( 255, 255, 255, 150 )
		for i = 1, 3 do
			surface.DrawLine( gx - (i * d), gy, gx, gy - (i * d) )
		end
		surface.SetDrawColor( 0, 0, 0, 120 )
		for i = 1, 3 do
			surface.DrawLine( gx - (i * d) - 1, gy - 1, gx - 1, gy - (i * d) - 1 )
		end
	end

	// Move every child control with the window. This lets the drag look right
	// without a network round-trip per frame.
	function DEV:TranslateWindow( dx, dy )
		if ((!dx) || (!dy) || ((dx == 0) && (dy == 0))) then return end
		self.win_x = self.win_x + dx
		self.win_y = self.win_y + dy
		for _, lb in pairs( self.Listboxes or {} ) do
			lb.X = (lb.X or 0) + dx
			lb.Y = (lb.Y or 0) + dy
			lb.MX = lb.X + ((lb.W or 0) * 0.5)
		end
		for _, tb in pairs( self.Textboxes or {} ) do
			if (tb.BX) then tb.BX = tb.BX + dx end
			if (tb.TX) then tb.TX = tb.TX + dx end
			if (tb.TMX) then tb.TMX = tb.TMX + dx end
			if (tb.X) then tb.X = tb.X + dx end
			if (tb.MX) then tb.MX = tb.MX + dx end
			tb.Y = (tb.Y or 0) + dy
			tb.MY = (tb.MY or 0) + dy
		end
		for _, el in pairs( self.Elements or {} ) do
			if ((el) && (el.SetLayout)) then el:SetLayout( el.X + dx, el.Y + dy, el.W, el.H ) end
		end
	end

	function DEV:UpdateWindowDrag()
		if (!self.WindowDragging) then return end
		local down = false
		if (input && input.IsMouseDown) then down = input.IsMouseDown( MOUSE_LEFT ) end
		if (!down) then
			self:FinishWindowGrab()
			return
		end
		if ((!gui) || (!gui.MouseX) || (!ScrW) || (!ScrH)) then return end
		local sw, sh = ScrW(), ScrH()
		if ((sw <= 0) || (sh <= 0)) then return end
		// X/Y are normalized to the viewport, so mouse movement maps through the
		// viewport size. The visible window is W*S wide, so the clamp must use
		// the scaled size too (otherwise small GUI scales stop the window at an
		// invisible border long before the screen edge).
		local S = self.DragUIScale or 1
		local visW = (self.DragDevW or 0.62) * S
		local visH = (self.DragDevH or 0.72) * S
		local mx, my = gui.MouseX(), gui.MouseY()
		local nx, ny
		local win = self:GetWindowModel()
		if (win) then
			nx, ny = win:ClampPosition( self.DragDevX + ((mx - self.DragMouseX) / sw), self.DragDevY + ((my - self.DragMouseY) / sh), visW, visH )
		else
			nx = math.Clamp( self.DragDevX + ((mx - self.DragMouseX) / sw), 0, math.max( 0, 1 - visW ) )
			ny = math.Clamp( self.DragDevY + ((my - self.DragMouseY) / sh), 0, math.max( 0, 0.94 - visH ) )
		end
		// Match the server's rounding/clamping exactly so the in-place update
		// does not look like a resize and rebuild the window.
		nx = tonumber( string.format( "%.4f", nx ) ) or nx
		ny = tonumber( string.format( "%.4f", ny ) ) or ny
		local px = nx * sw
		local py = ny * sh
		self:TranslateWindow( px - self.win_x, py - self.win_y )
		if (self.SSDevice) then
			self.SSDevice.X = nx
			self.SSDevice.Y = ny
		end
	end

	function DEV:SubmitCommand( ... )
		RunConsoleCommand( "pc_command", self.EntID, "input", ... )
	end

	function DEV:StreamCommand( ...)
		--PrintTable({...})
		--datastream.StreamToServer( "pc_stream", { self.EntID, "input", ... }, Msg )
		self.Entity.Bilgi = {...}
		net.Start("pc_stream")
			net.WriteTable({self.EntID, "input", ...})
		net.SendToServer();
	end

	function DEV:StreamProgCommand( progname, ... )
		self:StreamCommand( "os_command", "prog_command", progname, ... )
	end

	function DEV:RunProgCommand( progname, ... )
		self:SubmitCommand( "os_command", "prog_command", progname, ... )
	end

	function DEV:DrawControls()
		if ((!self.Controls) || (!PCMod.UI) || (!PCMod.UI.Widgets)) then return end
		local W = PCMod.UI.Widgets
		W.Each( self.Controls, nil, function( kind, c ) W.Paint( self, kind, c ) end )
	end

	function DEV:Draw()
		self:DrawControls()
	end

	function DEV:ProcessClick( x, y, right )
		// Right clicks are opt-in: only devices that understand them receive
		// them, so existing windows keep behaving exactly as before.
		if (right && (!self.AllowRightClick)) then return end
		if ((!self.Controls) || (!PCMod.UI) || (!PCMod.UI.Widgets)) then return end
		local W = PCMod.UI.Widgets
		for _, kind in ipairs( W.Order ) do
			if ((!right) || (W.AllowRight( kind ))) then
				self:ClickControlKind( kind, x, y, right )
			end
		end
	end

	function DEV:PassData( devname, dname, data )
		if (!devname) then return end
		local ent = self.Entity
		if ((!ent) || (!ent:IsValid())) then return end
		local devid = tostring( ent:EntIndex() ) .. ":" .. devname
		if (PCMod.SDraw.DevMap[ devid ]) then PCMod.SDraw.DevMap[ devid ]:DataRecieved( dname, data ) end
	end

	function DEV:Tick()
		self.LastTick = CurTime()
		self.LastFrame = PCMod.SDraw.CFrame
	end

	// The following 2 functions are overrides for compatability with the old SS Devices class
	function DEV:DrawButtons()
		self:Draw()
	end

	function DEV:ClickButtons( x, y )
		self:ProcessClick( x, y )
	end