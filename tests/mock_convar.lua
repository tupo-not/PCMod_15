-- Keyboard convar creation/application test.
local function assertTrue( v, m ) if (not v) then error( "FAILED: " .. m, 2 ) end end
local function assertEq( a, b, m )
	if (a ~= b) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end

SERVER = false
CLIENT = true

istable = function( t ) return type( t ) == "table" end

local created = {}
function GetConVar( name ) return nil end
function CreateClientConVar( name, default, shouldsave, userdata, helptext, min, max )
	created[ name ] = {
		name = name,
		default = default,
		shouldsave = shouldsave,
		userdata = userdata,
		helptext = helptext,
		min = min,
		max = max
	}
	return { GetFloat = function() return tonumber( default ) end }
end

local callbacks = {}
cvars = {
	AddChangeCallback = function( name, fn, id )
		callbacks[ name ] = { fn = fn, id = id }
	end
}

PCMod = { Msg = function() end, Gui = {} }
keyboard = {
	SetCallback = function() end,
	SetLatency = function( v ) keyboard.Latency = v end,
	SetHoldTime = function( v ) keyboard.Hold = v end,
	EnableCapture = function() end
}
hook = { Add = function() end }
net = { Receive = function() end }
vgui = { Register = function() end }
include = function() end

dofile( "cl_keyboard.lua" )

assertTrue( created.pc_keyrepeat ~= nil, "repeat convar created" )
assertEq( created.pc_keyrepeat.default, "200", "repeat default" )
assertEq( created.pc_keyrepeat.shouldsave, true, "repeat is archived" )
assertEq( created.pc_keyrepeat.userdata, false, "repeat is not userdata" )
assertEq( type( created.pc_keyrepeat.helptext ), "string", "repeat helptext is a string" )
assertTrue( created.pc_keyhold ~= nil, "hold convar created" )
assertEq( created.pc_keyhold.default, "500", "hold default" )
assertEq( created.pc_keyhold.shouldsave, true, "hold is archived" )
assertEq( created.pc_keyhold.userdata, false, "hold is not userdata" )
assertEq( type( created.pc_keyhold.helptext ), "string", "hold helptext is a string" )

assertTrue( callbacks.pc_keyrepeat ~= nil, "repeat change callback registered" )
assertTrue( callbacks.pc_keyhold ~= nil, "hold change callback registered" )
assertEq( keyboard.Latency, 200, "repeat applied at load" )
assertEq( keyboard.Hold, 500, "hold applied at load" )

callbacks.pc_keyrepeat.fn( "pc_keyrepeat", "200", "100" )
assertEq( keyboard.Latency, 100, "repeat change applied" )
callbacks.pc_keyhold.fn( "pc_keyhold", "500", "250" )
assertEq( keyboard.Hold, 250, "hold change applied" )

callbacks.pc_keyrepeat.fn( "pc_keyrepeat", "100", "5" )
assertEq( keyboard.Latency, 20, "repeat clamped low" )
callbacks.pc_keyrepeat.fn( "pc_keyrepeat", "20", "9999" )
assertEq( keyboard.Latency, 1000, "repeat clamped high" )
callbacks.pc_keyhold.fn( "pc_keyhold", "250", "-5" )
assertEq( keyboard.Hold, 0, "hold clamped low" )
callbacks.pc_keyhold.fn( "pc_keyhold", "0", "9999" )
assertEq( keyboard.Hold, 2000, "hold clamped high" )

print( "KEYBOARD CONVAR TESTS PASSED" )
