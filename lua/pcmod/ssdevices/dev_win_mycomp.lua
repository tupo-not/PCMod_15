
// PCMod ScreenSpace Device | Control Panel \\

DEV.Name = "window_mycomp"

DEV.LastTick = 0
DEV.LastFrame = 0

DEV.Th = "basic"
DEV.PWE = 0
DEV.Section = "os"
DEV.Net = {}
DEV.Dvs = {}

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

local function NetValue( value )
	if ((value == nil) || (value == "")) then return "Not available" end
	return tostring( value )
end

function DEV:ReinitializeSelf()
	if (self.Int_Reinitialize) then
		self:Int_Reinitialize( self.win_x, self.win_y, self.win_w, self.win_h )
	end
end

function DEV:SwitchSection( section )
	if ((section != "os") && (section != "network") && (section != "io")) then return end
	if (section == self.Section) then return end
	// Textboxes belonging to a hidden page are destroyed by the layout rebuild.
	// Keep password drafts so browsing the other categories cannot discard them.
	if (self.Section == "os") then
		self.OldPassDraft = self:GetTextboxText( "txtOldPass" )
		self.NewPassDraft = self:GetTextboxText( "txtNewPass" )
	end
	if (self.Section == "network") then
		self.WifiPassDraft = self:GetTextboxText( "txtWifiPass" )
		self.StaticIPDraft = self:GetTextboxText( "txtStaticIP" )
	end
	self.Section = section
	self:ReinitializeSelf()
end

function DEV:InitializeOS( x, y, w, h )
	self:CreateListbox( self.Th, "lstThemes", x+(w*0.325), y+(h*0.20), w*0.30, h*0.40 )
	for k, v in pairs( PCMod.Gui.Themes ) do
		self:AddListboxItem( "lstThemes", k, v.NiceName )
	end
	self:SetListboxSelRow( "lstThemes", self.Th )
	self:CreateButton2( self.Th, "btnSetTheme", x+(w*0.325), y+(h*0.63), w*0.30, h*0.07, "Apply Theme" )

	self:CreateListbox( self.Th, "lstGuiScale", x+(w*0.66), y+(h*0.20), w*0.30, h*0.28 )
	for _, v in ipairs( GUI_SCALES ) do
		self:AddListboxItem( "lstGuiScale", tostring( v ), ScaleLabel( v ) )
	end
	local cur = CurrentGuiScale()
	local bestkey = tostring( GUI_SCALES[ 4 ] )
	local bestdiff = 999
	for _, v in ipairs( GUI_SCALES ) do
		local diff = math.abs( v - cur )
		if (diff < bestdiff) then
			bestdiff = diff
			bestkey = tostring( v )
		end
	end
	self:SetListboxSelRow( "lstGuiScale", bestkey )
	self:CreateButton2( self.Th, "btnApplyScale", x+(w*0.66), y+(h*0.51), w*0.30, h*0.07, "Apply Scale" )

	self:CreateTextbox( self.Th, "txtOldPass", x+(w*0.485), y+(h*0.81), w*0.31, h*0.055, "Old Password:" )
	self:CreateTextbox( self.Th, "txtNewPass", x+(w*0.485), y+(h*0.89), w*0.31, h*0.055, "New Password:" )
	self:CreateButton2( self.Th, "btnApplyPass", x+(w*0.66), y+(h*0.81), w*0.30, h*0.07, "Change Password" )
	if (self.OldPassDraft) then self:SetTextboxText( "txtOldPass", self.OldPassDraft ) end
	if (self.NewPassDraft) then self:SetTextboxText( "txtNewPass", self.NewPassDraft ) end
end

function DEV:InitializeNetwork( x, y, w, h )
	self:CreateListbox( self.Th, "lstNetInfo", x+(w*0.325), y+(h*0.21), w*0.28, h*0.50 ).LeftAlign = true
	self:CreateListbox( self.Th, "lstWireless", x+(w*0.63), y+(h*0.21), w*0.335, h*0.38 ).LeftAlign = true
	self:CreateTextbox( self.Th, "txtWifiPass", x+(w*0.7975), y+(h*0.62), w*0.335, h*0.055, "Password:" )
	self:CreateButton2( self.Th, "btnWifiConnect", x+(w*0.63), y+(h*0.69), w*0.16, h*0.07, "Connect" )
	self:CreateButton2( self.Th, "btnWifiDisconnect", x+(w*0.805), y+(h*0.69), w*0.16, h*0.07, "Disconnect" )
	self:CreateButton2( self.Th, "btnRefreshNetwork", x+(w*0.325), y+(h*0.88), w*0.28, h*0.07, "Refresh" )
	self:CreateButton2( self.Th, "btnNetTools", x+(w*0.63), y+(h*0.88), w*0.335, h*0.07, "Network Tools" )
	self:CreateTextbox( self.Th, "txtStaticIP", x+(w*0.325), y+(h*0.74), w*0.28, h*0.055, "Static IP:" )
	self:CreateButton2( self.Th, "btnSetIP", x+(w*0.325), y+(h*0.81), w*0.28, h*0.055, "Set Static IP" )
	if (self.WifiPassDraft) then self:SetTextboxText( "txtWifiPass", self.WifiPassDraft ) end
	if (self.StaticIPDraft) then self:SetTextboxText( "txtStaticIP", self.StaticIPDraft ) end
