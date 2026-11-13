
// Router subsystem for PCMod 2 (This is for the router, not the pc)

SUBSYSTEM = PCMod.DeriveSubsystem( "base" )

SUBSYSTEM.NiceName = "WebGear Router Core"
SUBSYSTEM.Name = "router"
SUBSYSTEM.Type = "networking"
SUBSYSTEM.ID = 0
SUBSYSTEM.LAN = {}
SUBSYSTEM.BLAN = {}
SUBSYSTEM.NPorts = {}
SUBSYSTEM.OPorts = {}
SUBSYSTEM.BSubnet = nil
SUBSYSTEM.Subnet = nil
SUBSYSTEM.Wireless = false
// PCs ("stations") connected to this router over the air, keyed by ent index.
SUBSYSTEM.WirelessClients = {}

function SUBSYSTEM:Initialize()
	if (!self.Entity) then return end
	
	PCMod.Msg( "Initializing WebGear Router Core..", true )
	
	// Hook in our events
	self.Entity:AddEHook( "subsystem", self.Name, "linked" ) -- Something has been linked up
	self.Entity:AddEHook( "subsystem", self.Name, "unlinked" ) -- Something has been unlinked
	
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
	// Stateful IPv6 flows allow replies back into the LAN without opening it to
	// unsolicited WAN traffic.
	self.V6Flows = {}
	// L3 helpers are independent modules: ARP resolves an IPv4 next hop, NDP
	// resolves an IPv6 one, hello routing learns prefixes/neighbours.
	self.ArpCache = {}
	self.NdpCache = {}
	self.PrefixRoutes = {}
	self.NeighborMAC = {}
	self.Neighbors = {}
	self.RouteAdv = {}

	timer.Simple(1, function() if (!IsValid( self.Entity )) then return end self.BSubnet = self.Entity:GetBSubnet() end)
	timer.Simple(1, function() if (!IsValid( self.Entity )) then return end self.Subnet = self.Entity:GetSubnet() end)
	// A restored router may already carry a configured LAN (any RFC1918 block);
	// put its gateway back on it instead of the registration default.
	if ((!self:IsBackbone()) && self.Entity.Data) then self:ApplyLanAddress() end
	// Routing is a router-to-router hello protocol; switches only carry it.
	PCMod.Routing.Start( self )
	// A LAN router is a DHCP client on its WAN side. If the cable is already
	// restored, ask for an address once the ports exist.
	if (PCMod.IsLanRouterClass( self.Entity:GetClass() )) then
		timer.Simple( 1, function()
			if ((!IsValid( self.Entity )) || (self.Uplink)) then return end
			local ports = self.Entity:Ports()
			for _, idx in ipairs( self.OPorts or {} ) do
				if (ports[ idx ] && ports[ idx ].Connected) then
					self:SendDHCPDiscover( idx )
					break
				end
			end
		end )
	end
end

function SUBSYSTEM:PortSide( port )
	if (table.HasValue( self.NPorts, port )) then return "lan" end
	if (table.HasValue( self.OPorts, port )) then return "wan" end
	if (port == 0) then return "lan" end
	return nil
end

function SUBSYSTEM:InterfaceIP( side )
	if (side == "wan") then return (self.Entity.GetFullBIP && self.Entity:GetFullBIP()) or "0.0.0.0" end
	// A backbone's LAN-side interface is the MGMNT port; it shares the
	// backbone /24 and answers as the router's .1 address.
	if (self:IsBackbone()) then
		local bb = self.Entity.GetBSubnet && self.Entity:GetBSubnet()
		if (bb) then return PCMod.IPv4.BackboneAddress( bb, 1 ) end
	end
	return (self.Entity.GetFullIP && self.Entity:GetFullIP()) or "0.0.0.0"
end

// IPv6 source for neighbor discovery on an interface. A backbone uses its
// backbone /32 identity on both the fibre and MGMNT segments; a LAN router
// uses its LAN /64 address on the LAN side.
function SUBSYSTEM:InterfaceIPv6( side )
	if ((side == "wan") || self:IsBackbone()) then
		return (self.Entity.GetBIPv6 && self.Entity:GetBIPv6()) or false
	end
	return (self.Entity.GetIPv6 && self.Entity:GetIPv6()) or false
