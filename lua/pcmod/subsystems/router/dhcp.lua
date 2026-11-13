// ---------------------------------------------------------------------------------------------------------
// router/dhcp.lua - DHCP pools, leases and LAN address management.
// Included by subsystems/router.lua; all functions extend SUBSYSTEM.
// ---------------------------------------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// DHCP delegation. Leases live in the MAC-keyed engine; these methods keep the
// subsystem-facing names and apply the result to an entity.
// ---------------------------------------------------------------------------

function SUBSYSTEM:DHCPPool( scope )
	return PCMod.DHCPServer.Pool( self, scope )
end

// The scope this router hands leases out on: a backbone serves the backbone
// segment, a LAN router serves its own RFC1918 segment.
function SUBSYSTEM:LeaseScope()
	return self:IsBackbone() and "wan" or "lan"
end

function SUBSYSTEM:StaticLeases() return PCMod.DHCPServer.StaticList( self, self:LeaseScope() ) end
function SUBSYSTEM:StaticLeaseForMAC( mac ) return PCMod.DHCPServer.StaticForMAC( self, self:LeaseScope(), mac ) end
function SUBSYSTEM:DynamicLeases() return PCMod.DHCPServer.List( self, self:LeaseScope() ) end
function SUBSYSTEM:AddStaticLease( ip, mac ) return PCMod.DHCPServer.AddStatic( self, self:LeaseScope(), ip, mac ) end
function SUBSYSTEM:DeleteStaticLease( idx ) return PCMod.DHCPServer.DeleteStatic( self, self:LeaseScope(), idx ) end

// Release every LAN lease that arrived on this router port. Multi-NIC hosts
// hold one lease per interface, so a cable event must only drop the lease for
// the interface that was unplugged.
function SUBSYSTEM:ReleaseLeasesOnPort( port )
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
function SUBSYSTEM:EntityForMAC( mac )
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
function SUBSYSTEM:ApplyLease( scope, rec, ent )
	if ((!rec) || (!ent)) then return false end
	return PCMod.DHCPClient.ApplyHost( ent, PCMod.DHCPServer.Config( self, rec ) )
end

// Reserve and immediately apply a lease. The DORA path uses Offer/Ack; this
// synchronous form is for renumbering and the control panel.
function SUBSYSTEM:AssignDHCP( scope, pc, port )
	if ((!pc) || (!pc:IsValid())) then return nil end
	local mac = pc.GetMAC && pc:GetMAC()
	local rec = PCMod.DHCPServer.Lease( self, scope, mac, port )
	if (!rec) then return nil end
	self:ApplyLease( scope, rec, pc )
	return rec.host
end

function SUBSYSTEM:ReleaseDHCP( scope, pc )
	if ((!pc) || (!pc.IsValid) || (!pc:IsValid())) then return end
	local mac = pc.GetMAC && pc:GetMAC()
	local rec = mac && PCMod.DHCPServer.Find( self, scope, mac )
	if (!rec) then return end
	PCMod.DHCPServer.Release( self, mac )
	PCMod.DHCPClient.ReleaseHost( pc, scope, rec, self.Entity:EntIndex() )
	return rec.host
end

function SUBSYSTEM:RenewDHCP( scope, pc )
	if ((!pc) || (!pc:IsValid())) then return nil end
	local mac = pc.GetMAC && pc:GetMAC()
	local rec = mac && PCMod.DHCPServer.Find( self, scope, mac )
	if (!rec) then return self:AssignDHCP( scope, pc ) end
	rec.offered = false
	rec.expires = PCMod.Net.Now() + (PCMod.Net.LeaseTime or 3600)
	self:ApplyLease( scope, rec, pc )
	return rec.host
end

function SUBSYSTEM:HasDHCPLease( scope, pc )
	if (!pc) then return false end
	local mac = pc.GetMAC && pc:GetMAC()
	if (mac && PCMod.DHCPServer.Find( self, scope, mac )) then return true end
	local ifaces = pc.GetInterfaceMACs && pc:GetInterfaceMACs()
	for _, imac in pairs( ifaces or {} ) do
		if (PCMod.DHCPServer.Find( self, scope, imac )) then return true end
	end
	return false
end

function SUBSYSTEM:HasLeaseForMAC( scope, mac )
	if (!mac) then return false end
	return (PCMod.DHCPServer.Find( self, scope, mac ) != nil)
end

function SUBSYSTEM:HasLease( pc )
	return self:HasDHCPLease( "lan", pc )
end

