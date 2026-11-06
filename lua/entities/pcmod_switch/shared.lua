// ---------------------------------------------------------------------------------------------------------
// pcmod_switch
// Network switch entity - Ethernet or optical, forwards frames between its ports
// ---------------------------------------------------------------------------------------------------------

ENT.Type = "anim"
ENT.Base = "pcmod_base"
ENT.PrintName = "Switch"
ENT.Class = "pcmod_switch"

ENT.ItemModel = "models/props_lab/reciever01c.mdl"

ENT.IsSwitch = true

ENT.DefaultSetupData = {
	Mode = "ethernet",
}

ENT.PortCount = 8
ENT.PortTypes = {
	ethernet = "network",
	optic = "optic",
}

if (SERVER) then AddCSLuaFile( "shared.lua" ) end

// ---------------------------------------------------------------------------------------------------------
// MAC addresses
// ---------------------------------------------------------------------------------------------------------
// Switches are identified by a random base MAC and have one random MAC per port.
// They are generated once on spawn and persisted both by the duplicator
// (pcmod_base BuildDupeInfo / ApplyDupeInfo) and by map saves (OnSave /
// OnRestore), so a copied or saved world keeps the same addresses.
function ENT:GenerateMACs()
	local dt = self:Data()
	dt.MAC = PCMod.MAC.Random()
	dt.PortMACs = {}
	for i = 1, self.PortCount do
		dt.PortMACs[ i ] = PCMod.MAC.Random()
	end
	return dt
end

function ENT:GetPortMAC( port )
	local macs = self:Data().PortMACs
	if (!macs) then return nil end
	return macs[ port ]
end

function ENT:SetMACs( mac, portmacs )
	local dt = self:Data()
	if (PCMod.MAC.IsValid( mac )) then dt.MAC = PCMod.MAC.Normalize( mac ) end
	if (type( portmacs ) == "table") then dt.PortMACs = portmacs end
	self:UpdateData( dt )
	self:SetNWString( "MAC", dt.MAC )
end

// ---------------------------------------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------------------------------------

