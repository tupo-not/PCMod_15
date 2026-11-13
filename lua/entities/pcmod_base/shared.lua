
// ---------------------------------------------------------------------------------------------------------
// pcmod_base
// Base entity file for all PCMod entities
// ---------------------------------------------------------------------------------------------------------

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "PCMod Entity"
ENT.Author = "[GU]thomasfn"
ENT.Category = "PCMod"
ENT.Class = "pcmod_base"

ENT.Spawnable = false
ENT.AdminSpawnable = false

if (SERVER) then

	AddCSLuaFile( "shared.lua" )
end

if (CLIENT) then

	ENT.RenderGroup = RENDERGROUP_OPAQUE

end



------------------|

	ENT.IsPCMod = true -- This entity belongs to the PCMod addon

	ENT.UseDelay = 1 -- Delay between use event fired (secs)
	ENT.NextUse = 0 -- Internal usage data

	ENT.IsScreen = false -- Does the entity have a screen?

	ENT.AlwaysOn = true -- Is the entity always on?

	ENT.ItemModel = "models/props_lab/harddrive01.mdl"

	// Reject the remover tool by default so a stray click cannot delete PCMod
	// devices. Right-click (which removes the entity AND everything constrained to
	// it) is blocked outright; single remove/reload needs Shift (IN_SPEED).
	function ENT:CanTool( ply, trace, mode, tool, button )
		if (mode != "remover") then return true end
		if (PCMod && PCMod.Cfg && (PCMod.Cfg.RemoverProtection == false)) then return true end
		if (button == 2) then
			if (SERVER) then
				PCMod.Notice( "PCMod device can't be removed with right-click (it would take the whole network)", ply )
			end
			return false
		end
		if (IsValid( ply ) && ply:KeyDown( IN_SPEED )) then return true end
		if (SERVER) then
			PCMod.Notice( "PCMod device is protected from the remover - hold Shift to remove it", ply )
		end
		return false
	end

------------------|

