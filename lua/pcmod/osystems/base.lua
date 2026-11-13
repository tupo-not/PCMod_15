
OS.IntName = "baseos"
OS.ExtName = "Base OS"

OS.Version = "1.0.0"
OS.USBDevices = {}

OS.NetPorts = {}
OS.TraceRouteData = {}

// Simulated wall-clock seconds for RTT measurement. The mock suites do not
// provide CurTime, so fall back to a monotonic zero rather than erroring.
// Latency.Now() adds sub-tick cable/fibre delays, which are delivered in the
// same tick but still count toward the reported hop RTT.
local function NowSeconds()
	if (PCMod.Latency && PCMod.Latency.Now) then return PCMod.Latency.Now() end
	if (CurTime) then return CurTime() end
	if (RealTime) then return RealTime() end
	return 0
end

local function ElapsedMs( since )
	local ms = math.floor( ((NowSeconds() - (since or 0)) * 1000) + 0.5 )
	if (ms < 0) then ms = 0 end
	return ms
end

util.AddNetworkString("programyolla")

function OS:Print( txt )
	self:Bios():AddStatusText( "]> " .. txt )
end

function OS:Bios()
	local ent = self.Entity
	if ((!ent) || (!ent:IsValid())) then return end
	return PCMod.Data[ ent:EntIndex() ].Subsystems[ "bios" ]
end

function OS:Display()
	local ent = self.Entity
	if ((!ent) || (!ent:IsValid())) then return end
	return PCMod.Data[ ent:EntIndex() ].Subsystems[ "display" ]
end

function OS:Sound()
	local ent = self.Entity
	if ((!ent) || (!ent:IsValid())) then return end
	return PCMod.Data[ ent:EntIndex() ].Subsystems[ "sound" ]
end

function OS:USB()
	local ent = self.Entity
	if ((!ent) || (!ent:IsValid())) then return end
	return PCMod.Data[ ent:EntIndex() ].Subsystems[ "usb" ]
end

function OS:Network()
	local ent = self.Entity
	if ((!ent) || (!ent:IsValid())) then return end
	return PCMod.Data[ ent:EntIndex() ].Subsystems[ "network" ]
end

function OS:RequestControl()
	return self:Bios():SetState( 7 )
end

function OS:FirstRun()
	local ent = self.Entity
	if ((!ent) || (!ent:IsValid())) then return end
	local fl = ent:ReadFile( "system/firstrun.sys" )
	if ((!fl) || (fl == "")) then return false end
	if (fl == "1") then return true end
end

function OS:RegisterRun()
	local ent = self.Entity
	if ((!ent) || (!ent:IsValid())) then return end
	ent:UnlinkItem( "system/firstrun.sys" )
end

// Sets up the folders every PCMod OS needs. The OS-specific folder (mydocs/
// for a personal computer, serverfiles/ for a server) is passed in by the
// concrete OS so this shared code is not duplicated in os_personal/os_server.
function OS:SetupDataFolders( datafolder )
	local ent = self.Entity
	if ((!ent) || (!ent:IsValid())) then return end
	ent:LinkFolder( "system/data/" )
	ent:LockItem( "system/data/" )
	if (datafolder) then
		ent:LinkFolder( datafolder )
	end
end

function OS:SaveData()
	self.Entity:WriteFile( "system/data/pcdata.dat", PCMod.TableToString( self.PCData ) )
end

function OS:LoadData()
	// Round 29 (M-05): the file does not exist yet before the first run
	// wizard is finished - StringToTable("") returns nil and every later
	// access to self.PCData (e.g. in BuildDesktop) raised
	// "attempt to index a nil value (field 'PCData')".
	self.PCData = PCMod.StringToTable( self.Entity:ReadFile( "system/data/pcdata.dat" ) ) or {}
end

function OS:SetState( st )
	self.State = st
	self.NUpdate = 0
	self:TriggerUpdate( st )
end

// Scale a boot/shutdown delay by cfg.BootSpeed. Runtime changes to
// PCMod.Cfg.BootSpeed (e.g. from the settings panel) take effect immediately.
function OS:BootDelay( seconds )
	local scale = 1
	if (PCMod.Cfg && (PCMod.Cfg.BootSpeed != nil)) then
		scale = tonumber( PCMod.Cfg.BootSpeed )
		if (!scale) then scale = 1 end
	end
	if (scale < 0.05) then scale = 0.05 end
	if (scale > 4) then scale = 4 end
	return seconds * scale
