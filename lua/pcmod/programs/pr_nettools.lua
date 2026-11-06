
// Net-Tools Program for PCMod 2 \\

PROG.Name = "nettools"
PROG.Author = "[GU]thomasfn"
PROG.Title = "Net-Tools"
PROG.Icon = "app"
PROG.OS = "personal"

PROG.SimpleMode = true
PROG.NoShortcut = true

PROG.DeviceLink = "window_nettools"
PROG.DeviceName = "window_nettools"
PROG.DeviceData = {}

PROG.Pinging = false
PROG.P_TimeOut = 0

PROG.Tracing = false
PROG.T_TimeOut = 0

function PROG:DoCommand( com, args )
	if (com == "exit") then
		self:GetOS():RunCommand( "sys_openprog mycomputer" )
		self:Exit()
		return
	end
	if (com == "ip") then
		local os = self:GetOS()
		local ipv4 = os:GetIP()
		if (os.GetFullIP) then
			local full = os:GetFullIP()
			if (full) then ipv4 = full end
		end
		self.DeviceData.St = "IPv4: " .. tostring( ipv4 )
		self.DeviceData.IP = "IPv6: " .. tostring( os:GetIPv6() or "none" )
		local subnet = "Subnet: " .. tostring( os:GetIPv6Prefix() or "none" )
		// Secondary addresses: one per extra router this device is linked to.
		local alts = {}
		if (os.GetExtraAddresses) then
			for _, a in ipairs( os:GetExtraAddresses() ) do
				alts[ #alts + 1 ] = a.IPv4
			end
		end
		if (#alts > 0) then subnet = subnet .. " | Alt: " .. table.concat( alts, ", " ) end
		self.DeviceData.Tg = subnet
		self:UpdateSS()
		return
	end
	if (com == "ping") then
		if ((args[1]) && (PCMod.IPv6.IsIP( args[1] ))) then
			self:Ping( args[1] )
		end
	end
	if (com == "trace") then
		if ((args[1]) && (PCMod.IPv6.IsIP( args[1] ))) then
			self:Trace( args[1] )
		end
	end
end

function PROG:OnEnd()
	self.Pinging = false
	self.Tracing = false
end

function PROG:MessageFailed( hdl, code, data )
	local ip, port = hdl[1], hdl[2]
	local statcode = 0
	if (code == "netPortClosed") then statcode = 25 end
	if (code == "netPortLocked") then statcode = 26 end
	if (port == 0) then
		if (data[1] == "netPing") then
			if (!self.Pinging) then return end
			self.DeviceData.St = statcode
			self.DeviceData.IP = ip
			self.DeviceData.Tg = ""
			self:UpdateSS()
			self.P_TimeOut = 0
			self.Pinging = false
		end
		if (data[1] == "netTrace") then
			if (!self.Tracing) then return end
			self.DeviceData.St = statcode
			self.DeviceData.IP = ip
			self.DeviceData.Tg = ""
			self:UpdateSS()
			self.T_TimeOut = 0
			self.Tracing = false
		end
	end
end

function PROG:Ping( target )
	// if (self.Pinging) then return end
	// if (self.Tracing) then return end
	self.DeviceData.St = 21 -- Waiting for response...
	self.DeviceData.IP = target
	self.DeviceData.Tg = ""
	self:UpdateSS()
	self.P_TimeOut = CurTime()+5
	self.Pinging = true
	self:GetOS():NetPing( target, "nettools" )
end

function PROG:Trace( target )
	// if (self.Pinging) then return end
	// if (self.Tracing) then return end
	self.DeviceData.St = 21 -- Waiting for response...
	self.DeviceData.IP = target
	self.DeviceData.Tg = ""
	self.DeviceData.Tr = {}
	self:UpdateSS()
	self.T_TimeOut = CurTime()+5
	self.Tracing = true
	self:GetOS():NetTrace( target, "nettools" )
end

function PROG:PingSuccess( ip, tag )
	if (!self.Pinging) then return end
	self.DeviceData.St = 20 -- Pinged succesfully!
	self.DeviceData.IP = ip
	self.DeviceData.Tg = tag
	self:UpdateSS()
	self.P_TimeOut = 0
	self.Pinging = false
end

function PROG:TraceSuccess( ip, trace )
	if (!self.Tracing) then return end
	self.DeviceData.St = 23 -- Traced succesfully!
	self.DeviceData.IP = ip
	self.DeviceData.Tg = ""
	self.DeviceData.Tr = trace
	self:UpdateSS()
	self.T_TimeOut = 0
	self.Tracing = false
end

function PROG:Think()
	if (self.Pinging) then
		if (CurTime() > self.P_TimeOut) then
			self.P_TimeOut = 0
			self.Pinging = false
			self.DeviceData.St = 22 -- Timed out
			self.DeviceData.IP = ""
			self.DeviceData.Tg = ""
			self:UpdateSS()
		end
	end
	if (self.Tracing) then
		if (CurTime() > self.T_TimeOut) then
			self.T_TimeOut = 0
			self.Tracing = false
			self.DeviceData.St = 24 -- Timed out
			self.DeviceData.IP = ""
			self.DeviceData.Tg = ""
			self:UpdateSS()
		end
	end
end