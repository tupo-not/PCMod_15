
// Sound subsystem for PCMod 2
// Controls the sound

SUBSYSTEM = PCMod.DeriveSubsystem( "base" )

SUBSYSTEM.NiceName = "Sound Control"
SUBSYSTEM.Name = "sound"
SUBSYSTEM.Type = "sound"

SUBSYSTEM.SndPorts = {}

function SUBSYSTEM:Initialize()
	if (!self.Entity) then return end
	
	self.Entity:AddEHook( "subsystem", self.Name, "linked" )
	self.Entity:AddEHook( "subsystem", self.Name, "unlinked" )
	self.Entity:AddEHook( "subsystem", self.Name, "snd_stop" )
	self.Entity:AddEHook( "subsystem", self.Name, "snd_play" )
	
	for k, v in pairs( self.Entity:Ports() ) do
		if (v.Type == "minijack") then
			table.insert( self.SndPorts, k )
		end
	end
end

function SUBSYSTEM:CallEvent( data )
	if ((!data) || (!data.Event)) then return end
	local e = data.Event
	PCMod.Msg( "Sound subsystem CallEvent called! (" .. e .. ")", true )
	if (e == "snd_stop") then
		local dat = { "snd_stop" }
		for _, v in pairs( self.SndPorts ) do
			local pt = self.Entity:Ports()[ v ]
			self.Entity:PushData( pt, dat )
		end
		return
	end
	if (e == "snd_play") then
		local dat = { "snd_play", data[1] }
		for _, v in pairs( self.SndPorts ) do
			local pt = self.Entity:Ports()[ v ]
			self.Entity:PushData( pt, dat )
		end
		return
	end
end

function SUBSYSTEM:PlaySound( snd )
	self:CallEvent( { Event = "snd_play", [1] = snd} )
end

function SUBSYSTEM:StopSounds()
	self:CallEvent( { Event = "snd_stop" } )
end