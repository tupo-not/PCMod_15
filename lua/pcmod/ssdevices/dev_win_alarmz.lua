

// PCMod ScreenSpace Device | AlarmZ - Wiremod camera surveillance monitor \\
//
// Shows the live image of Wiremod "Improved RT Camera" entities
// (gmod_wire_rt_camera). The image is NOT captured by PCMod: we only mark the
// selected camera as observed through the camera's own clientside method
// SetIsObserved(true), which makes Wiremod create the camera's RenderTarget
// and re-render it in its own PreRender hook. We then draw that RenderTarget
// texture through a material. When observation stops (camera switch / window
// close) we call SetIsObserved(false) and Wiremod drops the reference itself -
// PCMod never creates or destroys a RenderTarget.

DEV.Name = "window_alarmz"

DEV.LastTick = 0
DEV.LastFrame = 0

DEV.Th = "basic"

// Server-sent state
DEV.Al = 0
DEV.Cm = 0
DEV.SelCam = 0
DEV.Cams = {} -- camera entindexes linked to this PC (from sv_alarmz via program)

// Client-side monitor state (never part of the server payload, so it survives
// Rev bumps and window moves)
DEV.SelEnt = 0
DEV.SelEntValid = false
DEV.CamList = {}
DEV.PrevActive = {}
DEV.Alerts = {}
DEV.LastScan = -10
DEV.WireOK = false
DEV.LastRT = nil

local CAM_CLASS = "gmod_wire_rt_camera"
local SCAN_INTERVAL = 1.0
local ALERT_MAX = 6
// A camera missing from ONE ents.FindByClass result is not proof of removal -
// it may just have left the client's PVS (player or camera moved). Only a camera
// missing for this many seconds straight is declared removed.
local GONE_GRACE = 3.0

// Material used to draw the Wiremod camera image. surface.SetTexture only
// accepts numeric texture IDs, while cam.RenderTarget is an ITexture userdata,
// so the RT is bound through a material instead (the same mechanism
// gmod_wire_rt_screen uses with material:SetTexture). The material is created
// once and only re-pointed when the watched camera changes - PCMod never
// creates or destroys a RenderTarget itself.
local camMat = nil
local function GetCamMaterial()
	if (!camMat) then
		camMat = CreateMaterial( "pcmod_alarmz_cam", "UnlitGeneric", { ["$basetexture"] = "color/white" } )
	end
	return camMat
end

// ------------------------------------------------------------------------------------------------
// Wiremod helpers
// ------------------------------------------------------------------------------------------------

local function WireAvailable()
	return (WireLib != nil)
end

// Resolve an entity index to a live RT camera entity (nil when gone/wrong class)
function DEV:GetCam( idx )
	if ((!idx) || (idx == 0)) then return nil end
	local ent = ents.GetByIndex( idx )
	if (!IsValid( ent )) then return nil end
	if (ent.GetClass && (ent:GetClass() != CAM_CLASS)) then return nil end
	return ent
end

function DEV:CamLabel( idx, cam )
	local label = "Camera #" .. tostring( idx )
	if (cam && cam.GetActive) then
		if (cam:GetActive()) then
			label = label .. "  [ON]"
		else
			label = label .. "  [OFF]"
		end
	end
	return label
end