function ENT:Setup( setupdata )
	if (!setupdata) then setupdata = self.DefaultSetupData end
	local mode = setupdata.Mode
	if (!self.PortTypes[ mode ]) then mode = "ethernet" end

	local dt = self:Data()
	dt.Mode = mode
	dt.IsSwitch = true

	// Create the ports for the selected configuration.
	local pts = {}
	for i = 1, self.PortCount do
		table.insert( pts, self:CreatePort( self.PortTypes[ mode ] ) )
	end
	dt.Ports = pts

	// MACs are generated once. A restored entity keeps the ones saved in its
	// dupe info; Setup only fills in what is missing.
	local macs = dt.PortMACs
	if ((!PCMod.MAC.IsValid( dt.MAC )) || (type( macs ) != "table") || (#macs != self.PortCount)) then
		self:GenerateMACs()
	end
	for i = 1, self.PortCount do
		if (!PCMod.MAC.IsValid( dt.PortMACs[ i ] )) then dt.PortMACs[ i ] = PCMod.MAC.Random() end
	end

	self:SetNWString( "MAC", dt.MAC )
	self:UpdateData( dt )

	// Routers only understand point-to-point links, so the switch has to tell
	// them about the devices on its other ports when the topology changes.
	self:AddEHook( "ent", nil, "linked" )
	self:AddEHook( "ent", nil, "unlinked" )
end

// ---------------------------------------------------------------------------------------------------------
// Topology relay
// ---------------------------------------------------------------------------------------------------------
// A bridge is transparent to routers: when two devices are on the same switch
// segment they must be told about each other as if cabled directly. The switch
// sends synthetic "linked"/"unlinked" events carrying the far-side entity so
// the router driver can adopt it without losing the switch as the data path.

local function IsRouterClass( ent )
	if (!ent) then return false end
	local cls = ent.GetClass && ent:GetClass()
	return (cls == "pcmod_router") || (cls == "pcmod_brouter")
end

// Does a router of class `cls` care about a peer on the same segment?
local function RouterWantsPeer( ent, peer )
	if (!ent || !peer) then return false end
	local cls = ent.GetClass && ent:GetClass()
	local pc = peer.GetClass && peer:GetClass()
	if (cls == "pcmod_brouter") then
		return (pc == "pcmod_router") || (pc == "pcmod_brouter")
	elseif (cls == "pcmod_router") then
		return (pc == "pcmod_router") || (pc == "pcmod_brouter") || (peer.IsComputer == true)
	end
	return false
end

// Remember which port on each attached device faces the switch, so an unlink
// can still address that device after its own port table has been cleared.
function ENT:RefreshBridgePorts()
	self.BridgePeerPort = self.BridgePeerPort or {}
	for _, v in pairs( self:Ports() ) do
		local e = v.Connected && v.ConEnt
		if (e && e:IsValid() && e.Ports) then
			for pi, pp in pairs( e:Ports() ) do
				if (pp.ConEnt == self) then
					self.BridgePeerPort[ e:EntIndex() ] = pi
					break
				end
			end
		end
	end
end

// List the devices directly attached to this switch. The router driver uses
// this to resolve addresses of hosts that sit behind the switch.
function ENT:GetBridgePeers()
	local out = {}
	for k, v in pairs( self:Ports() ) do
		local e = v.Connected && v.ConEnt
		if (e && e:IsValid() && (!e.IsSwitch)) then
			out[#out + 1] = { Ent = e, Port = k }
		end
	end
	return out
end

function ENT:NotifyBridgeLinked()
	self:RefreshBridgePorts()
	local peers = {}
	for k, v in pairs( self:Ports() ) do
		local e = v.Connected && v.ConEnt
		if (e && e:IsValid() && !e.IsSwitch) then
			peers[#peers + 1] = { Ent = e }
		end
	end
	for _, a in ipairs( peers ) do
		local aPort = self.BridgePeerPort[ a.Ent:EntIndex() ]
		if (aPort && IsRouterClass( a.Ent )) then
			for _, b in ipairs( peers ) do
				if ((b.Ent != a.Ent) && RouterWantsPeer( a.Ent, b.Ent )) then
					a.Ent:FireEvent( { "linked", aPort, self, b.Ent } )
				end
			end
		end
	end
end

function ENT:NotifyBridgeUnlinked( removed )
	self.BridgePeerPort = self.BridgePeerPort or {}
	if ((!removed) || (!removed:IsValid())) then return end
	local removedPort = self.BridgePeerPort[ removed:EntIndex() ]
	for _, v in pairs( self:Ports() ) do
		local e = v.Connected && v.ConEnt
		if ((e) && (e:IsValid()) && (e != removed) && (!e.IsSwitch)) then
			local ePort = self.BridgePeerPort && self.BridgePeerPort[ e:EntIndex() ]
			if (ePort && IsRouterClass( e )) then
				e:FireEvent( { "unlinked", ePort, removed } )
			end
			if (removedPort && IsRouterClass( removed ) && RouterWantsPeer( removed, e )) then
				removed:FireEvent( { "unlinked", removedPort, e } )
			end
		end
	end
	self.BridgePeerPort[ removed:EntIndex() ] = nil
end

function ENT:CallEvent( data )
	if ((!data) || (!data.Event)) then return end
	if (data.Event == "linked") then
		self:NotifyBridgeLinked()
	elseif (data.Event == "unlinked") then
		self:NotifyBridgeUnlinked( data[ 2 ] )
	end
end

// ---------------------------------------------------------------------------------------------------------
// Bridge table
// ---------------------------------------------------------------------------------------------------------
// MacTable: learned MAC -> port. IPTable: IP -> MAC, used to give frames a
// unicast destination as soon as both ends have been seen.

function ENT:LearnMAC( mac, port, ip )
	mac = PCMod.MAC.Normalize( mac )
	if (!mac) then return end
	self.MacTable = self.MacTable or {}
	self.MacTable[ mac ] = port
	if (ip) then
		self.IPTable = self.IPTable or {}
		self.IPTable[ tostring( ip ) ] = mac
	end
end

function ENT:PortForMAC( mac )
	local norm = PCMod.MAC.Normalize( mac )
	if ((!norm) || (norm == PCMod.MAC.BROADCAST)) then return nil end
	return self.MacTable && self.MacTable[ norm ] or nil
end

// ---------------------------------------------------------------------------------------------------------
// Frame forwarding
// ---------------------------------------------------------------------------------------------------------
// A switch is transparent: it repeats frames to every other connected port, or
// only to the learned destination port. Loop protection uses the packet table
// as the identity for "deliver" frames, and a per-frame sequence number for raw
// "sendpacket" frames (which have no packet id yet).

function ENT:DataRecieved( port, data )
	if (!istable( data )) then return end
	local tag = data[ 1 ]
	local target = nil

	if (tag == "sendpacket") then
		// Loop check first: a frame returning round a ring must not relearn
		// the sender's MAC on the wrong port.
		local meta = data[ 3 ]
		if (!istable( meta )) then
			meta = {}
			data[ 3 ] = meta
		end
		if (!meta.switchframe) then
			PCMod.Network.NextSwitchFrame = (PCMod.Network.NextSwitchFrame or 0) + 1
			meta.switchframe = PCMod.Network.NextSwitchFrame
		end
		self.SwitchFrames = self.SwitchFrames or {}
		if (self.SwitchFrames[ meta.switchframe ]) then return end
		self.SwitchFrames[ meta.switchframe ] = true

		// Bound the seen table. Loops happen synchronously, so dropping old
		// entries cannot reintroduce one in the current flood.
		self.SwitchFrameCount = (self.SwitchFrameCount or 0) + 1
		if (self.SwitchFrameCount > 2048) then
			self.SwitchFrames = { [ meta.switchframe ] = true }
			self.SwitchFrameCount = 1
		end

		local body = data[ 2 ]
		local macs = data[ 4 ]
		if (!istable( macs )) then
			macs = {}
			data[ 4 ] = macs
		end
		if (!macs.SourceMAC) then
			macs.SourceMAC = self:GetPortMAC( port ) or self:GetMAC()
		end
		if (!macs.DestMAC) then
			macs.DestMAC = PCMod.MAC.BROADCAST
		end
		if (istable( body )) then
			self:LearnMAC( macs.SourceMAC, port, body[ 1 ] )
			local destMAC = self.IPTable && self.IPTable[ tostring( body[ 2 ] ) ]
			if (destMAC) then macs.DestMAC = destMAC end
		else
			self:LearnMAC( macs.SourceMAC, port )
		end
		target = self:PortForMAC( macs.DestMAC )
	elseif (tag == "deliver") then
		local pid = data[ 2 ]
		local packet = PCMod.Network.Packets && PCMod.Network.Packets[ pid ]
		if (!packet) then return end

		// Learn the sender and look up the destination from the packet MACs.
		self:LearnMAC( packet.SourceMAC, port, packet.Source )
		target = self:PortForMAC( packet.DestMAC )

		self.SwitchSeen = self.SwitchSeen or {}
		if (self.SwitchSeen[ pid ] == packet) then return end
		self.SwitchSeen[ pid ] = packet
	else
		return
	end

	for k, v in pairs( self:Ports() ) do
		if ((k != port) && ((!target) || (k == target))) then
			self:PushData( k, data )
		end
	end
end
