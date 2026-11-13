// ---------------------------------------------------------------------------------------------------------
// sh_icmp.lua - one ICMP mechanism for ping and traceroute
//
// Ping and traceroute are the same probe: an echo request. A host or router
// answers an echo request addressed to it with an echo reply; a router whose
// TTL expires answers with time-exceeded. The originator (an OS) decides what
// the replies mean: an echo reply finishes a ping or is the final traceroute
// hop, while a time-exceeded reply records one intermediate hop and advances
// the probe.
//
// Wire body: { "icmp", type, session, seq, ... }
//   echo            session, seq, ttl           (ttl is informational)
//   echo-reply      session, seq, label
//   time-exceeded   session, seq, address, label
// The `session` id is chosen by the originator; responders echo it unchanged.
// A traceroute uses a numeric session (its trace handle); a ping uses a
// string session ("p1", "p2", ...) so the two never collide.
// ---------------------------------------------------------------------------------------------------------

PCMod = PCMod or {}
PCMod.ICMP = PCMod.ICMP or {}

local ICMP = PCMod.ICMP

ICMP.TAG = "icmp"
ICMP.Echo = "echo"
ICMP.EchoReply = "echo-reply"
ICMP.TimeExceeded = "time-exceeded"

function ICMP.Is( body )
	return ((type( body ) == "table") && (body[ 1 ] == ICMP.TAG))
end

function ICMP.Type( body )
	if (!ICMP.Is( body )) then return nil end
	return body[ 2 ]
end

function ICMP.IsEcho( body )
	return (ICMP.Type( body ) == ICMP.Echo)
end

function ICMP.IsEchoReply( body )
	return (ICMP.Type( body ) == ICMP.EchoReply)
end

function ICMP.IsTimeExceeded( body )
	return (ICMP.Type( body ) == ICMP.TimeExceeded)
end

// Echo request. For a traceroute, `seq` is also the probe number.
function ICMP.Request( session, seq, ttl )
	return { ICMP.TAG, ICMP.Echo, session, seq, ttl }
end

// Echo reply carrying the responder's label (host OS, BRTR, RTR, ...).
function ICMP.Reply( session, seq, label )
	return { ICMP.TAG, ICMP.EchoReply, session, seq, label }
end

// Time-exceeded report from a router that dropped the probe.
function ICMP.Expired( session, seq, address, label )
	return { ICMP.TAG, ICMP.TimeExceeded, session, seq, address, label }
end

function ICMP.Session( body )
	return body && body[ 3 ]
end

function ICMP.Seq( body )
	return tonumber( body && body[ 4 ] ) or 0
end

function ICMP.ReplyLabel( body )
	return body && body[ 5 ]
end

function ICMP.Address( body )
	return body && body[ 5 ]
end

function ICMP.ExpiredLabel( body )
	return body && body[ 6 ]
end