-- Alarmz: server program commands + client Wiremod camera monitor mock.
-- (plain Lua after translation; fixtures come from .build)

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
function string.Trim( s ) return (string.gsub( s, "^%s*(.-)%s*$", "%1" )) end
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
function math.Clamp( v, a, b )
	if (v < a) then return a end
	if (v > b) then return b end
	return v
end

local Now = 0
function CurTime() return Now end

notifies = {}
PCMod = {
	Msg = function() end,
	Data = {},
	Cfg = {},
	IPv6 = { IsIP = function() return false end },
	SDraw = { CFrame = 0 },
	Gui = {
		GetThemeColour = function( theme, key, default ) return default or Color( 0, 0, 0, 255 ) end,
		ThemeDraw = function() return false end,
		Notify = function( msg, err ) table.insert( notifies, { msg = msg, err = err } ) end,
	},
	SSEL = {
		Create = function( class )
			return {
				IsValid = function( self ) return true end,
				SetTheme = function( self, t ) end,
				SetLayout = function( self, x, y, w, h ) self.X, self.Y, self.W, self.H = x, y, w, h end,
				SetText = function( self, t ) self.Text = t end,
				SetIcon = function( self, i ) end,
				SetFunc = function( self, n, f ) self.Funcs = self.Funcs or {} self.Funcs[ n ] = f end,
				CursorInside = function( self, cx, cy ) return false end,
				Paint = function( self ) end,
				Remove = function( self ) end,
			}
		end,
	},
}

local texLast = nil
local texRect = nil
local matLast = nil
local curCol = nil
local rects = {}
local texts = {}
surface = {
	SetFont = function() end,
	GetTextSize = function( t ) return #tostring( t ) * 6, 10 end,
	SetDrawColor = function( r, g, b, a ) curCol = { r = r, g = g, b = b, a = a } end,
	DrawRect = function( x, y, w, h ) table.insert( rects, { x = x, y = y, w = w, h = h, col = curCol } ) end,
	DrawOutline = function() end,
	DrawLine = function() end,
	-- The engine build in use only accepts numeric texture IDs here; passing a
	-- userdata (e.g. a Wiremod RenderTarget ITexture) raises "number expected,
	-- got userdata". Keep the mock strict so the regression is caught.
	SetTexture = function( t )
		if (type( t ) ~= "number") then error( "surface.SetTexture: number expected, got " .. type( t ), 3 ) end
		texLast = t
	end,
	SetMaterial = function( m ) matLast = m end,
	DrawTexturedRect = function( x, y, w, h ) texRect = { x = x, y = y, w = w, h = h } end,
}
draw = { SimpleText = function( txt, ... ) table.insert( texts, tostring( txt ) ) end }
TEXT_ALIGN_LEFT = 0
TEXT_ALIGN_CENTER = 1
TEXT_ALIGN_TOP = 0
function RunConsoleCommand() end
util = { Compress = function( s ) return s end }

-- CreateMaterial mock: records the bound $basetexture like IMaterial:SetTexture.
local createdMats = {}
function CreateMaterial( name, shader, params )
	local m = { name = name, shader = shader, params = params, basetexture = nil }
	function m:SetTexture( param, tex )
		if (param ~= "$basetexture") then error( "FAILED: unexpected material param " .. tostring( param ), 2 ) end
		self.basetexture = tex
	end
	table.insert( createdMats, m )
	return m
end

-- Wiremod world mocks -------------------------------------------------------

WireLib = nil
local Ents = {}
function IsValid( e ) return (e != nil) and (e.removed != true) end
ents = {
	GetByIndex = function( i ) return Ents[ i ] end,
	FindByClass = function( cls )
		local out = {}
		for i, e in pairs( Ents ) do
			if (IsValid( e ) and (e:GetClass() == cls)) then table.insert( out, e ) end
		end
		table.sort( out, function( a, b ) return a:EntIndex() < b:EntIndex() end )
		return out
	end,
}

