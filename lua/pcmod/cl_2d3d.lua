
// ---------------------------------------------------------------------------------------------------------
// cl_2d3d.lua - Revision 1
// Client-Side
// Controls the 2D 3D Drawing operations
// ---------------------------------------------------------------------------------------------------------

// ---------------------------------------------------------------------------------------------------------
// Define our library
// ---------------------------------------------------------------------------------------------------------

PCMod.SDraw = {}
PCMod.SDraw.Version = "1.0"
PCMod.SDraw.Configs = {}
PCMod.SDraw.SSpaces = {}
PCMod.SDraw.Devices = {}
PCMod.SDraw.DevMap = {}
PCMod.SDraw.OldData = {}
PCMod.SDraw.DMap = {}

PCMod.SDraw.KeyboardEntID = 0
PCMod.SDraw.DrawKeyboard = false
PCMod.SDraw.KB_Shift = false
PCMod.SDraw.KB_UnShift = false
PCMod.SDraw.KB_Caps = false

PCMod.SDraw.DevFocus = ""

PCMod.SDraw.CFrame = 0

// Fullscreen UI transform (GUI scale). Geometry is drawn into a scaled,
// centred virtual screen; CalcCursor() applies the inverse so hit-testing and
// the on-screen windows stay aligned.
PCMod.SDraw.UIScale = 1
PCMod.SDraw.WindowScale = 1
PCMod.SDraw.UIOffX = 0
PCMod.SDraw.UIOffY = 0
PCMod.SDraw.LastMouseDown = false

PCMod.SDraw.DevParams = {}

PCMod.Msg( "2D 3D ScreenDraw Library Loaded (V" .. PCMod.SDraw.Version .. ")", true )


// ---------------------------------------------------------------------------------------------------------
// Load all our SS devices
// ---------------------------------------------------------------------------------------------------------

function PCMod.LoadSSDevice( id )
	DEV = {}
	if (id == "base") then
		include( "pcmod/ssdevices/base.lua" )
		PCMod.SDraw.Devices[ "base" ] = table.Copy( DEV )
		PCMod.Msg( "Loaded base device!", true )
		return
	end
	local fn = "pcmod/ssdevices/" ..id
	DEV.FileName = fn
	table.Merge( DEV, PCMod.SDraw.Devices[ "base" ] )
	include( fn )
	PCMod.SDraw.Devices[ DEV.Name ] = table.Copy( DEV )
	PCMod.Msg( "Device '" .. DEV.Name .. "' loaded!", true )
end

