-- Multi-homed addressing: a LAN lease and a WAN/backbone lease coexist on a
-- machine with more than one network interface.
PCMod = {
	Msg = function() end,
	Data = {},
	IPv4 = {
		ParseLan = function( ip )
			local a, b, c, d = string.match( tostring( ip ), "^(%d+)%.(%d+)%.(%d+)%.(%d+)$" )
			if (!a) then return nil end
			return { full = ip, a = tonumber( a ), b = tonumber( b ), c = tonumber( c ), d = tonumber( d ), sub = tonumber( c ), add = tonumber( d ) }
		end,
		SameLan = function( a, b, bits )
			local pa = string.match( tostring( a ), "^(%d+%.%d+%.%d+)%." )
			local pb = string.match( tostring( b ), "^(%d+%.%d+%.%d+)%." )
			return (pa != nil) && (pa == pb)
		end,
	},
	IPv6 = {
		Format = function( g )
			return "fd00:" .. tostring( g[ 2 ] ) .. ":0:" .. tostring( g[ 4 ] ) .. "::" .. tostring( g[ 8 ] )
		end,
	},
}
dofile( "pcmod_sh_dhcp_client.lua" )

local function assertEq( a, b, m )
	if (a ~= b) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end
local function assertTrue( v, m )
	if (not v) then error( "FAILED: " .. m, 2 ) end
end

local function makeHost( ip )
	local ipdata = ip
	local ent = {}
	function ent:Data() return { IP = ipdata } end
	function ent:SetLanAddress( v ) ipdata.LAN = v or false end
	function ent:SetUpBB( v ) ipdata.UpBB = v end
	function ent:SetLanID( v ) ipdata.LanID = v end
	function ent:SetBSubnet( v ) ipdata.WanBB = v end
	function ent:SetBIP( v ) ipdata.WanHost = v end
	function ent:AddExtraIP( addr, upbb, lanid, router )
		ipdata.Extra = ipdata.Extra or {}
		ipdata.Extra[ #ipdata.Extra + 1 ] = { IPv4 = addr, UpBB = upbb, LanID = lanid, Router = router }
	end
	return ent, ipdata
end

-- A single-interface machine still swaps between LAN and WAN identities.
local single, singleIP = makeHost( { LAN = "192.168.0.2", Router = 10 } )
PCMod.DHCPClient.ApplyHost( single, { scope = "wan", ip = "100.0.7.12", bb = 7, host = 12, server = 11, upbb = 9, lanid = 9 } )
assertEq( singleIP.LAN, false, "single NIC: WAN lease clears the LAN address" )
assertEq( singleIP.WanBB, 7, "single NIC: backbone id applied" )
assertEq( singleIP.WanHost, 11, "single NIC: backbone host applied" )

-- With two interfaces, a WAN lease must not erase the LAN identity.
local multi, multiIP = makeHost( { LAN = "192.168.0.2", UpBB = 3, LanID = 5, Router = 10, Extra = {} } )
PCMod.Data[ 10 ] = { Ent = { IsValid = function() return true end } }
PCMod.DHCPClient.ApplyHost( multi, { scope = "wan", ip = "100.0.7.12", bb = 7, host = 12, server = 11, upbb = 9, lanid = 9 }, true )
assertEq( multiIP.LAN, "192.168.0.2", "multi NIC: LAN address survives the WAN lease" )
assertEq( multiIP.UpBB, 3, "multi NIC: LAN upstream backbone unchanged" )
assertEq( multiIP.LanID, 5, "multi NIC: LAN id unchanged" )
assertEq( multiIP.Router, 10, "multi NIC: LAN lease owner unchanged" )
assertEq( multiIP.WanBB, 7, "multi NIC: backbone id from the WAN lease" )
assertEq( multiIP.WanHost, 11, "multi NIC: backbone host from the WAN lease" )

-- A second LAN lease becomes a secondary without dropping the WAN identity.
PCMod.DHCPClient.ApplyHost( multi, { scope = "lan", ip = "10.0.0.2", upbb = 3, lanid = 5, server = 12 }, true )
assertEq( multiIP.LAN, "192.168.0.2", "multi NIC: first LAN stays primary" )
assertTrue( multiIP.Extra[ 1 ] != nil, "multi NIC: second LAN becomes a secondary" )
assertEq( multiIP.Extra[ 1 ].IPv4, "10.0.0.2", "multi NIC: secondary address recorded" )
assertEq( multiIP.WanBB, 7, "multi NIC: WAN identity survives a LAN lease" )

-- Two NICs may sit on two routers that both use the same subnet. Each lease is
-- still a separate interface address; neither may replace the other.
local same, sameIP = makeHost( { LAN = "192.168.0.2", UpBB = 3, LanID = 5, Router = 10, Extra = {} } )
PCMod.DHCPClient.ApplyHost( same, { scope = "lan", ip = "192.168.0.9", upbb = 3, lanid = 5, server = 13 }, true )
assertEq( sameIP.LAN, "192.168.0.2", "same subnet: first adapter stays primary" )
assertEq( sameIP.Extra[ 1 ].IPv4, "192.168.0.9", "same subnet: second adapter keeps its address" )

print( "ALL MULTIHOME TESTS PASSED" )
