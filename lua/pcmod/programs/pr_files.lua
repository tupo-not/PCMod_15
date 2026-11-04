// File Manager Program for PCMod 2 \\
// Browse the PC's virtual hard drive, create/rename/delete items and open
// text files in Notepad. Uses the program-author filesystem helpers from
// programs/base.lua.

PROG.Name = "files"
PROG.Author = "PCMod"
PROG.Title = "File Manager"
PROG.Icon = "app"
PROG.OS = "personal"

PROG.SimpleMode = true

PROG.DeviceLink = "window_files"
PROG.DeviceName = "window_files"
PROG.DeviceData = {}

// Current directory ("" is the virtual root).
PROG.Path = ""

// ------------------------------------------------------------------------------------------------
// Internal helpers
// ------------------------------------------------------------------------------------------------
function PROG:CleanName( name )
	if (name == nil) then return nil end
	name = tostring( name )
	name = string.gsub( name, "^%s+", "" )
	name = string.gsub( name, "%s+$", "" )
	if ((name == "") || (name == ".") || (name == "..")) then return nil end
	if (string.find( name, "/", 1, true ) || string.find( name, "\\", 1, true )) then return nil end
	return name
end

function PROG:Refresh( status )
	if (!self.Path) then self.Path = "" end
	self.Path = self:NormalizePath( self.Path )
	if ((self.Path != "") && (!self:FolderExists( self.Path ))) then
		self.Path = ""
	end
	local list = self:ListDir( self.Path )
	if (!istable( list )) then list = {} end
	self.DeviceData.Path = self.Path
	self.DeviceData.Entries = list
	self.DeviceData.Places = self:GetPlaces()
	self.DeviceData.Tree = self:BuildFileTree()
	self.DeviceData.Status = status or ""
	self.DeviceData.Th = self:GetTheme()
	self:UpdateSS()
end

function PROG:SetPath( path )
	path = self:NormalizePath( path )
	if ((path != "") && (!self:FolderExists( path ))) then
		self:Refresh( "Folder does not exist." )
		return
	end
	self.Path = path
	self:Refresh( "" )
end

function PROG:OpenFile( path )
	path = self:NormalizePath( path )
	if (!self:FileExists( path )) then
		self:Refresh( "File does not exist." )
		return
	end
	local os = self:GetOS()
	if (!os) then return end
	if (!os.Progs[ "notepad" ]) then
		os:InstallProgram( "notepad" )
	end
	local note = os.Progs[ "notepad" ]
	if (!note) then
		self:Refresh( "Notepad is not installed." )
		return
	end
	note:Start()
	if (note.ProcessCommand) then
		note:ProcessCommand( "openpath", { path } )
	else
		note:DoCommand( "openpath", { path } )
	end
	self:Refresh( "Opened " .. self:GetBaseName( path ) )
end

// ------------------------------------------------------------------------------------------------
// Lifecycle
// ------------------------------------------------------------------------------------------------
function PROG:OnStart()
	if (!self.Path) then self.Path = "" end
	self:Refresh( "" )
end

function PROG:OnEnd()
	PCMod.Msg( "File Manager closed", true )
end

// ------------------------------------------------------------------------------------------------
// Commands from the device
// ------------------------------------------------------------------------------------------------
function PROG:DoCommand( com, args )
	args = args or {}
	if (com == "exit") then
		self:Exit()
		return
	end
	if (com == "refresh") then
		self:Refresh( "" )
		return
	end
	if (com == "up") then
		self:SetPath( self:GetParentPath( self.Path ) )
		return
	end
	if (com == "open") then
		local name = args[1]
		if (!name) then return end
		if (name == "..") then
			self:SetPath( self:GetParentPath( self.Path ) )
			return
		end
		local target = self:JoinPath( self.Path, name )
		local typ = args[2]
		if (!typ) then
			local info = self:GetItemInfo( target )
			if (info) then typ = info.Type end
		end
		if (typ == "folder") then
			self:SetPath( target )
		else
			self:OpenFile( target )
		end
		return
	end
	if (com == "newfolder") then
		local name = self:CleanName( args[1] )
		if (!name) then
			self:Refresh( "Invalid folder name." )
			return
		end
		local target = self:JoinPath( self.Path, name )
		if (self:FolderExists( target ) || self:FileExists( target )) then
			self:Refresh( "An item with that name already exists." )
			return
		end
		if (self:CreateFolder( target )) then
			self:Refresh( "Created folder '" .. name .. "'." )
		else
			self:Refresh( "Could not create the folder (is it locked?)." )
		end
		return
	end
	if (com == "rename") then
		local oldname = args[1]
		local newname = self:CleanName( args[2] )
		if ((!oldname) || (oldname == "..") || (!newname)) then
			self:Refresh( "Invalid name." )
			return
		end
		local oldpath = self:JoinPath( self.Path, oldname )
		local newpath = self:JoinPath( self.Path, newname )
		if (self:RenameItem( oldpath, newpath )) then
			self:Refresh( "Renamed to '" .. newname .. "'." )
		else
			self:Refresh( "Rename failed (name exists or item is locked)." )
		end
		return
	end
	if (com == "delete") then
		local name = args[1]
		if ((!name) || (name == "..")) then return end
		local target = self:JoinPath( self.Path, name )
		if (self:DeleteItem( target )) then
			self:Refresh( "Deleted '" .. name .. "'." )
		else
			self:Refresh( "Delete failed (the item is locked)." )
		end
		return
	end
	// Allow another program/console to jump straight to a directory.
	if (com == "openpath") then
		self:SetPath( args[1] )
		return
	end
	self:DbgMsg( "Unhandled file manager command '" .. tostring( com ) .. "'" )
end
