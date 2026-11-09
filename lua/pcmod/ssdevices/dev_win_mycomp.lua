
// PCMod ScreenSpace Device | Control Panel \\

DEV.Name = "window_mycomp"

DEV.LastTick = 0
DEV.LastFrame = 0

DEV.Th = "basic"
DEV.PWE = 0
DEV.Section = "os"
DEV.Net = {}
DEV.Dvs = {}

// Keep the active category and any per-page drafts when the client device is
// destroyed while the player walks away from the screen. A program restart has
// a new OpenID, so reopening the Control Panel still starts on the first page.
DEV.PersistKeys = {
	"Section",
	"OldPassDraft", "NewPassDraft",
	"StaticIPDraft", "NetmaskDraft", "GatewayDraft", "MacDraft",
	"WifiPassDraft",
	"KeyRepeatDraft", "KeyHoldDraft",
}

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

// Keyboard repeat limits (milliseconds). The active values are the archived
// pc_keyrepeat / pc_keyhold client convars.
local KEY_REPEAT_MIN = 20
local KEY_REPEAT_MAX = 1000
local KEY_HOLD_MIN = 0
local KEY_HOLD_MAX = 2000

local function CurrentKeyRepeat()
	if (keyboard && keyboard.GetLatency) then
		return math.floor( keyboard.GetLatency() + 0.5 )
	end
	return 200
end

local function CurrentKeyHold()
	if (keyboard && keyboard.GetHoldTime) then
		return math.floor( keyboard.GetHoldTime() + 0.5 )
	end
	return 500
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
	if ((section != "os") && (section != "network") && (section != "wifi") && (section != "io")) then return end
	if (section == self.Section) then return end
	// Textboxes belonging to a hidden page are destroyed by the layout rebuild.
	// Keep drafts so browsing the other categories cannot discard them.
	if (self.Section == "os") then
		self.OldPassDraft = self:GetTextboxText( "txtOldPass" )
		self.NewPassDraft = self:GetTextboxText( "txtNewPass" )
	end
	if (self.Section == "network") then
		self.StaticIPDraft = self:GetTextboxText( "txtStaticIP" )
		self.NetmaskDraft = self:GetTextboxText( "txtNetmask" )
		self.GatewayDraft = self:GetTextboxText( "txtGateway" )
		self.MacDraft = self:GetTextboxText( "txtMac" )
	end
	if (self.Section == "wifi") then
		self.WifiPassDraft = self:GetTextboxText( "txtWifiPass" )
	end
	if (self.Section == "io") then
		self.KeyRepeatDraft = self:GetTextboxText( "txtKeyRepeat" )
		self.KeyHoldDraft = self:GetTextboxText( "txtKeyHold" )
	end
	self.Section = section
	self:SaveLocalState()
	self:ReinitializeSelf()
end

local UI = PCMod.UI

local function MyCompList( dev, theme, name, rect, leftAlign )
	local lb = dev:CreateListbox( theme, name, rect.x, rect.y, rect.w, rect.h )
	if (leftAlign) then lb.LeftAlign = true end
	return lb
end

local function MyCompButton( dev, theme, name, rect, text )
	return dev:CreateButton2( theme, name, rect.x, rect.y, rect.w, rect.h, text )
end

local function MyCompTextbox( dev, theme, name, rect, label )
	return dev:CreateTextbox( theme, name, rect.x, rect.y, rect.w, rect.h, label )
end