function DEV:AddAlert( msg, isErr )
	if (!istable( self.Alerts )) then self.Alerts = {} end
	table.insert( self.Alerts, { t = CurTime(), when = os.date( "%H:%M:%S" ), msg = msg, err = (isErr == true) } )
	while (#self.Alerts > ALERT_MAX) do table.remove( self.Alerts, 1 ) end
	if (PCMod.Gui && PCMod.Gui.Notify) then PCMod.Gui.Notify( msg, isErr ) end
end

// Scan the map for RT cameras (called from Tick on an interval, plus on demand
// from the Refresh button - never every frame).
//
// Camera identity is the EntIndex: moving a camera or changing its FOV / Active
// state never changes the index, so those never count as "new". A camera missing
// from one scan is only "temporarily out of view" (kept in the list, no alerts,
// selection kept); it is declared removed only after GONE_GRACE seconds of
// continuous absence, and a later re-appearance then alerts "detected" again.
function DEV:ScanCameras()
	self.LastScan = CurTime()
	if (!WireAvailable()) then
		if (self.WireOK) then self:AddAlert( "Wiremod not detected", true ) end
		self.WireOK = false
		self.CamList = {}
		self.PrevActive = {}
		self:RebuildCamList()
		return
	end
	self.WireOK = true
	if (!istable( self.CamList )) then self.CamList = {} end
	if (!istable( self.PrevActive )) then self.PrevActive = {} end

	local now = CurTime()
	local seen = {}
	local found = ents.FindByClass( CAM_CLASS )
	for _, ent in ipairs( found or {} ) do
		if (IsValid( ent )) then
			local idx = ent:EntIndex()
			seen[ idx ] = true
			local entry = self.CamList[ idx ]
			if (!entry) then
				// Newly seen camera. No "detected" notification - only real
				// events (connect/disconnect/errors, signal, removal) alert.
				self.CamList[ idx ] = { lastSeen = now, goneSince = nil }
			else
				// Already known camera: re-scan / move / FOV / Active changes
				// only refresh the entry - no alerts.
				entry.lastSeen = now
				entry.goneSince = nil
			end
			// Signal state transitions are checked once per scan, not per frame
			local active = false
			if (ent.GetActive) then active = (ent:GetActive() == true) end
			if ((self.PrevActive[ idx ] != nil) && (self.PrevActive[ idx ] != active)) then
				if (active) then
					self:AddAlert( "Signal restored on camera #" .. idx )
				else
					self:AddAlert( "Signal lost on camera #" .. idx, true )
				end
			end
			self.PrevActive[ idx ] = active
		end
	end

	// Cameras missing from this scan: remember when they first went missing and
	// declare them removed only after GONE_GRACE seconds continuously missing.
	for idx, entry in pairs( self.CamList ) do
		if (!seen[ idx ]) then
			if (!entry.goneSince) then entry.goneSince = now end
			if ((now - entry.goneSince) >= GONE_GRACE) then
				// Confirmed gone clientside. Drop the entry so a later
				// re-appearance (real re-creation) alerts "detected" again.
				self.CamList[ idx ] = nil
				self.PrevActive[ idx ] = nil
				self:AddAlert( "Camera #" .. idx .. " removed", true )
				if (idx == self.SelEnt) then
					self.SelEnt = 0
					self.SelEntValid = false
					self:RunProgCommand( "alarmz", "selectcam", 0 )
				end
			end
		end
	end

	self:RebuildCamList()
end

// The camera list shows ONLY cameras linked to this PC (server registry via
// DeviceData.Cams). Discovered-but-unlinked cameras are tracked in CamList for
// state/alerts but never listed.
function DEV:RebuildCamList()
	if ((!self.Listboxes) || (!self.Listboxes[ "lstCams" ])) then return end
	self:ClearListbox( "lstCams" )
	local idxs = {}
	for _, idx in ipairs( self.Cams or {} ) do
		if (self:GetCam( idx )) then table.insert( idxs, idx ) end
	end
	table.sort( idxs )
	for _, idx in ipairs( idxs ) do
		self:AddListboxItem( "lstCams", "cam_" .. idx, self:CamLabel( idx, self:GetCam( idx ) ) .. " [LINKED]" )
	end
	if (self.SelEnt != 0) then self:SetListboxSelRow( "lstCams", "cam_" .. self.SelEnt ) end
	// Auto-watch the first linked camera when nothing is selected
	if ((self.SelEnt == 0) && istable( self.Cams )) then
		for _, c in ipairs( self.Cams ) do
			if (self:GetCam( c )) then self:SelectCam( c ) break end
		end
	end
end

// How many linked cameras are currently visible clientside
function DEV:LinkedCount()
	local n = 0
	for _, idx in ipairs( self.Cams or {} ) do
		if (self:GetCam( idx )) then n = n + 1 end
	end
	return n
end

// Watch a camera: unobserve the previous one, observe the new one. The actual
// RenderTarget is created/dropped by Wiremod inside SetIsObserved.
function DEV:SelectCam( idx )
	idx = tonumber( idx ) or 0
	local prev = self:GetCam( self.SelEnt )
	if (prev && prev.SetIsObserved && prev.IsObserved) then
		prev:SetIsObserved( false )
	end
	self.SelEnt = 0
	self.SelEntValid = false
	local cam = self:GetCam( idx )
	if (cam) then
		self.SelEnt = idx
		self.SelEntValid = true
		if (cam.SetIsObserved) then cam:SetIsObserved( true ) end
		self:RunProgCommand( "alarmz", "selectcam", idx )
		if (self.Listboxes && self.Listboxes[ "lstCams" ]) then self:SetListboxSelRow( "lstCams", "cam_" .. idx ) end
	elseif (idx != 0) then
		self:AddAlert( "Camera #" .. idx .. " unavailable", true )
	end
end

// Release everything we hold on Wiremod cameras. No hooks/timers are used
// (all work happens in Tick), so dropping the observation is the whole cleanup.
function DEV:Cleanup()
	local cam = self:GetCam( self.SelEnt )
	if (cam && cam.SetIsObserved && cam.IsObserved) then cam:SetIsObserved( false ) end
	self.SelEnt = 0
	self.SelEntValid = false
end

function DEV:Kill()
	self:Cleanup()
end

// __P2__

// ------------------------------------------------------------------------------------------------
// Window layout
// ------------------------------------------------------------------------------------------------

function DEV:Initialize( x, y, w, h )
	local ch = h * 0.06

	// Title-bar close button
	self:CreateButton2( self.Th, "btnExit", (x+w)-ch, y, ch, ch, "X" )

	// Camera manager panel (left column): header, camera list, refresh button.
	// Only the CONTROLS are created here (elements live at absolute coords and
	// are moved by the base class TranslateWindow / Int_Reinitialize); the
	// panel rectangles themselves are recomputed from x,y,w,h in every Paint.
	local cp = { X = x+(w*0.02), Y = y+ch+(h*0.02), W = w*0.30, H = h*0.58 }
	local lb = self:CreateListbox( self.Th, "lstCams", cp.X, cp.Y+(h*0.05), cp.W, cp.H-(h*0.12) )
	lb.LeftAlign = true
	self:CreateButton2( self.Th, "btnRefresh", cp.X, cp.Y+cp.H-(h*0.06), cp.W, h*0.05, "Refresh" )

	// Info panel + alerts panel (bottom strip)
	local iy = cp.Y + cp.H + (h*0.02)
	local ih = h * 0.16

	// Alarm bar (very bottom)
	local by = iy + ih + (h*0.02)
	local bh = h * 0.08
	self:CreateButton2( self.Th, "btnEnable", x+(w*0.02), by, w*0.30, bh, "Enable Alarm" )
	self:CreateButton2( self.Th, "btnDisable", x+(w*0.34), by, w*0.30, bh, "Disable Alarm" )

	// Record window data
	self.WinX = x
	self.WinY = y
	self.WinW = w
	self.WinH = h

	// First camera scan right away (Tick re-scans on the interval)
	self.LastScan = 0
	self:ScanCameras()
end

// __P3__

// ------------------------------------------------------------------------------------------------
// Drawing
// ------------------------------------------------------------------------------------------------

function DEV:DrawPanel( p, title, c_bor, c_panel, c_dim )
	surface.SetDrawColor( c_panel.r, c_panel.g, c_panel.b, c_panel.a )
	surface.DrawRect( p.X, p.Y, p.W, p.H )
	surface.DrawOutline( p.X, p.Y, p.W, p.H, c_bor )
	if (title && (title != "")) then
		draw.SimpleText( title, "pcmod_3d2d", p.X+6, p.Y+4, c_dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
	end
end

function DEV:Paint( x, y, w, h )
	local ch = h * 0.06
	self:RenderWindow( self.Th, x, y, w, h, "AlarmZ - Camera Monitor", ch )

	local c_bor = PCMod.Gui.GetThemeColour( self.Th, "Border", Color( 64, 68, 76, 255 ) )
	local c_panel = PCMod.Gui.GetThemeColour( self.Th, "TextboxBG", Color( 28, 30, 35, 255 ) )
	local c_txt = PCMod.Gui.GetThemeColour( self.Th, "Textbox_Text", Color( 216, 220, 226, 255 ) )
	local c_dim = PCMod.Gui.GetThemeColour( self.Th, "Button_Text_Locked", Color( 122, 126, 134, 255 ) )
	local c_ok = Color( 60, 200, 90, 255 )
	local c_bad = Color( 220, 70, 60, 255 )

	surface.SetFont( "pcmod_3d2d" )
	local _, th = surface.GetTextSize( "X" )

	// All panel rectangles are computed from the CURRENT window rect on every
	// frame (never cached from Initialize): while the window is dragged, Paint
	// receives the updated x,y,w,h and the whole UI moves with the window in
	// sync with the control elements (moved by the base TranslateWindow).
	// --- camera manager panel ---
	local cp = { X = x+(w*0.02), Y = y+ch+(h*0.02), W = w*0.30, H = h*0.58 }
	self:DrawPanel( cp, "CAMERAS", c_bor, c_panel, c_dim )

	// --- video area ---
	local v = { X = x+(w*0.34), Y = cp.Y, W = w*0.64, H = cp.H }
	surface.SetDrawColor( 0, 0, 0, 255 )
	surface.DrawRect( v.X, v.Y, v.W, v.H )
	surface.DrawOutline( v.X, v.Y, v.W, v.H, c_bor )

	local cam = self:GetCam( self.SelEnt )
	local rt = nil
	local active = false
	if (cam) then
		if (cam.GetActive) then active = (cam:GetActive() == true) end
		if (cam.RenderTarget) then rt = cam.RenderTarget end
	end

	local statusTxt = ""
	local statusCol = c_dim
	if (!self.WireOK) then
		statusTxt = "WIREMOD NOT DETECTED"
		statusCol = c_bad
	elseif (self.SelEnt == 0) then
		if (self:LinkedCount() == 0) then
			statusTxt = "NO CAMERAS FOUND"
		else
			statusTxt = "SELECT A CAMERA"
		end
	elseif (!cam) then
		statusTxt = "CAMERA #" .. self.SelEnt .. " UNAVAILABLE"
		statusCol = c_bad
	elseif ((!active) || (!rt)) then
		statusTxt = "NO SIGNAL"
		statusCol = c_bad
	else
		// Live image: this RenderTarget belongs to the Wiremod camera entity
		// and is re-rendered by Wiremod's own PreRender hook while we observe it.
		// surface.SetTexture needs a numeric texture ID, so bind the RT texture
		// through a material and draw with surface.SetMaterial instead.
		local mat = GetCamMaterial()
		if (rt != self.LastRT) then
			mat:SetTexture( "$basetexture", rt )
			self.LastRT = rt
		end
		surface.SetMaterial( mat )
		surface.SetDrawColor( 255, 255, 255, 255 )
		surface.DrawTexturedRect( v.X, v.Y, v.W, v.H )
		statusTxt = "CAM #" .. self.SelEnt .. " - LIVE"
		statusCol = c_ok
	end
	draw.SimpleText( statusTxt, "pcmod_3d2d", v.X+6, v.Y+4, statusCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )

	// --- camera info panel ---
	// Only ID and Status are shown here. FOV / Signal / Wiremod stay internal
	// (active + rt still drive the video area and its status overlay above).
	local iy = cp.Y + cp.H + (h*0.02)
	local ih = h * 0.16
	local ip = { X = x+(w*0.02), Y = iy, W = w*0.47, H = ih }
	self:DrawPanel( ip, "CAMERA INFO", c_bor, c_panel, c_dim )
	local lines = {}
	if (cam) then
		table.insert( lines, "ID: #" .. self.SelEnt )
		if (active) then table.insert( lines, "Status: ONLINE" ) else table.insert( lines, "Status: OFFLINE" ) end
	else
		if (self.SelEnt != 0) then table.insert( lines, "ID: #" .. self.SelEnt ) else table.insert( lines, "ID: none" ) end
		table.insert( lines, "Status: -" )
	end
	local lyy = ip.Y + 4 + th
	for _, ln in ipairs( lines ) do
		draw.SimpleText( ln, "pcmod_3d2d", ip.X+6, lyy, c_txt, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
		lyy = lyy + th
		if (lyy > (ip.Y + ip.H)) then break end
	end

	// --- alerts panel ---
	local ap = { X = x+(w*0.51), Y = ip.Y, W = w*0.47, H = ip.H }
	self:DrawPanel( ap, "ALERTS", c_bor, c_panel, c_dim )
	local alerts = self.Alerts or {}
	local ayy = ap.Y + 4 + th
	for _, a in ipairs( alerts ) do
		local acol = c_txt
		if (a.err) then acol = c_bad end
		draw.SimpleText( a.when .. "  " .. a.msg, "pcmod_3d2d", ap.X+6, ayy, acol, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
		ayy = ayy + th
		if (ayy > (ap.Y + ap.H)) then break end
	end

	// --- alarm status ---
	local ab = { X = x+(w*0.66), Y = ip.Y+ip.H+(h*0.02), W = w*0.32, H = h*0.08 }
	self:DrawPanel( ab, "", c_bor, c_panel, c_dim )
	if (self.Al == 1) then
		draw.SimpleText( "ALARM: ACTIVE", "pcmod_3d2d", ab.X+(ab.W*0.5), ab.Y+(ab.H*0.5), c_bad, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
	else
		draw.SimpleText( "ALARM: INACTIVE", "pcmod_3d2d", ab.X+(ab.W*0.5), ab.Y+(ab.H*0.5), c_ok, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
	end

	// Draw the listbox and the buttons on top
	self:Draw()
end

// ------------------------------------------------------------------------------------------------
// Input
// ------------------------------------------------------------------------------------------------

function DEV:ButtonClick( btn )
	if (btn == "btnExit") then
		self:RunProgCommand( "alarmz", "exit" )
		return
	end
	if (btn == "btnRefresh") then
		self.LastScan = 0
		self:ScanCameras()
		return
	end
	if (btn == "btnEnable") then
		self:RunProgCommand( "alarmz", "enable" )
		return
	end
	if (btn == "btnDisable") then
		self:RunProgCommand( "alarmz", "disable" )
		return
	end
end

function DEV:ListboxSelect( lbname, option, right, x, y )
	if (lbname != "lstCams") then return end
	if ((!option) || (option == "")) then return end
	local idx = tonumber( string.sub( option, 5 ) )
	if (!idx) then return end
	self:SelectCam( idx )
end

function DEV:DoClick( x, y, right )
	self:ProcessClick( x, y, right )
end

function DEV:Tick()
	self.LastTick = CurTime()
	self.LastFrame = PCMod.SDraw.CFrame
	if ((CurTime() - (self.LastScan or 0)) >= SCAN_INTERVAL) then self:ScanCameras() end
	// A camera that is no longer linked to this PC stops being watched at once
	// (checked every frame, not only on scan) - otherwise the video would keep
	// playing after a disconnect until something else was selected.
	if ((self.SelEnt != 0) && istable( self.Cams ) && (!table.HasValue( self.Cams, self.SelEnt ))) then
		local old = self:GetCam( self.SelEnt )
		if (old && old.SetIsObserved && old.IsObserved) then old:SetIsObserved( false ) end
		self.SelEnt = 0
		self.SelEntValid = false
		self:RunProgCommand( "alarmz", "selectcam", 0 )
	end
	// Keep the selected camera observed: Wiremod itself drops the observation
	// when a camera is switched off, so re-assert it here (SetIsObserved is
	// idempotent and only creates the RT while it is not observed yet).
	local cam = self:GetCam( self.SelEnt )
	if (cam) then
		self.SelEntValid = true
		if (cam.SetIsObserved && (cam.IsObserved != true)) then cam:SetIsObserved( true ) end
	else
		self.SelEntValid = false
	end
end

function DEV:KeyPress( key, txt )
	self:KeyPressTextboxes( key, txt )
end
