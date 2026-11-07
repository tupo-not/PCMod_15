
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
// DHCP/IP mechanics (including per-scope settings) live in pcmod/sh_dhcp.lua.
DRV.DHCPSettings = PCMod.DHCP.Settings

function DRV:Initialize()
	if (!self.Entity) then return end
	
	PCMod.Msg( "Initializing WebGear Router Core..", true )
	
	// Hook in our events
	self.Entity:AddEHook( "driver", self.Name, "linked" ) -- Something has been linked up
	self.Entity:AddEHook( "driver", self.Name, "unlinked" ) -- Something has been unlinked
	
	// Get a list of valid ports. The WAN side is fibre on the LAN modem and a
	// flagged Ethernet port on the Router variant, so split by role instead
	// of assuming every network port is LAN.
	local ports = self.Entity:Ports()
	local tmp = {}
	self.LAN = {}
	for k, v in pairs( ports ) do
		if ((v.Type == "network") && (!v.WAN)) then
			table.insert( tmp, k )
			table.insert( self.LAN, k, v )
		end
	end
	self.NPorts = table.Copy( tmp )
	local tmp = {}
	self.BLAN = {}
	for k, v in pairs( ports ) do
		if ((v.Type == "optic") || ((v.Type == "network") && v.WAN)) then
			table.insert( tmp, k )
			table.insert( self.BLAN, k, v )
		end
	end
	self.OPorts = table.Copy( tmp )
	// Backbone-side leases. Computers attached through a modem/switch use the
	// same DHCP allocator as LAN clients, only the pool and address space
	// differ. LAN routers occupy hosts 2..11, so this pool starts at 12.
	self.BLeases = {}
	self.BLeasePort = {}

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
		local macs = data[4] or {}
		local pid = PCMod.Network.CreatePacket( body[1], body[2], body[3], body[4], nil, macs.SourceMAC, macs.DestMAC, data[5] )
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

// Short label shown next to a traceroute hop.
function DRV:TraceLabel()
	if (self.Wireless) then return "WRTR" end
	if (self.Entity.GetClass && (self.Entity:GetClass() == "pcmod_brouter")) then return "BRTR" end
	return "RTR"
end

// The address a traceroute hop reply should come from. A reply to a LAN-side
// probe uses the LAN gateway (the address that host knows); a reply to a
// backbone-side probe uses the WAN/backbone address so the reply routes back.
function DRV:TraceReplySource( packet, side )
	local v6 = PCMod.IPv6.IsIPv6( packet.Source )
	local sip
	if (side == "lan") then
		if (v6) then
			sip = self.Entity.GetIPv6Gateway && self.Entity:GetIPv6Gateway()
			if (!sip) then sip = self.Entity.GetIPv6 && self.Entity:GetIPv6() end
		else
			if (self.Entity.GetClass && (self.Entity:GetClass() == "pcmod_brouter")) then
				if (PCMod.IPv4 && self.Entity.GetBSubnet) then
					sip = PCMod.IPv4.BackboneAddress( self.Entity:GetBSubnet(), 1 )
				end
			else
				// Use the router's actual LAN gateway (its fourth octet is not
				// always .1 once masks longer than /24 are in play).
				sip = self.Entity.GetFullIP && self.Entity:GetFullIP()
			end
			if (!sip) then sip = self.Entity.GetFullIP && self.Entity:GetFullIP() end
		end
	else
		if (v6) then sip = self.Entity.GetBIPv6 && self.Entity:GetBIPv6() end
		if (!sip) then sip = self.Entity.GetFullBIP && self.Entity:GetFullBIP() end
		if (!sip) then sip = self.Entity.GetFullIP && self.Entity:GetFullIP() end
	end
	return sip, self:TraceLabel()
end

// Report an expired traceroute probe to its sender: { netTraceHop, hk, thdl,
// hopAddress, hopLabel, hopNumber }. The reply keeps the probe's source port so
// it traverses the sender's NAT correctly.
function DRV:SendTraceHop( packet, side )
	local sip, sid = self:TraceReplySource( packet, side )
	if (!sip) then return false end
	local hk = packet.Body && packet.Body[2]
	local thdl = packet.Body && packet.Body[3]
	local hop = (packet.Body && packet.Body[4]) or packet.TTL
	packet.Delivered = true
	self:Process( { "sendpacket", { sip, packet.Source, packet.SourcePort or packet.Port, { "netTraceHop", hk, thdl, sip, sid, hop } } } )
	return true
end