end

// Send a raw frame out one port. Wireless has no port index; deliver to the
// associated clients and let their DHCP/ARP state filter the frame.
function SUBSYSTEM:SendOnPort( port, data )
	if (port == 0) then
		for _, pc in pairs( self.WirelessClients or {} ) do
			if ((pc) && (pc.IsValid) && (pc:IsValid())) then
				local cd = PCMod.Data[ pc:EntIndex() ]
				local net = cd && cd.Subsystems && cd.Subsystems[ "network" ]
				if (net) then
					local function deliver()
						if ((pc.IsValid) && (pc:IsValid())) then net:DataRecieved( 0, data ) end
					end
					if (PCMod.Latency && PCMod.Latency.Deliver) then
						local dist = PCMod.Latency.DistanceBetween && PCMod.Latency.DistanceBetween( self.Entity, pc )
						local range = (PCMod.Cfg && PCMod.Cfg.WirelessRange) or 0
						PCMod.Latency.Deliver( deliver, "wireless", dist, range )
					else
						deliver()
					end
				end
			end
		end
		return
	end
	self.Entity:PushData( port, data )
end

function SUBSYSTEM:DataRecieved( port, data )
	PCMod.Msg( "[webgr]Checking Ports", true )
	// DHCP, ARP and routing hellos are application frames. Switches/modems
	// forward them as ordinary L2 traffic; only routers interpret them.
	if ((istable( data )) && (data[1] == "sendpacket") && (istable( data[2] ))) then
		local app = data[2][4]
		local macs = data[4] or {}
		if (PCMod.Net.IsDHCP( app )) then
			if (app[2] == "discover") then return self:DHCPServerReceive( port, app, macs ) end
			if (app[2] == "request") then return self:DHCPServerRequest( port, app, macs ) end
			if (app[2] == "release") then return self:DHCPServerRelease( app ) end
			return self:DHCPClientReceive( port, app )
		end
		if (PCMod.Net.IsARP( app )) then return PCMod.ARP.Handle( self, port, app, macs ) end
		if (PCMod.Net.IsNDP( app ) && PCMod.NDP) then return PCMod.NDP.Handle( self, port, app, macs ) end
		if (PCMod.Net.IsHello( app )) then
			// Routing hellos only make sense on an uplink/backbone interface.
			if (self:PortSide( port ) != "wan") then return true end
			return PCMod.Routing.Handle( self, port, app, macs )
		end
	end
	local side = self:PortSide( port )
	if (side) then return self:Process( data, side ) end
	// Data is from another port unrelated to us
end

function SUBSYSTEM:DHCPServerReceive( port, app, macs )
	local side = self:PortSide( port )
	if (!side) then return false end
	local payload = app[5] or {}
	local mac = payload.mac or (macs && macs.SourceMAC)
	local rec = PCMod.DHCPServer.Offer( self, side, mac, app[3], port )
	if (!rec) then return false end
	local cfg = PCMod.DHCPServer.Config( self, rec )
	local reply = {
		"sendpacket",
		{ self:InterfaceIP( side ), cfg.ip, PCMod.Net.DHCPClientPort, PCMod.Net.DHCPOffer( app[3], self.Entity:EntIndex(), cfg ) },
		nil,
		{ SourceMAC = self.Entity:GetMAC(), DestMAC = mac or PCMod.MAC.BROADCAST },
	}
	self:SendOnPort( port, reply )
	return true
end

