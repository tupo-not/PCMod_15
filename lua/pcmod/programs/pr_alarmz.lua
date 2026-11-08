
// Alarmz Program for PCMod 2 \\
// Alarm output (USB iodev + sound) plus a Wiremod RT camera surveillance
// monitor. The camera monitor itself lives in the client-side window device
// (dev_win_alarmz.lua) because Wiremod RT camera textures only exist on the
// client; the window reports the watched camera back through "selectcam".

PROG.Name = "alarmz"
PROG.Author = "[GU]thomasfn"
PROG.Title = "AlarmZ"
PROG.Icon = "app"
PROG.OS = "personal"

PROG.SimpleMode = true

PROG.DeviceLink = "window_alarmz"
PROG.DeviceName = "window_alarmz"
PROG.DeviceData = {}

PROG.Device = 0
PROG.AlarmSound = "ambient/alarms/alarm1.wav"

// The surveillance window is bigger than the default program window.
PROG.WindowW = 0.72
PROG.WindowH = 0.80

function PROG:OnStart()
	if (!self.DeviceData) then self.DeviceData = {} end
	self.DeviceData.SelCam = 0
	self:GetDevice()
	self:DoCommand( "disable", {} )
end

function PROG:GetDevice()
	self:GetOS():RefreshUSBData()
	local devs = self:GetOS():GetUSBDevicePorts( "iodev" )
	if (#devs == 0) then self.Device = 0 end
	if (#devs > 0) then self.Device = devs[1] end
end

function PROG:DoCommand( com, args )
	if (com == "exit") then
		self:Exit()
		return
	end
	if (com == "enable") then
		self:GetOS():RunCommand( "snd_play " .. self.AlarmSound )
		self:GetDevice()
		self:GetOS():SendUSBData( self.Device, { "set_output", 1, 1 } )
		self.DeviceData.Al = 1
		self:UpdateSS()
	end
	if (com == "disable") then
		self:GetOS():RunCommand( "snd_stop" )
		self:GetDevice()
		self:GetOS():SendUSBData( self.Device, { "set_output", 1, 0 } )
		self.DeviceData.Al = 0
		self:UpdateSS()
	end
	if (com == "enable_c") then
		self.DeviceData.Cm = 1
		self:UpdateSS()
	end
	if (com == "disable_c") then
		self.DeviceData.Cm = 0
		self:UpdateSS()
	end
	// The client window tells us which Wiremod camera it is watching. The
	// entity index is only stored here (state/debug/future alarm linkage) -
	// the actual observation and rendering happens client-side.
	if (com == "selectcam") then
		local idx = tonumber( args[1] )
		if (idx && self.DeviceData && (self.DeviceData.SelCam != idx)) then
			self.DeviceData.SelCam = idx
		end
	end
	if (com == "setalarmsound") then
		self.AlarmSound = args[1]
	end
end