-- Emulates gmod_wire_rt_camera clientside behaviour: SetIsObserved creates /
-- drops the RenderTarget reference; deactivation unobserves the camera, the
-- same way Wiremod's own SetCameraActive does.
local function MakeCam( idx, active, fov )
	local cam = { removed = false, IsObserved = false, RenderTarget = nil, active = active, fov = fov, pos = { 0, 0, 0 } }
	function cam:GetClass() return "gmod_wire_rt_camera" end
	function cam:EntIndex() return idx end
	function cam:GetActive() return self.active == true end
	function cam:GetCamFOV() return self.fov end
	function cam:SetCamFOV( v ) self.fov = v end
	function cam:GetPos() return self.pos end
	function cam:SetPos( p ) self.pos = p end
	function cam:SetActive( v )
		self.active = (v ~= 0) and (v ~= false)
		if ((not self.active) and self.IsObserved) then self:SetIsObserved( false ) end
	end
	function cam:SetIsObserved( v )
		assert( type( v ) == "boolean" )
		if (v == self.IsObserved) then return end
		self.IsObserved = v
		if (v) then self.RenderTarget = { cam = idx } else self.RenderTarget = nil end
	end
	return cam
end

local function assertTrue( v, msg )
	if (not v) then error( "FAILED: " .. msg, 2 ) end
end
local function assertEq( a, b, msg )
	if (a ~= b) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function hasAlert( dev, part )
	for _, a in ipairs( dev.Alerts or {} ) do
		if (string.find( a.msg, part, 1, true )) then return true end
	end
	return false
end
-- Counts ALL notifications ever pushed (the in-app ring buffer is capped at 6).
local function countNotifies( part )
	local n = 0
	for _, nt in ipairs( notifies ) do
		if (string.find( nt.msg, part, 1, true )) then n = n + 1 end
	end
	return n
end

-- =============================================================================
-- Part 1: server-side program (pr_alarmz.lua)
-- =============================================================================

PROG = {}
dofile( "prog_base.lua" )
local pbase = table.Copy( PROG )
PROG = table.Copy( pbase )
dofile( "pcmod_alarmz.lua" )
local prog = table.Copy( PROG )

local usbSent = {}
local runCmds = {}
local fakeos = {
	RefreshUSBData = function( self ) end,
	GetUSBDevicePorts = function( self, name ) if (name == "iodev") then return { 7 } end return {} end,
	SendUSBData = function( self, port, data ) table.insert( usbSent, { port = port, data = data } ) end,
	RunCommand = function( self, com ) table.insert( runCmds, com ) end,
}
prog.DeviceData = {}
prog.GetOS = function( self ) return fakeos end
prog.UpdateSS = function( self ) self.SSUpdates = (self.SSUpdates or 0) + 1 end
prog.Exit = function( self ) self.Exited = true end

assertEq( prog.Name, "alarmz", "program name kept" )
assertEq( prog.DeviceLink, "window_alarmz", "device link contract kept" )
assertEq( prog.DeviceName, "window_alarmz", "device name contract kept" )

