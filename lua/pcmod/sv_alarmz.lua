
// ---------------------------------------------------------------------------------------------------------
// sv_alarmz.lua - Server side of the Alarmz manual camera connection system
// ---------------------------------------------------------------------------------------------------------
// Single source of truth for camera<->PC links and per-camera passwords:
//   PCMod.Alarmz.Cams[ camEntIndex ] = {
//       salt    = per-camera random salt (string),
//       hash    = util.SHA256( salt .. ":" .. password ) or nil when no password,
//       ownerID = SteamID of the FIRST player who connected the camera
//                 (allowed to set/change/remove the password),
//       links   = { [pcEntIndex] = true } - PCs (via their screen) the camera is shown on
//   }
// Passwords are only stored/checked here on the server, as salted SHA-256 hashes;
// the plaintext or the hash is never sent to clients. Removing a monitor/PC only
// drops its link - the camera password survives. Removing the camera drops
// everything about it.

PCMod.Alarmz = PCMod.Alarmz or {}
PCMod.Alarmz.Cams = PCMod.Alarmz.Cams or {}

local CAM_CLASS = "gmod_wire_rt_camera"
local CONNECT_RANGE = 4096 -- max distance player<->camera and player<->screen (units)

util.AddNetworkString( "pcmod_alarmz_req" )    // client -> server: action, camIdx, monIdx, pass
util.AddNetworkString( "pcmod_alarmz_state" )  // server -> client: camIdx, hasPass, isOwner, first, links
util.AddNetworkString( "pcmod_alarmz_result" ) // server -> client: ok, msg, camIdx, canSetPass

// --- password helpers (server only) ------------------------------------------------------------------

function PCMod.Alarmz.Hash( salt, pass )
	return util.SHA256( tostring( salt ) .. ":" .. tostring( pass ) )
end

function PCMod.Alarmz.NewSalt()
	local a = math.random( 0, 0x7FFFFFFF )
	local b = math.random( 0, 0x7FFFFFFF )
	return string.format( "%08x%08x", a, b ) .. string.format( "%f", CurTime() )
end

// --- camera entry helpers -----------------------------------------------------------------------------

function PCMod.Alarmz.CamEntry( camIdx )
	return PCMod.Alarmz.Cams[ camIdx ]
end

function PCMod.Alarmz.EnsureCam( camIdx )
	if (!PCMod.Alarmz.Cams[ camIdx ]) then
		PCMod.Alarmz.Cams[ camIdx ] = { salt = nil, hash = nil, ownerID = nil, links = {}, authed = {} }
	end
	return PCMod.Alarmz.Cams[ camIdx ]
end

function PCMod.Alarmz.IsCamEnt( ent )
	return (IsValid( ent ) && (ent:GetClass() == CAM_CLASS))
end

function PCMod.Alarmz.CamEnt( camIdx )
	local ent = ents.GetByIndex( camIdx )
	if (!PCMod.Alarmz.IsCamEnt( ent )) then return nil end
	return ent
end

function PCMod.Alarmz.InRange( ply, ent )
	if ((!IsValid( ply )) || (!IsValid( ent ))) then return false end
	local d = ply:GetPos():DistToSqr( ent:GetPos() )
	return (d <= (CONNECT_RANGE * CONNECT_RANGE))
end

// Resolve a screen entity to the computer that drives it. A PC/laptop IS the
// computer; a standalone monitor is resolved through its VGA port link.
function PCMod.Alarmz.ResolvePC( monEnt )
	if (!IsValid( monEnt )) then return nil end
	if (monEnt.IsPCMod && monEnt.IsComputer) then return monEnt end
	if (monEnt.IsPCMod && monEnt.IsScreen && monEnt.Ports) then
		for _, p in ipairs( monEnt:Ports() or {} ) do
			if ((p.Type == "vga") && p.Connected && IsValid( p.ConEnt ) && p.ConEnt.IsPCMod && p.ConEnt.IsComputer) then
				return p.ConEnt
			end
		end
	end
	return nil
end

// Sorted list of camera entindexes currently linked to a PC
function PCMod.Alarmz.CamsForPC( pcIdx )
	local out = {}
	for camIdx, entry in pairs( PCMod.Alarmz.Cams ) do
		if (entry.links && entry.links[ pcIdx ]) then table.insert( out, camIdx ) end
	end
	table.sort( out )
	return out
end

