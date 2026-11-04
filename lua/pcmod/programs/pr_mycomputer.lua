
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
	self.DeviceData.Net = {
		IPv4 = ipv4,
		IPv6 = os:GetIPv6(),
		Prefix = os:GetIPv6Prefix(),
		Gateway = os:GetIPv6Gateway(),
		LinkLocal = os:GetIPv6LinkLocal()
	}
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
		ets = ents.FindByClass( "pcmod_router" )
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
	local expected = tdata.WirePass or "123"
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
	if (reg == "assigned") then net.WirelessIPv4 = true end
	if (reg == "full") then net.WirelessIPv4 = false end
	self:RefreshNetwork()
	self:UpdateSS()
end

function PROG:DisconnectWireless()
	local net = self:GetNetworkDriver()
	if (net && net.DisconnectWireless) then net:DisconnectWireless() end
	self.DeviceData.Wifi = { Connected = false }
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
