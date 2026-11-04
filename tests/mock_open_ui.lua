-- File picker device mock (plain Lua after translation).

function table.Copy( t )
	if (type( t ) ~= "table") then return t end
	local o = {}
	for k, v in pairs( t ) do o[ k ] = table.Copy( v ) end
	return o
end
function table.Count( t )
	local n = 0
	for _ in pairs( t ) do n = n + 1 end
	return n
end
function istable( v ) return type( v ) == "table" end
function Color( r, g, b, a ) return { r = r, g = g, b = b, a = a or 255 } end
function ClampNum( v, a, b ) if (v < a) then return a end if (v > b) then return b end return v end

PCMod = {}
PCMod.Msg = function() end
PCMod.SDraw = { CFrame = 0 }
PCMod.Gui = {
	GetThemeColour = function() return Color( 0, 0, 0, 255 ) end,
	ThemeDraw = function() return false end,
}

surface = {
	SetFont = function() end,
	GetTextSize = function( t ) return #tostring( t ) * 6, 10 end,
	SetDrawColor = function() end,
	DrawRect = function() end,
	DrawOutline = function() end,
	DrawLine = function() end,
}
draw = { SimpleText = function() end }
TEXT_ALIGN_LEFT = 0
TEXT_ALIGN_CENTER = 1

math.Clamp = ClampNum

local Now = 0
function CurTime() return Now end

DEV = {}
dofile( "pcmod_ss_base.lua" )
dofile( "pcmod_open_ui.lua" )