function SUBSYSTEM:DHCPServerRequest( port, app, macs )
	local side = self:PortSide( port )
	if (!side) then return false end
	// The client names the server whose offer it accepted; other servers that
	// also saw the discover must stay quiet instead of NACKing it.
	if (app[4] && (tonumber( app[4] ) != self.Entity:EntIndex())) then return true end
	local payload = app[5] or {}
	local mac = payload.mac or (macs && macs.SourceMAC)
	local rec = PCMod.DHCPServer.Ack( self, mac, app[3], app[4] )
	local reply
	if (rec) then
		PCMod.ARP.Learn( self, rec.ip, mac, port )
		local cfg = PCMod.DHCPServer.Config( self, rec )
		reply = {
			"sendpacket",
			{ self:InterfaceIP( side ), cfg.ip, PCMod.Net.DHCPClientPort, PCMod.Net.DHCPAck( app[3], self.Entity:EntIndex(), cfg ) },
			nil,
			{ SourceMAC = self.Entity:GetMAC(), DestMAC = mac or PCMod.MAC.BROADCAST },
		}
	else
		reply = {
			"sendpacket",
			{ self:InterfaceIP( side ), PCMod.Net.BroadcastIP, PCMod.Net.DHCPClientPort, PCMod.Net.DHCPNack( app[3], self.Entity:EntIndex() ) },
			nil,
			{ SourceMAC = self.Entity:GetMAC(), DestMAC = mac or PCMod.MAC.BROADCAST },
		}
	end
	self:SendOnPort( port, reply )
	return true
end

function SUBSYSTEM:DHCPServerRelease( app )
	local payload = app[5] or {}
	PCMod.DHCPServer.Release( self, payload.mac )
	return true
end

// Offer/ack meant for this router when it is itself a DHCP client on WAN.
function SUBSYSTEM:DHCPClientReceive( port, app )
	if (!self.DHCPState) then return false end
	return PCMod.DHCPClient.Handle( self, app )
end

// Ask upstream for this router's own WAN address. The same discover as any
// host; the answer carries the backbone id and the /64 id it may use.
function SUBSYSTEM:SendDHCPDiscover( port, retries )
	retries = retries or 3
	local p = self.Entity:Ports()[ port ]
	if ((!p) || (!p.Connected)) then return false end
	self.LastDHCP = nil
	PCMod.DHCPClient.Start( self, {
		send = function( body )
			// Routers are network devices, so ENT:SendPacket would loop the
			// frame back into our own DataRecieved; push it onto the wire.
			self.Entity:PushData( port, {
				"sendpacket",
				{ "0.0.0.0", PCMod.Net.BroadcastIP, PCMod.Net.DHCPServerPort, body },
				nil,
				{ SourceMAC = self.Entity:GetMAC(), DestMAC = PCMod.MAC.BROADCAST },
			} )
		end,
		apply = function( cfg )
			PCMod.DHCPClient.ApplyRouter( self.Entity, self, cfg, port )
		end,
	} )
	if ((!self.LastDHCP) && (retries > 0) && timer && timer.Simple) then
		timer.Simple( 1, function()
			if ((!IsValid( self.Entity )) || (self.Uplink)) then return end
			self:SendDHCPDiscover( port, retries - 1 )
		end )
	end
	return true
end

