-- Minimal GLua/Lua mock for the PCMod filesystem helpers.
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
		if (!a) then
			table.insert( out, string.sub( str, start ) )
			break
		end
		table.insert( out, string.sub( str, start, a - 1 ) )
		start = b + 1
	end
	return out
end
function table.Copy( t )
	if (type( t ) != "table") then return t end
	local o = {}
	for k, v in pairs( t ) do o[ k ] = table.Copy( v ) end
	return o
end

PCMod = {}
PCMod.Data = {}
PCMod.Msg = function() end
PCMod.TableToString = function() return "" end
PCMod.StringToTable = function() return nil end
PCMod.Cfg = {}
function AddCSLuaFile() end

ENT = {}
dofile( "pcmod_shared.lua" )

local ent = setmetatable( {}, { __index = ENT } )
function ent:EntIndex() return 1 end
function ent:IsValid() return true end
PCMod.Data[ 1 ] = { HardDrive = {} }

local function assertTrue( v, msg )
	if (!v) then error( "FAILED: " .. msg, 2 ) end
end

-- Old-style folder key (with trailing slash) must still be found.
ent:LinkFolder( "mydocs/" )
assertTrue( ent:FileFolderExist( "mydocs" ), "folder without slash found" )
assertTrue( ent:FileFolderExist( "mydocs/" ), "folder with slash found" )

-- Recursive folder creation, including parents.
assertTrue( ent:MakeFolder( "mydocs/text/sub" ), "MakeFolder recursive" )
assertTrue( ent:MakeFolder( "mydocs/text/sub" ), "MakeFolder idempotent" )
assertTrue( ent:FileFolderExist( "mydocs/text/sub/" ), "created folder visible" )

-- Writing and reading, with and without leading slash.
ent:LinkFolder( "mydocs/text/" )
ent:WriteFile( "mydocs/text/a.txt", "hello" )
assertTrue( ent:ReadFile( "mydocs/text/a.txt" ) == "hello", "read file" )
assertTrue( ent:ReadFile( "/mydocs/text/a.txt" ) == "hello", "read file leading slash" )

