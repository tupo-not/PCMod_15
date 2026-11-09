
// Control Panel Program for PCMod 2 \\
// Internal name remains mycomputer for existing installs and program commands.

PROG.Name = "mycomputer"
PROG.Author = "[GU]thomasfn"
PROG.Title = "Control Panel"
PROG.Icon = "app"
PROG.OS = "personal"

PROG.SimpleMode = true

PROG.DeviceLink = "window_mycomp"
PROG.DeviceName = "window_mycomp"
PROG.DeviceData = {}

function PROG:RefreshNetwork()
	local os = self:GetOS()
	if (!os) then return end
	local ipv4 = os:GetIP()
	if (os.GetFullIP) then
		local full = os:GetFullIP()
		if (full) then ipv4 = full end
	end
	local static = nil
	local selfEnt = self.Entity
	local ipdata = (selfEnt && selfEnt.Data && selfEnt:Data() && selfEnt:Data().IP) or nil
	if (ipdata && ipdata.Static) then static = ipdata.Static end
	// A host attached straight to a backbone has only a WAN identity, so the
	// LAN /64 accessors are empty. Fall back to the backbone IPv6 fields.
	local v6 = os:GetIPv6()
	local v6prefix = os:GetIPv6Prefix()
	local v6gw = os:GetIPv6Gateway()
	local v6ll = os:GetIPv6LinkLocal()
	if ((!v6) && os.GetBIPv6) then
		v6 = os:GetBIPv6()
		if (os.GetBIPv6Prefix) then v6prefix = os:GetBIPv6Prefix() end
		if (os.GetBIPv6Gateway) then v6gw = os:GetBIPv6Gateway() end
		if (os.GetBIPv6LinkLocal) then v6ll = os:GetBIPv6LinkLocal() end
	end
	self.DeviceData.Net = {
		MAC = os:GetMAC(),
		IPv4 = ipv4,
		Static = static,
		Mask = ipdata && ipdata.Mask or nil,
		MaskBits = ipdata && ipdata.MaskBits or nil,
		Gateway4 = ipdata && ipdata.Gateway or nil,
		IPv6 = v6,
		Prefix = v6prefix,
		Gateway = v6gw,
		LinkLocal = v6ll,
		Extras = (os.GetExtraAddresses && os:GetExtraAddresses()) or {},
		Interfaces = (os.GetInterfaces && os:GetInterfaces()) or {}
	}
	self.DeviceData.IPNote = ""
	self:RefreshWireless()
end

// Scan for wireless routers this computer could reach. The PC itself links to
// a router by cable; these are the nearby Wi-Fi networks it is in range of.
function PROG:RefreshWireless()
	local selfEnt = self.Entity
	if ((!selfEnt) || (!selfEnt:IsValid())) then self.DeviceData.Wireless = {} return end
	local range = (PCMod.Cfg && PCMod.Cfg.WirelessRange) || 0
	local ets
	if (range > 0) then
		ets = ents.FindInSphere( selfEnt:GetPos(), range )
	else
		ets = {}
		for _, cls in ipairs( { "pcmod_router", "pcmod_erouter" } ) do
			for _, ent in ipairs( ents.FindByClass( cls ) or {} ) do
				table.insert( ets, ent )
			end
		end
	end
	local out = {}
	for _, ent in pairs( ets or {} ) do
		if ((ent) && (ent != selfEnt) && (ent:IsValid()) && (ent.IsPCMod)) then
			local data = (ent.Data && ent:Data()) or nil
			if (data && data.IsWireless) then
				local dist = math.floor( (ent:GetPos() - selfEnt:GetPos()):Length() + 0.5 )
				local signal = 100
				if (range > 0) then signal = math.max( 0, math.floor( (1 - (dist / range)) * 100 ) ) end
				table.insert( out, {
					Class = ent:GetClass(),
					EntIndex = ent:EntIndex(),
					Distance = dist,
					Signal = signal
				} )
			end
		end
	end
	table.sort( out, function( a, b ) return (a.Distance < b.Distance) end )
	self.DeviceData.Wireless = out
	self:RefreshWifiStatus()
end

// The PC's network driver (server-side).
function PROG:GetNetworkDriver()
	local data = PCMod.Data[ self.Entity:EntIndex() ]
	if (!data || !data.Drivers) then return nil end
	return data.Drivers[ "gen_network" ]
end

