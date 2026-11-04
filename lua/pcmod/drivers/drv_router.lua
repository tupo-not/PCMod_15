
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
// Active DHCP leases (host id -> entity), shared by cable and Wi-Fi clients.
DRV.Leases = {}

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
		// Data is from a network port (PC / LAN side).
		return self:Process( data, "lan" )
	end
	if (table.HasValue( self.OPorts, port )) then
		// Data is from an optic port (router / WAN side).
		return self:Process( data, "wan" )
	end
	if (port == 0) then
		// Data is from wireless (LAN side).
		if (self.Wireless) then self:Process( data, "lan" ) end
	end
	// Data is from another port unrelated to us
end

function DRV:Process( data, side )
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
		return self:ProcessPacket( pid, nil, side )
	end
	if ((tag == "deliver") && (type( body ) == "number")) then
		return self:ProcessPacket( body, data[3], side )
	end
end

// Classify a destination into the networks this router knows about.
// Returns { IsIPv6, IPv4, LAN, Backbone, OnLinkLAN, OnLinkBackbone }.
//   LAN/Backbone      - destination looks like a LAN/backbone address
//   OnLinkLAN         - destination is inside THIS router's LAN /64
//   OnLinkBackbone    - destination is inside THIS router's backbone /64
// IPv6 uses real prefix matching; IPv4 (and mapped IPv6) uses the private
// 192.168 / 10.x address-space test. The OnLink flags matter because an unknown
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
	else
		// IPv4 (and mapped IPv6) are classified by their historic address
		// space; an unknown IPv6 /32 is NOT retrofitted onto the IPv4 core, it
		// is forwarded upstream instead.
		if ((type( dest4 ) == "string")) then
			if (string.Left( dest4, 3 ) == "10.") then toBackbone = true end
			if (string.Left( dest4, 7 ) == "192.168") then toLAN = true end
		end
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