if (SERVER) then

	// Scripted entities do not get the engine's prop impact sounds.
	if (PCMod.AddPropImpactSounds) then PCMod.AddPropImpactSounds( ENT ) end

	-------------------------------------------------------------------------------------------------------------------------------------------------
	-- Setup Functions --
	-------------------------------------------------------------------------------------------------------------------------------------------------

		function ENT:Initialize()
		
			// Setup all our physics stuff
			self:ChangeModel( self.ItemModel )
			
			// Clear out all GVars
			self:ClearGVars()
			
			PCMod.Msg( "Creating entity derived from pcmod_base...", true )

			self:SetNWString( "IP", "" )
			self:SetNWString( "IP.WAN", "" )

			// Set up a slot for us in the PCMod Data table
			self:CreateSlotData()

			// Network hardware gets an identity MAC on spawn. It is persisted by
			// BuildDupeInfo so a world save/load keeps the same address.
			if (self.IsComputer || self.IsNetworkDevice || self.IsSwitch) then
				self:EnsureMAC()
			end
			
			// self:Setup()
			
			if (self.AlwaysOn) then self:TurnOn() end
			if (!self.AlwaysOn) then self:TurnOff() end
			
			if (self.IsScreen) then
				self:SetGVar( "mouse_enable", 0 )
			end
			
		end
		
		function ENT:OnRemove()
			local ent = self.Entity
			PCMod.Msg( "Start OnRemove", true )
			if (ent.IsComputer) then
				PCMod.Msg( "Properly close programs", true )
				ent:CloseAllPrograms()
			end
			PCMod.Msg( "Unlink ports", true )
			for k, _ in pairs(ent:Ports() or {}) do
				PCMod.Wiring.UnlinkPort( ent, k )
			end
			PCMod.Msg( "Ports unlinked, now for subsystems", true )
			local dat = PCMod.Data[ self:EntIndex() ]
			local subs = dat && PCMod.GetSubsystemStore( dat, false )
			if (subs) then
				for k, _ in pairs(subs) do
					subs[ k ]:OnRemove()
				end
			end
			PCMod.Msg( "Data!", true )
			// Round 19 (AUDIT2 A-02): the data slot is keyed by entity index, not by
			// array position - table.remove() inside pairs() removed nothing (or the
			// wrong entry), so slots leaked and a recycled entity index could inherit
			// stale data. Drop the slot by its key.
			PCMod.Data[ ent:EntIndex() ] = nil
			PCMod.Msg( "RunOnRemove!", true )
			ent:RunOnRemove()
			PCMod.Msg( "Unlinked all ports and deleted Data slot for entity "..ent:EntIndex()..", removing entity...", true )
		end
		
		function ENT:Setup( setupdata )
			-- Override Compatibility
			-- Note that this will be called after our entity has been created
			-- Setupdata will contain information from the toolgun needed to spawn the entity
		end

		function ENT:ForceRemove( error )
			if (error) then
				PCMod.Notice( error, self:GetOwner() )
			end

			self:Remove()
		end
		
		function ENT:RunOnRemove()
			//Override for compatability
		end
		
		function ENT:CreateSlotData()
			local tmp = {}
			tmp.ItemType = self:GetClass()
			tmp.PortData = self.Ports
			tmp.ItemModel = self.ItemModel
			tmp.Ent = self
			tmp.IP = {}
			// Every interface address is one plain dotted-quad IPv4 string.
			// LAN is a private RFC1918 address; WAN is a backbone address.
			// address of a router. PCs normally only have LAN.
			tmp.IP.LAN = false
			tmp.IP.WAN = false
			// Decomposition of WAN used internally for routing/IPv6.
			tmp.IP.WanBB = false
			tmp.IP.WanHost = false
			tmp.IP.V6 = false
			tmp.IP.V6Prefix = false
			tmp.IP.V6Link = false
			tmp.IP.WanV6 = false
			tmp.IP.WanV6Prefix = false
			tmp.IP.WanV6Link = false
			// EntIndex of the router that handed out the primary DHCP lease.
			tmp.IP.Router = false
			// Secondary LAN addresses: leases from other routers this device is
			// also linked to. Each entry is { IPv4 = "10.20.0.5", Router = ... }.
			tmp.IP.Extra = {}
			tmp.Memory = {}
			tmp.Ports = {}
			tmp.HardDrive = {}
			// New name for the per-entity hardware services.
			tmp.Subsystems = {}
			tmp.EHooks = {}
			tmp.ScreenSpace = PCMod.MakeScreenSpace()
			tmp.IsOn = false
			tmp.OS_FirstRun = true
			tmp.Password = ""
			PCMod.Data[ self:EntIndex() ] = tmp
		end


	-------------------------------------------------------------------------------------------------------------------------------------------------
	-- OS Functions --
	-------------------------------------------------------------------------------------------------------------------------------------------------		
	

		function ENT:InstallOS( osname )
			local osd = PCMod.OSys[ osname ]
			if (!osd) then return false end
			PCMod.Data[ self:EntIndex() ].OS = table.Copy( osd )
			PCMod.Data[ self:EntIndex() ].OS:Initialize( self )
		end
		
		function ENT:GetOS()
			return PCMod.Data[ self:EntIndex() ].OS
		end
	
		function ENT:CloseAllPrograms()
			local bios = PCMod.GetSubsystem && PCMod.GetSubsystem( self:Data(), "bios" )
			if(PCMod.Data[ self:EntIndex() ] && PCMod.Data[ self:EntIndex() ].OS) then
				PCMod.Data[ self:EntIndex() ].OS:ShutDown()
			elseif(bios && bios.OS) then
				bios.OS:ShutDown()
			else
				// No OS instance (never booted / already cleared) - there are no
				// programs to close, so this is a normal state, not a warning.
				PCMod.Msg( "CloseAllPrograms: no OS instance, nothing to close", true )
			end
		end
		
	-------------------------------------------------------------------------------------------------------------------------------------------------
	-- Port Functions --
	-------------------------------------------------------------------------------------------------------------------------------------------------
	

		function ENT:CreatePort( ptype )
			local tmp = {}
			tmp.Type = ptype
			tmp.Name = PCMod.Wiring.TypeToName( ptype )
			tmp.CanWireSameType = PCMod.Wiring.CanWireSameType( ptype )
			tmp.Connected = false
			tmp.ConEnt = nil
			tmp.RemotePort = 0
			return tmp
		end
		
		function ENT:UpdatePort( pid, data )
			local dt = self:Data()
			dt.Ports[ pid ] = data
			self:UpdateData( dt )
		end
		
		// Return Code
		// 0 = success
		// 1 = invalid port
		// 2 = no connection
	
		function ENT:GivenData( portid, data )
			// Called from another entity, that is giving us data through one of our ports
			local prt = self:Ports()[ portid ]
			if (!prt) then return 1 end
			self:DataRecieved( portid, data )
			// This is causing problems when entities are recieved data that aren't packets
			if ((prt.Type == "network") || (prt.Type == "optic")) then
				local packet = data[2]
				local pid
				if (type( packet ) == "number") then
					// If we just have a PID, get the packet itself
					pid = packet
					packet = PCMod.Network.Packets[ pid ]
					if (!PCMod.Network.Packets[ pid ]) then packet = nil end
				end
				if (!packet) then
					PCMod.Msg( "Invalid packet! (" .. self.Entity:EntIndex() .. ")", true )
					return 0
				end
				// Round 34 (M-51): packet.Source is not always a string - the
				// concatenation raised an error for a table
				PCMod.Msg( "Got packet containing the source " .. tostring( packet.Source ) .. " (" .. self:GetClass() .. ":"..self:EntIndex() .. ")", true )
				if (self:IsAddressedTo( packet.Dest )) then
					PCMod.Msg( "This packet was directed at us! Port: " .. packet.Port, true )

					PCMod.Network.Packets[ pid ].Delivered = true
					packet.ViaWireless = false
					
					// Forward data to the network subsystem.
					if (self.IsComputer) then
						local net = PCMod.GetSubsystem && PCMod.GetSubsystem( self:Data(), "network" )
						if (net) then net:PacketRecieved( packet ) end
					end
				else
					// Are we a router? If so forward it to the router subsystem.
					if (self.IsNetworkDevice) then
						local rtr = PCMod.GetSubsystem && PCMod.GetSubsystem( self:Data(), "router" )
						if (rtr) then rtr:DataRecieved( packet ) end
					end
				end
			end
			return 0
		end
		
		function ENT:DataRecieved( port, data )
			-- Override Compatibility
		end
		
		function ENT:PushData( port, data )
			// Called from us, sends data through the port to our peer
			local portid = (type( port ) == "number") and port or nil
			if (type( port ) == "number") then port = self:Ports()[ port ] end
			if (!port) then return 1 end
			if (!port.Connected) then return 2 end
			// Packet tracing (pcmod_debug_packets 1): log each network/fibre
			// transmission with the packet's source/destination and first 5
			// body fields. New frames carry their own addresses; forwarded
			// packets are looked up by pid.
			if (SERVER && PCMod.Network && PCMod.Network.LogPacket &&
				((port.Type == "network") || (port.Type == "optic"))) then
				local atIp = (self.GetFullIP && self:GetFullIP()) or (self.GetFullBIP && self:GetFullBIP()) or "?"
				local out = "at " .. tostring( atIp ) .. " out " .. self:GetClass() .. ":" .. tostring( portid or "?" )
				if (data && (data[ 1 ] == "sendpacket")) then
					local frame = data[ 2 ]
					PCMod.Network.LogPacket( "send", frame && frame[ 1 ], frame && frame[ 2 ],
						frame && frame[ 3 ], frame && frame[ 4 ], out )
				elseif (data && (data[ 1 ] == "deliver") && data[ 2 ]) then
					local pkt = PCMod.Network.Packets[ data[ 2 ] ]
					if (pkt) then
						PCMod.Network.LogPacket( "hop", pkt.Source, pkt.Dest, pkt.Port, pkt.Body,
							"pid=" .. tostring( data[ 2 ] ) .. " ttl=" .. tostring( pkt.TTL ) .. " " .. out )
					end
				end
			end
			local ent = port.ConEnt
			if ((ent) && (ent:IsValid())) then
				local remote = port.RemotePort
				local function deliver()
					if ((ent) && (ent:IsValid())) then ent:GivenData( remote, data ) end
				end
				// Emulate the delay of crossing this physical link. The port
				// type picks the link profile (fibre or Ethernet); non-network
				// ports are delivered immediately.
				local kind = PCMod.Latency && PCMod.Latency.KindForPort && PCMod.Latency.KindForPort( port )
				if (kind && PCMod.Latency.Deliver) then
					PCMod.Latency.Deliver( deliver, kind )
				else
					deliver()
				end
				return 0
			end
			return 2
		end
		
		function ENT:FullPushData( data, filter )
			// Called from us, sends a global message through every port
			for k, v in pairs( self:Ports() ) do
				if ((!filter) || ((filter) && (filter == v.Type))) then
					self:PushData( k, data )
				end
			end
		end
		
		function ENT:Ports()
			return (self:Data().Ports)
		end
	
	
	-------------------------------------------------------------------------------------------------------------------------------------------------
	-- Basic Entity Functions --
	-------------------------------------------------------------------------------------------------------------------------------------------------
	
	
		function ENT:Think()
			// The data slot can disappear (a core reload rebuilds PCMod.Data);
			// bail out instead of erroring every tick.
			if (!PCMod.Data[ self:EntIndex() ]) then return end
			local subs = PCMod.GetSubsystemStore( PCMod.Data[ self:EntIndex() ], false )
			for _, v in pairs( subs or {} ) do
				v:Think()
			end
			self.harddrive = self:Data().HardDrive -- Duplicator support
			self:CustomThink()
		end
		
		function ENT:CustomThink()
			// Override compatability
		end
		
		function ENT:Use( activator, caller )
			if (CurTime()<self.NextUse) then return end
			self.NextUse = CurTime() + self.UseDelay
			self:FireEvent( { "use", activator } )
		end
		
		function ENT:TurnOn()
			if (self:Data().IsOn) then return end
			PCMod.Msg( "Turning device on! (" .. tostring( self:EntIndex() ) .. ")", true )
			PCMod.Data[ self:EntIndex() ].IsOn = true
			self:ClearMemory()
			self:FireEvent( { "turnon" } )
			self:SetNWInt( "device_on", true )
		end
		 
		function ENT:TurnOff()
			if (!self:Data().IsOn) then return end
			if (self.AlwaysOn) then return end
			PCMod.Msg( "Turning device off! (" .. tostring( self:EntIndex() ) .. ")", true )
			PCMod.Data[ self:EntIndex() ].IsOn = false
			self:FireEvent( { "turnoff" } )
			if (self.IsComputer) then
				self:CloseAllPrograms()
			end
			self:ClearMemory()
			self:SetNWInt( "device_on", false )
		end
		
		function ENT:SetPlayer( ply )
			PCMod.Data[ self:EntIndex() ].Owner = ply
		end
		
		function ENT:GetOwner()
			return PCMod.Data[ self:EntIndex() ].Owner
		end
		
		function ENT:ChangeModel( mdl )
			self.Entity:SetModel( mdl )
			self.Entity:PhysicsInit(SOLID_VPHYSICS)
			self.Entity:SetMoveType(MOVETYPE_VPHYSICS)
			self.Entity:SetSolid(SOLID_VPHYSICS)
			local phys = self.Entity:GetPhysicsObject()
			if ((phys) && (phys:IsValid())) then phys:Wake() end
		end
		
		
	-------------------------------------------------------------------------------------------------------------------------------------------------
	-- Networking Functions --
	-------------------------------------------------------------------------------------------------------------------------------------------------

	
		include( "entities/pcmod_base/netidentity.lua" )

	
		function ENT:Data()
			local dt = PCMod.Data[ self:EntIndex() ]
			if (!dt) then
				PCMod.Warning( "Entity has no data slot! (" .. tostring( self:EntIndex() ) .. ")" )
				dt = {}
			end
			return (dt)
		end
		
		function ENT:Memory()
			return (self:Data().Memory)
		end
		
		function ENT:UpdateData( newdata )
			PCMod.Data[ self:EntIndex() ] = newdata
		end
		
		function ENT:UpdateMemory( newmem )
			PCMod.Data[ self:EntIndex() ].Memory = newmem
		end
		
		function ENT:ClearMemory()
			self:UpdateMemory( {} )
		end
		
		
	-------------------------------------------------------------------------------------------------------------------------------------------------
	-- Subsystem Functions --
	-------------------------------------------------------------------------------------------------------------------------------------------------
	
	
		function ENT:InstallSubsystem( name )
			local key = PCMod.ResolveSubsystemName( name ) or name
			local proto = PCMod.Subsystems && PCMod.Subsystems[ key ]
			if (!proto) then
				PCMod.Msg( "No such subsystem '" .. tostring( name ) .. "'!", true )
				return
			end
			local inst = table.Copy( proto )
			inst.Entity = self
			local store = PCMod.GetSubsystemStore( self:Data(), true )
			if (!store) then return end
			store[ key ] = inst
			inst:Initialize()
			PCMod.Msg( "Installing subsystem '" .. key .. "' to (" .. tostring( self:EntIndex() ) .. ")", true )
			return inst
		end

		function ENT:PushSubsystemData( name, port, data )
			local sub = PCMod.GetSubsystem( self:Data(), name )
			if (!sub) then return end
			sub:DataRecieved( port, data )
		end

		function ENT:CallSubsystem( name, func, ... )
			local sub = PCMod.GetSubsystem( self:Data(), name )
			if (!sub) then return end
			return sub[ func ]( sub, ... )
		end
		
	
	-------------------------------------------------------------------------------------------------------------------------------------------------
	-- File Functions --
	-------------------------------------------------------------------------------------------------------------------------------------------------
	
		include( "entities/pcmod_base/filesystem.lua" )

	
	-------------------------------------------------------------------------------------------------------------------------------------------------
	-- Event Handling Functions --
	-------------------------------------------------------------------------------------------------------------------------------------------------
	
	
		function ENT:AddEHook( target, id, event )
			local hk = {}
				hk.Target = target
				hk.ID = id
				hk.Event = event
			table.insert( PCMod.Data[ self:EntIndex() ].EHooks, hk )
			PCMod.Msg( "Adding EHook: " .. target .. ", " .. tostring(id) .. ", " .. event, true )
		end
	
		function ENT:FireEvent( event )
			if (!event) then return end
			if (!event[1]) then return end
			if (!PCMod.Data[ self:EntIndex() ]) then return end -- No data slot, hooks cannot run
			local ename = event[1]
			table.remove( event, 1 )
			local edata = event
			self:CustomFire( ename, edata )
			// edata[1] is likely to be a player, or activator
			PCMod.Msg( "Entity " .. tostring( self:EntIndex() ) .. " reported event '" .. ename .. "'", true )
			for _, v in pairs( PCMod.Data[ self:EntIndex() ].EHooks ) do
				if (v.Event == ename) then
					// Call the hook
					self:CallHook( v, event )
				end
			end
		end
		
		function ENT:CustomFire( ename, edata )
			if (ename == "toggleon") then
				PCMod.Msg( "Toggleon hook called (CustomFire[ename,edata])", true )
				if (self:Data().IsOn) then self:TurnOff() return end
				self:TurnOn()
			end
		end
		
		function ENT:CallHook( hk, data )
			PCMod.Msg( "Calling hook! (" .. hk.Event .. ")", true )
			if (!data) then data = {} end
			data.Event = hk.Event
			if (hk.Target == "subsystem") then
				local sub = PCMod.GetSubsystem( self:Data(), hk.ID )
				if (!sub) then return end
				PCMod.Msg( "Calling subsystem hook!", true )
				sub:CallEvent( data )
			end
			if (hk.Target == "ent") then
				PCMod.Msg( "Calling entity hook!", true )
				self:CallEvent( data )
			end
			if (hk.Target == "patch") then
				PCMod.Msg( "Calling patch hook!", true )
				self:FireEvent( { hk.ID, data } )
			end
		end
		
		function ENT:CallEvent( data )
			-- Override Compatibility
		end
		
		function ENT:DoCommand( pl, com, args )
			-- Override Compatibility
		end
		
		
	-------------------------------------------------------------------------------------------------------------------------------------------------
	-- ScreenSpace Functions --
	-------------------------------------------------------------------------------------------------------------------------------------------------
	
	
		function ENT:ScreenSpace()
			return (self:Data().ScreenSpace)
		end
		
		function ENT:UpdateScreenSpace( ss )
			PCMod.Data[ self:EntIndex() ].ScreenSpace = ss
			self:InvalidateScreenSpace()
		end
		
		function ENT:InvalidateScreenSpace()
			for _, v in pairs( player.GetAll() ) do
				if (!v.SSBeam) then v.SSBeam = {} end
				v.SSBeam[ self:EntIndex() ] = false
			end
			self:FireEvent( { "ss_inval" } )
			if (self.IsScreen) then	PCMod.Beam.BeamEntSS( self, PCMod.Beam.Range_SS ) end
		end
		
	-------------------------------------------------------------------------------------------------------------------------------------------------
	-- Misc Functions --
	-------------------------------------------------------------------------------------------------------------------------------------------------
		
		function ENT:EnsureMAC()
			local dt = self:Data()
			if (!PCMod.MAC.IsValid( dt.MAC )) then
				dt.MAC = PCMod.MAC.Random()
				self:UpdateData( dt )
			end
			return dt.MAC
		end

		function ENT:GetMAC()
			return self:EnsureMAC()
		end

		// Ports that carry an L2 hardware address (Ethernet/fibre). The Wi-Fi
		// interface is port 0 and is handled separately.
		function ENT:NetworkInterfacePorts()
			local out = {}
			local ports = (self.Ports && self:Ports()) or {}
			for k, v in pairs( ports ) do
				if ((v.Type == "network") || (v.Type == "optic")) then out[ #out + 1 ] = k end
			end
			table.sort( out )
			return out
		end

		// Every interface gets its own hardware address. The lowest wired port
		// keeps the entity's primary MAC so existing single-NIC saves and leases
		// stay stable; all other ports get a fresh address. Wi-Fi (port 0) is
		// distinct from every cable, so it never shares a DHCP lease with one.
		function ENT:EnsureInterfaceMAC( port )
			local dt = self:Data()
			if (port == nil) then return self:EnsureMAC() end
			dt.InterfaceMACs = dt.InterfaceMACs or {}
			local mac = dt.InterfaceMACs[ port ]
			if (PCMod.MAC.IsValid( mac )) then return mac end
			local wired = self:NetworkInterfacePorts()
			local lowest = wired[ 1 ]
			local primaryMAC = dt.MAC
			local primaryUsed = false
			for _, m in pairs( dt.InterfaceMACs ) do
				if (m == primaryMAC) then primaryUsed = true end
			end
			if (PCMod.MAC.IsValid( primaryMAC ) && (!primaryUsed) &&
				(((lowest != nil) && (port == lowest)) || ((lowest == nil) && (port == 0)))) then
				mac = primaryMAC
			else
				mac = PCMod.MAC.Random()
			end
			dt.InterfaceMACs[ port ] = mac
			self:UpdateData( dt )
			return mac
		end

		function ENT:GetInterfaceMAC( port )
			return self:EnsureInterfaceMAC( port )
		end

		function ENT:GetInterfaceMACs()
			local dt = self:Data()
			return dt.InterfaceMACs or {}
		end

		// Give this entity a fresh hardware identity. Switches also regenerate
		// their per-port MACs. Used on spawn and when a duplicator clones an
		// entity, so two copies never share an address on the same segment.
		function ENT:RandomizeIdentity()
			if (!PCMod.MAC) then return end
			local dt = self:Data()
			if (self.IsSwitch && self.GenerateMACs) then
				dt = self:GenerateMACs()
			elseif (self.IsComputer || self.IsNetworkDevice) then
				dt.MAC = PCMod.MAC.Random()
				dt.InterfaceMACs = nil
			else
				return
			end
			self:UpdateData( dt )
			if (dt.MAC && self.SetNWString) then self:SetNWString( "MAC", dt.MAC ) end
		end

		function ENT:SetMAC( mac )
			local norm = PCMod.MAC.Normalize( mac )
			if (!norm) then return false end
			local dt = self:Data()
			local old = dt.MAC
			dt.MAC = norm
			// The interface that used the primary MAC follows the new one, so
			// changing the primary address from the control panel takes effect
			// without disturbing the other NICs' addresses.
			if (istable( dt.InterfaceMACs )) then
				local replaced = false
				for k, v in pairs( dt.InterfaceMACs ) do
					if (v == old) then dt.InterfaceMACs[ k ] = norm; replaced = true end
				end
				if ((!replaced) && (norm)) then
					local wired = self:NetworkInterfacePorts()
					if (wired[ 1 ] != nil) then dt.InterfaceMACs[ wired[ 1 ] ] = norm end
				end
			end
			self:UpdateData( dt )
			self:SetNWString( "MAC", norm )
			return true
		end

		// Plain map saves (save/load) use these hooks rather than the
		// duplicator ones, so a switch keeps its address across a world save.
		function ENT:OnSave()
			local dt = self:Data()
			local tmp = {}
			if (PCMod.MAC.IsValid( dt.MAC )) then tmp.mac = dt.MAC end
			if (istable( dt.InterfaceMACs )) then tmp.ifacemacs = dt.InterfaceMACs end
			if (self.IsSwitch) then tmp.portmacs = dt.PortMACs end
			// Computer addressing (static IPv4, netmask, gateway) and login.
			// Only the configured identity is saved; DHCP addresses are re-leased
			// after a load so they cannot conflict with the restored network.
			if (self.IsComputer && istable( dt.IP )) then
				tmp.ip = {
					Static = dt.IP.Static,
					Mask = dt.IP.Mask,
					MaskBits = dt.IP.MaskBits,
					Gateway = dt.IP.Gateway,
				}
			end
			if (self.IsComputer && (dt.Password != nil)) then tmp.password = dt.Password end
			// Router configuration (LAN size, DHCP pool, NAT, forwards).
			if (self.IsNetworkDevice && istable( dt.RouterCfg )) then tmp.routercfg = dt.RouterCfg end
			return tmp
		end

		function ENT:OnRestore( data )
			if (!istable( data )) then return end
			local dt = self:Data()
			if (data.mac && PCMod.MAC.IsValid( data.mac )) then
				dt.MAC = PCMod.MAC.Normalize( data.mac )
			end
			if (istable( data.ifacemacs )) then
				dt.InterfaceMACs = {}
				for k, v in pairs( data.ifacemacs ) do
					if (PCMod.MAC.IsValid( v )) then dt.InterfaceMACs[ k ] = PCMod.MAC.Normalize( v ) end
				end
			end
			if (self.IsSwitch && istable( data.portmacs )) then
				dt.PortMACs = data.portmacs
			end
			if (self.IsComputer && istable( data.ip )) then
				-- Restore the configured identity; a static address is re-applied,
				-- otherwise the router hands out a fresh DHCP lease on relink.
				dt.IP = dt.IP or {}
				dt.IP.Static = data.ip.Static
				dt.IP.Mask = data.ip.Mask
				dt.IP.MaskBits = data.ip.MaskBits
				dt.IP.Gateway = data.ip.Gateway
				if (data.ip.Static && self.SetStaticIP) then
					self:SetStaticIP( data.ip.Static )
				end
			end
			if (self.IsComputer && (data.password != nil)) then
				dt.Password = data.password
			end
			if (self.IsNetworkDevice && istable( data.routercfg )) then
				dt.RouterCfg = data.routercfg
			end
			self:UpdateData( dt )
			if (dt.MAC && self.SetNWString) then
				self:SetNWString( "MAC", dt.MAC )
			end
			if (self.IsComputer && self.SetIPText) then
				self:SetIPText()
			end
			// Re-apply the restored LAN addressing (gateway on the configured
			// network) once the router subsystem exists.
			if (self.IsNetworkDevice) then
				local rdrv = PCMod.GetSubsystem && PCMod.GetSubsystem( dt, "router" )
				if (rdrv && rdrv.ApplyLanAddress) then rdrv:ApplyLanAddress() end
				// The saved RouterCfg owns the Wi-Fi state; republish it so the
				// overlay matches the restored web-panel setting.
				if (rdrv && rdrv.SyncWirelessOverlay) then rdrv:SyncWirelessOverlay() end
			end
		end

		function ENT:SetGVar( key, val )
			local id = self:EntIndex()
			PCMod.Beam.SetEntData( id, key, val )
		end
		
		function ENT:ClearGVars()
			PCMod.Beam.ClearEntData( self:EntIndex())
		end
		
		// Garry's duplicator calls this on the freshly created copy, before its
		// entity modifiers are applied. A cloned network device must not share
		// the original's MAC (two laptops on one switch would fight over the
		// same hardware address), so give the copy a fresh identity here.
		function ENT:OnDuplicated()
			self.IsPCModClone = true
			self:RandomizeIdentity()
		end

		function ENT:BuildDupeInfo()
			PCMod.Msg( "==> BUILDING DUPE INFO <==", true )
			local dt = self:Data()
			local tmp = {}
			tmp.harddrive = PCMod.TableToString( dt.HardDrive or {} )
			tmp.ison = (dt.IsOn == true)
			if (self.IsComputer) then
				// Only the configured identity travels with a dupe. A DHCP
				// address is a lease owned by a live router, so copying it
				// would make the duplicate reuse the original's address (and
				// its lease ownership). The pasted PC re-leases on relink.
				tmp.ip = {
					Static = dt.IP && dt.IP.Static,
					Mask = dt.IP && dt.IP.Mask,
					MaskBits = dt.IP && dt.IP.MaskBits,
					Gateway = dt.IP && dt.IP.Gateway,
				}
				tmp.password = dt.Password or ""
			end
			if (self.IsNetworkDevice) then
				tmp.routercfg = dt.RouterCfg
				tmp.wirepass = dt.WirePass
				tmp.iswireless = dt.IsWireless
			end
			if (PCMod.MAC.IsValid( dt.MAC )) then
				tmp.mac = dt.MAC
			end
			if (self.IsSwitch) then
				tmp.portmacs = dt.PortMACs
			end
			// Save the logical port links so they can be re-established on paste
			// (the physical ropes are restored by the duplicator itself).
			local links = {}
			for i, p in pairs( dt.Ports or {} ) do
				if (p.Connected && p.ConEnt && p.ConEnt:IsValid() && p.ConEnt.IsPCMod) then
					table.insert( links, { port = i, peer = p.ConEnt:EntIndex(), remote = p.RemotePort } )
				end
			end
			if (#links > 0) then tmp.links = links end
			return tmp
		end

		function ENT:ApplyDupeInfo( ply, ent, info, GetEntByID )
			PCMod.Msg( "==> APPLYING DUPE INFO <==", true )
			if (!info) then return end
			local dt = self:Data()
			if (info.harddrive) then
				dt.HardDrive = PCMod.StringToTable( info.harddrive ) or {}
			end
			if (self.IsComputer) then
				if (istable( info.ip )) then
					// Rebuild the address from the configured identity instead
					// of adopting the copied lease table: a static address is
					// re-applied, a DHCP client starts empty and re-leases on
					// relink.
					local src = info.ip
					local ipdata = dt.IP or {}
					dt.IP = ipdata
					ipdata.Mask = src.Mask
					ipdata.MaskBits = src.MaskBits
					ipdata.Gateway = src.Gateway
					if (src.Static) then
						ipdata.Extra = {}
						ipdata.Router = false
						ipdata.Static = src.Static
						if (self.SetStaticIP) then self:SetStaticIP( src.Static ) end
					else
						ipdata.Static = false
						ipdata.Router = false
						ipdata.Extra = {}
						if (self.SetLanAddress) then self:SetLanAddress( false ) end
					end
					self:UpdateData( dt )
				end
				if (info.password ~= nil) then dt.Password = info.password end
			end
			if (self.IsNetworkDevice) then
				if (info.routercfg) then dt.RouterCfg = info.routercfg end
				if (info.wirepass ~= nil) then dt.WirePass = info.wirepass end
				if (info.iswireless ~= nil) then dt.IsWireless = info.iswireless end
			end
			// A pasted entity is a clone, so it keeps the fresh identity that
			// OnDuplicated assigned instead of adopting the source's MAC (and a
			// switch does not adopt its source's per-port MACs either). Paste
			// paths that skip OnDuplicated get a fresh identity here too. World
			// saves still keep their MAC through OnSave/OnRestore.
			if (!self.IsPCModClone) then self:RandomizeIdentity() end
			self:UpdateData( dt )
			if (dt.MAC && self.SetNWString) then
				self:SetNWString( "MAC", dt.MAC )
			end

			// Re-sync the network address strings (and IPv6 meta) from the IP.
			if (self.IsComputer) then
				self:SetIPText()
				self:SetBIPText()
			end

			// Push the restored wireless flag into the router subsystem.
			if (self.IsNetworkDevice) then
				local rdrv = PCMod.GetSubsystem && PCMod.GetSubsystem( dt, "router" )
				if (rdrv && rdrv.SetWireless && (dt.IsWireless != nil)) then
					rdrv:SetWireless( dt.IsWireless == true )
				end
				// Move the restored gateway onto the configured LAN network.
				if (rdrv && rdrv.ApplyLanAddress) then rdrv:ApplyLanAddress() end
			end

			// Boot the computer back up if it was running when saved.
			if (self.IsComputer && info.ison) then
				dt.IsOn = false
				self:UpdateData( dt )
				self:TurnOn()
			end

			// Re-establish logical port links (the physical ropes are already
			// restored by the duplicator). We re-wire the ConEnt/RemotePort
			// bookkeeping and fire the "linked" events so routers and PCs rebuild
			// their network relationships against the new entities.
			if (info.links && GetEntByID && PCMod.Wiring && PCMod.Wiring.LinkPorts) then
				for _, link in ipairs( info.links ) do
					local peer = GetEntByID( link.peer )
					if (peer && peer:IsValid() && peer.IsPCMod) then
						PCMod.Wiring.LinkPorts( self, link.port, peer, link.remote, nil )
					end
				end
			end

			// Duplicator reads this field from the entity.
			self.harddrive = dt.HardDrive
		end
		
		function ENT:PreEntityCopy()
			// Build the DupeInfo table and save it as an entity mod
			local DupeInfo = self:BuildDupeInfo()
			if (DupeInfo) then
				duplicator.StoreEntityModifier( self.Entity, "PCModDupeInfo", DupeInfo )
			end
		end

		function ENT:PostEntityPaste( ply, ent, CreatedEntities )
			// Apply the DupeInfo
			if ((ent.EntityMods) && (ent.EntityMods.PCModDupeInfo)) then
				ent:ApplyDupeInfo( ply, ent, ent.EntityMods.PCModDupeInfo, function(id) return CreatedEntities[id] end )
			end
		end

end

if (CLIENT) then

	function ENT:GetGVar( key )
		return PCMod.Beam.GetEntData( self:EntIndex(), key )
	end
	
	function ENT:Draw()
	
		// See if the PCMod library exists or not
		if (!PCMod_IsValid()) then
			// Check if we have attempted to kick start
			if (_G.PCMod_Kicked) then
				// No luck, draw and finish
				self.Entity:DrawModel()
				return
			end
			
			// Try to kick start
			Msg( "\n", "==== {WARNING} ====", "\n" )
			ErrorNoHalt( "PCMod 2 libraries not loaded (CL)! About to kick start!" )
			_G.PCMod_Kicked = true
			
			// Kick start
			PCMod_KickStart()
			
			// Determine if we are successful or not
			if (PCMod_IsValid()) then
				ErrorNoHalt( "PCMod 2 was kick-started successfully!" )
				self.Entity:DrawModel()
				return
			end
			
			// Unsuccessful!
			ErrorNoHalt( "PCMod 2 FAILED to kick-start! Please post your console log on the forums." )
			self.Entity:DrawModel()
			return
		end
	
		// See if player is looking at the entity
		local tr = LocalPlayer():GetEyeTrace()
		if (tr.Entity == self) then			
			PCMod.SelEntity = self:EntIndex()
		end
	
		self.Entity:DrawModel() -- Draw the model
		
		if (self.IsScreen) then
			
			// We are a screen, we need to draw			
			// Round 19 (AUDIT2 A-07): both branches were identical - draw unconditionally.
			PCMod.SDraw.DrawScreen( self )
			
		end
	
	end
	
	// Addresses shown in the look-at overlay, one line per interface. Each IPv4
	// is followed by its matching IPv6. A WAN-only device (a backbone router)
	// publishes that address as its primary one too, so the duplicate IPv4 is
	// skipped and only its IPv6 remains for the WAN line.
	function ENT:GetOverlayAddresses()
		local txt = {}
		local function add( addr )
			if ((!addr) || (addr == "")) then return end
			if (table.HasValue( txt, addr )) then return end
			table.insert( txt, addr )
		end
		// Multi-homed hosts (two Ethernet adapters, or cable + Wi-Fi) publish
		// one address per interface. Label them so the second adapter is
		// visible even when both NICs share the same DHCP address.
		local ifstr = self.GetNWString && self:GetNWString( "IP.Ifaces" )
		if ((ifstr) && (ifstr != "") && PCMod.StringToTable) then
			local list = PCMod.StringToTable( ifstr ) or {}
			if (#list > 1) then
				// Every adapter is just an interface: eth 1, eth 2, ... (port 0
				// is the wireless link). No LAN/WAN role labels.
				local eth = 0
				for _, info in ipairs( list ) do
					local label
					if (info.Port == 0) then
						label = "wifi"
					else
						eth = eth + 1
						label = "eth " .. tostring( eth )
					end
					if (info.IPv4 && (info.IPv4 != "")) then add( label .. ": " .. info.IPv4 ) end
					if (info.IPv6 && (info.IPv6 != "")) then add( label .. ": " .. info.IPv6 ) end
				end
				return txt
			end
		end
		local primary = self:GetNWString( "IP" )
		local primary6 = self:GetNWString( "IPv6" )
		local wan = self:GetNWString( "IP.WAN" )
		local wan6 = self:GetNWString( "IPv6.WAN" )
		add( primary )
		add( primary6 )
		add( wan )
		add( wan6 )
		return txt
	end

	// SSID published by the router subsystem when Wi-Fi is enabled. Older saves
	// that only carry the boolean GVar fall back to the default name.
	function ENT:GetWirelessSSID()
		local ssid = self.GetNWString && self:GetNWString( "WifiSSID" )
		if ((ssid) && (ssid != "")) then return ssid end
		if (self.GetGVar && self:GetGVar( "wireless" )) then
			local idx = (self.EntIndex && self:EntIndex()) or 0
			return "WebGear-" .. tostring( idx )
		end
		return nil
	end

	function ENT:DrawInfo( origin )
		// If we are wireless then draw wireless info
		local ssid = self.GetWirelessSSID && self:GetWirelessSSID()
		local wireless = (ssid != nil)
		if (wireless) then PCMod.Gui.DrawWirelessLinks( self ) end
		
		// Fill in the info table
		local txt = {}
		txt[1] = self.PrintName
		if (wireless) then table.insert( txt, "SSID: " .. tostring( ssid ) ) end
		for _, addr in ipairs( self:GetOverlayAddresses() ) do table.insert( txt, addr ) end
		if (self:GetGVar( "noreg" )) then table.insert( txt, "Hardware Failure" ) end
		
		// Draw the label
		PCMod.Gui.DrawLabel( origin.x, origin.y, "ScoreboardText", txt, 10, Color( 50, 50, 50, 200 ), Color( 255, 255, 255, 255 ) )
	end

end
