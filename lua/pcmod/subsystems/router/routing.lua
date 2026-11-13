// ---------------------------------------------------------------------------------------------------------
// router/routing.lua - Distance-vector routing, backbone identity and Wi-Fi clients.
// Included by subsystems/router.lua; all functions extend SUBSYSTEM.
// ---------------------------------------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Shared DHCP lease table. LAN clients and backbone-side hosts use the same
// allocator; only the pool bounds and the address applier differ.
// ---------------------------------------------------------------------------

// LAN-scope aliases. The engine itself is scope-aware; these names exist
// because most callers only ever deal with their own LAN.
function SUBSYSTEM:AssignLease( pc )
	return self:AssignDHCP( "lan", pc )
end

function SUBSYSTEM:ReleaseLease( pc )
	return self:ReleaseDHCP( "lan", pc )
end

// A new /64 id within this backbone's /32 (one per attached LAN router).
function SUBSYSTEM:NextLanID()
	self.NextLan = (self.NextLan or 0) + 1
	return self.NextLan
end

function SUBSYSTEM:IsBackbone()
	return ((self.Entity != nil) && (self.Entity.GetClass != nil) && (self.Entity:GetClass() == "pcmod_brouter"))
end

// Backbone web guard. The control plane is management-only: only hosts 1-11
// of this backbone's /24 (the router itself and the MGMNT pool) may open the
// panel. The fibre DHCP pool (12-254), LAN identities and IPv6-derived LAN
// sources are all denied by default. Normal forwarding is unaffected (the
// backbone firewall stays in its default-allow state) and the router's own
// generated replies never pass through this check.
function SUBSYSTEM:BackboneWebAllowed( source )
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
function SUBSYSTEM:ReconfigureClients()
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
function SUBSYSTEM:PushClientConfig( pc, upbb, lanid )
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
function SUBSYSTEM:RecalcRoutes()
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
function SUBSYSTEM:GetDV( excludeBB )
	local dv = {}
	for bb, r in pairs( self.Routes or {} ) do
		if ((!excludeBB) || (r.via != excludeBB)) then dv[ bb ] = r.dist end
	end
	return dv
end

function SUBSYSTEM:NeighborDrv( port )
	local p = port
	if (type( p ) == "number") then
		local ports = self.Entity.Ports && self.Entity:Ports()
		p = ports && ports[ p ]
	end
	local ent = p && p.ConEnt
	if ((!ent) || (!ent:IsValid())) then return nil end
	local data = PCMod.Data[ ent:EntIndex() ]
	return data && data.Subsystems && data.Subsystems[ "router" ]
end

// Push this router's distance vector to every neighbouring backbone, with
// split horizon so a route is never sent back the way it was learned.
function SUBSYSTEM:AdvertiseRoutes()
	if (!self:IsBackbone()) then return end
	for bb, port in pairs( self.Neighbors or {} ) do
		local drv = self:NeighborDrv( port )
		if (drv && drv.RecvRoutes) then drv:RecvRoutes( self.Entity:GetBSubnet(), self:GetDV( bb ) ) end
	end
end

// Merge a neighbour's distance vector and recompute the table. Keeping the
// last advertisement per neighbour lets RecalcRoutes relax multi-hop paths.
function SUBSYSTEM:RecvRoutes( fromBB, dv )
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
function SUBSYSTEM:RoutesDiffer( a, b )
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
function SUBSYSTEM:RouteForBB( bb )
	local r = self.Routes && self.Routes[ bb ]
	if ((!r) || (!r.via)) then return nil end
	return self.Neighbors && self.Neighbors[ r.via ]
end

function SUBSYSTEM:RemoveWirelessClient( pc )
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
function SUBSYSTEM:DeliverToWirelessClient( packet )
	for _, pc in pairs( self.WirelessClients or {} ) do
		if ((pc) && (pc:IsValid()) && (pc.IsAddressedTo) && (pc:IsAddressedTo( packet.Dest ))) then
			packet.Delivered = true
			packet.ViaWireless = true
			local data = PCMod.Data[ pc:EntIndex() ]
			local drv = data && data.Subsystems && data.Subsystems[ "network" ]
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
function SUBSYSTEM:GetIPv6()
	return self.Entity:GetIPv6()
end

function SUBSYSTEM:GetIPv6Prefix()
	return self.Entity:GetIPv6Prefix()
end

function SUBSYSTEM:GetBIPv6()
	return self.Entity:GetBIPv6()
end

function SUBSYSTEM:GetBIPv6Prefix()
	return self.Entity:GetBIPv6Prefix()
end

// Is addr on one of this router's directly attached IPv6 subnets?
function SUBSYSTEM:HasIPv6Subnet( addr )
	if (PCMod.IPv6.InSubnet( addr, self:GetIPv6Prefix() )) then return true end
	if (PCMod.IPv6.InSubnet( addr, self:GetBIPv6Prefix() )) then return true end
	return false
end

