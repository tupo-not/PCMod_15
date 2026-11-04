
// Router Control Driver for PCMod 2 (This is for the router, not the pc)

DRV = PCMod.DeriveDriver( "base" )

DRV.NiceName = "WebGear Router Core"
DRV.Name = "webgr_router"
DRV.Type = "networking"
DRV.ID = 0
DRV.LAN = {}
DRV.BLAN = {}
DRV.NPorts = {}
DRV.OPorts = {}
DRV.BSubnet = nil
DRV.Subnet = nil
DRV.Wireless = false
// PCs ("stations") connected to this router over the air, keyed by ent index.
DRV.WirelessClients = {}

function DRV:Initialize()
	if (!self.Entity) then return end
	
	PCMod.Msg( "Initializing WebGear Router Core..", true )
	
	// Hook in our events
	self.Entity:AddEHook( "driver", self.Name, "linked" ) -- Something has been linked up
	self.Entity:AddEHook( "driver", self.Name, "unlinked" ) -- Something has been unlinked
	
	// Get a list of valid ports
	local ports = self.Entity:Ports()
	local tmp = {}
	self.LAN = {}
	for k, v in pairs( ports ) do
		if (v.Type == "network") then
			table.insert( tmp, k )
			table.insert( self.LAN, k, v )
		end
	end
	self.NPorts = table.Copy( tmp )
	local tmp = {}
	self.BLAN = {}
	for k, v in pairs( ports ) do
		if (v.Type == "optic") then
			table.insert( tmp, k )
			table.insert( self.BLAN, k, v )
		end
	end
	self.OPorts = table.Copy( tmp )

	timer.Simple(1, function() if (!IsValid( self.Entity )) then return end self.BSubnet = self.Entity:GetBSubnet() end)
	timer.Simple(1, function() if (!IsValid( self.Entity )) then return end self.Subnet = self.Entity:GetSubnet() end)
end

function DRV:DataRecieved( port, data )
	PCMod.Msg( "[webgr]Checking Ports", true )
	if (table.HasValue( self.NPorts, port )) then
		// Data is from a network port (PC)
		return self:Process( data )
	end
	if (table.HasValue( self.OPorts, port )) then
		// Data is from a optic port (Router)
		return self:Process( data )
	end
	if (port == 0) then
		// Data is from wireless
		if (self.Wireless) then self:Process( data ) end
	end
	// Data is from another port unrelated to us
end

function DRV:Process( data )
	PCMod.Msg( "[webgr]Data check " .. self.Entity:GetClass() .. " " .. tostring(self.Subnet) .. " (" .. tostring(self.BSubnet) .. ")", true )
	PCMod.Msg( table.ToString(data, "data", false), true )
	// Round 28 (M-06): the old guard was
	//   if (!data && !data[1] && table.maxn( data ) < 2) then return end
	// - with data == nil it raised "attempt to index a nil value" (exactly
	// the case it was supposed to protect) and with a valid table the &&
	// chain stopped at !data, so the length check NEVER ran at all.
	if (!istable( data )) then return end
	if (!data[1] || (table.maxn( data ) < 2)) then return end
	local tag = data[1]
	local body = data[2]
	// PCMod.Msg( "Router Driver is processing this packet ["..tag.."] { "..body[1]..", "..body[2]..", "..body[3]..", "..body[4].." }", true )
	PCMod.Msg( "[webgr] Router Driver is processing this packet [" .. tag .. "]", true )
	PCMod.Msg( "[webgr] Body datatype: " .. type( data ) .. " " .. tostring(body), true )
	if ((tag == "sendpacket") && (type( body ) == "table")) then
		local pid = PCMod.Network.CreatePacket( body[1], body[2], body[3], body[4] )
		if (!pid) then
			PCMod.Msg( "Network packet dropped: all packet slots are in flight", true )
			return false
		end
		return self:ProcessPacket( pid )
	end
	if ((tag == "deliver") && (type( body ) == "number")) then
		return self:ProcessPacket( body, data[3] )
	end
