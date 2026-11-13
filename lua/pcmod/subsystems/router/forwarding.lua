// ---------------------------------------------------------------------------------------------------------
// router/forwarding.lua - Port forwarding, NAT ephemerals and outbound masquerading.
// Included by subsystems/router.lua; all functions extend SUBSYSTEM.
// ---------------------------------------------------------------------------------------------------------

function SUBSYSTEM:AddForward( wan, ip, port )
	local wanN = tonumber( wan )
	local portN = tonumber( port )
	if ((!wanN) || (!portN) || (wanN < 1) || (portN < 1)) then return false end
	if (!PCMod.IPv6.IsIP( ip )) then return false end
	local c = self:GetCfg()
	c.Forwards = c.Forwards or {}
	c.Forwards[ tostring( wanN ) ] = { ip = ip, port = portN }
	return true
end

function SUBSYSTEM:DeleteForward( wan )
	local c = self:GetCfg()
	c.Forwards = c.Forwards or {}
	c.Forwards[ tostring( wan ) ] = nil
end

function SUBSYSTEM:GetForwardRule( wanPort )
	local c = self:GetCfg()
	return c.Forwards && c.Forwards[ tostring( wanPort ) ]
end

// PAT (port-address translation) state: each active connection gets a stable
// ephemeral source port, so many hosts can share one public /32 or one
// forwarded port at the same time.
function SUBSYSTEM:AllocEph()
	self.NextEph = (self.NextEph or 40000) + 1
	if (self.NextEph > 64999) then self.NextEph = 40000 end
	return self.NextEph
end

// Forward-connection reply mapping, keyed by the ephemeral port the router
// presented to the internal host.
function SUBSYSTEM:RememberForwardFlow( eph, src, port, pub )
	self.ForwardFlows = self.ForwardFlows or {}
	self.ForwardFlows[ tostring( eph ) ] = { src = src, port = port, pub = pub, time = CurTime() }
	if (table.Count( self.ForwardFlows ) > 128) then
		local now = CurTime()
		for k, v in pairs( self.ForwardFlows ) do
			if (v.time < now - 120) then self.ForwardFlows[ k ] = nil end
		end
	end
end

function SUBSYSTEM:GetForwardFlow( port )
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
function SUBSYSTEM:RememberNatOut( eph, ip, port )
	self.NatOut = self.NatOut or {}
	self.NatOut[ tostring( eph ) ] = { ip = ip, port = port, time = CurTime() }
	if (table.Count( self.NatOut ) > 128) then
		local now = CurTime()
		for k, v in pairs( self.NatOut ) do
			if (v.time < now - 120) then self.NatOut[ k ] = nil end
		end
	end
end

function SUBSYSTEM:GetNatOut( port )
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
function SUBSYSTEM:MasqueradeAndForward( packet, pass )
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
