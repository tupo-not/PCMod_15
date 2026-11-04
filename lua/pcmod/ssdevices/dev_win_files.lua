
// PCMod ScreenSpace Device | File Manager \\

DEV.Name = "window_files"

DEV.LastTick = 0
DEV.LastFrame = 0

DEV.Th = "basic"

DEV.Path = ""
DEV.Entries = {}
DEV.Places = {}
DEV.Tree = {}
DEV.Status = ""

// Right-click context menu support (opt-in in the SS device base).
DEV.AllowRightClick = true
DEV.Menu = nil
DEV.Edit = nil
DEV.LocalStatus = ""
DEV.LastClickName = nil
DEV.LastClickTime = 0
DEV.LastEventKey = nil
DEV.LastEventTime = 0

local EDIT_BOX = { X = 0.14, Y = 0.38, W = 0.72, H = 0.22 }
local DOUBLE_CLICK_TIME = 0.55

local function ClickNow()
	if (RealTime) then return RealTime() end
	return CurTime()
end

function DEV:Initialize( x, y, w, h )
	// Make exit button
	self:CreateButton2( self.Th, "btnExit", (x+w)-(h*0.06), y, h*0.06, h*0.06, "X" )

	// Folder tree on the left, folder contents on the right.
	self:CreateListbox( self.Th, "lstPlaces", x+(w*0.025), y+(h*0.185), w*0.27, h*0.65 ).LeftAlign = true
	self:CreateListbox( self.Th, "lstFiles", x+(w*0.335), y+(h*0.185), w*0.635, h*0.65 )

	// Record window data
	self.WinX = x
	self.WinY = y
	self.WinW = w
	self.WinH = h

	self.Menu = nil
	self.Edit = nil
	self.LocalStatus = ""
	self.LastClickName = nil
	self.LastClickTime = 0
	self.LastEventKey = nil
	self.LastEventTime = 0
	self.Expanded = { [""] = true }
	self.Tree = self.Tree or {}

	self:OnUpdate()
end

function DEV:OnUpdate()
	self.Path = self.Path or ""
	if (!istable( self.Entries )) then self.Entries = {} end
	if (!istable( self.Places )) then self.Places = {} end
	if (!istable( self.Tree )) then self.Tree = {} end
	self.Status = self.Status or ""
	self.Menu = nil
	self.Edit = nil
	// Click state must not leak across navigation: otherwise a single click on
	// a same-named item in the new folder could be treated as a double-click.
	if (self.LastPath != self.Path) then
		self.LastPath = self.Path
		self.LastClickName = nil
		self.LastClickTime = 0
		self.LastEventKey = nil
		self.LastEventTime = 0
	end
	if (!self.Expanded) then self.Expanded = { [""] = true } end
	self:ExpandPath( self.Path )
	self:BuildPlaces()
	self:BuildList()
end

// ------------------------------------------------------------------------------------------------
// Folder tree helpers (navigation pane)
// ------------------------------------------------------------------------------------------------
function DEV:IsExpanded( path )
	if ((path == nil) || (path == "")) then return true end
	return ((self.Expanded != nil) && (self.Expanded[ path ] == true))
end

function DEV:SetExpanded( path, expanded )
	if (!self.Expanded) then self.Expanded = { [""] = true } end
	if (expanded) then
		self.Expanded[ path ] = true
	else
		self.Expanded[ path ] = nil
	end
end

function DEV:ToggleExpanded( path )
	if ((path == nil) || (path == "")) then return end
	self:SetExpanded( path, !self:IsExpanded( path ) )
end

// Expand every ancestor of a path (and the path itself).
function DEV:ExpandPath( path )
	if (!self.Expanded) then self.Expanded = { [""] = true } end
	self.Expanded[ "" ] = true
	path = path or ""
	if (path == "") then return end
	local cur = ""
	for part in string.gmatch( path, "[^/]+" ) do
		if (cur == "") then cur = part else cur = cur .. "/" .. part end
		self.Expanded[ cur ] = true
	end
end

