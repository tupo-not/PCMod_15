
// ChatServ Program for PCMod 2 \\

PROG.Name = "chatserv"
PROG.Author = "[GU]thomasfn"
PROG.Title = "ChatServ"
PROG.Icon = "app"
PROG.OS = "personal"

PROG.SimpleMode = true -- Let the base do it's stuff, but we override our own stuff too

PROG.DeviceLink = "window_chatserv" -- This is the main window
PROG.DeviceName = "window_chatserv"
// The connection form is a different device type, so it keeps its own key.
// The window manager finds whichever one is active by its program owner.
PROG.ConnectKey = "window_chatserv_connect"
PROG.DeviceData = {}

PROG.Nick = "Unknown"
PROG.IP = "127.0.0.1"

PROG.MLimit = 10

// ChatServ has two window states: the connection form (1) and the connected
// chat (2). They use different device types/keys, so entering a state removes
// both entries and lets the client build the right window. The window manager
// finds the active one by program owner, so either one can be moved or resized.
function PROG:TriggerState( st )
	if ((st == 1) || (st == 2)) then
		local ss = self:GetScreenSpace()
		if (ss) then
			ss:RemoveDevice( self.DeviceName )
			ss:RemoveDevice( self.ConnectKey )
			self:SetScreenSpace( ss )
		end
		if (st == 2) then
			self:UpdateSS()
			return
		end
	end
	self:BaseTriggerState( st )
end

function PROG:BuildWindow()
	if (self.State == 1) then
		return {
			Type = self.ConnectKey,
			Key = self.ConnectKey,
			Data = self.DeviceData,
			Drag = true,
			Resize = true,
			Prepare = function( prog, data )
				if (data.Msgs) then data.Msgs = {} end
			end
		}
	end
	if (self.State == 2) then
		return {
			Type = self.DeviceLink,
			Key = self.DeviceName,
			Data = self.DeviceData,
			Drag = true,
			Resize = true,
			Prepare = function( prog, data )
				if (prog.ShouldClear) then data.Msgs = {} end
			end,
			After = function( prog, dev )
				if (prog.ShouldClear) then
					dev.Msgs = {}
					prog.ShouldClear = nil
				end
			end
		}
	end
	return nil
end

function PROG:DoCommand( com, args )
	if (com == "exit") then
		self:Exit()
	end
	if (self.State == 1) then
		if (com == "setnick") then
			if (args[1]) then
				self.Nick = args[1]
				self.DeviceData.Nk = args[1]
				self:UpdateSS()
			end
		end
		if (com == "connect") then
			if ((args[1]) && (args[2]) && (PCMod.IPv6.IsIP( args[2] ))) then
				self:DoCommand( "setnick", { args[1] } )
				self.IP = args[2]
				self.DeviceData.IP = args[2]
				self.DeviceData.St = 21 -- Waiting for response...
				self.ShouldClear = true
				self:UpdateSS()
				self:GetOS():SendNetMessage( self.IP, 72, { "netChat_Register", self.Nick } )
			end
		end
	end
	if (self.State == 2) then
		if (com == "disconnect") then
			self:GetOS():SendNetMessage( self.IP, 72, { "netChat_Unregister" } )
			self.DeviceData.Msgs = {}
			self.DeviceData.St = nil
			self:SetState( 1 )
		end
		if (com == "msg") then
			local msg = table.concat( args, " " )
			//self:AddMessage( self.Nick .. ": " .. msg )
			self:GetOS():SendNetMessage( self.IP, 72, { "netChat_Message", msg } )
		end
	end
end

function PROG:OnStart()
	self:GetOS():OpenNetPort( 72, "prog", "chatserv" )
	self.DeviceData.Msgs = {}
	// Show the last identity/address the player used on the connection form.
	if ((self.Nick) && (self.Nick != "Unknown")) then self.DeviceData.Nk = self.Nick end
	if ((self.IP) && (self.IP != "127.0.0.1")) then self.DeviceData.IP = self.IP end
end

function PROG:OnEnd()
	self:GetOS():SendNetMessage( self.IP, 72, { "netChat_Unregister" } )
	self:GetOS():CloseNetPort( 72 )
	self.DeviceData.Msgs = {}
	self.DeviceData.St = nil
end

function PROG:ProcessPacket( pt, dat, hdl )
	PCMod.Msg( "ChatServ recieved msg! (" .. dat[1] .. ")", true )
	if (pt == 72) then
		if (self.State == 1) then
			if (dat[1] == "netChat_Register_Success") then
				self:SetState( 2 )
				self:AddMessage( "Connected to " .. self.IP .. "!" )
			end
			if (dat[1] == "netChat_Register_Fail") then
				self.DeviceData.St = 27 -- Failed to connect!
				self:UpdateSS()
			end
			if (dat[1] == "netPortClosed") then
				self.DeviceData.St = 25 -- Target port closed!
				self:UpdateSS()
			end
			if (dat[1] == "netPortLocked") then
				self.DeviceData.St = 26 -- Target port locked!
				self:UpdateSS()
			end
		end
		if (self.State == 2) then
			if (dat[1] == "netChat_Message_Cl") then
				self:AddMessage( dat[2] )
			end
			if (dat[1] == "netPortClosed") then
				self:AddMessage( 25 ) -- Target port closed!
			end
			if (dat[1] == "netPortLocked") then
				self:AddMessage( 26 ) -- Target port locked!
			end
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
	self:UpdateSS()
end