// Router drivers this computer is attached to: every reachable router behind
// its cable ports (following switches) plus the Wi-Fi router it joined.
function PROG:GetConnectedRouterDrivers()
	local out = {}
	local seen = {}
	local function addRouter( ent )
		if ((!ent) || (!ent:IsValid())) then return end
		local d = PCMod.Data && PCMod.Data[ ent:EntIndex() ]
		local drv = d && d.Drivers && d.Drivers[ "webgr_router" ]
		if (drv && (!seen[ ent:EntIndex() ])) then
			seen[ ent:EntIndex() ] = true
			out[ #out + 1 ] = drv
		end
	end
	local function walk( ent, depth )
		if ((!ent) || (!ent:IsValid()) || (depth > 8)) then return end
		if (seen[ "e" .. ent:EntIndex() ]) then return end
		seen[ "e" .. ent:EntIndex() ] = true
		if (ent.IsSwitch) then
			local ports = (ent.Ports && ent:Ports()) or {}
			for _, port in pairs( ports ) do
				if (port && port.Connected && port.ConEnt) then walk( port.ConEnt, depth + 1 ) end
			end
		else
			addRouter( ent )
		end
	end
	local selfEnt = self.Entity
	if (selfEnt && selfEnt.Ports) then
		for _, port in pairs( selfEnt:Ports() ) do
			if (port && port.Connected && port.ConEnt) then walk( port.ConEnt, 0 ) end
		end
	end
	local net = self:GetNetworkDriver()
	if (net && net.WirelessEnt && net.WirelessEnt:IsValid()) then addRouter( net.WirelessEnt ) end
	return out
end

// Force a fresh DHCP lease. The device only broadcasts a discover; whichever
// router owns the interface it arrives on answers. The old router-walking
// fallback remains for drivers without DHCP support (older clients/mocks).
function PROG:RenewNetwork()
	local net = self:GetNetworkDriver()
	local renewed = 0
	if (net && net.DHCPDiscover) then
		net.LastDHCP = nil
		net:DHCPDiscover()
		if (net.LastDHCP) then renewed = 1 end
	else
		for _, drv in ipairs( self:GetConnectedRouterDrivers() ) do
			if (drv.RenewLease && drv:RenewLease( self.Entity )) then renewed = renewed + 1 end
		end
	end
	// Keep the Wi-Fi status in step with whether we still have a lease.
	if (net && net.WirelessEnt && net.WirelessEnt:IsValid()) then
		local rdata = PCMod.Data[ net.WirelessEnt:EntIndex() ]
		local rdrv = rdata && rdata.Drivers && rdata.Drivers[ "webgr_router" ]
		net.WirelessIPv4 = (rdrv && rdrv.HasLease && rdrv:HasLease( self.Entity )) and true or false
	end
	self:RefreshNetwork()
	self.DeviceData.IPNote = (renewed > 0) and "Address renewed." or "No DHCP answer."
	self:UpdateSS()
end

function PROG:RefreshWifiStatus()
	local net = self:GetNetworkDriver()
	if ((net) && (net.WirelessEnt) && (net.WirelessEnt:IsValid())) then
		self.DeviceData.Wifi = {
			Connected = true,
			EntIndex = net.WirelessEnt:EntIndex(),
			Class = net.WirelessEnt:GetClass(),
			NoIPv4 = (net.WirelessIPv4 == false)
		}
	else
		self.DeviceData.Wifi = { Connected = false }
	end
end

// Connect this computer to a wireless router, checking its Wi-Fi password
// (each router is created with the default "123").
function PROG:ConnectWireless( entIndex, pass )
	if (!entIndex) then return end
	pass = pass or ""
	local target = ents.GetByIndex( entIndex )
	if ((!target) || (!target:IsValid()) || (!target.IsPCMod)) then
		self.DeviceData.Wifi = { Connected = false, Error = "Network unavailable." }
		self:UpdateSS()
		return
	end
	local tdata = target.Data && target:Data() or nil
	if ((!tdata) || (!tdata.IsWireless)) then
		self.DeviceData.Wifi = { Connected = false, Error = "Network unavailable." }
		self:UpdateSS()
		return
	end
	local expected = (tdata.RouterCfg && tdata.RouterCfg.WirePass) or tdata.WirePass or "123"
	if (pass != expected) then
		self.DeviceData.Wifi = { Connected = false, BadPass = true }
		self:UpdateSS()
		return
	end
	local net = self:GetNetworkDriver()
	if (!net) then
		self.DeviceData.Wifi = { Connected = false, Error = "No network hardware." }
		self:UpdateSS()
		return
	end
	net:DisconnectWireless()
	net.WirelessEnt = target
	net.WirelessPass = pass
	local rdata = PCMod.Data[ target:EntIndex() ]
	local rdrv = rdata && rdata.Drivers && rdata.Drivers[ "webgr_router" ]
	local reg = (rdrv && rdrv.AddWirelessClient) && rdrv:AddWirelessClient( self.Entity )
	if ((!reg) || (reg == "invalid")) then
		net.WirelessEnt = nil
		net.WirelessPass = ""
		net.WirelessIPv4 = nil
		self.DeviceData.Wifi = { Connected = false, Error = "Network unavailable." }
		self:UpdateSS()
		return
	end
	// "full" still connects, but the client has no IPv4 lease (IPv6-only),
	// exactly like a real DHCP server that runs out of addresses.
	if (net.DHCPDiscover && PCMod.DHCPServer) then
		// Association is auth/range only. Addressing over Wi-Fi is DHCP, just
		// like a cable: ask, and the router serving this link answers.
		net.LastDHCP = nil
		net:DHCPDiscover()
		// Wi-Fi has its own interface state; report that lease, not any wired one.
		local wctx = net.DHCPByPort && net.DHCPByPort[ 0 ]
		net.WirelessIPv4 = (wctx && (wctx.LastDHCP != nil)) or ((!wctx) && (net.LastDHCP != nil))
	else
		// Older clients/routers without DHCP still report the association result.
		if (reg == "assigned") then net.WirelessIPv4 = true end
		if (reg == "full") then net.WirelessIPv4 = false end
	end
	self:RefreshNetwork()
	self:UpdateSS()
end

function PROG:DisconnectWireless()
	local net = self:GetNetworkDriver()
	if (net && net.DisconnectWireless) then net:DisconnectWireless() end
	// With the wireless link gone a cable may be the only path; ask for an
	// address again instead of keeping a lease that was released.
	if (net && net.DHCPDiscover) then
		net.LastDHCP = nil
		net:DHCPDiscover()
	end
	self.DeviceData.Wifi = { Connected = false }
	self:RefreshNetwork()
	self:UpdateSS()
end

function PROG:RefreshDevices()
	local os = self:GetOS()
	if (!os) then return end
	os:RefreshUSBData()
	local devs = os:GetUSBDevicePorts( "all" ) or {}
	local tmp = {}
	for _, port in pairs( devs ) do
		local pd = os:GetUSBData( port )
		if (pd && pd.HasIdent) then
			table.insert( tmp, { port, pd.DeviceType or "Unknown device" } )
		end
	end
	self.DeviceData.Dvs = tmp
end

function PROG:OnStart()
	self:RefreshNetwork()
	self:RefreshDevices()
end

function PROG:DoCommand( com, args )
	if (com == "exit") then
		self:Exit()
		return
	end
	if (com == "changepass") then
		local oldpass = args[1]
		if (!oldpass) then return end
		local newpass = args[2]
		if (!newpass) then return end
		local apass = PCMod.Data[ self.Entity:EntIndex() ].Password
		if ((!apass) || (oldpass == apass) || (apass == "")) then
			PCMod.Data[ self.Entity:EntIndex() ].Password = newpass
			self.DeviceData.PWE = 2
			self:UpdateSS()
		else
			self.DeviceData.PWE = 1
			self:UpdateSS()
		end
		return
	end
	if (com == "refresh_network") then
		self:RefreshNetwork()
		self:UpdateSS()
		return
	end
	if (com == "renew_network") then
		self:RenewNetwork()
		return
	end
	if (com == "refresh_wifi") then
		self:RefreshWireless()
		self:UpdateSS()
		return
	end
	if (com == "set_static_ip") then
		local addr = args[1]
		local applied = false
		if (self.Entity && self.Entity.SetStaticIP) then
			applied = (self.Entity:SetStaticIP( addr ) == true)
		end
		if (!applied) then
			self.DeviceData.IPError = "Invalid static IP - use 10.x, 172.16-31.x or 192.168.x"
		else
			self.DeviceData.IPError = ""
		end
		self:RefreshNetwork()
		self:UpdateSS()
		return
	end
	if (com == "set_network") then
		local ip = args[1] or ""
		local mask = args[2] or ""
		local gw = args[3] or ""
		local mac = args[4] or ""
		local ok, err = false, "Network configuration unavailable"
		if ((mac == "") || (PCMod.MAC && PCMod.MAC.IsValid( mac ))) then
			if (self.Entity && self.Entity.SetNetworkConfig) then
				ok, err = self.Entity:SetNetworkConfig( ip, mask, gw )
			end
			if (ok && (mac != "")) then
				if (!(self.Entity && self.Entity.SetMAC && self.Entity:SetMAC( mac ))) then
					ok, err = false, "Invalid MAC address"
				end
			end
		else
			err = "Invalid MAC address"
		end
		self.DeviceData.IPError = ok and "" or (err or "Invalid network settings")
		self:RefreshNetwork()
		self:UpdateSS()
		return
	end
	if (com == "connect_wifi") then
		self:ConnectWireless( tonumber( args[1] ), args[2] )
		return
	end
	if (com == "disconnect_wifi") then
		self:DisconnectWireless()
		return
	end
	if (com == "refresh_devices") then
		self:RefreshDevices()
		self:UpdateSS()
		return
	end
	if (com == "open_devman") then
		self:GetOS():RunCommand( "sys_openprog deviceman" )
		return
	end
	if (com == "open_nettools") then
		self:GetOS():RunCommand( "sys_openprog nettools" )
	end
end
