-- File Manager command mock test (plain Lua after translation).
SERVER = true
CLIENT = false

function string.Left( s, n ) return string.sub( s, 1, n ) end
function string.Right( s, n ) return string.sub( s, math.max( 1, #s - n + 1 ) ) end
function string.Explode( sep, str )
	local out = {}
	if (str == nil) then return out end
	local start = 1
	while true do
		local a, b = string.find( str, sep, start, true )
		if (not a) then
			table.insert( out, string.sub( str, start ) )
			break
		end
		table.insert( out, string.sub( str, start, a - 1 ) )
		start = b + 1
	end
	return out
end
function istable( v ) return type( v ) == "table" end
function table.Copy( t )
	if (type( t ) ~= "table") then return t end
	local o = {}
	for k, v in pairs( t ) do o[ k ] = table.Copy( v ) end
	return o
end

PCMod = {}
PCMod.Data = {}
PCMod.Msg = function() end
PCMod.Cfg = {}
function AddCSLuaFile() end
util = {}
util.Compress = function( s ) return s end
util.Decompress = function( s ) return s end

ENT = {}
dofile( "pcmod_shared.lua" )
local ent = setmetatable( {}, { __index = ENT } )
function ent:EntIndex() return 1 end
function ent:IsValid() return true end
PCMod.Data[ 1 ] = { HardDrive = {} }

local noteStub = { opened = nil }
function noteStub:Start() end
function noteStub:ProcessCommand( com, args )
	if (com == "openpath") then self.opened = args[ 1 ] end
end
local osStub = { Progs = { notepad = noteStub } }
function osStub:GetTheme() return "basic" end
function osStub:InstallProgram() end

PROG = {}
dofile( "sh_window.lua" )
dofile( "sv_window_payload.lua" )
dofile( "pcmod_base.lua" )
local base = table.Copy( PROG )
PROG = table.Copy( base )
dofile( "pcmod_files.lua" )

local prog = table.Copy( PROG )
prog.Entity = ent
prog.DeviceData = {}
prog.UpdateSS = function() end
prog.GetOS = function() return osStub end

local function assertTrue( v, msg )
	if (not v) then error( "FAILED: " .. msg, 2 ) end
end

prog:OnStart()
assertTrue( prog.DeviceData.Path == "", "starts at root" )

prog:DoCommand( "newfolder", { "Docs" } )
assertTrue( prog:FolderExists( "Docs" ), "created folder via command" )
assertTrue( istable( prog.DeviceData.Places ), "places list exists" )
local hasDocsPlace = false
for _, p in ipairs( prog.DeviceData.Places ) do
	if ((p.Name == "Docs") && (p.Path == "Docs")) then hasDocsPlace = true end
end
assertTrue( hasDocsPlace, "root folder exposed as a place/disk" )

assertTrue( istable( prog.DeviceData.Tree ), "tree list exists" )
local hasDocsNode = false
for _, n in ipairs( prog.DeviceData.Tree ) do
	if ((n.Path == "Docs") && (n.Depth == 1) && (n.Parent == "")) then hasDocsNode = true end
end
assertTrue( hasDocsNode, "root folder is a depth-1 tree node" )

prog:CreateFolder( "Docs/Sub" )
prog:Refresh( "" )
local docsNode, subNode
for _, n in ipairs( prog.DeviceData.Tree ) do
	if (n.Path == "Docs") then docsNode = n end
	if (n.Path == "Docs/Sub") then subNode = n end
end
assertTrue( docsNode ~= nil, "Docs node present" )
assertTrue( docsNode.HasChildren == true, "Docs reports children" )
assertTrue( subNode ~= nil, "nested folder in tree" )
assertTrue( subNode.Depth == 2, "nested folder depth" )
assertTrue( subNode.Parent == "Docs", "nested folder parent" )

-- Locked OS folders must still appear in the tree so navigating into
-- system/os does not jump back to This PC.
ent:LinkFolder( "system/" )
ent:LockItem( "system/" )
ent:LinkFolder( "system/os/" )
ent:LockItem( "system/os/" )
ent:WriteFile( "system/os/osid.sys", "personal" )
prog:Refresh( "" )
prog:SetPath( "system/os" )
assertTrue( prog.Path == "system/os", "opened locked system/os" )
local hasOsNode = false
for _, n in ipairs( prog.DeviceData.Tree ) do
	if (n.Path == "system/os") then hasOsNode = true end
end
assertTrue( hasOsNode, "locked system/os is in the tree" )
prog:SetPath( "" )

prog:DoCommand( "open", { "Docs", "folder" } )
assertTrue( prog.Path == "Docs", "opened folder" )

prog:WriteFile( "Docs/a.txt", "content" )
prog:DoCommand( "open", { "a.txt", "file" } )
assertTrue( noteStub.opened == "Docs/a.txt", "opened file in notepad" )

prog:DoCommand( "rename", { "a.txt", "b.txt" } )
assertTrue( prog:FileExists( "Docs/b.txt" ), "renamed file" )
assertTrue( not prog:FileExists( "Docs/a.txt" ), "old file gone" )

prog:DoCommand( "delete", { "b.txt" } )
assertTrue( not prog:FileExists( "Docs/b.txt" ), "deleted file" )

prog:DoCommand( "up", {} )
assertTrue( prog.Path == "", "went up to root" )

prog:DoCommand( "openpath", { "/" } )
assertTrue( prog.Path == "", "openpath root" )

prog:DoCommand( "newfolder", { "bad/name" } )
assertTrue( not prog:FolderExists( "bad/name" ), "rejects slash in name" )

-- Centralized file picker API (used by Notepad).
prog:WriteFile( "Docs/pick.txt", "pick me" )
assertTrue( istable( prog:BuildFileTree() ), "BuildFileTree is exposed by the base API" )
prog.ShowFilePicker = function( self, path, mode )
	local p = self:NormalizePath( path or "" )
	if ((p != "") && (!self:FolderExists( p ))) then p = "" end
	self.PickerPath = p
	self.PickerMode = mode or "open"
end
prog.CloseOpenFile = function( self ) self.pickerClosed = true end
local picked = nil
prog.OnFilePicked = function( self, path ) picked = path end

prog:ProcessCommand( "picker_nav", { "Docs" } )
assertTrue( prog.PickerPath == "Docs", "picker navigated to Docs" )
prog:ProcessCommand( "picker_sel", { "Docs/pick.txt" } )
assertTrue( picked == "Docs/pick.txt", "picker returned full path" )
assertTrue( prog.pickerClosed == true, "picker closed on select" )
prog:ProcessCommand( "picker_nav", { "does/not/exist" } )
assertTrue( prog.PickerPath == "Docs", "picker rejects missing folder" )
prog:ProcessCommand( "picker_close", {} )
assertTrue( prog.pickerClosed == true, "picker close command" )

print( "ALL FILE MANAGER TESTS PASSED" )
