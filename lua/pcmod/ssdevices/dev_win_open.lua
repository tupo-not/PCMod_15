
// PCMod ScreenSpace Device | File Picker \\
// A generic file browser used by programs through PROG:ShowFilePicker().
// It shows the whole virtual drive (folder tree + contents) and sends
// picker_nav / picker_sel / picker_close commands back to the owning program.

DEV.Name = "window_openfile"

DEV.LastTick = 0
DEV.LastFrame = 0

DEV.Th = "basic"
DEV.Path = ""
DEV.Entries = {}
DEV.Tree = {}
DEV.Places = {}
DEV.Fs = {}
DEV.Mode = "open"
DEV.Status = ""

DEV.LastClickName = nil
DEV.LastClickTime = 0
DEV.LastEventKey = nil
DEV.LastEventTime = 0

local DOUBLE_CLICK_TIME = 0.55

local function ClickNow()
	if (RealTime) then return RealTime() end
	return CurTime()
end

local function NormPath( path )
	if (!path) then return "" end
	path = tostring( path )
	path = string.gsub( path, "\\", "/" )
	path = string.gsub( path, "/+", "/" )
	while (string.sub( path, 1, 1 ) == "/") do
		path = string.sub( path, 2 )
	end
	while ((string.len( path ) > 0) && (string.sub( path, -1 ) == "/")) do
		path = string.sub( path, 1, string.len( path ) - 1 )
	end
	return path
end

local function JoinPath( dir, name )
	dir = NormPath( dir )
	name = NormPath( name )
	if (dir == "") then return name end
	if (name == "") then return dir end
	return dir .. "/" .. name
end

local function ParentPath( path )
	path = NormPath( path )
	for i = string.len( path ), 1, -1 do
		if (string.sub( path, i, i ) == "/") then
			return string.sub( path, 1, i - 1 )
		end
	end
	return ""
end

local function BaseName( path )
	path = NormPath( path )
	if (path == "") then return "" end
	return (string.match( path, "([^/]+)$" ) or path)
end

function DEV:Initialize( x, y, w, h )
	self:CreateButton2( self.Th, "btnExit", (x+w)-(h*0.1), y, h*0.1, h*0.1, "X" )
	self:CreateListbox( self.Th, "lstPlaces", x+(w*0.025), y+(h*0.185), w*0.27, h*0.59 ).LeftAlign = true
	self:CreateListbox( self.Th, "lstFiles", x+(w*0.335), y+(h*0.185), w*0.635, h*0.59 )
	self:CreateButton2( self.Th, "btnSelect", x+(w*0.02), y+(h*0.84), w*0.46, h*0.09, "Select" )
	self:CreateButton2( self.Th, "btnCancel", x+(w*0.52), y+(h*0.84), w*0.46, h*0.09, "Cancel" )

	self.WinX = x
	self.WinY = y
	self.WinW = w
	self.WinH = h

	self.Expanded = { [""] = true }
	self.LastClickName = nil
	self.LastClickTime = 0
	self.LastEventKey = nil
	self.LastEventTime = 0

	self:OnUpdate()
end

function DEV:OnUpdate()
	self.Path = NormPath( self.Path or "" )
	if (!istable( self.Entries )) then self.Entries = {} end
	if (!istable( self.Tree )) then self.Tree = {} end
	if (!istable( self.Places )) then self.Places = {} end
	if (!istable( self.Fs )) then self.Fs = {} end
	self.Mode = self.Mode or "open"
	self.Status = self.Status or ""
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
// Folder tree helpers
// ------------------------------------------------------------------------------------------------
function DEV:IsExpanded( path )
	if ((path == nil) || (path == "")) then return true end
	return ((self.Expanded != nil) && (self.Expanded[ path ] == true))
end

function DEV:ToggleExpanded( path )
	if ((path == nil) || (path == "")) then return end
	if (!self.Expanded) then self.Expanded = { [""] = true } end
	self.Expanded[ path ] = !self:IsExpanded( path )
end

function DEV:ExpandPath( path )
	if (!self.Expanded) then self.Expanded = { [""] = true } end
	self.Expanded[ "" ] = true
	path = NormPath( path or "" )
	if (path == "") then return end
	local cur = ""
	for part in string.gmatch( path, "[^/]+" ) do
		if (cur == "") then cur = part else cur = cur .. "/" .. part end
		self.Expanded[ cur ] = true
	end
end

