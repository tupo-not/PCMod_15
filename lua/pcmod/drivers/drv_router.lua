
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

function DRV:PortSide( port )
	if (table.HasValue( self.NPorts, port )) then return "lan" end
	if (table.HasValue( self.OPorts, port )) then return "wan" end
	if (port == 0) then return "lan" end
	return nil
end

function DRV:InterfaceIP( side )
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
function DRV:InterfaceIPv6( side )
	if ((side == "wan") || self:IsBackbone()) then
		return (self.Entity.GetBIPv6 && self.Entity:GetBIPv6()) or false
	end
	return (self.Entity.GetIPv6 && self.Entity:GetIPv6()) or false
end

// Send a raw frame out one port. Wireless has no port index; deliver to the
// associated clients and let their DHCP/ARP state filter the frame.
function DRV:SendOnPort( port, data )
	if (port == 0) then
		for _, pc in pairs( self.WirelessClients or {} ) do
			if ((pc) && (pc.IsValid) && (pc:IsValid())) then
				local cd = PCMod.Data[ pc:EntIndex() ]
				local net = cd && cd.Drivers && cd.Drivers[ "gen_network" ]
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

function DRV:DataRecieved( port, data )
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

function DRV:DHCPServerReceive( port, app, macs )
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

function DRV:DHCPServerRequest( port, app, macs )
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

function DRV:DHCPServerRelease( app )
	local payload = app[5] or {}
	PCMod.DHCPServer.Release( self, payload.mac )
	return true
end

// Offer/ack meant for this router when it is itself a DHCP client on WAN.
function DRV:DHCPClientReceive( port, app )
	if (!self.DHCPState) then return false end
	return PCMod.DHCPClient.Handle( self, app )
end

// Ask upstream for this router's own WAN address. The same discover as any
// host; the answer carries the backbone id and the /64 id it may use.
function DRV:SendDHCPDiscover( port, retries )
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
function DRV:DeliverOnInterface( pid, packet, pass, ports, side )
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

function DRV:PushToRouted( pid, packet, pass, port, bb )
	if (!port) then return false end
	// Use the MAC of the immediate next-hop backbone, not the far destination.
	local route = self.Routes && self.Routes[ bb ]
	local via = route && route.via
	local mac = via && self.NeighborMAC && self.NeighborMAC[ via ]
	if (mac) then packet.DestMAC = mac end
	self.Entity:PushData( port, { "deliver", pid, pass } )
	return true
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
// IPv6 uses real prefix matching; IPv4 (and mapped IPv6) is classified by
// address space: backbone 100.x vs any RFC1918 LAN. The OnLink flags matter
// because an unknown on-link IPv6 host must be dropped, while a LAN address
// that belongs to a different router still has to be forwarded.
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

function DRV:CallEvent( data )
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
			local child = cdata && cdata.Drivers && cdata.Drivers[ "webgr_router" ]
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

// ---------------------------------------------------------------------------
// DHCP delegation. Leases live in the MAC-keyed engine; these methods keep the
// driver-facing names and apply the result to an entity.
// ---------------------------------------------------------------------------

function DRV:DHCPPool( scope )
	return PCMod.DHCPServer.Pool( self, scope )
end

// The scope this router hands leases out on: a backbone serves the backbone
// segment, a LAN router serves its own RFC1918 segment.
function DRV:LeaseScope()
	return self:IsBackbone() and "wan" or "lan"
end

function DRV:StaticLeases() return PCMod.DHCPServer.StaticList( self, self:LeaseScope() ) end
function DRV:StaticLeaseForMAC( mac ) return PCMod.DHCPServer.StaticForMAC( self, self:LeaseScope(), mac ) end
function DRV:DynamicLeases() return PCMod.DHCPServer.List( self, self:LeaseScope() ) end
function DRV:AddStaticLease( ip, mac ) return PCMod.DHCPServer.AddStatic( self, self:LeaseScope(), ip, mac ) end
function DRV:DeleteStaticLease( idx ) return PCMod.DHCPServer.DeleteStatic( self, self:LeaseScope(), idx ) end

