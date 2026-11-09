-- End-to-end DORA through two pure-L2 bridges (switch -> modem -> backbone).
-- Regression: a laptop behind switch/modem used to get no address, then a LAN
-- address on Renew. Addressing is now role-blind DHCP over pure L2.
function string.Trim( s )
	return (string.gsub( s, "^%s*(.-)%s*$", "%1" ))
end
function string.Left( s, n ) return string.sub( s, 1, n ) end
function string.Right( s, n ) return string.sub( s, math.max( 1, #s - n + 1 ) ) end
function string.Explode( sep, str )
	local out = {}
	if (str == nil) then return out end
	if (sep == "") then
		for i = 1, #str do table.insert( out, string.sub( str, i, i ) ) end
		return out
	end
	local start = 1
	while true do
		local a, b = string.find( str, sep, start, true )
		if (not a) then
			table.insert( out, string.sub( str, start ) )
			break
		end
		table.insert( out, string.sub( str, start, a - 1 ) )
		start = b + 1
	end
	return out
end
function string.Count( str, char )
	local r = 0
	for i = 1, #str do if (string.sub( str, i, i ) == char) then r = r + 1 end end
	return r
end
function table.Copy( t )
	if (type( t ) ~= "table") then return t end
	local o = {}
	for k, v in pairs( t ) do o[ k ] = table.Copy( v ) end
	return o
end
function table.HasValue( t, v )
	for _, x in pairs( t ) do if (x == v) then return true end end
	return false
end

PCMod = {
	Msg = function() end,
	Cfg = { MaxNetworkPid = 500, MaxNetworkPass = 10, WirelessRange = 0, DefaultTTL = 64 },
	Network = { Packets = {}, NextSwitchFrame = 0 },
	DeriveDriver = function() return {} end,
}
math.Clamp = function( v, a, b ) if (v < a) then return a end if (v > b) then return b end return v end
function istable( v ) return type( v ) == "table" end
CurTime = function() return 0 end
timer = { Simple = function() end }

dofile( "pcmod_sh_common.lua" )
dofile( "pcmod_sh_netproto.lua" )
dofile( "pcmod_sh_dhcp_server.lua" )
dofile( "pcmod_sh_dhcp_client.lua" )
dofile( "pcmod_sh_arp.lua" )
dofile( "pcmod_sh_ndp.lua" )
dofile( "pcmod_sh_l2.lua" )
dofile( "pcmod_sh_routing.lua" )
dofile( "pcmod_drv_router.lua" )

local function assertEq( a, b, m )
	if (a ~= b) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end
local function assertTrue( v, m )
	if (not v) then error( "FAILED: " .. m, 2 ) end
end

local nextIdx = 100
local function newPort() return { Connected = false, ConEnt = nil, RemotePort = nil, Type = "network" } end

local function mkNode( mac, portcount, portmacs )
	local o = { mac = mac, MacTable = {}, SwitchFrames = {}, SwitchFrameCount = 0 }
	o.ports = {}
	for i = 1, portcount do o.ports[ i ] = newPort() end
	o.portmacs = portmacs or {}
	nextIdx = nextIdx + 1
	o.idx = nextIdx
	function o:IsValid() return true end
	function o:EntIndex() return self.idx end
	function o:GetMAC() return self.mac end
	function o:GetPortMAC( p ) return self.portmacs[ p ] or self.mac end
	function o:Ports() return self.ports end
	function o:PushData( port, data )
		if (type( port ) == "table") then
			for k, v in pairs( self.ports ) do if (v == port) then port = k break end end
		end
		local prt = self.ports[ port ]
		if ((!prt) || (!prt.Connected) || (!prt.ConEnt)) then return 2 end
		return prt.ConEnt:GivenData( prt.RemotePort, data )
	end
	function o:GivenData( port, data ) return self:DataRecieved( port, data ) end
	return o
end

local function connect( a, ap, b, bp )
	a.ports[ ap ].Connected = true
	a.ports[ ap ].ConEnt = b
	a.ports[ ap ].RemotePort = bp
	b.ports[ bp ].Connected = true
	b.ports[ bp ].ConEnt = a
	b.ports[ bp ].RemotePort = ap
end

-- ---------------------------------------------------------------------------
-- Topology: laptop -- switch -- modem -- backbone
-- ---------------------------------------------------------------------------
local laptop = mkNode( "AA:BB:CC:00:00:01", 1 )
local switch = mkNode( "AA:BB:CC:00:00:02", 3, { "AA:BB:CC:00:00:12", "AA:BB:CC:00:00:22", "AA:BB:CC:00:00:32" } )
local modem  = mkNode( "AA:BB:CC:00:00:03", 2, { "AA:BB:CC:00:00:13", "AA:BB:CC:00:00:23" } )

local routerData = {
	IP = { WanBB = 7, WanHost = 0, UpBB = 7, LanID = 0 },
	RouterCfg = { WanDHCPStart = 12, WanDHCPEnd = 254 },
}
local backbone = mkNode( "AA:BB:CC:00:00:04", 1, { "AA:BB:CC:00:00:14" } )
function backbone:GetClass() return "pcmod_brouter" end
function backbone:Data() return routerData end
function backbone:GetBSubnet() return 7 end
function backbone:GetFullBIP() return "100.0.7.1" end
function backbone:GetFullIP() return false end
function backbone:GetSourceAddress() return "100.0.7.1" end

connect( laptop, 1, switch, 1 )
connect( switch, 2, modem, 1 )
connect( modem, 2, backbone, 1 )

switch.DataRecieved = function( self, port, data ) return PCMod.L2.Receive( self, port, data ) end
modem.DataRecieved = function( self, port, data ) return PCMod.L2.Receive( self, port, data ) end

-- Reuse the real router driver methods (DHCP server side) on a fake entity.
local rdrv = {}
for k, v in pairs( DRV ) do rdrv[ k ] = v end
rdrv.Entity = backbone
rdrv.NPorts = {}
rdrv.OPorts = { 1 }
rdrv.ArpCache = {}
rdrv.PrefixRoutes = {}
rdrv.Neighbors = {}
rdrv.NeighborMAC = {}
rdrv.Uplink = nil

local function appOf( data )
	if ((!istable( data )) || (data[ 1 ] != "sendpacket") || (!istable( data[ 2 ]))) then return nil end
	return data[ 2 ][ 4 ], data[ 4 ] or {}
end

backbone.DataRecieved = function( self, port, data )
	local app, macs = appOf( data )
	if ((!app) || (!PCMod.Net.IsDHCP( app ))) then return end
	if (app[ 2 ] == "discover") then return rdrv:DHCPServerReceive( port, app, macs ) end
	if (app[ 2 ] == "request") then return rdrv:DHCPServerRequest( port, app, macs ) end
end

-- ---------------------------------------------------------------------------
-- Host DHCP client on the laptop
-- ---------------------------------------------------------------------------
local hostData = { IP = {} }
function laptop:Data() return hostData end
function laptop:EnsureMAC() return self.mac end
function laptop:SetBSubnet( v ) hostData.IP.WanBB = v end
function laptop:SetBIP( v ) hostData.IP.WanHost = v end
function laptop:SetUpBB( v ) hostData.IP.UpBB = v end
function laptop:SetLanID( v ) hostData.IP.LanID = v end
function laptop:SetLanAddress( v ) hostData.IP.LAN = v or false end

local owner = { Entity = laptop, LastDHCP = nil, DHPCState = nil }
laptop.DataRecieved = function( self, port, data )
	local app = appOf( data )
	if (app && PCMod.Net.IsDHCP( app )) then PCMod.DHCPClient.Handle( owner, app ) end
end

local sent = 0
PCMod.DHCPClient.Start( owner, {
	send = function( body )
		sent = sent + 1
		laptop:PushData( 1, {
			"sendpacket",
			{ "0.0.0.0", PCMod.Net.BroadcastIP, PCMod.Net.DHCPServerPort, body },
			nil,
			{ SourceMAC = laptop:GetMAC(), DestMAC = PCMod.MAC.BROADCAST },
		} )
	end,
	apply = function( cfg ) PCMod.DHCPClient.ApplyHost( laptop, cfg ) end,
} )

assertEq( sent, 2, "discover and request were sent" )
assertTrue( owner.LastDHCP != nil, "host completed DORA" )
assertEq( owner.LastDHCP.scope, "wan", "backbone answers with a WAN lease" )
assertEq( owner.LastDHCP.address, "100.0.7.12", "laptop gets a backbone host address" )
assertEq( hostData.IP.WanBB, 7, "WAN lease records the backbone id" )
assertEq( hostData.IP.WanHost, 11, "WAN lease records the zero-based host" )
assertTrue( hostData.IP.LAN == false, "laptop has no private LAN address" )

-- A second host on the same switch must get a different address.
local laptop2 = mkNode( "AA:BB:CC:00:00:05", 1 )
local hostData2 = { IP = {} }
function laptop2:Data() return hostData2 end
function laptop2:EnsureMAC() return self.mac end
function laptop2:SetBSubnet( v ) hostData2.IP.WanBB = v end
function laptop2:SetBIP( v ) hostData2.IP.WanHost = v end
function laptop2:SetUpBB( v ) hostData2.IP.UpBB = v end
function laptop2:SetLanID( v ) hostData2.IP.LanID = v end
function laptop2:SetLanAddress( v ) hostData2.IP.LAN = v or false end
connect( laptop2, 1, switch, 3 )
local owner2 = { Entity = laptop2, LastDHCP = nil }
laptop2.DataRecieved = function( self, port, data )
	local app = appOf( data )
	if (app && PCMod.Net.IsDHCP( app )) then PCMod.DHCPClient.Handle( owner2, app ) end
end
PCMod.DHCPClient.Start( owner2, {
	send = function( body )
		laptop2:PushData( 1, {
			"sendpacket",
			{ "0.0.0.0", PCMod.Net.BroadcastIP, PCMod.Net.DHCPServerPort, body },
			nil,
			{ SourceMAC = laptop2:GetMAC(), DestMAC = PCMod.MAC.BROADCAST },
		} )
	end,
	apply = function( cfg ) PCMod.DHCPClient.ApplyHost( laptop2, cfg ) end,
} )
assertTrue( owner2.LastDHCP != nil, "second host completed DORA" )
assertEq( owner2.LastDHCP.address, "100.0.7.13", "second host gets the next free address" )
assertTrue( owner2.LastDHCP.address ~= owner.LastDHCP.address, "two hosts never share an address" )

-- Replacing a device on the same switch port must not reuse a still-active
-- lease: the disconnected host's lease stays valid until it expires/releases.
switch.ports[ 1 ].Connected = false
switch.ports[ 1 ].ConEnt = nil
switch.ports[ 1 ].RemotePort = nil
laptop.ports[ 1 ].Connected = false
laptop.ports[ 1 ].ConEnt = nil
laptop.ports[ 1 ].RemotePort = nil

local tower = mkNode( "AA:BB:CC:00:00:06", 1 )
local towerData = { IP = {} }
function tower:Data() return towerData end
function tower:EnsureMAC() return self.mac end
function tower:SetBSubnet( v ) towerData.IP.WanBB = v end
function tower:SetBIP( v ) towerData.IP.WanHost = v end
function tower:SetUpBB( v ) towerData.IP.UpBB = v end
function tower:SetLanID( v ) towerData.IP.LanID = v end
function tower:SetLanAddress( v ) towerData.IP.LAN = v or false end
connect( tower, 1, switch, 1 )
local owner3 = { Entity = tower, LastDHCP = nil }
tower.DataRecieved = function( self, port, data )
	local app = appOf( data )
	if (app && PCMod.Net.IsDHCP( app )) then PCMod.DHCPClient.Handle( owner3, app ) end
end
PCMod.DHCPClient.Start( owner3, {
	send = function( body )
		tower:PushData( 1, {
			"sendpacket",
			{ "0.0.0.0", PCMod.Net.BroadcastIP, PCMod.Net.DHCPServerPort, body },
			nil,
			{ SourceMAC = tower:GetMAC(), DestMAC = PCMod.MAC.BROADCAST },
		} )
	end,
	apply = function( cfg ) PCMod.DHCPClient.ApplyHost( tower, cfg ) end,
} )
assertTrue( owner3.LastDHCP != nil, "replacement host completed DORA" )
assertEq( owner3.LastDHCP.address, "100.0.7.14", "replacement host gets a fresh address, not the old lease" )


-- The switch and modem stay pure L2: MAC learning only, no IP/DHCP state.
assertTrue( switch.IPTable == nil, "switch keeps no IP table" )
assertTrue( modem.IPTable == nil, "modem keeps no IP table" )
assertTrue( switch.CollectSegment == nil, "switch has no topology walk" )
assertTrue( modem.GetBridgePeers == nil, "modem has no topology relay" )
assertTrue( PCMod.L2.PortForMAC( switch, laptop:GetMAC() ) == 1, "switch learned the laptop MAC" )
assertTrue( PCMod.L2.PortForMAC( modem, laptop:GetMAC() ) == 1, "modem learned the laptop MAC" )

-- A Released lease frees the address for the next discover.
PCMod.DHCPServer.Release( rdrv, laptop:GetMAC() )
assertTrue( PCMod.DHCPServer.Find( rdrv, "wan", laptop:GetMAC() ) == nil, "release dropped the lease" )

-- Static reservations still win over the dynamic pool.
assertTrue( rdrv:AddStaticLease( "100.0.7.30", "AA:BB:CC:00:00:99" ), "static reservation accepted" )
local rec = PCMod.DHCPServer.Offer( rdrv, "wan", "AA:BB:CC:00:00:99", 9001 )
assertEq( rec.ip, "100.0.7.30", "reserved MAC gets its static address" )
assertTrue( rdrv:DeleteStaticLease( 1 ), "reservation deleted" )
PCMod.DHCPServer.Release( rdrv, "AA:BB:CC:00:00:99" )

-- ---------------------------------------------------------------------------
-- LAN scope: a host cabled to a LAN router gets a private 192.168 lease.
-- ---------------------------------------------------------------------------
local lanRouter = mkNode( "AA:BB:CC:00:01:01", 1, { "AA:BB:CC:00:01:11" } )
local lanData = {
	IP = { LAN = "192.168.5.1", UpBB = 7, LanID = 12 },
	RouterCfg = { LanNet = 5, DHCPStart = 2, DHCPEnd = 254 },
}
function lanRouter:GetClass() return "pcmod_router" end
function lanRouter:Data() return lanData end
function lanRouter:GetBSubnet() return 7 end
function lanRouter:GetFullIP() return "192.168.5.1" end
function lanRouter:GetFullBIP() return false end

local lrdrv = {}
for k, v in pairs( DRV ) do lrdrv[ k ] = v end
lrdrv.Entity = lanRouter
lrdrv.NPorts = { 1 }
lrdrv.OPorts = {}
lrdrv.ArpCache = {}
function lanRouter:DataRecieved( port, data )
	local app, macs = appOf( data )
	if ((!app) || (!PCMod.Net.IsDHCP( app ))) then return end
	if (app[ 2 ] == "discover") then return lrdrv:DHCPServerReceive( port, app, macs ) end
	if (app[ 2 ] == "request") then return lrdrv:DHCPServerRequest( port, app, macs ) end
end

local lanHost = mkNode( "AA:BB:CC:00:01:02", 1 )
local lanHostData = { IP = { Add = nil, Sub = nil } }
function lanHost:Data() return lanHostData end
function lanHost:EnsureMAC() return self.mac end
function lanHost:SetSubnet( s )
	lanHostData.IP.Sub = s or false
	if (lanHostData.IP.Add) then
		lanHostData.IP.LAN = "192.168." .. tostring( s ) .. "." .. tostring( lanHostData.IP.Add )
	end
end
function lanHost:SetIP( h )
	lanHostData.IP.Add = h or false
	if (lanHostData.IP.Sub) then
		lanHostData.IP.LAN = "192.168." .. tostring( lanHostData.IP.Sub ) .. "." .. tostring( h )
	end
end
function lanHost:SetUpBB( v ) lanHostData.IP.UpBB = v end
function lanHost:SetLanID( v ) lanHostData.IP.LanID = v end
function lanHost:SetLanAddress( v ) lanHostData.IP.LAN = v or false end
function lanHost:AddExtraIP( addr, ub, lid, r )
	lanHostData.IP.Extra = lanHostData.IP.Extra or {}
	table.insert( lanHostData.IP.Extra, { IPv4 = addr, UpBB = ub, LanID = lid, Router = r } )
end
function lanHost:ReleaseExtraIP( addr )
	local list = lanHostData.IP.Extra or {}
	for i, ex in ipairs( list ) do
		if (ex.IPv4 == addr) then table.remove( list, i ) return true end
	end
	return false
end

connect( lanHost, 1, lanRouter, 1 )

local lanOwner = { Entity = lanHost, LastDHCP = nil }
function lanHost:DataRecieved( port, data )
	local app = appOf( data )
	if (app && PCMod.Net.IsDHCP( app )) then PCMod.DHCPClient.Handle( lanOwner, app ) end
end
PCMod.DHCPClient.Start( lanOwner, {
	send = function( body )
		lanHost:PushData( 1, {
			"sendpacket",
			{ "0.0.0.0", PCMod.Net.BroadcastIP, PCMod.Net.DHCPServerPort, body },
			nil,
			{ SourceMAC = lanHost:GetMAC(), DestMAC = PCMod.MAC.BROADCAST },
		} )
	end,
	apply = function( cfg ) PCMod.DHCPClient.ApplyHost( lanHost, cfg ) end,
} )
assertEq( lanOwner.LastDHCP.scope, "lan", "LAN router answers with a LAN lease" )
assertEq( lanOwner.LastDHCP.address, "192.168.5.2", "first LAN host is .2 on the router's subnet" )
assertEq( lanHostData.IP.LAN, "192.168.5.2", "LAN host address applied" )
assertEq( lanHostData.IP.UpBB, 7, "LAN lease carries the upstream backbone" )
assertEq( lanHostData.IP.LanID, 12, "LAN lease carries the /64 id" )

-- Replacing/changing the router but keeping the same LAN must re-take the
-- address as the primary, not stack it as an ALT/secondary.
lanHostData.IP.Router = 999
PCMod.DHCPClient.ApplyHost( lanHost, {
	ip = "192.168.5.2", scope = "lan", upbb = 8, lanid = 20, server = 1001,
	maskbits = 24, netmask = "255.255.255.0", gateway = "192.168.5.1",
} )
assertEq( lanHostData.IP.LAN, "192.168.5.2", "same LAN keeps the primary address" )
assertEq( lanHostData.IP.Router, 1001, "primary lease owner moves to the new router" )
assertEq( lanHostData.IP.LanID, 20, "primary /64 id follows the new router" )
assertEq( #( lanHostData.IP.Extra or {} ), 0, "same LAN is not added as a secondary" )

-- A genuinely different LAN still becomes a secondary address.
PCMod.DHCPClient.ApplyHost( lanHost, {
	ip = "192.168.9.5", scope = "lan", upbb = 9, lanid = 21, server = 1002,
	maskbits = 24, netmask = "255.255.255.0", gateway = "192.168.9.1",
} )
assertEq( lanHostData.IP.LAN, "192.168.5.2", "different LAN leaves the primary intact" )
assertEq( #lanHostData.IP.Extra, 1, "different LAN becomes a secondary address" )
assertEq( lanHostData.IP.Extra[ 1 ].IPv4, "192.168.9.5", "secondary address recorded" )

-- A LAN static reservation is honoured and skipped by the dynamic pool.
assertTrue( lrdrv:AddStaticLease( "192.168.5.30", "AA:BB:CC:00:01:99" ), "LAN static reservation accepted" )
local lanRec = PCMod.DHCPServer.Offer( lrdrv, "lan", "AA:BB:CC:00:01:99", 9002 )
assertEq( lanRec.ip, "192.168.5.30", "reserved LAN MAC gets its address" )
local dynLan = PCMod.DHCPServer.Offer( lrdrv, "lan", "AA:BB:CC:00:01:98", 9003 )
assertEq( dynLan.ip, "192.168.5.3", "dynamic LAN lease skips the reservation" )
assertTrue( lrdrv:DeleteStaticLease( 1 ), "LAN reservation deleted" )
PCMod.DHCPServer.Release( lrdrv, "AA:BB:CC:00:01:99" )
PCMod.DHCPServer.Release( lrdrv, "AA:BB:CC:00:01:98" )

print( "mock_dora PASSED" )
