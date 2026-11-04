
// PCMod ScreenSpace Device | Control Panel \\

DEV.Name = "window_mycomp"

DEV.LastTick = 0
DEV.LastFrame = 0

DEV.Th = "basic"

DEV.PWE = 0

// Presets offered by the Control Panel. The active value lives in
// PCMod.Cfg.GuiScale (and can also be changed with pc_guiscale <n>).
local GUI_SCALES = { 0.25, 0.5, 0.75, 1, 1.25, 1.5, 2 }

local function CurrentGuiScale()
	if (PCMod.SDraw && PCMod.SDraw.GetGuiScale) then
		return PCMod.SDraw.GetGuiScale()
	end
	local n = 1
	if (PCMod.Cfg && (PCMod.Cfg.GuiScale != nil)) then n = tonumber( PCMod.Cfg.GuiScale ) or 1 end
	return n
end

local function ScaleLabel( v )
	return tostring( math.floor( (v * 100) + 0.5 ) ) .. "%"
end

function DEV:Initialize( x, y, w, h )
	// Make exit button
	self:CreateButton2( self.Th, "btnExit", (x+w)-(h*0.06), y, h*0.06, h*0.06, "X" )
	
	// Make all themes
	self:CreateListbox( self.Th, "lstThemes", x+(w*0.04), y+(h*0.13), w*0.26, h*0.58 )
	local cnt = 0
	for k, v in pairs( PCMod.Gui.Themes ) do
		cnt = cnt + 1
		self:AddListboxItem( "lstThemes", k, v.NiceName )
	end
	self:SetListboxSelRow( "lstThemes", self.Th )
	self:CreateButton2( self.Th, "btnSetTheme", x+(w*0.04), y+(h*0.73), w*0.26, h*0.07, "Apply Theme" )
	
	// GUI scale presets
	self:CreateListbox( self.Th, "lstGuiScale", x+(w*0.35), y+(h*0.13), w*0.22, h*0.44 )
	for _, v in ipairs( GUI_SCALES ) do
		self:AddListboxItem( "lstGuiScale", tostring( v ), ScaleLabel( v ) )
	end
	local cur = CurrentGuiScale()
	local bestkey = tostring( GUI_SCALES[ 2 ] )
	local bestdiff = 999
	for _, v in ipairs( GUI_SCALES ) do
		local diff = math.abs( v - cur )
		if (diff < bestdiff) then
			bestdiff = diff
			bestkey = tostring( v )
		end
	end
	self:SetListboxSelRow( "lstGuiScale", bestkey )
	self:CreateButton2( self.Th, "btnApplyScale", x+(w*0.35), y+(h*0.59), w*0.22, h*0.07, "Apply Scale" )
	
	// Make password change boxes
	self:CreateTextbox( self.Th, "txtOldPass", x+(w*0.80), y+(h*0.22), w*0.32, h*0.05, "Old Password:" )
	self:CreateTextbox( self.Th, "txtNewPass", x+(w*0.80), y+(h*0.29), w*0.32, h*0.05, "New Password:" )
	self:CreateButton2( self.Th, "btnApplyPass", x+(w*0.69), y+(h*0.38), w*0.22, h*0.07, "Change" )
	
	// Make other buttons
	self:CreateButton2( self.Th, "btnDeviceManager", x+(w*0.35), y+(h*0.80), w*0.6, h*0.07, "Device Manager" )
	self:CreateButton2( self.Th, "btnNetTools", x+(w*0.35), y+(h*0.89), w*0.6, h*0.07, "Network Tools" )
	
	// Record window data
	self.WinX = x
	self.WinY = y
	self.WinW = w
	self.WinH = h
end

function DEV:Paint( x, y, w, h )
	self:RenderWindow( self.Th, x, y, w, h, "Control Panel", h*0.06 )
	self:RenderText( x+(w*0.80), y+(h*0.14), { "Welcome to the control panel!" }, Color( 0, 0, 0, 255 ), 1 )
	self:RenderText( x+(w*0.46), y+(h*0.10), { "GUI Scale" }, Color( 0, 0, 0, 255 ), 1 )
	self:RenderText( x+(w*0.46), y+(h*0.68), { "Current: " .. ScaleLabel( CurrentGuiScale() ) }, Color( 0, 0, 0, 255 ), 1 )
	if (self.PWE == 1) then self:RenderError( self.Th, x+(w*0.8), y+(h*0.46), "Old password wrong!" ) end
	if (self.PWE == 2) then self:RenderText( x+(w*0.8), y+(h*0.46), { "Password changed!" }, Color( 0, 0, 0, 255 ), 1 ) end
	self:Draw()
end

function DEV:ButtonClick( btn )
	local x, y, w, h = self.win_x, self.win_y, self.win_w, self.win_h
	if (btn == "btnExit") then
		self:RunProgCommand( "mycomputer", "exit" )
		return
	end
	if (btn == "btnApplyPass") then
		local old = self:GetTextboxText( "txtOldPass" )
		local new = self:GetTextboxText( "txtNewPass" )
		self:RunProgCommand( "mycomputer", "changepass", old, new )
		return
	end
	if (btn == "btnSetTheme") then
		local newth = self:GetListboxSelRow( "lstThemes" )
		if ((newth) && (newth != "")) then self:SubmitCommand( "os_command", "sys_settheme", newth ) end
	end
	if (btn == "btnApplyScale") then
		local val = tonumber( self:GetListboxSelRow( "lstGuiScale" ) )
		if (val) then
			// Client-side setting: applies immediately to this screen.
			RunConsoleCommand( "pc_guiscale", tostring( val ) )
		end
	end
	if (btn == "btnDeviceManager") then
		// self:SubmitCommand( "os_command", "sys_openprog", "deviceman" )
		self:RunProgCommand( "mycomputer", "open_devman" )
	end
	if (btn == "btnNetTools") then
		//self:SubmitCommand( "os_command", "sys_openprog", "nettools" )
		self:RunProgCommand( "mycomputer", "open_nettools" )
	end
end

function DEV:DoClick( x, y )
	self:ProcessClick( x, y )
end

function DEV:Tick()
	self.LastTick = CurTime()
	self.LastFrame = PCMod.SDraw.CFrame
end

function DEV:KeyPress( key, txt )
	self:KeyPressTextboxes( key, txt )
end