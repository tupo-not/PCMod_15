
// Network subsystem for PCMod 2

SUBSYSTEM = PCMod.DeriveSubsystem( "base" )

SUBSYSTEM.NiceName = "Generic Network"
SUBSYSTEM.Name = "network"
SUBSYSTEM.Type = "network"

SUBSYSTEM.PTData = {}
SUBSYSTEM.NetworkPort = 0
SUBSYSTEM.WirelessEnt = nil
SUBSYSTEM.WirelessPass = ""
SUBSYSTEM.WirelessIPv4 = nil

function SUBSYSTEM:Initialize()
	if (!self.Entity) then return end
	// A machine may have more than one Ethernet port (the tower has two).
	// Keep them all: each can carry its own DHCP lease and segment.
	self.NetworkPorts = {}
	for k, v in pairs( self.Entity:Ports() ) do
		if (v.Type == "network") then table.insert( self.NetworkPorts, k ) end
	end
	table.sort( self.NetworkPorts )
	self.NetworkPort = self.NetworkPorts[ 1 ] or 0
	self.DHCPByPort = {}
	// Addressing is driven by DHCP now: the host asks, a router answers. The
	// machine does not need to know which router (or how many switches) it is
	// attached to. Boot and cable events both trigger a fresh discover.
	if (self.Entity.AddEHook) then
		self.Entity:AddEHook( "subsystem", self.Name, "linked" )
		self.Entity:AddEHook( "subsystem", self.Name, "unlinked" )
		self.Entity:AddEHook( "subsystem", self.Name, "turnon" )
	end
end

// A network cable was plugged in (or restored from a save), or the machine
// booted. Ask for an address like a real DHCP client instead of relying on
// router-side link topology events.
function SUBSYSTEM:CallEvent( data )
	if ((!data) || (!data.Event)) then return end
	if ((!self.Entity) || (!self.Entity:IsValid())) then return end
	if (data.Event == "linked") then
		local ports = (self.Entity && self.Entity.Ports && self.Entity:Ports()) or {}
		local port = ports[ data[ 1 ] ]
		if ((port) && (port.Type == "network")) then self:DHCPDiscover( data[ 1 ] ) end
	elseif (data.Event == "unlinked") then
		// Drop the lease held by the interface that lost its cable. A second
		// NIC may still be linked, so only clear the host identity when every
		// interface is gone.
		local ports = (self.Entity && self.Entity.Ports && self.Entity:Ports()) or {}
		local port = ports[ data[ 1 ] ]
		if ((port) && (port.Type == "network")) then self:ReleasePort( data[ 1 ] ) end
		if (!self:HasNetworkLink()) then self:ClearDHCPAddress() end
	elseif (data.Event == "turnon") then
		self:DHCPDiscover()
	end
end

// Forget a DHCP-assigned identity (primary LAN/WAN and secondaries).
function SUBSYSTEM:ClearDHCPAddress()
	local ent = self.Entity
	if ((!ent) || (!ent.IsValid) || (!ent:IsValid())) then return false end
	local ipdata = ent.Data && ent:Data() && ent:Data().IP
	if ((!ipdata) || ipdata.Static) then return false end
	if (ent.SetLanAddress) then ent:SetLanAddress( false ) end
	if (ent.SetBSubnet) then ent:SetBSubnet( false ) end
	if (ent.SetBIP) then ent:SetBIP( false ) end
	ipdata.Router = false
	ipdata.Extra = {}
	ipdata.Mask = nil
	ipdata.MaskBits = nil
	ipdata.Gateway = nil
	if (ent.ClearInterfaces) then ent:ClearInterfaces() end
	for _, ctx in pairs( self.DHCPByPort or {} ) do
		ctx.DHCPState = nil
		ctx.LastDHCP = nil
		ctx.Lease = nil
	end
	self.LastDHCP = nil
	return true
end

// Per-interface DHCP client context. Keeps the shared client state machine
// unchanged while letting each Ethernet port hold its own lease.
function SUBSYSTEM:DHCPContext( port )
	self.DHCPByPort = self.DHCPByPort or {}
	local ctx = self.DHCPByPort[ port ]
	if (!ctx) then
		ctx = { Entity = self.Entity, Port = port }
		self.DHCPByPort[ port ] = ctx
	end
	return ctx
end

