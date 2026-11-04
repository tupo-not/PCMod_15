// Notepad Program for PCMod 2 \\
// Enhanced with new API features

PROG.Name = "notepad"
PROG.Author = "[GU]thomasfn"
PROG.Title = "Notepad"
PROG.Icon = "app"
PROG.OS = "personal"

PROG.SimpleMode = true

// Device configuration
PROG.DeviceLink = "window_notepad"
PROG.DeviceName = "window_notepad"
PROG.DeviceData = {}

// Program-specific data
PROG.SaveRoot = "mydocs/text/"
PROG.Fs = {} // Browse list
PROG.OpenPath = nil // Full path of a file opened from another program

// Resolve where "Save" should write. Files opened from outside mydocs/text/
// keep saving back to their original location until the user renames them.
function PROG:GetSaveTarget( filename )
	if ((!filename) || (filename == "")) then filename = "untitled.txt" end
	if (self.OpenPath && (self:GetBaseName( self.OpenPath ) == filename)) then
		return self.OpenPath
	end
	return self.SaveRoot .. filename
end

// Save through the lock-aware program API. A failed save must not advance TC
// or OpenPath: those describe the last successfully saved document.
function PROG:SaveDocument( filename, text )
	if (text == nil) then text = "" end
	local target = self:GetSaveTarget( filename )
	local ok, err = self:WriteFile( target, util.Compress( text ) )
	self.DeviceData.SaveFailed = !ok
	if (!ok) then
		self.DeviceData.St = (err == "locked") and 6 or 7
		self:UpdateSS()
		return false, err
	end
	self.DeviceData.TC = text
	self.OpenPath = target
	self.DeviceData.FN = self:GetBaseName( target )
	self.DeviceData.St = 1 // "File saved."
	// Push the new TC back to the client so the "Unsaved Changes" marker
	// compares against the saved text and disappears.
	self:UpdateSS()
	return true
end

// ==========================================
// OnInstall - called when program is installed
// ==========================================
function PROG:OnInstall()
	// Register program in OS menu
	self:GetOS():AddProg( self.Icon, self.Title, "sys_openprog " .. self.Name )
	// Link data folder
	self.Entity:LinkFolder( "mydocs/text/" )
	// Initialize device data
	if (!self.DeviceData.TC) then
		self.DeviceData.TC = ""
	end
	if (!self.DeviceData.St) then
		self.DeviceData.St = 0
	end
end

