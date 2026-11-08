if (!PCTool) then include( "pcmod/sh_tool.lua" ) end

TOOL.Name = "Router"
TOOL.Class = "pcspawn_router"
TOOL.Desc = "Spawns a LAN router; choose the WAN uplink type"
TOOL.Inst = {
	{ "Spawn a router. Choose Fibre or Ethernet for its WAN uplink in the panel." }
}

TOOL.ModelList = {
	"models/props_lab/reciever01a.mdl",
	"models/PCMod/wrt54g.mdl",
	"models/props_lab/reciever01b.mdl"
}

TOOL.Type = "spawner"
TOOL.SpawnType = "Networking"

TOOL.EntName = "Router"
TOOL.EntClass = "pcmod_router"
TOOL.DefaultMax = 8
TOOL.Model = TOOL.ModelList[ 1 ]

local dat = PCTool.RegisterSTool( TOOL )
table.Merge( TOOL, dat )

if CLIENT then
	language.Add( "tool."..TOOL.Class..".name", TOOL.Name )
	language.Add( "tool."..TOOL.Class..".desc", TOOL.Desc )
	language.Add( "Cleanup_pcmod_erouters", "Routers" )
	language.Add( "sboxlimit_pcmod_erouters", "You've hit the Router limit!" )
	if TOOL.Inst then
		for k,v in pairs(TOOL.Inst) do
			language.Add( "tool."..TOOL.Class.."."..(k-1), v[1] )
		end
	end
end

TOOL.ClientConVar[ "wireless" ] = 0
// "optic" = fibre WAN (LAN Modem), "network" = Ethernet WAN (Router).
TOOL.ClientConVar[ "uplink" ] = "optic"

// The Ethernet variant is a separate entity class for saved-world and
// program compatibility, but it is spawned from this one tool.
cleanup.Register( "pcmod_erouters" )
CreateConVar( "sbox_maxpcmod_erouters", TOOL.DefaultMax, { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY } )

if (SERVER) then

	function TOOL:GetUplink()
		local up = self:GetClientInfo( "uplink" )
		if (up == "network") then return "network" end
		return "optic"
	end

	function TOOL:GetSpawnClass()
		return (self:GetUplink() == "network") and "pcmod_erouter" or "pcmod_router"
	end

	function TOOL:BuildSetupData()
		return {
			Wireless = (self:GetClientNumber( "wireless" ) == 1),
			Uplink = self:GetUplink(),
		}
	end

	// Existing pcmod_erouter entities still paste correctly even though their
	// own spawn tool is gone.
	if (duplicator && duplicator.RegisterEntityClass) then
		duplicator.RegisterEntityClass( "pcmod_erouter", PCTool.SpawnEntity, "Model", "Pos", "Ang", "Class", "harddrive" )
	end

end

if (CLIENT) then

	function TOOL.BuildCPanel( panel )
		local pf = "Tool_pcspawn_router_"
	
		// Header
		panel:AddControl( "Header", { Text = "#" .. pf .. "name", Description = "#" .. pf .. "desc" } )
		
		// Model select
		panel:AddControl( "PropSelect", { Label = "Model:",
							ConVar = "pcspawn_router_model",
							Category = "pcmod",
							Models = list.Get( "mdls_pcspawn_router" ) } )

		// WAN uplink medium
		panel:AddControl( "ComboBox", { Label = "WAN uplink:",
							ConVar = "pcspawn_router_uplink",
							Category = "pcmod",
							Options = {
								[ "Fibre (LAN Modem)" ] = { pcspawn_router_uplink = "optic" },
								[ "Ethernet (Router)" ] = { pcspawn_router_uplink = "network" }
							} } )
							
		// Wireless option
		panel:AddControl( "CheckBox", { Label = "Wireless:",
							Description = "Enable Wireless",
							Command = "pcspawn_router_wireless" } )
	end
	
end

// I suggest any people looking to learn to make STools do NOT look and learn from this code, it is not the conventional way of doing it. -thomasfn