function PCMod.LoadAllDevices()
	local ssds = file.Find( "pcmod/ssdevices/dev_*", "LUA")
	if ((!ssds) || (#ssds == 0)) then
		PCMod.Warning( "No ScreenSpace devices to load!" )
	else
		DEV = {}
		PCMod.LoadSSDevice( "base" )
		for _, v in pairs( ssds ) do
			DEV = {}
			PCMod.LoadSSDevice( v )
		end
	end
	DEV = nil
end

PCMod.LoadAllDevices()

concommand.Add( "pc_ssd_reload", function( pl, com, args )
	// SECURITY (stage 3, fix 2.5): validate the argument before include().
	// Note: the plan's "^[%w_]+$" would reject the real input ("dev_allprogs.lua",
	// "base") - the same "%.lua" scheme as pc_prog_reload keeps working usage intact.
	local id = args[1]
	if (!id) then return end
	if (id != "base" && !string.match( id, "^[%w_]+%.lua$")) then return end
	if (id != "base" && !file.Exists( "pcmod/ssdevices/" .. id, "LUA" )) then return end
	PCMod.LoadSSDevice( id )
end )
concommand.Add( "pc_ssd_reloadall", function() PCMod.LoadAllDevices(); end )


// ---------------------------------------------------------------------------------------------------------
// Define all the screen configs
// ---------------------------------------------------------------------------------------------------------

// Old CRT
local sc = {}
	// For Reference:
	sc.ScreenModel = "models/props_lab/monitor01a.mdl"
	
	// For 3D 2D Drawing:
	sc.OffsetForward = 12.4
	sc.OffsetUp = 2.95
	sc.OffsetRight = -2.4
	sc.Resolution = 0.04
	sc.Rotation = Vector( 4.5, 0, 0 )
	
	// For Screen Drawing:
	sc.RX = -302
	sc.RY = -218
	sc.RW = 480
	sc.RH = 393
	
	// For Cursor Position Calculation:
	sc.x1 = -9
	sc.x2 = 9
	sc.y1 = 12.5
	sc.y2 = -4
	sc.z = 6.4
	sc.fov = 70
	
	// For Camera Lock Positioning:
	sc.UpAdjust = 0
	sc.RightAdjust = 0
	sc.ForwardAdjust = 1
	
PCMod.SDraw.Configs[ sc.ScreenModel ] = sc

// New LCD
sc = {}
	// For Reference:
	sc.ScreenModel = "models/props/cs_office/computer_monitor.mdl"
	
	// For 3D 2D Drawing:
	sc.OffsetForward = 3.25
	sc.OffsetUp = 15.85
	sc.OffsetRight = -2.2
	sc.Resolution = 0.0425
	sc.Rotation = Vector( 0, 0, 0 )
	
	// For Screen Drawing:
	sc.RX = -296
	sc.RY = -205
	sc.RW = 487
	sc.RH = 368
	
	// For Cursor Position Calculation:
	sc.x1 = -10.5
	sc.x2 = 10.5
	sc.y1 = 24.7
	sc.y2 = 8.6
	sc.z = 3.33
	sc.fov = 70
	
	// For Camera Lock Positioning:
	sc.UpAdjust = 13
	sc.RightAdjust = 0
	sc.ForwardAdjust = -6.5
	
PCMod.SDraw.Configs[ sc.ScreenModel ] = sc

// Darksunrise's model
local sc = {}

	sc.ScreenModel = "models/darksunrise/monitor01.mdl"

	// For 3D 2D Drawing:
	sc.OffsetForward = 3.25
	sc.OffsetUp = -2.24
	sc.OffsetRight = -15.8
	sc.Resolution = 0.0425
	sc.Rotation = Vector( 180, 90, 180 )

	// For Screen Drawing:
	sc.RX = -296
	sc.RY = -205
	sc.RW = 487
	sc.RH = 368

	// For Cursor Position Calculation:
	sc.x1 = 9
	sc.x2 = 24
	sc.y1 = 10
	sc.y2 = -6
	sc.z = 6
	sc.fov = 70

	// For Camera Lock Positioning:
	sc.UpAdjust = 0
	sc.RightAdjust = -17
	sc.ForwardAdjust = -8

PCMod.SDraw.Configs[ sc.ScreenModel ] = table.Copy( sc )

// New LCD
sc = {}
	// For Reference:
	sc.ScreenModel = "models/pcmod/eeepc.mdl"
	
	// For 3D 2D Drawing:
	sc.OffsetForward = -9.84
	sc.OffsetUp = 10
	sc.OffsetRight = -2.2
	sc.Resolution = 0.0425
	sc.Rotation = Vector( 11, 0, 0 )
	
	// For Screen Drawing:
	sc.RX = -317
	sc.RY = -205
	sc.RW = 530
	sc.RH = 368
	
	// For Cursor Position Calculation:
	sc.x1 = -11.5
	sc.x2 = 11.5
	sc.y1 = 18.5
	sc.y2 = 3
	sc.z = 3.33
	sc.fov = 70
	
	// For Camera Lock Positioning:
	sc.UpAdjust = 6.8
	sc.RightAdjust = 0
	sc.ForwardAdjust = -22.5
	
PCMod.SDraw.Configs[ sc.ScreenModel ] = sc

// ---------------------------------------------------------------------------------------------------------
// SetDevParam - Sets a device parameter
// ---------------------------------------------------------------------------------------------------------
function PCMod.SetDevParam( um )
	local entid = um:ReadShort()
	local device = um:ReadString()
	local index = um:ReadShort()
	local type = um:ReadString()
	local value = nil
	if (type == "bool") then
		value = um:ReadBool()
	elseif (type == "string") then
		value = um:ReadString()
	elseif (type == "int") then
		value = um:ReadShort()
	elseif (type == "float") then
		value = um:ReadFloat()
	elseif (type == "entity") then
		value = um:ReadEntity()
	end
	// Round 34 (M-10): the whole table of the entity was wiped by every
	// message - the parameters of the other devices were lost.
	if (!PCMod.SDraw.DevParams[ entid ]) then PCMod.SDraw.DevParams[ entid ] = {} end
	if (!PCMod.SDraw.DevParams[ entid ][ device ]) then PCMod.SDraw.DevParams[ entid ][ device ] = {} end
	PCMod.SDraw.DevParams[ entid ][ device ][ index ] = value
end
usermessage.Hook( "pcmod_setdevparam", PCMod.SetDevParam )

// ---------------------------------------------------------------------------------------------------------
// Add some dev adjustment commands
// ---------------------------------------------------------------------------------------------------------
function PCMod.SDraw.SetScreenConfig( ply, com, args )
	if (!args[1]) then
		PCMod.Msg( "Invalid screen id!" )
		return
	end
	local mdl_id = tonumber( args[1] )
	local mdl = ""
	if (mdl_id == 1) then mdl = "models/props_lab/monitor01a.mdl" end
	if (mdl_id == 2) then mdl = "models/props/cs_office/computer_monitor.mdl" end
	if (mdl_id == 3) then mdl = "models/darksunrise/monitor01.mdl" end
	if (mdl_id == 4) then mdl = "models/pcmod/eeepc.mdl" end
	if (mdl == "") then
		PCMod.Msg( "Invalid screen id!" )
		return
	end
	if (!args[2]) then
		PCMod.Msg( "Invalid setting!" )
		return
	end
	local setting = tostring( args[2] )
	local set = PCMod.SDraw.Configs[ mdl ][ setting ]
	if (!set) then
		PCMod.Msg( setting .. ": Nil" )
		return
	end
	if (!args[3]) then
		PCMod.Msg( setting .. ": " .. set )
		return
	end
	local value = tonumber( args[3] )
	if (!value) then return end
	// Round 34 (M-46): the type of the new value has to be the type of the
	// old one - a number where a Vector was expected raised an error in
	// EVERY frame.
	if (type( set ) != type( value ) ) then
		PCMod.Msg( setting .. ": wrong type (" .. type( set ) .. ")" )
		return
	end
	PCMod.SDraw.Configs[ mdl ][ setting ] = value
end
concommand.Add( "pc_ssc", PCMod.SDraw.SetScreenConfig )


// ---------------------------------------------------------------------------------------------------------
// Add a data dumping command
// ---------------------------------------------------------------------------------------------------------
function PCMod.SDraw.DumpScreenConfig( ply, com, args )
	if (!args[1]) then
		PCMod.Msg( "Invalid screen id!" )
		return
	end
	local mdl_id = tonumber( args[1] )
	local mdl = ""
	if (mdl_id == 1) then mdl = "models/props_lab/monitor01a.mdl" end
	if (mdl_id == 2) then mdl = "models/props/cs_office/computer_monitor.mdl" end
	if (mdl_id == 3) then mdl = "models/darksunrise/monitor01.mdl" end
	if (mdl_id == 4) then mdl = "models/pcmod/eeepc.mdl" end	
	if (mdl == "") then
		PCMod.Msg( "Invalid screen id!" )
		return
	end
	local cfg = PCMod.SDraw.Configs[ mdl ]
	local txt = PCMod.TableToString( cfg )
	local pth = PCMod.Cfg.DataFolderRoot .. PCMod.Cfg.DumpPath .. tostring( mdl_id ) .. "_config.txt"
	file.Write( pth, txt )
	PCMod.Msg( "Screen config dumped!" )
end
concommand.Add( "pc_ssc_dump", PCMod.SDraw.DumpScreenConfig )


// ---------------------------------------------------------------------------------------------------------
// GarbageCollect - Destroys all stored devices that are 2 or more frames old
// ---------------------------------------------------------------------------------------------------------
function PCMod.SDraw.GarbageCollect()
	PCMod.SDraw.CFrame = PCMod.SDraw.CFrame + 1
	for k, v in pairs( PCMod.SDraw.DevMap ) do
		if ((v.LastFrame < (PCMod.SDraw.CFrame-2)) && (!v.NoGarbage)) then
			PCMod.SDraw.DevMap[ k ]:Kill()
			PCMod.SDraw.DevMap[ k ] = nil
			PCMod.Msg( "Garbage collected '" .. k .. "'", true )
		end
	end
end
hook.Add( "Think", "PCMod.SDraw.GarbageCollect", PCMod.SDraw.GarbageCollect )


// ---------------------------------------------------------------------------------------------------------
// GUI scale / fullscreen screen helpers
// ---------------------------------------------------------------------------------------------------------
function PCMod.SDraw.GetGuiScale()
	local scale = 1
	if (PCMod.Cfg && (PCMod.Cfg.GuiScale != nil)) then
		scale = tonumber( PCMod.Cfg.GuiScale ) or 1
	end
	if (scale < 0.25) then scale = 0.25 end
	if (scale > 3) then scale = 3 end
	return scale
end

// Destroy the client-side device instances for one entity (or all) so the next
// draw re-initializes their layout at the current screen size / font scale.
function PCMod.SDraw.ResetDevices( entid )
	local prefix = nil
	if (entid) then prefix = tostring( entid ) .. ":" end
	for k, v in pairs( PCMod.SDraw.DevMap ) do
		if ((!prefix) || (string.sub( k, 1, string.len( prefix ) ) == prefix)) then
			if (v && v.Kill) then v:Kill() end
			PCMod.SDraw.DevMap[ k ] = nil
			PCMod.SDraw.DMap[ k ] = nil
		end
	end
end

// Rebuild every live device at its current pixel rectangle. Unlike
// ResetDevices(), the instances (and their local text edits) are kept; this is
// used for GUI-scale changes so unsaved text is not lost.
function PCMod.SDraw.RebuildDevices()
	for _, v in pairs( PCMod.SDraw.DevMap ) do
		if ((v) && (v.Int_Reinitialize) && (v.win_w or 0) > 0 && (v.win_h or 0) > 0) then
			v:Int_Reinitialize( v.win_x, v.win_y, v.win_w, v.win_h )
		end
	end
end

// Enter/leave fullscreen screen UI. The UI is drawn at native resolution in
// HUDPaint, so the font is scaled by the screen height to keep its relative
// size; entering/leaving rebuilds the entity's devices at the new size.
function PCMod.SDraw.SetFullscreenUI( on, entid )
	on = (on == true)
	if (PCMod.SDraw.Fullscreen == on) then
		if (on) then PCMod.SDraw.RebuildDevices() end
		return
	end
	PCMod.SDraw.Fullscreen = on
	if (PCMod.Gui && PCMod.Gui.InitFonts) then PCMod.Gui.InitFonts() end
	if (on) then
		PCMod.SDraw.FS_W = ScrW()
		PCMod.SDraw.FS_H = ScrH()
	else
		PCMod.SDraw.LastMouseDown = false
		PCMod.SDraw.GrabActive = false
		PCMod.SDraw.SuppressClicksUntil = 0
		PCMod.SDraw.UIScale = 1
		PCMod.SDraw.WindowScale = 1
		PCMod.SDraw.UIOffX = 0
		PCMod.SDraw.UIOffY = 0
	end
	PCMod.SDraw.RebuildDevices()
end

function PCMod.SDraw.DrawCursorAt( ax, ay )
	surface.SetDrawColor( 255, 255, 255, 255 )
	surface.DrawLine( ax, ay, ax+6, ay+6 )
	surface.DrawLine( ax-2, ay-2, ax+3, ay-2 )
	surface.DrawLine( ax-3, ay+3, ax+3, ay-3 )
	surface.DrawLine( ax-2, ay-2, ax-2, ay+3 )
	surface.SetDrawColor( 0, 0, 0, 255 )
	surface.DrawLine( ax-3, ay-3, ax+4, ay-3 )
	surface.DrawLine( ax-3, ay-3, ax-3, ay+4 )
	surface.DrawLine( ax-3, ay+4, ax+4, ay-3 )
	surface.DrawLine( ax, ay+1, ax+5, ay+6 )
	surface.DrawLine( ax+1, ay, ax+6, ay+5 )
	surface.SetDrawColor( 255, 255, 255, 255 )
end

// Device-picker helper: the topmost device whose drawn rectangle contains the
// point. Hit-testing must use this instead of merely walking the draggable
// devices, otherwise a lower window's title bar hidden under another window
// could still be grabbed.
function PCMod.SDraw.GetTopDeviceAt( ss, mx, my, w, h )
	if ((!ss) || (!istable( ss ))) then return nil end
	w = w or ScrW()
	h = h or ScrH()
	local best = nil
	local bestp = -1
	for _, v in pairs( ss ) do
		if ((type( v ) == "table") && v.DevID && v.W && v.H && (v.W > 0) && (v.H > 0)) then
			local dx, dy, dw, dh = PCMod.SDraw.GetDeviceVisualRect( v, w, h )
			if ((mx >= dx) && (mx <= (dx + dw)) && (my >= dy) && (my <= (dy + dh))) then
				local p = v.Priority or 0
				if (p >= bestp) then
					bestp = p
					best = v
				end
			end
		end
	end
	return best
end

// Starts a window grab on the topmost matching device at the moment the left
// mouse button goes down. GMod's DButton clicks fire on release, so polling the
// press edge here is what makes dragging/resizing work at all.
function PCMod.SDraw.UpdateWindowGrab( ss, mx, my )
	local down = false
	if (input && input.IsMouseDown) then down = input.IsMouseDown( MOUSE_LEFT ) end
	local pressed = (down && (!PCMod.SDraw.LastMouseDown))
	PCMod.SDraw.LastMouseDown = down
	if (!pressed) then return end
	if ((!ss) || (!istable( ss ))) then return end

	// Only the window actually on top may start a grab. If the topmost device
	// at this point is not draggable (or is a system screen/menu), the press
	// must not reach a window buried underneath it.
	local top = PCMod.SDraw.GetTopDeviceAt( ss, mx, my, ScrW(), ScrH() )
	if ((!top) || (!(top.WindowDrag || top.WindowResize))) then return end
	local dev = PCMod.SDraw.DevMap[ top.DevID ]
	if (dev && dev.TryStartWindowGrab && dev:TryStartWindowGrab( mx, my )) then return end
end

// Draws the locked screen across the whole viewport (replaces the 3D monitor
// close-up). Input is mapped directly to mouse coordinates by CalcCursor.
function PCMod.SDraw.DrawFullscreen()
	if (!PCMod.Gui || !PCMod.Gui.CamLocked) then return end
	local entid = PCMod.Gui.CamLockID
	local ent = ents.GetByIndex( entid )
	if ((!ent) || (!ent:IsValid()) || (!ent.IsScreen)) then return end

	// Paint the whole viewport black first, so a missing/stale screenspace
	// never flashes the 3D world through while the screen is locked.
	local w, h = ScrW(), ScrH()
	surface.SetDrawColor( 0, 0, 0, 255 )
	surface.DrawRect( 0, 0, w, h )

	local ss = PCMod.SDraw.SSpaces[ entid ]
	if ((!ss) || (!istable( ss ))) then return end

	// Standard clientside background device.
	if (!ss[ "cl_bg" ]) then
		ss[ "cl_bg" ] = {
			Priority = 0,
			X = 0,
			Y = 0,
			W = 1,
			H = 1,
			Type = "background",
			NoGarbage = true
		}
	end

	if ((PCMod.SDraw.FS_W != w) || (PCMod.SDraw.FS_H != h)) then
		PCMod.SDraw.FS_W = w
		PCMod.SDraw.FS_H = h
		PCMod.SDraw.RebuildDevices()
		if (PCMod.Gui && PCMod.Gui.InitFonts) then PCMod.Gui.InitFonts() end
	end

	// Cache the cursor in the same native coordinate space the devices use.
	local mx, my = gui.MouseX(), gui.MouseY()
	if (!PCMod.SDraw.Cursor) then PCMod.SDraw.Cursor = {} end
	PCMod.SDraw.Cursor.X = mx
	PCMod.SDraw.Cursor.Y = my
	PCMod.SDraw.Cursor.Ent = entid
	PCMod.SDraw.Cursor.Frame = PCMod.SDraw.CFrame

	// GUI scale: windows and their controls are scaled around their own
	// top-left; the desktop/taskbar stays fullscreen. This changes the actual
	// element sizes instead of zooming/letterboxing the whole picture.
	local sc = PCMod.SDraw.GetGuiScale()
	PCMod.SDraw.UIScale = sc
	PCMod.SDraw.WindowScale = sc
	PCMod.SDraw.UIOffX = 0
	PCMod.SDraw.UIOffY = 0

	// Start a title-bar drag or corner resize on the actual mouse press (GMod
	// button clicks only fire on release, which is too late for dragging).
	PCMod.SDraw.UpdateWindowGrab( ss, mx, my )

	PCMod.SDraw.DrawSpace( ss, 0, 0, w, h, entid )
	PCMod.SDraw.DrawCursorAt( mx, my )
	// Do not stamp ss.SC here: DrawSpace iterates every key in ss and expects
	// device tables, so a boolean marker would crash the next frame.
end
hook.Add( "HUDPaint", "PCMod.SDraw.Fullscreen", PCMod.SDraw.DrawFullscreen )

// Hide the stock game HUD while a screen is fullscreen.
hook.Add( "HUDShouldDraw", "PCMod.SDraw.FullscreenHUD", function( name )
	if (PCMod.Gui && PCMod.Gui.CamLocked) then
		if ((name == "CHudCrosshair") || (name == "CHudHealth") || (name == "CHudBattery") || (name == "CHudAmmo") || (name == "CHudSecondaryAmmo") || (name == "CHudWeaponSelection")) then
			return false
		end
	end
end )

concommand.Add( "pc_guiscale", function( ply, cmd, args )
	local n = tonumber( args[1] )
	if (!n) then
		PCMod.Notice( "PCMod GUI scale: " .. tostring( PCMod.SDraw.GetGuiScale() ) )
		return
	end
	PCMod.Cfg.GuiScale = n
	if (PCMod.Gui && PCMod.Gui.InitFonts) then PCMod.Gui.InitFonts() end
	PCMod.SDraw.RebuildDevices()
end )


// ---------------------------------------------------------------------------------------------------------
// DrawScreen - Draws the screen of a PC entity
// ---------------------------------------------------------------------------------------------------------
function PCMod.SDraw.DrawScreen( ent, cursor )
	// Validate Entity
	if ((!ent) || (!ent:IsValid())) then return end
	
	// Check it's a screen
	if (!ent.IsScreen) then return end

	// While locked, this screen is drawn fullscreen by DrawFullscreen() in
	// HUDPaint, at native resolution (no 3D monitor close-up).
	if (PCMod.Gui && PCMod.Gui.CamLocked && (PCMod.Gui.CamLockID == ent:EntIndex())) then return end
	
	// Check its distance from the player
	local dist = (LocalPlayer():GetPos()-ent:GetPos()):Length()
	if (dist > PCMod.Cfg.SightRange) then return end
	
	// Retrieve it's screenspace, validate it
	local ss = PCMod.SDraw.SSpaces[ ent:EntIndex() ]
	if (!ss) then
		PCMod.Msg( "Entity (" .. tostring( ent:EntIndex() ) .. ") has no screenspace!", true )
		PCMod.SDraw.SSpaces[ ent:EntIndex() ] = {}
		return
	end
	
	// Check if we have any 'sneaky' variables
	if ((ss.SC) && (ss.SC==true)) then
		cursor = true
	end
	ss.SC = nil
	
	// Add the standard clientside devices if they dont exist
	// Round 19 (AUDIT2 A-04): allocate once per screenspace instead of every
	// frame - every value is constant (the background resolves its colours at
	// paint time), which is what the original comment promised anyway.
	if (!ss["cl_bg"]) then
		ss["cl_bg"] = {
			Priority = 0,
			X = 0,
			Y = 0,
			W = 1,
			H = 1,
			Type = "background",
			NoGarbage = true
		}
	end
	
	// Retrieve the screen config, validate it
	local sc = PCMod.SDraw.Configs[ ent:GetModel() ]
	if (!sc) then
		PCMod.Msg( "Entity (" .. tostring( ent:EntIndex() ) .. ") has no screen configuration!", true )
		return
	end
	
	// Get the entity angles & pos
	local ang = ent:GetAngles()
	local rot = Vector(-90,90,0) + sc.Rotation
	ang:RotateAroundAxis(ang:Right(), 	rot.x)
	ang:RotateAroundAxis(ang:Up(), 		rot.y)
	ang:RotateAroundAxis(ang:Forward(), rot.z)
	local pos = ent:GetPos() + (ent:GetForward() * sc.OffsetForward) + (ent:GetUp() * sc.OffsetUp) + (ent:GetRight() * sc.OffsetRight)
	
	// Start the 3D 2D
	cam.Start3D2D( pos, ang, sc.Resolution )
		
	// Get drawing coords
	local x = sc.RX
	local y = sc.RY
	local w = sc.RW
	local h = sc.RH
	
	// PCMOD15 E4a: compute and cache the cursor BEFORE DrawSpace so
	// element Paint hooks can resolve hover state. Same condition as
	// the cursor draw below (zero extra traces when not interacting);
	// the cache is a fixed table (no per-frame allocation), stamped
	// with CFrame so stale frames read as "no hover".
	local cur_x, cur_y
	if (cursor) then
		local ccx, ccy = PCMod.SDraw.CalcCursor( ent, sc.fov )
		if (!PCMod.SDraw.Cursor) then PCMod.SDraw.Cursor = {} end
		PCMod.SDraw.Cursor.X = x+(ccx*w)
		PCMod.SDraw.Cursor.Y = y+(ccy*h)
		PCMod.SDraw.Cursor.Ent = ent:EntIndex()
		PCMod.SDraw.Cursor.Frame = PCMod.SDraw.CFrame
		cur_x = x+(ccx*w)
		cur_y = y+(ccy*h)
	end
	
	// Draw the screen space
	// 3D monitor drawing keeps the unscaled coordinate system.
	PCMod.SDraw.UIScale = 1
	PCMod.SDraw.WindowScale = 1
	PCMod.SDraw.UIOffX = 0
	PCMod.SDraw.UIOffY = 0

	PCMod.SDraw.DrawSpace( ss, x, y, w, h, ent:EntIndex() )
	
	// If we are drawing the cursor, then...
	if (cursor) then
	
		// PCMOD15 E4a: reuse the cursor computed above (no second trace)
		local ax = cur_x
		local ay = cur_y
		
		// Draw it
		surface.SetDrawColor( 255, 255, 255, 255 )
		// surface.DrawRect( ax-3, ay-3, 8, 8 )
		surface.DrawLine( ax, ay, ax+6, ay+6 )
		surface.DrawLine( ax-2, ay-2, ax+3, ay-2 )
		surface.DrawLine( ax-3, ay+3, ax+3, ay-3 )
		surface.DrawLine( ax-2, ay-2, ax-2, ay+3 )
		surface.SetDrawColor( 0, 0, 0, 255 )
		surface.DrawLine( ax-3, ay-3, ax+4, ay-3 )
		surface.DrawLine( ax-3, ay-3, ax-3, ay+4 )
		surface.DrawLine( ax-3, ay+4, ax+4, ay-3 )
		surface.DrawLine( ax, ay+1, ax+5, ay+6 )
		surface.DrawLine( ax+1, ay, ax+6, ay+5 )

		
		// Set back our 'sneaky' variable (lol)
		ss.SC = true
		
	end
	
	// End the 3D 2D
	cam.End3D2D()
	
	// Reupdate the screenspace
	PCMod.SDraw.SSpaces[ ent:EntIndex() ] = ss
end

// Devices that follow cfg.GuiScale. Program windows (and pickers) scale around
// their top-left; the Start menu also scales but stays glued to the taskbar.
function PCMod.SDraw.UsesGuiScale( device )
	if (!device) then return false end
	if (device.ProgName && (device.ProgName != "")) then return true end
	local t = device.Type
	return ((t == "menu_start") || (t == "menu_allprogs"))
end

// Returns the visual rectangle of a device in the target space (pass w=1, h=1
// for normalized viewport coordinates), plus the applied scale.
function PCMod.SDraw.GetDeviceVisualRect( device, w, h )
	local ds = 1
	if (PCMod.SDraw.UsesGuiScale( device )) then ds = PCMod.SDraw.WindowScale or 1 end
	local dx = device.X * w
	local dy = device.Y * h
	local vw = device.W * w * ds
	local vh = device.H * h * ds
	local isMenu = ((device.Type == "menu_start") || (device.Type == "menu_allprogs"))
	if ((ds != 1) && isMenu) then
		// Menus stay a block in the bottom-left: keep their bottom edge on the
		// taskbar and their horizontal positions relative to the Start menu, so
		// All Programs sits right next to it instead of floating at the top.
		dx = dx * ds
		dy = ((device.Y + device.H) * h) - vh
		return dx, dy, vw, vh, ds
	end
	// Program windows may never extend past the viewport / taskbar. This also
	// covers stale sizes from another GUI scale (e.g. a window maximised at
	// 25% and then viewed at 100%) and keeps drawing, hover and clicks aligned.
	if (device.ProgName && (device.ProgName != "")) then
		local limH = 0.94 * h
		if (vw > w) then vw = w end
		if (vh > limH) then vh = limH end
		dx = math.Clamp( dx, 0, math.max( 0, w - vw ) )
		dy = math.Clamp( dy, 0, math.max( 0, limH - vh ) )
	end
	return dx, dy, vw, vh, ds
end

// ---------------------------------------------------------------------------------------------------------
// DrawSpace - Draws the screenspace
// ---------------------------------------------------------------------------------------------------------
function PCMod.SDraw.DrawSpace( ss, x, y, w, h, entid )
	// Get the entity for reference
	local ent = ents.GetByIndex( entid )
	
	// Cycle through list of devices, reorder them
	// Round 19 (AUDIT2 A-04): bucket the entries by reference - the per-frame
	// table.Copy() of every device (the heaviest client-side allocation while a
	// screen is in view) is gone. The only writes left are idempotent stamps
	// (DevID once, Rev/Entity to constant values), so behaviour is unchanged.
	local tmp = {}
	for k, v in pairs( ss ) do
		if (type( v ) == "table") then
			local pr = v.Priority
			if (!pr) then pr = 1 end
			local devid = v.DevID
			if (!devid) then
				devid = tostring( entid ) .. ":" .. k
				v.DevID = devid
			end
			if (!tmp[pr]) then tmp[pr] = {} end
			table.insert( tmp[pr], v )
		end
	end
	
	// Reset the per-frame top-device marker. Element hover uses it so buttons
	// in a covered window do not light up through the window on top. This has
	// to be a full pre-pass: deciding it while drawing would let a lower window
	// (drawn first) see itself as topmost before the window above it is drawn.
	local cur = PCMod.SDraw.Cursor
	if (cur && (cur.Ent == entid)) then cur.HoverDevID = nil end
	for i=0, table.maxn( tmp ) do
		local v = tmp[i]
		if (v) then
			for _, device in pairs( v ) do
				if (cur && (cur.Ent == entid)) then
					local pdx, pdy, pdw, pdh = PCMod.SDraw.GetDeviceVisualRect( device, w, h )
					if ((cur.X > (x + pdx)) && (cur.X < (x + pdx + pdw)) && (cur.Y > (y + pdy)) && (cur.Y < (y + pdy + pdh))) then
						// Later (higher priority) devices overwrite earlier ones,
						// matching the painter's-algorithm draw order.
						cur.HoverDevID = device.DevID
					end
				end
			end
		end
	end

	// Cycle through the reordered devices, render them
	local i = 1
	for i=0, table.maxn( tmp ) do
		local v = tmp[i]
		if (v) then
			for _, device in pairs( v ) do
				if (PCMod.SDraw.DevMap[ device.DevID ]) then PCMod.SDraw.DevMap[ device.DevID ]:Tick() end
				// GUI scale applies to program windows/pickers and the Start
				// menus; fullscreen system screens and the desktop stay native.
				local dx, dy, dw, dh, ds = PCMod.SDraw.GetDeviceVisualRect( device, w, h )
				device.Scale = ds
				if (!device.Rev) then device.Rev = 1 end
				device.Entity = ent
				PCMod.SDraw.DrawDevice( device, x+dx, y+dy, dw, dh, entid )
			end
		end
	end
	
end

// ---------------------------------------------------------------------------------------------------------
// ApplyDeviceData - Applies a server payload to a device instance
// ---------------------------------------------------------------------------------------------------------
// Round 20 (M-01): the device prototype must never be written to.
//
// The old code applied the payload with table.Merge( dev, device ) on an instance
// that only had a metatable pointing at the prototype (__index = basedev).
// GMod's table.Merge recurses into dest[k] whenever the source value is a table,
// and dest[k] resolved through __index into the PROTOTYPE's table. Every instance
// of a device type on the client therefore shared - and permanently polluted - one
// table: chat history, file lists, device lists and port lists leaked from one PC
// into another and could never be cleared again.
//
// The instance owns its state now:
//   - it starts as a deep copy of the prototype (table.Copy), so no field is
//     shared with the template and no metatable is needed at all;
//   - the payload is applied by REPLACEMENT, not merged into the old value, so a
//     server side clear really empties the client;
//   - only the keys the server actually sent are touched, so client side state
//     (textboxes, listboxes, elements, selection, window geometry) survives;
//   - tables are taken by reference: the payload is already a client side copy of
//     the server data, so this costs no copying at all - and it is O(number of
//     keys) per frame instead of the old O(elements of every nested table).
function PCMod.SDraw.ApplyDeviceData( dev, device )
	for k, v in pairs( device ) do
		dev[ k ] = v
	end
end

// ---------------------------------------------------------------------------------------------------------
// DrawDevice - Draws a ScreenSpace device
// ---------------------------------------------------------------------------------------------------------
function PCMod.SDraw.DrawDevice( device, x, y, w, h, entid )
	// Get the device details
	local basedev = PCMod.SDraw.Devices[ device.Type ]
	local dev = PCMod.SDraw.DevMap[ device.DevID ]
	
	if (!dev) then
	
		// Create a new device
		if (!basedev) then return end
		// Round 20 (M-01): the instance gets its OWN copy of the prototype.
		// The prototype stays a pure template - no metatable, so nothing can
		// reach the shared tables through __index any more (that was the vector
		// that let table.Merge write into every instance of this device type).
		dev = table.Copy( basedev )
		if (dev.OnCreate) then dev:OnCreate() end
		PCMod.SDraw.DevMap[ device.DevID ] = dev
		
		// Feed in the data
		PCMod.SDraw.ApplyDeviceData( dev, device )
		
		// Initialize it
		dev:Int_Initialize( x, y, w, h)
	else		
		// Feed in the data
		PCMod.SDraw.ApplyDeviceData( dev, device )
		
		// Check for update
		local lastrev = PCMod.SDraw.DMap[ device.DevID ] or 0
		local moved = ((dev.win_x != x) || (dev.win_y != y) || (dev.win_w != w) || (dev.win_h != h))
		if (moved) then
			// Window rectangle changed (multi-window move/resize). The controls
			// were laid out for the old geometry, so rebuild them. Int_Reinitialize
			// keeps local textbox edits; only refresh from the payload if the
			// server also bumped Rev.
			dev:Int_Reinitialize( x, y, w, h )
			if (device.Rev && (device.Rev > lastrev)) then
				dev:Int_Update()
			end
		elseif (device.Rev && (device.Rev > lastrev)) then
			dev:Int_Update()
		end
	end
	
	// Fill in the DMap link & the entid
	PCMod.SDraw.DMap[ device.DevID ] = device.Rev
	dev.EntID = entid
	dev.SSDevice = device
	
	// Draw it
	dev:Int_Paint( x, y, w, h )
end

// ---------------------------------------------------------------------------------------------------------
// NewScreenSpace - Updates a screenspace with a full newer copy
// ---------------------------------------------------------------------------------------------------------
function PCMod.SDraw.NewScreenSpace( entid, ss )
	PCMod.SDraw.SSpaces[ entid ] = ss
end

// ---------------------------------------------------------------------------------------------------------
// UpdateScreenSpace - Updates a screenspace with a partial newer copy
// ---------------------------------------------------------------------------------------------------------
function PCMod.SDraw.UpdateScreenSpace( entid, ss )
	if (!PCMod.SDraw.SSpaces[ entid ]) then PCMod.SDraw.SSpaces[ entid ] = {} end
	for k, v in pairs( ss ) do
		if (v == 0) then
			// Let's hope there are no sneaky variables that equal 0... -thomasfn
			PCMod.SDraw.SSpaces[ entid ][ k ] = nil
		else
			if (type(v) == "table") then
				PCMod.SDraw.SSpaces[ entid ][ k ] = table.Copy( v )
			else
				PCMod.SDraw.SSpaces[ entid ][ k ] = v
			end
		end
	end
end

// ---------------------------------------------------------------------------------------------------------
// CalcCursor - Calculates the location of the cursor on a screen
// ---------------------------------------------------------------------------------------------------------
function PCMod.SDraw.CalcCursor( ent, fov )
	if ((!ent) || (!ent:IsValid())) then return end

	// Fullscreen screen: map the mouse directly (the desktop fills the
	// viewport; individual windows apply their own GUI-scale factor).
	if (PCMod.Gui && PCMod.Gui.CamLocked && (PCMod.Gui.CamLockID == ent:EntIndex())) then
		if ((ScrW() > 0) && (ScrH() > 0)) then
			return math.Clamp( gui.MouseX() / ScrW(), 0, 1 ), math.Clamp( gui.MouseY() / ScrH(), 0, 1 )
		end
	end

	local sc = PCMod.SDraw.Configs[ ent:GetModel() ]
	if (!sc) then return end
	
	// Begin adapted nighteagle code (amazing work with vectors!!!)  
	// Nighteagle has put a lot of work into refining the use of cam3d2d and traces to create cursor screen systems.
	// (Taken from gmod_wire_graphics_tablet, in wiremod pack)
		
		// Get the entity information
		local ang = ent:GetAngles()
		local rot = Vector(-90,90,0)+sc.Rotation
		ang:RotateAroundAxis(ang:Right(), rot.x)
		ang:RotateAroundAxis(ang:Up(), rot.y)
		ang:RotateAroundAxis(ang:Forward(), rot.z)
		local pos = ent:GetPos() + (ent:GetForward() * sc.z)
		
		// Get the cursor's traceline
		local trace = {}
			trace.start = LocalPlayer():GetShootPos()
			trace.endpos = (LocalPlayer():GetAimVector() * 64) + trace.start
			trace.filter = LocalPlayer()
			if ((PCMod.Gui.CamLocked) && (PCMod.Gui.CamLockID == ent:EntIndex())) then
				if ((ent) && (ent:IsValid())) then
					// This chunk of code is mine, it does the job of 'ply:GetAimVector()' but compensates for CalcView as well - thomasfn
					local view = PCMod.Cam.CalcEntView( ent )
					trace.start = view[1]
					trace.endpos = trace.start + (gui.ScreenToVector( gui.MouseX(), gui.MouseY() ) * 64)
					// End chunk of code
				end
			end
		local tr = util.TraceLine(trace)
		
		// If the cursor's traceline hits the entity, calculate where
		if (tr.Entity == ent) then
			local pos = ent:WorldToLocal( tr.HitPos )
			local cx = math.Clamp( (sc.x1 - pos.y) / (sc.x1 - sc.x2), 0, 1 )
			local cy = math.Clamp( (sc.y1 - pos.z) / (sc.y1 - sc.y2), 0, 1 )
			return cx, cy
		else
			// No hit, return default
			return 0.5, 0.5
		end
		
	// End adapted nighteagle code
	
end