// Consume one TTL for a forwarded packet. Returns false when the packet died
// here (and, for traceroute probes, a hop report was sent).
function DRV:CheckTTL( packet, side )
	local ttl = tonumber( packet.TTL ) or tonumber( PCMod.Cfg && PCMod.Cfg.DefaultTTL ) or 64
	if (ttl <= 1) then
		if ((packet.Body) && (packet.Body[1] == "netTrace")) then
			self:SendTraceHop( packet, side )
		end
		packet.Delivered = true
		return false
	end
	packet.TTL = ttl - 1
	return true
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
	// Port forwarding + PAT. An inbound packet to a forwarded port is destination
	// NAT'ed to the internal host (each peer given a stable ephemeral source port
	// so the host can tell clients apart); replies are translated back at both
	// edges.
	local isSelf = (self.Entity.IsAddressedTo && self.Entity:IsAddressedTo( packet.Dest ))
	if (isSelf) then
		// Forwarded reply (SNAT): the internal host replied on an ephemeral port.
		local flow = self:GetForwardFlow( packet.Port )
		if (flow) then
			local wanSrc = flow.pub or self.Entity:GetFullIP() or self.Entity:GetIPv6()
			if (wanSrc) then
				packet.Delivered = true
				local rpid = PCMod.Network.CreatePacket( wanSrc, flow.src, flow.port, packet.Body, nil, self.Entity:GetMAC(), packet.SourceMAC, packet.TTL )
				if (rpid) then self:ProcessPacket( rpid ) end
			end
			return
		end
		// Masquerade reply (DNAT): a peer replied to this router's WAN /32 on an
		// ephemeral port handed out by MasqueradeAndForward.
		local nat = self:GetNatOut( packet.Port )
		local wan = self.Entity.GetFullBIP && self.Entity:GetFullBIP()
		if (nat && wan && (PCMod.IPv6.ToIPv4( packet.Dest ) == wan)) then
			packet.Delivered = true
			local mpid = PCMod.Network.CreatePacket( packet.Source, nat.ip, nat.port, packet.Body, nil, packet.SourceMAC, packet.DestMAC, packet.TTL )
			if (mpid) then self:ProcessPacket( mpid ) end
			return
		end
		// Forward DNAT: inbound to a forwarded port.
		local rule = self:GetForwardRule( packet.Port )
		if (rule) then
			local lanSrc = self.Entity:GetFullIP() or self.Entity:GetIPv6()
			if (lanSrc) then
				self.FwdByPeer = self.FwdByPeer or {}
				local pk = tostring( packet.Source ) .. ":" .. tostring( packet.SourcePort or packet.Port )
				local eph = self.FwdByPeer[ pk ]
				if (!eph) then
					eph = self:AllocEph()
					self.FwdByPeer[ pk ] = eph
				end
				self:RememberForwardFlow( eph, packet.Source, (packet.SourcePort or packet.Port), packet.Dest )
				packet.Delivered = true
				local dpid = PCMod.Network.CreatePacket( lanSrc, rule.ip, rule.port, packet.Body, eph, self.Entity:GetMAC(), packet.SourceMAC, packet.TTL )
				if (dpid) then self:ProcessPacket( dpid ) end
			end
			return
		end
	end
	// Routers answer pings addressed to their own LAN/WAN address, the same way
	// a computer OS does. Reply from the address that was pinged so NAT on the
	// sender's router translates the response back correctly.
	if ((packet.Body) && (packet.Body[1] == "netPing") && (self.Entity.IsAddressedTo && self.Entity:IsAddressedTo( packet.Dest ))) then
		local hdl = { packet.Source, packet.SourcePort or packet.Port }
		local rbody = { "netPingResponse", packet.Body[2], "Router" }
		packet.Delivered = true
		self:Process( { "sendpacket", { packet.Dest, hdl[1], hdl[2], rbody } } )
		return
	end
	// A traceroute probe addressed to this router has reached its final hop.
	// Answer it as the destination, exactly like a host OS does.
	if ((isSelf) && (packet.Body) && (packet.Body[1] == "netTrace")) then
		local sid = self:TraceLabel()
		packet.Delivered = true
		self:Process( { "sendpacket", { packet.Dest, packet.Source, packet.SourcePort or packet.Port, { "netTraceResponse", packet.Body[2], packet.Body[3], sid } } } )
		return
	end
	// Minimal web server: a request to port 80 addressed to the router itself
	// (body { "http", path }) is answered with a plain-text config page.
	if ((packet.Port == 80) && (packet.Body) && (packet.Body[1] == "http") && (self.Entity.IsAddressedTo && self.Entity:IsAddressedTo( packet.Dest ))) then
		self:HandleWebRequest( packet )
		return
	end
	// TTL handling: a router that forwards this packet is one hop, so decrement
	// it. When it reaches zero the packet dies here; traceroute probes get a
	// hop report from this router's ingress-facing address.
	if ((!isSelf) && (!self:CheckTTL( packet, side ))) then return end
	// Resolve the destination. IPv4 is LAN-local only; IPv6 is routed by prefix
	// (explicit /64 and /32 routing table, no flooding, no IPv4 retrofitting).
	local dest6 = PCMod.IPv6.IsIPv6( packet.Dest )

	if (!dest6) then
		// Same-LAN IPv4 (192.168.x) is delivered locally and never leaves it.
		local port = self:HasPC( packet.Dest )
		if (port) then
			self.Entity:PushData( port, { "deliver", pid, pass } )
			return
		end
		if (self:DeliverToWirelessClient( packet )) then return end
		// 10.x backbone IPv4 routes across backbones; at the LAN edge a router
		// masquerades its private hosts behind its own /32.
		local bb4 = PCMod.IPv4.Parse( packet.Dest )
		if (bb4) then
			if (self:IsBackbone()) then
				// Backbone router: route my own /16 (host table) or a peer /16.
				local mybb = self.Entity:GetBSubnet()
				if (bb4.bb == mybb) then
					local cport = self:HasRouter( packet.Dest )
					if (cport) then
						self.Entity:PushData( cport, { "deliver", pid, pass } )
						return
					end
				else
					local nPort = self:RouteForBB( bb4.bb )
					if (nPort) then
						self.Entity:PushData( nPort, { "deliver", pid, pass } )
						return
					end
				end
			elseif (self.Uplink) then
				// LAN router: masquerade only traffic that originated from my own
				// hosts (LAN-side); forward the rest upstream without re-NAT.
				if (side == "lan") then
					self:MasqueradeAndForward( packet, pass )
				else
					self.Entity:PushData( self.Uplink, { "deliver", pid, pass } )
				end
				return
			end
		end
		PCMod.Msg( "[webgr]IPv4 target " .. tostring( packet.Dest ) .. " is not routable; dropping", true )
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
			// A backbone-attached station (through a modem/switch) has no /64
			// of its own; find it by its host address instead.
			local hostPort = self:HasRouter( packet.Dest )
			if (hostPort) then
				self.Entity:PushData( hostPort, { "deliver", pid, pass } )
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
		if (!port) then return end
		local cls = self.Entity:GetClass()
		// A switch passes a synthetic link event carrying the real far-side
		// device (data[3]); without one this is a normal direct cable.
		local peerEnt = data[ 3 ] || port.ConEnt
		if (!peerEnt) then return end
		local peer = peerEnt:GetClass()

		if ((cls == "pcmod_brouter") && PCMod.IsLanRouterClass( peer )) then
			// LAN router attaches to my backbone: give it a /64 of my /32 and a
			// WAN backbone address, then renumber its LAN.
			self:AttachLANRouter( data[ 1 ], port, peerEnt )
		elseif ((cls == "pcmod_brouter") && (peer == "pcmod_brouter")) then
			// Peer backbone: learn its /32 -> this port, then reconverge.
			self.BLAN[ data[ 1 ] ] = port
			if (!self.Neighbors) then self.Neighbors = {} end
			self.Neighbors[ peerEnt:GetBSubnet() ] = port
			self:RecalcRoutes()
			PCMod.Network.Reconverge()
		elseif ((cls == "pcmod_brouter") && (peerEnt.IsComputer == true)) then
			// A computer on the backbone side (typically through a modem) gets
			// a 10.x host address from this backbone's /24, not a private LAN
			// lease from some other router.
			self:AssignBackboneLease( peerEnt, data[ 1 ] )
		elseif (PCMod.IsLanRouterClass( cls ) && PCMod.IsRouterClass( peer )) then
			// My WAN uplink (directly or through a switch/modem).
			self.Uplink = port
		elseif (PCMod.IsLanRouterClass( cls ) && (peer != "pcmod_switch") && (peer != "pcmod_modem")) then
			// A computer plugs into a LAN port. Switches/modems themselves never
			// take a DHCP lease; the devices behind them do. A PC behind a modem
			// on the WAN side is not on this router's LAN, so it must not get a
			// 192.168 lease (that was why WAN-side laptops showed a LAN address).
			if (table.HasValue( self.NPorts, data[ 1 ] )) then
				self.LAN[ data[ 1 ] ] = port
				if (!self:HasLease( peerEnt )) then self:AssignLease( peerEnt ) end
			end
		end
	end
	if (e == "unlinked") then
		local peerEnt = data[ 2 ]
		if (!peerEnt) then return end
		local cls = self.Entity:GetClass()
		local peer = peerEnt.GetClass && peerEnt:GetClass() or ""

		if ((cls == "pcmod_brouter") && PCMod.IsLanRouterClass( peer )) then
			local lanid = self.Children && self.Children[ peerEnt:EntIndex() ]
			PCMod.Network.UnRegisterPC( peerEnt, self.Entity:GetBSubnet() )
			if (lanid && self.ChildLan) then self.ChildLan[ lanid ] = nil end
			if (self.Children) then self.Children[ peerEnt:EntIndex() ] = nil end
			// The detached LAN becomes standalone again.
			peerEnt:SetUpBB( 0 )
			peerEnt:SetLanID( 0 )
			local cdata = PCMod.Data[ peerEnt:EntIndex() ]
			local child = cdata && cdata.Drivers && cdata.Drivers[ "webgr_router" ]
			if (child && child.ReconfigureClients) then child:ReconfigureClients() end
		elseif ((cls == "pcmod_brouter") && (peer == "pcmod_brouter")) then
			if (self.Neighbors) then self.Neighbors[ peerEnt:GetBSubnet() ] = nil end
			self:RecalcRoutes()
			PCMod.Network.Reconverge()
		elseif ((cls == "pcmod_brouter") && (peerEnt.IsComputer == true)) then
			self:ReleaseBackboneLease( peerEnt )
		elseif ((cls == "pcmod_brouter") && (peerEnt.IsSwitch == true)) then
			// The modem/switch itself left this backbone port: its leases go
			// with it, even if no per-host event arrives.
			self:ReleaseBackboneLeasesOnPort( data[ 1 ] )
		elseif (PCMod.IsLanRouterClass( cls ) && PCMod.IsRouterClass( peer )) then
			self.Uplink = nil
			// Lost our uplink: fall back to standalone addressing.
			self.Entity:SetUpBB( 0 )
			self.Entity:SetLanID( 0 )
			self:ReconfigureClients()
		elseif (PCMod.IsLanRouterClass( cls ) && ((peer == "pcmod_switch") || (peer == "pcmod_modem"))) then
			// The cable to the switch itself was removed: drop a switch-derived
			// uplink if that was the port we were using.
			if (self.Uplink && (self.Uplink.ConEnt == peerEnt)) then
				self.Uplink = nil
				self.Entity:SetUpBB( 0 )
				self.Entity:SetLanID( 0 )
				self:ReconfigureClients()
			end
		elseif (PCMod.IsLanRouterClass( cls ) && (peer != "pcmod_switch") && (peer != "pcmod_modem")) then
			// Pulling the cable only takes the lease away when the client is
			// not still joined over Wi-Fi.
			if (!self:HasWirelessClient( peerEnt )) then self:ReleaseLease( peerEnt ) end
		end
	end