local function assertTrue( v, msg ) if (not v) then error( "FAILED: " .. msg, 2 ) end end
local function assertEq( a, b, msg )
	if (a ~= b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end

local dev = table.Copy( DEV )
dev.Listboxes = {}
dev.Textboxes = {}
dev.Elements = {}
dev.win_x = 0
dev.win_y = 0
dev.win_w = 800
dev.win_h = 600
dev.Th = "basic"
dev.ProgName = "notepad"
dev.Mode = "open"
dev.Path = "Docs"

local calls = {}
function dev:RunProgCommand( prog, com, arg )
	table.insert( calls, { prog = prog, com = com, arg = arg } )
end

dev:CreateListbox( "basic", "lstPlaces", 0, 0, 100, 100 )
dev:CreateListbox( "basic", "lstFiles", 0, 0, 100, 100 )

dev.Tree = {
	{ Path = "", Name = "This PC", Parent = nil, Depth = 0, Locked = false, HasChildren = true },
	{ Path = "Docs", Name = "Docs", Parent = "", Depth = 1, Locked = false, HasChildren = true },
	{ Path = "Docs/Sub", Name = "Sub", Parent = "Docs", Depth = 2, Locked = false, HasChildren = false },
	{ Path = "system", Name = "system", Parent = "", Depth = 1, Locked = true, HasChildren = false },
}
dev.Places = { { Name = "Docs", Path = "Docs", Locked = false } }
dev.Entries = {
	{ Name = "Sub", Type = "folder", Locked = false },
	{ Name = "a.txt", Type = "file", Locked = false },
}

dev:OnUpdate()

assertEq( dev.Listboxes.lstPlaces.Order[ 1 ], "node:", "root first" )
assertEq( dev.Listboxes.lstPlaces.Order[ 2 ], "node:Docs", "Docs second" )
assertEq( dev.Listboxes.lstPlaces.Order[ 3 ], "node:Docs/Sub", "current path expanded" )
assertEq( dev:GetListboxSelRow( "lstPlaces" ), "node:Docs", "current path selected" )
assertEq( dev.Listboxes.lstFiles.Order[ 1 ], "..", "up row first" )
assertEq( dev.Listboxes.lstFiles.Order[ 2 ], "Sub", "folder row" )
assertEq( dev.Listboxes.lstFiles.Order[ 3 ], "a.txt", "file row" )

-- Double-click a file selects its full path.
Now = 100
dev:ListboxSelect( "lstFiles", "a.txt", false, 0.5, 0.5 )
assertEq( #calls, 0, "first click only selects" )
Now = 100.2
dev:ListboxSelect( "lstFiles", "a.txt", false, 0.5, 0.5 )
assertEq( #calls, 1, "second click selects file" )
assertEq( calls[ 1 ].com, "picker_sel", "picker_sel command" )
assertEq( calls[ 1 ].arg, "Docs/a.txt", "full file path" )

-- Double-click a folder navigates.
Now = 200
dev:ListboxSelect( "lstFiles", "Sub", false, 0.5, 0.5 )
Now = 200.1
dev:ListboxSelect( "lstFiles", "Sub", false, 0.5, 0.5 )
assertEq( calls[ #calls ].com, "picker_nav", "folder nav command" )
assertEq( calls[ #calls ].arg, "Docs/Sub", "folder nav path" )

-- Double-click ".." goes to the parent.
Now = 300
dev:ListboxSelect( "lstFiles", "..", false, 0.5, 0.5 )
Now = 300.1
dev:ListboxSelect( "lstFiles", "..", false, 0.5, 0.5 )
assertEq( calls[ #calls ].com, "picker_nav", "parent nav command" )
assertEq( calls[ #calls ].arg, "", "parent of Docs is root" )

-- Double-click a tree node navigates.
Now = 400
dev:ListboxSelect( "lstPlaces", "node:system", false, 0.5, 0.5 )
Now = 400.1
dev:ListboxSelect( "lstPlaces", "node:system", false, 0.5, 0.5 )
assertEq( calls[ #calls ].com, "picker_nav", "tree nav command" )
assertEq( calls[ #calls ].arg, "system", "tree nav path" )

-- Tree arrow click toggles without navigating.
local count = #calls
Now = 500
dev:ListboxSelect( "lstPlaces", "node:Docs", false, 0.0375, 0.5 )
assertEq( #calls, count, "arrow does not navigate" )
assertEq( dev.Listboxes.lstPlaces.Order[ 3 ], "node:system", "child hidden after collapse" )

-- Escape closes the picker.
Now = 600
dev:KeyPress( "escape", "" )
assertEq( calls[ #calls ].com, "picker_close", "escape closes picker" )

-- Old payload fallback: current nested path is synthesized and selected.
dev.Tree = {}
dev.Places = { { Name = "system", Path = "system", Locked = true } }
dev.Path = "system/os"
dev.Expanded = { [""] = true }
dev:ExpandPath( "system/os" )
dev:BuildPlaces()
assertEq( dev.PlacePaths[ "node:system/os" ], "system/os", "fallback synthesizes path" )
assertEq( dev:GetListboxSelRow( "lstPlaces" ), "node:system/os", "fallback selects path" )

-- Legacy program payload (old ShowOpenFile): only Fs is sent.
local pass = {}
function dev:PassData( devname, dname, data )
	table.insert( pass, { dev = devname, name = dname, data = data } )
end
dev.ProgName = nil
dev.Parent = "window_notepad"
dev.Entries = {}
dev.Tree = {}
dev.Places = {}
dev.Fs = { "old.txt" }
dev.Path = ""
dev:OnUpdate()
assertEq( dev.Listboxes.lstFiles.Order[ 1 ], "old.txt", "legacy Fs file listed" )
Now = 700
dev:ListboxSelect( "lstFiles", "old.txt", false, 0.5, 0.5 )
Now = 700.2
dev:ListboxSelect( "lstFiles", "old.txt", false, 0.5, 0.5 )
assertEq( pass[ 1 ].name, "filename", "legacy filename data" )
assertEq( pass[ 1 ].data, "old.txt", "legacy filename value" )
assertEq( pass[ 2 ].data, "closebrowse", "legacy closebrowse" )

print( "ALL FILE PICKER UI TESTS PASSED" )
