
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
	else
		// IPv4 (and mapped IPv6) are classified by their historic address
		// space; an unknown IPv6 /32 is NOT retrofitted onto the IPv4 core, it
		// is forwarded upstream instead.
		if ((type( dest4 ) == "string")) then
			if (string.find( dest4, "10.0", 1, true )) then toBackbone = true end
			if (string.find( dest4, "192.168", 1, true )) then toLAN = true end
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
			PCMod.Network.RegisterPC( port.ConEnt, bb, true )
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
			PCMod.Network.UnRegisterPC( port.ConEnt, self.Entity:GetBSubnet(), true )
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
	local mask = (tonumber( PCMod.Cfg.LanNetmask ) == 16) and 16 or 24
	local start = tonumber( PCMod.Cfg.DHCPStart ) or 2
	local finish = tonumber( PCMod.Cfg.DHCPEnd ) or ((mask == 16) and 65534 or 254)
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
	local src = self.Entity:GetSourceAddress( packet.Source ) or self.Entity:GetFullIP()
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
	self.Leases = {}
	self.Children = {}
	self.ChildLan = {}
	self.Neighbors = {}
	self.Uplink = nil
end