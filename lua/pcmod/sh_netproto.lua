// ---------------------------------------------------------------------------------------------------------
// sh_netproto.lua - wire protocol formats shared by every network device
//
// Kept deliberately small: DHCP (DORA), ARP and routing hellos are plain
// application bodies carried inside the existing PCMod frame ("sendpacket").
// No subsystem owns another; switches forward these frames like any other.
// ---------------------------------------------------------------------------------------------------------

PCMod = PCMod or {}
PCMod.Net = PCMod.Net or {}

PCMod.Net.DHCPServerPort = 67
PCMod.Net.DHCPClientPort = 68
PCMod.Net.BroadcastIP = "255.255.255.255"
PCMod.Net.LeaseTime = 3600
PCMod.Net.LeaseOfferTime = 30
PCMod.Net.ArpTime = 60

// Real time, so leases survive a map restart instead of rebasing on CurTime().
function PCMod.Net.Now()
	return os.time()
end

function PCMod.Net.DHCP( kind, xid, server, payload )
	return { "dhcp", kind, xid, server, payload }
end

function PCMod.Net.DHCPDiscover( xid, mac )
	return PCMod.Net.DHCP( "discover", xid, nil, { mac = mac } )
end

function PCMod.Net.DHCPOffer( xid, server, config )
	return PCMod.Net.DHCP( "offer", xid, server, config )
end

function PCMod.Net.DHCPRequest( xid, server, mac )
	return PCMod.Net.DHCP( "request", xid, server, { mac = mac } )
end

function PCMod.Net.DHCPAck( xid, server, config )
	return PCMod.Net.DHCP( "ack", xid, server, config )
end

function PCMod.Net.DHCPNack( xid, server )
	return PCMod.Net.DHCP( "nack", xid, server, {} )
end

function PCMod.Net.DHCPRelease( mac, server )
	return PCMod.Net.DHCP( "release", nil, server, { mac = mac } )
end

function PCMod.Net.ARPRequest( targetIP, sourceIP, sourceMAC )
	return { "arp", "request", targetIP, sourceIP, sourceMAC }
end

function PCMod.Net.ARPReply( targetIP, sourceIP, sourceMAC )
	return { "arp", "reply", targetIP, sourceIP, sourceMAC }
end

function PCMod.Net.Hello( bb, ip, mac, dv, prefixes )
	return { "hello", bb, ip, mac, dv or {}, prefixes or {} }
end

function PCMod.Net.IsDHCP( body )
	return (istable( body ) && (body[1] == "dhcp"))
end

function PCMod.Net.IsARP( body )
	return (istable( body ) && (body[1] == "arp"))
end

function PCMod.Net.IsHello( body )
	return (istable( body ) && (body[1] == "hello"))
end

// A DHCP server/lease identity. MAC strings are unique per interface.
function PCMod.Net.MACKey( mac )
	return (PCMod.MAC && PCMod.MAC.Normalize( mac )) or nil
end

function PCMod.Net.NewXID()
	PCMod.Net.LastXID = (PCMod.Net.LastXID or math.random( 1, 60000 )) + 1
	if (PCMod.Net.LastXID > 2147483647) then PCMod.Net.LastXID = 1 end
	return PCMod.Net.LastXID
end