function SUBSYSTEM:LinkedNetworkPorts()
	local out = {}
	if ((!self.Entity) || (!self.Entity.Ports)) then
		if (self.NetworkPort && (self.NetworkPort != 0)) then out[ 1 ] = self.NetworkPort end
		return out
	end
	local ports = self.Entity:Ports() or {}
	local list = self.NetworkPorts
	if ((!list) || (#list == 0)) then
		list = (self.NetworkPort && (self.NetworkPort != 0)) and { self.NetworkPort } or {}
	end
	for _, idx in ipairs( list ) do
		local p = ports[ idx ]
		if ((p) && (p.Connected) && (p.Type == "network")) then out[ #out + 1 ] = idx end
	end
	return out
end

// Describe an interface lease for the UI: IPv4, matching IPv6, and family.
function SUBSYSTEM:InterfaceInfo( port, cfg )
	if ((!port) || (!cfg) || (!cfg.ip)) then return nil end
	local info = {
		Port = port,
		IPv4 = cfg.ip,
		Kind = cfg.scope or "lan",
		Mask = cfg.netmask,
		MaskBits = cfg.maskbits,
		Gateway4 = cfg.gateway,
	}
	if (self.Entity.EnsureInterfaceMAC) then
		info.MAC = self.Entity:EnsureInterfaceMAC( port )
	end
	if ((cfg.scope == "wan") || (cfg.scope == "mgmt")) then
		local bb = cfg.bb or 0
		info.IPv6 = PCMod.IPv6.Format( { 0xfd00, bb, 0, 0, 0, 0, 0, cfg.host or 0 } )
		if (PCMod.IPv6.BackbonePrefix) then
			info.IPv6Prefix = PCMod.IPv6.BackbonePrefix( bb )
			info.IPv6Gateway = PCMod.IPv6.Gateway( info.IPv6Prefix )
		end
	else
		local p = PCMod.IPv4.ParseLan( cfg.ip )
		local host = (p && (((p.sub or 0) * 256) + (p.add or 0))) or (cfg.host or 0)
		info.IPv6 = PCMod.IPv6.Format( { 0xfd00, cfg.upbb or 0, 0, cfg.lanid or 0, 0, 0, 0, host } )
		if (PCMod.IPv6.LANPrefix) then
			info.IPv6Prefix = PCMod.IPv6.LANPrefix( cfg.upbb or 0, cfg.lanid or 0 )
			info.IPv6Gateway = PCMod.IPv6.Gateway( info.IPv6Prefix )
		end
	end
	if (PCMod.IPv6.LinkLocal && info.IPv6) then
		info.IPv6LinkLocal = PCMod.IPv6.LinkLocal( info.IPv6 )
	end
	return info
end

function SUBSYSTEM:RecordInterface( port, cfg )
	local info = self:InterfaceInfo( port, cfg )
	if ((info) && self.Entity.SetInterface) then self.Entity:SetInterface( port, info ) end
end

function SUBSYSTEM:GetInterfaces()
	if (self.Entity.GetInterfaceList) then return self.Entity:GetInterfaceList() end
	return {}
end

// Source address belonging to a specific interface. New outbound traffic uses
// it so a reply/flow leaves with the address of the NIC that carries it.
function SUBSYSTEM:SourceFor( ctx, dest )
	local l = ctx && ctx.Lease
	if ((!l) || (!l.ip)) then return nil end
	if (PCMod.IPv6.IsIPv6( dest )) then
		if ((l.scope == "wan") || (l.scope == "mgmt")) then
			return PCMod.IPv6.Format( { 0xfd00, l.bb or 0, 0, 0, 0, 0, 0, l.host or 0 } )
		end
		local p = PCMod.IPv4.ParseLan( l.ip )
		local host = (p && (((p.sub or 0) * 256) + (p.add or 0))) or (l.host or 0)
		return PCMod.IPv6.Format( { 0xfd00, l.upbb or 0, 0, l.lanid or 0, 0, 0, 0, host } )
	end
	return l.ip
end

// Remove the lease held by one interface. The address is kept when another
// interface still has a lease from the same router.
function SUBSYSTEM:ReleasePort( port )
	local ctx = self.DHCPByPort && self.DHCPByPort[ port ]
	if (!ctx) then return end
	local rec = ctx.Lease
	ctx.DHCPState = nil
	ctx.Lease = nil
	ctx.LastDHCP = nil
	if (port == 0) then self.WirelessIPv4 = nil end
	if (self.Entity.ClearInterface) then self.Entity:ClearInterface( port ) end
	local latest
	for _, other in pairs( self.DHCPByPort ) do
		if (other.LastDHCP) then latest = other.LastDHCP end
	end
	self.LastDHCP = latest
	if ((!rec) || (!PCMod.DHCPClient.ReleaseHost)) then return end
	for p, other in pairs( self.DHCPByPort ) do
		if ((p != port) && (other.Lease) && (other.Lease.server == rec.server)) then return end
	end
	PCMod.DHCPClient.ReleaseHost( self.Entity, rec.scope, rec, rec.server )
	// The remaining interface's lease becomes the primary identity. Keep the
	// other family: another adapter may still be using it.
	for _, other in pairs( self.DHCPByPort ) do
		if (other.Lease && PCMod.DHCPClient.ApplyHost) then
			PCMod.DHCPClient.ApplyHost( self.Entity, other.Lease, true )
			break
		end
	end
end

// True when the machine has another active link besides `port` (an Ethernet
// cable or an associated Wi-Fi router).
function SUBSYSTEM:HasOtherInterface( port )
	for _, idx in ipairs( self:LinkedNetworkPorts() ) do
		if (idx != port) then return true end
	end
	if ((port != 0) && self:WirelessConnected()) then return true end
	return false
end

function SUBSYSTEM:HasNetworkLink()
	if ((!self.Entity) || (!self.Entity:IsValid())) then return false end
	local ports = self.Entity:Ports() or {}
	for _, port in pairs( ports ) do
		if (port.Connected && ((port.Type == "network") || (port.Type == "optic"))) then return true end
	end
	return self:WirelessConnected()
end

// Broadcast a DHCP discover on an interface. The first router whose port the
// request arrives on answers with the address for that segment (LAN router ->
// private address, backbone router -> backbone host). With no port argument,
// every linked Ethernet port asks on its own. Retries cover a cable that was
// plugged in before the rest of the segment was ready.
function SUBSYSTEM:DHCPDiscover( port, retries )
	if ((!self.Entity) || (!self.Entity:IsValid())) then return false end
	if (port == nil) then
		// Ask on every active interface: each Ethernet port and Wi-Fi (port 0)
		// can be on a different network and needs its own lease.
		local any = false
		for _, idx in ipairs( self:LinkedNetworkPorts() ) do
			if (self:DHCPDiscover( idx, retries )) then any = true end
		end
		if (self:WirelessConnected()) then
			if (self:DHCPDiscover( 0, retries )) then any = true end
		end
		return any
	end
	retries = retries or 3
	if (port == 0) then
		if (!self:WirelessConnected()) then return false end
	else
		local ports = (self.Entity.Ports && self.Entity:Ports()) or {}
		local p = ports[ port ]
		if ((!p) || (!p.Connected)) then return false end
	end
	local ipdata = self.Entity:Data() && self.Entity:Data().IP
	if (ipdata && ipdata.Static) then return false end
	local ctx = self:DHCPContext( port )
	ctx.LastDHCP = nil
	self.LastDHCP = nil
	PCMod.DHCPClient.Start( ctx, {
		send = function( body )
			self:SendPacket( PCMod.Net.BroadcastIP, PCMod.Net.DHCPServerPort, body, nil, "0.0.0.0", nil, port )
		end,
		apply = function( cfg )
			ctx.Lease = cfg
			if (port == 0) then self.WirelessIPv4 = true end
			PCMod.DHCPClient.ApplyHost( self.Entity, cfg, self:HasOtherInterface( port ) )
			self:RecordInterface( port, cfg )
		end,
	} )
	if ((!ctx.LastDHCP) && (retries > 0) && timer && timer.Simple) then
		timer.Simple( 1, function()
			if ((!IsValid( self.Entity )) || (ctx.LastDHCP)) then return end
			self:DHCPDiscover( port, retries - 1 )
		end )
	end
	return true
end

function SUBSYSTEM:HandleDHCP( port, body )
	local ctx = self.DHCPByPort && self.DHCPByPort[ port ]
	if (!ctx) then return false end
	local ok = PCMod.DHCPClient.Handle( ctx, body )
	if (ctx.LastDHCP) then self.LastDHCP = ctx.LastDHCP end
	return ok
end

// ARP is how a router finds us without tracking devices. Answer only for an
// address we actually own; the reply carries our MAC.
function SUBSYSTEM:HandleARP( port, body, macs )
	if (!PCMod.Net.IsARP( body )) then return false end
	if (body[2] == "request") then
		local target = body[3]
		if (!self.Entity:IsAddressedTo( target )) then return true end
		local myip = self.Entity:GetSourceAddress( target ) or self.Entity:GetFullIP()
		if (!myip) then return true end
		local mac
		if (self.Entity.EnsureInterfaceMAC) then
			mac = self.Entity:EnsureInterfaceMAC( port )
		elseif (self.Entity.EnsureMAC) then
			mac = self.Entity:EnsureMAC()
		end
		self.Entity:SendPacket( port, body[4] or "0.0.0.0", 0, PCMod.Net.ARPReply( target, myip, mac ), nil, myip )
		return true
	end
	return true
end

function SUBSYSTEM:GetOSSubsystem( name )
	return PCMod.GetSubsystem( self.Entity:Data(), name )
end

function SUBSYSTEM:PacketRecieved( packet )
	if (self:GetOSSubsystem( "bios" ).OS) then
		self:GetOSSubsystem( "bios" ).OS:NetDataRecieved( packet )
	end
end

// A directly-connected peer (another PC on a crossover cable) sent us a raw
// "sendpacket". There is no router on the link to route it, so create the packet
// and deliver it locally when it is addressed to us.
function SUBSYSTEM:DataRecieved( port, data )
	if (istable( data ) && (data[1] == "sendpacket") && istable( data[2] )) then
		local app = data[2][4]
		if (istable( app ) && (app[1] == "dhcp")) then
			return self:HandleDHCP( port, app )
		end
		if (PCMod.Net.IsARP( app )) then
			return self:HandleARP( port, app, data[4] or {} )
		end
		if (PCMod.Net.IsNDP( app ) && PCMod.NDP) then
			return PCMod.NDP.Handle( self, port, app, data[4] or {} )
		end
		local body = data[2]
		local macs = data[4] or {}
		local pid = PCMod.Network.CreatePacket( body[1], body[2], body[3], body[4], nil, macs.SourceMAC, macs.DestMAC, data[5] )
		if (!pid) then return end
		local packet = PCMod.Network.Packets[ pid ]
		if (!packet) then return end
		if (self.Entity:IsAddressedTo( packet.Dest )) then
			packet.Delivered = true
			packet.ViaWireless = false
			self:PacketRecieved( packet )
		else
			// A switch floods frames, so unrelated PCs also see this raw frame.
			// We created a packet copy just to inspect it - release the slot
			// instead of leaving it in flight forever.
			packet.Delivered = true
		end
	end
end

// Send one frame over the Wi-Fi link. Wireless has its own latency profile
// and may drop the frame; the router sees the same "sendpacket" shape as a
// cable frame.
function SUBSYSTEM:DeliverWireless( data )
	local ent = self.WirelessEnt
	if ((!ent) || (!ent.DataRecieved)) then return false end
	local function deliver()
		if ((!ent.IsValid) || (ent:IsValid())) then ent:DataRecieved( 0, data ) end
	end
	if (PCMod.Latency && PCMod.Latency.Deliver) then
		local dist = PCMod.Latency.DistanceBetween && PCMod.Latency.DistanceBetween( self.Entity, ent )
		local range = (PCMod.Cfg && PCMod.Cfg.WirelessRange) or 0
		return PCMod.Latency.Deliver( deliver, "wireless", dist, range )
	end
	deliver()
	return true
end

function SUBSYSTEM:SendPacket( dest, port, body, ttl, src, viaWireless, forcePort )
	// Loopback is accepted in IPv4 (127.0.0.1), IPv6 (::1) and hostname form.
	// Anything addressed to one of our own addresses is local traffic too: the
	// kernel short-circuits it instead of putting it on the wire. Without this
	// a host could not ping itself (the frame would never come back to it).
	local selfAddressed = (self.Entity && self.Entity.IsAddressedTo && self.Entity:IsAddressedTo( dest ))
	if (PCMod.IPv6.IsLoopback( dest ) || selfAddressed) then
		local pk = {}
		pk.Source = src or self.Entity:GetSourceAddress( dest )
		pk.Dest = dest
		pk.Port = port
		pk.SourcePort = port
		pk.Body = body
		pk.TTL = tonumber( ttl ) or tonumber( PCMod.Cfg && PCMod.Cfg.DefaultTTL ) or 64
		pk.Delivered = true
		pk.ViaWireless = false
		self:PacketRecieved( pk )
		return
	end
	// Wi-Fi is just another interface (port 0), not a preferred uplink. Pick
	// the adapter whose lease covers the destination; replies go back out the
	// link they arrived on (`viaWireless`).
	local wireless = self:WirelessConnected()
	local sendPort
	if (forcePort != nil) then
		sendPort = forcePort
	elseif (viaWireless == true) then
		sendPort = 0
	elseif (viaWireless == false) then
		sendPort = self:PickPort( dest, src, false )
	else
		sendPort = self:PickPort( dest, src, true )
	end
	if ((sendPort == 0) && (!wireless)) then sendPort = self:PickPort( dest, src, false ) end
	if ((!sendPort) || ((sendPort == 0) && (!wireless))) then return end
	if (sendPort == 0) then
		local ctx = self.DHCPByPort && self.DHCPByPort[ 0 ]
		local wsrc = src or self:SourceFor( ctx, dest ) or self:GetWirelessSource( dest ) or self.Entity:GetSourceAddress( dest )
		local wmac
		if (self.Entity.EnsureInterfaceMAC) then
			wmac = self.Entity:EnsureInterfaceMAC( 0 )
		elseif (self.Entity.EnsureMAC) then
			wmac = self.Entity:EnsureMAC()
		end
		local frame = { "sendpacket", { wsrc, dest, port, body }, nil, nil, ttl }
		if (wmac && PCMod.MAC) then
			frame[ 4 ] = { SourceMAC = wmac, DestMAC = PCMod.MAC.BROADCAST }
		end
		self:DeliverWireless( frame )
		return
	end
	// Source from the lease owned by the chosen interface, so a multi-homed
	// host sends with the address of the NIC it uses (IPv4 or IPv6).
	local ctx = self.DHCPByPort && self.DHCPByPort[ sendPort ]
	local sendSrc = src or self:SourceFor( ctx, dest )
	return self.Entity:SendPacket( sendPort, dest, port, body, ttl, sendSrc )
end

// Every active interface: linked Ethernet ports, plus Wi-Fi (port 0) when
// allowed and associated.
function SUBSYSTEM:CandidatePorts( allowWireless )
	local ports = self:LinkedNetworkPorts()
	if (allowWireless && self:WirelessConnected()) then
		table.insert( ports, 0 )
	end
	if (#ports == 0) then
		local p = self.NetworkPort or 0
		if (p != 0) then
			ports[ 1 ] = p
		elseif (allowWireless && self:WirelessConnected()) then
			ports[ 1 ] = 0
		end
	end
	return ports
end

// Choose the interface for outbound traffic: the one whose lease owns the
// source address (replies), else the one whose subnet contains the
// destination, else the primary identity's interface.
function SUBSYSTEM:PickPort( dest, src, allowWireless )
	local ports = self:CandidatePorts( allowWireless )
	if (#ports == 0) then return 0 end
	local ctxs = self.DHCPByPort or {}
	if (src) then
		for _, idx in ipairs( ports ) do
			local c = ctxs[ idx ]
			if (c && c.Lease && (c.Lease.ip == src)) then return idx end
		end
	end
	if (dest) then
		local h = PCMod.IPv6.IsIPv6( dest ) and PCMod.IPv6.Hierarchy( dest ) or nil
		for _, idx in ipairs( ports ) do
			local c = ctxs[ idx ]
			local l = c && c.Lease
			if (l && l.ip) then
				if (h) then
					if ((h.bb == l.upbb) && (h.lan == l.lanid)) then return idx end
				elseif (PCMod.IPv4.SameLan( l.ip, dest, l.maskbits or 24 )) then
					return idx
				end
			end
		end
		// Not on a directly connected subnet: use the family that matches the
		// destination. Backbone traffic leaves the WAN adapter, everything else
		// the LAN adapter, instead of whichever port happens to be first.
		local wantWan
		if (h) then
			wantWan = (h.lan == 0)
		else
			wantWan = (PCMod.IPv4 && PCMod.IPv4.IsBackbone && PCMod.IPv4.IsBackbone( dest )) and true or false
		end
		for _, idx in ipairs( ports ) do
			local c = ctxs[ idx ]
			local l = c && c.Lease
			if (l) then
				local isWan = ((l.scope == "wan") || (l.scope == "mgmt"))
				if (isWan == wantWan) then return idx end
			end
		end
	end
	// Default route: prefer the interface that owns our primary identity, then
	// any interface with a lease, then the first candidate.
	local primary = self.Entity.GetFullIP && self.Entity:GetFullIP()
	local wan = self.Entity.GetFullBIP && self.Entity:GetFullBIP()
	for _, idx in ipairs( ports ) do
		local c = ctxs[ idx ]
		local l = c && c.Lease
		if (l && l.ip && ((l.ip == primary) || (l.ip == wan))) then return idx end
	end
	for _, idx in ipairs( ports ) do
		local c = ctxs[ idx ]
		if (c && c.Lease) then return idx end
	end
	return ports[ 1 ]
end

// The address this PC should use when sending through its Wi-Fi router: the
// lease that router handed out (primary when it owns our primary address,
// otherwise the secondary it gave us).
function SUBSYSTEM:GetWirelessSource( dest )
	local ent = self.WirelessEnt
	if ((!ent) || (!ent:IsValid())) then return nil end
	local ipdata = self.Entity:Data() && self.Entity:Data().IP
	if (!ipdata) then return nil end
	local want = ent:EntIndex()
	local v6 = dest && PCMod.IPv6.IsIPv6( dest )
	if (ipdata.Router == want) then
		if (v6) then return self.Entity:GetIPv6() or self.Entity:GetFullIP() end
		return self.Entity:GetFullIP()
	end
	for _, ex in ipairs( ipdata.Extra or {} ) do
		if (ex.Router == want) then
			local full = ex.IPv4
			if (v6) then
				local p = PCMod.IPv4.ParseLan( full )
				local host = (p and ((p.sub or 0) * 256 + p.add)) or 0
				return PCMod.IPv6.Format( { 0xfd00, ex.UpBB or 0, 0, ex.LanID or 0, 0, 0, 0, host } ) or full
			end
			return full
		end
	end
	return nil
end

// The PC has an active in-range wireless link to a router.
function SUBSYSTEM:WirelessConnected()
	local ent = self.WirelessEnt
	if ((!ent) || (!ent:IsValid())) then return false end
	if ((!self.Entity) || (!self.Entity:IsValid())) then return false end
	local range = (PCMod.Cfg && PCMod.Cfg.WirelessRange) || 0
	if (range > 0) then
		local dist = (self.Entity:GetPos() - ent:GetPos()):Length()
		if (dist > range) then return false end
	end
	return true
end

// Drop the current wireless link and unregister the PC from that router's
// subnet (if it was registered through this link).
function SUBSYSTEM:DisconnectWireless()
	local ent = self.WirelessEnt
	if ((ent) && (ent:IsValid())) then
		local rdata = PCMod.Data[ ent:EntIndex() ]
		local rdrv = rdata && rdata.Subsystems && rdata.Subsystems[ "router" ]
		if (rdrv && rdrv.RemoveWirelessClient) then rdrv:RemoveWirelessClient( self.Entity ) end
	end
	// Drop the Wi-Fi interface's own lease/address; a cable lease stays.
	if (self.DHCPByPort && self.DHCPByPort[ 0 ] && self.ReleasePort) then self:ReleasePort( 0 ) end
	self.WirelessEnt = nil
	self.WirelessPass = ""
	self.WirelessIPv4 = nil
end

function SUBSYSTEM:GetMAC()
	return self.Entity:EnsureMAC()
end

function SUBSYSTEM:GetIP()
	return self.Entity:GetIP()
end

function SUBSYSTEM:GetFullIP()
	return self.Entity:GetFullIP()
end

// Secondary addresses (leases from other routers this device is linked to).
function SUBSYSTEM:GetExtraAddresses()
	if (self.Entity.GetExtraAddresses) then return self.Entity:GetExtraAddresses() end
	return {}
end

function SUBSYSTEM:GetIPv6()
	return self.Entity:GetIPv6()
end

function SUBSYSTEM:GetIPv6Prefix()
	return self.Entity:GetIPv6Prefix()
end

function SUBSYSTEM:GetIPv6Gateway()
	return self.Entity:GetIPv6Gateway()
end

function SUBSYSTEM:GetIPv6LinkLocal()
	return self.Entity:GetIPv6LinkLocal()
end

function SUBSYSTEM:GetBIPv6Prefix()
	return self.Entity:GetBIPv6Prefix()
end

function SUBSYSTEM:GetBIPv6()
	return self.Entity:GetBIPv6()
end

function SUBSYSTEM:GetBIPv6Gateway()
	return self.Entity:GetBIPv6Gateway()
end

function SUBSYSTEM:GetBIPv6LinkLocal()
	return self.Entity:GetBIPv6LinkLocal()
end