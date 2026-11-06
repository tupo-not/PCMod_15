// Base Program for PCMod 2 \\
// Rebuilt: keeps every original method and adds program-author helpers.

PROG.Name = "base"
PROG.Author = "[GU]thomasfn"
PROG.Title = "Base Program"
PROG.Icon = "app"

PROG.State = 0
PROG.OS = "personal"

PROG.SimpleMode = false

PROG.DeviceLink = ""
PROG.DeviceName = ""
PROG.DeviceData = {}

PROG.NoShortcut = false

PROG.Slot = -1

// ------------------------------------------------------------------------------------------------
// Original lifecycle hooks (programs override these)
// ------------------------------------------------------------------------------------------------
function PROG:Initialize() end
function PROG:Think() end
function PROG:DoCommand( com, args ) end
function PROG:OnStart() end
function PROG:OnEnd() end
function PROG:ProcessPacket() end
function PROG:PingSuccess() end
function PROG:TraceSuccess() end
function PROG:MessageFailed() end

function PROG:CanUse()
	return true
end

function PROG:OnInstall()
	if (!self.NoShortcut) then
		local com = "sys_openprog " .. self.Name
		if (self.OS == "server") then com = self.Name end
		self:GetOS():AddProg( self.Icon, self.Title, com )
	end
end

// ------------------------------------------------------------------------------------------------
// Original start / stop / state management
// ------------------------------------------------------------------------------------------------
function PROG:Start()
	// Already running: bring the existing window to the front instead of
	// resetting the program (this is what makes multi-window switching work
	// from the Start menu and from other programs).
	if (self.State > 0) then
		self:RequestFocus( true )
		return
	end
	self:AssignWindow()
	self:RequestFocus( false )
	self:SetState( 1 )
	self:OnActivate()
end

function PROG:Exit()
	self:OnDeactivate()
	self:RemoveFocus()
	self:SetState( 0 )
end

function PROG:GetScreenSpace()
	local ent = self.Entity
	if ((!ent) || (!ent:IsValid())) then return end
	return PCMod.Data[ ent:EntIndex() ].Drivers[ "gen_display" ]:GetScreen()
end

function PROG:SetScreenSpace( ss )
	local ent = self.Entity
	if ((!ent) || (!ent:IsValid())) then return end
	PCMod.Data[ ent:EntIndex() ].Drivers[ "gen_display" ]:SetScreen( ss )
end

function PROG:GetOS()
	local ent = self.Entity
	if ((!ent) || (!ent:IsValid())) then return end
	return PCMod.Data[ ent:EntIndex() ].Drivers[ "gen_bios" ].OS
end

function PROG:SetState( st )
	if (self.State == st) then return end
	self.State = st
	self:TriggerState( st )
end

function PROG:Tick()
	if (self.State == 0) then return end
	self:Think()
end

function PROG:TriggerState( st )
	if (!self.SimpleMode) then return end
	if (st == 0) then
		if (self.OS == "server") then
			self:GetOS().CP = nil
			self:GetOS():BuildDesktop()
		end
		self:OnEnd()
		local ss = self:GetScreenSpace()
		ss:RemoveDevice( self.DeviceName )
		ss:RemoveDevice( "win_" .. self.Name .. "_openfile" )
		ss:RemoveDevice( "win_" .. self.Name .. "_printloc" )
		self:SetScreenSpace( ss )
		// Drop the whole device payload so a reopen (or a power cycle) starts
		// with a clean window instead of a stale page/status/edit.
		self.DeviceData = {}
		return
	end
	if (st == 1) then
		if (self.OS == "server") then
			self:GetOS().CP = self.Title
			self:GetOS():BuildDesktop()
		end
		// Fresh payload on every start; OnStart re-populates what it needs.
		self.DeviceData = {}
		if (self:GetOS()) then self.DeviceData.Th = self:GetOS():GetTheme() end
		self:OnStart()
		self:UpdateSS()
	end
end

