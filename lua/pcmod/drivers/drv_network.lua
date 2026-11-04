
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

function DRV:SendPacket( dest, port, body )
	// Loopback is accepted in IPv4 (127.0.0.1), IPv6 (::1) and hostname form.
	if (PCMod.IPv6.IsLoopback( dest )) then
		local pk = {}
		pk.Source = self:GetIP()
		pk.Dest = dest
		pk.Port = port
		pk.Body = body
		pk.Delivered = true
		self:PacketRecieved( pk )
		return
	end
	// Wireless uplink: when connected to a router, send through it over the air
	// instead of the cable port. Falls back to the cable when out of range.
	if (self:WirelessConnected()) then
		local src = self.Entity:GetFullIP() or self.Entity:GetFullBIP()
		self.WirelessEnt:DataRecieved( 0, { "sendpacket", { src, dest, port, body } } )
		return
	end
	if (self.NetworkPort == 0) then return end
	return self.Entity:SendPacket( self.NetworkPort, dest, port, body )
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

function DRV:GetIP()
	return self.Entity:GetIP()
end

function DRV:GetFullIP()
	return self.Entity:GetFullIP()
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