function DRV:ProcessPacket( pid, pass, side )
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
		PCMod.Msg( "[webgr]Parsed packet with pass: " .. pass .. " (id " .. tostring( pid ) .. ")", true )
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
	// Rules-based firewall: drop matching traffic arriving on a real interface.
	if (side && self:FirewallBlocks( packet, side )) then
		PCMod.Msg( "[webgr]Firewall dropped packet on port " .. tostring( packet.Port ), true )
		return
	end
	// Port forwarding (NAT). A reply from a forwarded internal host is source-
	// NAT'ed back to the original peer; an inbound packet to a forwarded port is
	// destination-NAT'ed to the internal host.
	local isSelf = (self.Entity.IsAddressedTo && self.Entity:IsAddressedTo( packet.Dest ))
	if (isSelf) then
		local flow = self:GetForwardFlow( packet.Source, packet.Port )
		if (flow) then
			local wanSrc = self.Entity:GetFullIP() or self.Entity:GetIPv6()
			if (wanSrc) then
				packet.Delivered = true
				local rpid = PCMod.Network.CreatePacket( wanSrc, flow.src, flow.port, packet.Body )
				if (rpid) then self:ProcessPacket( rpid ) end
			end
			return
		end
		local rule = self:GetForwardRule( packet.Port )
		if (rule) then
			local lanSrc = self.Entity:GetFullIP() or self.Entity:GetIPv6()
			if (lanSrc) then
				self:RememberForwardFlow( rule, packet.Source, packet.Port )
				packet.Delivered = true
				local dpid = PCMod.Network.CreatePacket( lanSrc, rule.ip, rule.port, packet.Body )
				if (dpid) then self:ProcessPacket( dpid ) end
			end
			return
		end
	end
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
			sip = PCMod.IPv4.BackboneAddress( self.Entity:GetBSubnet(), 1 )
			sid = "BRTR"
		end
		if (self.Wireless) then
			sid = "WRTR"
		end
		PCMod.Msg( "[webgr][== This entity has found a trace packet! (" .. sip .. ") ==]", true )
		// source, dest, port, body
		self:Process( { "sendpacket", { sip, packet.Source, 0, { "netTraceNode", packet.Body[3], sid } } } )
	end
	// Resolve the destination. IPv4 is LAN-local only; IPv6 is routed by prefix
	// (explicit /64 and /32 routing table, no flooding, no IPv4 retrofitting).
	local dest6 = PCMod.IPv6.IsIPv6( packet.Dest )

	if (!dest6) then
		// IPv4 never leaves the LAN it was born on (real private addressing;
		// cross-router traffic goes over IPv6).
		local port = self:HasPC( packet.Dest )
		if (port) then
			self.Entity:PushData( port, { "deliver", pid, pass } )
			return
		end
		if (self:DeliverToWirelessClient( packet )) then return end
		PCMod.Msg( "[webgr]IPv4 target " .. tostring( packet.Dest ) .. " is not on this LAN; dropping", true )
		return
	end

	// IPv6: on-link LAN first.
	local lp = self:GetIPv6Prefix()
	if (lp && PCMod.IPv6.InSubnet( packet.Dest, lp )) then
		local port = self:HasPC( packet.Dest )
		if (port) then
			self.Entity:PushData( port, { "deliver", pid, pass } )
			return
		end
		if (self:DeliverToWirelessClient( packet )) then return end
		// Unknown host on my own /64: IPv6 has no broadcast.
		PCMod.Msg( "[webgr]No host for on-link IPv6 target " .. tostring( packet.Dest ), true )
		return
	end

	// Route by hierarchy.
	local hier = PCMod.IPv6.Hierarchy( packet.Dest )
	if (self.Entity:GetClass() == "pcmod_brouter") then
		// Backbone router: child /64s (my /32) and peer /32s (neighbors).
		local mybb = self.Entity:GetBSubnet()
		if (hier && (hier.bb == mybb)) then
			local childPort = self.ChildLan && self.ChildLan[ hier.lan ]
			if (childPort) then
				self.Entity:PushData( childPort, { "deliver", pid, pass } )
				return
			end
		elseif (hier) then
			local nPort = self:RouteForBB( hier.bb )
			if (nPort) then
				self.Entity:PushData( nPort, { "deliver", pid, pass } )
				return
			end
		end
		PCMod.Msg( "[webgr]No IPv6 route for " .. tostring( packet.Dest ) .. "; dropping", true )
		return
	end

	// LAN router: everything not on my LAN goes upstream.
	if (self.Uplink) then
		self.Entity:PushData( self.Uplink, { "deliver", pid, pass } )
		return
	end
	PCMod.Msg( "[webgr]No uplink for IPv6 target " .. tostring( packet.Dest ) .. "; dropping", true )
end