end

function OS:DelayUpdate( amount )
	self.NUpdate = CurTime() + self:BootDelay( amount )
end

function OS:Launch()
	self.Mode = "bios"
	self.NUpdate = 0
	self.State = 0
	PCMod.Msg( "Launching " .. self.ExtName .. "...", true )
	self:Boot()
end

function OS:Boot()
	if (self.Mode == "bios") then
		self:DelayUpdate( 0 )
		self:Tick()
	end
end

function OS:Tick()
	if (self.NUpdate == 0) then return end
	if (CurTime() > self.NUpdate) then
		self:SetState( self.State + 1 )
	end
	for k, v in pairs( self.Progs ) do
		self.Progs[ k ]:Tick()
	end
end

function OS:InstallProgram( progname, setup )
	if ((self.State != 10) && (!setup)) then return "Installation denied!" end
	if (!PCMod.Progs[ progname ]) then
		PCMod.Msg( "Tried to install invalid program! (" .. progname .. ")", true )
		return "Installation invalid!"
	end
	local pr = PCMod.Progs[ progname ]
	if ((self.Progs[ progname ]) && (!setup)) then
		PCMod.Msg( "Tried to install already present program! (" .. progname .. ")", true )
		return "Program already installed!"
	end
	self.Progs[ progname ] = table.Copy( pr )
	if (!self.Progs[ progname ]:CanUse()) then
		PCMod.Msg( "Removed program '" .. progname .. "', flagged as unusable!", true )
		self.Progs[ progname ] = nil
		return "Installation denied!"
	end
	if (self.Progs[ progname ].OS != self.IntName) then
		PCMod.Msg( "Removed program '" .. progname .. "', flagged as invalid os!", true )
		self.Progs[ progname ] = nil
		return "Wrong operating system!"
	end
	PCMod.Msg( "Installed program '" .. progname .. "')", true )
	self.Progs[ progname ].Entity = self.Entity
	self.Progs[ progname ]:OnInstall()
	return true
end

function OS:LaunchProgram( progname )
	if (!self.Progs[ progname ]) then return false end
	PCMod.Progs[ progname ].Entity = self.Entity
	return PCMod.Progs[ progname ]:Start()
end

function OS:ShutDown()
	// Closing programs is only part of a shutdown. Net ports and in-flight
	// traceroute handles are runtime state too; leaving them behind made a
	// powered-off machine keep answering on an open port until it rebooted.
	for k, v in pairs( self.Progs or {} ) do
		if (v && v.Exit) then v:Exit() end
	end
	self.Progs = {}
	self.NetPorts = {}
	self.TraceRouteData = {}
	self.State = 0
	self.NUpdate = 0
	self.Mode = nil
end

function OS:GetAllProgs()
	// On a fresh install the file is empty, StringToTable returns nil and
	// net.WriteTable(nil) errors - Broadcast and the return were both skipped.
	local ps = PCMod.StringToTable( self.Entity:ReadFile( "system/data/allprogs.dat" ) ) or {}
	// Round 31 (M-50): the program list used to go to EVERY client
	// (net.Broadcast) - so every player on the server could read the program
	// list of every PC. Now only the players that can actually see the
	// machine get it.
	for _, v in pairs( PCMod.Beam.NearPlayers( self.Entity ) ) do
		net.Start("programyolla")
			net.WriteEntity(self.Entity)
			net.WriteTable(ps)
		net.Send( v )
	end

	return ps
end

function OS:SetAllProgs( ps )
	self.Entity:WriteFile( "system/data/allprogs.dat", PCMod.TableToString( ps ) )
end