// Resolve the last hop with the matching discovery protocol, then send. ARP
// answers "who has this IPv4"; NDP answers "who has this IPv6". Unknown hosts
// fall back to flooding the interface; switches do the L2 filtering.
function SUBSYSTEM:DeliverOnInterface( pid, packet, pass, ports, side )
	if ((!ports) || (#ports == 0)) then return false end
	local rec
	if (PCMod.IPv6.IsIPv6( packet.Dest )) then
		if (PCMod.NDP && PCMod.NDP.Resolve) then
			rec = PCMod.NDP.Resolve( self, packet.Dest, ports, self:InterfaceIPv6( side ) )
		else
			// Compatibility fallback when the NDP module is not loaded (old
			// saves/tests): resolve the derived IPv4 identity with ARP.
			rec = PCMod.ARP.Resolve( self, PCMod.IPv6.ToIPv4( packet.Dest ) or packet.Dest, ports, self:InterfaceIP( side ) )
		end
	else
		rec = PCMod.ARP.Resolve( self, packet.Dest, ports, self:InterfaceIP( side ) )
	end
	if (rec) then
		packet.DestMAC = rec.mac
		local out = rec.port or ports[ 1 ]
		self.Entity:PushData( out, { "deliver", pid, pass } )
		return true
	end
	packet.DestMAC = PCMod.MAC.BROADCAST
	for _, idx in ipairs( ports ) do
		self.Entity:PushData( idx, { "deliver", pid, pass } )
	end
	return true
end

function SUBSYSTEM:PushToRouted( pid, packet, pass, port, bb )
	if (!port) then return false end
	// Use the MAC of the immediate next-hop backbone, not the far destination.
	local route = self.Routes && self.Routes[ bb ]
	local via = route && route.via
	local mac = via && self.NeighborMAC && self.NeighborMAC[ via ]
	if (mac) then packet.DestMAC = mac end
	self.Entity:PushData( port, { "deliver", pid, pass } )
	return true
end

function SUBSYSTEM:Process( data, side )
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
	// PCMod.Msg( "Router subsystem is processing this packet ["..tag.."] { "..body[1]..", "..body[2]..", "..body[3]..", "..body[4].." }", true )
	PCMod.Msg( "[router] Router subsystem is processing this packet [" .. tag .. "]", true )
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
// IPv6 uses real prefix matching; IPv4 (and mapped IPv6) is classified by
// address space: backbone 100.x vs any RFC1918 LAN. The OnLink flags matter
// because an unknown on-link IPv6 host must be dropped, while a LAN address
// that belongs to a different router still has to be forwarded.
function SUBSYSTEM:ClassifyDestination( dest )
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
			if (PCMod.IPv4.Parse( dest4 )) then toBackbone = true end
			if (PCMod.IPv4.ParseLan( dest4 )) then toLAN = true end
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
function SUBSYSTEM:TraceLabel()
	if (self.Wireless) then return "WRTR" end
	if (self.Entity.GetClass && (self.Entity:GetClass() == "pcmod_brouter")) then return "BRTR" end
	return "RTR"
end

// The address a traceroute hop reply should come from. A reply to a LAN-side
// probe uses the LAN gateway (the address that host knows); a reply to a
// backbone-side probe uses the WAN/backbone address so the reply routes back.
function SUBSYSTEM:TraceReplySource( packet, side )
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
function SUBSYSTEM:SendTraceHop( packet, side )
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
function SUBSYSTEM:CheckTTL( packet, side )
	local ttl = tonumber( packet.TTL ) or tonumber( PCMod.Cfg && PCMod.Cfg.DefaultTTL ) or 64
	if (ttl <= 1) then
		if (PCMod.Network && PCMod.Network.LogPacket) then
			PCMod.Network.LogPacket( "expire", packet.Source, packet.Dest, packet.Port, packet.Body,
				"ttl exhausted at " .. self.Entity:GetClass() .. ":" .. tostring( self.Entity:EntIndex() ) )
		end
		if ((packet.Body) && (packet.Body[1] == "netTrace")) then
			self:SendTraceHop( packet, side )
		end
		packet.Delivered = true
		return false
	end
	packet.TTL = ttl - 1
	return true
end

function SUBSYSTEM:ProcessPacket( pid, pass, side )
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
	// WAN -> LAN boundary. Without NAT, an outside host could otherwise address
	// the router's LAN /64 (including its LAN gateway) or reach the LAN
	// identities by their private IPv4/mapped form. Only replies to flows this
	// LAN started, or explicit inbound firewall rules, may enter.
	if (side == "wan") then
		local lanTarget = self:IsLanSelfAddress( packet.Dest )
		if ((!lanTarget) && PCMod.IPv6.IsIPv6( packet.Dest )) then
			lanTarget = self:IsLanIPv6( packet.Dest )
		end
		if (lanTarget && (!self:WanToLanAllowed( packet ))) then
			PCMod.Msg( "[webgr]WAN -> LAN ingress blocked for " .. tostring( packet.Dest ), true )
			return
		end
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
		// Backbone: management-only. The firewall-is-off default does not
		// expose the panel to the backbone DHCP pool.
		if (!self:BackboneWebAllowed( packet.Source )) then
			PCMod.Msg( "[webgr]Backbone web access denied for " .. tostring( packet.Source ), true )
			packet.Delivered = true
			return
		end
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
		// Private LAN IPv4 is only meaningful on a LAN interface.
		if (PCMod.IPv4.ParseLan( packet.Dest )) then
			if (self:DeliverToWirelessClient( packet )) then return end
			self:DeliverOnInterface( pid, packet, pass, self.NPorts, "lan" )
			return
		end
		// Backbone IPv4 routes across backbones; at the LAN edge a router
		// masquerades its private hosts behind its own /32.
		local bb4 = PCMod.IPv4.Parse( packet.Dest )
		if (bb4) then
			if (self:IsBackbone()) then
				local mybb = self.Entity:GetBSubnet()
				if (bb4.bb == mybb) then
					if (self:DeliverToWirelessClient( packet )) then return end
					// Hosts .2-.11 belong to the MGMNT port; the rest of the
					// backbone /24 is on the fibre ports.
					if ((bb4.host >= 2) && (bb4.host <= 11)) then
						self:DeliverOnInterface( pid, packet, pass, self.NPorts, "lan" )
					else
						self:DeliverOnInterface( pid, packet, pass, self.OPorts, "wan" )
					end
					return
				end
				local nPort = self:RouteForBB( bb4.bb )
				if (nPort) then
					self:PushToRouted( pid, packet, pass, nPort, bb4.bb )
					return
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
		if (PCMod.Network && PCMod.Network.LogPacket) then
			PCMod.Network.LogPacket( "noroute", packet.Source, packet.Dest, packet.Port, packet.Body,
				"no route at " .. self.Entity:GetClass() .. ":" .. tostring( self.Entity:EntIndex() ) )
		end
		PCMod.Msg( "[webgr]IPv4 target " .. tostring( packet.Dest ) .. " is not routable; dropping", true )
		return
	end

	// IPv6: on-link LAN first.
	local lp = self:GetIPv6Prefix()
	if (lp && PCMod.IPv6.InSubnet( packet.Dest, lp )) then
		if (self:DeliverToWirelessClient( packet )) then return end
		self:DeliverOnInterface( pid, packet, pass, self.NPorts, "lan" )
		return
	end

	// Route by hierarchy.
	local hier = PCMod.IPv6.Hierarchy( packet.Dest )
	if (self.Entity:GetClass() == "pcmod_brouter") then
		// A LAN router advertises its /64 in the routing hello; route to the
		// advertised next hop instead of looking up connected devices.
		local prefix = PCMod.IPv6.GetPrefix( packet.Dest, 64 )
		local rec = prefix && PCMod.Routing.PrefixRoute( self, prefix )
		if (rec) then
			if (rec.mac) then packet.DestMAC = rec.mac end
			self.Entity:PushData( rec.port, { "deliver", pid, pass } )
			return
		end
		local mybb = self.Entity:GetBSubnet()
		if (hier && (hier.bb == mybb)) then
			// A backbone-attached host has no /64 of its own; deliver on the
			// interface that owns the host slot. Backbone hosts 2..11 are the
			// MGMNT segment, everything else is on the fibre ports.
			if ((hier.lan == 0) && (hier.iid >= 2) && (hier.iid <= 11)) then
				self:DeliverOnInterface( pid, packet, pass, self.NPorts, "lan" )
			else
				self:DeliverOnInterface( pid, packet, pass, self.OPorts, "wan" )
			end
			return
		elseif (hier) then
			local nPort = self:RouteForBB( hier.bb )
			if (nPort) then
				self:PushToRouted( pid, packet, pass, nPort, hier.bb )
				return
			end
		end
		PCMod.Msg( "[webgr]No IPv6 route for " .. tostring( packet.Dest ) .. "; dropping", true )
		return
	end

	// LAN router: everything not on my LAN goes upstream.
	if (self.Uplink) then
		// Remember LAN-initiated traffic so the matching reply is allowed back
		// through the IPv6 WAN -> LAN boundary above.
		if (side == "lan") then self:RememberV6Flow( packet ) end
		self.Entity:PushData( self.Uplink, { "deliver", pid, pass } )
		return
	end
	PCMod.Msg( "[webgr]No uplink for IPv6 target " .. tostring( packet.Dest ) .. "; dropping", true )
end

function SUBSYSTEM:CallEvent( data )
	if ((!data) || (!data.Event)) then return end
	PCMod.Msg( "[webgr]An event was called(" .. table.ToString(data) .. ")", true )
	local e = data.Event
	if (e == "linked") then
		local port = self.Entity:Ports()[ data[ 1 ] ]
		if (!port) then return end
		local cls = self.Entity:GetClass()
		local peerEnt = data[ 3 ] || port.ConEnt
		// Routers learn peers from hellos, not from link events relayed by
		// switches. A direct cable gets an immediate hello for fast start.
		PCMod.Routing.Send( self, true )
		if (PCMod.IsLanRouterClass( cls ) && table.HasValue( self.OPorts, data[ 1 ] )) then
			// A LAN router is a DHCP client on its WAN interface.
			self:SendDHCPDiscover( data[ 1 ] )
		end
		if (PCMod.IsLanRouterClass( cls ) && peerEnt && PCMod.IsRouterClass( peerEnt:GetClass() ) && table.HasValue( self.OPorts, data[ 1 ] )) then
			// Immediate default-route hint; DHCP also sets it on the ack.
			self.Uplink = port
		end
	end
	if (e == "unlinked") then
		local peerEnt = data[ 2 ]
		if (!peerEnt) then return end
		local cls = self.Entity:GetClass()
		local peer = peerEnt.GetClass && peerEnt:GetClass() or ""

		if ((cls == "pcmod_brouter") && PCMod.IsLanRouterClass( peer )) then
			local lanid = self.Children && self.Children[ peerEnt:EntIndex() ]
			if (lanid && self.ChildLan) then self.ChildLan[ lanid ] = nil end
			if (self.Children) then self.Children[ peerEnt:EntIndex() ] = nil end
			// The detached LAN becomes standalone again.
			peerEnt:SetUpBB( 0 )
			peerEnt:SetLanID( 0 )
			local cdata = PCMod.Data[ peerEnt:EntIndex() ]
			local child = cdata && cdata.Subsystems && cdata.Subsystems[ "router" ]
			if (child && child.ReconfigureClients) then child:ReconfigureClients() end
		elseif ((cls == "pcmod_brouter") && (peer == "pcmod_brouter")) then
			local pbb = peerEnt:GetBSubnet()
			if (self.Neighbors) then self.Neighbors[ pbb ] = nil end
			if (self.RouteAdv) then self.RouteAdv[ pbb ] = nil end
			self:RecalcRoutes()
			PCMod.Network.Reconverge()
		elseif ((cls == "pcmod_brouter") && (peerEnt.IsComputer == true)) then
			if (!self:ReleaseLeasesOnPort( data[ 1 ] )) then
				PCMod.DHCPServer.Release( self, peerEnt.GetMAC && peerEnt:GetMAC() )
			end
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
			if (!self:HasWirelessClient( peerEnt )) then
				if (!self:ReleaseLeasesOnPort( data[ 1 ] )) then
					PCMod.DHCPServer.Release( self, peerEnt.GetMAC && peerEnt:GetMAC() )
				end
			end
		end
	end
end


// ---------------------------------------------------------------------------------------------------------
// Router subsystem for PCMod 2 (This is for the router, not the pc)
// The router is split by domain; each part extends the same SUBSYSTEM table.
// ---------------------------------------------------------------------------------------------------------

include( "pcmod/subsystems/router/dhcp.lua" )
include( "pcmod/subsystems/router/routing.lua" )
include( "pcmod/subsystems/router/config.lua" )
include( "pcmod/subsystems/router/forwarding.lua" )
include( "pcmod/subsystems/router/web.lua" )

function SUBSYSTEM:OnRemove()
	if (PCMod.Routing && PCMod.Routing.Stop) then PCMod.Routing.Stop( self ) end
	self.LAN = {}
	self.BLAN = {}
	self.BSubnet = self.Entity:GetBSubnet()
	self.Subnet = self.Entity:GetSubnet()
	self.NPorts = {}
	self.OPorts = {}
	self.WirelessClients = {}
	self.V6Flows = {}
	self.Children = {}
	self.ChildLan = {}
	self.ArpCache = {}
	self.NdpCache = {}
	self.PrefixRoutes = {}
	self.Neighbors = {}
	self.NeighborMAC = {}
	self.RouteAdv = {}
	self.Uplink = nil
	self.ForwardFlows = {}
	self.NatOut = {}
	self.FwdByPeer = {}
	self.NatByPeer = {}
	self.NextEph = nil
end