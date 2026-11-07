if (!PCTool) then include( "pcmod/sh_tool.lua" ) end

TOOL.Name = "Router"
TOOL.Class = "pcspawn_erouter"
TOOL.Desc = "Spawns a router with an Ethernet WAN uplink"
TOOL.Inst = {
	{ "Spawn a router. Its WAN uplink uses a normal network cable." }
}

TOOL.ModelList = {
	"models/props_lab/reciever01a.mdl"
}

TOOL.Type = "spawner"
TOOL.SpawnType = "Networking"

TOOL.EntName = "Router"
TOOL.EntClass = "pcmod_erouter"
TOOL.DefaultMax = 8
TOOL.Model = TOOL.ModelList[ 1 ]

local dat = PCTool.RegisterSTool( TOOL )
table.Merge( TOOL, dat )

if CLIENT then
	language.Add( "tool."..TOOL.Class..".name", TOOL.Name )
	language.Add( "tool."..TOOL.Class..".desc", TOOL.Desc )
	if TOOL.Inst then
		for k,v in pairs(TOOL.Inst) do
			language.Add( "tool."..TOOL.Class.."."..(k-1), v[1] )
		end
	end
end

TOOL.ClientConVar[ "wireless" ] = 0

if (SERVER) then

	function TOOL:BuildSetupData()
		return { Wireless = (self:GetClientNumber( "wireless" ) == 1)}
	end

end

if (CLIENT) then

	function TOOL.BuildCPanel( panel )
		local pf = "Tool_pcspawn_erouter_"
	
		// Header
		panel:AddControl( "Header", { Text = "#" .. pf .. "name", Description = "#" .. pf .. "desc" } )
		
		// Model select
		panel:AddControl( "PropSelect", { Label = "Model:",
							ConVar = "pcspawn_erouter_model",
							Category = "pcmod",
							Models = list.Get( "mdls_pcspawn_erouter" ) } )
							
		// Wireless option
		panel:AddControl( "CheckBox", { Label = "Wireless:",
							Description = "Enable Wireless",
							Command = "pcspawn_erouter_wireless" } )
	end
	
end

// I suggest any people looking to learn to make STools do NOT look and learn from this code, it is not the conventional way of doing it. -thomasfn