// Rebuild the runtime program instances from the saved start-menu list. A
// booted OS is a fresh copy of the prototype, so allprogs.dat holds the
// desktop shortcuts but not the live programs: without this a duplicated PC
// (or any PC recreated by a map load) shows shortcuts whose sys_openprog finds
// nothing to start. OnInstall is intentionally not called again - it would add
// duplicate shortcuts to the already-saved list.
function OS:LoadPrograms()
	self.Progs = self.Progs or {}
	local ps = PCMod.StringToTable( self.Entity:ReadFile( "system/data/allprogs.dat" ) ) or {}
	for _, entry in ipairs( ps ) do
		local com = (type( entry ) == "table") && entry[ 3 ]
		if (type( com ) == "string") then
			local name = string.match( com, "^sys_openprog%s+(.+)$" ) or com
			local pr = PCMod.Progs[ name ]
			if ((type( pr ) == "table") && (pr.OS == self.IntName) && (!self.Progs[ name ])) then
				local inst = table.Copy( pr )
				inst.Entity = self.Entity
				if (inst.CanUse && inst:CanUse()) then
					self.Progs[ name ] = inst
				end
			end
		end
	end
	// Programs flagged NoShortcut are not in allprogs.dat (they are launched
	// from the Control Panel, e.g. Network Tools and Device Manager), but they
	// still have to exist at run time. Reinstall the ones for this OS.
	for name, pr in pairs( PCMod.Progs ) do
		if ((type( pr ) == "table") && (pr.OS == self.IntName) && (pr.NoShortcut == true) && (!self.Progs[ name ])) then
			local inst = table.Copy( pr )
			inst.Entity = self.Entity
			if (inst.CanUse && inst:CanUse()) then
				self.Progs[ name ] = inst
			end
		end
	end
end

function OS:AddProg( icon, dispname, com )
	PCMod.Msg( "Adding prog: " .. icon ..", " .. dispname .. ", " .. com, true )
	local ps = self:GetAllProgs()
	table.insert( ps, { icon, dispname, com } )
	self:SetAllProgs( ps )
end

function OS:RefreshUSBData()
	self:USB():RetrievePortData()
end

function OS:GetUSBDevicePorts( devname )
	return self:USB():FindDevices( devname )
end

function OS:SendUSBData( port, data )
	self:USB():SendDeviceData( port, data )
end

function OS:GetUSBData( port )
	return self:USB():GetDevice( port )
end

function OS:OpenNetPort( portid, dest, destid )
	if (!self:ValidatePortID( portid )) then return end
	if (self:NetPortOpen( portid )) then return end
	local tmp = {}
	tmp.PortID = portid
	tmp.Dest = dest
	tmp.DestID = destid
	tmp.Locked = false -- Locked means block all incoming but allow outgoing
	self.NetPorts[ portid ] = tmp
end

function OS:CloseNetPort( portid )
	if (!self:ValidatePortID( portid )) then return end
	if (!self:NetPortOpen( portid )) then return end
	self.NetPorts[ portid ] = nil
end

function OS:NetPortOpen( portid )
	if (!self:ValidatePortID( portid )) then return false end
	if (self.NetPorts[ portid ]) then return true end
	return false
end

function OS:SetPortLock( portid, lock )
	if (!self:NetPortOpen( portid )) then return end
	self.NetPorts[ portid ].Locked = (lock == true)
end

function OS:ValidatePortID( portid )
	if (!portid) then return false end
	if (type( portid ) != "number") then return false end
	if ((portid<0) || (portid>5000)) then return false end
	return true
end

function OS:NetDataRecieved( packet )
	if (!packet) then return end
	if (type( packet ) != "table") then return end
	local pt = packet.Port
	if (!pt) then return end
	local dat = packet.Body
	if (!dat) then return end
	// handle[3] = the local address the packet was addressed to, so replies
	// can be sourced from that identity (multi-homed devices). handle[4] =
	// whether it arrived over Wi-Fi, so the reply leaves on the same link.
	local hdl = { packet.Source, packet.SourcePort or packet.Port, packet.Dest, packet.ViaWireless == true }
	if (!self:NetPortOpen( pt )) then
		self:ReplyNetMessage( hdl, { "netPortClosed", dat } )
		return
	end
	local port = self.NetPorts[ pt ]
	if (port.Locked) then
		self:ReplyNetMessage( hdl, { "netPortLocked", dat } )
		return
	end
	if (port.Dest == "osbase") then self:ProcessPacket( pt, dat, hdl ) end
	if (port.Dest == "prog") then
		// Round 34 (M-28): the program of the port may not exist (anymore)
		local prog = self.Progs[ port.DestID ]
		if (prog) then prog:ProcessPacket( pt, dat, hdl ) end
	end
end

function OS:LinkNetPorts()
	self:OpenNetPort( 0, "osbase", nil ) -- Ping / Traceroute
end

