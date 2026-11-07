
// ---------------------------------------------------------------------------------------------------------
// sh_settings.lua - Revision 1
// Shared
// Controls PCMod related settings
// ---------------------------------------------------------------------------------------------------------


// ---------------------------------------------------------------------------------------------------------
// Define our library
// ---------------------------------------------------------------------------------------------------------

PCMod.Settings = {}
PCMod.Settings.Version = "1.0"

PCMod.Msg( "Settings library loaded! (" .. PCMod.Settings.Version .. ")", true )

if (CLIENT) then

	// ---------------------------------------------------------------------------------------------------------
	// Open - Opens the settings window
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.Settings.Open( um )
		local admin = um:ReadBool() -- Determine if we are admin or not
		local sadmin = um:ReadBool() -- Determine if we are super admin or not
		
		// Create the window
		local win = vgui.CreateWindow( 0.5, 0.75, "PCMod - Settings" )
		PCMod.Settings.MainWindow = win
		win:MakePopup()
		win:SetVisible( true )
		
		// Create the sheet
		local sheet = vgui.CreateSheet( win )
		PCMod.Settings.Sheet = sheet
		
		// Add the info tab
		local tb_info = vgui.AddTab( sheet, Color( 50, 50, 50, 255 ), "Information" )
		PCMod.Settings.InfoTab = tb_info
		
		// Add the info labels
		vgui.AddText( tb_info, "Welcome to the PCMod 13 settings panel!" )
		vgui.AddText( tb_info, "Below is a list of settings that PCMod is currently using." )
		vgui.AddText( tb_info, "To change these settings you need to edit the config file." )
		vgui.AddText( tb_info, "You can also temporarily change them in the 'Options' tab." )
		
		vgui.AddText( tb_info, " " )
		
		vgui.AddText( tb_info, "Name: PCMod 13" )
		vgui.AddText( tb_info, "Version: " .. PCMod.Version )
		vgui.AddText( tb_info, "Author: <BA>Riekelt, CrazyScouter, [GU]thomasfn" )
		
		vgui.AddText( tb_info, " " )
		
		for k, v in pairs( PCMod.Cfg ) do
			if (type( v ) != "table") then
				PCMod.Msg( "Adding '" .. k .. "'...", true )
				vgui.AddText( tb_info, k .. ": " .. tostring( v ) )
			else
				PCMod.Msg( "NOT adding '" .. k .. "'...", true )
			end
		end
		
		// Add the options tab
		local tb_options = vgui.AddTab( sheet, Color( 50, 50, 50, 255 ), "Options", "page" )
		PCMod.Settings.OptionsTab = tb_options
		
		// Add all the options
		vgui.AddText( tb_options, "Here you can change some PCMod settings." )
		vgui.AddText( tb_options, "The changes you make will NOT be saved if you rejoin the server!" )
		
		vgui.AddText( tb_options, " " )
		
		/*vgui.AddCheckbox( tb_options, "Enable Debug Mode:", PCMod.Cfg.DebugMode, function( self )
			local ch = self:GetChecked()
			PCMod.Cfg.DebugMode = ch
			if (ch) then
				PCMod.Notice( "PCMod: Debug mode enabled!" )
			else
				PCMod.Notice( "PCMod: Debug mode disabled!" )
			end
		end )*/
		
		vgui.AddButton( tb_options, "Enable Debug Mode", function() PCMod.Notice( "PCMod: Debug mode enabled! (CL)" ); PCMod.Cfg.DebugMode = true; end )
		vgui.AddButton( tb_options, "Disable Debug Mode", function() PCMod.Notice( "PCMod: Debug mode disabled! (CL)" ); PCMod.Cfg.DebugMode = false; end )
		vgui.AddButton( tb_options, "Enable Debug Logging", function() PCMod.Notice( "PCMod: Message logging is on! (CL)" ); PCMod.Cfg.LogMessages = true; timer.Start( "PCMod.SaveLog" ); end )
		vgui.AddButton( tb_options, "Disable Debug Logging", function() PCMod.Notice( "PCMod: Message logging is off! (CL)" ); PCMod.Cfg.LogMessages = false; timer.Stop( "PCMod.SaveLog" ); end )
		vgui.AddButton( tb_options, "Save Debug Logs Now", function() PCMod.SaveLogPre( true ); end )
		vgui.AddButton( tb_options, "High Quality Graphics", function() PCMod.Notice( "PCMod: High quality graphics enabled!" ); PCMod.Cfg.HighQuality = true; end )
		vgui.AddButton( tb_options, "Low Quality Graphics", function() PCMod.Notice( "PCMod: High quality graphics disabled!" ); PCMod.Cfg.HighQuality = false; end )
		
		// All other stuff is admin only stuff
		if (!admin) then return end
		
		// Add the server tab
		local tb_server = vgui.AddTab( sheet, Color( 50, 50, 50, 255 ), "Server", "wrench" )
		PCMod.Settings.ServerTab = tb_server
		
		// Add all the options
		vgui.AddText( tb_server, "Here you can change global PCMod settings." )
		vgui.AddText( tb_server, "They will affect the whole server." )
		
		vgui.AddText( tb_server, " " )
		
		vgui.AddButton( tb_server, "Enable Server Debug Mode", function() RunConsoleCommand( "pc_sv_debugmode", 1 ) end )
		vgui.AddButton( tb_server, "Disable Server Debug Mode", function() RunConsoleCommand( "pc_sv_debugmode", 0 ) end )
		vgui.AddButton( tb_server, "Enable RolePlay Mode", function() RunConsoleCommand( "pc_sv_rpmode", 1 ) end )
		vgui.AddButton( tb_server, "Disable RolePlay Mode", function() RunConsoleCommand( "pc_sv_rpmode", 0 ) end )
		vgui.AddButton( tb_server, "Enable Server Logging", function() RunConsoleCommand( "pc_sv_logmsgs", 1 ) end )
		vgui.AddButton( tb_server, "Disable Server Logging", function() RunConsoleCommand( "pc_sv_logmsgs", 0 ) end )
		vgui.AddButton( tb_server, "Save Debug Logs Now", function() RunConsoleCommand( "pc_sv_logmsgsave" ) end )
		vgui.AddButton( tb_server, "Reset RPCost to Defaults", function() RunConsoleCommand( "pc_reset_rpcost", 1 ) end )
		vgui.AddButton( tb_server, "Full Program List Editor", function() PCMod.Notice( "Use console: pc_setprogramlist <programs>" ) end )
		
		// All other stuff is super admin only stuff
		if (!sadmin) then return end
		
		// Add all SA options
		local cl = PCMod.Settings.ChangeLimit -- This is a function  -thomasfn
		vgui.AddSlider( tb_server, "Max Towers:", 0, 50, "sbox_maxpcmod_towers", cl, "towers" )
		vgui.AddSlider( tb_server, "Max Monitors:", 0, 50, "sbox_maxpcmod_monitors", cl, "monitors" )
		vgui.AddSlider( tb_server, "Max Keyboards:", 0, 50, "sbox_maxpcmod_keyboards", cl, "keyboards" )
		vgui.AddSlider( tb_server, "Max Printers:", 0, 50, "sbox_maxpcmod_printers", cl, "printers" )
		vgui.AddSlider( tb_server, "Max Speakers:", 0, 50, "sbox_maxpcmod_speakers", cl, "speakers" )
		vgui.AddSlider( tb_server, "Max LAN Modems:", 0, 50, "sbox_maxpcmod_routers", cl, "routers" )
		vgui.AddSlider( tb_server, "Max Routers:", 0, 50, "sbox_maxpcmod_erouters", cl, "erouters" )
		vgui.AddSlider( tb_server, "Max Modems:", 0, 50, "sbox_maxpcmod_modems", cl, "modems" )
		vgui.AddSlider( tb_server, "Max BRouters:", 0, 50, "sbox_maxpcmod_brouters", cl, "brouters" )
	end
	usermessage.Hook( "pcmod_opensettings", PCMod.Settings.Open )
	
	// ---------------------------------------------------------------------------------------------------------
	// ChangeLimit - Alters a entity limit
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.Settings.ChangeLimit( id, val )
		RunConsoleCommand( "pc_setlimit", id, val )
	end
	
