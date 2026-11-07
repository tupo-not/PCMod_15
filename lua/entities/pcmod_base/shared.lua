
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
			PCMod.Msg( "Ports unlinked, now for drivers", true )
			local dat = PCMod.Data[ self:EntIndex() ]
			if (dat && dat.Drivers) then
				for k, _ in pairs(dat.Drivers) do
					dat.Drivers[ k ]:OnRemove()
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
			// LAN is the private 192.168.x.y address; WAN is the 10.x backbone
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
			// also linked to. Each entry is { IPv4 = "192.168.c.d", Router = ... }.
			tmp.IP.Extra = {}
			tmp.Memory = {}
			tmp.Ports = {}
			tmp.HardDrive = {}
			tmp.Drivers = {}
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
			local drv = self:Data().Drivers or {}
			if(PCMod.Data[ self:EntIndex() ] && PCMod.Data[ self:EntIndex() ].OS) then
				PCMod.Data[ self:EntIndex() ].OS:ShutDown()
			elseif(drv[ "gen_bios" ] && drv[ "gen_bios" ].OS) then
				drv[ "gen_bios" ].OS:ShutDown()
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
					
					// Forward data to network driver
					if (self.IsComputer) then
						if (PCMod.Data[ self:EntIndex() ].Drivers[ "gen_network" ]) then
							PCMod.Data[ self:EntIndex() ].Drivers[ "gen_network" ]:PacketRecieved( packet )
						end
					end
				else
					// Are we a router? If so forward it to webgear
					if (self.IsNetworkDevice) then
						if (PCMod.Data[ self:EntIndex() ].Drivers[ "webgr_router" ]) then
							PCMod.Data[ self:EntIndex() ].Drivers[ "webgr_router" ]:DataRecieved( packet )
						end
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
			if (type( port ) == "number") then port = self:Ports()[ port ] end
			if (!port) then return 1 end
			if (!port.Connected) then return 2 end
			local ent = port.ConEnt
			if ((ent) && (ent:IsValid())) then
				return ent:GivenData( port.RemotePort, data )
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
			for _, v in pairs( PCMod.Data[ self:EntIndex() ].Drivers ) do
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

	
		// -----------------------------------------------------------------------------------------------------
		// IPv4 addressing. Every interface is stored as one plain dotted quad:
		//   IP.LAN  - private LAN address (192.168.x.y)
		//   IP.WAN  - routed WAN/backbone address (10.x.x.x)
		// Subnet/host numbers are derived from the string; there are no separate
		// LAN vs backbone address types.
		// -----------------------------------------------------------------------------------------------------

		local function ParseLanAddress( addr )
			if ((!addr) || (type( addr ) != "string")) then return nil end
			return PCMod.IPv4.ParseLan( addr )
		end

		function ENT:GetSubnet()
			local p = ParseLanAddress( self:Data().IP.LAN )
			return p and p.sub or false
		end

		function ENT:GetIP()
			local p = ParseLanAddress( self:Data().IP.LAN )
			return p and p.add or false
		end

		// The device's primary IPv4. A PC on a backbone (for example behind a
		// modem) has only IP.WAN, so the primary address falls back to it.
		function ENT:GetFullIP()
			local ip = self:Data().IP
			return ip.LAN or ip.WAN
		end

		function ENT:GetIPv4()
			local ip = self:Data().IP
			return ip.LAN or ip.WAN
		end

		// WAN/backbone IPv4 (plain dotted quad, same type as the LAN address).
		function ENT:GetFullBIP()
			return self:Data().IP.WAN
		end

		function ENT:GetWANIPv4()
			return self:Data().IP.WAN
		end

		// Backbone id / zero-based host slot behind the WAN address. Kept for
		// routing and IPv6 derivation; the user-facing address is IP.WAN.
		function ENT:GetBSubnet()
			return self:Data().IP.WanBB
		end

		function ENT:GetBIP()
			return self:Data().IP.WanHost
		end

		// -----------------------------------------------------------------------------------------------------
		// Secondary LAN addresses (one per additional router this device is
		// linked to). Stored as plain IPv4 strings as well.
		// -----------------------------------------------------------------------------------------------------

		function ENT:ExtraIPs()
			local ip = self:Data().IP
			ip.Extra = ip.Extra or {}
			return ip.Extra
		end

		// Record a secondary lease. Returns the entry (existing one when the
		// address is already present).
		function ENT:AddExtraIP( addr, upbb, lanid, router )
			if (!addr) then return nil end
			local full = PCMod.IPv4.ParseLan( tostring( addr ) )
			if (!full) then return nil end
			local list = self:ExtraIPs()
			for _, ex in ipairs( list ) do
				if (ex.IPv4 == full.full) then return ex end
			end
			local ex = {
				IPv4 = full.full,
				UpBB = upbb or 0,
				LanID = lanid or 0,
				Router = router,
			}
			list[ #list + 1 ] = ex
			return ex
		end

		// Drop the secondary with this address. Returns true when found.
		function ENT:ReleaseExtraIP( addr )
			if (!addr) then return false end
			local p = PCMod.IPv4.ParseLan( tostring( addr ) )
			local full = p and p.full or tostring( addr )
			local list = self:ExtraIPs()
			for i, ex in ipairs( list ) do
				if (ex.IPv4 == full) then
					table.remove( list, i )
					return true
				end
			end
			return false
		end

		// Re-number the secondary(s) leased from `router` (its LAN /64 moved).
		function ENT:UpdateExtraIPRouter( router, upbb, lanid )
			local changed = false
			for _, ex in ipairs( self:ExtraIPs() ) do
				if (ex.Router == router) then
					ex.UpBB = upbb or 0
					ex.LanID = lanid or 0
					changed = true
				end
			end
			return changed
		end

		// Every secondary address this device answers on (one per additional
		// router it is linked to).
		function ENT:GetExtraAddresses()
			local out = {}
			for _, ex in ipairs( self:ExtraIPs() ) do
				local p = ParseLanAddress( ex.IPv4 )
				out[ #out + 1 ] = {
					IPv4 = ex.IPv4,
					IPv6 = (p and PCMod.IPv6.Format( { 0xfd00, ex.UpBB or 0, 0, ex.LanID or 0, 0, 0, 0, (p.sub or 0) * 256 + (p.add or 0) } )) or false,
					Router = ex.Router,
				}
			end
			return out
		end

		// Set the LAN IPv4 from a dotted quad. This is the one address PCs and
		// router LAN interfaces use.
		function ENT:SetLanAddress( addr, upbb, lanid )
			local ip = self:Data().IP
			ip.V6 = nil
			ip.V6Prefix = nil
			ip.V6Link = nil
			if (!addr) then
				ip.LAN = false
			else
				local p = ParseLanAddress( tostring( addr ) )
				if (!p) then return false end
				ip.LAN = p.full
				if (upbb != nil) then ip.UpBB = upbb end
				if (lanid != nil) then ip.LanID = lanid end
			end
			self:SetIPText()
			return true
		end

		// Compatibility helpers used by the DHCP core: update one octet of the
		// current LAN address, keeping the other.
		function ENT:SetSubnet( subnet )
			local ip = self:Data().IP
			if ((subnet == false) || (subnet == nil)) then
				ip.LAN = false
			else
				local p = ParseLanAddress( ip.LAN )
				ip.LAN = "192.168." .. tostring( subnet ) .. "." .. tostring( (p and p.add) or 1 )
			end
			self:SetIPText()
		end

		function ENT:SetIP( ip )
			local data = self:Data().IP
			if ((ip == false) || (ip == nil)) then
				data.LAN = false
			else
				local p = ParseLanAddress( data.LAN )
				data.LAN = "192.168." .. tostring( (p and p.sub) or 0 ) .. "." .. tostring( ip )
			end
			self:SetIPText()
		end

		// Configure a static LAN IP (192.168.x.y). Pass "" or false to clear it and
		// fall back to DHCP. Returns false on a malformed/out-of-range address.
		function ENT:SetStaticIP( addr )
			local ip = self:Data().IP
			if (type( addr ) == "string") then
				addr = string.Trim( addr )
			end
			if (type( addr ) == "string" && addr != "") then
				local p = ParseLanAddress( addr )
				if (!p) then return false end
				ip.Static = p.full
				// A static address is not owned by any DHCP router.
				ip.Router = false
				self:SetLanAddress( p.full )
				return true
			end
			ip.Static = false
			ip.Router = false
			self:SetLanAddress( false )
			return true
		end

		function ENT:GetStaticIP()
			return self:Data().IP.Static
		end

		// Dotted netmask and IPv4 gateway configured on the Network page.
		function ENT:GetNetmask()
			return self:Data().IP.Mask
		end

		function ENT:GetGateway()
			return self:Data().IP.Gateway
		end

		function ENT:SetNetmask( mask )
			local bits = PCMod.IPv4.MaskToBits( mask )
			if (!bits) then return false end
			local ip = self:Data().IP
			ip.Mask = PCMod.IPv4.BitsToMask( bits )
			ip.MaskBits = bits
			return true
		end

		function ENT:SetGateway( gw )
			local ip = self:Data().IP
			if ((gw == nil) || (gw == "")) then
				ip.Gateway = false
				return true
			end
			local lan = PCMod.IPv4.ParseLan( tostring( gw ) )
			if (!lan) then return false end
			ip.Gateway = lan.full
			return true
		end

		// Apply a static IPv4 setup (address, netmask, gateway) in one go.
		// An empty address clears the static IP (DHCP), an empty netmask keeps
		// the current one, and an empty gateway clears it. Returns true, or
		// false plus a reason.
		function ENT:SetNetworkConfig( addr, mask, gw )
			local ip = self:Data().IP
			local maskBits = nil
			if ((mask != nil) && (string.Trim( tostring( mask ) ) != "")) then
				maskBits = PCMod.IPv4.MaskToBits( mask )
				if (!maskBits) then return false, "Invalid netmask" end
			end
			local g = ""
			if (gw != nil) then g = string.Trim( tostring( gw ) ) end
			if ((g != "") && (!PCMod.IPv4.ParseLan( g ))) then return false, "Invalid gateway" end
			if (!self:SetStaticIP( addr )) then return false, "Invalid IP address" end
			if (maskBits != nil) then
				ip.Mask = PCMod.IPv4.BitsToMask( maskBits )
				ip.MaskBits = maskBits
			end
			if (gw != nil) then ip.Gateway = (g != "") and g or false end
			return true
		end

		// Set the WAN/backbone IPv4 from a dotted quad. Routers use this for
		// their uplink; it is the same plain IPv4 type as IP.LAN.
		function ENT:SetWanAddress( addr, bb, host )
			local ip = self:Data().IP
			if (!addr) then
				ip.WAN = false
				ip.WanBB = false
				ip.WanHost = false
			else
				local p = PCMod.IPv4.Parse( tostring( addr ) )
				if (!p) then return false end
				ip.WAN = tostring( addr )
				ip.WanBB = bb or p.bb
				ip.WanHost = (host != nil) and host or (p.host - 1)
			end
			self:SetBIPText()
			return true
		end

		function ENT:SetBSubnet( subnet )
			local ip = self:Data().IP
			ip.WanBB = ((subnet == false) || (subnet == nil)) and false or subnet
			self:SetBIPText()
		end

		function ENT:SetBIP( host )
			local ip = self:Data().IP
			ip.WanHost = ((host == false) || (host == nil)) and false or host
			self:SetBIPText()
		end

		function ENT:SetIPText()
			local ip = self:Data().IP
			local p = ParseLanAddress( ip.LAN )
			if (p) then
				ip.LAN = p.full
				self:SetNWString( "IP", ip.LAN )
				// Emulated dual-stack address (see PCMod.IPv6 in sh_common.lua).
				// Hierarchical LAN: fd00:<bb>:0:<subnet>::<host>.
				local host = (p.sub or 0) * 256 + p.add
				ip.V6 = PCMod.IPv6.Format( { 0xfd00, ip.UpBB or 0, 0, ip.LanID or 0, 0, 0, 0, host } )
				ip.V6Prefix = PCMod.IPv6.LANPrefix( ip.UpBB or 0, ip.LanID or 0 )
				ip.V6Link = PCMod.IPv6.LinkLocal( ip.V6 )
				self:SetNWString( "IPv6", ip.V6 or "" )
				self:SetNWString( "IPv6.Prefix", ip.V6Prefix or "" )
				self:SetNWString( "IPv6.LinkLocal", ip.V6Link or "" )
			else
				ip.LAN = false
				ip.V6 = false
				ip.V6Prefix = false
				ip.V6Link = false
				self:SetNWString( "IP", ip.WAN or "" )
				self:SetNWString( "IPv6", "" )
				self:SetNWString( "IPv6.Prefix", "" )
				self:SetNWString( "IPv6.LinkLocal", "" )
			end
		end

		function ENT:SetBIPText()
			local ip = self:Data().IP
			if ((ip.WanBB != false) && (ip.WanBB != nil) && (ip.WanHost != false) && (ip.WanHost != nil)) then
				local host = ip.WanHost + 1
				ip.WAN = PCMod.IPv4.BackboneAddress( ip.WanBB, host )
				self:SetNWString( "IP.WAN", ip.WAN )
				if (!ip.LAN) then self:SetNWString( "IP", ip.WAN ) end
				ip.WanV6 = PCMod.IPv6.Format( { 0xfd00, ip.WanBB, 0, 0, 0, 0, 0, host } )
				ip.WanV6Prefix = PCMod.IPv6.BackbonePrefix( ip.WanBB )
				ip.WanV6Link = PCMod.IPv6.LinkLocal( ip.WanV6 )
				self:SetNWString( "IPv6.WAN", ip.WanV6 or "" )
				self:SetNWString( "IPv6.WAN.Prefix", ip.WanV6Prefix or "" )
				self:SetNWString( "IPv6.WAN.LinkLocal", ip.WanV6Link or "" )
			else
				ip.WAN = false
				ip.WanV6 = false
				ip.WanV6Prefix = false
				ip.WanV6Link = false
				self:SetNWString( "IP.WAN", "" )
				if (!ip.LAN) then self:SetNWString( "IP", "" ) end
				self:SetNWString( "IPv6.WAN", "" )
				self:SetNWString( "IPv6.WAN.Prefix", "" )
				self:SetNWString( "IPv6.WAN.LinkLocal", "" )
			end
		end

		// Emulated IPv6 accessors. The address is derived lazily so entities
		// created before the IPv6 fields existed still report one.
		// LAN addressing is hierarchical: fd00:<bb>:0:<subnet>::<host>.
		function ENT:GetIPv6()
			local ip = self:Data().IP
			local p = ParseLanAddress( ip.LAN )
			if (!p) then return false end
			if (ip.V6 == nil) then
				local host = (p.sub or 0) * 256 + p.add
				ip.V6 = PCMod.IPv6.Format( { 0xfd00, ip.UpBB or 0, 0, ip.LanID or 0, 0, 0, 0, host } )
			end
			return ip.V6
		end

		function ENT:GetFullIPv6()
			return self:GetIPv6()
		end

		// WAN interface IPv6: fd00:<bb>::<host+1> (host slot 0 -> ::1).
		function ENT:GetBIPv6()
			local ip = self:Data().IP
			if ((ip.WanBB == false) || (ip.WanBB == nil) || (ip.WanHost == false) || (ip.WanHost == nil)) then return false end
			if (ip.WanV6 == nil) then
				ip.WanV6 = PCMod.IPv6.Format( { 0xfd00, ip.WanBB, 0, 0, 0, 0, 0, ip.WanHost + 1 } )
			end
			return ip.WanV6
		end

		function ENT:GetFullBIPv6()
			return self:GetBIPv6()
		end

		// The /64 LAN prefix fd00:<bb>:0:<net>::/64.
		function ENT:GetIPv6Prefix()
			local ip = self:Data().IP
			if (!ParseLanAddress( ip.LAN )) then return false end
			if (!ip.V6Prefix) then ip.V6Prefix = PCMod.IPv6.LANPrefix( ip.UpBB or 0, ip.LanID or 0 ) end
			return ip.V6Prefix
		end

		function ENT:GetIPv6Network()
			return self:GetIPv6Prefix()
		end

		function ENT:GetIPv6Subnet()
			return self:GetIPv6Prefix()
		end

		// The router/gateway address of this LAN (prefix + ::1).
		function ENT:GetIPv6Gateway()
			local p = self:GetIPv6Prefix()
			if (!p) then return false end
			return PCMod.IPv6.Gateway( p )
		end

		// Link-local address of this interface (fe80::/64).
		function ENT:GetIPv6LinkLocal()
			local v6 = self:GetIPv6()
			if (!v6) then return false end
			local ip = self:Data().IP
			if (!ip.V6Link) then ip.V6Link = PCMod.IPv6.LinkLocal( v6 ) end
			return ip.V6Link
		end

		// The /32 backbone prefix fd00:<bb>::/32.
		function ENT:GetBIPv6Prefix()
			local ip = self:Data().IP
			if ((ip.WanBB == false) || (ip.WanBB == nil)) then return false end
			if (!ip.WanV6Prefix) then ip.WanV6Prefix = PCMod.IPv6.BackbonePrefix( ip.WanBB ) end
			return ip.WanV6Prefix
		end

		function ENT:GetBIPv6Network()
			return self:GetBIPv6Prefix()
		end

		function ENT:GetBIPv6Subnet()
			return self:GetBIPv6Prefix()
		end

		function ENT:GetBIPv6Gateway()
			local p = self:GetBIPv6Prefix()
			if (!p) then return false end
			return PCMod.IPv6.Gateway( p )
		end

		function ENT:GetBIPv6LinkLocal()
			local v6 = self:GetBIPv6()
			if (!v6) then return false end
			local ip = self:Data().IP
			if (!ip.WanV6Link) then ip.WanV6Link = PCMod.IPv6.LinkLocal( v6 ) end
			return ip.WanV6Link
		end

		// Which backbone /32 this LAN hangs off (0 = standalone). Used to build
		// the LAN /64; set by the network core when the PC joins a router.
		function ENT:SetUpBB( bb )
			local ip = self:Data().IP
			ip.UpBB = bb
			ip.V6 = nil
			ip.V6Prefix = nil
			ip.V6Link = nil
			self:SetIPText()
		end

		// The /64 network id this LAN uses inside its backbone /32.
		function ENT:SetLanID( net )
			local ip = self:Data().IP
			ip.LanID = net
			ip.V6 = nil
			ip.V6Prefix = nil
			ip.V6Link = nil
			self:SetIPText()
		end

		// Is addr part of this entity's LAN (or backbone) /64?
		function ENT:IsInIPv6Subnet( addr, backbone )
			local p = backbone && self:GetBIPv6Prefix() or self:GetIPv6Prefix()
			if (!p) then return false end
			return PCMod.IPv6.InSubnet( addr, p )
		end

		// True when addr (IPv4, emulated IPv6, mapped IPv6 or loopback) points
		// at this entity's LAN or backbone address (primary or secondary).
		function ENT:IsAddressedTo( addr )
			if ((!addr) || (type( addr ) != "string")) then return false end
			if (PCMod.IPv6.Matches( addr, self:GetFullIP(), self:GetIPv6() )) then return true end
			if (PCMod.IPv6.Matches( addr, self:GetFullBIP(), self:GetBIPv6() )) then return true end
			// Secondary addresses (leases from other routers).
			for _, ex in ipairs( self:ExtraIPs() ) do
				local p = PCMod.IPv4.ParseLan( ex.IPv4 )
				local v6 = p and PCMod.IPv6.Format( { 0xfd00, ex.UpBB or 0, 0, ex.LanID or 0, 0, 0, 0, (p.sub or 0) * 256 + (p.add or 0) } ) or false
				if (PCMod.IPv6.Matches( addr, ex.IPv4, v6 )) then return true end
			end
			return false
		end

		function ENT:GetSourceAddress( dest )
			// Answering on one of our own addresses (multi-homed devices
			// included): source from the exact address that was contacted so
			// the reply goes back out on the same identity.
			if (dest && self:IsAddressedTo( dest )) then return dest end
			// Pick the routable source: IPv6 for IPv6 destinations, otherwise
			// the plain IPv4 address (LAN first, WAN for a backbone-only device).
			if (dest && PCMod.IPv6.IsIPv6( dest )) then
				return self:GetIPv6() or self:GetFullIP() or self:GetFullBIP()
			end
			return self:GetFullIP() or self:GetFullBIP()
		end

		function ENT:SendPacket( portid, dest, port, body, ttl, src )
			// Called from this entity, sends a new packet
			if (!portid) then
				for k, v in pairs( self:Ports() ) do
					if ((v.Type == "network") || (v.Type == "optic")) then
						portid = k
						break
					end
				end
			end
			PCMod.Msg("Sending packet from "..self.Entity:GetClass().." {"..tostring(portid)..", "..tostring(dest)..", "..tostring(port)..", "..tostring(body).."}", true)
			local prt = self:Ports()[ portid ]
			if (!prt) then return 1 end
			if (!prt.Connected) then return 2 end
			local portid2 = prt.RemotePort
			local data = {}
			data[1] = "sendpacket"
			// An explicit source (a reply to one of our secondary addresses)
			// wins over the automatic interface pick.
			data[2] = { src or self:GetSourceAddress( dest ), dest, port, body }
			// Layer-2 frame metadata: the sender's MAC and, until a switch has
			// learned the destination, a broadcast address.
			data[4] = {
				SourceMAC = self:EnsureMAC(),
				DestMAC = PCMod.MAC.BROADCAST,
			}
			// IP TTL travels with the frame until a router turns it into a
			// packet. data[3] is already used by switches for loop detection.
			if (ttl) then data[5] = ttl end
			if (!self.IsNetworkDevice) then
				prt.ConEnt:DataRecieved( portid2, data )
				// self:PushData
			else
				self:DataRecieved( portid, data )
			end
			return 0
		end
		
		
	-------------------------------------------------------------------------------------------------------------------------------------------------
	-- Entity Data Functions --
	-------------------------------------------------------------------------------------------------------------------------------------------------

	
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
	-- Driver Functions --
	-------------------------------------------------------------------------------------------------------------------------------------------------
	
	
		function ENT:InstallDriver( drivername )
			local drv = PCMod.Drivers[ drivername ]
			if (!drv) then
				PCMod.Msg( "No such driver '" .. drivername .. "'!", true )
				return
			end
			local mydrv = table.Copy( drv )
			mydrv.Entity = self
			PCMod.Data[ self:EntIndex() ].Drivers[ drivername ] = mydrv
			PCMod.Data[ self:EntIndex() ].Drivers[ drivername ]:Initialize()
			PCMod.Msg( "Installing driver '" .. drivername .. "' to (" .. tostring( self:EntIndex() ) .. ")", true )
			return PCMod.Data[ self:EntIndex() ].Drivers[ drivername ]
		end
		
		function ENT:PushDriverData( drivername, port, data )
			if (!PCMod.Data[ self:EntIndex() ].Drivers[ drivername ]) then return end
			PCMod.Data[ self:EntIndex() ].Drivers[ drivername ]:DataRecieved( port, data )
		end
		
		function ENT:CallDriver( drivername, func, ... )
			if (!PCMod.Data[ self:EntIndex() ].Drivers[ drivername ]) then return end
			return PCMod.Data[ self:EntIndex() ].Drivers[ drivername ][ func ]( ... ) -- Now that's what I call a function call :D
		end
		
	
	-------------------------------------------------------------------------------------------------------------------------------------------------
	-- File Functions --
	-------------------------------------------------------------------------------------------------------------------------------------------------
	
		// Internal path helpers. The hard drive table uses keys such as
		// "/mydocs/text/" for folders and "/mydocs/text/a.txt" for files, so
		// every public helper normalises its input before looking anything up.
		local function FS_NormalizePath( path )
			if (path == nil) then return "" end
			path = tostring( path )
			path = string.gsub( path, "\\", "/" )
			path = string.gsub( path, "/+", "/" )
			while (string.Left( path, 1 ) == "/") do
				path = string.sub( path, 2 )
			end
			while ((string.len( path ) > 0) && (string.Right( path, 1 ) == "/")) do
				path = string.sub( path, 1, string.len( path ) - 1 )
			end
			return path
		end

		local function FS_HardDrive( ent )
			local data = PCMod.Data[ ent:EntIndex() ]
			if (!data) then return nil end
			if (!data.HardDrive) then data.HardDrive = {} end
			return data.HardDrive
		end

		local function FS_FindKey( hd, path )
			if (!hd) then return nil end
			local norm = FS_NormalizePath( path )
			if (norm == "") then return nil end
			local direct = "/" .. norm
			if (hd[ direct ]) then return direct end
			if (hd[ direct .. "/" ]) then return direct .. "/" end
			// Older code (and FileList) treated paths case-insensitively.
			local lower = string.lower( direct )
			for key, _ in pairs( hd ) do
				local k = string.lower( key )
				if ((k == lower) || (k == lower .. "/")) then return key end
			end
			return nil
		end

		local function FS_ParentPath( path )
			local norm = FS_NormalizePath( path )
			for i = string.len( norm ), 1, -1 do
				if (string.sub( norm, i, i ) == "/") then
					return string.sub( norm, 1, i - 1 )
				end
			end
			return ""
		end

		local function FS_Basename( path )
			local norm = FS_NormalizePath( path )
			if (norm == "") then return "" end
			local name = string.match( norm, "([^/]+)$" )
			return name or norm
		end

		function ENT:IsPathLocked( path )
			local hd = FS_HardDrive( self )
			if (!hd) then return false end
			local norm = FS_NormalizePath( path )
			if (norm == "") then return false end
			local cur = ""
			for _, seg in ipairs( string.Explode( "/", norm ) ) do
				if (seg != "") then
					if (cur == "") then cur = seg else cur = cur .. "/" .. seg end
					local key = FS_FindKey( hd, cur )
					if (key && hd[ key ].Locked) then return true end
				end
			end
			return false
		end

		function ENT:MakeFolder( path )
			local hd = FS_HardDrive( self )
			if (!hd) then return false end
			local norm = FS_NormalizePath( path )
			if (norm == "") then return true end
			if (self:IsPathLocked( norm )) then
				PCMod.Msg( "Tried to create a folder in a locked path: " .. norm .. " (" .. tostring( self:EntIndex() ) .. ")", true )
				return false
			end
			local cur = ""
			for _, seg in ipairs( string.Explode( "/", norm ) ) do
				if (seg != "") then
					if (cur == "") then cur = seg else cur = cur .. "/" .. seg end
					local key = FS_FindKey( hd, cur )
					if (key) then
						if (hd[ key ].ItemType != "folder") then return false end
					else
						local item = {}
						item.ItemType = "folder"
						item.ItemName = cur
						item.ItemContent = ""
						item.Locked = false
						hd[ "/" .. cur .. "/" ] = item
					end
				end
			end
			return true
		end

		function ENT:ListDir( path )
			local out = {}
			local hd = FS_HardDrive( self )
			if (!hd) then return out end
			local norm = FS_NormalizePath( path )
			local prefix = "/" .. norm
			if (norm != "") then prefix = prefix .. "/" end
			local seen = {}
			for key, item in pairs( hd ) do
				if (string.Left( key, string.len( prefix ) ) == prefix) then
					local rest = string.sub( key, string.len( prefix ) + 1 )
					while ((string.len( rest ) > 0) && (string.Right( rest, 1 ) == "/")) do
						rest = string.sub( rest, 1, string.len( rest ) - 1 )
					end
					if ((rest != "") && (!string.find( rest, "/", 1, true ))) then
						local size = 0
						if (item.ItemType == "file") then size = string.len( item.ItemContent or "" ) end
						local info = {}
						info.Name = rest
						info.Path = ((norm == "") && rest) || (norm .. "/" .. rest)
						info.Type = item.ItemType
						info.Size = size
						info.Locked = (item.Locked == true)
						local idx = seen[ rest ]
						if (!idx) then
							seen[ rest ] = #out + 1
							table.insert( out, info )
						elseif (item.ItemType == "folder") then
							// If both "/name" and "/name/" exist, prefer the folder.
							out[ idx ] = info
						end
					end
				end
			end
			table.sort( out, function( a, b )
				if (a.Type != b.Type) then return (a.Type == "folder") end
				return (string.lower( a.Name ) < string.lower( b.Name ))
			end )
			return out
		end

		function ENT:GetItemInfo( path )
			local hd = FS_HardDrive( self )
			if (!hd) then return nil end
			local key = FS_FindKey( hd, path )
			if (!key) then return nil end
			local item = hd[ key ]
			if (!item) then return nil end
			local norm = FS_NormalizePath( key )
			local info = {}
			info.Name = FS_Basename( norm )
			info.Path = norm
			info.Type = item.ItemType
			info.Locked = (item.Locked == true)
			info.Size = 0
			if (item.ItemType == "file") then
				info.Size = string.len( item.ItemContent or "" )
				info.Content = item.ItemContent
			end
			return info
		end

		function ENT:RenameItem( oldpath, newpath )
			local hd = FS_HardDrive( self )
			if (!hd) then return false end
			local oldnorm = FS_NormalizePath( oldpath )
			local newnorm = FS_NormalizePath( newpath )
			if ((oldnorm == "") || (newnorm == "") || (oldnorm == newnorm)) then return false end
			local oldkey = FS_FindKey( hd, oldnorm )
			if (!oldkey) then return false end
			// Lookup is case-insensitive; use the stored spelling for every
			// descendant mutation as well or a case-variant path matches nothing.
			oldnorm = FS_NormalizePath( oldkey )
			if (self:IsPathLocked( oldnorm ) || self:IsPathLocked( newnorm )) then
				PCMod.Msg( "Tried to rename a locked path: " .. oldnorm .. " (" .. tostring( self:EntIndex() ) .. ")", true )
				return false
			end
			if (FS_FindKey( hd, newnorm )) then return false end
			local oldprefix = "/" .. oldnorm
			local newprefix = "/" .. newnorm
			// Never move a folder into itself.
			if (string.Left( newprefix, string.len( oldprefix ) + 1 ) == oldprefix .. "/") then return false end
			if (!self:MakeFolder( FS_ParentPath( newnorm ) )) then return false end
			local moves = {}
			for key, _ in pairs( hd ) do
				if ((key == oldprefix) || (string.Left( key, string.len( oldprefix ) + 1 ) == oldprefix .. "/")) then
					table.insert( moves, key )
				end
			end
			for _, key in ipairs( moves ) do
				local suffix = string.sub( key, string.len( oldprefix ) + 1 )
				if (hd[ newprefix .. suffix ]) then return false end
			end
			for _, key in ipairs( moves ) do
				local item = hd[ key ]
				local suffix = string.sub( key, string.len( oldprefix ) + 1 )
				local target = newprefix .. suffix
				hd[ target ] = item
				hd[ key ] = nil
				local rel = string.sub( target, 2 )
				while ((string.len( rel ) > 0) && (string.Right( rel, 1 ) == "/")) do
					rel = string.sub( rel, 1, string.len( rel ) - 1 )
				end
				item.ItemName = rel
			end
			return true
		end

		function ENT:CopyItem( oldpath, newpath )
			local hd = FS_HardDrive( self )
			if (!hd) then return false end
			local oldnorm = FS_NormalizePath( oldpath )
			local newnorm = FS_NormalizePath( newpath )
			if ((oldnorm == "") || (newnorm == "") || (oldnorm == newnorm)) then return false end
			local oldkey = FS_FindKey( hd, oldnorm )
			if (!oldkey) then return false end
			oldnorm = FS_NormalizePath( oldkey )
			if (self:IsPathLocked( oldnorm ) || self:IsPathLocked( newnorm )) then
				PCMod.Msg( "Tried to copy a locked path: " .. oldnorm .. " (" .. tostring( self:EntIndex() ) .. ")", true )
				return false
			end
			if (FS_FindKey( hd, newnorm )) then return false end
			local oldprefix = "/" .. oldnorm
			local newprefix = "/" .. newnorm
			if (string.Left( newprefix, string.len( oldprefix ) + 1 ) == oldprefix .. "/") then return false end
			if (!self:MakeFolder( FS_ParentPath( newnorm ) )) then return false end
			local copies = {}
			for key, item in pairs( hd ) do
				if ((key == oldprefix) || (string.Left( key, string.len( oldprefix ) + 1 ) == oldprefix .. "/")) then
					table.insert( copies, { key = key, item = item } )
				end
			end
			for _, v in ipairs( copies ) do
				local suffix = string.sub( v.key, string.len( oldprefix ) + 1 )
				if (hd[ newprefix .. suffix ]) then return false end
			end
			for _, v in ipairs( copies ) do
				local suffix = string.sub( v.key, string.len( oldprefix ) + 1 )
				local target = newprefix .. suffix
				local item = table.Copy( v.item )
				local rel = string.sub( target, 2 )
				while ((string.len( rel ) > 0) && (string.Right( rel, 1 ) == "/")) do
					rel = string.sub( rel, 1, string.len( rel ) - 1 )
				end
				item.ItemName = rel
				hd[ target ] = item
			end
			return true
		end

		function ENT:DeleteItem( path )
			local hd = FS_HardDrive( self )
			if (!hd) then return false end
			local norm = FS_NormalizePath( path )
			if (norm == "") then return false end
			local key = FS_FindKey( hd, norm )
			if (!key) then return false end
			norm = FS_NormalizePath( key )
			if (self:IsPathLocked( norm )) then
				PCMod.Msg( "Tried to delete a locked path: " .. norm .. " (" .. tostring( self:EntIndex() ) .. ")", true )
				return false
			end
			local prefix = "/" .. norm
			local dels = {}
			for key, item in pairs( hd ) do
				if ((key == prefix) || (string.Left( key, string.len( prefix ) + 1 ) == prefix .. "/")) then
					if (item.Locked) then return false end
					table.insert( dels, key )
				end
			end
			for _, key in ipairs( dels ) do
				hd[ key ] = nil
			end
			return true
		end

		function ENT:LinkFolder( dir )
			local hd = FS_HardDrive( self )
			if (!hd) then return end
			local norm = FS_NormalizePath( dir )
			if (norm == "") then return end
			local key = FS_FindKey( hd, norm )
			// Only an explicitly locked folder entry is protected. Creating a
			// folder *inside* a locked one (system/os/, system/data/) must keep
			// working: the entity/OS setup does exactly that during boot.
			if (key && hd[ key ].Locked) then
				PCMod.Msg( "Tried to overwrite locked folder: " .. norm .. " (" .. tostring( self:EntIndex() ) .. ")", true )
				return
			end
			if (key && (hd[ key ].ItemType != "folder")) then
				PCMod.Msg( "Tried to use file as a folder: " .. norm .. " (" .. tostring( self:EntIndex() ) .. ")", true )
				return
			end
			local tmp = {}
			tmp.ItemType = "folder"
			tmp.ItemName = norm
			tmp.ItemContent = ""
			tmp.Locked = false
			// Keep the historical key format (folders commonly end in "/"), so
			// existing save data and PCMod.Beam.FileList keep working.
			hd[ key or ( "/" .. norm .. "/" ) ] = tmp
		end
		
		function ENT:UnlinkItem( dir )
			local hd = FS_HardDrive( self )
			if (!hd) then return end
			local norm = FS_NormalizePath( dir )
			if (norm == "") then return end
			local key = FS_FindKey( hd, norm )
			if (!key) then return end
			// Removing a file that lives inside a locked folder is legitimate
			// (for example OS:RegisterRun deletes system/firstrun.sys). Only
			// the item itself being locked is refused here.
			if (hd[ key ].Locked) then
				PCMod.Msg( "Tried to unlink locked item: " .. norm .. " (" .. tostring( self:EntIndex() ) .. ")", true )
				return
			end
			hd[ key ] = nil
		end
		
		function ENT:LockItem( dir )
			local hd = FS_HardDrive( self )
			local key = FS_FindKey( hd, dir )
			if (key) then hd[ key ].Locked = true end
		end
		function ENT:UnLockItem( dir )
			local hd = FS_HardDrive( self )
			local key = FS_FindKey( hd, dir )
			if (key) then hd[ key ].Locked = false end
		end
		
		function ENT:WriteFile( filename, content )
			local hd = FS_HardDrive( self )
			if (!hd) then return false, "no_drive" end
			local norm = FS_NormalizePath( filename )
			if (norm == "") then return false, "invalid_path" end
			// Trusted entity/OS writes may still target locked folders during
			// setup and persistence. Untrusted program writes use
			// WriteFileChecked below, which enforces inherited locks too.
			local existing = FS_FindKey( hd, norm )
			if (existing && hd[ existing ].Locked) then
				PCMod.Msg( "Tried to overwrite locked file: " .. norm .. " (" .. tostring( self:EntIndex() ) .. ")", true )
				return false, "locked"
			end
			if (existing && (hd[ existing ].ItemType != "file")) then
				return false, "not_file"
			end
			local dir = FS_ParentPath( norm )
			local dirkey = FS_FindKey( hd, dir )
			if (dirkey && (hd[ dirkey ].ItemType == "file")) then
				PCMod.Msg( "Tried to use file as a folder: " .. dir .. " (" .. tostring( self:EntIndex() ) .. ")", true )
				return false, "parent_is_file"
			end
			// Preserve the stored key when an existing file was found through
			// case-insensitive lookup instead of creating a duplicate.
			local stored = existing and FS_NormalizePath( existing ) or norm
			local tmp = {}
			tmp.ItemType = "file"
			tmp.ItemName = stored
			tmp.ItemContent = content
			tmp.Locked = false
			hd[ existing or ( "/" .. norm ) ] = tmp
			return true
		end

		// Lock-aware write for player/program input. Entity and OS internals keep
		// using WriteFile because they legitimately populate system/data during
		// setup and save PC state while those folders are locked to users.
		function ENT:WriteFileChecked( filename, content )
			if (self:IsPathLocked( filename )) then
				PCMod.Msg( "Tried to write inside locked path: " .. tostring( filename ) .. " (" .. tostring( self:EntIndex() ) .. ")", true )
				return false, "locked"
			end
			return self:WriteFile( filename, content )
		end
		
		function ENT:ReadFile( filename )
			local hd = FS_HardDrive( self )
			local key = FS_FindKey( hd, filename )
			local item = key && hd[ key ]
			if (!item) then
				PCMod.Msg( "Tried to read unexistant file: " .. tostring( filename ) .. " (" .. tostring( self:EntIndex() ) .. ")", true )
				return ""
			end
			if (item.ItemType == "file") then return item.ItemContent end
			PCMod.Msg( "Tried to read a folder: " .. tostring( filename ) .. " (" .. tostring( self:EntIndex() ) .. ")", true )
			return ""
		end
		
		function ENT:FileFolderExist( filename )
			local hd = FS_HardDrive( self )
			if (FS_FindKey( hd, filename )) then return true end
			return false
		end

		function ENT:IsLocked( target )
			local hd = FS_HardDrive( self )
			local key = FS_FindKey( hd, target )
			if (!key) then return false end
			return hd[ key ].Locked
		end
		
	
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
			if (hk.Target == "driver") then
				if (!self:Data().Drivers[ hk.ID ]) then return end
				PCMod.Msg( "Calling driver hook!", true )
				self:Data().Drivers[ hk.ID ]:CallEvent( data )
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
		
	/*	util.AddNetworkString( "ekrantazele" )
		net.Receive("ekrantazele", function()
		print("anaaa")
		local ent = net.ReadEntity()
		for _, v in pairs( player.GetAll() ) do
				if (!v.SSBeam) then v.SSBeam = {} end
				v.SSBeam[ ent:EntIndex() ] = false
			end
			ent:FireEvent( { "ss_inval" } )
			if (ent.IsScreen) then	PCMod.Beam.BeamEntSS( ent, PCMod.Beam.Range_SS ) end
		end)
		*/
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
			dt.MAC = norm
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
			// network) once the router driver exists.
			if (self.IsNetworkDevice) then
				local rdrv = dt.Drivers && dt.Drivers[ "webgr_router" ]
				if (rdrv && rdrv.ApplyLanAddress) then rdrv:ApplyLanAddress() end
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

			// Push the restored wireless flag into the router driver.
			if (self.IsNetworkDevice) then
				local rdrv = dt.Drivers && dt.Drivers[ "webgr_router" ]
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

			// Legacy duplicator Think stamp.
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
	
	function ENT:DrawInfo( origin )
		// If we are wireless then draw wireless info
		local wireless = self:GetGVar( "wireless" )
		if (wireless) then PCMod.Gui.DrawWirelessLinks( self ) end
		
		// Get the IP info (both are plain IPv4 strings)
		local lan = self:GetNWString( "IP" )
		local wan = self:GetNWString( "IP.WAN" )
		
		// Fill in the info table
		local txt = {}
		txt[1] = self.PrintName
		if (wireless) then table.insert( txt, "Wireless" ) end
		if (lan != "") then table.insert( txt, lan ) end
		if (wan != "") then table.insert( txt, wan ) end
		if (self:GetGVar( "noreg" )) then table.insert( txt, "Hardware Failure" ) end
		
		// Draw the label
		PCMod.Gui.DrawLabel( origin.x, origin.y, "ScoreboardText", txt, 10, Color( 50, 50, 50, 200 ), Color( 255, 255, 255, 255 ) )
	end

end