function DRV:CallEvent( data )
	if ((!data) || (!data.Event)) then return end
	PCMod.Msg( "[webgr]An event was called(" .. table.ToString(data) .. ")", true )
	local e = data.Event
	if (e == "linked") then
		local port = self.Entity:Ports()[ data[ 1 ] ]
		local cls = self.Entity:GetClass()
		local peer = port.ConEnt:GetClass()

		if ((cls == "pcmod_brouter") && (peer == "pcmod_router")) then
			// LAN router attaches to my backbone: give it a /64 of my /32 and a
			// WAN backbone address, then renumber its LAN.
			self.BLAN[ data[ 1 ] ] = port
			local bb = self.Entity:GetBSubnet()
			PCMod.Network.RegisterPC( port.ConEnt, bb )
			local lanid = self:NextLanID()
			port.ConEnt:SetUpBB( bb )
			port.ConEnt:SetLanID( lanid )
			if (!self.Children) then self.Children = {} end
			if (!self.ChildLan) then self.ChildLan = {} end
			self.Children[ port.ConEnt:EntIndex() ] = lanid
			self.ChildLan[ lanid ] = port
			local cdata = PCMod.Data[ port.ConEnt:EntIndex() ]
			local child = cdata && cdata.Drivers && cdata.Drivers[ "webgr_router" ]
			if (child && child.ReconfigureClients) then child:ReconfigureClients() end
		elseif ((cls == "pcmod_brouter") && (peer == "pcmod_brouter")) then
			// Peer backbone: learn its /32 -> this port, then reconverge.
			self.BLAN[ data[ 1 ] ] = port
			if (!self.Neighbors) then self.Neighbors = {} end
			self.Neighbors[ port.ConEnt:GetBSubnet() ] = port
			self:RecalcRoutes()
			PCMod.Network.Reconverge()
		elseif ((cls == "pcmod_router") && (peer == "pcmod_brouter")) then
			// My WAN uplink.
			self.Uplink = port
		elseif ((cls == "pcmod_router") && (peer == "pcmod_router")) then
			// Two LAN routers cabled together: treat it as an uplink too.
			self.Uplink = port
		elseif ((cls == "pcmod_router") && (peer != "pcmod_router") && (peer != "pcmod_brouter")) then
			// A computer plugs into a LAN port.
			self.LAN[ data[ 1 ] ] = port
			self:AssignLease( port.ConEnt )
		end
	end
	if (e == "unlinked") then
		local port = {}
		port.ConEnt = data[ 2 ]
		local cls = self.Entity:GetClass()
		local peer = port.ConEnt && port.ConEnt:GetClass() or ""

		if ((cls == "pcmod_brouter") && (peer == "pcmod_router")) then
			local lanid = self.Children && self.Children[ port.ConEnt:EntIndex() ]
			PCMod.Network.UnRegisterPC( port.ConEnt, self.Entity:GetBSubnet() )
			if (lanid && self.ChildLan) then self.ChildLan[ lanid ] = nil end
			if (self.Children) then self.Children[ port.ConEnt:EntIndex() ] = nil end
			// The detached LAN becomes standalone again.
			port.ConEnt:SetUpBB( 0 )
			port.ConEnt:SetLanID( 0 )
			local cdata = PCMod.Data[ port.ConEnt:EntIndex() ]
			local child = cdata && cdata.Drivers && cdata.Drivers[ "webgr_router" ]
			if (child && child.ReconfigureClients) then child:ReconfigureClients() end
		elseif ((cls == "pcmod_brouter") && (peer == "pcmod_brouter")) then
			if (self.Neighbors) then self.Neighbors[ port.ConEnt:GetBSubnet() ] = nil end
			self:RecalcRoutes()
			PCMod.Network.Reconverge()
		elseif ((cls == "pcmod_router") && ((peer == "pcmod_brouter") || (peer == "pcmod_router"))) then
			self.Uplink = nil
			// Lost our uplink: fall back to standalone addressing.
			self.Entity:SetUpBB( 0 )
			self.Entity:SetLanID( 0 )
			self:ReconfigureClients()
		elseif ((cls == "pcmod_router") && (peer != "pcmod_router") && (peer != "pcmod_brouter")) then
			self:ReleaseLease( port.ConEnt )
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

// Register a PC that connected to this router over Wi-Fi.
function DRV:AddWirelessClient( pc )
	if ((!pc) || (!pc:IsValid())) then return false end
	if (!self.WirelessClients) then self.WirelessClients = {} end
	self.WirelessClients[ pc:EntIndex() ] = pc
	local host = self:AssignLease( pc )
	if (!host) then return "full" end
	return "assigned"
end

// Hand out an IPv4 lease from this router's private LAN pool. Returns the host
// id, or nil when the pool is exhausted (the client is still admitted as
// IPv6-only by the caller).
function DRV:AssignLease( pc )
	if ((!pc) || (!pc:IsValid())) then return nil end
	if (!self.Leases) then self.Leases = {} end
	self:ReleaseLease( pc )
	local c = self:GetCfg()
	local mask = (tonumber( PCMod.Cfg.LanNetmask ) == 16) and 16 or 24
	local start = c.DHCPStart
	local finish = c.DHCPEnd
	if (finish > 65534) then finish = 65534 end
	local host = nil
	for h = start, finish do
		if (!self.Leases[ h ]) then host = h break end
	end
	if (!host) then return nil end
	self.Leases[ host ] = pc
	if (mask == 16) then
		pc:SetSubnet( math.floor( host / 256 ) )
		pc:SetIP( host % 256 )
	else
		pc:SetSubnet( 0 )
		pc:SetIP( host )
	end
	local ip = self.Entity:Data().IP
	if (pc.SetUpBB) then pc:SetUpBB( ip.UpBB or 0 ) end
	if (pc.SetLanID) then pc:SetLanID( ip.LanID or 0 ) end
	return host
end