end

function DEV:InitializeIO( x, y, w, h )
	self:CreateListbox( self.Th, "lstDevices", x+(w*0.325), y+(h*0.20), w*0.635, h*0.55 ).LeftAlign = true
	self:CreateButton2( self.Th, "btnRefreshDevices", x+(w*0.325), y+(h*0.80), w*0.30, h*0.07, "Refresh Devices" )
	self:CreateButton2( self.Th, "btnDeviceManager", x+(w*0.66), y+(h*0.80), w*0.30, h*0.07, "Device Manager" )
end

function DEV:Initialize( x, y, w, h )
	self:CreateButton2( self.Th, "btnExit", (x+w)-(h*0.06), y, h*0.06, h*0.06, "X" )

	// File Manager-style navigation: categories on the left, the active
	// category's settings and information in the larger right-hand pane.
	self:CreateListbox( self.Th, "lstSections", x+(w*0.025), y+(h*0.16), w*0.25, h*0.76 ).LeftAlign = true
	self:AddListboxItem( "lstSections", "os", "Operating System" )
	self:AddListboxItem( "lstSections", "network", "Network" )
	self:AddListboxItem( "lstSections", "io", "Input / Output" )
	if ((self.Section != "os") && (self.Section != "network") && (self.Section != "io")) then self.Section = "os" end
	self:SetListboxSelRow( "lstSections", self.Section )

	if (self.Section == "network") then
		self:InitializeNetwork( x, y, w, h )
	elseif (self.Section == "io") then
		self:InitializeIO( x, y, w, h )
	else
		self:InitializeOS( x, y, w, h )
	end

	self.WinX = x
	self.WinY = y
	self.WinW = w
	self.WinH = h
	self:OnUpdate()
end

function DEV:BuildNetworkInfo()
	if ((!self.Listboxes) || (!self.Listboxes[ "lstNetInfo" ])) then return end
	self:ClearListbox( "lstNetInfo" )
	local net = self.Net
	if (type( net ) != "table") then net = {} end
	self:AddListboxItem( "lstNetInfo", "ipv4", "IPv4 Address: " .. NetValue( net.IPv4 ) )
	self:AddListboxItem( "lstNetInfo", "static", "Static IP: " .. tostring( net.Static or "DHCP (auto)" ) )
	self:AddListboxItem( "lstNetInfo", "ipv6", "IPv6 Address: " .. NetValue( net.IPv6 ) )
	self:AddListboxItem( "lstNetInfo", "prefix", "IPv6 Subnet: " .. NetValue( net.Prefix ) )
	self:AddListboxItem( "lstNetInfo", "gateway", "IPv6 Gateway: " .. NetValue( net.Gateway ) )
	self:AddListboxItem( "lstNetInfo", "linklocal", "Link-Local: " .. NetValue( net.LinkLocal ) )
end

function DEV:BuildDevices()
	if ((!self.Listboxes) || (!self.Listboxes[ "lstDevices" ])) then return end
	self:ClearListbox( "lstDevices" )
	local count = 0
	for _, v in pairs( self.Dvs or {} ) do
		if (v && v[1]) then
			count = count + 1
			local key = tostring( v[1] )
			self:AddListboxItem( "lstDevices", key, "Port " .. key .. "  |  " .. tostring( v[2] or "Unknown device" ) )
		end
	end
	if (count == 0) then self:AddListboxItem( "lstDevices", "none", "No identified USB devices." ) end
end

function DEV:BuildWireless()
	if ((!self.Listboxes) || (!self.Listboxes[ "lstWireless" ])) then return end
	self:ClearListbox( "lstWireless" )
	local count = 0
	for _, w in pairs( self.Wireless or {} ) do
		if (w && w.EntIndex) then
			count = count + 1
			local key = tostring( w.EntIndex )
			// Simplify the router class name into a friendly label.
			local name = "Router"
			if (w.Class == "pcmod_brouter") then name = "Backbone Router" end
			self:AddListboxItem( "lstWireless", key, name .. " #" .. key .. "  |  " .. tostring( w.Distance or 0 ) .. "m  |  Signal " .. tostring( w.Signal or 0 ) .. "%" )
		end
	end
	if (count == 0) then self:AddListboxItem( "lstWireless", "none", "No wireless networks in range." ) end
end

function DEV:OnUpdate()
	self:BuildNetworkInfo()
	self:BuildWireless()
	self:BuildDevices()
end