function DEV:InitializeOS( x, y, w, h )
	local R = UI.Rect( x, y, w, h )

	MyCompList( self, self.Th, "lstThemes", UI.Box( R, 0.325, 0.20, 0.30, 0.40 ) )
	for k, v in pairs( PCMod.Gui.Themes ) do
		self:AddListboxItem( "lstThemes", k, v.NiceName )
	end
	self:SetListboxSelRow( "lstThemes", self.Th )
	MyCompButton( self, self.Th, "btnSetTheme", UI.Box( R, 0.325, 0.63, 0.30, 0.07 ), "Apply Theme" )

	MyCompList( self, self.Th, "lstGuiScale", UI.Box( R, 0.66, 0.20, 0.30, 0.28 ) )
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
	MyCompButton( self, self.Th, "btnApplyScale", UI.Box( R, 0.66, 0.51, 0.30, 0.07 ), "Apply Scale" )

	MyCompTextbox( self, self.Th, "txtOldPass", UI.Box( R, 0.485, 0.81, 0.31, 0.055 ), "Old Password:" )
	MyCompTextbox( self, self.Th, "txtNewPass", UI.Box( R, 0.485, 0.89, 0.31, 0.055 ), "New Password:" )
	MyCompButton( self, self.Th, "btnApplyPass", UI.Box( R, 0.66, 0.81, 0.30, 0.07 ), "Change Password" )
	if (self.OldPassDraft) then self:SetTextboxText( "txtOldPass", self.OldPassDraft ) end
	if (self.NewPassDraft) then self:SetTextboxText( "txtNewPass", self.NewPassDraft ) end
end

function DEV:InitializeNetwork( x, y, w, h )
	local R = UI.Rect( x, y, w, h )
	local net = (type( self.Net ) == "table") and self.Net or {}

	MyCompList( self, self.Th, "lstNetInfo", UI.Box( R, 0.325, 0.21, 0.30, 0.62 ), true )

	// Right half: manual address settings (IPv4, netmask, gateway, MAC).
	MyCompTextbox( self, self.Th, "txtStaticIP", UI.Box( R, 0.80, 0.27, 0.26, 0.045 ), "IP:" )
	MyCompTextbox( self, self.Th, "txtNetmask", UI.Box( R, 0.80, 0.35, 0.26, 0.045 ), "Mask:" )
	MyCompTextbox( self, self.Th, "txtGateway", UI.Box( R, 0.80, 0.42, 0.26, 0.045 ), "Gateway:" )
	MyCompTextbox( self, self.Th, "txtMac", UI.Box( R, 0.80, 0.49, 0.26, 0.045 ), "MAC:" )
	MyCompButton( self, self.Th, "btnApplyNetwork", UI.Box( R, 0.7, 0.58, 0.205, 0.07 ), "Apply Network" )

	MyCompButton( self, self.Th, "btnRefreshNetwork", UI.Box( R, 0.325, 0.86, 0.145, 0.07 ), "Refresh" )
	MyCompButton( self, self.Th, "btnRenewNetwork", UI.Box( R, 0.48, 0.86, 0.145, 0.07 ), "Renew DHCP" )
	MyCompButton( self, self.Th, "btnNetTools", UI.Box( R, 0.63, 0.86, 0.335, 0.07 ), "Network Tools" )

	local ipVal = self.StaticIPDraft
	if (ipVal == nil) then ipVal = net.Static or net.IPv4 or "" end
	local maskVal = self.NetmaskDraft
	if (maskVal == nil) then maskVal = net.Mask or "" end
	local gwVal = self.GatewayDraft
	if (gwVal == nil) then gwVal = net.Gateway4 or "" end
	local macVal = self.MacDraft
	if (macVal == nil) then macVal = net.MAC or "" end
	self:SetTextboxText( "txtStaticIP", tostring( ipVal or "" ) )
	self:SetTextboxText( "txtNetmask", tostring( maskVal or "" ) )
	self:SetTextboxText( "txtGateway", tostring( gwVal or "" ) )
	self:SetTextboxText( "txtMac", tostring( macVal or "" ) )
end

