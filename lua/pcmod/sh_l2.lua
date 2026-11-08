// ---------------------------------------------------------------------------------------------------------
// sh_l2.lua - the pure L2 bridge algorithm
//
// A switch/modern only knows source MAC -> port. It learns from frames, floods
// unknown destinations and forwards known ones. It has no notion of IP,
// DHCP, routers or devices, which keeps the entity tiny and predictable.
// ---------------------------------------------------------------------------------------------------------

PCMod = PCMod or {}
PCMod.L2 = PCMod.L2 or {}

function PCMod.L2.Learn( ent, mac, port )
	mac = PCMod.MAC && PCMod.MAC.Normalize( mac )
	if ((!mac) || (mac == PCMod.MAC.BROADCAST)) then return end
	ent.MacTable = ent.MacTable or {}
	ent.MacTable[ mac ] = port
end

function PCMod.L2.PortForMAC( ent, mac )
	local norm = PCMod.MAC && PCMod.MAC.Normalize( mac )
	if ((!norm) || (norm == PCMod.MAC.BROADCAST)) then return nil end
	return ent.MacTable && ent.MacTable[ norm ] or nil
end

// Forward one frame. Returns nothing; the entity supplies ports/PushData/MACs.
function PCMod.L2.Receive( ent, port, data )
	if (!istable( data )) then return end
	local tag = data[ 1 ]
	local target = nil

	if (tag == "sendpacket") then
		local meta = data[ 3 ]
		if (!istable( meta )) then
			meta = {}
			data[ 3 ] = meta
		end
		if (!meta.switchframe) then
			PCMod.Network.NextSwitchFrame = (PCMod.Network.NextSwitchFrame or 0) + 1
			meta.switchframe = PCMod.Network.NextSwitchFrame
		end
		if (ent.SwitchFrames && ent.SwitchFrames[ meta.switchframe ]) then return end
		ent.SwitchFrames = ent.SwitchFrames or {}
		ent.SwitchFrames[ meta.switchframe ] = true
		ent.SwitchFrameCount = (ent.SwitchFrameCount or 0) + 1
		if (ent.SwitchFrameCount > 2048) then
			ent.SwitchFrames = { [ meta.switchframe ] = true }
			ent.SwitchFrameCount = 1
		end

		local macs = data[ 4 ]
		if (!istable( macs )) then
			macs = {}
			data[ 4 ] = macs
		end
		if (!macs.SourceMAC) then
			macs.SourceMAC = ent:GetPortMAC( port ) or ent:GetMAC()
		end
		if (!macs.DestMAC) then
			macs.DestMAC = PCMod.MAC.BROADCAST
		end
		PCMod.L2.Learn( ent, macs.SourceMAC, port )
		target = PCMod.L2.PortForMAC( ent, macs.DestMAC )
	elseif (tag == "deliver") then
		local pid = data[ 2 ]
		local packet = PCMod.Network.Packets && PCMod.Network.Packets[ pid ]
		if (!packet) then return end
		PCMod.L2.Learn( ent, packet.SourceMAC, port )
		target = PCMod.L2.PortForMAC( ent, packet.DestMAC )
		ent.SwitchSeen = ent.SwitchSeen or {}
		if (ent.SwitchSeen[ pid ] == packet) then return end
		ent.SwitchSeen[ pid ] = packet
	else
		return
	end

	for k, v in pairs( ent:Ports() ) do
		if ((k != port) && ((!target) || (k == target))) then
			ent:PushData( k, data )
		end
	end
end