// True when the device on this port (or anything behind a switch on it) owns
// the address. Returned port stays the router's own port, so delivery still
// goes through the switch.
function SUBSYSTEM:PortMatchesAddress( port, ip )
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

function SUBSYSTEM:HasRouter( ip )
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

function SUBSYSTEM:HasPC( ip )
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
// is needed; the direct-port check remains for clients without DHCP.
function SUBSYSTEM:IsWiredClient( pc )
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
function SUBSYSTEM:HasWirelessClient( pc )
	if (!pc) then return false end
	return ((self.WirelessClients) && (self.WirelessClients[ pc:EntIndex() ] != nil)) or false
end

// Register a PC that connected to this router over Wi-Fi. Association only
// handles authentication/range; the client gets its address from DHCP like
// any other host, so nothing is leased here.
function SUBSYSTEM:AddWirelessClient( pc )
	if ((!pc) || (!pc:IsValid())) then return false end
	if (!self.WirelessClients) then self.WirelessClients = {} end
	self.WirelessClients[ pc:EntIndex() ] = pc
	return true
end

// Release and immediately re-request a client's lease. The control panel's
// "Renew" button uses this to pick up the router's current pool/netmask
// without physically relinking the device. A client with no recorded lease is
// treated like a fresh link, so a stale lease table self-heals.
function SUBSYSTEM:RenewLease( pc )
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
function SUBSYSTEM:GetLanNetmask()
	local m = tonumber( self:GetCfg().LanNetmask ) or 24
	return math.Clamp( math.floor( m ), 16, 32 )
end

// The third octet of the LAN network (0-255), derived from the full base.
function SUBSYSTEM:GetLanNet()
	return math.floor( self:GetLanBase() / 256 ) % 256
end

// The fourth octet of the LAN network, derived from the full base.
function SUBSYSTEM:GetLanLow()
	return self:GetLanBase() % 256
end

// Number of addresses in one subnet of the given mask.
function SUBSYSTEM:LanBlockSize( mask )
	mask = math.Clamp( math.floor( tonumber( mask ) or self:GetLanNetmask() ), 16, 32 )
	return 2 ^ (32 - mask)
end

// Align a full 32-bit LAN base to the subnet size. Masks stay in 16-32, so a
// LAN subnet always sits inside one RFC1918 block and its host space fits the
// 16-bit IID used by the emulated IPv6 layer.
function SUBSYSTEM:ComputeLanBase( mask, base )
	mask = math.Clamp( math.floor( tonumber( mask ) or self:GetLanNetmask() ), 16, 32 )
	base = math.floor( tonumber( base ) or tonumber( self:GetCfg().LanBase ) or 0 )
	local size = self:LanBlockSize( mask )
	return math.floor( base / size ) * size
end

function SUBSYSTEM:GetLanBase( mask )
	return self:ComputeLanBase( mask or self:GetLanNetmask(), self:GetCfg().LanBase )
end

// Human-readable LAN prefix, e.g. "192.168.5.0/24" or "10.20.0.0/16".
function SUBSYSTEM:GetLanPrefix( mask, base )
	local m = math.Clamp( math.floor( tonumber( mask ) or self:GetLanNetmask() ), 16, 32 )
	base = self:ComputeLanBase( m, base or self:GetCfg().LanBase )
	return PCMod.IPv4.FromInt( base ) .. "/" .. tostring( m )
end

// Last leaseable host id within the subnet. Host 1 is the gateway and the last
// address is the broadcast, so a /30 has a single client (id 2).
function SUBSYSTEM:PoolMax()
	return math.max( 2, self:LanBlockSize() - 2 )
end

// Keep the pool inside the current subnet and ordered. Host 1 is the gateway,
// so the first leaseable id is always 2.
function SUBSYSTEM:ClampDHCPPool()
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
function SUBSYSTEM:ApplyLanAddress()
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
function SUBSYSTEM:RenumberLeases()
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
function SUBSYSTEM:SetLanNetmask( mask )
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
// octets. Kept for the web field; `lanaddr` sets the full base.
function SUBSYSTEM:SetLanNet( net )
	local n = math.Clamp( math.floor( tonumber( net ) or 0 ), 0, 255 )
	local base = self:GetLanBase()
	local newBase = (base - (base % 65536)) + (n * 256)
	return self:SetLanBase( newBase )
end

// Move the LAN network anywhere inside RFC1918. The base is aligned to the
// subnet size and stored as a full 32-bit value; LanNet/LanLow stay in sync for
// older saves and displays.
function SUBSYSTEM:SetLanBase( base )
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