end

// Classify a destination into the networks this router knows about.
// Returns { IsIPv6, IPv4, LAN, Backbone, OnLinkLAN, OnLinkBackbone }.
//   LAN/Backbone      - destination looks like a LAN/backbone address
//   OnLinkLAN         - destination is inside THIS router's LAN /64
//   OnLinkBackbone    - destination is inside THIS router's backbone /64
// IPv6 uses real prefix matching; IPv4 (and mapped IPv6) uses the historical
// 192.168/10.0 address-space test. The OnLink flags matter because an unknown
// on-link IPv6 host must be dropped, while a LAN address that belongs to a
// different router still has to be forwarded.
function DRV:ClassifyDestination( dest )
	local dest6 = PCMod.IPv6.IsIPv6( dest )
	local dest4 = PCMod.IPv6.ToIPv4( dest ) or dest
	local toBackbone = false
	local toLAN = false
	local onLinkLAN = false
	local onLinkBackbone = false
	if (dest6) then
		local bp = self:GetBIPv6Prefix()
		local lp = self:GetIPv6Prefix()
		// Most specific first: a LAN's /64 lives inside its backbone /32.
		if (lp && PCMod.IPv6.InSubnet( dest, lp )) then
			toLAN = true
			onLinkLAN = true
		elseif (bp && PCMod.IPv6.InSubnet( dest, bp )) then
			toBackbone = true
			onLinkBackbone = true
		end
	end
	if ((!onLinkLAN) && (!onLinkBackbone) && (type( dest4 ) == "string")) then
		if (string.find( dest4, "10.0", 1, true )) then toBackbone = true end
		if (string.find( dest4, "192.168", 1, true )) then toLAN = true end
	end
	return {
		IsIPv6 = dest6,
		IPv4 = dest4,
		LAN = toLAN,
		Backbone = toBackbone,
		OnLinkLAN = onLinkLAN,
		OnLinkBackbone = onLinkBackbone,
	}
end