end

// Attach a LAN router that may be directly cabled or on the far side of a
// switch. The switch port carries the data; the child still gets its backbone
// /64 and uplink so its addressing (and the 10.x WAN shown when aiming) works.
function DRV:AttachLANRouter( idx, port, childEnt )
	self.BLAN[ idx ] = port
	if ((!childEnt) || (!childEnt:IsValid())) then return end
	if (!self.Children) then self.Children = {} end
	if (!self.ChildLan) then self.ChildLan = {} end
	local existing = self.Children[ childEnt:EntIndex() ]
	if (existing) then
		self.ChildLan[ existing ] = port
		return
	end
	local bb = self.Entity:GetBSubnet()
	PCMod.Network.RegisterPC( childEnt, bb )
	local lanid = self:NextLanID()
	childEnt:SetUpBB( bb )
	childEnt:SetLanID( lanid )
	self.Children[ childEnt:EntIndex() ] = lanid
	self.ChildLan[ lanid ] = port
	local cdata = PCMod.Data[ childEnt:EntIndex() ]
	local child = cdata && cdata.Drivers && cdata.Drivers[ "webgr_router" ]
	if (child) then
		if (child.SetLinkToEntity) then child:SetLinkToEntity( self.Entity ) end
		if (child.ReconfigureClients) then child:ReconfigureClients() end
	end
end

// ---------------------------------------------------------------------------
// DHCP/IP mechanics live in pcmod/sh_dhcp.lua (PCMod.DHCP). These thin
// wrappers keep the driver's historical method names.
// ---------------------------------------------------------------------------

function DRV:DHCPTable( scope ) return PCMod.DHCP.Table( self, scope ) end
function DRV:DHCPPool( scope ) return PCMod.DHCP.Pool( self, scope ) end
function DRV:DHCPLeaseHost( scope, pc ) return PCMod.DHCP.LeaseHost( self, scope, pc ) end
function DRV:DHCPAllocHost( scope, pc ) return PCMod.DHCP.AllocLease( self, scope, pc ) end
function DRV:DHCPDropHost( scope, pc ) return PCMod.DHCP.DropLease( self, scope, pc ) end

