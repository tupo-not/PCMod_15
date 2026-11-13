// ---------------------------------------------------------------------------------------------------------
// entities/pcmod_base/netidentity.lua - IPv4/IPv6 identity, interfaces and
// packet sending. Included by pcmod_base/shared.lua inside its SERVER block.
// ---------------------------------------------------------------------------------------------------------

		// -----------------------------------------------------------------------------------------------------
		// IPv4 addressing. Every interface is stored as one plain dotted quad:
		//   IP.LAN  - private LAN address (any RFC1918 block)
		//   IP.WAN  - routed WAN/backbone address (100.x.x.x by default)
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

		// Only the private LAN IPv4 (false on a device with no LAN side).
		function ENT:GetLanIPv4()
			return self:Data().IP.LAN
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

		// -----------------------------------------------------------------------------------------------------
		// Per-interface addresses (one entry per Ethernet port / Wi-Fi link).
		// The primary and WAN fields above stay as the routable identities; this
		// list lets the UI show every adapter, including two NICs on the same
		// subnet that share one address.
		// -----------------------------------------------------------------------------------------------------

		function ENT:Interfaces()
			local ip = self:Data().IP
			ip.Interfaces = ip.Interfaces or {}
			return ip.Interfaces
		end

		function ENT:SetInterface( port, info )
			if ((!port) || (!info)) then return end
			self:Interfaces()[ port ] = info
			self:UpdateInterfaceText()
		end

		function ENT:ClearInterface( port )
			local list = self:Interfaces()
			if (list[ port ]) then
				list[ port ] = nil
				self:UpdateInterfaceText()
			end
		end

		function ENT:ClearInterfaces()
			self:Data().IP.Interfaces = {}
			self:UpdateInterfaceText()
		end

		function ENT:GetInterfaceList()
			local out = {}
			for port, info in pairs( self:Interfaces() ) do
				out[ #out + 1 ] = {
					Port = port,
					IPv4 = info.IPv4,
					IPv6 = info.IPv6,
					Kind = info.Kind,
					MAC = info.MAC,
					Mask = info.Mask,
					MaskBits = info.MaskBits,
					Gateway4 = info.Gateway4,
					IPv6Prefix = info.IPv6Prefix,
					IPv6Gateway = info.IPv6Gateway,
					IPv6LinkLocal = info.IPv6LinkLocal,
				}
			end
			table.sort( out, function( a, b ) return (a.Port < b.Port) end )
			return out
		end

		function ENT:UpdateInterfaceText()
			self:SetNWString( "IP.Ifaces", PCMod.TableToString( self:GetInterfaceList() ) )
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

		// Address helpers: update the third/fourth octet of the current LAN
		// address, preserving the RFC1918 network the device already has.
		function ENT:SetSubnet( subnet )
			local ip = self:Data().IP
			if ((subnet == false) || (subnet == nil)) then
				ip.LAN = false
			else
				local p = ParseLanAddress( ip.LAN )
				local a, b = 192, 168
				if (p) then a, b = p.a, p.b end
				ip.LAN = tostring( a ) .. "." .. tostring( b ) .. "." .. tostring( subnet ) .. "." .. tostring( (p and p.add) or 1 )
			end
			self:SetIPText()
		end

		function ENT:SetIP( ip )
			local data = self:Data().IP
			if ((ip == false) || (ip == nil)) then
				data.LAN = false
			else
				local p = ParseLanAddress( data.LAN )
				local a, b, c = 192, 168, 0
				if (p) then a, b, c = p.a, p.b, p.c end
				data.LAN = tostring( a ) .. "." .. tostring( b ) .. "." .. tostring( c ) .. "." .. tostring( ip )
			end
			self:SetIPText()
		end

		// Configure a static LAN IP (any RFC1918 address). Pass "" or false to
		// clear it and fall back to DHCP. Returns false on a malformed address.
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
			// Per-interface addresses (two NICs on the same router, cable +
			// Wi-Fi, and so on). Every assigned interface stays reachable even
			// when another one owns the primary identity.
			for _, info in pairs( self:Interfaces() ) do
				if (PCMod.IPv6.Matches( addr, info.IPv4, info.IPv6 )) then return true end
			end
			return false
		end

		function ENT:GetSourceAddress( dest )
			// Answering on one of our own addresses (multi-homed devices
			// included): source from the exact address that was contacted so
			// the reply goes back out on the same identity.
			if (dest && self:IsAddressedTo( dest )) then return dest end
			// Pick the routable source: IPv6 for IPv6 destinations (LAN /64
			// first, then the backbone /32 identity), otherwise the plain IPv4
			// address (LAN first, WAN for a backbone-only device).
			if (dest && PCMod.IPv6.IsIPv6( dest )) then
				return self:GetIPv6() or self:GetBIPv6() or self:GetFullIP() or self:GetFullBIP()
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
				SourceMAC = self:EnsureInterfaceMAC( portid ),
				DestMAC = PCMod.MAC.BROADCAST,
			}
			// IP TTL travels with the frame until a router turns it into a
			// packet. data[3] is already used by switches for loop detection.
			if (ttl) then data[5] = ttl end
			// Simulate the one-way delay of the physical link the frame is
			// leaving on. The peer may be a switch, modem or router.
			local kind = PCMod.Latency && PCMod.Latency.KindForPort && PCMod.Latency.KindForPort( prt )
			if (!self.IsNetworkDevice) then
				local peer = prt.ConEnt
				local function deliver()
					if ((peer) && (peer:IsValid())) then peer:DataRecieved( portid2, data ) end
				end
				if (kind && PCMod.Latency.Deliver) then
					PCMod.Latency.Deliver( deliver, kind )
				else
					deliver()
				end
				// self:PushData
			else
				local function deliver()
					if ((self) && (self:IsValid())) then self:DataRecieved( portid, data ) end
				end
				if (kind && PCMod.Latency.Deliver) then
					PCMod.Latency.Deliver( deliver, kind )
				else
					deliver()
				end
			end
			return 0
		end
		
		
	-------------------------------------------------------------------------------------------------------------------------------------------------
	-- Entity Data Functions --
	-------------------------------------------------------------------------------------------------------------------------------------------------