function DRV:ProcessPacket( pid, pass )
	pass = (pass or 0) + 1
	// Round 19 (AUDIT2 A-01): the nil guard must run BEFORE `pid > MaxNetworkPid` -
	// comparing nil with a number raises a Lua error at language level. Order is
	// unchanged for every valid (numeric) pid.
	if (!pid) then
		PCMod.Msg( "[webgr]No pid", true )
		return
	end
	if (pid > PCMod.Cfg.MaxNetworkPid) then PCMod.Msg( "[webgr]WARNING: Connection ERROR!" ) return end
	if (pass > PCMod.Cfg.MaxNetworkPass) then
		PCMod.Msg( "[webgr]WARNING: Packet reached maximum pass! (id " .. tostring( pid ) .. ")" )
		return
	else
		PCMod.Msg( "[webgr]Parsed packet with pass: " .. pass .. " (id " .. tostring( pid ) .. ")" )
	end
	local mem = self.Entity:Memory()
	if (!mem.P) then mem.P = {} end
	if (mem.P[pid]) then
		PCMod.Msg( "[webgr]Already processed", true )
		return
	end -- Already processed, skip
	mem.P[pid] = true -- Processed flag enabled
	self.Entity:UpdateMemory( mem )
	local packet = PCMod.Network.Packets[ pid ] -- Get the packet
	if (!packet) then
		PCMod.Msg( "[webgr]Packet is nil", true )
		return
	end
	if (packet.Delivered) then
		PCMod.Msg( "[webgr]Already delivered", true )
		return
	end -- Task completed by another router!
	// Minimal web server: a request to port 80 addressed to the router itself
	// (body { "http", path }) is answered with a plain-text config page.
	if ((packet.Port == 80) && (packet.Body) && (packet.Body[1] == "http") && (self.Entity.IsAddressedTo && self.Entity:IsAddressedTo( packet.Dest ))) then
		self:HandleWebRequest( packet )
		return
	end
	// See if its a traceroute
	PCMod.Msg( "[webgr]The packet was not delivered, begin target checks", true )
	if ((packet.Body) && (packet.Body[1]) && (packet.Body[1] == "netTrace")) then
		local sip = "n/a"
		local sid = "n/a"
		if (self.Entity:GetClass() == "pcmod_router") then
			sip = "192.168." .. tostring( self.Entity:GetSubnet() ) .. ".1"
			sid = "RTR"
		end
		if (self.Entity:GetClass() == "pcmod_brouter") then
			sip = "10.0." .. tostring( self.Entity:GetBSubnet() ) .. ".0"
			sid = "BRTR"
		end
		if (self.Wireless) then
			sid = "WRTR"
		end
		PCMod.Msg( "[webgr][== This entity has found a trace packet! (" .. sip .. ") ==]", true )
		// source, dest, port, body
		self:Process( { "sendpacket", { sip, packet.Source, 0, { "netTraceNode", packet.Body[3], sid } } } )
	end
	// Resolve the destination against this router's LAN/backbone /64s. IPv4,
	// the emulated IPv6 form, IPv4-mapped IPv6 and bracketed literals all end
	// up in the same classification.
	local route = self:ClassifyDestination( packet.Dest )
	local dest6 = route.IsIPv6
	local toBackbone = route.Backbone
	local toLAN = route.LAN

	if (toBackbone) then
		local port = self:HasRouter( packet.Dest )
		if (port) then
			PCMod.Msg( "[webgr]This packet is headed for a backbone IP, searching local network", true )
			PCMod.Msg( "[webgr]The target on this network is on port " .. port .. ". Pushing data", true )

			// Deliver to Router
			self.Entity:PushData( port, { "deliver", pid, pass } )

			// Check to see if the packet has been delivered yet
			if (PCMod.Network.Packets[ pid ].Delivered) then
				PCMod.Msg( "[webgr]The packet was delivered", true )
				// Delivery successful!
				return
			end
		elseif (dest6) then
			PCMod.Msg( "[webgr]Backbone IPv6 target is not directly attached; flooding backbone", true )
		end
	end

	if (toLAN) then
		local port = self:HasPC( packet.Dest )
		if (port) then
			PCMod.Msg( "[webgr]This packet is headed for a normal IP, searching local network", true )
			PCMod.Msg( "[webgr]The target on this network is on port " .. port .. ". Pushing data", true )

			// Deliver to PC
			self.Entity:PushData( port, { "deliver", pid, pass } )

			// Check to see if the packet has been delivered yet
			if (PCMod.Network.Packets[ pid ].Delivered) then
				PCMod.Msg( "[webgr]The packet was delivered", true )
				// Delivery successful!
				return
			end
		elseif ((!port) && self:DeliverToWirelessClient( packet )) then
			return
		elseif (dest6 && route.OnLinkLAN) then
			// IPv6 has no broadcast. An address on THIS router's LAN /64 that
			// no attached host owns must not leak onto the rest of the network.
			// Addresses belonging to another router's LAN are still forwarded.
			PCMod.Msg( "[webgr]No host for on-link IPv6 target " .. tostring( packet.Dest ), true )
			return
		end
	end

	PCMod.Msg( "[webgr]This router does not have the target. Pushing to other routers", true )

	// If not, push it to all connected routers
	self.Entity:FullPushData( { "deliver", pid, pass }, "optic" )
end