-- Listing with types and sorting (folders first).
local list = ent:ListDir( "mydocs/text" )
assertTrue( #list == 2, "ListDir count " .. #list )
assertTrue( list[ 1 ].Type == "folder" and list[ 1 ].Name == "sub", "folder first" )
assertTrue( list[ 2 ].Type == "file" and list[ 2 ].Name == "a.txt", "file second" )

local info = ent:GetItemInfo( "mydocs/text/a.txt" )
assertTrue( info && info.Type == "file" && info.Size == 5 && info.Content == "hello", "GetItemInfo" )

-- Rename a folder with its contents.
assertTrue( ent:RenameItem( "mydocs/text/sub", "mydocs/text/renamed" ), "rename folder" )
assertTrue( ent:FileFolderExist( "mydocs/text/renamed" ), "renamed folder exists" )
assertTrue( !ent:FileFolderExist( "mydocs/text/sub" ), "old folder gone" )

-- Rename a file.
assertTrue( ent:RenameItem( "mydocs/text/a.txt", "mydocs/text/b.txt" ), "rename file" )
assertTrue( ent:ReadFile( "mydocs/text/b.txt" ) == "hello", "renamed file content" )

-- Copy a file, then a folder.
assertTrue( ent:CopyItem( "mydocs/text/b.txt", "mydocs/text/c.txt" ), "copy file" )
assertTrue( ent:ReadFile( "mydocs/text/c.txt" ) == "hello", "copied content" )
assertTrue( ent:CopyItem( "mydocs/text/renamed", "mydocs/text/renamed2" ), "copy folder" )
assertTrue( ent:FileFolderExist( "mydocs/text/renamed2" ), "copied folder exists" )

-- Case-insensitive lookup must use the stored key for recursive mutations.
ent:MakeFolder( "mydocs/text/CaseFolder/Sub" )
ent:WriteFile( "mydocs/text/CaseFolder/Sub/Mixed.TXT", "mixed" )
assertTrue( ent:RenameItem( "MYDOCS/TEXT/casefolder", "mydocs/text/CaseMoved" ), "mixed-case folder rename" )
assertTrue( ent:ReadFile( "mydocs/text/CaseMoved/Sub/Mixed.TXT" ) == "mixed", "mixed-case rename kept descendants" )
assertTrue( ent:CopyItem( "MYDOCS/TEXT/CASEMOVED", "mydocs/text/CaseCopied" ), "mixed-case folder copy" )
assertTrue( ent:ReadFile( "mydocs/text/CaseCopied/Sub/Mixed.TXT" ) == "mixed", "mixed-case copy kept descendants" )
assertTrue( ent:DeleteItem( "mydocs/text/casecopied" ), "mixed-case folder delete" )
assertTrue( !ent:FileFolderExist( "mydocs/text/CaseCopied" ), "mixed-case deleted folder gone" )
ent:WriteFile( "MYDOCS/TEXT/CASEMOVED/SUB/MIXED.TXT", "updated" )
assertTrue( ent:ReadFile( "mydocs/text/CaseMoved/Sub/Mixed.TXT" ) == "updated", "mixed-case overwrite uses stored file" )

-- Locks: system/data/ is protected, including descendants.
ent:LinkFolder( "system/data/" )
ent:LockItem( "system/data/" )
assertTrue( ent:IsLocked( "system/data" ), "IsLocked without trailing slash" )
assertTrue( ent:IsPathLocked( "system/data/secret.txt" ), "descendant locked" )
assertTrue( !ent:MakeFolder( "system/data/new" ), "cannot create in locked folder" )
assertTrue( !ent:DeleteItem( "system/data" ), "cannot delete locked folder" )
assertTrue( !ent:RenameItem( "system/data", "system/data2" ), "cannot rename locked folder" )

-- Setup compatibility: the entity/OS setup must still write system files even
-- after "system/" has been locked (this is what the BIOS boots from).
ent:LinkFolder( "system/" )
ent:LockItem( "system/" )
ent:LinkFolder( "system/os/" )
assertTrue( ent:FileFolderExist( "system/os/" ), "nested folder under locked parent" )
ent:WriteFile( "system/boot.sys", "os:instance\nos:launch" )
assertTrue( ent:ReadFile( "system/boot.sys" ) == "os:instance\nos:launch", "boot.sys written under locked system" )
ent:LockItem( "system/boot.sys" )
ent:WriteFile( "system/boot.sys", "hacked" )
assertTrue( ent:ReadFile( "system/boot.sys" ) == "os:instance\nos:launch", "locked boot.sys not overwritten" )
ent:LockItem( "system/os/" )
ent:WriteFile( "system/os/osid.sys", "personal" )
ent:LockItem( "system/os/osid.sys" )
assertTrue( ent:ReadFile( "system/os/osid.sys" ) == "personal", "osid.sys written under locked system" )
ent:WriteFile( "system/firstrun.sys", "1" )
assertTrue( ent:ReadFile( "system/firstrun.sys" ) == "1", "firstrun.sys written" )
ent:UnlinkItem( "system/firstrun.sys" )
assertTrue( !ent:FileFolderExist( "system/firstrun.sys" ), "firstrun.sys removed under locked parent" )
ent:UnlinkItem( "system/boot.sys" )
assertTrue( ent:FileFolderExist( "system/boot.sys" ), "locked file cannot be unlinked" )
ent:WriteFile( "system/data/pcdata.dat", "persist" )
assertTrue( ent:ReadFile( "system/data/pcdata.dat" ) == "persist", "OS data written under locked folder" )
ent:WriteFile( "system/data/pcdata.dat", "persist2" )
assertTrue( ent:ReadFile( "system/data/pcdata.dat" ) == "persist2", "OS data overwritten under locked folder" )
assertTrue( !ent:MakeFolder( "system/evil" ), "user cannot create under locked system" )

-- Recursive delete of an unlocked folder.
assertTrue( ent:DeleteItem( "mydocs/text/renamed2" ), "delete folder" )
assertTrue( !ent:FileFolderExist( "mydocs/text/renamed2" ), "deleted folder gone" )

-- Program-level API (base.lua).
PROG = {}
dofile( "pcmod_base.lua" )
local prog = table.Copy( PROG )
prog.Entity = ent
assertTrue( prog:FileExists( "MYDOCS/TEXT/CASEMOVED/SUB/MIXED.TXT" ), "program FileExists is case-insensitive" )
local lockedok, lockederr = prog:WriteFile( "system/data/blocked.txt", "blocked" )
assertTrue( (!lockedok) && (lockederr == "locked"), "program write rejects inherited folder lock" )
assertTrue( ent:ReadFile( "system/data/blocked.txt" ) == "", "locked program write changed nothing" )
assertTrue( prog:CreateFolder( "docs/api/demo" ), "program CreateFolder" )
assertTrue( prog:FolderExists( "docs/api/demo" ), "program FolderExists" )
prog:WriteFile( "docs/api/demo/x.txt", "program" )
assertTrue( prog:ReadFile( "docs/api/demo/x.txt" ) == "program", "program ReadFile" )
local plist = prog:ListDir( "docs/api" )
assertTrue( #plist == 1 && plist[ 1 ].Name == "demo", "program ListDir" )
assertTrue( prog:JoinPath( "/docs//api/", "/x.txt" ) == "docs/api/x.txt", "JoinPath" )
assertTrue( prog:GetParentPath( "docs/api/demo" ) == "docs/api", "GetParentPath" )
assertTrue( prog:GetBaseName( "docs/api/demo" ) == "demo", "GetBaseName" )
assertTrue( prog:RenameFile( "docs/api/demo/x.txt", "docs/api/demo/y.txt" ), "program RenameFile" )
assertTrue( prog:CopyFile( "docs/api/demo/y.txt", "docs/api/demo/z.txt" ), "program CopyFile" )
assertTrue( prog:ReadFile( "docs/api/demo/z.txt" ) == "program", "program copied content" )
assertTrue( prog:DeleteFolder( "docs/api/demo" ), "program DeleteFolder" )

print( "ALL FILESYSTEM TESTS PASSED" )
