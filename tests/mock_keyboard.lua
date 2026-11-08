local function assertTrue(v,m) if not v then error("FAILED: "..m,2) end end
local function assertEq(a,b,m) if a~=b then error("FAILED: "..m.." got "..tostring(a).." want "..tostring(b),2) end end

local KEY_NAMES = {
  "KEY_0","KEY_1","KEY_2","KEY_3","KEY_4","KEY_5","KEY_6","KEY_7","KEY_8","KEY_9",
  "KEY_A","KEY_APOSTROPHE","KEY_B","KEY_BACKSLASH","KEY_BACKSPACE","KEY_C","KEY_COMMA",
  "KEY_D","KEY_E","KEY_ENTER","KEY_EQUAL","KEY_F","KEY_G","KEY_H","KEY_I","KEY_J","KEY_K",
  "KEY_L","KEY_LBRACKET","KEY_LEFT","KEY_LSHIFT","KEY_M","KEY_MINUS","KEY_N","KEY_O","KEY_P",
  "KEY_PAD_0","KEY_PAD_1","KEY_PAD_2","KEY_PAD_3","KEY_PAD_4","KEY_PAD_5","KEY_PAD_6",
  "KEY_PAD_7","KEY_PAD_8","KEY_PAD_9","KEY_PAD_DECIMAL","KEY_PAD_DIVIDE","KEY_PAD_ENTER",
  "KEY_PAD_MINUS","KEY_PAD_MULTIPLY","KEY_PAD_PLUS","KEY_PERIOD","KEY_Q","KEY_R","KEY_RBRACKET",
  "KEY_RIGHT","KEY_RSHIFT","KEY_S","KEY_SEMICOLON","KEY_SLASH","KEY_SPACE","KEY_T","KEY_TAB",
  "KEY_U","KEY_V","KEY_W","KEY_X","KEY_Y","KEY_Z"
}
for i, name in ipairs( KEY_NAMES ) do _G[ name ] = 1000 + i end

local fires = {}
local down = {}
local now = 0
local hookThink

input = { IsKeyDown = function( k ) return down[ k ] == true end }
hook = { Add = function( name, id, fn )
  if (name == "Think") then hookThink = fn end
end }
CurTime = function() return now end

dofile( "cl_input.lua" )

keyboard.SetCallback( function( k ) table.insert( fires, k ) end )
assertEq( keyboard.GetLatency(), 200, "default repeat delay" )
assertEq( keyboard.GetHoldTime(), 500, "default hold time" )
keyboard.SetLatency( 100 )
keyboard.SetHoldTime( 300 )
assertEq( keyboard.GetLatency(), 100, "configured repeat delay" )
assertEq( keyboard.GetHoldTime(), 300, "configured hold time" )

keyboard.AddKey( KEY_A, "a" )
keyboard.EnableCapture( true )