function DEV:InitializeWifi( x, y, w, h )
	local R = UI.Rect( x, y, w, h )

	MyCompList( self, self.Th, "lstWireless", UI.Box( R, 0.325, 0.21, 0.35, 0.40 ), true )
	MyCompTextbox( self, self.Th, "txtWifiPass", UI.Box( R, 0.485, 0.66, 0.35, 0.055 ), "Password:" )
	MyCompButton( self, self.Th, "btnWifiConnect", UI.Box( R, 0.325, 0.73, 0.17, 0.07 ), "Connect" )
	MyCompButton( self, self.Th, "btnWifiDisconnect", UI.Box( R, 0.505, 0.73, 0.17, 0.07 ), "Disconnect" )
	MyCompButton( self, self.Th, "btnRefreshWifi", UI.Box( R, 0.325, 0.81, 0.35, 0.07 ), "Scan / Refresh" )
	if (self.WifiPassDraft) then self:SetTextboxText( "txtWifiPass", self.WifiPassDraft ) end
end

function DEV:InitializeIO( x, y, w, h )
	local R = UI.Rect( x, y, w, h )

	// The device list and the repeat settings share one content pane; keeping
	// the list box explicit preserves the existing layout exactly.
	MyCompList( self, self.Th, "lstDevices", UI.Box( R, 0.325, 0.20, 0.30, 0.55 ), true )

	MyCompTextbox( self, self.Th, "txtKeyRepeat", UI.Box( R, 0.81, 0.245, 0.30, 0.055 ), "Repeat (ms):" )
	MyCompTextbox( self, self.Th, "txtKeyHold", UI.Box( R, 0.81, 0.345, 0.30, 0.055 ), "Hold (ms):" )
	local rep = self.KeyRepeatDraft
	if (rep == nil) then rep = tostring( CurrentKeyRepeat() ) end
	local hold = self.KeyHoldDraft
	if (hold == nil) then hold = tostring( CurrentKeyHold() ) end
	self:SetTextboxText( "txtKeyRepeat", rep )
	self:SetTextboxText( "txtKeyHold", hold )
	MyCompButton( self, self.Th, "btnApplyKeyRepeat", UI.Box( R, 0.66, 0.43, 0.30, 0.07 ), "Apply Key Repeat" )
	MyCompButton( self, self.Th, "btnRefreshDevices", UI.Box( R, 0.325, 0.80, 0.30, 0.07 ), "Refresh Devices" )
	MyCompButton( self, self.Th, "btnDeviceManager", UI.Box( R, 0.66, 0.80, 0.30, 0.07 ), "Device Manager" )
end

