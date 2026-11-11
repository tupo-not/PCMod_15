
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
end

function DEV:Paint( x, y, w, h )
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
	end
end

function DEV:DoClick( x, y, right )
	if (PCMod.Cfg.DebugHitbox) then
		local el = self.Elements and self.Elements[ "btn_start" ]
		PCMod.Msg( string.format( "CLICK x=%.3f y=%.3f win=%d,%d,%d,%d btn=%s", x, y, self.win_x, self.win_y, self.win_w, self.win_h, (el and string.format( "%d,%d,%d,%d", el.X, el.Y, el.W, el.H )) or "nil" ) )
	end
	// Padded Start hitbox: accept clicks in a margin around the drawn button.
	// Clicking the empty desktop does nothing anyway, and the Start menu (when
	// open) sits above the taskbar and takes its clicks first by priority.
	if ((!right) && (y > (1 - self.BarSize - self.StartHitPad)) && (x < (self.BtnW + self.StartHitPad))) then
		self:ButtonClick( "btn_start" )
		return
	end
	self:ProcessClick( x, y )
end

function DEV:Tick()
	self.LastTick = CurTime()
	self.LastFrame = PCMod.SDraw.CFrame
end

function DEV:Kill()
	
end

function DEV:KeyPress( key, txt )
	self:KeyPressTextboxes( key, txt )
end