down[ KEY_A ] = true
hookThink()
assertEq( #fires, 1, "first press fires" )
assertEq( fires[1], "a", "typed character" )

now = 0.1
hookThink()
assertEq( #fires, 1, "no repeat during hold" )

now = 0.3
hookThink()
assertEq( #fires, 2, "repeat starts after hold" )

now = 0.35
hookThink()
assertEq( #fires, 2, "repeat waits for interval" )

now = 0.4
hookThink()
assertEq( #fires, 3, "repeats at interval" )

down[ KEY_A ] = false
hookThink()
now = 0.41
down[ KEY_A ] = true
hookThink()
assertEq( #fires, 4, "released key re-arms immediately" )

now = 1
down[ KEY_A ] = false
hookThink()
down[ KEY_LSHIFT ] = true
down[ KEY_A ] = true
hookThink()
assertEq( fires[ #fires ], "A", "shift uses shifted character" )

keyboard.EnableCapture( false )
local n = #fires
now = 2
down[ KEY_A ] = false
hookThink()
down[ KEY_A ] = true
hookThink()
assertEq( #fires, n, "capture disabled blocks input" )

-- Quick Type is now a text window ("Clipboard" button): the usermessage carries
-- the server-stored text (same on every PC), the entry is prefilled with it (or
-- with the system clipboard when nothing is stored), and Enter saves the text
-- on the server + pastes it into the focused device.
function istable( v ) return type( v ) == "table" end
local umHooks = {}
usermessage = { Hook = function( name, fn ) umHooks[ name ] = fn end }
local madePanels = {}
local function mockPanel( title )
	local p = { _valid = true, title = title or "", _val = "" }
	function p:IsValid() return self._valid end
	function p:Remove() self._valid = false end
	function p:GetValue() return self._val end
	function p:SetValue( v ) self._val = v end
	function p:GetWide() return 400 end
	function p:GetTall() return 200 end
	return setmetatable( p, { __index = function() return function() end end } )
end
vgui = {
	Register = function() end,
	CreateWindow = function( w, h, t ) local p = mockPanel( t ) table.insert( madePanels, p ) return p end,
	Create = function( cls ) local p = mockPanel( cls ) table.insert( madePanels, p ) return p end,
}
include = function() end -- cl_input.lua fixture is already loaded above
function GetConVar( name ) return nil end
function CreateClientConVar( name, default ) return { GetFloat = function() return tonumber( default ) or 0 end } end
local notifyLog = {}
local qtSaved = {}
net = {
	Start = function( name ) net.cur = { name = name, fields = {} } end,
	WriteString = function( s ) table.insert( net.cur.fields, s ) end,
	SendToServer = function() table.insert( qtSaved, net.cur ) net.cur = nil end,
}
PCMod = { Msg = function() end, Warning = function() end, Gui = { Notify = function( msg, err ) table.insert( notifyLog, { msg = msg, err = err } ) end } }

dofile( "cl_keyboard.lua" )

assertTrue( umHooks[ "pcmod_quicktype" ] != nil, "pcmod_quicktype usermessage is hooked" )
assertTrue( PCMod.Gui.OpenQuickTypeWindow != nil, "text window handler exists" )
assertTrue( PCMod.Gui.ShowQuickType == nil, "old manual typing window is gone" )

local pasted = {}
local mockdev = { Int_QuickType = function( self, text ) table.insert( pasted, text ) end }
PCMod.SDraw = { DevFocus = "win_test", DevMap = { [ "1:win_test" ] = mockdev } }
PCMod.Gui.CamLockID = 1

-- server-stored text prefills the window; Enter saves + pastes
madePanels = {}
umHooks[ "pcmod_quicktype" ]( { ReadString = function() return "hello pc" end } )
assertEq( #madePanels, 3, "window + entry + button created" )
local qwin, qentry, qbtn = madePanels[ 1 ], madePanels[ 2 ], madePanels[ 3 ]
assertEq( qentry.title, "DTextEntry", "entry is a text entry" )
assertEq( qentry._val, "hello pc", "entry prefilled with the server-stored text" )
qentry:SetValue( "edited text" )
qbtn.DoClick()
assertEq( qtSaved[ #qtSaved ].fields[ 1 ], "edited text", "text saved on the server" )
assertEq( qtSaved[ #qtSaved ].name, "pcmod_quicktype_save", "save net message" )
assertEq( pasted[ #pasted ], "edited text", "text pasted into the focused device" )
assertTrue( qwin._valid == false, "window closed after Enter" )

-- nothing stored -> prefill from the system clipboard when available
function GetClipboardText() return "clip content" end
madePanels = {}
umHooks[ "pcmod_quicktype" ]( { ReadString = function() return "" end } )
assertEq( madePanels[ 2 ]._val, "clip content", "empty stored text prefills from clipboard" )

-- no clipboard API and nothing stored -> empty entry, no crash
GetClipboardText = nil
clipboard = nil
madePanels = {}
local crashed = not pcall( umHooks[ "pcmod_quicktype" ], { ReadString = function() return "" end } )
assertTrue( not crashed, "missing clipboard API does not raise a Lua error" )
assertEq( madePanels[ 2 ]._val, "", "entry empty when nothing stored and no clipboard API" )

print("KEYBOARD TESTS PASSED")