function DEV:Paint( x, y, w, h )
	self:RenderWindow( self.Th, x, y, w, h, "Control Panel", h*0.06 )
	self:RenderText( x+(w*0.15), y+(h*0.105), { "Categories" }, Color( 0, 0, 0, 255 ), 1 )
	if (self.Section == "network") then
		self:RenderText( x+(w*0.6425), y+(h*0.105), { "Network Settings & Status" }, Color( 0, 0, 0, 255 ), 1 )
		self:RenderText( x+(w*0.465), y+(h*0.16), { "Status" }, Color( 0, 0, 0, 255 ), 1 )
		self:RenderText( x+(w*0.7975), y+(h*0.16), { "Wireless Networks" }, Color( 0, 0, 0, 255 ), 1 )
		local wf = self.Wifi
		local wstat = "Not connected."
		if (wf && wf.Connected) then
			wstat = "Connected to " .. tostring( wf.Class or "Router" ) .. " #" .. tostring( wf.EntIndex )
			if (wf.NoIPv4) then wstat = wstat .. " (IPv6 only)" end
		elseif (wf && wf.BadPass) then
			wstat = "Incorrect password."
		elseif (wf && wf.Error) then
			wstat = tostring( wf.Error )
		end
		self:RenderText( x+(w*0.7975), y+(h*0.79), { wstat }, Color( 0, 0, 0, 255 ), 1 )
	elseif (self.Section == "io") then
		self:RenderText( x+(w*0.6425), y+(h*0.105), { "Input / Output Devices" }, Color( 0, 0, 0, 255 ), 1 )
		self:RenderText( x+(w*0.6425), y+(h*0.90), { "Identified USB devices connected to this computer." }, Color( 0, 0, 0, 255 ), 1 )
	else
		self:RenderText( x+(w*0.6425), y+(h*0.105), { "Operating System" }, Color( 0, 0, 0, 255 ), 1 )
		self:RenderText( x+(w*0.475), y+(h*0.17), { "Theme" }, Color( 0, 0, 0, 255 ), 1 )
		self:RenderText( x+(w*0.81), y+(h*0.17), { "GUI Scale" }, Color( 0, 0, 0, 255 ), 1 )
		self:RenderText( x+(w*0.81), y+(h*0.59), { "Current: " .. ScaleLabel( CurrentGuiScale() ) }, Color( 0, 0, 0, 255 ), 1 )
		self:RenderText( x+(w*0.485), y+(h*0.73), { "Security" }, Color( 0, 0, 0, 255 ), 1 )
		if (self.PWE == 1) then self:RenderError( self.Th, x+(w*0.81), y+(h*0.90), "Old password wrong!" ) end
		if (self.PWE == 2) then self:RenderText( x+(w*0.81), y+(h*0.90), { "Password changed!" }, Color( 0, 0, 0, 255 ), 1 ) end
	end
	self:Draw()
end

function DEV:ButtonClick( btn )
	if (btn == "btnExit") then
		self:RunProgCommand( "mycomputer", "exit" )
		return
	end
	if (btn == "btnApplyPass") then
		local old = self:GetTextboxText( "txtOldPass" )
		local new = self:GetTextboxText( "txtNewPass" )
		self.OldPassDraft = old
		self.NewPassDraft = new
		self:RunProgCommand( "mycomputer", "changepass", old, new )
		return
	end
	if (btn == "btnSetTheme") then
		local newth = self:GetListboxSelRow( "lstThemes" )
		if ((newth) && (newth != "")) then self:SubmitCommand( "os_command", "sys_settheme", newth ) end
		return
	end
	if (btn == "btnApplyScale") then
		local val = tonumber( self:GetListboxSelRow( "lstGuiScale" ) )
		if (val) then RunConsoleCommand( "pc_guiscale", tostring( val ) ) end
		return
	end
	if (btn == "btnRefreshNetwork") then
		self:RunProgCommand( "mycomputer", "refresh_network" )
		return
	end
	if (btn == "btnSetIP") then
		self.StaticIPDraft = self:GetTextboxText( "txtStaticIP" )
		self:RunProgCommand( "mycomputer", "set_static_ip", self.StaticIPDraft or "" )
		return
	end
	if (btn == "btnWifiConnect") then
		local sel = self:GetListboxSelRow( "lstWireless" )
		if ((sel) && (sel != "none")) then
			self.WifiPassDraft = self:GetTextboxText( "txtWifiPass" )
			self:RunProgCommand( "mycomputer", "connect_wifi", sel, self.WifiPassDraft or "" )
		end
		return
	end
	if (btn == "btnWifiDisconnect") then
		self:RunProgCommand( "mycomputer", "disconnect_wifi" )
		return
	end
	if (btn == "btnRefreshDevices") then
		self:RunProgCommand( "mycomputer", "refresh_devices" )
		return
	end
	if (btn == "btnDeviceManager") then
		self:RunProgCommand( "mycomputer", "open_devman" )
		return
	end
	if (btn == "btnNetTools") then
		self:RunProgCommand( "mycomputer", "open_nettools" )
	end
end

function DEV:ListboxSelect( name, option )
	if (name == "lstSections") then self:SwitchSection( option ) end
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