function OS:UnlinkNetPorts()
	self:CloseNetPort( 0 )
end

function OS:ProcessPacket( pt, dat, handle )
	if ((dat[1] == "netPortClosed") || (dat[1] == "netPortLocked")) then
		local olddat = dat[2]
		// Olddat is the data we sent
		local hk = olddat[2]
		if (hk) then
			if (hk == "os") then
				self:MessageFailed( handle, dat[1], olddat )
			else
				if (self.Progs[ hk ]) then self.Progs[ hk ]:MessageFailed( handle, dat[1], olddat ) end
			end
		end
	end
	if (pt == 0) then
		// We have been pinged / tracerouted!
		PCMod.Msg( "OS BASE: " .. dat[1], true )
		if (dat[1] == "netPing") then self:ReplyNetMessage( handle, { "netPingResponse", dat[2], "Computer Tower OS" } ) end
		if (dat[1] == "netPing_DEBUG") then
			PCMod.Msg( "==] 'netPing_DEBUG' has been recieved! (OS BASE, ent " .. self.Entity:EntIndex() .. ")" )
			if (dat[2]) then dat[2]:Say( "Ping was recieved! (OS BASE, ent " .. self.Entity:EntIndex() .. ")" ) end
		end
		if (dat[1] == "netTrace") then self:ReplyNetMessage( handle, { "netTraceResponse", dat[2], dat[3], "Computer Tower OS" } ) end
		if (dat[1] == "netPingResponse") then
			local hk = dat[2]
			if (hk) then
				if (hk == "os") then
					self:PingSuccess( handle[1] )
				else
					if (self.Progs[ hk ]) then self.Progs[ hk ]:PingSuccess( handle[1], dat[3] ) end
				end
			end
		end
		if (dat[1] == "netTraceHop") then
			local hk = dat[2]
			local thdl = dat[3]
			local st = self.TraceRouteData[ thdl ]
			if (st) then
				local hop = tonumber( dat[6] ) or st.TTL
				local ms = ElapsedMs( st.SentAt )
				st.HopMs = st.HopMs or {}
				st.HopMs[ hop ] = ms
				st.Hops[ hop ] = tostring( dat[4] or handle[1] ) .. " - " .. tostring( dat[5] or "HOP" ) .. "  (" .. tostring( ms ) .. " ms)"
				st.TTL = hop + 1
				self:SendTraceProbe( thdl )
			end
		end
		if (dat[1] == "netTraceResponse") then
			local hk = dat[2]
			if (hk) then
				local thdl = dat[3]
				local st = self.TraceRouteData[ thdl ]
				self.TraceRouteData[ thdl ] = nil
				if (st) then
					local ms = ElapsedMs( st.SentAt )
					st.HopMs = st.HopMs or {}
					st.HopMs[ st.TTL ] = ms
					st.Hops[ st.TTL ] = tostring( handle[1] ) .. " - " .. tostring( dat[4] or "HOST" ) .. "  (" .. tostring( ms ) .. " ms)"
					if (hk == "os") then
						self:TraceSuccess( handle[1], st.Hops )
					else
						if (self.Progs[ hk ]) then self.Progs[ hk ]:TraceSuccess( handle[1], st.Hops ) end
					end
				end
			end
		end
	end
	self:DoPacket( pt, dat, handle )
end

function OS:SendNetMessage( dest, port, body, ttl, src, viaWireless )
	if ((!dest) || (!port) || (!body)) then
		PCMod.Msg( "Os failed to send net message! (" .. tostring(dest != nil) .. "," .. tostring(port != nil) .. "," .. tostring(body != nil ) .. ")", true )
		return
	end
	PCMod.Msg( "Os sending net message... (" .. dest .. ":" .. port .. ")", true )
	//PrintTable( body )
	return self:Network():SendPacket( dest, port, body, ttl, src, viaWireless )
end

function OS:ReplyNetMessage( handle, body )
	// handle[3] is the local address the request was sent to; replying from
	// that address keeps multi-homed devices answering on the right identity.
	// handle[4] sends the reply back out the same interface.
	return self:SendNetMessage( handle[1], handle[2], body, nil, handle[3], handle[4] )
end

function OS:GetIP()
	return self:Network():GetIP()
end

// Hardware address of this machine's network interface.
function OS:GetMAC()
	return self:Network():GetMAC()
