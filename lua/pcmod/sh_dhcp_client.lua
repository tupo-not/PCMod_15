// ---------------------------------------------------------------------------------------------------------
// sh_dhcp_client.lua - DHCP client state machine (DORA)
//
// The client knows nothing about the topology. It broadcasts a discover, then
// follows whichever offer arrives. The same code runs on a computer and on a
// router's WAN interface; only the apply callback differs.
// ---------------------------------------------------------------------------------------------------------

PCMod = PCMod or {}
PCMod.DHCPClient = PCMod.DHCPClient or {}

function PCMod.DHCPClient.Start( owner, opts )
	if ((!owner) || (!opts) || (!opts.send)) then return false end
	local ent = owner.Entity
	if ((!ent) || (!ent:IsValid())) then return false end
	local mac = ent.EnsureMAC && ent:EnsureMAC() or nil
	if (!mac) then return false end
	owner.DHCPState = {
		xid = PCMod.Net.NewXID(),
		mac = mac,
		send = opts.send,
		apply = opts.apply,
	}
	local body = PCMod.Net.DHCPDiscover( owner.DHCPState.xid, mac )
	opts.send( body )
	return true
end

// Feed a DHCP body into the client. Returns true when it was consumed.
function PCMod.DHCPClient.Handle( owner, body )
	if ((!owner) || (!PCMod.Net.IsDHCP( body ))) then return false end
	local state = owner.DHCPState
	if (!state) then return false end
	local kind = body[2]
	local xid = body[3]
	local server = body[4]
	local config = body[5]
	// A broadcast answer is only ours when the lease names our MAC.
	if ((kind == "offer") || (kind == "ack")) then
		if (istable( config ) && config.mac && state.mac) then
			if (PCMod.Net.MACKey( config.mac ) != PCMod.Net.MACKey( state.mac )) then return true end
		end
	end
	if (kind == "offer") then
		if ((xid) && (xid != state.xid)) then return true end
		// Accept the first offer; later offers from other servers are ignored.
		if (state.server && (state.server != server)) then return true end
		if (state.requested) then return true end
		state.server = server
		state.offer = config
		state.requested = true
		if (state.send) then state.send( PCMod.Net.DHCPRequest( state.xid, server, state.mac ) ) end
		return true
	end
	if (kind == "ack") then
		if ((xid) && (xid != state.xid)) then return true end
		if ((server) && (state.server) && (server != state.server)) then return true end
		state.done = true
		if (state.apply) then state.apply( config ) end
		owner.LastDHCP = { time = PCMod.Net.Now(), address = (config && config.ip), scope = (config && config.scope), server = server }
		return true
	end
	if (kind == "nack") then
		state.done = false
		state.offer = nil
		return true
	end
	if (kind == "release") then return true end
	return false
end

