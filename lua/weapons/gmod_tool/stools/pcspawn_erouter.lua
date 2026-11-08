if (!PCTool) then include( "pcmod/sh_tool.lua" ) end

// Deprecated: the Router and LAN Modem spawn tools are merged into
// pcspawn_router, which selects the WAN uplink medium (fibre or Ethernet).
// This file is kept only so existing pcmod_erouter entities still paste and
// their limit cvar keeps working; it registers no tool of its own.

cleanup.Register( "pcmod_erouters" )
CreateConVar( "sbox_maxpcmod_erouters", 8, { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY } )

if (SERVER) then
	if (duplicator && duplicator.RegisterEntityClass) then
		duplicator.RegisterEntityClass( "pcmod_erouter", PCTool.SpawnEntity, "Model", "Pos", "Ang", "Class", "harddrive" )
	end
end