end

// Dotted-quad IPv4 address (GetIP returns only the host octet).
function OS:GetFullIP()
	return self:Network():GetFullIP()
end

// Secondary addresses from other routers this device is also linked to.
function OS:GetExtraAddresses()
	if (self:Network().GetExtraAddresses) then return self:Network():GetExtraAddresses() end
	return {}
end

// Addresses of every network interface (one entry per Ethernet port / Wi-Fi
// link), so the control panel can show a second adapter on the same host.
function OS:GetInterfaces()
	if (self:Network().GetInterfaces) then return self:Network():GetInterfaces() end
	return {}
end

// Emulated IPv6 address of this machine (see PCMod.IPv6 in sh_common.lua).
function OS:GetIPv6()
	return self:Network():GetIPv6()
end

// Preferred address for new programs: IPv6 when available, IPv4 otherwise.
// Existing programs that expect IPv4 can keep calling OS:GetIP().
function OS:GetAddress()
	return self:GetIPv6() or self:GetIP()
end

// IPv6 subnet information for programs (for example an "ipconfig" screen).
function OS:GetIPv6Prefix()
	return self:Network():GetIPv6Prefix()
end

// Alias for program code that thinks in subnets.
function OS:GetIPv6Subnet()
	return self:GetIPv6Prefix()
end

function OS:GetIPv6Gateway()
	return self:Network():GetIPv6Gateway()
end

function OS:GetIPv6LinkLocal()
	return self:Network():GetIPv6LinkLocal()
end

function OS:GetBIPv6Prefix()
	return self:Network():GetBIPv6Prefix()
end

function OS:GetBIPv6()
	return self:Network():GetBIPv6()
end

function OS:GetBIPv6LinkLocal()
	return self:Network():GetBIPv6LinkLocal()
end

function OS:GetBIPv6Subnet()
	return self:GetBIPv6Prefix()
end

function OS:GetBIPv6Gateway()
	return self:Network():GetBIPv6Gateway()
end

// Address family/type of a target: "ipv4", "ipv4-mapped", "unique-local",
// "link-local", "loopback", "global" or "invalid".
function OS:GetAddressType( addr )
	return PCMod.IPv6.AddressType( addr )
end

function OS:NetPing( dest, hk )
	return self:SendNetMessage( dest, 0, { "netPing", hk } )
end

function OS:NetTrace( dest, hk )
	// Get a trace handle
	local thdl
	local cnt = 0
	for cnt=1, 50 do
		if (!self.TraceRouteData[ cnt ]) then
			thdl = cnt
			break
		end
	end
	if (!thdl) then
		PCMod.Msg( "== OS FAILED TO FIND EMPTY TRACE HANDLE! ==" )
		return
	end
	// Traceroute works like the real thing: send a probe with TTL = 1, then
	// increase the TTL by one for each hop report until the destination replies.
	self.TraceRouteData[ thdl ] = {
		Dest = dest,
		HK = hk,
		Hops = {},
		HopMs = {},
		TTL = 1,
		SentAt = NowSeconds(),
	}
	return self:SendTraceProbe( thdl )
end

function OS:SendTraceProbe( thdl )
	local st = self.TraceRouteData[ thdl ]
	if (!st) then return end
	local max = tonumber( PCMod.Cfg && PCMod.Cfg.TraceMaxHops ) or 255
	if (st.TTL > max) then
		self.TraceRouteData[ thdl ] = nil
		return false
	end
	st.SentAt = NowSeconds()
	return self:SendNetMessage( st.Dest, 0, { "netTrace", st.HK, thdl, st.TTL }, st.TTL )
end

function OS:MessageFailed( hdl, code, data )
	PCMod.Msg( "OS Base recieved msg fail code! (" .. hdl[1] .. ":" .. hdl[2] .. "), " .. code, true )
end


// Callbacks for OS-level ping / traceroute replies (hk == "os").
// ProcessPacket calls these on every netPingResponse / netTraceResponse;
// without them it died with "attempt to call method 'PingSuccess' (a nil value)".
function OS:PingSuccess( ip )
	PCMod.Msg( "OS Base pinged " .. tostring( ip ) .. " successfully!", true )
end

function OS:TraceSuccess( ip, trace )
	PCMod.Msg( "OS Base traced " .. tostring( ip ) .. " successfully!", true )
end