function DRV:ReleaseLease( pc )
	if (!pc) then return end
	if (!self.Leases) then self.Leases = {} end
	for host, ent in pairs( self.Leases ) do
		if (ent == pc) then
			self.Leases[ host ] = nil
			pc:SetSubnet( false )
			pc:SetIP( false )
			return host
		end
	end
end

// A new /64 id within this backbone's /32 (one per attached LAN router).
function DRV:NextLanID()
	self.NextLan = (self.NextLan or 0) + 1
	return self.NextLan
end

function DRV:IsBackbone()
	return (self.Entity:GetClass() == "pcmod_brouter")
end

// Re-push this router's own /32 + /64 onto every client lease (a LAN router
// renumbers its LAN when its upstream changes).
function DRV:ReconfigureClients()
	local ip = self.Entity:Data().IP
	local upbb = ip.UpBB or 0
	local lanid = ip.LanID or 0
	for _, pc in pairs( self.Leases or {} ) do
		if (pc && pc.SetUpBB) then pc:SetUpBB( upbb ) end
		if (pc && pc.SetLanID) then pc:SetLanID( lanid ) end
	end
	for _, pc in pairs( self.WirelessClients or {} ) do
		if (pc && pc.SetUpBB) then pc:SetUpBB( upbb ) end
		if (pc && pc.SetLanID) then pc:SetLanID( lanid ) end
	end
end

// ---------------------------------------------------------------------------
// Distance-vector routing between backbones. Each backbone keeps Routes[bb] =
// { dist = hops, via = neighbor /32 }, seeded from direct neighbours, and all
// backbones reconverge whenever the backbone graph changes.
// ---------------------------------------------------------------------------
function DRV:RecalcRoutes()
	if (!self:IsBackbone()) then return end
	self.Routes = {}
	local mybb = self.Entity:GetBSubnet()
	if (mybb) then self.Routes[ mybb ] = { dist = 0, via = nil } end
	for bb, port in pairs( self.Neighbors or {} ) do
		local cur = self.Routes[ bb ]
		if ((!cur) || (cur.dist > 1)) then self.Routes[ bb ] = { dist = 1, via = bb } end
	end
end

function DRV:GetDV()
	local dv = {}
	for bb, r in pairs( self.Routes or {} ) do dv[ bb ] = r.dist end
	return dv
end

function DRV:NeighborDrv( port )
	local ent = port && port.ConEnt
	if ((!ent) || (!ent:IsValid())) then return nil end
	local data = PCMod.Data[ ent:EntIndex() ]
	return data && data.Drivers && data.Drivers[ "webgr_router" ]
end

// Push this router's distance vector to every neighbouring backbone.
function DRV:AdvertiseRoutes()
	if (!self:IsBackbone()) then return end
	for bb, port in pairs( self.Neighbors or {} ) do
		local drv = self:NeighborDrv( port )
		if (drv && drv.RecvRoutes) then drv:RecvRoutes( self.Entity:GetBSubnet(), self:GetDV() ) end
	end
end

// Merge a neighbour's distance vector (Bellman-Ford update).
function DRV:RecvRoutes( fromBB, dv )
	if (!self:IsBackbone()) then return end
	for bb, dist in pairs( dv or {} ) do
		if (bb != self.Entity:GetBSubnet()) then
			local nd = dist + 1
			local cur = self.Routes[ bb ]
			if ((!cur) || (cur.dist > nd)) then self.Routes[ bb ] = { dist = nd, via = fromBB } end
		end
	end
end

// The next-hop optic port for an IPv6 /32 destination (nil = no route).
function DRV:RouteForBB( bb )
	local r = self.Routes && self.Routes[ bb ]
	if ((!r) || (!r.via)) then return nil end
	return self.Neighbors && self.Neighbors[ r.via ]
end

function DRV:RemoveWirelessClient( pc )
	if (!pc) then return end
	if (self.WirelessClients && self.WirelessClients[ pc:EntIndex() ]) then
		self.WirelessClients[ pc:EntIndex() ] = nil
	end
	self:ReleaseLease( pc )
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