end

function menuCommand (ply, text, public) 
	if (string.sub(text, 1, 6) == "!pcmod") then
		if (SERVER && IsValid(ply)) then
			PCMod.Settings.OpenClientWindow( ply, "pc_settings", {} )
		end
	end
end
hook.Add("PlayerSay", "menuCommand", menuCommand); 

if (SERVER) then

	// ---------------------------------------------------------------------------------------------------------
	// OpenClientWindow - Opens the settings window on a client
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.Settings.OpenClientWindow( pl, com, args )
		if (!pl || !pl:IsValid() || !pl:IsPlayer()) then return end
		umsg.Start( "pcmod_opensettings", pl )
			umsg.Bool( pl:IsAdmin() )
			umsg.Bool( pl:IsSuperAdmin() )
		umsg.End()
	end
	concommand.Add( "pc_settings", PCMod.Settings.OpenClientWindow )
	
	// ---------------------------------------------------------------------------------------------------------
	// ChangeSetting - Alters a server-side setting
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.Settings.ChangeSetting( pl, com, args )
		// Round 26 (M-12): a NULL player means the command came from the
		// server console - pl:IsAdmin() on NULL raises a Lua error.
		if (IsValid( pl ) && !pl:IsAdmin()) then
			PCMod.Notice( "You are not an admin!", pl )
			return
		end
		// Alot of weird logic here. - thomasfn
		local noval = (args[1] == nil)
		local val = 0
		if (!noval) then val = tonumber( args[1] ) end
		local st = (val == 1)
		if (com == "pc_sv_debugmode") then
			if (!noval) then PCMod.Cfg.DebugMode = st end
			if (PCMod.Cfg.DebugMode) then
				PCMod.Notice( "PCMod: Debug mode is on! (SV)", pl )
			else
				PCMod.Notice( "PCMod: Debug mode is off! (SV)", pl )
			end
		end
		if (com == "pc_sv_rpmode") then
			if (!noval) then PCMod.Cfg.RPMode = st end
			if (PCMod.Cfg.RPMode) then
				PCMod.Notice( "PCMod: RolePlay mode is on!", pl )
			else
				PCMod.Notice( "PCMod: RolePlay mode is off!", pl )
			end
		end
		if (com == "pc_sv_logmsgs") then
			if (!noval) then PCMod.Cfg.LogMessages = st end
			if (PCMod.Cfg.LogMessages) then
				timer.Start( "PCMod.SaveLog" )
				PCMod.Notice( "PCMod: Message logging is on! (SV)", pl )
			else
				timer.Stop( "PCMod.SaveLog" )
				PCMod.Notice( "PCMod: Message logging is off! (SV)", pl )
			end
		end
		if (com == "pc_sv_logmsgsave") then
			PCMod.SaveLogPre( true )
		end
	end
	concommand.Add( "pc_sv_debugmode", PCMod.Settings.ChangeSetting )
	concommand.Add( "pc_sv_rpmode", PCMod.Settings.ChangeSetting )
	concommand.Add( "pc_sv_logmsgs", PCMod.Settings.ChangeSetting )
	concommand.Add( "pc_sv_logmsgsave", PCMod.Settings.ChangeSetting )

	// ---------------------------------------------------------------------------------------------------------
	// ResetRPCost - Restores the stock RP prices
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.Settings.ResetRPCost( pl, com, args )
		if (IsValid( pl ) && !pl:IsAdmin()) then
			PCMod.Notice( "You are not an admin!", pl )
			return
		end
		PCMod.Cfg.RPCost = table.Copy( PCMod.Cfg.RPCostDefaults or {} )
		PCMod.Notice( "PCMod: RP prices reset to defaults.", pl )
	end
	concommand.Add( "pc_reset_rpcost", PCMod.Settings.ResetRPCost )

	// ---------------------------------------------------------------------------------------------------------
	// SetProgramList - Changes the list of programs a disk can install
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.Settings.SetProgramList( pl, com, args )
		if (IsValid( pl ) && !pl:IsAdmin()) then
			PCMod.Notice( "You are not an admin!", pl )
			return
		end
		local list = args[1]
		if (!list) then
			PCMod.Notice( "Usage: pc_setprogramlist <comma,separated,programs>", pl )
			return
		end
		if (string.find( list, "[^%w_,]" )) then
			PCMod.Notice( "PCMod: Program names may only contain letters, numbers and underscores.", pl )
			return
		end
		PCMod.Cfg.FullProgramList = list
		// Keep the generated "Ultimate Pack" disk in sync with the new list.
		if (PCMod.Cfg.RPDisks) then
			for _, pack in pairs( PCMod.Cfg.RPDisks ) do
				if (pack[3] == "ulti") then pack[4] = list end
			end
		end
		PCMod.Notice( "PCMod: Program list updated to '" .. list .. "'.", pl )
	end
	concommand.Add( "pc_setprogramlist", PCMod.Settings.SetProgramList )

end