function DRV:CallEvent( data )
	if ((!data) || (!data.Event)) then return end
	PCMod.Msg( "[webgr]An event was called(" .. table.ToString(data) .. ")", true )
	local e = data.Event
	if (e == "linked") then
		local port = self.Entity:Ports()[ data[ 1 ] ]
		
		PCMod.Msg( "[webgr]Linked event called on router! (" .. self.Entity:EntIndex() .. ")", true )
		PCMod.Msg( "[webgr]REMOTE: " .. port.ConEnt:GetClass(), true )
		PCMod.Msg( "[webgr]SOURCE: " .. self.Entity:GetClass(), true )
		
		if (self.Entity:GetClass() == "pcmod_brouter" && port.ConEnt:GetClass() == "pcmod_router") then
			table.insert( self.BLAN, data[ 1 ], port )
			PCMod.Network.RegisterPC( port.ConEnt, self.Entity:GetBSubnet(), true )
		end

		if (self.Entity:GetClass() == "pcmod_router" && port.ConEnt:GetClass() != "pcmod_router" && port.ConEnt:GetClass() != "pcmod_brouter") then
			table.insert( self.LAN, data[ 1 ], port )
			PCMod.Network.RegisterPC( port.ConEnt, self.Entity:GetSubnet(), false, self.Entity:GetBSubnet() )
		end
	end
	if (e == "unlinked") then
		local port = {}
		port.ConEnt = data[ 2 ]

		PCMod.Msg( "[webgr]An unlink event was called", true )

		if (self.Entity:GetClass() == "pcmod_brouter" && port.ConEnt:GetClass() == "pcmod_router") then
			table.insert( self.BLAN, data[ 1 ], self.Entity:Ports()[ data[ 1 ] ] )
			PCMod.Network.UnRegisterPC( port.ConEnt, self.Entity:GetBSubnet(), true )
		end

		if (self.Entity:GetClass() == "pcmod_router" && port.ConEnt:GetClass() != "pcmod_router" && port.ConEnt:GetClass() != "pcmod_brouter") then
			table.insert( self.LAN, data[ 1 ], self.Entity:Ports()[ data[ 1 ] ] )
			PCMod.Network.UnRegisterPC( port.ConEnt, self.Entity:GetSubnet(), false )
		end
	end
end

function DRV:HasRouter( ip )
	PCMod.Msg( "[webgr]looking for router " .. ip, true )
	for k, v in pairs( self.BLAN ) do
		if (v.Connected) then
			PCMod.Msg( "[webgr]port " .. k .. " has the ips " .. tostring(v.ConEnt:GetFullIP()) .. "(" .. tostring(v.ConEnt:GetFullBIP()) .. ")", true )
			if (v.ConEnt.IsAddressedTo && v.ConEnt:IsAddressedTo( ip )) then
				return k
			end
		end
	end
	return false
end

function DRV:HasPC( ip )
	PCMod.Msg( "[webgr]looking for pc " .. tostring( ip ), true )
	for k, v in pairs( self.LAN ) do
		if (v.Connected) then
			PCMod.Msg( "[webgr]port " .. k .. " has the ips " .. tostring(v.ConEnt:GetFullIP()) .. "(" .. tostring(v.ConEnt:GetFullBIP()) .. ")", true )
			if (v.ConEnt.IsAddressedTo && v.ConEnt:IsAddressedTo( ip )) then
				return k
			end
		end
	end
	return false
end

// Register a PC that connected to this router over Wi-Fi. The address lease is
// handed out by the same DHCP pool as cable clients (PCMod.Network.RegisterPC);
// when the pool is full the client is still admitted and stands by as
// IPv6-only, so the network never turns anyone away.
function DRV:AddWirelessClient( pc )
	if ((!pc) || (!pc:IsValid())) then return false end
	if (!self.WirelessClients) then self.WirelessClients = {} end
	self.WirelessClients[ pc:EntIndex() ] = pc
	return PCMod.Network.RegisterPC( pc, self.Entity:GetSubnet(), false, self.Entity:GetBSubnet() )
end

function DRV:RemoveWirelessClient( pc )
	if (!pc) then return end
	if (self.WirelessClients && self.WirelessClients[ pc:EntIndex() ]) then
		self.WirelessClients[ pc:EntIndex() ] = nil
		PCMod.Network.UnRegisterPC( pc, self.Entity:GetSubnet(), false )
	end
end