function DRV:StaticLeases() return PCMod.DHCP.StaticLeases( self ) end
function DRV:StaticLeaseForMAC( mac ) return PCMod.DHCP.StaticLeaseForMAC( self, mac ) end
function DRV:StaticLeaseHosts() return PCMod.DHCP.StaticHosts( self ) end
function DRV:AddStaticLease( ip, mac ) return PCMod.DHCP.AddStaticLease( self, ip, mac ) end
function DRV:DeleteStaticLease( idx ) return PCMod.DHCP.DeleteStaticLease( self, idx ) end

function DRV:ApplyDHCP( scope, pc, host, port ) return PCMod.DHCP.Apply( self, scope, pc, host, port ) end
function DRV:AssignDHCP( scope, pc, port ) return PCMod.DHCP.Assign( self, scope, pc, port ) end
function DRV:ReleaseDHCP( scope, pc, mask, net, low ) return PCMod.DHCP.Release( self, scope, pc, mask, net, low ) end
function DRV:RenewDHCP( scope, pc ) return PCMod.DHCP.Renew( self, scope, pc ) end

function DRV:AssignBackboneLease( pc, port )
	return (self:AssignDHCP( "wan", pc, port ) != nil)
end

function DRV:ReleaseBackboneLease( pc )
	return self:ReleaseDHCP( "wan", pc )
end

// Drop every backbone lease on a port (its modem/switch was unplugged).
function DRV:ReleaseBackboneLeasesOnPort( port )
	return PCMod.DHCP.ReleaseOnPort( self, "wan", port )
end

// Find this router's own port that leads to `other` (usually a switch).
function DRV:FindLinkPort( other )
	for k, v in pairs( self.Entity:Ports() or {} ) do
		if (v.Connected && (v.ConEnt == other)) then return k, v end
	end
	return nil
end

function DRV:SetLinkToEntity( other )
	local _, port = self:FindLinkPort( other )
	if (port) then self.Uplink = port end
	return (port != nil)
end

function DRV:HasDHCPLease( scope, pc )
	return PCMod.DHCP.Has( self, scope, pc )
end

function DRV:HasLease( pc )
	return self:HasDHCPLease( "lan", pc )
end

// True when the device on this port (or anything behind a switch on it) owns
// the address. Returned port stays the router's own port, so delivery still
// goes through the switch.
function DRV:PortMatchesAddress( port, ip )
	local ent = port && port.ConEnt
	if (!ent) then return false end
	if (ent.IsAddressedTo && ent:IsAddressedTo( ip )) then return true end
	if (ent.IsSwitch && ent.GetBridgePeers) then
		for _, p in ipairs( ent:GetBridgePeers() ) do
			local pe = p.Ent
			if ((pe) && (pe.IsAddressedTo) && (pe:IsAddressedTo( ip ))) then return true end
		end
	end
	return false
end

function DRV:HasRouter( ip )
	PCMod.Msg( "[webgr]looking for router " .. ip, true )
	for k, v in pairs( self.BLAN ) do
		if (v.Connected) then
			PCMod.Msg( "[webgr]port " .. k .. " has the ips " .. tostring(v.ConEnt:GetFullIP()) .. "(" .. tostring(v.ConEnt:GetFullBIP()) .. ")", true )
			if (self:PortMatchesAddress( v, ip )) then
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
			if (self:PortMatchesAddress( v, ip )) then
				return k
			end
		end
	end
	return false
end

// True when the PC is cabled to this router, directly or through a switch.
function DRV:IsWiredClient( pc )
	if ((!pc) || (!pc:IsValid())) then return false end
	for _, v in pairs( self.LAN or {} ) do
		if (v.Connected) then
			local ent = v.ConEnt
			if (ent == pc) then return true end
			if ((ent) && (ent.IsSwitch) && (ent.GetBridgePeers)) then
				for _, p in ipairs( ent:GetBridgePeers() ) do
					if (p.Ent == pc) then return true end
				end
			end
		end
	end
	return false
end

// True when the PC is joined to this router over Wi-Fi.
function DRV:HasWirelessClient( pc )
	if (!pc) then return false end
	return ((self.WirelessClients) && (self.WirelessClients[ pc:EntIndex() ] != nil)) or false
end

// Register a PC that connected to this router over Wi-Fi.
function DRV:AddWirelessClient( pc )
	if ((!pc) || (!pc:IsValid())) then return false end
	if (!self.WirelessClients) then self.WirelessClients = {} end
	self.WirelessClients[ pc:EntIndex() ] = pc
	// AssignLease reuses the lease the client already holds from us, so a
	// wired client joining Wi-Fi keeps its address and a Wi-Fi-only client on
	// a second router gets a secondary address.
	local host = self:AssignLease( pc )
	if (!host) then return "full" end
	return "assigned"
end

// Release and immediately re-request a client's lease. The control panel's
// "Renew" button uses this to pick up the router's current pool/netmask
// without physically relinking the device. A client with no recorded lease is
// treated like a fresh link, so a stale lease table self-heals.
function DRV:RenewLease( pc )
	return self:RenewDHCP( "lan", pc )
end

// Netmask prefix for this router's private LAN, anywhere in 16-32.
function DRV:GetLanNetmask()
	local m = tonumber( self:GetCfg().LanNetmask ) or 24
	return math.Clamp( math.floor( m ), 16, 32 )
end

// The third octet of the LAN network (0-255).
function DRV:GetLanNet()
	return math.Clamp( math.floor( tonumber( self:GetCfg().LanNet ) or 0 ), 0, 255 )
end

// The fourth octet of the LAN network, used by masks longer than /24.
function DRV:GetLanLow()
	return math.Clamp( math.floor( tonumber( self:GetCfg().LanLow ) or 0 ), 0, 255 )
end

// Number of addresses in one subnet of the given mask.
function DRV:LanBlockSize( mask )
	mask = math.Clamp( math.floor( tonumber( mask ) or self:GetLanNetmask() ), 16, 32 )
	return 2 ^ (32 - mask)
end

// Offset of the LAN subnet start within 192.168.0.0/16 (0-65535), aligned to
// the subnet size. Masks shorter than /24 snap LanNet down to the enclosing
// block; masks longer than /24 use LanLow for the fourth octet.
function DRV:ComputeLanBase( mask, net, low )
	mask = math.Clamp( math.floor( tonumber( mask ) or self:GetLanNetmask() ), 16, 32 )
	net = math.Clamp( math.floor( tonumber( net ) or self:GetLanNet() ), 0, 255 )
	low = math.Clamp( math.floor( tonumber( low ) or self:GetLanLow() ), 0, 255 )
	local size = self:LanBlockSize( mask )
	local raw
	if (mask > 24) then
		raw = (net * 256) + low
	elseif (mask == 24) then
		raw = net * 256
	else
		local perNet = 2 ^ (24 - mask)
		raw = math.floor( net / perNet ) * perNet * 256
	end
	return math.floor( raw / size ) * size