// ---------------------------------------------------------------------------
// Router configuration (editable from the web page). Stored per-router in the
// entity data, seeded from cfg defaults / setup data on first read.
// ---------------------------------------------------------------------------
function DRV:GetCfg()
	local d = self.Entity:Data()
	d.RouterCfg = d.RouterCfg or {}
	local c = d.RouterCfg
	if (c.Wireless == nil) then c.Wireless = (self.Wireless == true) end
	if (c.WirePass == nil) then c.WirePass = d.WirePass or "123" end
	if (c.DHCPStart == nil) then c.DHCPStart = tonumber( PCMod.Cfg.DHCPStart ) or 2 end
	if (c.DHCPEnd == nil) then c.DHCPEnd = tonumber( PCMod.Cfg.DHCPEnd ) or 254 end
	if (c.Firewall == nil) then c.Firewall = false end
	if (c.NAT == nil) then c.NAT = true end
	if (c.Forwards == nil) then c.Forwards = {} end
	if (c.FirewallRules == nil) then c.FirewallRules = {} end
	return c
end

function DRV:SetWireless( on )
	on = (on == true)
	self.Wireless = on
	local d = self.Entity:Data()
	d.IsWireless = on
	local c = self:GetCfg()
	c.Wireless = on
	if (self.Entity.SetGVar) then self.Entity:SetGVar( "wireless", on ) end
end

// Rules-based firewall (blacklist). When enabled, traffic matching any rule
// (direction + optional source/dest IP + optional port) is dropped; otherwise
// everything passes.
function DRV:FirewallBlocks( packet, side )
	local c = self:GetCfg()
	if (!c.Firewall) then return false end
	local dir = (side == "wan") and "in" or "out"
	for _, r in ipairs( c.FirewallRules or {} ) do
		if ((r.dir == dir) || (r.dir == "any")) then
			local m = true
			if ((r.src != "") && (r.src != packet.Source)) then m = false end
			if ((r.dst != "") && (r.dst != packet.Dest)) then m = false end
			if ((r.port != 0) && (r.port != packet.Port)) then m = false end
			if (m) then return true end
		end
	end
	return false
end

function DRV:AddFirewallRule( dir, src, dst, port )
	if ((dir != "in") && (dir != "out") && (dir != "any")) then return false end
	src = tostring( src or "" )
	dst = tostring( dst or "" )
	if ((src != "") && (!PCMod.IPv6.IsIP( src ))) then return false end
	if ((dst != "") && (!PCMod.IPv6.IsIP( dst ))) then return false end
	local p = tonumber( port ) or 0
	if (p < 0) then p = 0 end
	local c = self:GetCfg()
	c.FirewallRules = c.FirewallRules or {}
	table.insert( c.FirewallRules, { dir = dir, src = src, dst = dst, port = p } )
	return true
end

function DRV:DeleteFirewallRule( idx )
	local c = self:GetCfg()
	c.FirewallRules = c.FirewallRules or {}
	table.remove( c.FirewallRules, idx )
end

function DRV:ApplyWebQuery( path )
	path = tostring( path or "" )
	local q = string.match( path, "%?(.*)$" )
	if (!q) then return end
	local parsed = {}
	for _, pair in ipairs( string.Explode( "&", q ) ) do
		local k, v = string.match( pair, "^(.-)=(.*)$" )
		if (k) then parsed[ k ] = v end
	end
	// Port-forwarding rules are multi-field; handle atomically before the
	// generic single-key settings.
	if (parsed.delpf) then self:DeleteForward( parsed.delpf ) end
	if (parsed.pfwan && parsed.pfip && parsed.pfport) then
		self:AddForward( parsed.pfwan, parsed.pfip, parsed.pfport )
	end
	if (parsed.delfw) then self:DeleteFirewallRule( tonumber( parsed.delfw ) ) end
	if (parsed.fwdir) then
		self:AddFirewallRule( parsed.fwdir, parsed.fwsrc or "", parsed.fwdst or "", parsed.fwport or "" )
	end
	for k, v in pairs( parsed ) do
		self:ApplyWebSetting( k, v )
	end
end

// Port forwarding (DNAT): wanPort -> lanIP:lanPort. A matching inbound packet
// addressed to the router is re-targeted at the internal host.
function DRV:AddForward( wan, ip, port )
	local wanN = tonumber( wan )
	local portN = tonumber( port )
	if ((!wanN) || (!portN) || (wanN < 1) || (portN < 1)) then return false end
	if (!PCMod.IPv6.IsIP( ip )) then return false end
	local c = self:GetCfg()
	c.Forwards = c.Forwards or {}
	c.Forwards[ tostring( wanN ) ] = { ip = ip, port = portN }
	return true
