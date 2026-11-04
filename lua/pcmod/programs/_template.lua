// ================================================================================================
// PCMod program template
// ================================================================================================
// This file is NOT loaded automatically (only pr_*.lua files are). Copy it to
// pr_myprogram.lua, rename the program, and fill in the hooks you need.
//
// Every program is a copy of programs/base.lua, so all of these helpers are
// already available:
//   persistence : SaveData, LoadData, GetDataPath
//   files       : FileExists, FolderExists, ReadFile, WriteFile, DeleteFile,
//                 ListFiles, CreateFolder, ListDir, GetItemInfo, RenameItem,
//                 CopyItem, DeleteItem, JoinPath, GetParentPath, GetBaseName
//   networking  : SendNetworkPacket, ProcessNetworkPacket
//                 IPv6: GetOS():GetIPv6/Prefix/Gateway, PCMod.IPv6.* (see
//                 PROGRAM_API.txt; IPv4 and IPv6 targets both work)
//   devices     : GetUSBDevicePorts, SendUSBData, ReceiveUSBData
//   audio       : PlaySound, StopSounds
//   timers      : Timer, KillTimer
//   lifecycle   : OnActivate, OnDeactivate, OnLoad, OnUnload, OnUninstall
//   misc        : ProcessCommand, Toggle, GetInfo, DbgMsg
// ================================================================================================

PROG.Name = "myprogram"
PROG.Author = "Your Name"
PROG.Title = "My Program"
PROG.Icon = "app"
PROG.OS = "personal" // "personal" or "server"

// SimpleMode makes the base class create/destroy the window for you using the
// DeviceLink/DeviceName/DeviceData fields below.
PROG.SimpleMode = true

PROG.DeviceLink = "window_myprogram"
PROG.DeviceName = "window_myprogram"
PROG.DeviceData = {}

// Files are relative to the program's SaveRoot (defaults to mydocs/).
PROG.SaveRoot = "mydocs/myprogram/"

// Called once when the program is installed into an OS.
// The default implementation registers a start-menu shortcut. Keep a reference
// to it before overriding so you can still get that behaviour.
local baseOnInstall = PROG.OnInstall

function PROG:OnInstall()
	baseOnInstall( self )
	self.Entity:LinkFolder( self.SaveRoot )
	self.DeviceData.Text = ""
end

// Called when the base class is about to show the window.
function PROG:OnStart()
	// Load the last saved document if there is one.
	local saved = self:LoadData( "state" )
	if (saved && saved.Text) then
		self.DeviceData.Text = saved.Text
	end
end

// Called when the base class is about to hide the window.
function PROG:OnEnd()
	self:SaveData( "state", { Text = self.DeviceData.Text } )
end

// Called every OS tick while the program is running.
function PROG:Think()
	// Per-frame work goes here. Keep it cheap.
end

// Commands from buttons/textboxes arrive here. ProcessCommand already handles
// "exit"/"close" and then calls DoCommand, so you only implement your own names.
function PROG:DoCommand( com, args )
	if (com == "update") then
		self:UpdateSS()
		return
	end
	if (com == "clear") then
		self.DeviceData.Text = ""
		self:UpdateSS()
		return
	end
	// Unknown commands are ignored by default.
end

// Incoming network packets addressed to this program.
function PROG:ProcessNetworkPacket( sourceEnt, port, body )
	// `body` is the packet table sent by SendNetworkPacket.
end
