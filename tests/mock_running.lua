-- Running-program taskbar: focus, minimize, restore and per-OpenID cleanup.
PCMod = {
	Msg = function() end,
	Cfg = {},
	SDraw = { SSpaces = {}, Minimized = {}, DevFocus = "", CFrame = 0 },
	Gui = {
		ThemeDraw = function() return false end,
		GetThemeColour = function() return { r = 20, g = 22, b = 26, a = 255 } end,
	},
}
concommand = { Add = function() end }
function CurTime() return 100 end
DEV = {}
dofile( "pcmod_desktop.lua" )

local function assertEq( a, b, msg )
	if (a ~= b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function assertTrue( v, msg ) if (!v) then error( "FAILED: " .. msg, 2 ) end end
local function count( t ) local n = 0 for _ in pairs( t ) do n = n + 1 end return n end
local function app( prog, title, openid )
	return {
		Type = "window_" .. prog, ProgName = prog, AppTitle = title,
		DevID = "42:window_" .. prog, OpenID = openid or 1, ActivateID = 1, AppMain = true,
		X = 0, Y = 0, W = 0.5, H = 0.5, Priority = 5,
	}
end

function PCMod.SDraw.IsMinimized( device, entid )
	local perEnt = PCMod.SDraw.Minimized[ entid ]
	local rec = perEnt && (perEnt[ device.DevID ] || perEnt[ "prog:" .. device.ProgName ])
	if (!rec) then return false end
	if ((device.OpenID && rec.OpenID && (device.OpenID != rec.OpenID)) ||
		(device.ActivateID && rec.ActivateID && (device.ActivateID != rec.ActivateID))) then
		perEnt[ device.DevID ] = nil
		perEnt[ "prog:" .. device.ProgName ] = nil
		return false
	end
	return true
end
function PCMod.SDraw.SetMinimized( device, entid, minimized )
	PCMod.SDraw.Minimized[ entid ] = PCMod.SDraw.Minimized[ entid ] or {}
	if (minimized) then
		local rec = { OpenID = device.OpenID, ActivateID = device.ActivateID }
		PCMod.SDraw.Minimized[ entid ][ device.DevID ] = rec
		PCMod.SDraw.Minimized[ entid ][ "prog:" .. device.ProgName ] = rec
		if (PCMod.SDraw.DevFocus == string.match( device.DevID, ":(.+)$" )) then PCMod.SDraw.DevFocus = "" end
	else
		PCMod.SDraw.Minimized[ entid ][ device.DevID ] = nil
		PCMod.SDraw.Minimized[ entid ][ "prog:" .. device.ProgName ] = nil
	end
end

local desktop = {}
for k, v in pairs( DEV ) do desktop[ k ] = v end
desktop.EntID = 42
desktop.Elements = {}
desktop.commands = {}
function desktop:CreateButton2( theme, name, x, y, w, h, text, icon )
	local btn = { NAME = name, X = x, Y = y, W = w, H = h, Text = text, Icon = icon, Active = false }
	self.Elements[ name ] = btn
	return btn
end
function desktop:RemoveElement( name ) self.Elements[ name ] = nil end
function desktop:SubmitCommand( ... ) self.commands[ #self.commands + 1 ] = { ... } end

PCMod.SDraw.SSpaces[ 42 ] = {
	window_files = app( "files", "Files" ),
	window_notepad = app( "notepad", "Notepad" ),
}
PCMod.SDraw.SSpaces[ 42 ].window_files.Priority = 10
desktop:Initialize( 0, 0, 800, 600 )
assertEq( count( desktop.TaskItems ), 2, "open programs appear on the taskbar" )
assertTrue( desktop.Elements[ "btn_start" ] != nil, "Start button remains" )
local created = count( desktop.Elements )
desktop:Tick()
assertEq( count( desktop.Elements ), created, "unchanged windows do not rebuild controls" )

desktop.ProcessClick = function( self, x, y ) self.processed = { x = x, y = y } end
desktop:DoClick( 0.15, 0.99, false )
assertTrue( desktop.processed != nil, "first task button does not fall into Start padding" )
assertEq( #desktop.commands, 0, "taskbar area click did not open Start" )
desktop:DoClick( 0.10, 0.99, false )
assertEq( #desktop.commands, 1, "Start keeps its own padded hitbox" )
desktop.commands = {}

PCMod.SDraw.SSpaces[ 42 ].window_browser = app( "browser", "Browser" )
desktop:Tick()
assertEq( count( desktop.TaskItems ), 3, "new program is added without duplicating old buttons" )

PCMod.SDraw.DevFocus = "desktop" -- RegisterClick overwrites this before dispatch.
desktop:ButtonClick( "btn_task_files" )
assertTrue( PCMod.SDraw.IsMinimized( PCMod.SDraw.SSpaces[ 42 ].window_files, 42 ), "active program minimizes even after desktop gets DevFocus" )
assertTrue( desktop:GetTopTaskItem().DevID ~= PCMod.SDraw.SSpaces[ 42 ].window_files.DevID, "minimized window no longer counts as topmost" )
desktop:UpdateTaskActive()
assertEq( desktop.Elements[ "btn_task_files" ].Active, false, "minimized button is not active" )

desktop:ButtonClick( "btn_task_files" )
assertTrue( not PCMod.SDraw.IsMinimized( PCMod.SDraw.SSpaces[ 42 ].window_files, 42 ), "minimized program restores on click" )
assertEq( PCMod.SDraw.DevFocus, "window_files", "restored program receives focus" )
local cmd = desktop.commands[ #desktop.commands ]
assertEq( cmd[ 1 ], "os_command", "restore uses the OS command channel" )
assertEq( cmd[ 2 ], "prog_command", "restore targets the program command" )
assertEq( cmd[ 3 ], "files", "restore targets the correct program" )
assertEq( cmd[ 4 ], "focus", "restore requests focus" )

-- Auxiliary pickers never replace the main program taskbar identity.
PCMod.SDraw.SSpaces[ 42 ].win_notepad_openfile = app( "notepad", "Notepad" )
PCMod.SDraw.SSpaces[ 42 ].win_notepad_openfile.DevID = "42:win_notepad_openfile"
PCMod.SDraw.SSpaces[ 42 ].win_notepad_openfile.AppMain = false
PCMod.SDraw.SSpaces[ 42 ].win_notepad_openfile.Priority = 240
desktop:Tick()
assertEq( desktop.TaskItems[ "btn_task_notepad" ].DevID, "42:window_notepad", "picker does not steal the main taskbar identity" )
PCMod.SDraw.SetMinimized( desktop.TaskItems[ "btn_task_notepad" ], 42, true )
assertTrue( PCMod.SDraw.IsMinimized( PCMod.SDraw.SSpaces[ 42 ].win_notepad_openfile, 42 ), "main task minimizes auxiliary pickers too" )
PCMod.SDraw.SetMinimized( desktop.TaskItems[ "btn_task_notepad" ], 42, false )

-- Server activation restores a minimized program without changing OpenID.
local activated = PCMod.SDraw.SSpaces[ 42 ].window_notepad
PCMod.SDraw.SetMinimized( activated, 42, true )
activated.ActivateID = 2
assertTrue( not PCMod.SDraw.IsMinimized( activated, 42 ), "new ActivateID restores the minimized program" )

-- Server focus changes do not rebuild the layout, but must refresh active state.
PCMod.SDraw.SSpaces[ 42 ].window_notepad.Priority = 20
desktop:Tick()
desktop:UpdateTaskActive()
assertEq( desktop.Elements[ "btn_task_notepad" ].Active, true, "new topmost program becomes active" )
assertEq( desktop.Elements[ "btn_task_files" ].Active, false, "previous topmost program loses active state" )

-- A new OpenID is a new program lifetime and must not inherit minimization.
local win = PCMod.SDraw.SSpaces[ 42 ].window_files
PCMod.SDraw.SetMinimized( win, 42, true )
win.OpenID = 2
assertTrue( not PCMod.SDraw.IsMinimized( win, 42 ), "new OpenID clears old minimized state" )

PCMod.SDraw.SSpaces[ 42 ].window_files = nil
desktop:Tick()
assertEq( desktop.TaskItems[ "btn_task_files" ], nil, "closed program leaves the taskbar" )
assertEq( desktop.Elements[ "btn_task_files" ], nil, "closed program button is removed" )
assertEq( PCMod.SDraw.Minimized[ 42 ][ win.DevID ], nil, "closed program cleans minimized state" )

-- More than four programs are split into pages. +N cycles them without
-- rebuilding unrelated controls or losing the full active-window set.
PCMod.SDraw.SSpaces[ 42 ].window_alarmz = app( "alarmz", "AlarmZ" )
PCMod.SDraw.SSpaces[ 42 ].window_chatserv = app( "chatserv", "ChatServ" )
PCMod.SDraw.SSpaces[ 42 ].window_pplayer = app( "pplayer", "Personal Player" )
desktop:Tick()
assertEq( count( desktop.AllTaskItems ), 5, "all programs remain available to active logic" )
assertEq( count( desktop.TaskItems ), 4, "first page shows three apps plus overflow" )
assertTrue( desktop.Elements[ "btn_task_more" ] != nil, "overflow button exists" )
assertEq( desktop.Elements[ "btn_task_more" ].Text, "+2", "overflow counts programs on other pages" )
desktop:ButtonClick( "btn_task_more" )
assertEq( desktop.TaskPage, 1, "overflow advances to the next page" )
assertTrue( desktop.TaskItems[ "btn_task_notepad" ] != nil, "next page contains the remaining programs" )
assertEq( desktop.Elements[ "btn_task_more" ].Text, "+3", "later page counts programs on the other pages" )
desktop:ButtonClick( "btn_task_more" )
assertEq( desktop.TaskPage, 0, "overflow wraps to the first page" )

print( "mock_running PASSED" )
