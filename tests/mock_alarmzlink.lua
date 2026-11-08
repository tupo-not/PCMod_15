-- Alarmz camera link + password system (sv_alarmz.lua) mock tests.
-- plain Lua after translation; fixture: pcmod_sv_alarmz.lua

local function assertTrue( v, m ) if (not v) then error( "FAILED: " .. m, 2 ) end end
local function assertEq( a, b, m ) if (a ~= b) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end end
function istable( v ) return type( v ) == "table" end

function CurTime() return 100 end

-- vector-ish position with DistToSqr
local function V( x, y, z )
	return { x = x, y = y, z = z,
		DistToSqr = function( self, o )
			local dx, dy, dz = self.x - o.x, self.y - o.y, self.z - o.z
			return dx * dx + dy * dy + dz * dz
		end }
end

function IsValid( e ) return (e != nil) and (e._valid == true) end

local Ents = {}
ents = { GetByIndex = function( i ) return Ents[ i ] end }

local function MakeEnt( idx, class, opts )
	opts = opts or {}
	local e = { _valid = true, _idx = idx, _class = class, _pos = opts.pos or V( 0, 0, 0 ),
		IsPCMod = opts.IsPCMod, IsScreen = opts.IsScreen, IsComputer = opts.IsComputer, _ports = opts.ports or {} }
	function e:GetClass() return self._class end
	function e:EntIndex() return self._idx end
	function e:GetPos() return self._pos end
	function e:Ports() return self._ports end
	return e
end

local function MakePly( steamid, pos )
	local p = { _valid = true, steamid = steamid, _pos = pos or V( 0, 0, 0 ) }
	function p:IsValid() return self._valid end
	function p:SteamID() return self.steamid end
	function p:GetPos() return self._pos end
	return p
end

-- net mock: records sent messages, supports scripted reads
local netSent = {}
local netHandlers = {}
local readq = {}
local cur = nil
net = {
	Start = function( name ) cur = { name = name, fields = {} } end,
	WriteString = function( s ) table.insert( cur.fields, s ) end,
	WriteUInt = function( v ) table.insert( cur.fields, v ) end,
	WriteBool = function( v ) table.insert( cur.fields, v and true or false ) end,
	ReadString = function() return table.remove( readq, 1 ) end,
	ReadUInt = function() return table.remove( readq, 1 ) end,
	Send = function( ply ) table.insert( netSent, { msg = cur, to = ply and ply.steamid or "?" } ) cur = nil end,
	Broadcast = function() table.insert( netSent, { msg = cur, to = "all" } ) cur = nil end,
	Receive = function( name, fn ) netHandlers[ name ] = fn end,
}

util = {
	AddNetworkString = function() end,
	SHA256 = function( s ) return "sha256(" .. tostring( s ) .. ")" end,
}

local hooks = {}
hook = { Add = function( name, id, fn ) hooks[ name .. ":" .. id ] = fn end }

local notices = {}
PCMod = {
	Data = {},
	Notice = function( msg, ply ) table.insert( notices, { msg = msg, to = ply and ply.steamid or "?" } ) end,
}

-- fake PC with an alarmz program instance
local function MakePC( idx )
	local prog = { DeviceData = {}, updated = 0, UpdateSS = function( self ) self.updated = self.updated + 1 end }
	PCMod.Data[ idx ] = { Drivers = { gen_bios = { OS = { Progs = { alarmz = prog } } } } }
	local pc = MakeEnt( idx, "pcmod_tower", { IsPCMod = true, IsComputer = true } )
	Ents[ idx ] = pc
	return pc, prog
end