// Declarative window descriptor. The default is the old single-window
// behaviour; programs override this (see ChatServ) instead of rebuilding the
// screen-space payload by hand.
function PROG:BuildWindow()
	return {
		Type = self.DeviceLink,
		Key = self.DeviceName,
		Data = self.DeviceData,
		Drag = (self.OS == "personal"),
		Resize = (self.OS == "personal")
	}
end

function PROG:UpdateSS()
	local ss = self:GetScreenSpace()
	if ((!ss) || (!PCMod.WindowPayload)) then return end
	local win = PCMod.WindowPayload.Build( self, self:BuildWindow() )
	if ((!win) || (!win.Type) || (win.Type == "") || (!win.Key) || (win.Key == "")) then return end
	local dev = ss:MakeDevice( win.Type, win.X, win.Y, win.W, win.H, win.Data, win.Priority )
	ss:AddDevice( win.Key, dev )
	self:SetScreenSpace( ss )
	if (win.After) then win.After( self, dev ) end
end

// ------------------------------------------------------------------------------------------------
// Original window helpers (open file / print location / printing)
// ------------------------------------------------------------------------------------------------
// Central program API: a file picker that browses the whole virtual drive.
// Programs call ShowFilePicker( startpath, mode ) (or the legacy ShowOpenFile)
// and override OnFilePicked( path ) if they do not handle "openpath".
function PROG:ShowOpenFile( path )
	self:ShowFilePicker( path or "", "open" )
end

function PROG:ShowFilePicker( path, mode )
	path = self:NormalizePath( path or "" )
	if ((path != "") && (!self:FolderExists( path ))) then path = "" end
	self.PickerPath = path
	self.PickerMode = mode or "open"
	local list = self:ListDir( path )
	if (!istable( list )) then list = {} end
	local ss = self:GetScreenSpace()
	local tmp = {}
	tmp.Th = self:GetOS():GetTheme()
	tmp.Path = path
	tmp.Entries = list
	tmp.Tree = self:BuildFileTree()
	tmp.Places = self:GetPlaces()
	tmp.Mode = self.PickerMode
	tmp.ProgName = self.Name
	tmp.Parent = self.DeviceName
	local dev = ss:MakeDevice( "window_openfile", 0.2, 0.2, 0.6, 0.6, tmp, 240 )
	local on = "win_" .. self.Name .. "_openfile"
	ss:AddDevice( on, dev )
	self:SetScreenSpace( ss )
end

function PROG:PickerNavigate( path )
	path = self:NormalizePath( path or "" )
	if ((path != "") && (!self:FolderExists( path ))) then return end
	self:ShowFilePicker( path, self.PickerMode or "open" )
end

function PROG:PickerSelect( path )
	path = self:NormalizePath( path or "" )
	if ((path == "") || (!self:FileExists( path ))) then return end
	self:CloseOpenFile()
	if (self.OnFilePicked) then
		self:OnFilePicked( path )
	else
		self:DoCommand( "openpath", { path } )
	end
end

// A pre-order folder tree for any file browser UI. Each node is
// { Path, Name, Parent, Depth, Locked, HasChildren }.
PROG.TreeMaxDepth = 8
PROG.TreeMaxNodes = 600