// The alarmz program instance running on a PC (nil when absent)
function PCMod.Alarmz.GetProg( pcIdx )
	local d = PCMod.Data[ pcIdx ]
	if ((!d) || (!d.Drivers) || (!d.Drivers[ "gen_bios" ])) then return nil end
	local os = d.Drivers[ "gen_bios" ].OS
	if ((!os) || (!os.Progs)) then return nil end
	return os.Progs[ "alarmz" ]
end

// Push the linked camera list into the alarmz window of a PC
function PCMod.Alarmz.PushLinksToPC( pcIdx )
	local prog = PCMod.Alarmz.GetProg( pcIdx )
	if (prog) then
		prog.DeviceData.Cams = PCMod.Alarmz.CamsForPC( pcIdx )
		prog:UpdateSS()
	end
end

// --- state / result network messages ------------------------------------------------------------------

function PCMod.Alarmz.PushCamState( camIdx, ply )
	local entry = PCMod.Alarmz.CamEntry( camIdx )
	if (!entry) then return end
	local links = {}
	for pcIdx in pairs( entry.links or {} ) do table.insert( links, pcIdx ) end
	table.sort( links )
	net.Start( "pcmod_alarmz_state" )
		net.WriteUInt( camIdx, 32 )
		net.WriteBool( entry.hash != nil )
		net.WriteBool( ply && (entry.ownerID == ply:SteamID()) || false )
		net.WriteUInt( #links, 16 ) -- 8 bits truncated the count above 255 links
		for _, pcIdx in ipairs( links ) do net.WriteUInt( pcIdx, 32 ) end
	if (ply) then
		net.Send( ply )
	else
		net.Broadcast()
	end
end

function PCMod.Alarmz.SendResult( ply, ok, msg, camIdx, canSetPass )
	net.Start( "pcmod_alarmz_result" )
		net.WriteBool( ok == true )
		net.WriteString( msg or "" )
		net.WriteUInt( camIdx or 0, 32 )
		net.WriteBool( canSetPass == true )
	net.Send( ply )
	if (PCMod.Notice) then PCMod.Notice( msg, ply ) end
end

// --- actions -------------------------------------------------------------------------------------------

// "begin": validate the camera and send its state; the first connector becomes
// the password owner. Returns nothing - the reply goes through PushCamState.
function PCMod.Alarmz.Begin( ply, camIdx )
	local cam = PCMod.Alarmz.CamEnt( camIdx )
	if ((!IsValid( ply )) || (!cam)) then return end
	if (!PCMod.Alarmz.InRange( ply, cam )) then
		PCMod.Alarmz.SendResult( ply, false, "Camera too far away", camIdx, false )
		return
	end
	local entry = PCMod.Alarmz.EnsureCam( camIdx )
	local first = (entry.ownerID == nil)
	if (first) then entry.ownerID = ply:SteamID() end
	PCMod.Alarmz.PushCamState( camIdx, ply )
end

// Server-side password check - the only place a password is verified.
function PCMod.Alarmz.CheckPass( entry, pass )
	if (!entry.hash) then return true end
	if (pass == nil) then return false end
	return (PCMod.Alarmz.Hash( entry.salt, pass ) == entry.hash)
end

// A player may skip the password when the camera is open, when they are the
// first-connector owner, or when they already passed "auth" for this camera
// this session (so the later "connect" is not rejected with Wrong password).
function PCMod.Alarmz.CanBypassPass( entry, ply )
	if (!entry.hash) then return true end
	if (entry.ownerID == ply:SteamID()) then return true end
	return (entry.authed && entry.authed[ ply:SteamID() ] == true)
end

// "auth": password-only check (client asks before entering monitor-pick mode)
function PCMod.Alarmz.Auth( ply, camIdx, pass )
	local entry = PCMod.Alarmz.CamEntry( camIdx )
	if ((!IsValid( ply )) || (!entry) || (!PCMod.Alarmz.CamEnt( camIdx ))) then return end
	if (!PCMod.Alarmz.InRange( ply, PCMod.Alarmz.CamEnt( camIdx ) )) then
		PCMod.Alarmz.SendResult( ply, false, "Camera too far away", camIdx, false )
		return
	end
	if (PCMod.Alarmz.CheckPass( entry, pass )) then
		entry.authed[ ply:SteamID() ] = true
		PCMod.Alarmz.SendResult( ply, true, "Password accepted", camIdx, false )
	else
		PCMod.Alarmz.SendResult( ply, false, "Wrong camera password", camIdx, false )
	end
end

// "connect": link the camera to the PC behind the aimed screen.
function PCMod.Alarmz.Connect( ply, camIdx, monIdx, pass )
	local cam = PCMod.Alarmz.CamEnt( camIdx )
	if ((!IsValid( ply )) || (!cam)) then return end
	if (!PCMod.Alarmz.InRange( ply, cam )) then
		PCMod.Alarmz.SendResult( ply, false, "Camera too far away", camIdx, false )
		return
	end
	local mon = ents.GetByIndex( monIdx )
	if ((!IsValid( mon )) || (!mon.IsPCMod) || (!mon.IsScreen)) then
		PCMod.Alarmz.SendResult( ply, false, "Not a PCMod screen", camIdx, false )
		return
	end
	if (!PCMod.Alarmz.InRange( ply, mon )) then
		PCMod.Alarmz.SendResult( ply, false, "Screen too far away", camIdx, false )
		return
	end
	local pc = PCMod.Alarmz.ResolvePC( mon )
	if (!pc) then
		PCMod.Alarmz.SendResult( ply, false, "Screen is not connected to a computer (VGA)", camIdx, false )
		return
	end
	local entry = PCMod.Alarmz.EnsureCam( camIdx )
	if ((!PCMod.Alarmz.CanBypassPass( entry, ply )) && (!PCMod.Alarmz.CheckPass( entry, pass ))) then
		PCMod.Alarmz.SendResult( ply, false, "Wrong camera password", camIdx, false )
		return
	end
	local pcIdx = pc:EntIndex()
	if (entry.links[ pcIdx ]) then
		PCMod.Alarmz.SendResult( ply, false, "Camera #" .. camIdx .. " is already connected to PC #" .. pcIdx, camIdx, false )
		return
	end
	entry.links[ pcIdx ] = true
	PCMod.Alarmz.PushLinksToPC( pcIdx )
	PCMod.Alarmz.PushCamState( camIdx )
	// The first connector may set a password right after connecting
	local canSetPass = ((entry.ownerID == ply:SteamID()) && (entry.hash == nil))
	PCMod.Alarmz.SendResult( ply, true, "Camera #" .. camIdx .. " connected to PC #" .. pcIdx, camIdx, canSetPass )
end

// "disconnect": unlink the camera from a screen's PC. monIdx == 0 picks the first link.
function PCMod.Alarmz.Disconnect( ply, camIdx, monIdx )
	local entry = PCMod.Alarmz.CamEntry( camIdx )
	if ((!IsValid( ply )) || (!entry)) then return end
	local cam = PCMod.Alarmz.CamEnt( camIdx )
	if (cam && (!PCMod.Alarmz.InRange( ply, cam ))) then
		PCMod.Alarmz.SendResult( ply, false, "Camera too far away", camIdx, false )
		return
	end
	if (!PCMod.Alarmz.CanBypassPass( entry, ply )) then
		PCMod.Alarmz.SendResult( ply, false, "Wrong camera password", camIdx, false )
		return
	end
	local pcIdx = 0
	if (monIdx && (monIdx != 0)) then
		local mon = ents.GetByIndex( monIdx )
		if (IsValid( mon ) && (!PCMod.Alarmz.InRange( ply, mon ))) then
			PCMod.Alarmz.SendResult( ply, false, "Screen too far away", camIdx, false )
			return
		end
		local pc = PCMod.Alarmz.ResolvePC( mon )
		if (pc) then pcIdx = pc:EntIndex() end
	else
		// no screen given: drop the lowest linked PC (deterministic)
		for k in pairs( entry.links or {} ) do
			if ((pcIdx == 0) || (k < pcIdx)) then pcIdx = k end
		end
	end
	if ((pcIdx == 0) || (!entry.links[ pcIdx ])) then
		PCMod.Alarmz.SendResult( ply, false, "Camera #" .. camIdx .. " is not connected there", camIdx, false )
		return
	end
	entry.links[ pcIdx ] = nil
	PCMod.Alarmz.PushLinksToPC( pcIdx )
	PCMod.Alarmz.PushCamState( camIdx )
	PCMod.Alarmz.SendResult( ply, true, "Camera #" .. camIdx .. " disconnected from PC #" .. pcIdx, camIdx, false )
end

// "setpass"/"removepass": only the first connector (ownerID) may touch the password.
function PCMod.Alarmz.SetPass( ply, camIdx, pass )
	local entry = PCMod.Alarmz.CamEntry( camIdx )
	if ((!IsValid( ply )) || (!entry) || (!PCMod.Alarmz.CamEnt( camIdx ))) then return end
	if (!PCMod.Alarmz.InRange( ply, PCMod.Alarmz.CamEnt( camIdx ) )) then
		PCMod.Alarmz.SendResult( ply, false, "Camera too far away", camIdx, false )
		return
	end
	if (entry.ownerID != ply:SteamID()) then
		PCMod.Alarmz.SendResult( ply, false, "Only the camera owner can change the password", camIdx, false )
		return
	end
	if ((!pass) || (pass == "")) then
		entry.hash = nil
		entry.salt = nil
		PCMod.Alarmz.PushCamState( camIdx )
		PCMod.Alarmz.SendResult( ply, true, "Camera #" .. camIdx .. " password removed", camIdx, false )
		return
	end
	entry.salt = PCMod.Alarmz.NewSalt()
	entry.hash = PCMod.Alarmz.Hash( entry.salt, pass )
	entry.authed = {} -- password changed: previous auths no longer apply
	PCMod.Alarmz.PushCamState( camIdx )
	PCMod.Alarmz.SendResult( ply, true, "Camera #" .. camIdx .. " password set", camIdx, false )
end

// --- net receiver + cleanup ----------------------------------------------------------------------------

net.Receive( "pcmod_alarmz_req", function( len, ply )
	if (!IsValid( ply )) then return end
	// Per-player rate limit: every accepted action triggers net sends
	// (PushCamState -> Broadcast), so an unthrottled client could spam them.
	ply._pcmodAlarmzNext = ply._pcmodAlarmzNext or 0
	if (CurTime() < ply._pcmodAlarmzNext) then return end
	ply._pcmodAlarmzNext = CurTime() + 0.2
	local action = net.ReadString()
	local camIdx = net.ReadUInt( 32 )
	local monIdx = net.ReadUInt( 32 )
	local pass = net.ReadString()
	if (action == "begin") then
		PCMod.Alarmz.Begin( ply, camIdx )
	elseif (action == "auth") then
		PCMod.Alarmz.Auth( ply, camIdx, pass )
	elseif (action == "connect") then
		PCMod.Alarmz.Connect( ply, camIdx, monIdx, pass )
	elseif (action == "disconnect") then
		PCMod.Alarmz.Disconnect( ply, camIdx, monIdx )
	elseif (action == "setpass") then
		PCMod.Alarmz.SetPass( ply, camIdx, pass )
	elseif (action == "state") then
		PCMod.Alarmz.PushCamState( camIdx, ply )
	end
end )

// Removing the camera drops its password and all links; removing a monitor/PC
// only drops the links that pointed at it (the camera password survives).
// Drop per-player auth flags when they leave, so entry.authed does not grow
// without bound across reconnects.
hook.Add( "PlayerDisconnected", "PCMod.Alarmz.CleanAuth", function( ply )
	local sid = ply:SteamID()
	for camIdx, entry in pairs( PCMod.Alarmz.Cams or {} ) do
		if (entry.authed) then entry.authed[ sid ] = nil end
	end
end )

hook.Add( "EntityRemoved", "PCMod.Alarmz.Cleanup", function( ent )
	if (!IsValid( ent )) then return end
	if (ent:GetClass() == CAM_CLASS) then
		local camIdx = ent:EntIndex()
		local entry = PCMod.Alarmz.CamEntry( camIdx )
		PCMod.Alarmz.Cams[ camIdx ] = nil
		if (entry) then
			for pcIdx in pairs( entry.links or {} ) do
				PCMod.Alarmz.PushLinksToPC( pcIdx )
			end
		end
	elseif (ent.IsPCMod) then
		// A removed PCMod entity drops the links that pointed at it - directly
		// (it was the PC) or through its screen (a standalone monitor: the link
		// is keyed by the PC behind its VGA port). The camera password survives.
		local resolved = { [ ent:EntIndex() ] = true }
		local pc = PCMod.Alarmz.ResolvePC( ent )
		if (pc) then resolved[ pc:EntIndex() ] = true end
		for camIdx, entry in pairs( PCMod.Alarmz.Cams ) do
			if (entry.links) then
				for pcIdx in pairs( entry.links ) do
					if (resolved[ pcIdx ]) then
						entry.links[ pcIdx ] = nil
						PCMod.Alarmz.PushCamState( camIdx )
					end
				end
			end
		end
	end
end )