prog:OnStart()
assertEq( prog.Device, 7, "iodev port found on start" )
assertEq( prog.DeviceData.Al, 0, "alarm disabled on start" )
assertEq( prog.DeviceData.SelCam, 0, "no camera selected on start" )
assertEq( usbSent[ #usbSent ].data[ 1 ], "set_output", "usb set_output sent" )
assertEq( usbSent[ #usbSent ].data[ 3 ], 0, "usb output 0 on start" )
assertTrue( runCmds[ #runCmds ] == "snd_stop", "sound stopped on start" )

prog:DoCommand( "enable", {} )
assertEq( prog.DeviceData.Al, 1, "alarm enabled" )
assertEq( usbSent[ #usbSent ].data[ 3 ], 1, "usb output 1 on enable" )
assertTrue( runCmds[ #runCmds ] == "snd_play ambient/alarms/alarm1.wav", "alarm sound played" )

prog:DoCommand( "selectcam", { 123 } )
assertEq( prog.DeviceData.SelCam, 123, "selectcam stored server-side" )
prog:DoCommand( "selectcam", { "abc" } )
assertEq( prog.DeviceData.SelCam, 123, "invalid selectcam ignored" )

prog:DoCommand( "setalarmsound", { "x.wav" } )
assertEq( prog.AlarmSound, "x.wav", "alarm sound changed" )

prog:DoCommand( "exit", {} )
assertTrue( prog.Exited == true, "exit command exits" )

-- =============================================================================
-- Part 2: client-side window device (dev_win_alarmz.lua) + Wiremod integration
-- =============================================================================

DEV = {}
dofile( "pcmod_ss_base.lua" )
dofile( "pcmod_alarmz_ui.lua" )

local dev = table.Copy( DEV )
dev:OnCreate()
dev.Th = "basic"
dev.win_x, dev.win_y, dev.win_w, dev.win_h = 0, 0, 800, 600

local progCalls = {}
dev.RunProgCommand = function( self, p, com, a ) table.insert( progCalls, { prog = p, com = com, a = a } ) end

local function lastProgCall()
	return progCalls[ #progCalls ]
end

-- No Wiremod installed: window must initialise and report it, no crash.
WireLib = nil
Ents = {}
Now = 100
dev:Initialize( 0, 0, 800, 600 )
assertTrue( dev.Listboxes.lstCams != nil, "camera listbox created" )
assertTrue( dev.Elements.btnExit != nil, "exit button created" )
assertTrue( dev.Elements.btnRefresh != nil, "refresh button created" )
assertTrue( dev.Elements.btnEnable != nil, "enable button created" )
assertTrue( dev.Elements.btnDisable != nil, "disable button created" )
assertTrue( dev.WireOK == false, "wiremod reported missing" )
assertEq( table.Count( dev.CamList ), 0, "no cameras without wiremod" )
texLast = "sentinel"
matLast = nil
dev:Paint( 0, 0, 800, 600 )
assertTrue( texLast == "sentinel", "no camera texture drawn without wiremod" )
assertTrue( matLast == nil, "no material drawn without wiremod" )

-- Wiremod present, two cameras (one active, one inactive).
WireLib = {}
local cam11 = MakeCam( 11, true, 80 )
local cam12 = MakeCam( 12, false, 60 )
Ents = { [11] = cam11, [12] = cam12 }
Now = 101
dev:ScanCameras()
assertTrue( dev.WireOK == true, "wiremod detected" )
assertTrue( dev.CamList[ 11 ] != nil and dev.CamList[ 12 ] != nil, "both cameras found" )
assertEq( #dev.Listboxes.lstCams.Order, 2, "two rows in camera list" )
assertEq( dev.Listboxes.lstCams.Order[ 1 ], "cam_11", "list sorted by entindex (1)" )
assertEq( dev.Listboxes.lstCams.Order[ 2 ], "cam_12", "list sorted by entindex (2)" )
assertTrue( string.find( dev.Listboxes.lstCams.List.cam_11, "%[ON%]" ) != nil, "active camera labelled ON" )
assertTrue( string.find( dev.Listboxes.lstCams.List.cam_12, "%[OFF%]" ) != nil, "inactive camera labelled OFF" )
assertTrue( hasAlert( dev, "Camera #11 detected" ), "detection alert logged" )

-- Select camera 11 through the listbox: it becomes observed, its RenderTarget
-- is drawn through the material, and the server is told about the selection.
dev:ListboxSelect( "lstCams", "cam_11", false, 0.1, 0.3 )
assertEq( dev.SelEnt, 11, "camera 11 selected" )
assertTrue( cam11.IsObserved == true, "camera 11 observed via SetIsObserved" )
assertTrue( cam11.RenderTarget != nil, "camera 11 RenderTarget exists (created by wiremod)" )
assertEq( dev:GetListboxSelRow( "lstCams" ), "cam_11", "listbox row selected" )
assertEq( lastProgCall().com, "selectcam", "selectcam sent to server" )
assertEq( lastProgCall().a, 11, "selectcam carries entindex" )
texLast = "sentinel"
matLast = nil
dev:Paint( 0, 0, 800, 600 )
assertTrue( texLast == "sentinel", "RenderTarget userdata never passed to surface.SetTexture" )
assertTrue( matLast != nil, "camera image drawn through a material" )
assertTrue( matLast.basetexture == cam11.RenderTarget, "material $basetexture is the wiremod RenderTarget" )
assertTrue( texRect != nil and texRect.w > 400, "video drawn into the big pane" )

-- Switch to camera 12: 11 is unobserved (RT reference dropped by wiremod),
-- 12 observed but inactive -> NO SIGNAL, nothing drawn.
dev:SelectCam( 12 )
assertTrue( cam11.IsObserved == false, "previous camera unobserved on switch" )
assertTrue( cam11.RenderTarget == nil, "previous camera RT dropped by wiremod" )
assertTrue( cam12.IsObserved == true, "new camera observed" )
assertEq( dev.SelEnt, 12, "camera 12 selected" )
texLast = "sentinel"
matLast = nil
dev:Paint( 0, 0, 800, 600 )
assertTrue( texLast == "sentinel" and matLast == nil, "no signal drawn for inactive camera" )

-- Switching to another live camera re-points the SAME material at the new
-- camera RenderTarget (no new material, no new RenderTarget).
cam12:SetActive( true )
Now = 102
dev:Tick()
matLast = nil
texLast = "sentinel"
dev:Paint( 0, 0, 800, 600 )
assertTrue( matLast != nil, "material drawn for the newly active camera" )
assertTrue( matLast.basetexture == cam12.RenderTarget, "material re-pointed to the new camera RenderTarget on switch" )
assertEq( #createdMats, 1, "camera material created only once" )

-- Signal loss on the watched camera: wiremod unobserves on deactivate, our
-- Tick re-asserts observation, the next scan logs the transition.
dev:SelectCam( 11 )
cam11:SetActive( false )
assertTrue( cam11.IsObserved == false, "wiremod dropped observation on deactivate" )
Now = 103
dev:Tick()
assertTrue( cam11.IsObserved == true, "Tick re-observes the selected camera" )
assertTrue( hasAlert( dev, "Signal lost on camera #11" ), "signal lost alert logged" )
cam11:SetActive( true )
Now = 105
dev:Tick()
assertTrue( hasAlert( dev, "Signal restored on camera #11" ), "signal restored alert logged" )

-- Scan interval: Tick within 1s must not rescan.
local ls = dev.LastScan
Now = 105.5
dev:Tick()
assertEq( dev.LastScan, ls, "no rescan inside the interval" )

-- Repeated scans of already-known cameras must not create any new alerts.
local det0 = countNotifies( "detected" )
local rem0 = countNotifies( "removed" )
Now = 106
dev:ScanCameras()
Now = 106.4
dev:ScanCameras()
Now = 106.8
dev:ScanCameras()
assertEq( countNotifies( "detected" ), det0, "re-scan of known cameras creates no detected alerts" )
assertEq( countNotifies( "removed" ), rem0, "re-scan creates no removal alerts" )
assertEq( #dev.Listboxes.lstCams.Order, 2, "no duplicate list rows after repeated scans" )

-- Moving the camera or changing its FOV is not a new detection (identity is
-- the EntIndex, which does not change).
cam11:SetPos( { 999, 0, 0 } )
cam11:SetCamFOV( 45 )
Now = 107
dev:ScanCameras()
assertEq( countNotifies( "detected" ), det0, "moving the camera / FOV change is not a detection" )
assertTrue( dev.CamList[ 11 ] != nil, "camera 11 still known after move" )

-- Temporary loss of client visibility (PVS): missing from one scan, but within
-- the grace period it is NOT removed, and returning to view creates no alerts.
Ents[ 11 ] = nil
Now = 108
dev:Tick() -- scan runs (108 - 107 >= 1)
assertTrue( dev.CamList[ 11 ] != nil, "camera kept in list during grace period" )
assertEq( dev.SelEnt, 11, "selection kept during grace period" )
assertEq( countNotifies( "removed" ), rem0, "no false removal alert during grace" )
texLast = "sentinel"
matLast = nil
dev:Paint( 0, 0, 800, 600 )
assertTrue( texLast == "sentinel" and matLast == nil, "nothing drawn while camera is out of view" )
-- The camera re-enters the client view as a FRESH entity object with the same
-- EntIndex (exactly what happens on PVS re-entry).
local cam11b = MakeCam( 11, true, 80 )
Ents[ 11 ] = cam11b
Now = 109
dev:Tick()
assertTrue( dev.CamList[ 11 ] != nil, "camera still known after returning to view" )
assertEq( dev.SelEnt, 11, "selection kept after temporary PVS loss" )
assertEq( countNotifies( "detected" ), det0, "no false re-detection after temporary PVS loss" )
assertEq( countNotifies( "removed" ), rem0, "no false removal after temporary PVS loss" )
assertTrue( cam11b.IsObserved == true, "re-entered camera is observed again by Tick" )

-- Real removal: missing longer than the grace period -> removed alert once,
-- entry dropped, selection cleared, server notified.
Ents[ 11 ] = nil
Now = 110
dev:Tick() -- goneSince = 110
assertTrue( dev.CamList[ 11 ] != nil, "still within grace right after disappearance" )
Now = 114
dev:Tick() -- 114 - 110 = 4 >= GONE_GRACE(3)
assertTrue( dev.CamList[ 11 ] == nil, "camera dropped from list after grace" )
assertEq( dev.SelEnt, 0, "selection cleared after confirmed removal" )
assertEq( countNotifies( "removed" ), rem0 + 1, "removal alert logged exactly once" )
assertEq( lastProgCall().com, "selectcam" )
assertEq( lastProgCall().a, 0, "server told selection cleared" )
texLast = "sentinel"
matLast = nil
dev:Paint( 0, 0, 800, 600 )
assertTrue( texLast == "sentinel" and matLast == nil, "nothing drawn after camera removal" )

-- Re-creation after a confirmed removal: "detected" fires again.
local cam11c = MakeCam( 11, true, 80 )
Ents[ 11 ] = cam11c
Now = 115
dev:ScanCameras()
assertTrue( dev.CamList[ 11 ] != nil, "re-created camera listed again" )
assertEq( countNotifies( "detected" ), det0 + 1, "detected fires again after real removal + re-creation" )

-- Refresh button picks up a newly spawned camera.
local cam13 = MakeCam( 13, true, 90 )
Ents = { [11] = cam11c, [12] = cam12, [13] = cam13 }
dev:ButtonClick( "btnRefresh" )
assertTrue( dev.CamList[ 13 ] != nil, "refresh finds new camera" )

-- Selecting a camera that does not exist client-side: alert, no selection.
dev:SelectCam( 99 )
assertEq( dev.SelEnt, 0, "invalid camera not selected" )
assertTrue( hasAlert( dev, "Camera #99 unavailable" ), "invalid selection alert" )

-- Alarm + exit buttons still route to the server program.
dev:ButtonClick( "btnEnable" )
assertEq( lastProgCall().com, "enable", "enable alarm routed" )
dev:ButtonClick( "btnDisable" )
assertEq( lastProgCall().com, "disable", "disable alarm routed" )
dev:ButtonClick( "btnExit" )
assertEq( lastProgCall().com, "exit", "exit routed" )

-- Closing the window (Kill) releases the observed camera.
dev:SelectCam( 13 )
assertTrue( cam13.IsObserved == true, "camera 13 observed" )
dev:Kill()
assertTrue( cam13.IsObserved == false, "Kill unobserves the camera" )
assertTrue( cam13.RenderTarget == nil, "Kill leaves no RT reference" )
assertEq( dev.SelEnt, 0, "Kill clears selection" )

-- Alerts were also pushed through the HUD notification API.
assertTrue( #notifies > 0, "alerts also pushed to PCMod.Gui.Notify" )

-- CAMERA INFO panel shows only ID and Status - no FOV / Signal / Wiremod rows.
dev:SelectCam( 13 )
texts = {}
dev:Paint( 0, 0, 800, 600 )
local sawID, sawStatus = false, false
for _, t in ipairs( texts ) do
	assertTrue( string.sub( t, 1, 4 ) != "FOV:", "no FOV line in CAMERA INFO" )
	assertTrue( string.sub( t, 1, 7 ) != "Signal:", "no Signal line in CAMERA INFO" )
	assertTrue( string.sub( t, 1, 8 ) != "Wiremod:", "no Wiremod line in CAMERA INFO" )
	if (t == "ID: #13") then sawID = true end
	if (t == "Status: ONLINE") then sawStatus = true end
end
assertTrue( sawID, "CAMERA INFO still shows the camera ID" )
assertTrue( sawStatus, "CAMERA INFO still shows the status" )

-- Window-drag positioning regression: Paint must lay out every panel relative
-- to the CURRENT window rect (x,y,w,h), never to coordinates cached in
-- Initialize. Simulate drag frames by painting at different window positions
-- without re-running Initialize.
local function assertApprox( a, b, msg )
	if (math.abs( a - b ) > 0.001) then error( "FAILED: " .. msg .. " (got " .. tostring( a ) .. ", want " .. tostring( b ) .. ")", 2 ) end
end
local function paintAt( px, py, pw, ph )
	rects = {}
	dev:Paint( px, py, pw, ph )
	return rects
end
local function expectedView( px, py, pw, ph )
	local ch = ph * 0.06
	local cpy = py + ch + (ph * 0.02)
	return { x = px + (pw * 0.34), y = cpy, w = pw * 0.64, h = ph * 0.58 }
end
local positions = { { 0, 0, 800, 600 }, { 100, 50, 800, 600 }, { 400, 250, 800, 600 }, { 224, 300, 800, 600 } }
for _, pos in ipairs( positions ) do
	local px, py, pw, ph = pos[ 1 ], pos[ 2 ], pos[ 3 ], pos[ 4 ]
	-- what UpdateWindowDrag does on every drag frame: move the controls, then
	-- Paint is called with the new window rect (drag changes X/Y only)
	dev:TranslateWindow( px - dev.win_x, py - dev.win_y )
	local rs = paintAt( px, py, pw, ph )
	local vr = expectedView( px, py, pw, ph )
	local videoFound = false
	for _, r in ipairs( rs ) do
		assertTrue( r.x >= (px - 0.001) and ((r.x + r.w) <= (px + pw + 0.001)), "rect stays inside window horizontally at " .. px .. "," .. py )
		assertTrue( r.y >= (py - 0.001) and ((r.y + r.h) <= (py + ph + 0.001)), "rect stays inside window vertically at " .. px .. "," .. py )
		if ((r.w == vr.w) and (r.h == vr.h)) then
			assertApprox( r.x, vr.x, "video area X follows the window X" )
			assertApprox( r.y, vr.y, "video area Y follows the window Y" )
			videoFound = true
		end
	end
	assertTrue( videoFound, "video area drawn at the window position " .. px .. "," .. py )
end

-- After a server-side move (Int_Reinitialize at the new geometry, as happens
-- when the drag ends and win_move round-trips), the controls are rebuilt at
-- the new absolute position.
dev:Int_Reinitialize( 300, 200, 800, 600 )
assertApprox( dev.Listboxes.lstCams.X, 300 + (800 * 0.02), "listbox rebuilt at the new window X" )
assertApprox( dev.Elements.btnRefresh.X, 300 + (800 * 0.02), "refresh button rebuilt at the new window X" )
local wantBtnY = 200 + (600 * 0.06) + (600 * 0.02) + (600 * 0.58) + (600 * 0.02) + (600 * 0.16) + (600 * 0.02)
assertApprox( dev.Elements.btnEnable.Y, wantBtnY, "enable button rebuilt at the new window Y" )
assertApprox( dev.Elements.btnExit.X, 300 + 800 - (600 * 0.06), "exit button at the top-right of the new window" )

-- Resize gesture: Int_Reinitialize at a smaller geometry rebuilds the controls
-- and Paint keeps every rect inside the smaller window.
dev:Int_Reinitialize( 60, 30, 300, 260 )
local rs2 = paintAt( 60, 30, 300, 260 )
local vr2 = expectedView( 60, 30, 300, 260 )
local videoFound2 = false
for _, r in ipairs( rs2 ) do
	assertTrue( r.x >= (60 - 0.001) and ((r.x + r.w) <= (60 + 300 + 0.001)), "resized: rect inside window horizontally" )
	assertTrue( r.y >= (30 - 0.001) and ((r.y + r.h) <= (30 + 260 + 0.001)), "resized: rect inside window vertically" )
	if ((r.w == vr2.w) and (r.h == vr2.h)) then
		assertApprox( r.x, vr2.x, "resized: video area X follows the window" )
		assertApprox( r.y, vr2.y, "resized: video area Y follows the window" )
		videoFound2 = true
	end
end
assertTrue( videoFound2, "video area drawn inside the resized window" )

-- The camera material itself: created once, UnlitGeneric, white base texture.
assertEq( #createdMats, 1, "exactly one camera material created" )
assertEq( createdMats[ 1 ].name, "pcmod_alarmz_cam", "camera material name" )
assertEq( createdMats[ 1 ].shader, "UnlitGeneric", "camera material shader" )
assertEq( createdMats[ 1 ].params[ "$basetexture" ], "color/white", "camera material base texture" )

print( "ALL ALARMZ TESTS PASSED" )
