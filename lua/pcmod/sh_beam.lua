
// ---------------------------------------------------------------------------------------------------------
// sh_beam.lua - Revision 1
// Shared
// Controls beaming data from server to client
// ---------------------------------------------------------------------------------------------------------

// ---------------------------------------------------------------------------------------------------------
// Define our library
// ---------------------------------------------------------------------------------------------------------

PCMod.Beam = {}
PCMod.Beam.Version = "1.0"
PCMod.Beam.StrSegs = {}
PCMod.Beam.Hooks = {}

PCMod.Beam.Range_SS = 1024 -- Range to beam ScreenSpaces to
PCMod.Beam.MaxString = 65000 -- net.WriteString can only carry 65532 bytes (M-03)

PCMod.PortData = {}

PCMod.EntData = {}

PCMod.Gui = PCMod.Gui or {}
PCMod.Gui.Version = "1.0"
PCMod.SelEntity = 0

PCMod.Gui.MouseDown = false

PCMod.Gui.DebugBoxes = {}
PCMod.Gui.Themes = {}

PCMod.Gui.CamLocked = false
PCMod.Gui.CamLockID = 0

PCMod.Msg( "Beam Library Loaded (V" .. PCMod.Beam.Version .. ")", true )

if (SERVER) then
	util.AddNetworkString("pcmod_stringhook");
	util.AddNetworkString("EntityBilgi")

	// ---------------------------------------------------------------------------------------------------------
	// SendScreenSpace - Sends a screen space to the client
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.Beam.SendScreenSpace( ply, ent )
		PCMod.Msg( "Preparing to send SS...", true )
		
		// If the entity is not on, tell the client which screen to clear.
		// A bare {} has no entity id, so the client could not attribute it
		// and discarded the message with a misleading warning.
		if (!ent:Data().IsOn) then
			PCMod.Beam.BeamTable( ply, "ssdata", { EntID = ent:EntIndex() } )
		end
		
		// Get the SS data
		local ss = ent:ScreenSpace()
		if (!ss) then return end
		local dat = ss.Data
		
		// Ensure the player's beam data exists
		if (!ply.BeamData) then ply.BeamData = {} end
		if (!ply.BeamData[ ent:EntIndex() ]) then ply.BeamData[ ent:EntIndex() ] = {} end
		
		// Check the player's beam data for items that no longer exist
		local btbl = ply.BeamData[ ent:EntIndex() ]
		local newdat = {}
		// Resend a device when its revision, stacking order or geometry
		// changed. win_move/focus update the entry in place without bumping
		// Rev (to avoid resetting text fields), so a Rev-only cache never
		// delivered the new position or z-order to the client.
		local function DevSig( dev )
			return tostring( dev.Rev ) .. "|" .. tostring( dev.Priority ) .. "|" ..
				tostring( dev.X ) .. "|" .. tostring( dev.Y ) .. "|" ..
				tostring( dev.W ) .. "|" .. tostring( dev.H )
		end
		for k, v in pairs( dat ) do
			if (type(v) == "table") then
				// For every device name and device in the screenspace;
				// k is the device name in the sspace, v is the actual device.
				// Check to see what version the player has
				// Cycle through player beam data for the right one
				// We're screwed if an entity needs multiple screenspaces - thomasfn
				local f = false
				for devname, sig in pairs( btbl ) do
					if (k == devname) then
						f = true -- We found the device, at least the player has recieved a version of this device
						-- Check the revision and priority
						if (sig != DevSig( v )) then
							-- Revision mismatch! Assume the server's version
							newdat[ k ] = v
							ply.BeamData[ ent:EntIndex() ][ devname ] = DevSig( v )
							PCMod.Msg( "Server has different revision! (" .. k .. ")", true )
						end
						break
					end
				end
				if (f == false) then
					// We have not found this device, insert it right in
					PCMod.Msg( "Server has new device! (" .. k .. ")", true )
					newdat[ k ] = v
					ply.BeamData[ ent:EntIndex() ][ k ] = DevSig( v )
				end
			else
				// We have a variable which isn't a table. Probably a 'sneaky' variable, let's send it anyway
				newdat[ k ] = v
			end
		end
		
		// Check if the player has a ss device that we don't
		for k, v in pairs( btbl ) do
			if (!table.HasKey( dat, k )) then
				// Tell the client the device no longer exists
				newdat[ k ] = 0
				ply.BeamData[ ent:EntIndex() ][ k ] = nil
			end
		end
		
		// Send the data
		newdat.EntID = ent:EntIndex()
		PCMod.Beam.BeamTable( ply, "ssdata_update", newdat )
	end

	// ---------------------------------------------------------------------------------------------------------
	// BeamTable - Sends a table to the client
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.Beam.BeamTable( ply, tag, tbl )
		if (type(tbl) != "table") then
			PCMod.Warning( "BeamTable recieved a non-table value!" )
			return
		end
		PCMod.Beam.BeamString( ply, tag, PCMod.TableToString( tbl ) )
	end

	// ---------------------------------------------------------------------------------------------------------
	// BeamString - Sends a string to one player, or to everyone when ply is nil
	// ---------------------------------------------------------------------------------------------------------
	local function BeamStartUMsg( name, ply )
		if (ply) then
			umsg.Start( name, ply )
		else
			umsg.Start( name )
		end
	end

	function PCMod.Beam.BeamString( ply, tag, str )
		str = tostring( str or "" )
		tag = tostring( tag or "" )
		// Round 30 (M-03): net.WriteString can only carry 65532 bytes. A
		// bigger payload raised an unhandled Lua error ("net.WriteString:
		// string too long"), the message never left the server and the
		// screenspace of that PC stayed frozen for everybody. Big payloads go
		// through the chunked usermessage channel instead - the same one the
		// broadcast already used, it just works for a single player as well.
		if (string.len( str ) <= PCMod.Beam.MaxString) then
			net.Start( "pcmod_stringhook" )
				net.WriteString( str )
				net.WriteString( tag )
			if (ply) then net.Send( ply ) else net.Broadcast() end
			return
		end

		local rs = 230 - string.len( tag )
		if (rs < 1) then rs = 1 end
		local chunks = PCMod.SplitString( str, rs )
		// the segment counter is a short - a payload that would need more
		// than 32000 segments is cut off (that is far beyond every real
		// screenspace) instead of raising an error
		if (#chunks > 32000) then
			str = string.sub( str, 1, (32000 * rs) )
			chunks = PCMod.SplitString( str, rs )
		end
		if (!chunks[1]) then return end

		BeamStartUMsg( "pcmod_stringstart", ply )
			umsg.String( tag )
			umsg.Short( #chunks )
			umsg.String( chunks[1] )
		umsg.End()
		if (#chunks < 2) then return end
		for i = 2, #chunks do
			BeamStartUMsg( "pcmod_stringseg", ply )
				umsg.String( tag )
				umsg.Short( i )
				umsg.String( chunks[ i ] )
			umsg.End()
		end
	end
	
	// ---------------------------------------------------------------------------------------------------------
	// BeamEntSS - Beam a screen space of an entity to all players in range
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.Beam.BeamEntSS( ent, range )
		if ((!ent) || (!ent:IsValid())) then return end
		for _, v in pairs( player.GetAll() ) do
			if (!v.SSBeam) then v.SSBeam = {} end
			if (!v.SSBeam[ ent:EntIndex() ]) then
				if ((v:GetPos()-ent:GetPos()):Length()<range) then
					PCMod.Beam.SendScreenSpace( v, ent )
					// Round 30 (M-07): the flag is only set when the screenspace
					// really was delivered. It used to be set for EVERY player -
					// also for the ones that were out of range. Such a player
					// never got the screen and the flag said "delivered", so he
					// did not get it later either.
					v.SSBeam[ ent:EntIndex() ] = true
				end
			end
		end
	end
	
	// ---------------------------------------------------------------------------------------------------------
	// SetEntData - Sets a networked piece of ent data
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.Beam.SetEntData( id, key, val )
		if (!PCMod.EntData[ id ]) then PCMod.EntData[ id ] = {} end
		PCMod.EntData[ id ].ID = id
		//PCMod.Msg( "Setting ent data (" .. key .. " = " .. tostring( val ) .. ")", true )
		if (PCMod.EntData[ id ][ key ] == val) then return end
		PCMod.EntData[ id ][ key ] = val
		PCMod.Msg( "Beaming ent data...", true )
		// Entity data is global state read by every client (overlays, printer
		// text, wireless state), so nil means broadcast. The old code passed an
		// undeclared global `ply` here, which only worked by accident because
		// the chunked path happened to broadcast nil.
		PCMod.Beam.BeamTable( nil, "entdata", PCMod.EntData[ id ] )
	end
	
	// ---------------------------------------------------------------------------------------------------------
	// ClearEntData - Clears the entity data table
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.Beam.ClearEntData( id )
		PCMod.Msg( "Resetting ent data (" .. id .. ")!", true )
		PCMod.EntData[ id ] = {}
		PCMod.EntData[ id ].ID = id
		PCMod.Beam.BeamTable( nil, "entdata", PCMod.EntData[ id ] )
	end
	
	// ---------------------------------------------------------------------------------------------------------
	// SendFullEntData - Sends the full entdata table to the client
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.Beam.SendFullEntData( ply )
		PCMod.Beam.BeamTable( ply, "fullentdata", PCMod.EntData )
	end
	
	// ---------------------------------------------------------------------------------------------------------
	// FirstSpawn - Called when a player spawns for the first time
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.Beam.FirstSpawn( ply )
		if ((!ply) || (!ply:IsValid())) then return end
		timer.Simple( 1, function()
			if ((!ply) || (!ply:IsValid())) then return end
			PCMod.Beam.SendFullEntData( ply )
		end)
	end
	hook.Add( "PlayerInitialSpawn", "PCMod.Beam.FirstSpawn", PCMod.Beam.FirstSpawn )
	
	// ---------------------------------------------------------------------------------------------------------
	// HD_Struct - Returns a HD structure
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.Beam.HD_Struct( ent )
		if ((!ent) || (!ent:IsValid()) || (!ent.IsPCMod)) then return {} end
		local hd = PCMod.Data[ ent:EntIndex() ].HardDrive
		if (!hd) then return {} end
		local tmp = {}
		for dir, item in pairs( hd ) do
			local dt = string.Explode( "/", dir )
			table.remove( dt, 1 )
		end
		return tmp
	end
	
	// ---------------------------------------------------------------------------------------------------------
	// NearPlayers - All players that can see the entity (the screenspace range)
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.Beam.NearPlayers( ent )
		local res = {}
		if ((!ent) || (!ent:IsValid())) then return res end
		for _, v in pairs( player.GetAll() ) do
			if ((v:GetPos()-ent:GetPos()):Length() < PCMod.Beam.Range_SS) then
				table.insert( res, v )
			end
		end
		return res
	end
	
	// ---------------------------------------------------------------------------------------------------------
	// FileList - Lists all files inside a certain directory
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.Beam.FileList( ent, path )
		if ((!ent) || (!ent:IsValid()) || (!ent.IsPCMod)) then return {} end
		local hd = PCMod.Data[ ent:EntIndex() ].HardDrive
		if (!hd) then return {} end
		--PrintTable(hd)
		local tmp = {}
		path = "/" .. path
		PCMod.Msg( "Preparing to check vs '" .. path .. "'...", true )
		for dir, item in pairs( hd ) do
			if (item.ItemType == "file") then
				PCMod.Msg( "Checking file '" .. dir .. "'...", true )
				if (string.lower( string.sub( dir, 1, string.len( path ) ) ) == string.lower( path )) then
					PCMod.Msg( "Path match found!", true )
					// First bit matches, now check it doesn't go on
					local rt = string.sub( dir, string.len( path )+1, string.len( dir ) )
					if (!string.find( rt, "/" )) then
						// This looks like a file! Add it
						table.insert( tmp, rt )
						PCMod.Msg( "Full match found!", true )
					end
				end
			end
		end/*
		local saybakam = table.Count(tmp)
		if (saybakam == 0) then
		table.insert( tmp, "Empty" )
		end*/
		// Round 31 (M-50): the file list used to be sent to EVERY client
		// (net.Broadcast) - so every player on the server could read the file
		// names of every hard drive. Now only the players that can actually
		// see the machine get the list.
		for _, v in pairs( PCMod.Beam.NearPlayers( ent ) ) do
			net.Start("EntityBilgi")
				net.WriteEntity( ent )
				net.WriteTable (tmp)
			net.Send( v )
		end
		return tmp
	end
end

if (CLIENT) then

	// ---------------------------------------------------------------------------------------------------------
	// StringStart - The server has started to send us a long string
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.StringStart( um )
		local tag = um:ReadString()
		local chunks = um:ReadShort()
		local ca = um:ReadString()
		if ((!tag) || (chunks < 1) || (chunks > 32000)) then return end
		if (chunks == 1) then
			PCMod.Msg( "Small string recieved! (" .. tag .. ")", true )
			PCMod.Beam.CallHook( tag, ca )
			return
		end
		PCMod.Beam.StrSegs[ tag ] = {
			Tag = tag,
			SegCnt = chunks,
			SegsR = 1,
			Segs = { ca },
			Seen = { [ 1 ] = true },
		}
		PCMod.Msg( "String beam started! (" .. tag .. ")", true )
		
	end
	usermessage.Hook( "pcmod_stringstart", PCMod.StringStart )
	
	// ---------------------------------------------------------------------------------------------------------
	// StringSegment - The server has sent us a segment of a long string
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.StringSegment( um )
		local tag = um:ReadString()
		local cid = um:ReadShort()
		local seg = um:ReadString()
		local stream = PCMod.Beam.StrSegs[ tag ]
		if ((!stream) || (!cid) || (cid < 1) || (cid > stream.SegCnt)) then return end
		// Count each index once. A duplicated segment used to inflate SegsR,
		// falsely complete the stream, and leave a nil hole for table.concat.
		if (!stream.Seen[ cid ]) then
			stream.Seen[ cid ] = true
			stream.SegsR = stream.SegsR + 1
		end
		stream.Segs[ cid ] = seg
		PCMod.Msg( "String segment recieved! (" .. tag .. ")", true )
		if (stream.SegsR == stream.SegCnt) then
			local str = table.concat( stream.Segs, "" )
			PCMod.Beam.StrSegs[ tag ] = nil
			PCMod.Msg( "String fully recieved! (" .. tag .. ")", true )
			PCMod.Beam.CallHook( tag, str )
		end
		
	end
	usermessage.Hook( "pcmod_stringseg", PCMod.StringSegment )
	
	net.Receive("pcmod_stringhook", function(len, client)
		local str = net.ReadString();
		local tag =	net.ReadString();
		PCMod.Beam.CallHook(tag, str);
	end)
	
	// ---------------------------------------------------------------------------------------------------------
	// CallHook - Calls the hook when a string has been fully recieved
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.Beam.CallHook( tag, str )
		local cnt = 0
		for _, v in pairs( PCMod.Beam.Hooks ) do
			if (v[1] == tag) then
				v[2]( str )
				cnt = cnt + 1
			end
		end
		if (cnt == 0) then PCMod.Warning( "Unhandled big string! (" .. tag .. ")" ) end
	end
	
	// ---------------------------------------------------------------------------------------------------------
	// Hook - Adds a hook to call when a string has been fully recieved
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.Beam.Hook( tag, callback )
		table.insert( PCMod.Beam.Hooks, { tag, callback } )
	end
	
	// ---------------------------------------------------------------------------------------------------------
// ShowDocument - Shows a printed document on the screen
// ---------------------------------------------------------------------------------------------------------

function PCMod.Gui.ShowDocument( str )
	PCMod.Msg( "Showing printed document! (" .. str .. ")", true )
	if (PCMod.Gui.PDoc) then
		PCMod.Gui.PDoc:Remove()
		PCMod.Gui.PDoc = nil
	end
	local pn = vgui.Create( "PrintedDoc" )
	if (!pn) then return end
	pn:SetText( str, "ScoreboardText" )
	pn:SetVisible( true )
	PCMod.Gui.PDoc = pn
	gui.EnableScreenClicker( true )
end
PCMod.Beam.Hook( "docu_info", PCMod.Gui.ShowDocument )
	// ---------------------------------------------------------------------------------------------------------
	// NewScreenSpace - Records the full screenspace of a entity that we just recieved from server
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.Beam.NewScreenSpace( str )
		if (!str) then return end
		local ss = PCMod.StringToTable( str )
		if (!ss) then return end
		local entid = ss.EntID
		ss.EntID = nil
		if (!entid) then
			PCMod.Msg( "Invalid ScreenSpace recieved! STT must have failed.", true )
			return
		end
		PCMod.SDraw.NewScreenSpace( entid, table.Copy( ss ) )
		PCMod.Msg( "New ScreenSpace Recieved! (" .. str .. ")", true )
	end
	PCMod.Beam.Hook( "ssdata", PCMod.Beam.NewScreenSpace )
	
	// ---------------------------------------------------------------------------------------------------------
	// UpdateScreenSpace - Records the partial screenspace of a entity that we just recieved from server
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.Beam.UpdateScreenSpace( str )
		if (!str) then return end
		local ss = PCMod.StringToTable( str )
		if (!ss) then return end
		local entid = ss.EntID
		ss.EntID = nil
		if (!entid) then
			PCMod.Msg( "Invalid ScreenSpace recieved! STT must have failed.", true )
			return
		end
		PCMod.SDraw.UpdateScreenSpace( entid, table.Copy( ss ) )
		//PCMod.Msg( "Partial ScreenSpace Recieved! (" .. str .. ")", true )
	end
	PCMod.Beam.Hook( "ssdata_update", PCMod.Beam.UpdateScreenSpace )
	
	// ---------------------------------------------------------------------------------------------------------
	// UpdateEntData - Records a piece of EntData
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.Beam.UpdateEntData( str )
		if (!str) then return end
		local dat = PCMod.StringToTable( str )
		if (!dat) then return end
		local entid = dat.ID
		if (!entid) then
			PCMod.Msg( "Invalid EntData recieved! STT must have failed.", true )
			return
		end
		PCMod.EntData[ entid ] = dat
	end
	PCMod.Beam.Hook( "entdata", PCMod.Beam.UpdateEntData )
	
	// ---------------------------------------------------------------------------------------------------------
	// FullUpdateEntData - Records all of EntData
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.Beam.FullUpdateEntData( str )
		if (!str) then return end
		local dat = PCMod.StringToTable( str )
		if (!dat) then
			PCMod.Msg( "Invalid FullEntData recieved! STT must have failed.", true )
			return
		end
		table.Merge( PCMod.EntData, dat )
	end
	PCMod.Beam.Hook( "fullentdata", PCMod.Beam.FullUpdateEntData )
	
	// ---------------------------------------------------------------------------------------------------------
	// GetEntData - Gets a networked piece of ent data
	// ---------------------------------------------------------------------------------------------------------
	function PCMod.Beam.GetEntData( id, key )
		if (!PCMod.EntData[ id ]) then PCMod.EntData[ id ] = {} end
		return PCMod.EntData[ id ][ key ]
	end

end

// ---------------------------------------------------------------------------------------------------------
// LockCam - Tells a client to lock the cam on an object
// ---------------------------------------------------------------------------------------------------------
function PCMod.Beam.LockCam( entid, ply )
	if (SERVER) then
		if ((!ply) || (!ply:IsValid()) || (!ply:IsPlayer())) then return end
		umsg.Start( "pcmod_lockcam", ply ); umsg.Long( entid ); umsg.End()
		return
	end
	if (CLIENT) then
		if (ply != LocalPlayer()) then return end
		
		PCMod.Gui.CamLocked = true
		PCMod.Gui.CamLockID = entid
		
		gui.EnableScreenClicker( true )
		LocalPlayer():Freeze( true )
		
		PCMod.Gui.EnableHackyClicky( true )
		PCMod.Gui.ShowLockFrame( true )
		PCMod.SDraw.DevFocus = ""

		// New: the screen is rendered fullscreen at native resolution.
		if (PCMod.SDraw && PCMod.SDraw.SetFullscreenUI) then
			PCMod.SDraw.SetFullscreenUI( true, entid )
		end
		
		PCMod.Cam.Trigger( "lock", entid )
	end
end
if (CLIENT) then
	usermessage.Hook( "pcmod_lockcam", function( um )
		PCMod.Beam.LockCam( um:ReadLong(), LocalPlayer() )
	end )
end

// ---------------------------------------------------------------------------------------------------------
// UnlockCam - Tells a client to unlock the cam
// ---------------------------------------------------------------------------------------------------------
function PCMod.Beam.UnlockCam( ply )
	if (SERVER) then
		if ((!ply) || (!ply:IsValid()) || (!ply:IsPlayer())) then return end
		umsg.Start( "pcmod_unlockcam", ply ); umsg.End()
		return
	end
	if (CLIENT) then
		if (ply != LocalPlayer()) then return end
		
		local oldid = PCMod.Gui.CamLockID
		PCMod.Gui.CamLocked = false
		PCMod.Gui.CamLockID = 0
		
		gui.EnableScreenClicker( false )
		LocalPlayer():Freeze( false )
		
		PCMod.Gui.ShowLockFrame( false )
		PCMod.Beam.UnlockKeyboard( LocalPlayer() )
		PCMod.Gui.EnableHackyClicky( false )
		PCMod.SDraw.DevFocus = ""

		if (PCMod.SDraw && PCMod.SDraw.SetFullscreenUI) then
			PCMod.SDraw.SetFullscreenUI( false, oldid )
		end
		
		PCMod.Cam.Trigger( "unlock" )
	end
end
if (CLIENT) then
	usermessage.Hook( "pcmod_unlockcam", function( um )
		PCMod.Beam.UnlockCam( LocalPlayer() )
	end )
end

// ---------------------------------------------------------------------------------------------------------
// LockKeyboard - Tells a client to lock to keyboard
// ---------------------------------------------------------------------------------------------------------
function PCMod.Beam.LockKeyboard( ply, entid )
	if (!entid) then entid = 0 end
	if (SERVER) then
		if ((!ply) || (!ply:IsValid()) || (!ply:IsPlayer())) then return end
		umsg.Start( "pcmod_lockkeyboard", ply ); umsg.Long( entid ); umsg.End()
		return
	end
	if (CLIENT) then
		PCMod.SDraw.DrawKeyboard = true
		PCMod.SDraw.KeyboardEntID = entid
		PCMod.EnableCapture( true )
		if (PCMod.Gui.KeyBoard) then
			PCMod.Gui.KeyBoard:SetVisible( true )
		else
			PCMod.Msg( "No keyboard derma panel!", true )
		end
		// Keep the click-catcher above the keyboard while it is visible.
		if (PCMod.Gui.HackyClicky) then PCMod.Gui.HackyClicky:PerformLayout() end
	end
end
if (CLIENT) then
	usermessage.Hook( "pcmod_lockkeyboard", function( um )
		PCMod.Beam.LockKeyboard( nil, um:ReadLong() )
	end )
end

// ---------------------------------------------------------------------------------------------------------
// UnlockKeyboard - Tells a client to unlock the keyboard
// ---------------------------------------------------------------------------------------------------------
function PCMod.Beam.UnlockKeyboard( ply )
	if (SERVER) then
		if ((!ply) || (!ply:IsValid()) || (!ply:IsPlayer())) then return end
		umsg.Start( "pcmod_unlockkeyboard", ply ); umsg.End()
		return
	end
	if (CLIENT) then
		PCMod.SDraw.DrawKeyboard = false
		PCMod.SDraw.KeyboardEntID = 0
		PCMod.EnableCapture( false )
		if (PCMod.Gui.KeyBoard) then
			PCMod.Gui.KeyBoard:SetVisible( false )
		else
			//PCMod.Msg( "No keyboard derma panel!", true )
		end
		// The keyboard is gone: let the click-catcher cover the whole screen again.
		if (PCMod.Gui.HackyClicky) then PCMod.Gui.HackyClicky:PerformLayout() end
	end
end
if (CLIENT) then
	usermessage.Hook( "pcmod_unlockkeyboard", function()
		PCMod.Beam.UnlockKeyboard()
	end )
end

if (SERVER) then
	
	// ---------------------------------------------------------------------------------------------------------
	// BeamPorts - Beams an entity's ports to the client
	// ---------------------------------------------------------------------------------------------------------
	function PC_BeamPorts( ent, ply )
		// Validate entity
		if ((!ent) || (!ent:IsValid()) || (!ent.IsPCMod)) then return end
		if ((!ply) || (!ply:IsValid()) || (!ply:IsPlayer())) then return end
		
		// Get the ports
		local ports = ent:Ports()
		
		//PCMod.Msg( "Sending port data...", true )
		
		// Compile a table to send
		local tmp = {}
		tmp.EntID = ent:EntIndex()
		local cnt
		for cnt=1, #ports do
			table.insert( tmp, { ports[ cnt ].Type, ports[ cnt ].Connected, ports[ cnt ].Name } )
		end
		local str = PCMod.TableToString( tmp )
		--PrintTable(tmp);
		--print(str)
		
		// Send the table
		PCMod.Beam.BeamString( ply, "portdata", str )
	end
	
	// ---------------------------------------------------------------------------------------------------------
	// PortSelected - Pushes a selected port through to the toolgun
	// ---------------------------------------------------------------------------------------------------------
	function PC_PortSelected( pl, com, args )
		local tool = pl:GetActiveWeapon()
		
		if ((!tool) || (!tool:IsValid())) then return end
		
		if (tool:GetClass() == "gmod_tool") then
		
			local obj = tool:GetTable():GetToolObject()
			
			//PCMod.Msg( "(TOOLGUN) Selecting port " .. args[2] .. " on entity " .. args[1], true )
			
			if (obj && obj.SelectPort) then
				obj:SelectPort( tonumber( args[1] ), tonumber( args[2] ) )
			end
			
			return
		end
		
		if (tool:GetClass() == "pcmod_wireswep") then
		
			local obj = tool:GetTable().ToolMode
			
			//PCMod.Msg( "(SWEP) Selecting port " .. args[2] .. " on entity " .. args[1], true )
			
			if (obj && obj.SelectPort) then
				obj:SelectPort( tonumber( args[1] ), tonumber( args[2] ) )
			end
			
			return
		end
		
		//PCMod.Msg( "Invalid weapon! (pc_selport)", true )
	end
	concommand.Add( "pc_selport", PC_PortSelected )
	
	// ---------------------------------------------------------------------------------------------------------
	// AskForPort - Sends a port request to the client
	// ---------------------------------------------------------------------------------------------------------
	function PC_AskForPort( ply, entid, porttype, unwire )
		if (ply && (!ply:IsValid() || !ply:IsPlayer())) then return end -- nil still broadcasts
		if (!porttype) then porttype = "" end
		if (!unwire) then unwire = false end
		umsg.Start( "pcmod_askport", ply )
			umsg.Long( entid )
			umsg.String( porttype )
			umsg.Bool( unwire )
		umsg.End()
	end
	
end


if (CLIENT) then

	// ---------------------------------------------------------------------------------------------------------
	// PortsRecieved - Reads the ports into an entity
	// ---------------------------------------------------------------------------------------------------------
	function PC_PortsRecieved( str )
		local tbl = PCMod.StringToTable( str )
		if !tbl then return end
		--PCMod.Msg( str, true )
		local entid = tbl.EntID
		tbl.EntID = nil
		local tmp = {}
		//PCMod.Msg( "Ports recieved! (" .. tostring( #tbl ) .. ")", true )
		local cnt
		for k, v in pairs( tbl ) do
			
			tmp[ tonumber( k ) ] = { Type=v[1], Connected=v[2], Name=v[3] }
		end
		PCMod.PortData[ entid ] = tmp
		
	end
	PCMod.Beam.Hook( "portdata", PC_PortsRecieved )
	
	// ---------------------------------------------------------------------------------------------------------
	// PortAskedFor - Forwards the request to the Gui library
	// ---------------------------------------------------------------------------------------------------------
	function PC_PortAskedFor( um )
		local entid = um:ReadLong()
		local porttype = um:ReadString()
		local unwire = um:ReadBool()
		if ((porttype == "NA") || (porttype == "")) then porttype = nil end
		PCMod.Gui.AskForPort( entid, porttype, (!!unwire) ) -- !!unwire means convert to evaluated state
	end
	usermessage.Hook( "pcmod_askport", PC_PortAskedFor )

end