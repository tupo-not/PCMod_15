
// P2P Chat Program for PCMod 2 \\

PROG.Name = "p2pchat"
PROG.Author = "[GU]thomasfn"
PROG.Title = "P2P Chat"
PROG.Icon = "app"
PROG.OS = "personal"

PROG.SimpleMode = true

PROG.DeviceLink = "window_p2pchat"
PROG.DeviceName = "window_p2pchat"
PROG.DeviceData = {}

PROG.Nick = "Unknown"
PROG.IP = "127.0.0.1"

PROG.MLimit = 10

// IsSelfAddress - Is the given IP this very program?
// Round 22: a packet addressed to us comes back to us, so the local echo would
// store every message twice. That happens for two addresses:
//   - 127.0.0.1 - the network driver short-circuits it back to this program
//     (drv_network.lua:31-40);
//   - our OWN in-game IP - the router finds this PC on its own LAN and delivers
//     the packet right back to us (drv_router.lua HasPC -> pcmod_base GivenData:
//     "packet.Dest == self:GetFullIP()").
// For any other address the packet leaves the PC, so the echo is needed.
function PROG:IsSelfAddress( ip )
	if (PCMod.IPv6.IsLoopback( ip )) then return true end
	local ent = self.Entity
	if ((!ent) || (!ent:IsValid())) then return false end
	// Accept both the IPv4 and the emulated IPv6 form of our own address.
	return ent:IsAddressedTo( ip )
end

function PROG:DoCommand( com, args )
	if (com == "exit") then
		self:Exit()
	end
	if (com == "setnick") then
		if (args[1]) then
			self.Nick = args[1]
			self.DeviceData.Nk = args[1]
			self:UpdateSS()
		end
	end
	if (com == "setip") then
		if ((args[1]) && (PCMod.IPv6.IsIP( args[1] ))) then
			self.IP = args[1]
			self.DeviceData.IP = args[1]
			self:UpdateSS()
		end
	end
	if (com == "msg") then
		if (PCMod.IPv6.IsIP( self.IP ) && args[1]) then
			local msg = table.concat( args, " " )
			// Round 21/22: the local echo is only needed for a REAL peer. Sending to
			// 127.0.0.1 (loopback) or to our own in-game IP brings the packet back
			// to this program, and the echo would store every message twice.
			if (!self:IsSelfAddress( self.IP )) then
				self:AddMessage( self.Nick .. ": " .. msg )
			end
			self:GetOS():SendNetMessage( self.IP, 75, { "netChat_P2P", self.Nick, msg } )
		end
	end
end

function PROG:OnStart()
	self:GetOS():OpenNetPort( 75, "prog", "p2pchat" )
	self.DeviceData.Msgs = {}
end

function PROG:OnEnd()
	self:GetOS():CloseNetPort( 75 )
	self.DeviceData.Msgs = {}
end

function PROG:ProcessPacket( pt, dat, hdl )
	PCMod.Msg( "P2P Chat recieved msg! (" .. dat[1] .. ")", true )
	if (pt == 75) then
		if (dat[1] == "netChat_P2P") then
			self:AddMessage( dat[2] .. ": " .. dat[3] )
		end
		if (dat[1] == "netPortClosed") then
			self:AddMessage( 25 ) -- Target port closed!
		end
		if (dat[1] == "netPortLocked") then
			self:AddMessage( 26 ) -- Target port locked!
		end
	end
end

function PROG:MessageFailed( handle, code, olddat )
	
end

function PROG:AddMessage( msg )
	local oldmsgs = self.DeviceData.Msgs
	if (type(msg) == "string") then
		msg = string.Replace( msg, self.Nick, "/M" )
	end
	table.insert( oldmsgs, msg )
	if (#oldmsgs > self.MLimit) then
		local tm = #oldmsgs - self.MLimit
		local cnt
		for cnt=1,tm do
			table.remove( oldmsgs, 1 )
		end
	end
	self.DeviceData.Msgs = oldmsgs
	self:UpdateSS()
end