local function lastResult()
	local r = netSent[ #netSent ]
	assertTrue( r != nil, "a result message was sent" )
	return r.msg.fields -- { ok, msg, camIdx, canSetPass }
end

local function lastStateFor( camIdx, plyid )
	for i = #netSent, 1, -1 do
		local m = netSent[ i ].msg
		if ((m.name == "pcmod_alarmz_state") && (m.fields[ 1 ] == camIdx) && ((plyid == nil) || (netSent[ i ].to == plyid))) then
			return m.fields
		end
	end
	return nil
end

dofile( "pcmod_sv_alarmz.lua" )

-- world: camera #11, monitor #21 (vga-linked to PC #31), PC #31, spare PC #32,
-- unlinked monitor #22
local cam11 = MakeEnt( 11, "gmod_wire_rt_camera", { pos = V( 10, 0, 0 ) } )
Ents[ 11 ] = cam11
local pc31, prog31 = MakePC( 31 )
pc31._pos = V( 100, 0, 0 )
local mon21 = MakeEnt( 21, "pcmod_monitor", { IsPCMod = true, IsScreen = true, pos = V( 100, 10, 0 ),
	ports = { { Type = "vga", Connected = true, ConEnt = pc31, RemotePort = 1 } } } )
Ents[ 21 ] = mon21
local pc32, prog32 = MakePC( 32 )
pc32._pos = V( 200, 0, 0 )
local mon22 = MakeEnt( 22, "pcmod_monitor", { IsPCMod = true, IsScreen = true, pos = V( 100, 20, 0 ),
	ports = { { Type = "vga", Connected = false, ConEnt = nil, RemotePort = 0 } } } )
Ents[ 22 ] = mon22
local mon23 = MakeEnt( 23, "pcmod_monitor", { IsPCMod = true, IsScreen = true, pos = V( 200, 10, 0 ),
	ports = { { Type = "vga", Connected = true, ConEnt = pc32, RemotePort = 1 } } } )
Ents[ 23 ] = mon23

local plyA = MakePly( "STEAM_A" )   -- will become the first connector / password owner
local plyB = MakePly( "STEAM_B" )
local farPly = MakePly( "STEAM_FAR", V( 999999, 0, 0 ) )

-- 1. first begin: entry created, owner = A, no password
PCMod.Alarmz.Begin( plyA, 11 )
local entry = PCMod.Alarmz.CamEntry( 11 )
assertTrue( entry != nil, "cam entry created on first begin" )
assertEq( entry.ownerID, "STEAM_A", "first connector becomes password owner" )
assertEq( entry.hash, nil, "no password yet" )
local st = lastStateFor( 11, "STEAM_A" )
assertTrue( st != nil, "state sent to beginner" )
assertEq( st[ 2 ], false, "state: hasPass=false" )
assertEq( st[ 3 ], true, "state: isOwner=true for A" )

-- 2. connect without password works (camera is open)
netSent = {}
PCMod.Alarmz.Connect( plyA, 11, 21, "" )
local res = lastResult()
assertEq( res[ 1 ], true, "open camera connects: " .. tostring( res[ 2 ] ) )
assertTrue( entry.links[ 31 ] == true, "link to PC 31 recorded" )
assertEq( prog31.DeviceData.Cams[ 1 ], 11, "alarmz window of PC 31 got the camera" )
assertTrue( prog31.updated >= 1, "PC 31 window was refreshed" )

-- 3. duplicate connect is rejected
netSent = {}
PCMod.Alarmz.Connect( plyA, 11, 21, "" )
assertEq( lastResult()[ 1 ], false, "duplicate connect rejected" )
assertTrue( string.find( lastResult()[ 2 ], "already connected", 1, true ) != nil, "duplicate message" )

-- 4. owner sets a password: stored hashed, never plaintext
netSent = {}
PCMod.Alarmz.SetPass( plyA, 11, "secret" )
assertEq( lastResult()[ 1 ], true, "owner can set password" )
assertTrue( entry.hash != nil, "hash stored" )
assertTrue( entry.hash != "secret", "password not stored in plaintext" )
assertEq( entry.hash, PCMod.Alarmz.Hash( entry.salt, "secret" ), "hash = sha256(salt:pass)" )
assertEq( lastStateFor( 11 )[ 2 ], true, "state broadcast: hasPass=true" )

-- 5. other player cannot connect without / with wrong password
PCMod.Alarmz.Connect( plyB, 11, 23, "" )
assertEq( lastResult()[ 1 ], false, "no password -> rejected" )
assertTrue( string.find( lastResult()[ 2 ], "Wrong camera password", 1, true ) != nil, "wrong-pass message" )
PCMod.Alarmz.Connect( plyB, 11, 23, "nope" )
assertEq( lastResult()[ 1 ], false, "wrong password -> rejected" )

-- 6. correct password connects the other player
PCMod.Alarmz.Connect( plyB, 11, 23, "secret" )
assertEq( lastResult()[ 1 ], true, "correct password connects" )
assertTrue( entry.links[ 32 ] == true, "link to PC 32 recorded" )
assertEq( prog32.DeviceData.Cams[ 1 ], 11, "alarmz window of PC 32 got the camera" )

-- 7. non-owner cannot change or remove the password
PCMod.Alarmz.SetPass( plyB, 11, "hacked" )
assertEq( lastResult()[ 1 ], false, "non-owner cannot set password" )
assertEq( entry.hash, PCMod.Alarmz.Hash( entry.salt, "secret" ), "hash unchanged after non-owner attempt" )
PCMod.Alarmz.SetPass( plyB, 11, "" )
assertEq( lastResult()[ 1 ], false, "non-owner cannot remove password" )
assertTrue( entry.hash != nil, "password survives non-owner removal attempt" )

-- 8. owner leaving does not weaken the password (hash stays, checks still enforced)
plyA._valid = false
assertTrue( PCMod.Alarmz.CheckPass( entry, "secret" ) == true, "owner offline: correct pass still works" )
assertTrue( PCMod.Alarmz.CheckPass( entry, "wrong" ) == false, "owner offline: wrong pass still rejected" )
plyA._valid = true

-- 9. owner changes the password; old one stops working, new one works
PCMod.Alarmz.SetPass( plyA, 11, "newpass" )
assertTrue( PCMod.Alarmz.CheckPass( entry, "secret" ) == false, "old password invalid after change" )
assertTrue( PCMod.Alarmz.CheckPass( entry, "newpass" ) == true, "new password valid after change" )

-- 10. owner removes the password -> camera open again
PCMod.Alarmz.SetPass( plyA, 11, "" )
assertEq( entry.hash, nil, "password removed" )
assertTrue( PCMod.Alarmz.CheckPass( entry, nil ) == true, "no password -> any connect allowed" )

-- 11. monitor without VGA link is rejected
PCMod.Alarmz.Connect( plyA, 11, 22, "" )
assertEq( lastResult()[ 1 ], false, "unlinked monitor rejected" )
assertTrue( string.find( lastResult()[ 2 ], "VGA", 1, true ) != nil, "VGA message" )

-- 12. non-screen entity as monitor is rejected
local notscreen = MakeEnt( 24, "pcmod_tower", { IsPCMod = true, IsComputer = true } )
Ents[ 24 ] = notscreen
PCMod.Alarmz.Connect( plyA, 11, 24, "" )
assertEq( lastResult()[ 1 ], false, "non-screen monitor rejected" )

-- 13. distance is enforced
PCMod.Alarmz.Begin( farPly, 11 )
assertEq( lastResult()[ 1 ], false, "far player cannot begin" )
PCMod.Alarmz.Connect( farPly, 11, 21, "" )
assertEq( lastResult()[ 1 ], false, "far player cannot connect" )

-- 14. non-camera entity cannot be begun
PCMod.Alarmz.Begin( plyA, 24 )
assertTrue( PCMod.Alarmz.CamEntry( 24 ) == nil, "non-camera gets no entry" )

-- 15. disconnect (monIdx=0 picks first link)
PCMod.Alarmz.Disconnect( plyA, 11, 0 )
assertEq( lastResult()[ 1 ], true, "disconnect works" )
assertEq( #PCMod.Alarmz.CamsForPC( 31 ), 0, "PC 31 no longer has the camera" )
assertEq( prog31.DeviceData.Cams[ 1 ], nil, "PC 31 window list updated" )
assertTrue( entry.links[ 32 ] == true, "other link untouched" )

-- 16. removing the camera clears password + all links
PCMod.Alarmz.SetPass( plyA, 11, "secret" ) -- set again to prove cleanup
hooks[ "EntityRemoved:PCMod.Alarmz.Cleanup" ]( cam11 )
assertTrue( PCMod.Alarmz.CamEntry( 11 ) == nil, "camera entry removed with the camera" )
assertEq( #PCMod.Alarmz.CamsForPC( 32 ), 0, "links cleaned on camera removal" )
assertEq( prog32.DeviceData.Cams[ 1 ], nil, "PC 32 window list cleaned" )

-- 17. removing a monitor/PC drops only its links, password survives
PCMod.Alarmz.Begin( plyA, 11 ) -- re-create entry (camera entity still exists here)
entry = PCMod.Alarmz.CamEntry( 11 )
PCMod.Alarmz.Connect( plyA, 11, 21, "" )
PCMod.Alarmz.Connect( plyB, 11, 23, "" )
PCMod.Alarmz.SetPass( plyA, 11, "secret" )
hooks[ "EntityRemoved:PCMod.Alarmz.Cleanup" ]( mon21 ) -- monitor removed
assertEq( #PCMod.Alarmz.CamsForPC( 31 ), 0, "link to PC31 dropped when its monitor was removed" )
assertTrue( entry.links[ 32 ] == true, "link to PC32 survives" )
assertTrue( entry.hash != nil, "camera password survives monitor removal" )
hooks[ "EntityRemoved:PCMod.Alarmz.Cleanup" ]( pc32 ) -- PC removed
assertEq( #PCMod.Alarmz.CamsForPC( 32 ), 0, "link dropped when PC removed" )
assertTrue( PCMod.Alarmz.CamEntry( 11 ) != nil, "camera entry survives PC removal" )
assertTrue( entry.hash != nil, "password survives PC removal" )

-- 18. net dispatch works end to end
netSent = {}
readq = { "begin", 11, 0, "" }
netHandlers[ "pcmod_alarmz_req" ]( 0, plyA )
assertTrue( lastStateFor( 11, "STEAM_A" ) != nil, "net 'begin' produces a state message" )

-- =============================================================================
-- client side: cl_alarmz.lua (overlay + E-key flow)
-- =============================================================================

net.ReadBool = function() return table.remove( readq, 1 ) end
local clSent = {}
net.SendToServer = function() table.insert( clSent, cur ) cur = nil end

local clNotifies = {}
local clLabels = {}
PCMod.Gui = {
	CamLocked = false,
	Notify = function( msg, err ) table.insert( clNotifies, { msg = msg, err = err } ) end,
	DrawLabel = function( x, y, font, lines ) table.insert( clLabels, lines ) end,
}

function Color( r, g, b, a ) return { r = r, g = g, b = b, a = a or 255 } end
function ScrW() return 1600 end
function ScrH() return 900 end

local clTrace = { Entity = nil, HitPos = nil }
local clPly = {
	GetEyeTrace = function() return clTrace end,
	GetShootPos = function() return V( 0, 0, 0 ) end,
}
function LocalPlayer() return clPly end

local function mockPanel( title )
	local p = { _valid = true, title = title, _val = "" }
	function p:IsValid() return self._valid end
	function p:Remove() self._valid = false end
	function p:GetValue() return self._val end
	function p:SetValue( v ) self._val = v end
	function p:GetWide() return 300 end
	function p:GetTall() return 120 end
	return setmetatable( p, { __index = function( t, k ) return function() end end } )
end
local createdWins = {}
vgui = {
	CreateWindow = function( w, h, title ) local win = mockPanel( title ) table.insert( createdWins, win ) return win end,
	Create = function( cls ) return mockPanel( cls ) end,
}

dofile( "pcmod_cl_alarmz.lua" )

-- overlay text content
cam11.GetActive = function() return true end
local lines = PCMod.AlarmzCL.OverlayLines( 11, cam11, nil )
assertEq( lines[ 1 ], "RT Camera #11", "overlay shows camera id" )
assertEq( lines[ 2 ], "Status: ONLINE", "overlay shows status" )
assertEq( lines[ 3 ], "[E] Connect", "open camera offers connect" )
lines = PCMod.AlarmzCL.OverlayLines( 11, cam11, { hasPass = false, isOwner = true, links = { [ 31 ] = true } } )
assertTrue( string.find( lines[ 3 ], "Linked to PC #31", 1, true ) != nil, "overlay lists link" )
assertEq( lines[ 4 ], "[E] Disconnect", "linked camera offers disconnect" )
lines = PCMod.AlarmzCL.OverlayLines( 11, cam11, { hasPass = true, isOwner = false, links = {} } )
assertTrue( string.find( lines[ 3 ], "Locked", 1, true ) != nil, "locked camera marked" )
assertEq( lines[ 4 ], "[E] Enter password", "locked camera asks for password" )
lines = PCMod.AlarmzCL.OverlayLines( 11, cam11, { hasPass = true, isOwner = true, links = {} } )
assertEq( lines[ 4 ], "[E] Connect (owner)", "owner connects without password" )

-- flow decision
assertEq( PCMod.AlarmzCL.DecideFlow( { hasPass = true, isOwner = false } ), "pass", "locked+stranger -> password" )
assertEq( PCMod.AlarmzCL.DecideFlow( { hasPass = true, isOwner = true } ), "pick", "locked+owner -> pick" )
assertEq( PCMod.AlarmzCL.DecideFlow( { hasPass = false, isOwner = false } ), "pick", "open -> pick" )

-- aiming alone does NOT connect: Think only tracks + asks for state
clTrace.Entity = cam11
clTrace.HitPos = { ToScreen = function() return { x = 100, y = 100 } end }
hooks[ "Think:PCMod.AlarmzCL.Track" ]()
assertEq( PCMod.AlarmzCL.Target, 11, "aiming at camera sets target" )
assertEq( clSent[ #clSent ].fields[ 1 ], "state", "aiming only requests state, no connect" )
clTrace.Entity = nil
hooks[ "Think:PCMod.AlarmzCL.Track" ]()
assertEq( PCMod.AlarmzCL.Target, 0, "looking away clears target" )

-- E on camera sends begin and is consumed (blocks ENT:Use)
clTrace.Entity = cam11
hooks[ "Think:PCMod.AlarmzCL.Track" ]()
clSent = {}
local consumed = hooks[ "PlayerBindPress:PCMod.AlarmzCL.Use" ]( clPly, "+use" )
assertEq( consumed, true, "E on camera is consumed by Alarmz (ENT:Use blocked)" )
assertEq( clSent[ #clSent ].fields[ 1 ], "begin", "E sends begin" )
assertEq( PCMod.AlarmzCL.PendingBegin, 11, "begin pending" )
-- E elsewhere (not aiming at a camera) is not consumed
clTrace.Entity = nil
hooks[ "Think:PCMod.AlarmzCL.Track" ]()
assertTrue( hooks[ "PlayerBindPress:PCMod.AlarmzCL.Use" ]( clPly, "+use" ) == nil, "E elsewhere passes through" )

-- server answers state (no password) -> pick mode
readq = { 11, false, true, 0 }
netHandlers[ "pcmod_alarmz_state" ]()
assertEq( PCMod.AlarmzCL.PickCam, 11, "state without password enters monitor-pick mode" )

-- E in pick mode on a screen sends connect; E off-screen cancels
local monEnt = MakeEnt( 21, "pcmod_monitor", { IsPCMod = true, IsScreen = true, pos = V( 100, 0, 0 ) } )
clTrace.Entity = monEnt
clSent = {}
consumed = hooks[ "PlayerBindPress:PCMod.AlarmzCL.Use" ]( clPly, "+use" )
assertEq( consumed, true, "E in pick mode consumed" )
assertEq( clSent[ #clSent ].fields[ 1 ], "connect", "pick on screen sends connect" )
assertEq( clSent[ #clSent ].fields[ 2 ], 11, "connect carries camera" )
assertEq( clSent[ #clSent ].fields[ 3 ], 21, "connect carries screen" )
clTrace.Entity = nil
hooks[ "PlayerBindPress:PCMod.AlarmzCL.Use" ]( clPly, "+use" )
assertEq( PCMod.AlarmzCL.PickCam, 0, "E off-screen cancels the pick" )

-- result ok on connect: notify + leave pick mode
PCMod.AlarmzCL.PickCam = 11
readq = { true, "Camera #11 connected to PC #31", 11, false }
netHandlers[ "pcmod_alarmz_result" ]()
assertEq( PCMod.AlarmzCL.PickCam, 0, "successful connect leaves pick mode" )
assertEq( clNotifies[ #clNotifies ].msg, "Camera #11 connected to PC #31", "success notification shown" )
assertEq( clNotifies[ #clNotifies ].err, false, "success is not an error" )

-- wrong password: result fail on auth reopens window with error
PCMod.AlarmzCL.LastAction = "auth"
createdWins = {}
readq = { false, "Wrong camera password", 11, false }
netHandlers[ "pcmod_alarmz_result" ]()
assertTrue( #createdWins > 0, "password window reopened after wrong password" )
assertTrue( PCMod.AlarmzCL.PassErr ~= nil, "error label stored" )

-- locked camera: state with hasPass -> password window opens instead of pick
PCMod.AlarmzCL.PendingBegin = 11
createdWins = {}
readq = { 11, true, false, 0 }
netHandlers[ "pcmod_alarmz_state" ]()
assertEq( PCMod.AlarmzCL.PickCam, 0, "locked camera does not enter pick mode" )
assertTrue( #createdWins > 0, "password window opened for locked camera" )
assertTrue( string.find( createdWins[ #createdWins ].title, "password required", 1, true ) != nil, "auth window title" )

-- first connect by owner: result with canSetPass opens the set-password offer
readq = { true, "Camera #11 connected to PC #31", 11, true }
netHandlers[ "pcmod_alarmz_result" ]()
assertTrue( #createdWins > 0, "set-password offer opened after first connect" )
assertTrue( string.find( createdWins[ #createdWins ].title, "set password", 1, true ) != nil, "setpass window title" )

-- E on a linked camera sends disconnect
PCMod.AlarmzCL.PickCam = 0
PCMod.AlarmzCL.Target = 11
PCMod.AlarmzCL.States[ 11 ] = { hasPass = false, isOwner = true, links = { [ 31 ] = true } }
clSent = {}
hooks[ "PlayerBindPress:PCMod.AlarmzCL.Use" ]( clPly, "+use" )
assertEq( clSent[ #clSent ].fields[ 1 ], "disconnect", "E on linked camera disconnects" )

-- overlay drawing uses the PCMod label style
clLabels = {}
clTrace.Entity = cam11
clTrace.HitPos = { ToScreen = function() return { x = 100, y = 100 } end }
hooks[ "HUDPaint:PCMod.AlarmzCL.Overlay" ]()
assertTrue( #clLabels > 0, "overlay drawn when aiming at camera" )
assertEq( clLabels[ 1 ][ 1 ], "RT Camera #11", "overlay first line is the camera id" )

-- overlay range is a cfg setting (default 512), checked client-side
PCMod.Cfg = { AlarmzOverlayRange = 512 }
assertEq( PCMod.AlarmzCL.OverlayRange(), 512, "range read from cfg" )
local nearCam = MakeEnt( 14, "gmod_wire_rt_camera", { pos = V( 500, 0, 0 ) } ) -- 500 < 512
local farCam = MakeEnt( 15, "gmod_wire_rt_camera", { pos = V( 600, 0, 0 ) } )  -- 600 > 512
clTrace.Entity = farCam
clSent = {}
hooks[ "Think:PCMod.AlarmzCL.Track" ]()
assertEq( PCMod.AlarmzCL.Target, 0, "camera beyond the overlay range is not targeted" )
assertEq( #clSent, 0, "no state request for an out-of-range camera" )
clTrace.Entity = nearCam
hooks[ "Think:PCMod.AlarmzCL.Track" ]()
assertEq( PCMod.AlarmzCL.Target, 14, "camera within range is targeted" )
clTrace.Entity = farCam
hooks[ "Think:PCMod.AlarmzCL.Track" ]()
assertEq( PCMod.AlarmzCL.Target, 0, "target cleared immediately when leaving the radius" )
PCMod.Cfg = {}
assertEq( PCMod.AlarmzCL.OverlayRange(), 512, "default 512 when cfg missing" )
PCMod.Cfg = { AlarmzOverlayRange = 100 }
assertEq( PCMod.AlarmzCL.OverlayRange(), 100, "cfg override respected" )
PCMod.Cfg = { AlarmzOverlayRange = 512 }
clTrace.Entity = nil

print( "ALL ALARMZ LINK TESTS PASSED" )