end

function DRV:GetLanBase()
	return self:ComputeLanBase()
end

// Human-readable LAN prefix, e.g. "192.168.5.0/24" or "192.168.0.0/16".
function DRV:GetLanPrefix( mask, net, low )
	local base = self:ComputeLanBase( mask, net, low )
	local m = math.Clamp( math.floor( tonumber( mask ) or self:GetLanNetmask() ), 16, 32 )
	return "192.168." .. tostring( math.floor( base / 256 ) ) .. "." .. tostring( base % 256 ) .. "/" .. tostring( m )
end

// Last leaseable host id within the subnet. Host 1 is the gateway and the last
// address is the broadcast, so a /30 has a single client (id 2).
function DRV:PoolMax()
	return math.max( 2, self:LanBlockSize() - 2 )
end

// Keep the pool inside the current subnet and ordered. Host 1 is the gateway,
// so the first leaseable id is always 2.
function DRV:ClampDHCPPool()
	local c = self:GetCfg()
	local max = self:PoolMax()
	local start = tonumber( c.DHCPStart ) or 2
	local finish = tonumber( c.DHCPEnd ) or 254
	start = math.Clamp( start, 2, max )
	finish = math.Clamp( finish, start, max )
	c.DHCPStart = start
	c.DHCPEnd = finish
end

// Move this router's own LAN gateway onto the configured network.
function DRV:ApplyLanAddress()
	if (self.Entity:GetClass() == "pcmod_brouter") then return end
	local addr = self:GetLanBase() + 1
	self.Entity:SetSubnet( math.floor( addr / 256 ) )
	self.Entity:SetIP( addr % 256 )
end

