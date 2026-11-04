
// ---------------------------------------------------------------------------------------------------------
// sh_pcmod_launch.lua - Revision 1
// Shared
// Runs the core PCMod files
// ---------------------------------------------------------------------------------------------------------

function PCMod_ResetOld( hookid )
	PCMod = nil
	local hktbl = table.Copy( hook.GetTable() )
	PrintTable(hktbl)
	for name, tbl in pairs( hktbl ) do
		for uniquename, func in pairs( tbl ) do
			// Non-string hook ids exist in current GMod - skip them
			if (type( uniquename ) == "string") then
				if (string.Left( uniquename, string.len( hookid ) ) == hookid) then
					hook.Remove( name, uniquename )
					Msg( "PCMod2: Removed old hook '" .. uniquename .. "'\n" )
				end
			end
		end
	end
end

// Check if PCMod is already installed
if (PCMod) then

	Error( "PCMod2: PCMod libraries already exist!\n" )
	Error( "PCMod2: Attempting to reset...\n" )
	
	PCMod_ResetOld( "PCMod_" )

end

if (SERVER) then

	AddCSLuaFile( "autorun/sh_pcmod_launch.lua" ) -- Add this file

	include( "pcmod/sv_core.lua" ) -- Include the core serverside PCMod file

end

if (CLIENT) then

	// Define kick-start functions
	function PCMod_KickStart()
		// Release every piece of client-side PCMod UI before discarding the
		// tables. Otherwise the old full-screen HackyClicky panel, lock frame,
		// keyboard and screen clicker stay alive with no reference to remove
		// them, leaving the player stuck looking at the PC.
		if (CLIENT) then
			if (PCMod) then
				if (PCMod.Gui) then
					// Remove the actual panels directly: the helper functions may
					// themselves be half-reloaded when this runs.
					if (PCMod.Gui.LFrame && IsValid( PCMod.Gui.LFrame )) then PCMod.Gui.LFrame:Remove() end
					if (PCMod.Gui.HackyClicky && IsValid( PCMod.Gui.HackyClicky )) then PCMod.Gui.HackyClicky:Remove() end
					if (PCMod.Gui.KeyBoard && IsValid( PCMod.Gui.KeyBoard )) then PCMod.Gui.KeyBoard:Remove() end
					if (PCMod.Gui.QuickType && IsValid( PCMod.Gui.QuickType )) then PCMod.Gui.QuickType:Remove() end
					if (PCMod.Gui.PDoc && IsValid( PCMod.Gui.PDoc )) then PCMod.Gui.PDoc:Remove() end
					PCMod.Gui.KeyBoard = nil
					PCMod.Gui.LFrame = nil
					PCMod.Gui.HackyClicky = nil
					PCMod.Gui.QuickType = nil
					PCMod.Gui.QuickTypeText = nil
					PCMod.Gui.PDoc = nil
					PCMod.Gui.CamLocked = false
					PCMod.Gui.CamLockID = 0
				end
				if (PCMod.EnableCapture) then PCMod.EnableCapture( false ) end
				if (PCMod.SDraw) then
					if (PCMod.SDraw.SetFullscreenUI) then PCMod.SDraw.SetFullscreenUI( false ) end
					PCMod.SDraw.DevFocus = ""
					PCMod.SDraw.DrawKeyboard = false
					PCMod.SDraw.KeyboardEntID = 0
				end
				if (PCMod.Cam && PCMod.Cam.Trigger) then PCMod.Cam.Trigger( "unlock" ) end
			end
			if (gui) then gui.EnableScreenClicker( false ) end
			local ply = LocalPlayer()
			if (ply && ply:IsValid()) then ply:Freeze( false ) end
			// The server freezes/unfreezes through this command; do it too so
			// a kickstart while seated at a PC cannot leave the player frozen.
			RunConsoleCommand( "pc_locked", "0" )
		end

		PCMod_ResetOld( "PCMod_" )
		PCMod_ResetOld( "PCMod." )
		Msg( "==> About to KickStart PCMod! <==\n" )
		include( "autorun/sh_pcmod_launch.lua" )
		PCMod_Init( "PCMod." )
	end
	function PCMod_IsValid()
		return ((PCMod) && (PCMod.IsPCMod2))
	end
	function PCMod_Init( hookid )
		local inits = hook.GetTable().Initialize
		if (!inits) then return end
		for uniquename, func in pairs( inits ) do
			if (type( uniquename ) == "string") then
				if (string.Left( uniquename, string.len( hookid ) ) == hookid) then
					func()
					Msg( "PCMod2: Called init hook '" .. uniquename .. "'\n" )
				end
			end
		end
	end
	concommand.Add( "pc_kickstart", PCMod_KickStart )

	include( "pcmod/cl_core.lua" ) -- Include the core clientside PCMod file

end