// Deliver an in-flight packet to a Wi-Fi client on this router. Returns true
// when a client claimed it (and the packet is marked delivered).
function DRV:DeliverToWirelessClient( packet )
	for _, pc in pairs( self.WirelessClients or {} ) do
		if ((pc) && (pc:IsValid()) && (pc.IsAddressedTo) && (pc:IsAddressedTo( packet.Dest ))) then
			packet.Delivered = true
			local data = PCMod.Data[ pc:EntIndex() ]
			local drv = data && data.Drivers && data.Drivers[ "gen_network" ]
			if (drv) then drv:PacketRecieved( packet ) end
			return true
		end
	end
	return false
end

// Emulated IPv6 view of this router. The router's own address is the ::1
// gateway of its LAN/backbone /64, and GetIPv6Prefix is that /64.
function DRV:GetIPv6()
	return self.Entity:GetIPv6()
end

function DRV:GetIPv6Prefix()
	return self.Entity:GetIPv6Prefix()
end

function DRV:GetBIPv6()
	return self.Entity:GetBIPv6()
end

function DRV:GetBIPv6Prefix()
	return self.Entity:GetBIPv6Prefix()
end

// Is addr on one of this router's directly attached IPv6 subnets?
function DRV:HasIPv6Subnet( addr )
	if (PCMod.IPv6.InSubnet( addr, self:GetIPv6Prefix() )) then return true end
	if (PCMod.IPv6.InSubnet( addr, self:GetBIPv6Prefix() )) then return true end
	return false
end

// A plain-text config/status "web page" served by the router (the browser is a
// later milestone; any client can fetch this over the network on port 80).
function DRV:GetWebPage()
	local e = self.Entity
	local data = e.Data && e:Data() or nil
	local bb = e:GetBSubnet()
	local lines = {}
	table.insert( lines, "WebGear Router" )
	table.insert( lines, "=================" )
	table.insert( lines, "Model: " .. tostring( e:GetClass() ) )
	table.insert( lines, "IPv4 LAN: " .. tostring( e:GetFullIP() or "unassigned" ) )
	table.insert( lines, "IPv6 LAN: " .. tostring( e:GetIPv6() or "unassigned" ) )
	if (e.GetIPv6Prefix && e:GetIPv6Prefix()) then table.insert( lines, "IPv6 prefix: " .. tostring( e:GetIPv6Prefix() ) ) end
	if (bb) then table.insert( lines, "Backbone: fd00:" .. tostring( bb ) .. "::/32" ) else table.insert( lines, "Backbone: none (standalone)" ) end
	local dhcpS = tonumber( PCMod.Cfg.DHCPStart ) or 2
	local dhcpE = tonumber( PCMod.Cfg.DHCPEnd ) or 254
	table.insert( lines, "DHCP pool: ." .. tostring( dhcpS ) .. " - ." .. tostring( dhcpE ) )
	if (self.Wireless) then
		table.insert( lines, "Wi-Fi: enabled (password " .. tostring( (data && data.WirePass) or "123" ) .. ")" )
	else
		table.insert( lines, "Wi-Fi: disabled" )
	end
	local wc = 0
	for _, v in pairs( self.WirelessClients or {} ) do if (v) then wc = wc + 1 end end
	table.insert( lines, "Wi-Fi clients: " .. tostring( wc ) )
	return table.concat( lines, "\n" )
end

// Reply to an in-game HTTP request with the page body.
function DRV:HandleWebRequest( packet )
	local page = self:GetWebPage()
	local src = self.Entity:GetFullIP() or self.Entity:GetIPv6()
	if (!src) then return false end
	PCMod.Network.CreatePacket( src, packet.Source, 80, { "http-response", page } )
	return true
end

function DRV:OnRemove()
	self.LAN = {}
	self.BLAN = {}
	self.BSubnet = self.Entity:GetBSubnet()
	self.Subnet = self.Entity:GetSubnet()
	self.NPorts = {}
	self.OPorts = {}
	self.WirelessClients = {}
end