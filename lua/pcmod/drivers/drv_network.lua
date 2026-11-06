
// Network Driver for PCMod 2

DRV = PCMod.DeriveDriver( "base" )

DRV.NiceName = "Generic Network Driver"
DRV.Name = "gen_network"
DRV.Type = "network"

DRV.PTData = {}
DRV.NetworkPort = 0
DRV.WirelessEnt = nil
DRV.WirelessPass = ""
DRV.WirelessIPv4 = nil

function DRV:Initialize()
	if (!self.Entity) then return end
	for k, v in pairs( self.Entity:Ports() ) do
		if (v.Type == "network") then self.NetworkPort = k end
	end
end

function DRV:GetOSDriver( dname )
	return PCMod.Data[ self.Entity:EntIndex() ].Drivers[ dname ]
end

function DRV:PacketRecieved( packet )
	if (self:GetOSDriver( "gen_bios" ).OS) then
		self:GetOSDriver( "gen_bios" ).OS:NetDataRecieved( packet )
	end
end

// A directly-connected peer (another PC on a crossover cable) sent us a raw
// "sendpacket". There is no router on the link to route it, so create the packet
// and deliver it locally when it is addressed to us.
function DRV:DataRecieved( port, data )
	if (istable( data ) && (data[1] == "sendpacket") && istable( data[2] )) then
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

function DRV:SendPacket( dest, port, body, ttl, src, viaWireless )
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
	// Wireless uplink: when connected to a router, send through it over the air
	// instead of the cable port. Falls back to the cable when out of range.
	// A reply (viaWireless ~= nil) goes back out the interface the request
	// arrived on; new traffic prefers Wi-Fi while it is connected.
	local wireless = self:WirelessConnected()
	if (viaWireless != nil) then wireless = (viaWireless == true) && wireless end
	if (wireless) then
		local wsrc = src or self:GetWirelessSource( dest ) or self.Entity:GetSourceAddress( dest )
		self.WirelessEnt:DataRecieved( 0, { "sendpacket", { wsrc, dest, port, body }, nil, nil, ttl } )
		return
	end
	if (self.NetworkPort == 0) then return end
	return self.Entity:SendPacket( self.NetworkPort, dest, port, body, ttl, src )
end

// The address this PC should use when sending through its Wi-Fi router: the
// lease that router handed out (primary when it owns our primary address,
// otherwise the secondary it gave us).
function DRV:GetWirelessSource( dest )
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
			local full = "192.168." .. tostring( ex.Sub ) .. "." .. tostring( ex.Add )
			if (v6) then
				return PCMod.IPv6.Format( { 0xfd00, ex.UpBB or 0, 0, ex.LanID or 0, 0, 0, 0, (ex.Sub or 0) * 256 + (ex.Add or 0) } ) or full
			end
			return full
		end
	end
	return nil
end

// The PC has an active in-range wireless link to a router.
function DRV:WirelessConnected()
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
function DRV:DisconnectWireless()
	local ent = self.WirelessEnt
	if ((ent) && (ent:IsValid())) then
		local rdata = PCMod.Data[ ent:EntIndex() ]
		local rdrv = rdata && rdata.Drivers && rdata.Drivers[ "webgr_router" ]
		if (rdrv && rdrv.RemoveWirelessClient) then rdrv:RemoveWirelessClient( self.Entity ) end
	end
	self.WirelessEnt = nil
	self.WirelessPass = ""
	self.WirelessIPv4 = nil
end

function DRV:GetMAC()
	return self.Entity:EnsureMAC()
end

function DRV:GetIP()
	return self.Entity:GetIP()
end

function DRV:GetFullIP()
	return self.Entity:GetFullIP()
end

// Secondary addresses (leases from other routers this device is linked to).
function DRV:GetExtraAddresses()
	if (self.Entity.GetExtraAddresses) then return self.Entity:GetExtraAddresses() end
	return {}
end

function DRV:GetIPv6()
	return self.Entity:GetIPv6()
end

function DRV:GetIPv6Prefix()
	return self.Entity:GetIPv6Prefix()
end

function DRV:GetIPv6Gateway()
	return self.Entity:GetIPv6Gateway()
end

function DRV:GetIPv6LinkLocal()
	return self.Entity:GetIPv6LinkLocal()
end

function DRV:GetBIPv6Prefix()
	return self.Entity:GetBIPv6Prefix()
end

function DRV:GetBIPv6Gateway()
	return self.Entity:GetBIPv6Gateway()
end