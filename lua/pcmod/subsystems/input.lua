
// Display subsystem for PCMod 2

SUBSYSTEM = PCMod.DeriveSubsystem( "base" )

SUBSYSTEM.NiceName = "Generic Input"
SUBSYSTEM.Name = "input"
SUBSYSTEM.Type = "input"
SUBSYSTEM.ID = 0
SUBSYSTEM.PortHook = "ps2"
SUBSYSTEM.PortID = 0

function SUBSYSTEM:Initialize()
	if (!self.Entity) then return end
	
	// Get our primary PS2 port
	local ports = self.Entity:Ports()
	for k, v in pairs( ports ) do
		if (v.Type == self.PortHook) then
			self.PortID = k
			break
		end
	end
end

function SUBSYSTEM:GetPort()
	if (!self.Entity) then return end
	return self.Entity:Ports()[ self.PortID ]
end

function SUBSYSTEM:DataRecieved( port, data )
	local pt = self.Entity:GetPorts()[ port ]
	if (!pt) then return end
	if (pt.Type == "vga") then
		if (data[1] == "keyboard_req") then
			PCMod.Msg( "Recieved keyboard lock request from VGA port!", true )
			self.Entity:PushData( self.Entity:GetPorts()[ self.PortID ], data ) -- Forward data to keyboard
		end
	end
end