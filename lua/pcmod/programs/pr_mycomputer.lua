
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