// Apply a DHCP offer to a normal host. Keeps the existing primary/secondary
// multi-homing model: a lease from a different router becomes a secondary.
function PCMod.DHCPClient.ApplyHost( ent, cfg )
	if ((!ent) || (!cfg) || (!cfg.ip)) then return false end
	local data = ent.Data && ent:Data()
	local ipdata = data && data.IP
	if (!ipdata) then return false end
	if (ipdata.Static) then return false end
	if (cfg.scope == "wan") then
		// The DHCP answer carries the full interface configuration, so show the
		// same netmask/gateway a static setup would.
		if (cfg.netmask) then ipdata.Mask = cfg.netmask end
		if (cfg.maskbits) then ipdata.MaskBits = cfg.maskbits end
		if (cfg.gateway) then ipdata.Gateway = cfg.gateway end
		if (ent.SetLanAddress) then ent:SetLanAddress( false ) end
		if (cfg.upbb != nil && ent.SetUpBB) then ent:SetUpBB( cfg.upbb ) end
		if (cfg.lanid != nil && ent.SetLanID) then ent:SetLanID( cfg.lanid ) end
		if (ent.SetBSubnet) then ent:SetBSubnet( cfg.bb ) end
		if (ent.SetBIP) then ent:SetBIP( math.max( 0, (tonumber( cfg.host ) or 1) - 1 ) ) end
		ipdata.Router = cfg.server
		return true
	end
	local p = PCMod.IPv4.ParseLan( cfg.ip )
	if (!p) then return false end
	local primary = PCMod.IPv4.ParseLan( ipdata.LAN )
	local owner = ipdata.Router
	// Same subnet means the same LAN answered under a new/replaced router:
	// take the lease as the primary again instead of pinning it as an extra.
	// Only a genuinely different LAN becomes a secondary address.
	local sameLan = primary && PCMod.IPv4.SameLan( ipdata.LAN, cfg.ip, ipdata.MaskBits or cfg.maskbits or 24 )
	local ownerGone = false
	if (owner && PCMod.Data) then
		local odata = PCMod.Data[ owner ]
		local oent = odata && odata.Ent
		if ((!odata) || (oent && oent.IsValid && (!oent:IsValid()))) then ownerGone = true end
	end
	if (primary && owner && (owner != cfg.server) && (!sameLan) && (!ownerGone)) then
		if (ent.AddExtraIP) then
			ent:AddExtraIP( cfg.ip, cfg.upbb or 0, cfg.lanid or 0, cfg.server )
		end
		return true
	end
	// Promote to primary. Drop a stale secondary with the same address left
	// behind by the earlier "different router" rule.
	if (ent.ReleaseExtraIP) then ent:ReleaseExtraIP( cfg.ip ) end
	if (cfg.netmask) then ipdata.Mask = cfg.netmask end
	if (cfg.maskbits) then ipdata.MaskBits = cfg.maskbits end
	if (cfg.gateway) then ipdata.Gateway = cfg.gateway end
	if (cfg.upbb != nil && ent.SetUpBB) then ent:SetUpBB( cfg.upbb ) end
	if (cfg.lanid != nil && ent.SetLanID) then ent:SetLanID( cfg.lanid ) end
	ent:SetSubnet( p.sub )
	ent:SetIP( p.add )
	// A private lease is the primary identity now; drop a backbone address the
	// machine carried from an earlier segment so overlays don't show both.
	if (ent.SetBSubnet) then ent:SetBSubnet( false ) end
	if (ent.SetBIP) then ent:SetBIP( false ) end
	ipdata.Router = cfg.server
	return true
end

// A router's WAN address: the lease carries the upstream backbone and the
// LAN /64 id it may use, but the same discover is used as any other host.
function PCMod.DHCPClient.ApplyRouter( ent, driver, cfg, port )
	if ((!ent) || (!cfg) || (!cfg.ip)) then return false end
	local ipdata = ent.Data && ent:Data() && ent:Data().IP
	if (!ipdata) then return false end
	// A LAN router keeps its own LAN identity; the lease only gives it a WAN
	// address, a backbone id and the /64 id its LAN should advertise.
	if (ent.SetBSubnet) then ent:SetBSubnet( cfg.bb ) end
	if (ent.SetBIP) then ent:SetBIP( math.max( 0, (tonumber( cfg.host ) or 1) - 1 ) ) end
	if (cfg.upbb && ent.SetUpBB) then ent:SetUpBB( cfg.upbb ) end
	if (ent.SetLanID) then ent:SetLanID( cfg.lanid or cfg.host or 0 ) end
	ipdata.Router = cfg.server
	if (driver && port) then
		driver.Uplink = ent:Ports()[ port ] or driver.Uplink
	end
	// Existing LAN clients were numbered under the old /64; renumber them.
	if (driver && driver.ReconfigureClients) then driver:ReconfigureClients() end
	// Advertise the new /64 immediately instead of waiting for the next hello.
	if (driver && PCMod.Routing && PCMod.Routing.Send) then PCMod.Routing.Send( driver, true ) end
	return true
end