function DEV:Initialize( x, y, w, h )
	local R = UI.Rect( x, y, w, h )

	self:CreateButton2( self.Th, "btnExit", R.x + R.w - (R.h * 0.06), R.y, R.h * 0.06, R.h * 0.06, "X" )

	// File Manager-style navigation: categories on the left, the active
	// category's settings and information in the larger right-hand pane.
	MyCompList( self, self.Th, "lstSections", UI.Box( R, 0.025, 0.16, 0.25, 0.76 ), true )
	self:AddListboxItem( "lstSections", "os", "Operating System" )
	self:AddListboxItem( "lstSections", "network", "Network" )
	self:AddListboxItem( "lstSections", "wifi", "Wi-Fi" )
	self:AddListboxItem( "lstSections", "io", "Input / Output" )
	if ((self.Section != "os") && (self.Section != "network") && (self.Section != "wifi") && (self.Section != "io")) then self.Section = "os" end
	self:SetListboxSelRow( "lstSections", self.Section )

	if (self.Section == "network") then
		self:InitializeNetwork( x, y, w, h )
	elseif (self.Section == "wifi") then
		self:InitializeWifi( x, y, w, h )
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
	self:AddListboxItem( "lstNetInfo", "mac", "MAC Address: " .. NetValue( net.MAC ) )
	self:AddListboxItem( "lstNetInfo", "ipv4", "IPv4 Address: " .. NetValue( net.IPv4 ) )
	self:AddListboxItem( "lstNetInfo", "static", "Static IP: " .. tostring( net.Static or "DHCP (auto)" ) )
	self:AddListboxItem( "lstNetInfo", "netmask", "Netmask: " .. NetValue( net.Mask ) )
	self:AddListboxItem( "lstNetInfo", "gateway4", "IPv4 Gateway: " .. NetValue( net.Gateway4 ) )
	self:AddListboxItem( "lstNetInfo", "ipv6", "IPv6 Address: " .. NetValue( net.IPv6 ) )
	self:AddListboxItem( "lstNetInfo", "prefix", "IPv6 Subnet: " .. NetValue( net.Prefix ) )
	self:AddListboxItem( "lstNetInfo", "gateway", "IPv6 Gateway: " .. NetValue( net.Gateway ) )
	self:AddListboxItem( "lstNetInfo", "linklocal", "Link-Local: " .. NetValue( net.LinkLocal ) )
	// Secondary addresses from other routers (multi-homed devices), unless the
	// per-interface list below already covers them.
	local ifaces = net.Interfaces or {}
	if (#ifaces == 0) then
		for i, a in ipairs( net.Extras or {} ) do
			self:AddListboxItem( "lstNetInfo", "alt" .. i, "Alt IPv4: " .. NetValue( a.IPv4 ) .. "  (" .. NetValue( a.IPv6 ) .. ")" )
		end
	end
	// One row per adapter. Both Ethernet ports are just interfaces; there is no
	// LAN/WAN role distinction.
	local eth = 0
	for i, a in ipairs( ifaces ) do
		local label
		if (a.Port == 0) then
			label = "wifi"
		else
			eth = eth + 1
			label = "eth " .. tostring( eth )
		end
		self:AddListboxItem( "lstNetInfo", "iface" .. i, label .. ": " .. NetValue( a.IPv4 ) .. "  (" .. NetValue( a.IPv6 ) .. ")" )
	end
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
			local name = "LAN Modem"
			if (w.Class == "pcmod_erouter") then name = "Router"
			elseif (w.Class == "pcmod_brouter") then name = "Backbone Router" end
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
		self:RenderText( x+(w*0.465), y+(h*0.105), { "Network Settings & Status" }, Color( 0, 0, 0, 255 ), 1 )
		self:RenderText( x+(w*0.465), y+(h*0.16), { "Status" }, Color( 0, 0, 0, 255 ), 1 )
		self:RenderText( x+(w*0.75), y+(h*0.16), { "Address Settings" }, Color( 0, 0, 0, 255 ), 1 )
		if (self.IPError && (self.IPError != "")) then
			self:RenderError( self.Th, x+(w*0.63), y+(h*0.68), self.IPError )
		elseif (self.IPNote && (self.IPNote != "")) then
			self:RenderText( x+(w*0.63), y+(h*0.68), { self.IPNote }, Color( 0, 0, 0, 255 ), 1 )
		end
	elseif (self.Section == "wifi") then
		self:RenderText( x+(w*0.465), y+(h*0.105), { "Wi-Fi" }, Color( 0, 0, 0, 255 ), 1 )
		self:RenderText( x+(w*0.465), y+(h*0.16), { "Wireless Networks" }, Color( 0, 0, 0, 255 ), 1 )
		local wf = self.Wifi
		local wstat = "Not connected."
		if (wf && wf.Connected) then
			local wname = "LAN Modem"
			if (wf.Class == "pcmod_erouter") then wname = "Router"
			elseif (wf.Class == "pcmod_brouter") then wname = "Backbone Router" end
			wstat = "Connected to " .. wname .. " #" .. tostring( wf.EntIndex )
			if (wf.NoIPv4) then wstat = wstat .. " (IPv6 only)" end
		elseif (wf && wf.BadPass) then
			wstat = "Incorrect password."
		elseif (wf && wf.Error) then
			wstat = tostring( wf.Error )
		end
		self:RenderText( x+(w*0.465), y+(h*0.90), { wstat }, Color( 0, 0, 0, 255 ), 1 )
	elseif (self.Section == "io") then
		self:RenderText( x+(w*0.6425), y+(h*0.105), { "Input / Output Devices" }, Color( 0, 0, 0, 255 ), 1 )
		self:RenderText( x+(w*0.475), y+(h*0.16), { "USB Devices" }, Color( 0, 0, 0, 255 ), 1 )
		self:RenderText( x+(w*0.81), y+(h*0.16), { "Keyboard Repeat" }, Color( 0, 0, 0, 255 ), 1 )
		if (self.KeyRepeatError) then
			self:RenderError( self.Th, x+(w*0.81), y+(h*0.60), self.KeyRepeatError )
		end
	else
		self:RenderText( x+(w*0.6425), y+(h*0.105), { "Operating System" }, Color( 0, 0, 0, 255 ), 1 )
		self:RenderText( x+(w*0.475), y+(h*0.15), { "Theme" }, Color( 0, 0, 0, 255 ), 1 )
		self:RenderText( x+(w*0.81), y+(h*0.15), { "GUI Scale" }, Color( 0, 0, 0, 255 ), 1 )
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
	if (btn == "btnApplyKeyRepeat") then
		local reps = self:GetTextboxText( "txtKeyRepeat" )
		local holds = self:GetTextboxText( "txtKeyHold" )
		self.KeyRepeatDraft = reps
		self.KeyHoldDraft = holds
		local rep = tonumber( reps )
		local hold = tonumber( holds )
		if ((!rep) || (!hold)) then
			self.KeyRepeatError = "Enter digits only"
		elseif ((rep < KEY_REPEAT_MIN) || (rep > KEY_REPEAT_MAX)) then
			self.KeyRepeatError = "Repeat: " .. KEY_REPEAT_MIN .. "-" .. KEY_REPEAT_MAX .. " ms"
		elseif ((hold < KEY_HOLD_MIN) || (hold > KEY_HOLD_MAX)) then
			self.KeyRepeatError = "Hold: " .. KEY_HOLD_MIN .. "-" .. KEY_HOLD_MAX .. " ms"
		else
			self.KeyRepeatError = nil
			if (keyboard && keyboard.SetLatency) then keyboard.SetLatency( rep ) end
			if (keyboard && keyboard.SetHoldTime) then keyboard.SetHoldTime( hold ) end
			RunConsoleCommand( "pc_keyrepeat", tostring( rep ) )
			RunConsoleCommand( "pc_keyhold", tostring( hold ) )
		end
		return
	end
	if (btn == "btnRefreshNetwork") then
		self.IPNote = nil
		self:RunProgCommand( "mycomputer", "refresh_network" )
		return
	end
	if (btn == "btnRenewNetwork") then
		self.IPNote = nil
		self.IPError = nil
		self:RunProgCommand( "mycomputer", "renew_network" )
		return
	end
	if (btn == "btnApplyNetwork") then
		self.IPNote = nil
		self.IPError = nil
		self.StaticIPDraft = self:GetTextboxText( "txtStaticIP" )
		self.NetmaskDraft = self:GetTextboxText( "txtNetmask" )
		self.GatewayDraft = self:GetTextboxText( "txtGateway" )
		self.MacDraft = self:GetTextboxText( "txtMac" )
		// A DHCP client whose box still shows the leased address stays on DHCP
		// unless the user actually typed a different (static) address.
		local ipSend = self.StaticIPDraft
		if ((type( self.Net ) == "table") && (!self.Net.Static) && (ipSend == self.Net.IPv4)) then
			ipSend = ""
		end
		self:RunProgCommand( "mycomputer", "set_network",
			ipSend or "", self.NetmaskDraft or "",
			self.GatewayDraft or "", self.MacDraft or "" )
		return
	end
	if (btn == "btnRefreshWifi") then
		self:RunProgCommand( "mycomputer", "refresh_wifi" )
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
