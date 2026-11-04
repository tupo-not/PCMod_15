
// Network Driver for PCMod 2

DRV = PCMod.DeriveDriver( "base" )

DRV.NiceName = "Generic Network Driver"
DRV.Name = "gen_network"
DRV.Type = "network"

DRV.PTData = {}
DRV.NetworkPort = 0

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
	if (self.NetworkPort == 0) then return end
	return self.Entity:SendPacket( self.NetworkPort, dest, port, body )
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