end

function DRV:DeleteForward( wan )
	local c = self:GetCfg()
	c.Forwards = c.Forwards or {}
	c.Forwards[ tostring( wan ) ] = nil
end

function DRV:GetForwardRule( wanPort )
	local c = self:GetCfg()
	return c.Forwards && c.Forwards[ tostring( wanPort ) ]
end

// NAT reply tracking: the internal host replies on (ip, port); remember the
// original peer so the router can rewrite the reply's source back to itself.
function DRV:RememberForwardFlow( rule, src, port )
	self.ForwardFlows = self.ForwardFlows or {}
	self.ForwardFlows[ tostring( rule.ip ) .. ":" .. tostring( rule.port ) ] = { src = src, port = port, time = CurTime() }
	if (table.Count( self.ForwardFlows ) > 64) then self.ForwardFlows = {} end
end

function DRV:GetForwardFlow( src, port )
	local f = self.ForwardFlows && self.ForwardFlows[ tostring( src ) .. ":" .. tostring( port ) ]
	if (!f) then return nil end
	if (f.time < (CurTime() - 120)) then
		self.ForwardFlows[ tostring( src ) .. ":" .. tostring( port ) ] = nil
		return nil
	end
	return f
end

function DRV:ApplyWebSetting( key, value )
	local c = self:GetCfg()
	if (key == "wireless") then
		self:SetWireless( (value == "1") || (value == "on") )
	elseif (key == "wpass") then
		if (value == "random") then
			c.WirePass = tostring( math.random( 100000, 999999 ) )
		else
			c.WirePass = tostring( value or "" )
		end
	elseif (key == "dhcpstart") then
		local n = tonumber( value )
		if (n) then c.DHCPStart = math.Clamp( n, 1, 65534 ) end
	elseif (key == "dhcpend") then
		local n = tonumber( value )
		if (n) then c.DHCPEnd = math.Clamp( n, 1, 65534 ) end
	elseif (key == "firewall") then
		c.Firewall = (value == "1") || (value == "on")
	elseif (key == "nat") then
		c.NAT = (value == "1") || (value == "on")
	end
end

// Strip a query string and leading/trailing slashes off a request path to get
// the page id ("" = home, "wifi"/"lan"/"firewall" = sub-pages).
function DRV:WebPage( path )
	path = tostring( path or "" )
	path = string.gsub( path, "%?.*$", "" )
	path = string.gsub( path, "/+", "/" )
	path = string.gsub( path, "^/", "" )
	path = string.gsub( path, "/$", "" )
	return path
end

// Shared navigation bar linking the pages.
function DRV:WebNav( current )
	local items = { { "", "Home" }, { "wifi", "Wi-Fi" }, { "lan", "LAN" }, { "firewall", "Firewall" } }
	local parts = {}
	for _, it in ipairs( items ) do
		table.insert( parts, '<a href="/' .. it[ 1 ] .. '">' .. it[ 2 ] .. '</a>' )
	end
	return "<p>Navigation: " .. table.concat( parts, " | " ) .. "</p>"
end