// Re-issue every lease after the addressing changed (netmask, network or
// third octet): release under the OLD decomposition, then assign under the new.
function DRV:RenumberLeases( oldMask, oldNet, oldLow )
	local clients = {}
	for _, pc in pairs( self.Leases or {} ) do
		if ((pc) && (pc.IsValid) && (pc:IsValid())) then clients[ #clients + 1 ] = pc end
	end
	for _, pc in ipairs( clients ) do
		self:ReleaseLease( pc, oldMask, oldNet, oldLow )
	end
	for _, pc in ipairs( clients ) do
		self:AssignLease( pc )
	end
end

// Change the LAN subnet size (16-32). Existing leases are renumbered onto the
// new block and the pool is clamped to it.
function DRV:SetLanNetmask( mask )
	mask = math.Clamp( math.floor( tonumber( mask ) or 24 ), 16, 32 )
	local c = self:GetCfg()
	local oldMask, oldNet, oldLow = self:GetLanNetmask(), self:GetLanNet(), self:GetLanLow()
	if (mask == oldMask) then return end
	c.LanNetmask = mask
	self:ClampDHCPPool()
	self:RenumberLeases( oldMask, oldNet, oldLow )
	self:ApplyLanAddress()
end

// Change the third octet of the LAN network (0-255); this selects a .0 base.
function DRV:SetLanNet( net )
	local n = math.Clamp( math.floor( tonumber( net ) or 0 ), 0, 255 )
	local c = self:GetCfg()
	local oldMask, oldNet, oldLow = self:GetLanNetmask(), self:GetLanNet(), self:GetLanLow()
	local oldBase = self:GetLanBase()
	if ((n == oldNet) && (oldLow == 0)) then return end
	c.LanNet = n
	c.LanLow = 0
	// A shorter mask can snap several third octets to the same block; only
	// renumber when the actual network moved.
	if (self:GetLanBase() != oldBase) then
		self:RenumberLeases( oldMask, oldNet, oldLow )
		self:ApplyLanAddress()
	end
end

// Move the LAN network anywhere inside 192.168.0.0/16. The base is aligned to
// the subnet size and stored as LanNet/LanLow so it survives saves.
function DRV:SetLanBase( base )
	local c = self:GetCfg()
	local oldMask, oldNet, oldLow = self:GetLanNetmask(), self:GetLanNet(), self:GetLanLow()
	local oldBase = self:GetLanBase()
	base = math.Clamp( math.floor( tonumber( base ) or 0 ), 0, 65535 )
	base = self:ComputeLanBase( oldMask, math.floor( base / 256 ), base % 256 )
	c.LanNet = math.floor( base / 256 )
	c.LanLow = base % 256
	if (base != oldBase) then
		self:RenumberLeases( oldMask, oldNet, oldLow )
		self:ApplyLanAddress()
	end
end

// ---------------------------------------------------------------------------
// Shared DHCP lease table. LAN clients and backbone-side hosts use the same
// allocator; only the pool bounds and the address applier differ.
// ---------------------------------------------------------------------------

// Compatibility wrappers around the unified DHCP engine. Callers keep the
// familiar LAN/backbone names while sharing one implementation.
function DRV:AssignLease( pc )
	return self:AssignDHCP( "lan", pc )
end

function DRV:ReleaseLease( pc, mask, net, low )
	return self:ReleaseDHCP( "lan", pc, mask, net, low )
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
		if ((pc) && (pc.IsValid) && (pc:IsValid())) then self:PushClientConfig( pc, upbb, lanid ) end
	end
	for _, pc in pairs( self.WirelessClients or {} ) do
		if ((pc) && (pc.IsValid) && (pc:IsValid())) then self:PushClientConfig( pc, upbb, lanid ) end
	end
end

// Renumber one client for this router: its primary address when we handed it
// out, otherwise the secondary lease it holds from us.
function DRV:PushClientConfig( pc, upbb, lanid )
	local ipdata = pc.Data && pc:Data() && pc:Data().IP
	if (ipdata && ((ipdata.Router == self.Entity:EntIndex()) || (ipdata.Router == nil) || (ipdata.Router == false))) then
		if (pc.SetUpBB) then pc:SetUpBB( upbb ) end
		if (pc.SetLanID) then pc:SetLanID( lanid ) end
		return
	end
	// The primary belongs to another router: renumber only the secondary we
	// handed out.
	if (pc.UpdateExtraIPRouter) then pc:UpdateExtraIPRouter( self.Entity:EntIndex(), upbb, lanid ) end
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
	if ((!pc) || (!pc:IsValid())) then return end
	if (self.WirelessClients && self.WirelessClients[ pc:EntIndex() ]) then
		self.WirelessClients[ pc:EntIndex() ] = nil
	end
	// Leaving Wi-Fi must not strip the address of a client that is still
	// cabled to this router - the cable and the Wi-Fi link share the lease.
	// (ReleaseLease itself only takes away the address this router handed
	// out, so a client cabled to another router keeps that primary.)
	if (self:IsWiredClient( pc )) then return end
	self:ReleaseLease( pc )
end

// Deliver an in-flight packet to a Wi-Fi client on this router. Returns true
// when a client claimed it (and the packet is marked delivered).
function DRV:DeliverToWirelessClient( packet )
	for _, pc in pairs( self.WirelessClients or {} ) do
		if ((pc) && (pc:IsValid()) && (pc.IsAddressedTo) && (pc:IsAddressedTo( packet.Dest ))) then
			packet.Delivered = true
			packet.ViaWireless = true
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
	// Backbone-side pool (hosts 2..11 are reserved for attached LAN routers).
	if (c.WanDHCPStart == nil) then c.WanDHCPStart = 12 end
	if (c.WanDHCPEnd == nil) then c.WanDHCPEnd = 254 end
	// Static backbone reservations, each { ip = "10.x.x.y", mac = "AA:..." }.
	if (c.StaticLeases == nil) then c.StaticLeases = {} end
	// Per-router LAN size (16-32) and network octets, seeded from the global
	// defaults so existing routers keep their behaviour. LanLow selects the
	// fourth octet for masks longer than /24.
	if (c.LanNetmask == nil) then c.LanNetmask = tonumber( PCMod.Cfg.LanNetmask ) or 24 end
	if (c.LanLow == nil) then c.LanLow = 0 end
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

// Rules-based firewall (allow-list). When enabled (default deny) everything is
// dropped except the router's control plane (web 80 / ping 0), an established
// NAT reply, and traffic matching an allow rule (direction + optional
// source/dest IP + optional port). This is the classic "protect the LAN" model:
// to expose a service behind the router you open it with an allow rule (or a
// port-forward rule, which the firewall also gates).
function DRV:FirewallBlocks( packet, side )
	local c = self:GetCfg()
	if (!c.Firewall) then return false end
	local dir = (side == "wan") and "in" or "out"
	// Control plane always reachable (else the config UI dies).
	if ((packet.Port == 0) || (packet.Port == 80)) then return false end
	// An established NAT reply flows back automatically (stateful pass).
	if (self:GetForwardFlow( packet.Port )) then return false end
	if (self:GetNatOut( packet.Port )) then return false end
	for _, r in ipairs( c.FirewallRules or {} ) do
		if ((r.dir == dir) || (r.dir == "any")) then
			local m = true
			if ((r.src != "") && (r.src != packet.Source)) then m = false end
			if ((r.dst != "") && (r.dst != packet.Dest)) then m = false end
			if ((r.port != 0) && (r.port != packet.Port)) then m = false end
			if (m) then return false end
		end
	end
	// Default deny.
	return true
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
	if (parsed.dellease) then self:DeleteStaticLease( parsed.dellease ) end
	if (parsed.sip && parsed.smac) then
		self:AddStaticLease( parsed.sip, parsed.smac )
	end
	// Apply single-key settings in a fixed order: the addressing (netmask,
	// third octet) first, then the pool that is clamped against it. pairs()
	// order is not deterministic, which would make multi-key queries flaky.
	local order = { "wireless", "netmask", "lannet", "dhcpstart", "dhcpend", "firewall", "nat", "wpass" }
	// When the first pool bound is a bare host id, a dotted last bound is the
	// one that names the network, so let it derive the subnet.
	local startDotted = parsed.dhcpstart && (string.find( parsed.dhcpstart, "%." ) != nil)
	for _, k in ipairs( order ) do
		if (parsed[ k ] != nil) then
			local derive = (k == "dhcpend") && (!startDotted)
			self:ApplyWebSetting( k, parsed[ k ], derive )
		end
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

// PAT (port-address translation) state: each active connection gets a stable
// ephemeral source port, so many hosts can share one public /32 or one
// forwarded port at the same time.
function DRV:AllocEph()
	self.NextEph = (self.NextEph or 40000) + 1
	if (self.NextEph > 64999) then self.NextEph = 40000 end
	return self.NextEph
end

// Forward-connection reply mapping, keyed by the ephemeral port the router
// presented to the internal host.
function DRV:RememberForwardFlow( eph, src, port, pub )
	self.ForwardFlows = self.ForwardFlows or {}
	self.ForwardFlows[ tostring( eph ) ] = { src = src, port = port, pub = pub, time = CurTime() }
	if (table.Count( self.ForwardFlows ) > 128) then
		local now = CurTime()
		for k, v in pairs( self.ForwardFlows ) do
			if (v.time < now - 120) then self.ForwardFlows[ k ] = nil end
		end
	end
end

function DRV:GetForwardFlow( port )
	local f = self.ForwardFlows && self.ForwardFlows[ tostring( port ) ]
	if (!f) then return nil end
	if (f.time < (CurTime() - 120)) then
		self.ForwardFlows[ tostring( port ) ] = nil
		return nil
	end
	return f
end

// Outbound masquerade mapping, keyed by the ephemeral source port handed to the
// WAN, so a reply to this router's /32 is translated back to the internal host.
function DRV:RememberNatOut( eph, ip, port )
	self.NatOut = self.NatOut or {}
	self.NatOut[ tostring( eph ) ] = { ip = ip, port = port, time = CurTime() }
	if (table.Count( self.NatOut ) > 128) then
		local now = CurTime()
		for k, v in pairs( self.NatOut ) do
			if (v.time < now - 120) then self.NatOut[ k ] = nil end
		end
	end
end

function DRV:GetNatOut( port )
	local f = self.NatOut && self.NatOut[ tostring( port ) ]
	if (!f) then return nil end
	if (f.time < (CurTime() - 120)) then
		self.NatOut[ tostring( port ) ] = nil
		return nil
	end
	return f
end

// Masquerade an outbound LAN packet (PAT): rewrite its source to this router's
// WAN /32 and its source port to a stable ephemeral, then forward upstream. The
// reply is translated back in ProcessPacket (masquerade reply).
function DRV:MasqueradeAndForward( packet, pass )
	local wan = self.Entity.GetFullBIP && self.Entity:GetFullBIP()
	if (!wan) then
		PCMod.Msg( "[webgr]No WAN /32 to masquerade behind; dropping", true )
		return
	end
	// One stable ephemeral source port per (host : dest : port) connection.
	self.NatByPeer = self.NatByPeer or {}
	local ck = tostring( packet.Source ) .. ":" .. tostring( packet.Dest ) .. ":" .. tostring( packet.Port )
	local eph = self.NatByPeer[ ck ]
	if (!eph) then
		eph = self:AllocEph()
		self.NatByPeer[ ck ] = eph
		self:RememberNatOut( eph, packet.Source, packet.Port )
	end
	packet.Delivered = true
	local npid = PCMod.Network.CreatePacket( wan, packet.Dest, packet.Port, packet.Body, eph, self.Entity:GetMAC(), packet.DestMAC, packet.TTL )
	if (!npid) then return end
	local mem = self.Entity:Memory()
	if (!mem.P) then mem.P = {} end
	mem.P[ npid ] = true
	self.Entity:UpdateMemory( mem )
	self.Entity:PushData( self.Uplink, { "deliver", npid, pass } )
end

// A DHCP pool bound is a host id inside the subnet ("42") or a full dotted
// address ("192.168.4.1"). A dotted bound also selects the network: deriveBase
// true snaps the address to its subnet, false just measures it from the
// current base.
function DRV:ParsePoolBound( value, deriveBase )
	local v = tostring( value or "" )
	local a, b, c, d = string.match( v, "^(%d+)%.(%d+)%.(%d+)%.(%d+)$" )
	if (!a) then return tonumber( v ), nil end
	local abs = ((tonumber( c ) or 0) * 256) + (tonumber( d ) or 0)
	if (!deriveBase) then
		return abs - self:GetLanBase(), nil
	end
	local size = self:LanBlockSize()
	local base = math.floor( abs / size ) * size
	return abs - base, base
end

function DRV:ApplyWebSetting( key, value, deriveBase )
	local c = self:GetCfg()
	if (key == "wireless") then
		self:SetWireless( (value == "1") || (value == "on") )
	elseif (key == "wpass") then
		if (value == "random") then
			c.WirePass = tostring( math.random( 100000, 999999 ) )
		else
			c.WirePass = tostring( value or "" )
		end
	elseif (key == "netmask") then
		self:SetLanNetmask( value )
	elseif (key == "lannet") then
		self:SetLanNet( value )
	elseif (key == "dhcpstart") then
		local host, base = self:ParsePoolBound( value, true )
		if (base != nil) then self:SetLanBase( base ) end
		if (host != nil) then c.DHCPStart = host end
		self:ClampDHCPPool()
	elseif (key == "dhcpend") then
		// The first bound normally chooses the network; a dotted last bound
		// may choose it too when the first one is a bare host id.
		local host, base = self:ParsePoolBound( value, deriveBase == true )
		if (base != nil) then self:SetLanBase( base ) end
		if (host != nil) then c.DHCPEnd = host end
		self:ClampDHCPPool()
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
	if (self:IsBackbone()) then
		table.insert( items, { "static", "Static DHCP" } )
	end
	local parts = {}
	for _, it in ipairs( items ) do
		table.insert( parts, '<a href="/' .. it[ 1 ] .. '">' .. it[ 2 ] .. '</a>' )
	end
	return "<p>Navigation: " .. table.concat( parts, " | " ) .. "</p>"
end

// First and last address of a DHCP pool in dotted-quad form. The scope picks
// the network (LAN 192.168.x.y or backbone 10.x.x.y).
function DRV:DHCPPoolRange( scope )
	return PCMod.DHCP.PoolRange( self, scope )
end

function DRV:PoolRange()
	return self:DHCPPoolRange( "lan" )
end

function DRV:PageHome()
	local e = self.Entity
	local c = self:GetCfg()
	local bb = e:GetBSubnet()
	local lines = {}
	table.insert( lines, "<h1>WebGear Router</h1>" )
	table.insert( lines, self:WebNav( "" ) )
	table.insert( lines, "<hr>" )
	table.insert( lines, "<h2>Status</h2>" )
	table.insert( lines, "<p><b>Model:</b> " .. tostring( e:GetClass() ) .. "</p>" )
	if (self:IsBackbone()) then
		table.insert( lines, "<p><b>IPv4 WAN:</b> " .. tostring( e:GetFullBIP() or "unassigned" ) .. " in " .. tostring( PCMod.IPv4.BackbonePrefix( bb ) ) .. "</p>" )
	else
		table.insert( lines, "<p><b>IPv4 LAN:</b> " .. tostring( e:GetFullIP() or "unassigned" ) .. " on " .. self:GetLanPrefix() .. "</p>" )
		local wan = (e.GetFullBIP && e:GetFullBIP())
		if (wan) then table.insert( lines, "<p><b>IPv4 WAN /32 (NAT):</b> " .. tostring( wan ) .. " in " .. tostring( PCMod.IPv4.BackbonePrefix( bb ) ) .. "</p>" ) end
	end
	table.insert( lines, "<p><b>IPv6:</b> " .. tostring( e:GetIPv6() or "unassigned" ) .. "</p>" )
	if (e.GetIPv6Prefix && e:GetIPv6Prefix()) then table.insert( lines, "<p><b>Prefix:</b> " .. tostring( e:GetIPv6Prefix() ) .. "</p>" ) end
	if (bb) then table.insert( lines, "<p><b>Backbone:</b> " .. tostring( PCMod.IPv6.BackbonePrefix( bb ) ) .. "</p>" ) else table.insert( lines, "<p><b>Backbone:</b> none (standalone)</p>" ) end
	table.insert( lines, "<p><b>Wi-Fi:</b> " .. (c.Wireless and "enabled" or "disabled") .. "</p>" )
	table.insert( lines, "<p><b>Firewall:</b> " .. (c.Firewall and "on" or "off") .. "</p>" )
	table.insert( lines, "<p><b>NAT:</b> " .. (c.NAT and "on" or "off") .. "</p>" )
	local scope = self:IsBackbone() and "wan" or "lan"
	local first, last = self:DHCPPoolRange( scope )
	local startHost, finishHost = self:DHCPPool( scope )
	if (first) then
		table.insert( lines, "<p><b>DHCP pool:</b> " .. first .. " - " .. last .. " (" .. tostring( finishHost - startHost + 1 ) .. " hosts)</p>" )
	end
	if (self:IsBackbone()) then
		table.insert( lines, '<p><b>Static DHCP:</b> ' .. tostring( #self:StaticLeases() ) .. ' reservation(s) <a href="/static">[Manage]</a></p>' )
	end

	local wc = 0
	for _, v in pairs( self.WirelessClients or {} ) do if (v) then wc = wc + 1 end end
	table.insert( lines, "<p><b>Wi-Fi clients:</b> " .. tostring( wc ) .. "</p>" )

	table.insert( lines, "<hr>" )
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
	table.insert( lines, "<hr>" )
	table.insert( lines, "<h2>Addressing</h2>" )
	table.insert( lines, "<p><b>Network:</b> " .. self:GetLanPrefix() .. "</p>" )
	table.insert( lines, '<p><b>Netmask size:</b> <input type="text" name="netmask" value="' .. tostring( self:GetLanNetmask() ) .. '"> (16-32)</p>' )
	table.insert( lines, '<p><b>Quick:</b> <a href="?netmask=16">[/16]</a> <a href="?netmask=24">[/24]</a> <a href="?netmask=30">[/30]</a></p>' )
	table.insert( lines, "<hr>" )
	table.insert( lines, "<h2>DHCP pool</h2>" )
	local first, last = self:PoolRange()
	// Bounds are shown as full addresses; typing a different network here
	// (e.g. 192.168.4.1) also moves the LAN's subnet.
	table.insert( lines, '<p><b>First address:</b> <input type="text" name="dhcpstart" value="' .. first .. '"></p>' )
	table.insert( lines, '<p><b>Last address:</b> <input type="text" name="dhcpend" value="' .. last .. '"></p>' )
	local startHost, finishHost = self:DHCPPool( "lan" )
	local hosts = 0
	if (startHost) then hosts = math.max( 0, finishHost - startHost + 1 ) end
	table.insert( lines, "<p><b>Range:</b> " .. first .. " - " .. last .. " (" .. tostring( hosts ) .. " hosts)</p>" )
	table.insert( lines, "<p><b>Note:</b> host ids run 2-" .. tostring( self:PoolMax() ) .. " (.1 is the router). Type a full 192.168.x.y address to choose the network.</p>" )
	if (c.NAT) then
		table.insert( lines, '<p><b>NAT:</b> on <a href="?nat=0">[Disable]</a></p>' )
	else
		table.insert( lines, '<p><b>NAT:</b> off <a href="?nat=1">[Enable]</a></p>' )
	end
	table.insert( lines, '<p><input type="submit" value="Apply"></p>' )
	return table.concat( lines, "\n" )
end

// Backbone admin: static DHCP reservations, IP <-> MAC.
function DRV:PageStaticLeases()
	local bb = self.Entity:GetBSubnet()
	local lines = {}
	table.insert( lines, "<h1>Backbone static DHCP</h1>" )
	table.insert( lines, self:WebNav( "static" ) )
	table.insert( lines, "<hr>" )
	table.insert( lines, "<p>Reserve a backbone IPv4 for a MAC address. The reservation is handed out when that device links to the backbone.</p>" )
	table.insert( lines, "<p><b>Backbone:</b> " .. PCMod.IPv4.BackbonePrefix( bb ) .. " (hosts 12-254)</p>" )

	local list = self:StaticLeases()
	if (#list == 0) then
		table.insert( lines, "<p>No static leases.</p>" )
	else
		table.insert( lines, "<h2>Reservations</h2>" )
		for i, l in ipairs( list ) do
			table.insert( lines, '<p>' .. tostring( l.ip ) .. ' -> ' .. tostring( l.mac )
				.. ' <a href="?dellease=' .. i .. '">[Delete]</a></p>' )
		end
	end

	table.insert( lines, "<h2>Add / replace</h2>" )
	table.insert( lines, "<form>" )
	table.insert( lines, '<p>IPv4 <input type="text" name="sip" value=""></p>' )
	table.insert( lines, '<p>MAC <input type="text" name="smac" value=""></p>' )
	table.insert( lines, '<p><input type="submit" value="Save Lease"></p>' )
	table.insert( lines, "</form>" )
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
	table.insert( lines, "<p>When on, traffic is blocked by default; add allow rules below (web/ping and NAT replies always pass).</p>" )

	table.insert( lines, "<h2>Allow rules</h2>" )
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
	if (rc == 0) then table.insert( lines, "<p>No rules (everything except web/ping is blocked).</p>" ) end
	table.insert( lines, "<h3>Add allow rule</h3>" )
	table.insert( lines, "<form>" )
	table.insert( lines, '<p>Direction (in/out) <input type="text" name="fwdir" value=""></p>' )
	table.insert( lines, '<p>Source IP (blank=any) <input type="text" name="fwsrc" value=""></p>' )
	table.insert( lines, '<p>Dest IP (blank=any) <input type="text" name="fwdst" value=""></p>' )
	table.insert( lines, '<p>Port (blank=any) <input type="text" name="fwport" value=""></p>' )
	table.insert( lines, '<p><input type="submit" value="Add Allow Rule"></p>' )
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
	if ((page == "static") && self:IsBackbone()) then return self:PageStaticLeases() end
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
	local pid = PCMod.Network.CreatePacket( src, packet.Source, 80, { "http-response", page }, nil, self.Entity:GetMAC(), packet.SourceMAC )
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
	self.BLeases = {}
	self.BLeasePort = {}
	self.Children = {}
	self.ChildLan = {}
	self.Neighbors = {}
	self.Uplink = nil
	self.ForwardFlows = {}
	self.NatOut = {}
	self.FwdByPeer = {}
	self.NatByPeer = {}
	self.NextEph = nil
end