// Make sure the current path (and its ancestors) exist in the tree even when
// the server only sent a one-level Places list (old program on an existing PC).
function DEV:EnsureTreePath( tree, path )
	path = path or ""
	if (path == "") then return end
	local bypath = {}
	for _, n in ipairs( tree ) do
		if (n && (n.Path != nil)) then bypath[ n.Path ] = n end
	end
	local cur = ""
	local depth = 0
	for part in string.gmatch( path, "[^/]+" ) do
		depth = depth + 1
		local parent = cur
		if (cur == "") then cur = part else cur = cur .. "/" .. part end
		local node = bypath[ cur ]
		if (!node) then
			node = { Path = cur, Name = part, Parent = parent, Depth = depth, Locked = false, HasChildren = false }
			table.insert( tree, node )
			bypath[ cur ] = node
		end
		local pnode = bypath[ parent ]
		if ((parent != "") && pnode) then pnode.HasChildren = true end
	end
end

function DEV:BuildPlaces()
	if ((!self.Listboxes) || (!self.Listboxes[ "lstPlaces" ])) then return end
	local lb = self.Listboxes[ "lstPlaces" ]
	lb.LeftAlign = true
	self:ClearListbox( "lstPlaces" )
	self.PlacePaths = {}
	self.PlaceLocked = {}
	self.NodeByKey = {}
	if (!self.Expanded) then self.Expanded = { [""] = true } end
	self.Expanded[ "" ] = true

	// Fall back to a flat one-level list when the server still runs the old
	// File Manager program and has not sent a Tree yet.
	local tree
	if (istable( self.Tree ) && (#self.Tree > 0)) then
		tree = table.Copy( self.Tree )
	else
		tree = { { Path = "", Name = "This PC", Parent = nil, Depth = 0, Locked = false, HasChildren = (#(self.Places or {}) > 0) } }
		for _, p in ipairs( self.Places or {} ) do
			if (p && p.Name) then
				table.insert( tree, {
					Path = p.Path or p.Name,
					Name = p.Name,
					Parent = "",
					Depth = 1,
					Locked = (p.Locked == true),
					HasChildren = false,
				} )
			end
		end
	end
	self:EnsureTreePath( tree, self.Path )

	local visible = { [""] = true }
	for _, node in ipairs( tree ) do
		if (node && (node.Path != nil)) then
			local path = node.Path
			local parent = node.Parent or ""
			local depth = node.Depth or 0
			local show = true
			if (depth > 0) then
				show = (visible[ parent ] == true) && self:IsExpanded( parent )
			end
			if (show) then
				visible[ path ] = true
				local key = "node:" .. path
				local label
				local ind = string.rep( "   ", depth )
				if (depth == 0) then
					label = "[D] " .. node.Name
				elseif (node.HasChildren) then
					if (self:IsExpanded( path )) then
						label = ind .. "v " .. node.Name
					else
						label = ind .. "> " .. node.Name
					end
				else
					label = ind .. "  " .. node.Name
				end
				if (node.Locked) then label = label .. " *" end
				self:AddListboxItem( "lstPlaces", key, label )
				self.PlacePaths[ key ] = path
				self.PlaceLocked[ key ] = (node.Locked == true)
				self.NodeByKey[ key ] = node
			end
		end
	end

	local sel = "node:" .. (self.Path or "")
	if (!self.PlacePaths[ sel ]) then sel = "node:" end
	self:SetListboxSelRow( "lstPlaces", sel )
end

function DEV:BuildList()
	if ((!self.Listboxes) || (!self.Listboxes[ "lstFiles" ])) then return end
	self:ClearListbox( "lstFiles" )
	self:SetListboxSelRow( "lstFiles", "" )
	self.EntryTypes = {}
	self.EntryLocked = {}

	if ((self.Path or "") != "") then
		self:AddListboxItem( "lstFiles", "..", "[..] Up" )
		self.EntryTypes[ ".." ] = "folder"
		self.EntryLocked[ ".." ] = false
	end

	for _, e in ipairs( self.Entries or {} ) do
		if (e && e.Name) then
			local prefix = "[F] "
			if (e.Type == "folder") then prefix = "[D] " end
			if (e.Locked) then prefix = prefix .. "* " end
			self:AddListboxItem( "lstFiles", e.Name, prefix .. e.Name )
			self.EntryTypes[ e.Name ] = e.Type or "file"
			self.EntryLocked[ e.Name ] = (e.Locked == true)
		end
	end
end

function DEV:FindEntry( name )
	for _, e in ipairs( self.Entries or {} ) do
		if (e && (e.Name == name)) then return e end
	end
	return nil
end

// ------------------------------------------------------------------------------------------------
// Context menu
// ------------------------------------------------------------------------------------------------
function DEV:OpenFilesMenu( name, x, y )
	if ((!name) || (name == "")) then
		self:ShowMenu( x, y, {
			{ Label = "New Folder", Action = "newfolder" },
			{ Label = "Refresh", Action = "refresh" },
		}, { Lb = "lstFiles", Sel = "", Kind = "blank" } )
		return
	end
	if (name == "..") then
		self:ShowMenu( x, y, {
			{ Label = "Open", Action = "open" },
			{ Label = "Refresh", Action = "refresh" },
		}, { Lb = "lstFiles", Sel = name, Kind = "parent" } )
		return
	end
	local kind = self.EntryTypes[ name ] or "file"
	local locked = (self.EntryLocked[ name ] == true)
	self:ShowMenu( x, y, {
		{ Label = "Open", Action = "open" },
		{ Label = "Rename", Action = "rename", Enabled = !locked },
		{ Label = "Delete", Action = "delete", Enabled = !locked },
		{ Label = "Refresh", Action = "refresh" },
	}, { Lb = "lstFiles", Sel = name, Kind = kind, Locked = locked } )
end

function DEV:OpenPlacesMenu( name, x, y )
	if ((!name) || (name == "")) then
		self:ShowMenu( x, y, {
			{ Label = "Refresh", Action = "refresh" },
		}, { Lb = "lstPlaces", Sel = "", Kind = "blank" } )
		return
	end
	self:ShowMenu( x, y, {
		{ Label = "Open", Action = "open" },
		{ Label = "Refresh", Action = "refresh" },
	}, { Lb = "lstPlaces", Sel = name, Kind = "place" } )
end

function DEV:ShowMenu( x, y, items, ctx )
	local winw = self.win_w or self.WinW or 0
	local winh = self.win_h or self.WinH or 0
	if ((!winw) || (winw <= 0) || (!winh) || (winh <= 0) || (!items) || (#items == 0)) then return end

	surface.SetFont( "pcmod_3d2d" )
	local maxw = 0
	for _, it in ipairs( items ) do
		local tw = surface.GetTextSize( it.Label )
		if (tw > maxw) then maxw = tw end
	end
	local tw, th = surface.GetTextSize( "Ag" )
	local padX = th * 0.7
	local padY = th * 0.3
	local rowH = th * 1.55
	local mw = maxw + (padX*2)
	local mh = ((#items) * rowH) + (padY*2)

	local nw = mw / winw
	local nh = mh / winh
	if (nw > 0.94) then nw = 0.94 end
	if (nh > 0.94) then nh = 0.94 end

	local nx = math.Clamp( x, 0.005, 1-nw-0.005 )
	local ny = math.Clamp( y, 0.005, 1-nh-0.005 )

	self.Menu = {
		X = nx, Y = ny, W = nw, H = nh,
		PadX = padX / winw,
		PadY = padY / winh,
		RowH = rowH / winh,
		Items = items,
		Ctx = ctx,
	}
end

function DEV:MenuClick( x, y, right )
	local m = self.Menu
	if (!m) then return false end
	if ((x < m.X) || (x > (m.X+m.W)) || (y < m.Y) || (y > (m.Y+m.H))) then return false end
	if (!right) then
		local rel = y - m.Y - m.PadY
		if (rel >= 0) then
			local idx = math.floor( rel / m.RowH ) + 1
			local it = m.Items[ idx ]
			if (it && (it.Enabled != false) && it.Action) then
				self:MenuAction( it.Action )
			end
		end
	end
	return true
end

function DEV:MenuAction( action )
	local m = self.Menu
	if ((!m) || (!m.Ctx)) then self.Menu = nil return end
	local ctx = m.Ctx

	// Delete asks for confirmation inside the same little menu.
	if (action == "delete") then
		self:ShowMenu( m.X, m.Y, {
			{ Label = "Confirm Delete", Action = "confirmdelete" },
			{ Label = "Cancel", Action = "cancel" },
		}, ctx )
		return
	end

	self.Menu = nil
	self.LastClickName = nil
	self.LocalStatus = ""

	if (action == "open") then
		if (ctx.Lb == "lstPlaces") then
			local path = self.PlacePaths[ ctx.Sel ] or ""
			self:ExpandPath( path )
			self:RunProgCommand( "files", "openpath", path )
		else
			local typ = self.EntryTypes[ ctx.Sel ] or "file"
			self:RunProgCommand( "files", "open", ctx.Sel, typ )
		end
	elseif (action == "refresh") then
		self:RunProgCommand( "files", "refresh" )
	elseif (action == "newfolder") then
		self:BeginEdit( "newfolder", "New Folder" )
	elseif (action == "rename") then
		self:BeginEdit( "rename", ctx.Sel )
	elseif (action == "confirmdelete") then
		self:RunProgCommand( "files", "delete", ctx.Sel )
	end
end

function DEV:DrawMenu( x, y, w, h )
	local m = self.Menu
	if (!m) then return end
	local c_bg = PCMod.Gui.GetThemeColour( self.Th, "ListboxBG" )
	local c_bor = PCMod.Gui.GetThemeColour( self.Th, "Border" )
	local c_txt = PCMod.Gui.GetThemeColour( self.Th, "Listbox_Text" )
	local c_dis = Color( c_txt.r, c_txt.g, c_txt.b, 110 )

	local mx = x + (w*m.X)
	local my = y + (h*m.Y)
	local mw = w*m.W
	local mh = h*m.H

	surface.SetDrawColor( c_bg.r, c_bg.g, c_bg.b, 250 )
	surface.DrawRect( mx, my, mw, mh )
	surface.DrawOutline( mx, my, mw, mh, c_bor )

	for i, it in ipairs( m.Items ) do
		local ry = my + (h*(m.PadY + ((i-1)*m.RowH)))
		if (i > 1) then
			surface.SetDrawColor( c_bor.r, c_bor.g, c_bor.b, 120 )
			surface.DrawLine( mx, ry, mx+mw, ry )
		end
		local col = c_txt
		if (it.Enabled == false) then col = c_dis end
		draw.SimpleText( it.Label, "pcmod_3d2d", mx + (w*m.PadX), ry + (h*m.RowH*0.5), col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
	end
end

// ------------------------------------------------------------------------------------------------
// Inline name editor (New Folder / Rename)
// ------------------------------------------------------------------------------------------------
function DEV:BeginEdit( mode, text )
	self.Menu = nil
	self.LocalStatus = ""
	self.LastClickName = nil
	self.Edit = { Mode = mode, Target = text, Text = text or "" }
	if (self.Edit.Mode == "newfolder") then
		self.Edit.Target = nil
	end
end

function DEV:CommitEdit()
	local e = self.Edit
	if (!e) then return end
	local name = e.Text or ""
	self.Edit = nil
	self.LocalStatus = ""
	name = string.gsub( name, "^%s+", "" )
	name = string.gsub( name, "%s+$", "" )
	if (name == "") then
		self.LocalStatus = "Name cannot be empty."
		return
	end
	if (e.Mode == "rename") then
		self:RunProgCommand( "files", "rename", e.Target, name )
	else
		self:RunProgCommand( "files", "newfolder", name )
	end
end

function DEV:EditorKey( key, txt )
	local e = self.Edit
	if (!e) then return end
	if ((key == "escape") || (key == "esc")) then
		self.Edit = nil
		self.LocalStatus = ""
		return
	end
	if (key == "enter") then
		self:CommitEdit()
		return
	end
	if (key == "<--") then
		e.Text = string.sub( e.Text or "", 1, math.max( 0, string.len( e.Text or "" ) - 1 ) )
		return
	end
	if ((key == "ctrl") || (key == "shift") || (key == "alt") || (key == "caps") || (key == "tab") || (key == "arrow_left") || (key == "arrow_right")) then return end
	if (txt && (txt != "")) then
		e.Text = (e.Text or "") .. txt
	end
end

function DEV:DrawEditor( x, y, w, h )
	local e = self.Edit
	if (!e) then return end
	local b = EDIT_BOX
	local bx = x + (w*b.X)
	local by = y + (h*b.Y)
	local bw = w*b.W
	local bh = h*b.H

	local c_bg = PCMod.Gui.GetThemeColour( self.Th, "ListboxBG" )
	local c_bor = PCMod.Gui.GetThemeColour( self.Th, "Border" )
	local c_txt = PCMod.Gui.GetThemeColour( self.Th, "Listbox_Text" )

	surface.SetDrawColor( c_bg.r, c_bg.g, c_bg.b, 250 )
	surface.DrawRect( bx, by, bw, bh )
	surface.DrawOutline( bx, by, bw, bh, c_bor )

	local title = "New Folder"
	if (e.Mode == "rename") then title = "Rename" end
	draw.SimpleText( title, "pcmod_3d2d", bx+(bw*0.5), by+(bh*0.18), c_txt, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )

	local ix = bx + (bw*0.06)
	local iy = by + (bh*0.40)
	local iw = bw*0.88
	local ih = bh*0.30
	surface.SetDrawColor( c_bor.r, c_bor.g, c_bor.b, 255 )
	surface.DrawRect( ix, iy, iw, ih )
	surface.SetDrawColor( c_bg.r, c_bg.g, c_bg.b, 255 )
	surface.DrawRect( ix+1, iy+1, iw-2, ih-2 )

	surface.SetFont( "pcmod_3d2d" )
	local txt = e.Text or ""
	local tw = surface.GetTextSize( txt )
	while ((string.len( txt ) > 0) && (tw > (iw*0.92))) do
		txt = string.sub( txt, 2 )
		tw = surface.GetTextSize( txt )
	end
	local cursor = ""
	if ((CurTime()%1) >= 0.5) then cursor = "|" end
	draw.SimpleText( txt .. cursor, "pcmod_3d2d", ix+(iw*0.03), iy+(ih*0.5), c_txt, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
	draw.SimpleText( "Enter = OK, click outside = Cancel", "pcmod_3d2d", bx+(bw*0.5), by+(bh*0.86), Color( c_txt.r, c_txt.g, c_txt.b, 160 ), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
end

// ------------------------------------------------------------------------------------------------
// Painting / input
// ------------------------------------------------------------------------------------------------
function DEV:Paint( x, y, w, h )
	self:RenderWindow( self.Th, x, y, w, h, "File Manager", h*0.06 )

	local path = self.Path or ""
	local crumb = "This PC"
	if (path != "") then
		crumb = "This PC / " .. string.gsub( path, "/", " / " )
	end
	// Keep the breadcrumb on its own line, above the pane frames, and never
	// let it run off the window (it used to overlap the "Contents" header).
	surface.SetFont( "pcmod_3d2d" )
	local maxw = w*0.94
	local tw = surface.GetTextSize( crumb )
	while ((string.len( crumb ) > 0) && (tw > maxw)) do
		crumb = string.sub( crumb, 2 )
		tw = surface.GetTextSize( crumb )
	end
	self:RenderText( x+(w*0.03), y+(h*0.078), { crumb }, Color( 0, 0, 0, 255 ), 0 )

	self:RenderFrame( self.Th, "Folders", x+(w*0.015), y+(h*0.145), w*0.29, h*0.73, Color( 255, 255, 255, 255 ) )
	self:RenderFrame( self.Th, "Contents", x+(w*0.315), y+(h*0.145), w*0.67, h*0.73, Color( 255, 255, 255, 255 ) )

	self:Draw()

	local status = self.LocalStatus
	if ((!status) || (status == "")) then status = self.Status end
	if (status && (status != "")) then
		self:RenderText( x+(w*0.5), y+(h*0.925), { status }, Color( 0, 0, 0, 255 ), 1 )
	end

	self:DrawMenu( x, y, w, h )
	self:DrawEditor( x, y, w, h )
end

function DEV:ButtonClick( btn )
	if (btn == "btnExit") then
		self:RunProgCommand( "files", "exit" )
		return
	end
end

function DEV:ListboxSelect( lbname, option, right, x, y )
	if ((!option) || (option == "")) then return end

	if (right) then
		self.LastClickName = nil
		if (lbname == "lstFiles") then
			self:OpenFilesMenu( option, x, y )
		elseif (lbname == "lstPlaces") then
			self:OpenPlacesMenu( option, x, y )
		end
		return
	end

	// Single click selects, double click opens.
	local key = lbname .. ":" .. option
	local now = ClickNow()
	// Ignore duplicate events belonging to the same physical click (press and
	// release / multiple input paths). Two real clicks are always further apart.
	if ((self.LastEventKey == key) && ((now - (self.LastEventTime or 0)) < 0.04)) then
		return
	end
	self.LastEventKey = key
	self.LastEventTime = now
	if ((self.LastClickName == key) && ((now - (self.LastClickTime or 0)) <= DOUBLE_CLICK_TIME)) then
		self.LastClickName = nil
		self.LastClickTime = 0
		if (lbname == "lstFiles") then
			local typ = self.EntryTypes[ option ] or "file"
			self:RunProgCommand( "files", "open", option, typ )
		elseif (lbname == "lstPlaces") then
			local path = self.PlacePaths[ option ] or ""
			self:ExpandPath( path )
			self:RunProgCommand( "files", "openpath", path )
		end
		return
	end

	self.LastClickName = key
	self.LastClickTime = now

	// In the tree, clicking the expand/collapse arrow toggles the branch
	// without navigating. Everything else keeps the double-click convention.
	if (lbname == "lstPlaces") then
		local node = self.NodeByKey and self.NodeByKey[ option ]
		local lb = self.Listboxes[ "lstPlaces" ]
		if (node && node.HasChildren && ((node.Depth or 0) > 0) && lb && self.win_w && (self.win_w > 0)) then
			surface.SetFont( "pcmod_3d2d" )
			local indent = surface.GetTextSize( "   " )
			local arrow = surface.GetTextSize( "v " )
			local ax = lb.X + 6 + ((node.Depth or 0) * indent)
			local px = self.win_x + (self.win_w * x)
			if ((px >= ax) && (px <= (ax + arrow))) then
				self:ToggleExpanded( node.Path )
				self:BuildPlaces()
				self:SetListboxSelRow( "lstPlaces", option )
				self.LastClickName = nil
				return
			end
		end
	end
end

function DEV:ListboxBlankClick( lbname, right, x, y )
	if (!right) then return end
	self.LastClickName = nil
	if (lbname == "lstFiles") then
		self:OpenFilesMenu( "", x, y )
	elseif (lbname == "lstPlaces") then
		self:OpenPlacesMenu( "", x, y )
	end
end

function DEV:DoClick( x, y, right )
	if (self.Edit) then
		local b = EDIT_BOX
		if ((x >= b.X) && (x <= (b.X+b.W)) && (y >= b.Y) && (y <= (b.Y+b.H))) then return end
		self.Edit = nil
		self.LocalStatus = ""
		return
	end

	if (self.Menu) then
		if (self:MenuClick( x, y, right )) then return end
		self.Menu = nil
		self.LastClickName = nil
		if (!right) then return end
	end

	self:ProcessClick( x, y, right )
end

function DEV:Tick()
	self.LastTick = CurTime()
	self.LastFrame = PCMod.SDraw.CFrame
	if (self.LastClickName && ((ClickNow() - (self.LastClickTime or 0)) > DOUBLE_CLICK_TIME)) then
		self.LastClickName = nil
	end
end

function DEV:KeyPress( key, txt )
	if (self.Edit) then
		self:EditorKey( key, txt )
		return
	end
	self:KeyPressTextboxes( key, txt )
end
