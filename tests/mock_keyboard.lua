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

print("KEYBOARD TESTS PASSED")