// Make sure the current path (and its ancestors) are represented even when
// an older program only sends a one-level Places list.
function DEV:EnsureTreePath( tree, path )
	path = NormPath( path or "" )
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
	self.NodeByKey = {}
	if (!self.Expanded) then self.Expanded = { [""] = true } end
	self.Expanded[ "" ] = true

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
				local ind = string.rep( "   ", depth )
				local label
				if (depth == 0) then
					label = "[D] " .. node.Name
				elseif (node.HasChildren) then
					label = ind .. (self:IsExpanded( path ) && "v " || "> ") .. node.Name
				else
					label = ind .. "  " .. node.Name
				end
				if (node.Locked) then label = label .. " *" end
				self:AddListboxItem( "lstPlaces", key, label )
				self.PlacePaths[ key ] = path
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
	self.EntryTypes = {}
	self.EntryLocked = {}

	// Legacy payload (old ShowOpenFile) only has Fs: a flat list of file names.
	local source = self.Entries or {}
	if ((#source == 0) && (#(self.Tree or {}) == 0) && (#(self.Places or {}) == 0) && (#(self.Fs or {}) > 0)) then
		source = {}
		for _, name in ipairs( self.Fs ) do
			if (name && (name != "") && (name != "Empty")) then
				table.insert( source, { Name = name, Type = "file", Locked = false } )
			end
		end
	end

	if ((self.Path or "") != "") then
		self:AddListboxItem( "lstFiles", "..", "[..] Up" )
		self.EntryTypes[ ".." ] = "folder"
		self.EntryLocked[ ".." ] = false
	end
	for _, e in ipairs( source ) do
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

// ------------------------------------------------------------------------------------------------
// Commands back to the program
// ------------------------------------------------------------------------------------------------
function DEV:SendPicker( com, arg )
	if (self.ProgName) then
		if (arg != nil) then
			self:RunProgCommand( self.ProgName, com, arg )
		else
			self:RunProgCommand( self.ProgName, com )
		end
		return
	end
	// Legacy program that still uses the old open-file window protocol.
	if (!self.Parent) then return end
	if (com == "picker_close") then
		self:PassData( self.Parent, "runcommand", "closebrowse" )
	elseif (com == "picker_sel") then
		self:PassData( self.Parent, "filename", BaseName( arg ) )
		self:PassData( self.Parent, "runcommand", "closebrowse" )
	end
end

function DEV:OpenEntry( name )
	if ((!name) || (name == "")) then return end
	if (name == "..") then
		self:SendPicker( "picker_nav", ParentPath( self.Path ) )
		return
	end
	local typ = self.EntryTypes[ name ] or "file"
	local full = JoinPath( self.Path, name )
	if (typ == "folder") then
		self:SendPicker( "picker_nav", full )
	else
		self:SendPicker( "picker_sel", full )
	end
end

// ------------------------------------------------------------------------------------------------
// Painting / input
// ------------------------------------------------------------------------------------------------
function DEV:Paint( x, y, w, h )
	local title = "Open File"
	if (self.Mode == "save") then title = "Save File" end
	self:RenderWindow( self.Th, x, y, w, h, title, h*0.06 )

	local path = self.Path or ""
	local crumb = "This PC"
	if (path != "") then
		crumb = "This PC / " .. string.gsub( path, "/", " / " )
	end
	surface.SetFont( "pcmod_3d2d" )
	local maxw = w*0.94
	local tw = surface.GetTextSize( crumb )
	while ((string.len( crumb ) > 0) && (tw > maxw)) do
		crumb = string.sub( crumb, 2 )
		tw = surface.GetTextSize( crumb )
	end
	self:RenderText( x+(w*0.03), y+(h*0.078), { crumb }, Color( 0, 0, 0, 255 ), 0 )

	self:RenderFrame( self.Th, "Folders", x+(w*0.015), y+(h*0.145), w*0.29, h*0.66, Color( 255, 255, 255, 255 ) )
	self:RenderFrame( self.Th, "Files", x+(w*0.315), y+(h*0.145), w*0.67, h*0.66, Color( 255, 255, 255, 255 ) )

	self:Draw()

	if (self.Status && (self.Status != "")) then
		self:RenderText( x+(w*0.5), y+(h*0.79), { self.Status }, Color( 0, 0, 0, 255 ), 1 )
	end
end

function DEV:ButtonClick( btn )
	if ((btn == "btnExit") || (btn == "btnCancel")) then
		self:SendPicker( "picker_close" )
		return
	end
	if (btn == "btnSelect") then
		local sel = self:GetListboxSelRow( "lstFiles" )
		if ((sel) && (sel != "")) then
			self:OpenEntry( sel )
		end
		return
	end
end

function DEV:ListboxSelect( lbname, option, right, x, y )
	if ((!option) || (option == "")) then return end
	local now = ClickNow()

	// Ignore duplicate events belonging to the same physical click.
	local key = lbname .. ":" .. option
	if ((self.LastEventKey == key) && ((now - (self.LastEventTime or 0)) < 0.04)) then
		return
	end
	self.LastEventKey = key
	self.LastEventTime = now

	if ((self.LastClickName == key) && ((now - (self.LastClickTime or 0)) <= DOUBLE_CLICK_TIME)) then
		self.LastClickName = nil
		self.LastClickTime = 0
		if (lbname == "lstPlaces") then
			local path = self.PlacePaths[ option ] or ""
			self:SendPicker( "picker_nav", path )
		elseif (lbname == "lstFiles") then
			self:OpenEntry( option )
		end
		return
	end

	self.LastClickName = key
	self.LastClickTime = now

	// Tree arrows toggle a branch without navigating.
	if ((lbname == "lstPlaces") && (!right)) then
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
end

function DEV:Tick()
	self.LastTick = CurTime()
	self.LastFrame = PCMod.SDraw.CFrame
	if (self.LastClickName && ((ClickNow() - (self.LastClickTime or 0)) > DOUBLE_CLICK_TIME)) then
		self.LastClickName = nil
	end
end

function DEV:KeyPress( key, txt )
	if ((key == "escape") || (key == "esc")) then
		self:SendPicker( "picker_close" )
		return
	end
	self:KeyPressTextboxes( key, txt )
end

function DEV:Kill()
end
