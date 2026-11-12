
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

function PROG:RefreshNetwork( keepNote )
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
	if (!keepNote) then self.DeviceData.IPNote = "" end
	self:RefreshWireless()
end

// Friendly name of a wireless network: the router's configured SSID when it
// has one, otherwise a class-based fallback.
function PROG:WirelessName( ent, data )
	data = data or ((ent && ent.Data && ent:Data()) or nil)
	if (data) then
		if (data.RouterCfg && data.RouterCfg.WireName) then return data.RouterCfg.WireName end
		if (data.WireName) then return data.WireName end
		local rdrv = PCMod.GetSubsystem && PCMod.GetSubsystem( data, "router" )
		if (rdrv && rdrv.GetCfg) then
			local cfg = rdrv:GetCfg()
			if (cfg && cfg.WireName) then return cfg.WireName end
		end
	end
	if ((ent) && (ent.GetClass)) then
		local cls = ent:GetClass()
		if (cls == "pcmod_erouter") then return "Router" end
		if (cls == "pcmod_brouter") then return "Backbone Router" end
	end
	return "LAN Modem"
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
					Name = self:WirelessName( ent, data ),
					Class = ent:GetClass(),
					EntIndex = ent:EntIndex(),
					Distance = dist,
					Signal = signal
				} )
			end
		end
	end
	// Strongest signal first; the distance is only used to derive the signal.
	table.sort( out, function( a, b )
		if (a.Signal != b.Signal) then return a.Signal > b.Signal end
		return tostring( a.Name ) < tostring( b.Name )
	end )
	self.DeviceData.Wireless = out
	self:RefreshWifiStatus()
end

// The PC's network subsystem (server-side).
function PROG:GetNetworkSubsystem()
	return PCMod.GetSubsystem && PCMod.GetSubsystem( PCMod.Data[ self.Entity:EntIndex() ], "network" )
end

// Router subsystems this computer is attached to: every reachable router
// behind its cable ports (following switches) plus the Wi-Fi router it joined.
function PROG:GetConnectedRouterSubsystems()
	local out = {}
	local seen = {}
	local function addRouter( ent )
		if ((!ent) || (!ent:IsValid())) then return end
		local d = PCMod.Data && PCMod.Data[ ent:EntIndex() ]
		local sub = PCMod.GetSubsystem && PCMod.GetSubsystem( d, "router" )
		if (sub && (!seen[ ent:EntIndex() ])) then
			seen[ ent:EntIndex() ] = true
			out[ #out + 1 ] = sub
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
	local net = self:GetNetworkSubsystem()
	if (net && net.WirelessEnt && net.WirelessEnt:IsValid()) then addRouter( net.WirelessEnt ) end
	return out
end

// Force a fresh DHCP lease. The device only broadcasts a discover; whichever
// router owns the interface it arrives on answers. The direct router walk
// remains for subsystems without DHCP support.
function PROG:RenewNetwork()
	local net = self:GetNetworkSubsystem()
	local renewed = 0
	if (net && net.DHCPDiscover) then
		net.LastDHCP = nil
		net:DHCPDiscover()
		if (net.LastDHCP) then renewed = 1 end
	else
		for _, sub in ipairs( self:GetConnectedRouterSubsystems() ) do
			if (sub.RenewLease && sub:RenewLease( self.Entity )) then renewed = renewed + 1 end
		end
	end
	// Keep the Wi-Fi status in step with whether we still have a lease.
	if (net && net.WirelessEnt && net.WirelessEnt:IsValid()) then
		local rdata = PCMod.Data[ net.WirelessEnt:EntIndex() ]
		local rdrv = rdata && PCMod.GetSubsystem && PCMod.GetSubsystem( rdata, "router" )
		if (net.DHCPByPort && net.DHCPByPort[ 0 ]) then
			// Asynchronous Wi-Fi DHCP: let the live context drive the status.
			net.WirelessIPv4 = nil
		elseif (rdrv && rdrv.HasLeaseForMAC) then
			local wmac = self.Entity.GetInterfaceMAC && self.Entity:GetInterfaceMAC( 0 )
			net.WirelessIPv4 = (wmac && rdrv:HasLeaseForMAC( "lan", wmac )) and true or false
		elseif (rdrv && rdrv.HasLease) then
			net.WirelessIPv4 = rdrv:HasLease( self.Entity ) and true or false
		end
	end
	self:RefreshNetwork()
	self.DeviceData.IPNote = (renewed > 0) and "Address renewed." or "No DHCP answer."
	self:UpdateSS()
end

// Cheap state fingerprint for asynchronous network changes (DHCP answers and
// interface leases arrive on a timer now that link latency is emulated).
function PROG:NetworkSignature()
	local parts = {}
	local net = self:GetNetworkSubsystem()
	local wifi = net && net.WirelessEnt
	if ((wifi) && (wifi:IsValid())) then
		parts[ #parts + 1 ] = "w:" .. tostring( wifi:EntIndex() )
		local wctx = net.DHCPByPort && net.DHCPByPort[ 0 ]
		local lease = wctx && (wctx.Lease or wctx.LastDHCP)
		parts[ #parts + 1 ] = tostring( lease && (lease.ip or lease.address) or "noip" )
	else
		parts[ #parts + 1 ] = "w:off"
	end
	local os = self:GetOS()
	if (os) then
		if (os.GetFullIP) then parts[ #parts + 1 ] = tostring( os:GetFullIP() ) end
		for _, a in ipairs( (os.GetInterfaces && os:GetInterfaces()) or {} ) do
			parts[ #parts + 1 ] = tostring( a.Port ) .. "=" .. tostring( a.IPv4 )
		end
	end
	return table.concat( parts, "|" )
end

function PROG:Think()
	if (!CurTime) then return end
	local now = CurTime()
	if (self.NextNetPoll && (now < self.NextNetPoll)) then return end
	self.NextNetPoll = now + 0.25
	local sig = self:NetworkSignature()
	if (sig == self.NetSig) then return end
	self.NetSig = sig
	self:RefreshNetwork( true )
	self:UpdateSS()
end

function PROG:RefreshWifiStatus()
	local net = self:GetNetworkSubsystem()
	if ((net) && (net.WirelessEnt) && (net.WirelessEnt:IsValid())) then
		// A DHCP answer over Wi-Fi is asynchronous once link latency is
		// emulated, so do not trust the snapshot taken at association time.
		// Look at the Wi-Fi interface context itself.
		local ipv4 = net.WirelessIPv4
		local wctx = net.DHCPByPort && net.DHCPByPort[ 0 ]
		if (wctx) then ipv4 = ((wctx.Lease != nil) || (wctx.LastDHCP != nil)) end
		self.DeviceData.Wifi = {
			Connected = true,
			Name = self:WirelessName( net.WirelessEnt ),
			EntIndex = net.WirelessEnt:EntIndex(),
			Class = net.WirelessEnt:GetClass(),
			NoIPv4 = (ipv4 == false)
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
	local net = self:GetNetworkSubsystem()
	if (!net) then
		self.DeviceData.Wifi = { Connected = false, Error = "No network hardware." }
		self:UpdateSS()
		return
	end
	net:DisconnectWireless()
	net.WirelessEnt = target
	net.WirelessPass = pass
	local rdata = PCMod.Data[ target:EntIndex() ]
	local rdrv = rdata && PCMod.GetSubsystem && PCMod.GetSubsystem( rdata, "router" )
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
	local net = self:GetNetworkSubsystem()
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
	self.NetSig = self:NetworkSignature()
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