// ==========================================
// DoCommand - handle commands from OS
// ==========================================
function PROG:DoCommand( com, args )
	if (com == "exit") then
		self:Exit()
		return
	end
	if (com == "ct_clear") then
		self.DeviceData.TC = ""
		self:UpdateSS()
		return
	end
	if (com == "ct_start") then
		self.CTSegs = ""
		return
	end
	if (com == "ct_seg") then
		self.CTSegs = self.CTSegs .. table.concat( args, " " )
		return
	end
	if (com == "ct_end") then
		self.DeviceData.TC = self.CTSegs
		self.CTSegs = ""
		self:UpdateSS()
		return
	end
	if (com == "savecontent") then
		local filename = args[1]
		if (!filename) then filename = "untitled.txt" end
		// The text is normally a single argument (streamed), but keep the old
		// multi-argument form working as a fallback.
		local text
		if ((args[2] != nil) && (#args == 2)) then
			text = args[2]
		else
			local segs = {}
			for i = 2, #args do segs[ #segs + 1 ] = args[ i ] end
			text = table.concat( segs, " " )
		end
		if (text == nil) then text = "" end
		PCMod.Msg( "Recieved content to save! (" .. text .. ")", true )
		// Save raw compressed text - the "open" command reads the same format.
		self:SaveDocument( filename, text )
		return
	end
	if (com == "update") then
		self:UpdateSS()
		return
	end
	if (com == "save") then
		local txt = self.DeviceData.TC
		if (!txt) then txt = "" end
		local fname = args[1]
		if (!fname) then fname = "untitled.txt" end
		self:SaveDocument( fname, txt )
		return
	end
	if (com == "open") then
		self.DeviceData.SaveFailed = false
		local fname = args[1]
		if (!fname) then fname = "untitled.txt" end
		local fn = self.SaveRoot .. fname
		if (self:FileExists( fn )) then
			local text = self.Entity:ReadFile( fn )
			if (!text) then text = "" end
			// Files written by Notepad are compressed; tolerate plain files.
			local ok, decoded = pcall( util.Decompress, text )
			if (ok && decoded) then text = decoded end
			self.DeviceData.TC = text
			self.DeviceData.St = 2
			self.OpenPath = fn
			self.DeviceData.FN = fname
		else
			self.DeviceData.TC = ""
			self.DeviceData.St = 3
			self.OpenPath = nil
		end
		self:UpdateSS()
		// Clear browse list
		for i = #self.Fs, 1, -1 do
			table.remove( self.Fs, i )
		end
		return
	end
	if (com == "openpath") then
		self.DeviceData.SaveFailed = false
		local fn = args[1]
		if (!fn) then return end
		fn = string.gsub( tostring( fn ), "\\", "/" )
		if (self:FileExists( fn )) then
			local text = self.Entity:ReadFile( fn )
			if (!text) then text = "" end
			local ok, decoded = pcall( util.Decompress, text )
			if (ok && decoded) then text = decoded end
			self.DeviceData.TC = text
			self.DeviceData.St = 2
			self.OpenPath = fn
			self.DeviceData.FN = self:GetBaseName( fn )
		else
			self.DeviceData.TC = ""
			self.DeviceData.St = 3
			self.OpenPath = nil
		end
		self:UpdateSS()
		return
	end
	if (com == "browse") then
		// Browse the whole virtual drive, starting at the root (like the File
		// Manager). "openpath" then loads the selected file directly.
		self:ShowFilePicker( "", "open" )
		return
	end
	if (com == "closebrowse") then
		// Clear browse list from the back
		for i = #self.Fs, 1, -1 do
			table.remove( self.Fs, i )
		end
		self:CloseOpenFile()
		return
	end
	if (com == "print") then
		if (tonumber(args[1]) == 1) then
			self:ShowPrintLocation( true )
		else
			self:ShowPrintLocation( false )
		end
		return
	end
	if (com == "closeprint") then
		self:ClosePrintLocation()
		return
	end
	if (com == "printdoc") then
		self:ClosePrintLocation()
		local txt = self.DeviceData.TC
		if (!txt) then return end
		if ((!args[1]) || (args[1] == "local")) then
			self:PrintDocument( txt, false )
		else
			// Send to specific PC via network
			self:GetOS():SendNetMessage( args[1], 58, { "netPrintDocument", txt } )
		end
		self.DeviceData.St = 5
		self:UpdateSS()
		return
	end
		// Unknown command - just log it in debug mode
		self:DbgMsg( "Unhandled command '" .. tostring(com) .. "'" )
	end

// ==========================================
// OnStart - called when program becomes active
// ==========================================
function PROG:OnStart()
	// Program is now focused - initialize UI state
	PCMod.Msg( "Notepad opened", true )
	self:UpdateSS()
end

// ==========================================
// OnEnd - called when program loses focus
// ==========================================
function PROG:OnEnd()
	// Do not write "state" into SaveRoot here: it would overwrite a real
	// document called "state" and use a different format than the editor.
	PCMod.Msg( "Notepad closed", true )
end

// ==========================================
// Think - called every frame when program is active
// ==========================================
function PROG:Think()
	// Could add blinking cursor, auto-save, etc. here
end

// ==========================================
// ProcessPacket - handle network packets to this program
// ==========================================
function PROG:ProcessPacket( pt, dat, handle )
	// Handle incoming network packets
	if (pt == 58) then -- print document port
		if (dat[1] == "netPrintDocument") then
			local txt = dat[2]
			self:PrintDocument( txt, true )
		end
	end
end

// ==========================================
// New enhanced API usage examples:
// ==========================================

// Save program data using new API
function PROG:SaveNote( filename, text )
	self:SaveData( filename, { text = text, saved = CurTime() } )
end

// Load program data using new API
function PROG:LoadNote( filename )
	local data = self:LoadData( filename )
	if (data) then
		self.DeviceData.TC = data.text
		self.DeviceData.St = data.st or 0
		self:UpdateSS()
	end
end

// Play a sound
function PROG:Alert()
	self:PlaySound( "ui/buttonclick.wav" )
end

// Send network packet to another PC
function PROG:SendToPC( targetEntIndex, message )
	self:SendNetworkPacket( targetEntIndex, 58, { "note", message } )
end

// Toggle program state
function PROG:ToggleProgram()
	self:Toggle()
end

// ==========================================
// END OF ENHANCED NOTEPAD
// ==========================================