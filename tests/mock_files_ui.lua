-- File Manager UI/framework behaviour mock (plain Lua after translation).

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

function Color( r, g, b, a )
	return { r = r, g = g, b = b, a = a or 255 }
end

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

math.Clamp = function( v, a, b )
	if (v < a) then return a end
	if (v > b) then return b end
	return v
end

local Now = 0
function CurTime() return Now end

DEV = {}
dofile( "sh_ui_layout.lua" )
dofile( "sh_window.lua" )
dofile( "cl_ui_widgets.lua" )
dofile( "pcmod_ss_base.lua" )
dofile( "pcmod_files_ui.lua" )

local function assertTrue( v, msg )
	if (not v) then error( "FAILED: " .. msg, 2 ) end
end
local function assertEq( a, b, msg )
	if (a ~= b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end

local dev = table.Copy( DEV )
dev.Listboxes = {}
dev.Textboxes = {}
dev.Elements = {}
dev.win_w = 800
dev.win_h = 600
dev.win_x = 0
dev.win_y = 0
dev.Th = "basic"
dev.Path = "Docs"
dev.Status = ""

local calls = {}
function dev:RunProgCommand( prog, com, a, b )
	table.insert( calls, { prog = prog, com = com, a = a, b = b } )
end

dev:CreateListbox( "basic", "lstPlaces", 0, 0, 100, 100 )
dev:CreateListbox( "basic", "lstFiles", 0, 0, 100, 100 )

dev.Tree = {
	{ Path = "", Name = "This PC", Parent = nil, Depth = 0, Locked = false, HasChildren = true },
	{ Path = "Docs", Name = "Docs", Parent = "", Depth = 1, Locked = false, HasChildren = true },
	{ Path = "Docs/Sub", Name = "Sub", Parent = "Docs", Depth = 2, Locked = false, HasChildren = false },
	{ Path = "system", Name = "system", Parent = "", Depth = 1, Locked = true, HasChildren = false },
}
dev.Places = {
	{ Name = "Docs", Path = "Docs", Locked = false },
	{ Name = "system", Path = "system", Locked = true },
}
dev.Entries = {
	{ Name = "a.txt", Type = "file", Locked = false },
	{ Name = "Docs", Type = "folder", Locked = false },
	{ Name = "locked.txt", Type = "file", Locked = true },
}

dev:ExpandPath( "Docs" )
dev:BuildPlaces()
dev:BuildList()

assertEq( dev.Listboxes.lstPlaces.Order[ 1 ], "node:", "root tree row first" )
assertEq( dev.Listboxes.lstPlaces.Order[ 2 ], "node:Docs", "Docs tree row second" )
assertEq( dev.Listboxes.lstPlaces.Order[ 3 ], "node:Docs/Sub", "expanded child row third" )
assertEq( dev.Listboxes.lstPlaces.Order[ 4 ], "node:system", "system tree row fourth" )
assertEq( dev:GetListboxSelRow( "lstPlaces" ), "node:Docs", "current path selected" )
assertTrue( dev.Listboxes.lstPlaces.LeftAlign, "tree is left aligned" )
assertEq( dev.Listboxes.lstFiles.Order[ 1 ], "..", "up row first" )
assertEq( dev.Listboxes.lstFiles.Order[ 2 ], "a.txt", "file row second" )
assertEq( dev.Listboxes.lstFiles.Order[ 3 ], "Docs", "folder row third" )
local order = dev:GetListboxOrder( dev.Listboxes.lstFiles )
assertEq( #order, 4, "ordered row count" )
assertEq( order[ 1 ], "..", "order helper keeps insertion order" )

-- Clicking the tree arrow collapses a branch without navigating.
Now = 50
dev:ListboxSelect( "lstPlaces", "node:Docs", false, 0.0375, 0.5 )
assertEq( #calls, 0, "arrow click does not navigate" )
assertEq( dev.Listboxes.lstPlaces.Order[ 3 ], "node:system", "child hidden after collapse" )
-- Clicking it again expands.
Now = 51
dev:ListboxSelect( "lstPlaces", "node:Docs", false, 0.0375, 0.5 )
assertEq( dev.Listboxes.lstPlaces.Order[ 3 ], "node:Docs/Sub", "child shown after expand" )

-- Double click a folder -> open.
Now = 100
dev:ListboxSelect( "lstFiles", "Docs", false, 0.5, 0.5 )
assertEq( #calls, 0, "first click only selects" )
Now = 100.2
dev:ListboxSelect( "lstFiles", "Docs", false, 0.5, 0.5 )
assertEq( #calls, 1, "second click opens" )
assertEq( calls[ 1 ].com, "open", "open command sent" )
assertEq( calls[ 1 ].a, "Docs", "open target" )
assertEq( calls[ 1 ].b, "folder", "open type" )

-- Double click a tree node -> openpath.
Now = 200
dev:ListboxSelect( "lstPlaces", "node:Docs", false, 0.5, 0.5 )
assertEq( #calls, 1, "place first click only selects" )
Now = 200.1
dev:ListboxSelect( "lstPlaces", "node:Docs", false, 0.5, 0.5 )
assertEq( #calls, 2, "place second click opens" )
assertEq( calls[ 2 ].com, "openpath", "place openpath command" )
assertEq( calls[ 2 ].a, "Docs", "place path" )

-- A slow second click is a new single click, not a double click.
Now = 300
dev:ListboxSelect( "lstFiles", "a.txt", false, 0.5, 0.5 )
Now = 301
dev:ListboxSelect( "lstFiles", "a.txt", false, 0.5, 0.5 )
assertEq( #calls, 2, "slow clicks do not open" )

-- Old program fallback: only Places are sent, but the current nested path must
-- still be shown and selected instead of jumping back to This PC.
dev.Tree = {}
dev.Places = { { Name = "system", Path = "system", Locked = true } }
dev.Path = "system/os"
dev.Expanded = { [""] = true }
dev:ExpandPath( "system/os" )
dev:BuildPlaces()
assertEq( dev.PlacePaths[ "node:system/os" ], "system/os", "fallback synthesizes the current path" )
assertEq( dev:GetListboxSelRow( "lstPlaces" ), "node:system/os", "fallback selects the current path" )

-- Right click opens the little menu.
Now = 400
dev:ListboxSelect( "lstFiles", "a.txt", true, 0.5, 0.5 )
assertTrue( dev.Menu ~= nil, "right click opens menu" )
assertEq( dev.Menu.Items[ 1 ].Action, "open", "menu has Open" )
assertEq( dev.Menu.Items[ 2 ].Action, "rename", "menu has Rename" )
assertEq( dev.Menu.Items[ 3 ].Action, "delete", "menu has Delete" )
assertEq( dev.Menu.Items[ 4 ].Action, "refresh", "menu has Refresh" )
assertEq( dev.Menu.Items[ 2 ].Enabled, true, "unlocked file can be renamed" )

-- Locked entries cannot be renamed/deleted.
Now = 401
dev:ListboxSelect( "lstFiles", "locked.txt", true, 0.5, 0.5 )
assertEq( dev.Menu.Items[ 2 ].Enabled, false, "locked file cannot be renamed" )
assertEq( dev.Menu.Items[ 3 ].Enabled, false, "locked file cannot be deleted" )

-- Right click a tree node: Open/Refresh only.
Now = 402
dev:ListboxSelect( "lstPlaces", "node:system", true, 0.5, 0.5 )
assertEq( #dev.Menu.Items, 2, "place menu has two items" )
assertEq( dev.Menu.Items[ 1 ].Action, "open", "place menu Open" )

-- Right click empty space: New Folder/Refresh.
Now = 403
dev.Menu = nil
dev:ListboxBlankClick( "lstFiles", true, 0.5, 0.5 )
assertTrue( dev.Menu ~= nil, "blank right click opens menu" )
assertEq( dev.Menu.Items[ 1 ].Action, "newfolder", "blank menu New Folder" )
assertEq( dev.Menu.Items[ 2 ].Action, "refresh", "blank menu Refresh" )

-- Menu click on New Folder starts the inline editor, and Enter commits it.
dev.Menu = {
	X = 0.1, Y = 0.1, W = 0.4, H = 0.4,
	PadX = 0.01, PadY = 0.01, RowH = 0.1,
	Items = { { Label = "New Folder", Action = "newfolder" } },
	Ctx = { Lb = "lstFiles", Sel = "", Kind = "blank" },
}
Now = 500
assertTrue( dev:MenuClick( 0.15, 0.12, false ), "menu click handled" )
assertTrue( dev.Edit ~= nil, "editor opened" )
assertEq( dev.Edit.Mode, "newfolder", "new folder mode" )
dev.Edit.Text = "Test"
dev:CommitEdit()
assertEq( calls[ #calls ].com, "newfolder", "newfolder command" )
assertEq( calls[ #calls ].a, "Test", "newfolder name" )

-- Editor keys: backspace and Enter.
dev.Edit = { Mode = "newfolder", Text = "abc" }
dev:EditorKey( "<--", "" )
assertEq( dev.Edit.Text, "ab", "backspace" )
dev:EditorKey( "x", "x" )
assertEq( dev.Edit.Text, "abx", "typing" )
dev:EditorKey( "enter", "" )
assertTrue( dev.Edit == nil, "enter closes editor" )
assertEq( calls[ #calls ].com, "newfolder", "enter commits" )
assertEq( calls[ #calls ].a, "abx", "enter commit text" )

-- Rename action and commit.
local before = #calls
dev.Menu = {
	X = 0.1, Y = 0.1, W = 0.4, H = 0.4,
	PadX = 0.01, PadY = 0.01, RowH = 0.1,
	Items = { { Label = "Rename", Action = "rename" } },
	Ctx = { Lb = "lstFiles", Sel = "a.txt", Kind = "file" },
}
dev:MenuClick( 0.15, 0.12, false )
assertEq( dev.Edit.Mode, "rename", "rename editor" )
assertEq( dev.Edit.Target, "a.txt", "rename target" )
dev.Edit.Text = "b.txt"
dev:CommitEdit()
assertEq( calls[ #calls ].com, "rename", "rename command" )
assertEq( calls[ #calls ].a, "a.txt", "rename old name" )
assertEq( calls[ #calls ].b, "b.txt", "rename new name" )
assertEq( #calls, before + 1, "rename sent once" )

-- Delete asks for confirmation first, then deletes.
dev.Menu = {
	X = 0.1, Y = 0.1, W = 0.4, H = 0.4,
	PadX = 0.01, PadY = 0.01, RowH = 0.1,
	Items = { { Label = "Delete", Action = "delete" } },
	Ctx = { Lb = "lstFiles", Sel = "a.txt", Kind = "file" },
}
dev:MenuAction( "delete" )
assertTrue( dev.Menu ~= nil, "delete opens confirmation menu" )
assertEq( dev.Menu.Items[ 1 ].Action, "confirmdelete", "confirmation item" )
dev:MenuClick( 0.15, 0.12, false )
assertEq( calls[ #calls ].com, "delete", "confirmed delete command" )
assertEq( calls[ #calls ].a, "a.txt", "delete target" )

print( "ALL FILE MANAGER UI TESTS PASSED" )