// Release every LAN lease that arrived on this router port. Multi-NIC hosts
// hold one lease per interface, so a cable event must only drop the lease for
// the interface that was unplugged.
function DRV:ReleaseLeasesOnPort( port )
	if (port == nil) then return false end
	local c = PCMod.DHCPServer.Cfg( self )
	local drop = {}
	for mac, rec in pairs( c.Leases or {} ) do
		if (rec.port == port) then drop[ #drop + 1 ] = mac end
	end
	for _, mac in ipairs( drop ) do
		PCMod.DHCPServer.Release( self, mac )
	end
	return (#drop > 0)
end

// Find a live entity by its hardware address. The engine stores only MACs, so
// re-addressing after a LAN change looks the device up here.
function DRV:EntityForMAC( mac )
	mac = PCMod.Net.MACKey( mac )
	if (!mac) then return nil end
	for _, data in pairs( PCMod.Data or {} ) do
		local ent = data && data.Ent
		if ((ent) && (ent.IsValid) && (ent:IsValid()) && (ent.GetMAC)) then
			if (PCMod.Net.MACKey( ent:GetMAC() ) == mac) then return ent end
			local ifaces = ent.GetInterfaceMACs && ent:GetInterfaceMACs()
			for _, imac in pairs( ifaces or {} ) do
				if (PCMod.Net.MACKey( imac ) == mac) then return ent end
			end
		end
	end
	return nil
end

// Put an existing lease record onto the device that owns it.
function DRV:ApplyLease( scope, rec, ent )
	if ((!rec) || (!ent)) then return false end
	return PCMod.DHCPClient.ApplyHost( ent, PCMod.DHCPServer.Config( self, rec ) )
end

// Reserve and immediately apply a lease. The DORA path uses Offer/Ack; this
// synchronous form is for renumbering and the control panel.
function DRV:AssignDHCP( scope, pc, port )
	if ((!pc) || (!pc:IsValid())) then return nil end
	local mac = pc.GetMAC && pc:GetMAC()
	local rec = PCMod.DHCPServer.Lease( self, scope, mac, port )
	if (!rec) then return nil end
	self:ApplyLease( scope, rec, pc )
	return rec.host
end

function DRV:ReleaseDHCP( scope, pc )
	if ((!pc) || (!pc.IsValid) || (!pc:IsValid())) then return end
	local mac = pc.GetMAC && pc:GetMAC()
	local rec = mac && PCMod.DHCPServer.Find( self, scope, mac )
	if (!rec) then return end
	PCMod.DHCPServer.Release( self, mac )
	PCMod.DHCPClient.ReleaseHost( pc, scope, rec, self.Entity:EntIndex() )
	return rec.host
end

function DRV:RenewDHCP( scope, pc )
	if ((!pc) || (!pc:IsValid())) then return nil end
	local mac = pc.GetMAC && pc:GetMAC()
	local rec = mac && PCMod.DHCPServer.Find( self, scope, mac )
	if (!rec) then return self:AssignDHCP( scope, pc ) end
	rec.offered = false
	rec.expires = PCMod.Net.Now() + (PCMod.Net.LeaseTime or 3600)
	self:ApplyLease( scope, rec, pc )
	return rec.host
end

function DRV:HasDHCPLease( scope, pc )
	if (!pc) then return false end
	local mac = pc.GetMAC && pc:GetMAC()
	if (mac && PCMod.DHCPServer.Find( self, scope, mac )) then return true end
	local ifaces = pc.GetInterfaceMACs && pc:GetInterfaceMACs()
	for _, imac in pairs( ifaces or {} ) do
		if (PCMod.DHCPServer.Find( self, scope, imac )) then return true end
	end
	return false
end

function DRV:HasLeaseForMAC( scope, mac )
	if (!mac) then return false end
	return (PCMod.DHCPServer.Find( self, scope, mac ) != nil)
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
// Leases remember whether they arrived on a wired port, so no topology scan
// is needed; the direct-port check remains for legacy/no-DHCP clients.
function DRV:IsWiredClient( pc )
	if ((!pc) || (!pc:IsValid())) then return false end
	if (pc.GetMAC && PCMod.DHCPServer) then
		local rec = PCMod.DHCPServer.Find( self, "lan", pc:GetMAC() )
		// A synchronous lease carries no ingress port, so a false `wired` is
		// inconclusive; fall through to the physical port check.
		if (rec && (rec.wired == true)) then return true end
	end
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

// Register a PC that connected to this router over Wi-Fi. Association only
// handles authentication/range; the client gets its address from DHCP like
// any other host, so nothing is leased here.
function DRV:AddWirelessClient( pc )
	if ((!pc) || (!pc:IsValid())) then return false end
	if (!self.WirelessClients) then self.WirelessClients = {} end
	self.WirelessClients[ pc:EntIndex() ] = pc
	return true
end

// Release and immediately re-request a client's lease. The control panel's
// "Renew" button uses this to pick up the router's current pool/netmask
// without physically relinking the device. A client with no recorded lease is
// treated like a fresh link, so a stale lease table self-heals.
function DRV:RenewLease( pc )
	// A backbone router only hands out backbone hosts. Renewing there in the
	// LAN scope used to invent a LAN lease that the device could not even use.
	if (self:IsBackbone()) then
		return self:RenewDHCP( "wan", pc )
	end
	// A LAN router only renews devices that are actually on a LAN interface
	// (cabled to a LAN port or joined over Wi-Fi).
	if ((!self:IsWiredClient( pc )) && (!self:HasWirelessClient( pc ))) then return nil end
	return self:RenewDHCP( "lan", pc )
end

// Netmask prefix for this router's private LAN, anywhere in 16-32.
function DRV:GetLanNetmask()
	local m = tonumber( self:GetCfg().LanNetmask ) or 24
	return math.Clamp( math.floor( m ), 16, 32 )
end

// The third octet of the LAN network (0-255), derived from the full base.
function DRV:GetLanNet()
	return math.floor( self:GetLanBase() / 256 ) % 256
end

// The fourth octet of the LAN network, derived from the full base.
function DRV:GetLanLow()
	return self:GetLanBase() % 256
end

// Number of addresses in one subnet of the given mask.
function DRV:LanBlockSize( mask )
	mask = math.Clamp( math.floor( tonumber( mask ) or self:GetLanNetmask() ), 16, 32 )
	return 2 ^ (32 - mask)
end

// Align a full 32-bit LAN base to the subnet size. Masks stay in 16-32, so a
// LAN subnet always sits inside one RFC1918 block and its host space fits the
// 16-bit IID used by the emulated IPv6 layer.
function DRV:ComputeLanBase( mask, base )
	mask = math.Clamp( math.floor( tonumber( mask ) or self:GetLanNetmask() ), 16, 32 )
	base = math.floor( tonumber( base ) or tonumber( self:GetCfg().LanBase ) or 0 )
	local size = self:LanBlockSize( mask )
	return math.floor( base / size ) * size
end

function DRV:GetLanBase( mask )
	return self:ComputeLanBase( mask or self:GetLanNetmask(), self:GetCfg().LanBase )
end

// Human-readable LAN prefix, e.g. "192.168.5.0/24" or "10.20.0.0/16".
function DRV:GetLanPrefix( mask, base )
	local m = math.Clamp( math.floor( tonumber( mask ) or self:GetLanNetmask() ), 16, 32 )
	base = self:ComputeLanBase( m, base or self:GetCfg().LanBase )
	return PCMod.IPv4.FromInt( base ) .. "/" .. tostring( m )
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

// Move this router's own LAN gateway onto the configured network. A backbone
// has no LAN; its MGMNT segment shares the backbone /24 and uses the backbone
// address itself as the gateway.
function DRV:ApplyLanAddress()
	if (self:IsBackbone()) then return end
	local addr = self:GetLanBase() + 1
	if (self.Entity.SetLanAddress) then
		self.Entity:SetLanAddress( PCMod.IPv4.FromInt( addr ) )
	else
		self.Entity:SetSubnet( math.floor( addr / 256 ) )
		self.Entity:SetIP( addr % 256 )
	end
end

// Re-issue every LAN lease after the addressing changed. Addresses derive from
// the host id, so the engine recomputes them and each live owner is re-applied.
function DRV:RenumberLeases()
	local dropped = PCMod.DHCPServer.Reflow( self, "lan" )
	PCMod.DHCPServer.Readdress( self, "lan" )
	for mac, rec in pairs( PCMod.DHCPServer.Cfg( self ).Leases ) do
		if (rec.scope == "lan") then
			local ent = self:EntityForMAC( mac )
			if (ent) then self:ApplyLease( "lan", rec, ent ) end
		end
	end
	for _, d in ipairs( dropped ) do
		local ent = self:EntityForMAC( d.mac )
		if (ent) then PCMod.DHCPClient.ReleaseHost( ent, "lan", d.rec, self.Entity:EntIndex() ) end
	end
end

// Change the LAN subnet size (16-32). Existing leases are renumbered onto the
// new block and the pool is clamped to it.
function DRV:SetLanNetmask( mask )
	mask = math.Clamp( math.floor( tonumber( mask ) or 24 ), 16, 32 )
	local c = self:GetCfg()
	if (mask == self:GetLanNetmask()) then return end
	c.LanNetmask = mask
	// Re-align the base to the new subnet size, staying inside RFC1918.
	local aligned = self:ComputeLanBase( mask, c.LanBase )
	if (PCMod.IPv4.IsPrivate( aligned )) then c.LanBase = aligned end
	c.LanNet = math.floor( c.LanBase / 256 ) % 256
	c.LanLow = c.LanBase % 256
	self:ClampDHCPPool()
	self:RenumberLeases()
	self:ApplyLanAddress()
end

// Change the third octet of the LAN network (0-255), keeping the first two
// octets. Kept for the legacy web field; `lanaddr` sets the full base.
function DRV:SetLanNet( net )
	local n = math.Clamp( math.floor( tonumber( net ) or 0 ), 0, 255 )
	local base = self:GetLanBase()
	local newBase = (base - (base % 65536)) + (n * 256)
	return self:SetLanBase( newBase )
end

// Move the LAN network anywhere inside RFC1918. The base is aligned to the
// subnet size and stored as a full 32-bit value; LanNet/LanLow stay in sync for
// older saves and displays.
function DRV:SetLanBase( base )
	local c = self:GetCfg()
	local oldBase = self:GetLanBase()
	local aligned = PCMod.IPv4.ClampPrivate( base, self:GetLanNetmask() )
	if (!aligned) then return false end
	c.LanBase = aligned
	c.LanNet = math.floor( aligned / 256 ) % 256
	c.LanLow = aligned % 256
	if (aligned != oldBase) then
		self:RenumberLeases()
		self:ApplyLanAddress()
	end
	return true
end

// ---------------------------------------------------------------------------
// Shared DHCP lease table. LAN clients and backbone-side hosts use the same
// allocator; only the pool bounds and the address applier differ.
// ---------------------------------------------------------------------------

// LAN-scope aliases. The engine itself is scope-aware; these names exist
// because most callers only ever deal with their own LAN.
function DRV:AssignLease( pc )
	return self:AssignDHCP( "lan", pc )
end

function DRV:ReleaseLease( pc )
	return self:ReleaseDHCP( "lan", pc )
end

// A new /64 id within this backbone's /32 (one per attached LAN router).
function DRV:NextLanID()
	self.NextLan = (self.NextLan or 0) + 1
	return self.NextLan
end

function DRV:IsBackbone()
	return ((self.Entity != nil) && (self.Entity.GetClass != nil) && (self.Entity:GetClass() == "pcmod_brouter"))
end

// Backbone web guard. The control plane is management-only: only hosts 1-11
// of this backbone's /24 (the router itself and the MGMNT pool) may open the
// panel. The fibre DHCP pool (12-254), LAN identities and IPv6-derived LAN
// sources are all denied by default. Normal forwarding is unaffected (the
// backbone firewall stays in its default-allow state) and the router's own
// generated replies never pass through this check.
function DRV:BackboneWebAllowed( source )
	if (!self:IsBackbone()) then return true end
	if (self:GetCfg().WebGuard == false) then return true end
	local ip = source
	if (PCMod.IPv6.IsLoopback( ip )) then return true end
	if (PCMod.IPv6.IsIPv6( ip )) then ip = PCMod.IPv6.ToIPv4( ip ) end
	local p = ip && PCMod.IPv4.Parse( ip )
	if (!p) then return false end
	if (p.bb != self.Entity:GetBSubnet()) then return false end
	return ((p.host >= 1) && (p.host <= 11))
end

// Re-push this router's own /32 + /64 onto every client lease (a LAN router
// renumbers its LAN when its upstream changes).
function DRV:ReconfigureClients()
	local ip = self.Entity:Data().IP
	local upbb = ip.UpBB or 0
	local lanid = ip.LanID or 0
	for mac, rec in pairs( PCMod.DHCPServer.Cfg( self ).Leases ) do
		if (rec.scope == "lan") then
			local pc = self:EntityForMAC( mac )
			if (pc) then self:PushClientConfig( pc, upbb, lanid ) end
		end
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
	local mybb = self.Entity:GetBSubnet()
	local routes = {}
	if (mybb) then routes[ mybb ] = { dist = 0, via = nil } end
	// Direct neighbours are one hop away.
	for bb in pairs( self.Neighbors or {} ) do
		if (bb != mybb) then routes[ bb ] = { dist = 1, via = bb } end
	end
	// Relax the distance vectors advertised by those neighbours. Running a few
	// passes lets a change propagate across a chain of backbones immediately,
	// instead of waiting one hello interval per hop.
	local adv = self.RouteAdv or {}
	for _ = 1, 32 do
		local changed = false
		for fromBB, dv in pairs( adv ) do
			if ((self.Neighbors && self.Neighbors[ fromBB ]) && istable( dv )) then
				for dest, dist in pairs( dv ) do
					if ((dest != mybb) && (dest != fromBB)) then
						local nd = (tonumber( dist ) or 0) + 1
						local cur = routes[ dest ]
						if ((!cur) || (cur.dist > nd)) then
							routes[ dest ] = { dist = nd, via = fromBB }
							changed = true
						end
					end
				end
			end
		end
		if (!changed) then break end
	end
	self.Routes = routes
end

// Distance vector for a hello. `excludeBB` implements split horizon: routes
// learned through that neighbour are not advertised back to it, which prevents
// two backbones from reviving a dead path by pointing at each other.
function DRV:GetDV( excludeBB )
	local dv = {}
	for bb, r in pairs( self.Routes or {} ) do
		if ((!excludeBB) || (r.via != excludeBB)) then dv[ bb ] = r.dist end
	end
	return dv
end

function DRV:NeighborDrv( port )
	local p = port
	if (type( p ) == "number") then
		local ports = self.Entity.Ports && self.Entity:Ports()
		p = ports && ports[ p ]
	end
	local ent = p && p.ConEnt
	if ((!ent) || (!ent:IsValid())) then return nil end
	local data = PCMod.Data[ ent:EntIndex() ]
	return data && data.Drivers && data.Drivers[ "webgr_router" ]
end

// Push this router's distance vector to every neighbouring backbone, with
// split horizon so a route is never sent back the way it was learned.
function DRV:AdvertiseRoutes()
	if (!self:IsBackbone()) then return end
	for bb, port in pairs( self.Neighbors or {} ) do
		local drv = self:NeighborDrv( port )
		if (drv && drv.RecvRoutes) then drv:RecvRoutes( self.Entity:GetBSubnet(), self:GetDV( bb ) ) end
	end
end

// Merge a neighbour's distance vector and recompute the table. Keeping the
// last advertisement per neighbour lets RecalcRoutes relax multi-hop paths.
function DRV:RecvRoutes( fromBB, dv )
	if (!self:IsBackbone()) then return end
	if (!fromBB) then return end
	self.RouteAdv = self.RouteAdv or {}
	self.RouteAdv[ fromBB ] = dv
	local old = self.Routes
	self:RecalcRoutes()
	// A changed table is pushed onward immediately, so a chain converges in one
	// tick instead of one hello interval per hop. Split horizon terminates it.
	if (self:RoutesDiffer( old, self.Routes ) && self.AdvertiseRoutes) then
		self:AdvertiseRoutes()
	end
end

// True when two distance-vector tables disagree about any destination.
function DRV:RoutesDiffer( a, b )
	if ((!a) || (!b)) then return true end
	for bb, r in pairs( a ) do
		local o = b[ bb ]
		if ((!o) || ((o.dist or 0) != (r.dist or 0))) then return true end
	end
	for bb in pairs( b ) do
		if (!a[ bb ]) then return true end
	end
	return false
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
	// The Wi-Fi interface has its own MAC (and lease). Releasing it must not
	// disturb a cable lease the same machine still holds. Old single-MAC
	// devices keep the shared-lease behaviour.
	local wmac
	if ((!pc.IsNetworkDevice) && pc.GetInterfaceMAC) then wmac = pc:GetInterfaceMAC( 0 ) end
	local pmac = pc.GetMAC && pc:GetMAC()
	wmac = wmac or pmac
	if ((wmac == pmac) && self:IsWiredClient( pc )) then return end
	local rec = wmac && PCMod.DHCPServer.Find( self, "lan", wmac )
	if (!rec) then return end
	local ipdata = pc.Data && pc:Data() && pc:Data().IP
	if (ipdata) then
		if ((ipdata.Router == self.Entity:EntIndex()) && (ipdata.LAN == rec.ip)) then
			if (pc.SetSubnet) then pc:SetSubnet( false ) end
			if (pc.SetIP) then pc:SetIP( false ) end
			ipdata.Router = false
		elseif (pc.ReleaseExtraIP) then
			pc:ReleaseExtraIP( rec.ip )
		end
	end
	PCMod.DHCPServer.Release( self, wmac )
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
			if (drv) then
				local function deliver()
					if ((pc.IsValid) && (pc:IsValid())) then drv:PacketRecieved( packet ) end
				end
				if (PCMod.Latency && PCMod.Latency.Deliver) then
					local dist = PCMod.Latency.DistanceBetween && PCMod.Latency.DistanceBetween( self.Entity, pc )
					local range = (PCMod.Cfg && PCMod.Cfg.WirelessRange) or 0
					PCMod.Latency.Deliver( deliver, "wireless", dist, range )
				else
					deliver()
				end
			end
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
	if (c.WireName == nil) then
		// Stable default SSID. Users can rename the network from the Wi-Fi page.
		local idx = (self.Entity.EntIndex && self.Entity:EntIndex()) or 0
		c.WireName = d.WireName or ("WebGear-" .. tostring( idx ))
	end
	if (c.DHCPStart == nil) then c.DHCPStart = tonumber( PCMod.Cfg.DHCPStart ) or 2 end
	if (c.DHCPEnd == nil) then c.DHCPEnd = tonumber( PCMod.Cfg.DHCPEnd ) or 254 end
	// MGMNT segment on a backbone: hosts .2-.11 of the backbone's own /24.
	if (c.MgmtDHCPStart == nil) then c.MgmtDHCPStart = 2 end
	if (c.MgmtDHCPEnd == nil) then c.MgmtDHCPEnd = 11 end
	if (c.MgmtStaticLeases == nil) then c.MgmtStaticLeases = {} end
	// Default backbone rule: the web panel is management-only; the fibre DHCP
	// pool (hosts 12-254) cannot reach it. Set to false to open it up.
	if (c.WebGuard == nil) then c.WebGuard = true end
	// Backbone-side pool (hosts 12..254; .2-.11 belong to the MGMNT port).
	if (c.WanDHCPStart == nil) then c.WanDHCPStart = 12 end
	if (c.WanDHCPEnd == nil) then c.WanDHCPEnd = 254 end
	// Static backbone reservations, each { ip = "<octet>.x.x.y", mac = "AA:..." }.
	if (c.StaticLeases == nil) then c.StaticLeases = {} end
	// Per-router LAN size (16-32) and full 32-bit base. Older saves stored only
	// the 192.168 third/fourth octets (LanNet/LanLow); migrate them into
	// LanBase once, then keep both forms in sync for displays and old tools.
	if (c.LanNetmask == nil) then c.LanNetmask = tonumber( PCMod.Cfg.LanNetmask ) or 24 end
	c.LanNetmask = math.Clamp( math.floor( tonumber( c.LanNetmask ) or 24 ), 16, 32 )
	if (c.LanBase == nil) then
		local net = math.Clamp( math.floor( tonumber( c.LanNet ) or 0 ), 0, 255 )
		local low = math.Clamp( math.floor( tonumber( c.LanLow ) or 0 ), 0, 255 )
		c.LanBase = (192 * 16777216) + (168 * 65536) + (net * 256) + low
	end
	c.LanBase = math.max( 0, math.floor( tonumber( c.LanBase ) or 0 ) )
	if (c.LanNet == nil) then c.LanNet = math.floor( c.LanBase / 256 ) % 256 end
	if (c.LanLow == nil) then c.LanLow = c.LanBase % 256 end
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
	self:SyncWirelessOverlay()
end

// Publish the look-at overlay state. The overlay is client-side, so the SSID
// travels as a network string: non-empty means Wi-Fi is on. This is what makes
// the overlay follow the web panel instead of the spawn-time checkbox.
function DRV:SyncWirelessOverlay()
	local ent = self.Entity
	if ((!ent) || (!ent.SetNWString)) then return end
	local c = self:GetCfg()
	self.Wireless = (c.Wireless == true)
	local ssid = ""
	if (self.Wireless) then ssid = tostring( c.WireName or "" ) end
	ent:SetNWString( "WifiSSID", ssid )
	if (ent.SetGVar) then ent:SetGVar( "wireless", self.Wireless ) end
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

// IPv6 has no NAT, so the LAN edge needs its own stateful boundary. A packet
// arriving from the WAN may only reach an address inside this router's LAN
// /64 when it belongs to a flow the LAN started, or when an inbound firewall
// rule explicitly opens it. This mirrors IPv4's "LAN is private" behaviour and
// keeps freshly spawned routers closed by default.
function DRV:IsLanIPv6( addr )
	local lp = self:GetIPv6Prefix()
	if (!lp) then return false end
	return PCMod.IPv6.InSubnet( addr, lp )
end

// Is addr one of this router's private LAN identities (its gateway IPv4/IPv6)?
// On the WAN side these must not be treated as local addresses; otherwise a
// shared L2 segment could reach the LAN admin interface by its private IP.
function DRV:IsLanSelfAddress( addr )
	local v4 = self.Entity.GetLanIPv4 && self.Entity:GetLanIPv4()
	local v6 = self.Entity.GetIPv6 && self.Entity:GetIPv6()
	return PCMod.IPv6.Matches( addr, v4, v6 )
end

function DRV:RememberV6Flow( packet )
	if ((!packet) || (!packet.Source) || (!packet.Dest)) then return end
	self.V6Flows = self.V6Flows or {}
	local key = tostring( packet.Source ) .. "|" .. tostring( packet.Dest ) .. "|" .. tostring( packet.Port or 0 )
	self.V6Flows[ key ] = {
		localAddr = packet.Source,
		remote = packet.Dest,
		port = packet.Port or 0,
		time = CurTime(),
	}
end

// Is this WAN packet a reply to a flow the LAN started? Traceroute hop reports
// come from routers along the path rather than the final destination, so a
// port-0 trace flow also accepts netTraceHop replies.
function DRV:V6ReplyAllowed( packet )
	self.V6Flows = self.V6Flows or {}
	local now = CurTime()
	local port = packet.Port or 0
	for key, flow in pairs( self.V6Flows ) do
		if ((now - (flow.time or now)) > 3600) then
			self.V6Flows[ key ] = nil
		elseif ((flow.localAddr == packet.Dest) && (flow.port == port)) then
			if (flow.remote == packet.Source) then
				// Keep an active conversation alive while it is in use.
				flow.time = now
				return true
			end
			if ((port == 0) && (packet.Body) && (packet.Body[1] == "netTraceHop")) then return true end
		end
	end
	return false
end

// Explicit inbound allow rule. IPv6 has no port-forward/NAT fallback, so these
// rules are honoured for LAN ingress even when the general firewall is off.
function DRV:V6RuleAllowed( packet )
	local c = self:GetCfg()
	for _, r in ipairs( c.FirewallRules or {} ) do
		if ((r.dir == "in") || (r.dir == "any")) then
			local m = true
			if ((r.src != "") && (r.src != packet.Source)) then m = false end
			if ((r.dst != "") && (r.dst != packet.Dest)) then m = false end
			if ((r.port != 0) && (r.port != (packet.Port or 0))) then m = false end
			if (m) then return true end
		end
	end
	return false
end

function DRV:WanToLanAllowed( packet )
	return self:V6ReplyAllowed( packet ) || self:V6RuleAllowed( packet )
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
	// Apply single-key settings in a fixed order: the network and mask first,
	// then the pool that is clamped against it. pairs() order is not
	// deterministic, which would make multi-key queries flaky.
	local order = { "wireless", "netmask", "lanaddr", "lannet", "dhcpstart", "dhcpend", "firewall", "nat", "wname", "wpass" }
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
// address ("10.5.4.1"). A dotted bound also selects the network: deriveBase
// true snaps the address to its subnet, false just measures it from the
// current base.
function DRV:ParsePoolBound( value, deriveBase )
	local v = tostring( value or "" )
	local abs = PCMod.IPv4.ToInt( v )
	if (!abs) then return tonumber( v ), nil end
	local base = self:GetLanBase()
	if (!deriveBase) then
		return abs - base, nil
	end
	local size = self:LanBlockSize()
	local aligned = math.floor( abs / size ) * size
	return abs - aligned, aligned
end

function DRV:ApplyWebSetting( key, value, deriveBase )
	local c = self:GetCfg()
	if (key == "wireless") then
		self:SetWireless( (value == "1") || (value == "on") )
	elseif (key == "wname") then
		local name = string.Trim( tostring( value or "" ) )
		if (name == "") then
			c.WireName = nil
			self:GetCfg()
		else
			c.WireName = name
		end
		self:SyncWirelessOverlay()
	elseif (key == "wpass") then
		if (value == "random") then
			c.WirePass = tostring( math.random( 100000, 999999 ) )
		else
			c.WirePass = tostring( value or "" )
		end
	elseif (key == "netmask") then
		self:SetLanNetmask( value )
	elseif (key == "lanaddr") then
		// Full network address, any RFC1918 block ("10.5.0.0", "172.20.1.0",
		// "192.168.4.0"). The subnet size comes from the netmask field.
		local v = PCMod.IPv4.ToInt( string.Trim( tostring( value or "" ) ) )
		if (v) then self:SetLanBase( v ) end
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

// Shared navigation bar linking the pages. A backbone has no LAN, Wi-Fi or
// firewall/port-forwarding: it only exposes its management segment and leases.
function DRV:WebNav( current )
	local items
	if (self:IsBackbone()) then
		items = { { "", "Home" }, { "lan", "Management" }, { "static", "DHCP Leases" } }
	else
		items = { { "", "Home" }, { "wifi", "Wi-Fi" }, { "lan", "LAN" }, { "firewall", "Firewall" }, { "static", "DHCP Leases" } }
	end
	local parts = {}
	for _, it in ipairs( items ) do
		table.insert( parts, '<a href="/' .. it[ 1 ] .. '">' .. it[ 2 ] .. '</a>' )
	end
	return "<p>Navigation: " .. table.concat( parts, " | " ) .. "</p>"
end

// First and last address of a DHCP pool in dotted-quad form. The scope picks
// the network (LAN RFC1918 or the configured backbone /8).
function DRV:DHCPPoolRange( scope )
	local start, finish = PCMod.DHCPServer.Pool( self, scope )
	if (!start) then return nil end
	return PCMod.DHCPServer.Address( self, scope, start ), PCMod.DHCPServer.Address( self, scope, finish )
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
		table.insert( lines, "<p><b>IPv4 WAN / MGMNT:</b> " .. tostring( e:GetFullBIP() or "unassigned" ) .. " in " .. tostring( PCMod.IPv4.BackbonePrefix( bb ) ) .. "</p>" )
	else
		table.insert( lines, "<p><b>IPv4 LAN:</b> " .. tostring( e:GetFullIP() or "unassigned" ) .. " on " .. self:GetLanPrefix() .. "</p>" )
		local wan = (e.GetFullBIP && e:GetFullBIP())
		if (wan) then table.insert( lines, "<p><b>IPv4 WAN /32 (NAT):</b> " .. tostring( wan ) .. " in " .. tostring( PCMod.IPv4.BackbonePrefix( bb ) ) .. "</p>" ) end
	end
	table.insert( lines, "<p><b>IPv6:</b> " .. tostring( e:GetIPv6() or "unassigned" ) .. "</p>" )
	if (e.GetIPv6Prefix && e:GetIPv6Prefix()) then table.insert( lines, "<p><b>Prefix:</b> " .. tostring( e:GetIPv6Prefix() ) .. "</p>" ) end
	if (bb) then table.insert( lines, "<p><b>Backbone:</b> " .. tostring( PCMod.IPv6.BackbonePrefix( bb ) ) .. "</p>" ) else table.insert( lines, "<p><b>Backbone:</b> none (standalone)</p>" ) end
	if (self:IsBackbone()) then
		// A backbone only has the backbone pool and its management pool. It has
		// no Wi-Fi, firewall or NAT to report.
		local wfirst, wlast = self:DHCPPoolRange( "wan" )
		local ws, wf = self:DHCPPool( "wan" )
		if (wfirst) then
			table.insert( lines, "<p><b>Backbone DHCP pool:</b> " .. wfirst .. " - " .. wlast .. " (" .. tostring( wf - ws + 1 ) .. " hosts)</p>" )
		end
		local mfirst, mlast = self:DHCPPoolRange( "mgmt" )
		local ms, mf = self:DHCPPool( "mgmt" )
		if (mfirst) then
			table.insert( lines, "<p><b>MGMNT DHCP pool:</b> " .. mfirst .. " - " .. mlast .. " (" .. tostring( mf - ms + 1 ) .. " hosts)</p>" )
		end
		table.insert( lines, '<p><b>DHCP leases:</b> ' .. tostring( #self:DynamicLeases() ) .. ' backbone, ' .. tostring( #PCMod.DHCPServer.List( self, "mgmt" ) ) .. ' management <a href="/static">[Manage]</a></p>' )
	else
		table.insert( lines, "<p><b>Wi-Fi:</b> " .. (c.Wireless and "enabled" or "disabled") .. "</p>" )
		table.insert( lines, "<p><b>Firewall:</b> " .. (c.Firewall and "on" or "off") .. "</p>" )
		table.insert( lines, "<p><b>NAT:</b> " .. (c.NAT and "on" or "off") .. "</p>" )
		local first, last = self:DHCPPoolRange( "lan" )
		local startHost, finishHost = self:DHCPPool( "lan" )
		if (first) then
			table.insert( lines, "<p><b>DHCP pool:</b> " .. first .. " - " .. last .. " (" .. tostring( finishHost - startHost + 1 ) .. " hosts)</p>" )
		end
		table.insert( lines, '<p><b>DHCP leases:</b> ' .. tostring( #self:DynamicLeases() ) .. ' active, ' .. tostring( #self:StaticLeases() ) .. ' static <a href="/static">[Manage]</a></p>' )
		local wc = 0
		for _, v in pairs( self.WirelessClients or {} ) do if (v) then wc = wc + 1 end end
		table.insert( lines, "<p><b>Wi-Fi clients:</b> " .. tostring( wc ) .. "</p>" )
	end

	table.insert( lines, "<hr>" )
	table.insert( lines, "<h2>Network</h2>" )
	local links = {}
	if (self:IsBackbone()) then
		for lanid, port in pairs( self.ChildLan or {} ) do
			local child = port && port.ConEnt
			local name = "LAN router #" .. tostring( (child && child:IsValid() && child:EntIndex()) or "?" )
			table.insert( links, '<li><a href="fd00:' .. tostring( bb ) .. ':0:' .. tostring( lanid ) .. '::1">' .. name .. '</a></li>' )
		end
		// Child /64s learned from routing hellos.
		for prefix, rec in pairs( self.PrefixRoutes or {} ) do
			if (rec && rec.port) then
				table.insert( links, '<li>' .. tostring( prefix ) .. ' via port ' .. tostring( rec.port ) .. '</li>' )
			end
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
	table.insert( lines, '<p><b>Name:</b> <input type="text" name="wname" value="' .. tostring( c.WireName ) .. '"> <input type="submit" value="Set Name"></p>' )
	table.insert( lines, '<p><b>Password:</b> <input type="text" name="wpass" value="' .. tostring( c.WirePass ) .. '"> <input type="submit" value="Set Password"></p>' )
	return table.concat( lines, "\n" )
end

// Backbone management page. The MGMNT port is a separate physical segment but
// shares the backbone's own /24, so the web panel is reached at the router's
// backbone address (.1) and DHCP hands out .2-.11 on that port.
function DRV:PageManagement()
	local bb = self.Entity:GetBSubnet()
	local lines = {}
	table.insert( lines, "<h1>Management</h1>" )
	table.insert( lines, self:WebNav( "lan" ) )
	table.insert( lines, "<p>The MGMNT port is an isolated management segment on the backbone's own /24. This router is host .1 and hands out .2 through .11 over DHCP.</p>" )
	table.insert( lines, "<hr>" )
	table.insert( lines, "<h2>Addressing</h2>" )
	table.insert( lines, "<p><b>Network:</b> " .. tostring( PCMod.IPv4.BackbonePrefix( bb ) ) .. "</p>" )
	table.insert( lines, "<p><b>MGMNT address:</b> " .. tostring( self.Entity:GetFullBIP() or "unassigned" ) .. "</p>" )
	table.insert( lines, "<hr>" )
	table.insert( lines, "<h2>DHCP pool</h2>" )
	local first, last = self:DHCPPoolRange( "mgmt" )
	local s, f = self:DHCPPool( "mgmt" )
	if (first) then
		table.insert( lines, "<p><b>Range:</b> " .. first .. " - " .. last .. " (" .. tostring( f - s + 1 ) .. " hosts)</p>" )
	end
	table.insert( lines, "<p><b>Note:</b> hosts .2-.11 are reserved for the MGMNT port; .12-.254 are handed out on the fibre ports.</p>" )
	table.insert( lines, "<p><b>Web access:</b> management only (MGMNT .2-.11). Backbone pool hosts (.12-.254) are blocked from this panel by default.</p>" )
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
	table.insert( lines, '<p><b>LAN address:</b> <input type="text" name="lanaddr" value="' .. PCMod.IPv4.FromInt( self:GetLanBase() ) .. '"> (RFC1918: 10.x, 172.16-31.x or 192.168.x)</p>' )
	table.insert( lines, '<p><b>Netmask size:</b> <input type="text" name="netmask" value="' .. tostring( self:GetLanNetmask() ) .. '"> (16-32)</p>' )
	table.insert( lines, '<p><b>Quick:</b> <a href="?netmask=16">[/16]</a> <a href="?netmask=24">[/24]</a> <a href="?netmask=30">[/30]</a></p>' )
	table.insert( lines, "<hr>" )
	table.insert( lines, "<h2>DHCP pool</h2>" )
	local first, last = self:PoolRange()
	// Bounds are shown as full addresses; typing a different RFC1918 network
	// here also moves the LAN's subnet.
	table.insert( lines, '<p><b>First address:</b> <input type="text" name="dhcpstart" value="' .. first .. '"></p>' )
	table.insert( lines, '<p><b>Last address:</b> <input type="text" name="dhcpend" value="' .. last .. '"></p>' )
	local startHost, finishHost = self:DHCPPool( "lan" )
	local hosts = 0
	if (startHost) then hosts = math.max( 0, finishHost - startHost + 1 ) end
	table.insert( lines, "<p><b>Range:</b> " .. first .. " - " .. last .. " (" .. tostring( hosts ) .. " hosts)</p>" )
	table.insert( lines, "<p><b>Note:</b> host ids run 2-" .. tostring( self:PoolMax() ) .. " (.1 is the router). Type a full RFC1918 address to choose the network.</p>" )
	if (c.NAT) then
		table.insert( lines, '<p><b>NAT:</b> on <a href="?nat=0">[Disable]</a></p>' )
	else
		table.insert( lines, '<p><b>NAT:</b> off <a href="?nat=1">[Enable]</a></p>' )
	end
	table.insert( lines, '<p><input type="submit" value="Apply"></p>' )
	return table.concat( lines, "\n" )
end

// DHCP page: active (dynamic) leases plus static IP <-> MAC reservations.
// The scope follows the router role, so LAN and backbone pages look the same.
function DRV:PageStaticLeases()
	local scope = self:LeaseScope()
	local isWan = (scope == "wan")
	local bb = self.Entity:GetBSubnet()
	local lines = {}
	table.insert( lines, "<h1>" .. (isWan and "Backbone" or "LAN") .. " DHCP leases</h1>" )
	table.insert( lines, self:WebNav( "static" ) )
	table.insert( lines, "<hr>" )

	local dyn = self:DynamicLeases()
	table.insert( lines, "<h2>Active leases</h2>" )
	if (#dyn == 0) then
		table.insert( lines, "<p>No active leases.</p>" )
	else
		for _, rec in ipairs( dyn ) do
			local expires = tonumber( rec.expires ) or 0
			local left = math.max( 0, math.floor( (expires - PCMod.Net.Now()) / 60 ) )
			table.insert( lines, '<p>' .. tostring( rec.ip ) .. ' -> ' .. tostring( rec.mac )
				.. ' <i>' .. tostring( rec.static and "static" or "dynamic" ) .. '</i>'
				.. ' (' .. tostring( left ) .. ' min)</p>' )
		end
	end

	if (isWan) then
		local mgmt = PCMod.DHCPServer.List( self, "mgmt" )
		if (#mgmt > 0) then
			table.insert( lines, "<h2>Management leases (MGMNT)</h2>" )
			for _, rec in ipairs( mgmt ) do
				local expires = tonumber( rec.expires ) or 0
				local left = math.max( 0, math.floor( (expires - PCMod.Net.Now()) / 60 ) )
				table.insert( lines, '<p>' .. tostring( rec.ip ) .. ' -> ' .. tostring( rec.mac )
					.. ' <i>' .. tostring( rec.static and "static" or "dynamic" ) .. '</i>'
					.. ' (' .. tostring( left ) .. ' min)</p>' )
			end
		end
	end

	table.insert( lines, "<hr>" )
	table.insert( lines, "<p>Reserve an IPv4 for a MAC address. The reservation is handed out when that device asks for a lease.</p>" )
	if (isWan) then
		table.insert( lines, "<p><b>Backbone:</b> " .. tostring( PCMod.IPv4.BackbonePrefix( bb ) ) .. " (hosts 12-254)</p>" )
	else
		table.insert( lines, "<p><b>LAN:</b> " .. self:GetLanPrefix() .. " (hosts 2-" .. tostring( self:PoolMax() ) .. ")</p>" )
	end

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
	// A backbone has no Wi-Fi or firewall/port-forwarding UI; those paths fall
	// back to the home page instead of exposing controls that do nothing.
	if (self:IsBackbone() && ((page == "wifi") || (page == "firewall"))) then
		return self:PageHome()
	end
	if (page == "wifi") then return self:PageWifi() end
	if (page == "lan") then
		if (self:IsBackbone()) then return self:PageManagement() end
		return self:PageLAN()
	end
	if (page == "firewall") then return self:PageFirewall() end
	if (page == "static") then return self:PageStaticLeases() end
	return self:PageHome()
end

// Reply to an in-game HTTP request: apply any ?query settings, then serve.
function DRV:HandleWebRequest( packet )
	local path = (packet.Body && packet.Body[2]) or ""
	self:ApplyWebQuery( path )
	local page = self:GetWebPage( path )
	// Reply from the exact interface address the client contacted, so a
	// request over the backbone answers from the WAN /32 and one over the
	// MGMNT port answers from the management address.
	local src = packet.Dest
	if ((!src) || (!self.Entity.IsAddressedTo) || (!self.Entity:IsAddressedTo( src ))) then
		src = self.Entity:GetSourceAddress( packet.Source ) or self.Entity:GetFullIP() or self.Entity:GetFullBIP()
	end
	if (!src) then return false end
	packet.Delivered = true
	local pid = PCMod.Network.CreatePacket( src, packet.Source, 80, { "http-response", page }, nil, self.Entity:GetMAC(), packet.SourceMAC )
	if (pid) then self:ProcessPacket( pid ) end
	return true
end

function DRV:OnRemove()
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