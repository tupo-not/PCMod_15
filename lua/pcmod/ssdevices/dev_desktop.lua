
// PCMod ScreenSpace Device | Desktop \\

DEV.Name = "desktop"

DEV.LastTick = 0
DEV.LastFrame = 0

DEV.State = 1
-- 1 = just desktop
-- 2 = desktop with start menu
-- 3 = desktop with start menu and programs menu

DEV.BarSize = 0.06

DEV.BtnSize = 0.06
DEV.BtnW = 0.12

// Extra hitbox margin around the drawn Start button (fraction of the screen).
// The taskbar is only BarSize tall and the button sits in the bottom-left
// corner, where the cursor mapping is least precise, so clicks there are
// matched against a padded rect instead of the exact button rect.
DEV.StartHitPad = 0.04

DEV.Th = "basic"

// Running-program taskbar. The server describes windows through the normal
// payload; minimize state remains client-local in PCMod.SDraw.Minimized.
function DEV:GatherTaskItems()
	local byName = {}
	local entid = self.EntID
	local ss = (PCMod.SDraw.SSpaces && PCMod.SDraw.SSpaces[ entid ]) or {}
	for key, dev in pairs( ss ) do
		if ((type( dev ) == "table") && dev.ProgName && (dev.ProgName != "")) then
			local item = {
				ProgName = dev.ProgName,
				Title = dev.AppTitle or dev.ProgName,
				Icon = dev.AppIcon,
				DevID = dev.DevID or (tostring( entid ) .. ":" .. tostring( key )),
				OpenID = dev.OpenID,
				Priority = dev.Priority or 0,
			}
			local old = byName[ item.ProgName ]
			if ((!old) || (item.Priority > old.Priority)) then byName[ item.ProgName ] = item end
		end
	end
	local items = {}
	for _, item in pairs( byName ) do items[ #items + 1 ] = item end
	table.sort( items, function( a, b )
		if (string.lower( a.Title ) != string.lower( b.Title )) then return string.lower( a.Title ) < string.lower( b.Title ) end
		return a.DevID < b.DevID
	end )
	return items
end

function DEV:UpdateTaskbar()
	local items = self:GatherTaskItems()
	// Priorities change on every server focus without changing the button layout.
	// Refresh item objects before the early return so active/hit logic never sees
	// stale z-order from the moment the buttons were created.
	for name, old in pairs( self.TaskItems or {} ) do
		for _, item in ipairs( items ) do
			if (item.ProgName == old.ProgName) then
				self.TaskItems[ name ] = item
				break
			end
		end
	end
	local valid = {}
	for _, item in ipairs( items ) do valid[ item.DevID ] = true end
	local minimized = PCMod.SDraw.Minimized && PCMod.SDraw.Minimized[ self.EntID ]
	for devid in pairs( minimized or {} ) do
		if (!valid[ devid ]) then minimized[ devid ] = nil end
	end
	local sigParts = {}
	for _, item in ipairs( items ) do sigParts[ #sigParts + 1 ] = item.DevID .. "@" .. tostring( item.OpenID ) end
	local sig = table.concat( sigParts, "|" )
	if (sig == self.TaskSig) then return end
	self.TaskSig = sig

	for name, _ in pairs( self.Elements or {} ) do
		if (string.sub( name, 1, 9 ) == "btn_task_") then self:RemoveElement( name ) end
	end
	self.TaskItems = {}
	if (#items == 0) then return end

	local available = self.win_w * (1 - self.BtnW - 0.01)
	local bw = math.min( self.win_w * 0.18, available / #items )
	local x0 = self.win_x + (self.win_w * (self.BtnW + 0.01))
	local y = self.win_y + (self.win_h * (1 - self.BtnSize))
	for i, item in ipairs( items ) do
		local name = "btn_task_" .. item.ProgName
		self:CreateButton2( self.Th, name, x0 + ((i - 1) * bw), y, bw, self.win_h * self.BtnSize, item.Title, item.Icon )
		self.TaskItems[ name ] = item
	end
end

function DEV:GetTopTaskItem()
	local top, topPriority = nil, -1
	for _, item in pairs( self.TaskItems or {} ) do
		if ((!PCMod.SDraw.IsMinimized( item, self.EntID )) && (item.Priority >= topPriority)) then
			top = item
			topPriority = item.Priority
		end
	end
	return top
end

function DEV:UpdateTaskActive()
	local top = self:GetTopTaskItem()
	local topID = top && top.DevID or nil
	for name, item in pairs( self.TaskItems or {} ) do
		local el = self.Elements and self.Elements[ name ]
		if (el) then el.Active = (item.DevID == topID) end
	end
end

// Debug aid: pc_debug_hitbox 1 draws the desktop window rect (green) and the
// btn_start hitbox (red) on the screen and logs every click's normalized
// coords next to the element rect, so hitbox/visual mismatches are visible.
concommand.Add( "pc_debug_hitbox", function( pl, cmd, args )
	PCMod.Cfg.DebugHitbox = (tonumber( args[1] ) or 0) != 0
	PCMod.Msg( "DebugHitbox = " .. tostring( PCMod.Cfg.DebugHitbox ) )
end )

function DEV:Initialize( x, y, w, h )
	local btny = y + (h * (1 - self.BtnSize))
	self:CreateButton2( self.Th, "btn_start", x, btny, w*self.BtnW, h*self.BtnSize, "Start" )
	self.WinX = x
	self.WinY = y
	self.WinW = w
	self.WinH = h
	self.win_x = x
	self.win_y = y
	self.win_w = w
	self.win_h = h
	self.TaskSig = nil
	self.TaskItems = {}
	self:UpdateTaskbar()
end

function DEV:Paint( x, y, w, h )
	self:UpdateTaskActive()
	// TaskbarOnly: DrawSpace repaints just the taskbar strip (plus the Start
	// button) on top while a Start menu slides in/out from behind it.
	if (self.TaskbarOnly) then
		local bary = y + (h * (1 - self.BarSize))
		local c_tsk = PCMod.Gui.GetThemeColour( self.Th, "TaskBar" )
		local c_bor = PCMod.Gui.GetThemeColour( self.Th, "Border" )
		if (!PCMod.Gui.ThemeDraw( self.Th, "taskbar", x, bary, w, h*self.BarSize, self.BarSize, self.BtnW )) then
			surface.SetDrawColor( c_tsk.r, c_tsk.g, c_tsk.b, c_tsk.a )
			surface.DrawRect( x, bary, w, h*self.BarSize )
			surface.SetDrawColor( c_bor.r, c_bor.g, c_bor.b, c_bor.a )
			surface.DrawLine( x+(w*self.BtnW), bary, x+w, bary )
		end
		self:Draw()
		return
	end
	local c_pri = PCMod.Gui.GetThemeColour( self.Th, "Primary" )
	local c_sec = PCMod.Gui.GetThemeColour( self.Th, "Secondary" )
	local c_tsk = PCMod.Gui.GetThemeColour( self.Th, "TaskBar" )
	local c_bor = PCMod.Gui.GetThemeColour( self.Th, "Border" )
	local bary = y + (h * (1 - self.BarSize))
	local bg = self.BG
	if (!bg) then
		surface.SetDrawColor( c_sec.r, c_sec.g, c_sec.b, c_sec.a )
		surface.DrawRect( x, y, w, h )
	else
		local id = self.BGID
		if (!id) then
			self.BGID = surface.GetTextureID( self.BG )
			id = self.BGID
		end
		surface.SetTexture( id )
		surface.SetDrawColor( 255, 255, 255, 255 )
		surface.DrawTexturedRect( x, y, w, h )
	end
	// PCMOD15 E7: the taskbar strip is theme-hookable ("taskbar");
	// themes that do not handle the id fall through to the
	// original painting. The start button is a Button element and
	// is painted by self:Draw() in both cases.
	if (!PCMod.Gui.ThemeDraw( self.Th, "taskbar", x, bary, w, h*self.BarSize, self.BarSize, self.BtnW )) then
		surface.SetDrawColor( c_tsk.r, c_tsk.g, c_tsk.b, c_tsk.a )
		surface.DrawRect( x, bary, w, h*self.BarSize )
		surface.SetDrawColor( c_bor.r, c_bor.g, c_bor.b, c_bor.a )
		surface.DrawLine( x+(w*self.BtnW), bary, x+w, bary )
	end
	self:Draw()
	if (PCMod.Cfg.DebugHitbox) then
		surface.SetDrawColor( 0, 255, 0, 255 )
		surface.DrawOutlinedRect( self.win_x, self.win_y, self.win_w, self.win_h )
		local el = self.Elements and self.Elements[ "btn_start" ]
		if (el) then
			surface.SetDrawColor( 255, 0, 0, 255 )
			surface.DrawOutlinedRect( el.X, el.Y, el.W, el.H )
		end
	end
end

function DEV:ButtonClick( btn )
	local x, y, w, h = self.win_x, self.win_y, self.win_w, self.win_h
	PCMod.Msg( "CLICKING " .. btn, true )
	if (btn == "btn_start") then
		PCMod.Msg( "CLICKING START", true )
		self:SubmitCommand( "os_command", "startmenu_open" )
		return
	end
	local item = self.TaskItems and self.TaskItems[ btn ]
	if (item) then
		local minimized = PCMod.SDraw.IsMinimized( item, self.EntID )
		local top = self:GetTopTaskItem()
		if (minimized) then
			PCMod.SDraw.SetMinimized( item, self.EntID, false )
			PCMod.SDraw.DevFocus = string.match( item.DevID, ":(.+)$" )
			self:SubmitCommand( "os_command", "prog_command", item.ProgName, "focus" )
		elseif (top && (top.DevID == item.DevID)) then
			PCMod.SDraw.SetMinimized( item, self.EntID, true )
		else
			PCMod.SDraw.SetMinimized( item, self.EntID, false )
			PCMod.SDraw.DevFocus = string.match( item.DevID, ":(.+)$" )
			self:SubmitCommand( "os_command", "prog_command", item.ProgName, "focus" )
		end
	end
end

function DEV:DoClick( x, y, right )
	if (PCMod.Cfg.DebugHitbox) then
		local el = self.Elements and self.Elements[ "btn_start" ]
		PCMod.Msg( string.format( "CLICK x=%.3f y=%.3f win=%d,%d,%d,%d btn=%s", x, y, self.win_x, self.win_y, self.win_w, self.win_h, (el and string.format( "%d,%d,%d,%d", el.X, el.Y, el.W, el.H )) or "nil" ) )
	end
	// Padded Start hitbox: accept clicks in a margin around the drawn button.
	// When task buttons exist, stop the padding before their first rectangle so
	// the left edge of the first application cannot open Start by mistake.
	local startPad = self.StartHitPad
	if (next( self.TaskItems or {} )) then startPad = math.min( startPad, 0.01 ) end
	if ((!right) && (y > (1 - self.BarSize - self.StartHitPad)) && (x < (self.BtnW + startPad))) then
		self:ButtonClick( "btn_start" )
		return
	end
	self:ProcessClick( x, y )
end

function DEV:Tick()
	self:UpdateTaskbar()
	self.LastTick = CurTime()
	self.LastFrame = PCMod.SDraw.CFrame
end

function DEV:Kill()
	
end

function DEV:KeyPress( key, txt )
	self:KeyPressTextboxes( key, txt )
end