
// Display Driver for PCMod 2

DRV = PCMod.DeriveDriver( "base" )

DRV.NiceName = "Generic Display Driver"
DRV.Name = "gen_display"
DRV.Type = "display"
DRV.ID = 0
DRV.PortHook = "vga"
DRV.PortID = 0
DRV.SS = {}
// Round 34 (M-33): this was an undeclared global (it is not used anywhere
// else) - it belongs to the driver.
DRV.bekleniyor = 0

util.AddNetworkString("ekrantazele")

	
function DRV:Initialize()
	if (!self.Entity) then return end
	
	self.Entity:AddEHook( "driver", self.Name, "linked" )
	self.Entity:AddEHook( "driver", self.Name, "ss_inval" )
	self.Entity:AddEHook( "driver", self.Name, "turnoff" )
	
	// Get our primary VGA port
	local ports = self.Entity:Ports()
	for k, v in pairs( ports ) do
		if (v.Type == self.PortHook) then
			self.PortID = k
			break
		end
	end
end


function DRV:Think()
	//PCMod.Msg( "Display Driver Thinking...", true )

	
	
	local ss = self.Entity:ScreenSpace()
	if (ss != self.SS) then
		local prt = self:GetPort()
		
		if (!self.IsLaptop) then
			
			if (!prt) then
				PCMod.Msg( "Failed to locate port! (Display Driver)", true )
				return
			end
			
			PCMod.Msg( "Detected ScreenSpace update! Sending through vga... (" .. tostring( self.Entity:EntIndex() ) .. ")", true )
			
			self.Entity:PushData( prt, { "display", ss.Data } )
			
		else
			
			PCMod.Msg( "Detected ScreenSpace update! Sending to laptop hardware...(" .. tostring( self.Entity:EntIndex() ) .. ")", true )
			
			self.Entity:DataRecieved( nil, { "display", ss.Data } )
			
		end
		
		self.SS = ss
	end
end

function DRV:CallEvent( data )
	-- if ((!data) || (!data[1])) then return end
	if (!data) then return end
	
	if ((data.Event == "ss_inval") || ((data.Event == "linked") && (data[1] == self.PortID))) then
		PCMod.Msg( "Preparing to resend ScreenSpace!", true )
		self.SS = {} -- Hacky way of telling us to update
	end
	
	if (data.Event == "turnoff") then
		self:FullFlush()
	end
end

function DRV:GetPort()
	if (!self.Entity) then return end
	return self.Entity:Ports()[ self.PortID ]
end

function DRV:GetScreen()
	return self.Entity:ScreenSpace()
end


function DRV:FullFlush()
	local ss = self:GetScreen()
	if (!ss) then return end
	PCMod.Msg( "Performing full flush (ddriv)", true )
	ss:ClearAll()
	/*
	ss:AddDevice( "mainbackground",
		ss:MakeDevice( "panel", 0, 0, 1, 1, 
			{ Col = 
				{ r = 0, g = 0, b = 0 } 
			}, 1
		)
	)
	*/
	self:SetScreen( ss )
	self:CallEvent( { "ss_inval", 0 } )
end

function DRV:SetScreen( ss )
	PCMod.Msg( "Updating host screen!", true )
	self.Entity:UpdateScreenSpace( ss )
end

// Round 25 (M-04): "ekrantazele" is a CLIENT -> SERVER request to re-send a
// screenspace (the client side of it lives in cl_vgui.lua). It used to be accepted
// from ANY client for ANY machine: no sender check, no distance check, no rate
// limit - so a client could force the server to rebuild and re-broadcast other
// people's screens and spam the server console with print().
// The request is now only honoured when it comes from a valid player who can
// actually see that machine, and at most once every EKRAN_REFRESH_INTERVAL
// seconds per player. The rate limit is local to this channel on purpose -
// PCC_FLOOD is not touched (excluded topic).
local EKRAN_REFRESH_INTERVAL = 2
local ekranRefresh = {}

net.Receive("ekrantazele", function( len, ply )
	// SECURITY (stage 2, fix 1.4a): the net string is registered, so any client can
	// send this message - validate the entity before calling methods on it.
	if (!IsValid( ply ) || !ply:IsPlayer()) then return end
	local str = net.ReadEntity();
	if (!IsValid( str ) || !str.IsPCMod || !str.ScreenSpace) then return end
	// the requester has to be close enough to actually see that machine
	if ((str:GetPos() - ply:GetPos()):Length() > PCMod.Beam.Range_SS) then return end
	// local rate limit for this channel
	local now = CurTime()
	local last = ekranRefresh[ ply:SteamID() ]
	if ((last) && (now - last < EKRAN_REFRESH_INTERVAL)) then return end
	ekranRefresh[ ply:SteamID() ] = now
	local bilgi = str:ScreenSpace()
	str:UpdateScreenSpace( bilgi )
end)

// clean up the rate limit table when a player leaves the server
hook.Add( "PlayerDisconnected", "PCMod.EkranRefreshCleanup", function( ply )
	if (!IsValid( ply )) then return end
	ekranRefresh[ ply:SteamID() ] = nil
end )