function PROG:BuildFileTree()
	local nodes = {}
	local root = { Path = "", Name = "This PC", Parent = nil, Depth = 0, Locked = false, HasChildren = false }
	nodes[ 1 ] = root

	local function walk( path, depth )
		if (#nodes >= self.TreeMaxNodes) then return end
		local list = self:ListDir( path )
		if (!istable( list )) then return end
		local folders = {}
		for _, e in ipairs( list ) do
			if (e && e.Name && (e.Type == "folder")) then
				table.insert( folders, e )
			end
		end
		table.sort( folders, function( a, b )
			return string.lower( a.Name ) < string.lower( b.Name )
		end )
		for _, e in ipairs( folders ) do
			if (#nodes >= self.TreeMaxNodes) then return end
			local childpath = self:JoinPath( path, e.Name )
			local node = {
				Path = childpath,
				Name = e.Name,
				Parent = path,
				Depth = depth,
				Locked = (e.Locked == true),
				HasChildren = false,
			}
			local idx = #nodes + 1
			nodes[ idx ] = node
			if (depth < self.TreeMaxDepth) then
				walk( childpath, depth + 1 )
			end
			node.HasChildren = (#nodes > idx)
		end
	end

	walk( "", 1 )
	root.HasChildren = (#nodes > 1)
	return nodes
end
PROG.BuildTree = PROG.BuildFileTree

// Top-level folders, for compact "places" lists.
function PROG:GetPlaces()
	local places = {}
	local root = self:ListDir( "" )
	if (istable( root )) then
		for _, e in ipairs( root ) do
			if (e && (e.Type == "folder") && e.Name) then
				table.insert( places, {
					Name = e.Name,
					Path = e.Name,
					Locked = (e.Locked == true),
				} )
			end
		end
	end
	return places
end

// Normalise a virtual path (no leading/trailing slash, forward slashes).
function PROG:NormalizePath( path )
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

function PROG:CloseOpenFile()
	local ss = self:GetScreenSpace()
	local on = "win_" .. self.Name .. "_openfile"
	ss:RemoveDevice( on )
	self:SetScreenSpace( ss )
end

function PROG:ShowPrintLocation( isChanged )
	if (!isChanged) then
		isChanged = false
	end
	PCMod.Msg( "isChanged = "..PCMod.BTN( isChanged ), true )
	local ss = self:GetScreenSpace()
	local tmp = {}
	tmp.Th = self:GetOS():GetTheme()
	tmp.Parent = self.DeviceName
	local dev = ss:MakeDevice( "window_printloc", 0.2, 0.2, 0.6, 0.6, tmp, 240 )
	local on = "win_" .. self.Name .. "_printloc"
	PCMod.SetDevParam( self.Entity:EntIndex(), "window_printloc", 1, { "bool", isChanged } )
	ss:AddDevice( on, dev )
	self:SetScreenSpace( ss )
end

function PROG:ClosePrintLocation()
	local ss = self:GetScreenSpace()
	local on = "win_" .. self.Name .. "_printloc"
	ss:RemoveDevice( on )
	self:SetScreenSpace( ss )
end

function PROG:PrintDocument( txt, singleprinter )
	local printers = self:GetOS():GetUSBDevicePorts( "printer" )
	if (!singleprinter) then
		for _, v in pairs( printers ) do
			self:GetOS():SendUSBData( v, { "print_doc", txt } )
		end
	else
		if (printers[1]) then self:GetOS():SendUSBData( printers[1], { "print_doc", txt } ) end
	end
end

// Give a personal-OS program its own desktop window (instead of the old
// full-screen rectangle). The position is kept on the program instance, so a
// closed/reopened app returns to where the user left it; new windows cascade so
// several programs can be used at the same time.
PROG.WindowW = 0.62
PROG.WindowH = 0.72

// Universal minimum window geometry (viewport fractions), shared by every
// program. Shrinking below this makes fixed-size text collide with the
// proportional controls around it. Individual programs may raise MinW/MinH.
PROG.MinW = 0.5
PROG.MinH = 0.6

function PROG:GetMinWindowSize()
	local mw = tonumber( self.MinW ) or 0.5
	local mh = tonumber( self.MinH ) or 0.6
	return math.Clamp( mw, 0.05, 1 ), math.Clamp( mh, 0.05, 1 )
end

// Shared geometry model. The legacy WinX/WinY/WinW/WinH fields stay the public
// surface (programs and saves use them), but every clamp goes through the same
// object the client device uses.
function PROG:GetWindowModel()
	local win = self.WindowModel
	if ((!win) && (PCMod.Window)) then
		win = PCMod.Window.New()
		self.WindowModel = win
	end
	if (!win) then return nil end
	win:Set( self.WinX or 0, self.WinY or 0, self.WinW or self.WindowW or 0.62, self.WinH or self.WindowH or 0.72 )
	local minW, minH = self:GetMinWindowSize()
	win:SetMin( minW, minH )
	return win
end

function PROG:SetWindowFromModel( win )
	if (!win) then return end
	self.WinX, self.WinY, self.WinW, self.WinH = win:Get()
end

function PROG:AssignWindow()
	if (self.OS != "personal") then return end
	local os = self:GetOS()
	if (!os) then return end
	if ((self.WinX != nil) && (self.WinY != nil) && (self.WinW != nil) && (self.WinH != nil)) then return end

	local idx = 0
	for _, p in pairs( os.Progs or {} ) do
		if ((p != self) && ((p.State or 0) > 0)) then idx = idx + 1 end
	end
	local w = self.WindowW or 0.62
	local h = self.WindowH or 0.72
	local step = idx % 5
	self.WinW = w
	self.WinH = h
	self.WinX = math.Clamp( 0.02 + (step * 0.07), 0, math.max( 0, 1 - w ) )
	self.WinY = math.Clamp( 0.03 + (step * 0.05), 0, math.max( 0, 0.94 - h ) )
	if (self.WindowModel) then self.WindowModel:Set( self.WinX, self.WinY, self.WinW, self.WinH ) end
end

function PROG:GetDimensions()
	local tmp = {}
	tmp.x = 0
	tmp.y = 0
	tmp.w = 1
	tmp.h = 1
	if (self.OS == "personal") then
		self:AssignWindow()
		tmp.x = self.WinX or 0
		tmp.y = self.WinY or 0
		tmp.w = self.WinW or 0.62
		tmp.h = self.WinH or 0.72
		// Legacy/save data may hold a window smaller than the universal
		// minimum; grow it back so text cannot overlap. Store it on the
		// program as well, otherwise a later move would put the old size back.
		local win = self:GetWindowModel()
		if (win) then
			win:Set( tmp.x, tmp.y, tmp.w, tmp.h )
			win:SetSize( tmp.w, tmp.h )
			self:SetWindowFromModel( win )
			tmp.x, tmp.y, tmp.w, tmp.h = win:Get()
		else
			local minW, minH = self:GetMinWindowSize()
			tmp.w = math.max( tmp.w, minW )
			tmp.h = math.max( tmp.h, minH )
			self.WinW = tmp.w
			self.WinH = tmp.h
		end
	end
	if (self.OS == "server") then
		tmp.x = 0.58
		tmp.y = 0.12
		tmp.w = 0.36
		tmp.h = 0.84
	end
	return tmp
end

function PROG:RequestFocus( update )
	local os = self:GetOS()
	if (!os) then return end
	// Simple z-order: every focus/start gets the next integer priority. The
	// number stays in a small band so normal windows never draw over the start
	// menu or the file picker.
	os.ZCounter = (os.ZCounter or 5) + 1
	if (os.ZCounter > 100) then
		local running = {}
		for _, p in pairs( os.Progs or {} ) do
			if ((p) && ((p.State or 0) > 0)) then table.insert( running, p ) end
		end
		table.sort( running, function( a, b ) return ((a.ZOrder or 0) < (b.ZOrder or 0)) end )
		local n = 5
		for _, p in ipairs( running ) do
			n = n + 1
			p.ZOrder = n
		end
		os.ZCounter = n + 1
	end
	self.ZOrder = os.ZCounter
	os.ProgFocus = self.Name
	if (update) then
		// Raising a window only needs the priority to change. Re-sending the
		// full device data would bump Rev and make the client rebuild/refresh
		// the window (closing menus and resetting text fields), so update the
		// existing screen-space entry in place.
		local ss = self:GetScreenSpace()
		local dev = nil
		if (ss && ss.GetDevice) then dev = ss:GetDevice( self.DeviceName ) end
		if (dev) then
			dev.Priority = self:GetPriority()
			self:SetScreenSpace( ss )
		else
			self:UpdateSS()
		end
	end
end

function PROG:RemoveFocus()
	local os = self:GetOS()
	if (!os) then return end
	if (os.ProgFocus == self.Name) then
		os.ProgFocus = ""
		// Focus the topmost remaining window for status/introspection. Its
		// ZOrder is already correct, so no screen update is needed.
		local best = nil
		for _, p in pairs( os.Progs or {} ) do
			if ((p != self) && ((p.State or 0) > 0)) then
				if ((!best) || ((p.ZOrder or 0) > (best.ZOrder or 0))) then best = p end
			end
		end
		if (best) then os.ProgFocus = best.Name end
	end
end

function PROG:GetPriority()
	if ((self.State or 0) <= 0) then return 5 end
	return self.ZOrder or 5
end

// ================================================================================================
// NEW HELPERS FOR PROGRAM AUTHORS
// ================================================================================================

// Called when the program gains focus; override freely.
function PROG:OnActivate() end
// Called when the program loses focus; override freely.
function PROG:OnDeactivate() end

// Universal command entry point. Programs may implement DoCommand and call this
// to get "exit"/"close" handled automatically, or the OS can call ProcessCommand.
function PROG:ProcessCommand( com, args )
	if (!com) then return end
	com = tostring( com )
	args = args or {}
	local cmd = string.lower( com )
	if ((cmd == "exit") || (cmd == "close")) then
		self:Exit()
		return true
	end
	// Window manager commands (sent by the window device base).
	if (cmd == "focus") then
		self:RequestFocus( true )
		return true
	end
	if (cmd == "win_move") then
		local wx = tonumber( args[1] )
		local wy = tonumber( args[2] )
		if (wx != nil) then
			// GUI scale is client-side, so the client may legitimately place a
			// visually-scaled window closer to the edge than 1 - WinW. Keep
			// only absolute bounds here; the client enforces its visual limits.
			local win = self:GetWindowModel()
			if (win) then
				local nx, ny = win:ClampAbsolute( wx, wy or self.WinY or 0 )
				win:Set( nx, ny )
				self:SetWindowFromModel( win )
			else
				self.WinX = math.Clamp( wx, 0, 1 )
				self.WinY = math.Clamp( wy or self.WinY or 0, 0, 1 )
			end
		end
		self:RequestFocus( false )
		// Move the existing screen-space entry in place. A full UpdateSS()
		// would bump Rev and make the client refresh the window contents
		// (discarding unsaved edits) after a drag.
		local ss = self:GetScreenSpace()
		local dev = nil
		if (ss && ss.GetDevice) then dev = ss:GetDevice( self.DeviceName ) end
		if (dev) then
			dev.X = self.WinX or dev.X
			dev.Y = self.WinY or dev.Y
			dev.W = self.WinW or dev.W
			dev.H = self.WinH or dev.H
			dev.Priority = self:GetPriority()
			self:SetScreenSpace( ss )
		else
			self:UpdateSS()
		end
		return true
	end
	if (cmd == "win_resize") then
		local ww = tonumber( args[1] )
		local hh = tonumber( args[2] )
		if ((ww != nil) && (hh != nil)) then
			// W/H are viewport fractions of the unscaled window; at 25% GUI
			// scale a full-screen window is 4.0 wide, so allow up to that.
			// The client enforces the real visual limits for its own scale.
			local win = self:GetWindowModel()
			if (win) then
				local nw, nh = win:ClampSize( ww, hh, 4, 4 )
				win:Set( nil, nil, nw, nh )
				self:SetWindowFromModel( win )
			else
				local minW, minH = self:GetMinWindowSize()
				self.WinW = math.Clamp( ww, minW, 4 )
				self.WinH = math.Clamp( hh, minH, 4 )
			end
		end
		self:RequestFocus( false )
		// In-place geometry update, same reasoning as win_move: do not bump Rev.
		local ss = self:GetScreenSpace()
		local dev = nil
		if (ss && ss.GetDevice) then dev = ss:GetDevice( self.DeviceName ) end
		if (dev) then
			dev.W = self.WinW or dev.W
			dev.H = self.WinH or dev.H
			dev.Priority = self:GetPriority()
			self:SetScreenSpace( ss )
		else
			self:UpdateSS()
		end
		return true
	end
	// File picker commands are handled centrally for every program, so a
	// program only has to call ShowFilePicker() and (optionally) OnFilePicked().
	if (cmd == "picker_nav") then
		self:PickerNavigate( args[1] )
		return true
	end
	if (cmd == "picker_sel") then
		self:PickerSelect( args[1] )
		return true
	end
	if (cmd == "picker_close") then
		self:CloseOpenFile()
		return true
	end
	self:DoCommand( com, args )
	return true
end

// Toggle running state.
function PROG:Toggle()
	if (self.State == 0) then
		self:Start()
	else
		self:Exit()
	end
end

// ------------------------------------------------------------------------------------------------
// Data persistence helpers (JSON + util.Compress)
// ------------------------------------------------------------------------------------------------
function PROG:GetDataPath( filename )
	if (!filename) then filename = "state.dat" end
	local root = self.SaveRoot or "mydocs/"
	if (string.Right( root, 1 ) != "/") then root = root .. "/" end
	return root .. filename
end

function PROG:SaveData( filename, data )
	if (!self.Entity) then return false end
	data = data or self.DeviceData
	if (!data) then return false end
	local fn = self:GetDataPath( filename )
	local ok, err = self:WriteFile( fn, util.Compress( PCMod.TableToString( data ) ) )
	if (!ok) then return false, err end
	PCMod.Msg( "Program data saved to " .. fn, true )
	return true
end

function PROG:LoadData( filename )
	if (!self.Entity) then return end
	local fn = self:GetDataPath( filename )
	if (!self.Entity:FileFolderExist( fn )) then return end
	local text = self.Entity:ReadFile( fn )
	if ((!text) || (text == "")) then return end
	local ok, decoded = pcall( util.Decompress, text )
	if ((!ok) || (!decoded)) then return end
	local ok2, data = pcall( PCMod.StringToTable, decoded )
	if (ok2 && data) then return data end
	return nil
end

// ------------------------------------------------------------------------------------------------
// Theme helpers
// ------------------------------------------------------------------------------------------------
function PROG:GetTheme()
	local os = self:GetOS()
	if (os) then return os:GetTheme() end
	return "basic"
end

function PROG:GetThemeColor( key, default )
	local os = self:GetOS()
	// The theme table lives on the client (cl_gui.lua); programs run on the
	// server, so this helper must not crash when the GUI library is absent.
	if (os && PCMod.Gui && PCMod.Gui.GetThemeColour) then
		return PCMod.Gui.GetThemeColour( os:GetTheme(), key, default )
	end
	return default
end

// ------------------------------------------------------------------------------------------------
// Network helpers
// ------------------------------------------------------------------------------------------------
function PROG:SendNetworkPacket( destEntIndex, port, body )
	if (!destEntIndex) then return false end
	if (!port) then port = 0 end
	if (!body) then body = {} end
	local srcMAC = self.Entity.EnsureMAC && self.Entity:EnsureMAC() or nil
	local dstMAC = PCMod.MAC && PCMod.MAC.BROADCAST or nil
	local pid = PCMod.Network.CreatePacket( self.Entity:EntIndex(), destEntIndex, port, body, nil, srcMAC, dstMAC )
	if (!pid) then return false end
	PCMod.Msg( "Program sent network packet to entity " .. tostring( destEntIndex ), true )
	return pid
end

function PROG:ProcessNetworkPacket( sourceEnt, port, body )
	// Override in your program to handle incoming packets.
end

// ------------------------------------------------------------------------------------------------
// Virtual file system helpers (match the pcmod_base entity API)
// ------------------------------------------------------------------------------------------------

// Normalise a virtual path: no leading/trailing slash and no "//".
local function PCProgPath( path )
	if (!path) then return "" end
	path = tostring( path )
	path = string.gsub( path, "\\", "/" )
	path = string.gsub( path, "/+", "/" )
	while (string.Left( path, 1 ) == "/") do
		path = string.sub( path, 2 )
	end
	while ((string.len( path ) > 0) && (string.Right( path, 1 ) == "/")) do
		path = string.sub( path, 1, string.len( path ) - 1 )
	end
	return path
end

local function PCProgItem( ent, path )
	if ((!ent) || (!ent:IsValid())) then return nil end
	local norm = PCProgPath( path )
	if (norm == "") then return nil end
	// GetItemInfo uses the entity's canonical (case-insensitive) resolver, so
	// program existence checks agree with ReadFile and the VFS mutations.
	return ent:GetItemInfo( norm )
end

local function PCProgBasename( path )
	local norm = PCProgPath( path )
	if (norm == "") then return "" end
	return (string.match( norm, "([^/]+)$" ) or norm)
end

function PROG:FileExists( filename )
	local item = PCProgItem( self.Entity, filename )
	return (item != nil) && (item.Type == "file")
end

function PROG:FolderExists( foldername )
	local item = PCProgItem( self.Entity, foldername )
	return (item != nil) && (item.Type == "folder")
end

function PROG:ReadFile( filename )
	if (!self.Entity) then return "" end
	return self.Entity:ReadFile( PCProgPath( filename ) )
end

function PROG:WriteFile( filename, content )
	if (!self.Entity) then return false, "no_entity" end
	return self.Entity:WriteFileChecked( PCProgPath( filename ), content )
end

function PROG:DeleteFile( filename )
	if (!self.Entity) then return false end
	return self.Entity:UnlinkItem( PCProgPath( filename ) )
end

function PROG:ListFiles( directory )
	local out = {}
	if (!self.Entity) then return out end
	local data = PCMod.Data[ self.Entity:EntIndex() ]
	if ((!data) || (!data.HardDrive)) then return out end
	local norm = PCProgPath( directory )
	local prefix = "/" .. norm
	if (norm != "") then prefix = prefix .. "/" end
	for path in pairs( data.HardDrive ) do
		if (string.Left( path, #prefix ) == prefix) then
			local name = string.sub( path, #prefix + 1 )
			while ((string.len( name ) > 0) && (string.Right( name, 1 ) == "/")) do
				name = string.sub( name, 1, string.len( name ) - 1 )
			end
			if ((name != "") && (!string.find( name, "/", 1, true ))) then
				table.insert( out, name )
			end
		end
	end
	return out
end

// Rich directory listing: returns { {Name, Path, Type, Size, Locked}, ... }.
// Type is "file" or "folder". Results are sorted with folders first.
function PROG:ListDir( directory )
	if (!self.Entity) then return {} end
	return self.Entity:ListDir( PCProgPath( directory ) )
end

// Information about one file/folder, or nil when it does not exist.
// File entries also contain "Content" (the raw stored string).
function PROG:GetItemInfo( path )
	if (!self.Entity) then return nil end
	return self.Entity:GetItemInfo( PCProgPath( path ) )
end

// Create a folder (and any missing parents). Returns true on success.
function PROG:CreateFolder( foldername )
	if (!self.Entity) then return false end
	return self.Entity:MakeFolder( PCProgPath( foldername ) )
end

// Rename/move a file or folder (including its contents). Returns true on success.
function PROG:RenameItem( oldpath, newpath )
	if (!self.Entity) then return false end
	return self.Entity:RenameItem( PCProgPath( oldpath ), PCProgPath( newpath ) )
end
PROG.RenameFile = PROG.RenameItem
PROG.MoveItem = PROG.RenameItem

// Copy a file or folder. Returns true on success.
function PROG:CopyItem( oldpath, newpath )
	if (!self.Entity) then return false end
	return self.Entity:CopyItem( PCProgPath( oldpath ), PCProgPath( newpath ) )
end
PROG.CopyFile = PROG.CopyItem

// Delete a file or an entire folder. Returns true on success.
function PROG:DeleteItem( path )
	if (!self.Entity) then return false end
	return self.Entity:DeleteItem( PCProgPath( path ) )
end
PROG.DeleteFolder = PROG.DeleteItem

// Join a directory and a name into a normalised virtual path.
function PROG:JoinPath( directory, name )
	local dir = PCProgPath( directory )
	local nm = PCProgPath( name )
	if (dir == "") then return nm end
	if (nm == "") then return dir end
	return dir .. "/" .. nm
end

// Parent directory of a path ("" means the root).
function PROG:GetParentPath( path )
	local norm = PCProgPath( path )
	for i = string.len( norm ), 1, -1 do
		if (string.sub( norm, i, i ) == "/") then
			return string.sub( norm, 1, i - 1 )
		end
	end
	return ""
end

// File name at the end of a path.
function PROG:GetBaseName( path )
	return PCProgBasename( path )
end

// ------------------------------------------------------------------------------------------------
// Sound helpers
// ------------------------------------------------------------------------------------------------
function PROG:PlaySound( soundname )
	local os = self:GetOS()
	if (os && os.Sound) then os:Sound():PlaySound( soundname ) end
end

function PROG:StopSounds()
	local os = self:GetOS()
	if (os && os.Sound) then os:Sound():StopSounds() end
end

// ------------------------------------------------------------------------------------------------
// Timer helpers
// ------------------------------------------------------------------------------------------------
function PROG:Timer( name, delay, callback )
	if (!name) then return end
	if (!timer.Exists( name )) then
		timer.Create( name, delay, 1, callback )
	end
end

function PROG:KillTimer( name )
	if (name && timer.Exists( name )) then
		timer.Remove( name )
	end
end

// ------------------------------------------------------------------------------------------------
// USB helpers
// ------------------------------------------------------------------------------------------------
function PROG:GetUSBDevicePorts( devname )
	local os = self:GetOS()
	if (os && os.USB) then return os:USB():FindDevices( devname ) end
	return {}
end

function PROG:SendUSBData( port, data )
	local os = self:GetOS()
	if (os && os.USB) then os:USB():SendDeviceData( port, data ) end
end

function PROG:ReceiveUSBData( port )
	local os = self:GetOS()
	if (os && os.USB) then return os:USB():GetDevice( port ) end
	return nil
end

// ------------------------------------------------------------------------------------------------
// Load / unload helpers
// ------------------------------------------------------------------------------------------------
function PROG:OnLoad()
	self:Initialize()
	PCMod.Msg( "Program '" .. self.Name .. "' loaded", true )
end

function PROG:OnUnload()
	self:KillTimer( "prog_update" )
	self:Exit()
	self:RemoveFocus()
	PCMod.Msg( "Program '" .. self.Name .. "' unloaded", true )
end

function PROG:OnUninstall()
	self:OnUnload()
end

// ------------------------------------------------------------------------------------------------
// Introspection / debug
// ------------------------------------------------------------------------------------------------
function PROG:GetInfo()
	return {
		name = self.Name,
		title = self.Title,
		icon = self.Icon,
		author = self.Author,
		state = self.State,
		ops = self.OS,
		focused = (self:GetOS() && self:GetOS().ProgFocus == self.Name),
		priority = self:GetPriority()
	}
end

function PROG:DbgMsg( msg, ... )
	if (PCMod.Cfg && PCMod.Cfg.DebugMode) then
		local str = "[" .. self.Name .. "] " .. tostring( msg )
		if (select( "#", ... ) > 0) then
			for i = 1, select( "#", ... ) do
				str = str .. " " .. tostring( select( i, ... ) )
			end
		end
		PCMod.Msg( str, true )
	end
end

// Program-defined keyboard shortcut hook (handled by the OS/GUI).
function PROG:RegisterShortcut( key, handler )
	PCMod.Msg( "Program shortcut registered: " .. tostring( key ), true )
end