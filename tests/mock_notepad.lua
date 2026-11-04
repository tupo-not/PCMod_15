-- Notepad openpath/save-back mock test (plain Lua after translation).
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
util.Compress = function( s ) return "C:" .. s end
util.Decompress = function( s )
	if (string.sub( s, 1, 2 ) == "C:") then return string.sub( s, 3 ) end
	return nil
end

ENT = {}
dofile( "pcmod_shared.lua" )
local ent = setmetatable( {}, { __index = ENT } )
function ent:EntIndex() return 1 end
function ent:IsValid() return true end
PCMod.Data[ 1 ] = { HardDrive = {} }
ent:LinkFolder( "mydocs/text/" )
ent:LinkFolder( "projects/" )

PROG = {}
dofile( "pcmod_base.lua" )
local base = table.Copy( PROG )
PROG = table.Copy( base )
dofile( "pcmod_notepad.lua" )

local prog = table.Copy( PROG )
prog.Entity = ent
prog.DeviceData = {}
prog.UpdateSS = function() end

local function assertTrue( v, msg )
	if (not v) then error( "FAILED: " .. msg, 2 ) end
end

-- Open a text file from an arbitrary folder.
ent:WriteFile( "projects/readme.txt", util.Compress( "original" ) )
prog:DoCommand( "openpath", { "projects/readme.txt" } )
assertTrue( prog.DeviceData.TC == "original", "openpath loaded text" )
assertTrue( prog.OpenPath == "projects/readme.txt", "openpath stored path" )
assertTrue( prog.DeviceData.FN == "readme.txt", "openpath stored filename" )

-- Saving with the same filename must go back to the original path.
prog:DoCommand( "savecontent", { "readme.txt", "edited in place" } )
assertTrue( util.Decompress( ent:ReadFile( "projects/readme.txt" ) ) == "edited in place", "saved to original path" )
assertTrue( prog.DeviceData.TC == "edited in place", "TC updated on save" )

-- Saving under a new name goes to mydocs/text/ and becomes the new target.
prog:DoCommand( "savecontent", { "copy.txt", "a copy" } )
assertTrue( util.Decompress( ent:ReadFile( "mydocs/text/copy.txt" ) ) == "a copy", "saved new name to SaveRoot" )
assertTrue( prog.OpenPath == "mydocs/text/copy.txt", "new target tracked" )

-- Legacy "open" still works and sets the filename shown by the device.
prog:DoCommand( "open", { "copy.txt" } )
assertTrue( prog.DeviceData.TC == "a copy", "legacy open loaded text" )
assertTrue( prog.DeviceData.FN == "copy.txt", "legacy open filename" )

-- Locked files/folders must reject saves without claiming success or changing
-- the last-saved document state.
ent:LinkFolder( "system/data/" )
ent:WriteFile( "system/data/secret.txt", util.Compress( "original" ) )
ent:LockItem( "system/data/" )
prog:DoCommand( "openpath", { "system/data/secret.txt" } )
assertTrue( prog.DeviceData.TC == "original", "locked file opened" )
prog:DoCommand( "savecontent", { "secret.txt", "hacked" } )
assertTrue( util.Decompress( ent:ReadFile( "system/data/secret.txt" ) ) == "original", "locked save changed nothing" )
assertTrue( prog.DeviceData.St == 6, "locked save reports lock failure" )
assertTrue( prog.DeviceData.SaveFailed == true, "failed save flagged for the client" )
assertTrue( prog.DeviceData.TC == "original", "failed save preserves last-saved text" )
assertTrue( prog.OpenPath == "system/data/secret.txt", "failed save preserves open path" )
prog:DoCommand( "savecontent", { "recovered.txt", "valid" } )
assertTrue( util.Decompress( ent:ReadFile( "mydocs/text/recovered.txt" ) ) == "valid", "unlocked save still works" )
assertTrue( prog.DeviceData.SaveFailed == false, "successful save clears failure flag" )

print( "ALL NOTEPAD TESTS PASSED" )