// Main page: status overview + network links.
function DRV:PageHome()
	local e = self.Entity
	local c = self:GetCfg()
	local bb = e:GetBSubnet()
	local lines = {}
	table.insert( lines, "<h1>WebGear Router</h1>" )
	table.insert( lines, self:WebNav( "" ) )
	table.insert( lines, "<h2>Status</h2>" )
	table.insert( lines, "<p><b>Model:</b> " .. tostring( e:GetClass() ) .. "</p>" )
	table.insert( lines, "<p><b>IPv4 LAN:</b> " .. tostring( e:GetFullIP() or "unassigned" ) .. "</p>" )
	local wan = (e.GetFullBIP && e:GetFullBIP())
	if (wan) then table.insert( lines, "<p><b>IPv4 WAN /32 (NAT):</b> " .. tostring( wan ) .. " in " .. tostring( PCMod.IPv4.BackbonePrefix( bb ) ) .. "</p>" ) end
	table.insert( lines, "<p><b>IPv6:</b> " .. tostring( e:GetIPv6() or "unassigned" ) .. "</p>" )
	if (e.GetIPv6Prefix && e:GetIPv6Prefix()) then table.insert( lines, "<p><b>Prefix:</b> " .. tostring( e:GetIPv6Prefix() ) .. "</p>" ) end
	if (bb) then table.insert( lines, "<p><b>Backbone:</b> " .. tostring( PCMod.IPv6.BackbonePrefix( bb ) ) .. "</p>" ) else table.insert( lines, "<p><b>Backbone:</b> none (standalone)</p>" ) end
	table.insert( lines, "<p><b>Wi-Fi:</b> " .. (c.Wireless and "enabled" or "disabled") .. "</p>" )
	table.insert( lines, "<p><b>Firewall:</b> " .. (c.Firewall and "on" or "off") .. "</p>" )
	table.insert( lines, "<p><b>NAT:</b> " .. (c.NAT and "on" or "off") .. "</p>" )
	table.insert( lines, "<p><b>DHCP pool:</b> ." .. tostring( c.DHCPStart ) .. " - ." .. tostring( c.DHCPEnd ) .. "</p>" )

	local wc = 0
	for _, v in pairs( self.WirelessClients or {} ) do if (v) then wc = wc + 1 end end
	table.insert( lines, "<p><b>Wi-Fi clients:</b> " .. tostring( wc ) .. "</p>" )

	table.insert( lines, "<h2>Network</h2>" )
	local links = {}
	if (self:IsBackbone()) then
		for lanid, port in pairs( self.ChildLan or {} ) do
			local child = port && port.ConEnt
			local name = "LAN router #" .. tostring( (child && child:IsValid() && child:EntIndex()) or "?" )
			table.insert( links, '<li><a href="fd00:' .. tostring( bb ) .. ':0:' .. tostring( lanid ) .. '::1">' .. name .. '</a></li>' )
		end
		for nbb, port in pairs( self.Neighbors or {} ) do
			table.insert( links, '<li><a href="fd00:' .. tostring( nbb ) .. '::1">Backbone fd00:' .. tostring( nbb ) .. '::/32</a></li>' )
		end
	else
		if (bb) then
			table.insert( links, '<li><a href="fd00:' .. tostring( bb ) .. '::1">Upstream backbone fd00:' .. tostring( bb ) .. '::/32</a></li>' )
		end
	end
	if (#links == 0) then table.insert( links, "<li>No links.</li>" ) end
	table.insert( lines, "<ul>" )
	for _, l in ipairs( links ) do table.insert( lines, l ) end
	table.insert( lines, "</ul>" )

	return table.concat( lines, "\n" )
end

function DRV:PageWifi()
	local c = self:GetCfg()
	local lines = {}
	table.insert( lines, "<h1>Wi-Fi</h1>" )
	table.insert( lines, self:WebNav( "wifi" ) )
	if (c.Wireless) then
		table.insert( lines, '<p><b>Status:</b> enabled <a href="?wireless=0">[Disable]</a></p>' )
	else
		table.insert( lines, '<p><b>Status:</b> disabled <a href="?wireless=1">[Enable]</a></p>' )
	end
	table.insert( lines, '<p><b>Password:</b> <input type="text" name="wpass" value="' .. tostring( c.WirePass ) .. '"> <input type="submit" value="Set Password"></p>' )
	return table.concat( lines, "\n" )
end

function DRV:PageLAN()
	local c = self:GetCfg()
	local lines = {}
	table.insert( lines, "<h1>LAN / DHCP</h1>" )
	table.insert( lines, self:WebNav( "lan" ) )
	table.insert( lines, '<p><b>DHCP start:</b> <input type="text" name="dhcpstart" value="' .. tostring( c.DHCPStart ) .. '"></p>' )
	table.insert( lines, '<p><b>DHCP end:</b> <input type="text" name="dhcpend" value="' .. tostring( c.DHCPEnd ) .. '"></p>' )
	if (c.NAT) then
		table.insert( lines, '<p><b>NAT:</b> on <a href="?nat=0">[Disable]</a></p>' )
	else
		table.insert( lines, '<p><b>NAT:</b> off <a href="?nat=1">[Enable]</a></p>' )
	end
	table.insert( lines, '<p><input type="submit" value="Apply"></p>' )
	return table.concat( lines, "\n" )
end

function DRV:PageFirewall()
	local c = self:GetCfg()
	local lines = {}
	table.insert( lines, "<h1>Firewall & Port Forwarding</h1>" )
	table.insert( lines, self:WebNav( "firewall" ) )

	if (c.Firewall) then
		table.insert( lines, '<p><b>Firewall:</b> on <a href="?firewall=0">[Disable]</a></p>' )
	else
		table.insert( lines, '<p><b>Firewall:</b> off <a href="?firewall=1">[Enable]</a></p>' )
	end
	table.insert( lines, "<p>Rules block matching traffic when on (default: allow all).</p>" )

	table.insert( lines, "<h2>Rules</h2>" )
	local rc = 0
	for i, r in ipairs( c.FirewallRules or {} ) do
		rc = rc + 1
		local desc = tostring( r.dir ) .. " "
		if (r.src ~= "") then desc = desc .. r.src else desc = desc .. "any" end
		desc = desc .. " -> "
		if (r.dst ~= "") then desc = desc .. r.dst else desc = desc .. "any" end
		if (r.port ~= 0) then desc = desc .. ":" .. r.port end
		table.insert( lines, '<p>' .. desc .. ' <a href="?delfw=' .. i .. '">[Delete]</a></p>' )
	end
	if (rc == 0) then table.insert( lines, "<p>No rules.</p>" ) end
	table.insert( lines, "<h3>Add rule</h3>" )
	table.insert( lines, "<form>" )
	table.insert( lines, '<p>Direction (in/out) <input type="text" name="fwdir" value=""></p>' )
	table.insert( lines, '<p>Source IP (blank=any) <input type="text" name="fwsrc" value=""></p>' )
	table.insert( lines, '<p>Dest IP (blank=any) <input type="text" name="fwdst" value=""></p>' )
	table.insert( lines, '<p>Port (blank=any) <input type="text" name="fwport" value=""></p>' )
	table.insert( lines, '<p><input type="submit" value="Add Rule"></p>' )
	table.insert( lines, "</form>" )

	table.insert( lines, "<h2>Port Forwarding</h2>" )
	local pc = 0
	for wan, r in pairs( c.Forwards or {} ) do
		pc = pc + 1
		table.insert( lines, '<p>' .. tostring( wan ) .. ' -> ' .. tostring( r.ip ) .. ':' .. tostring( r.port ) .. ' <a href="?delpf=' .. tostring( wan ) .. '">[Delete]</a></p>' )
	end
	if (pc == 0) then table.insert( lines, "<p>No rules.</p>" ) end
	table.insert( lines, "<form>" )
	table.insert( lines, '<p>WAN port <input type="text" name="pfwan" value=""></p>' )
	table.insert( lines, '<p>Local IP <input type="text" name="pfip" value=""></p>' )
	table.insert( lines, '<p>Local port <input type="text" name="pfport" value=""></p>' )
	table.insert( lines, '<p><input type="submit" value="Add Forward"></p>' )
	table.insert( lines, "</form>" )

	return table.concat( lines, "\n" )
end

// A config/status "web page" served to the in-game browser (port 80).
function DRV:GetWebPage( path )
	local page = self:WebPage( path )
	if (page == "wifi") then return self:PageWifi() end
	if (page == "lan") then return self:PageLAN() end
	if (page == "firewall") then return self:PageFirewall() end
	return self:PageHome()
end

// Reply to an in-game HTTP request: apply any ?query settings, then serve.
function DRV:HandleWebRequest( packet )
	local path = (packet.Body && packet.Body[2]) or ""
	self:ApplyWebQuery( path )
	local page = self:GetWebPage( path )
	local src = self.Entity:GetSourceAddress( packet.Source ) or self.Entity:GetFullIP()
	if (!src) then return false end
	packet.Delivered = true
	local pid = PCMod.Network.CreatePacket( src, packet.Source, 80, { "http-response", page } )
	if (pid) then self:ProcessPacket( pid ) end
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
	self.Leases = {}
	self.Children = {}
	self.ChildLan = {}
	self.Neighbors = {}
	self.Uplink = nil
	self.ForwardFlows = {}
end