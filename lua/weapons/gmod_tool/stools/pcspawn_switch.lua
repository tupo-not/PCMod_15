if (!PCTool) then include( "pcmod/sh_tool.lua" ) end

TOOL.Name = "Switch"
TOOL.Class = "pcspawn_switch"
TOOL.Desc = "Spawns a network switch"
TOOL.Inst = {
	{ "Spawn a switch. Choose Ethernet or Optical in the panel." }
}

TOOL.ModelList = {
	"models/props_lab/reciever01a.mdl"
}

TOOL.Type = "spawner"
TOOL.SpawnType = "Networking"

TOOL.EntName = "Switch"
TOOL.EntClass = "pcmod_switch"
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

TOOL.ClientConVar[ "mode" ] = "ethernet"

if (SERVER) then

	function TOOL:BuildSetupData()
		local mode = self:GetClientInfo( "mode" )
		if (mode != "optic") then mode = "ethernet" end
		return { Mode = mode }
	end

end

if (CLIENT) then

	function TOOL.BuildCPanel( panel )
		local pf = "Tool_pcspawn_switch_"

		// Header
		panel:AddControl( "Header", { Text = "#" .. pf .. "name", Description = "#" .. pf .. "desc" } )

		// Model select
		panel:AddControl( "PropSelect", { Label = "Model:",
							ConVar = "pcspawn_switch_model",
							Category = "pcmod",
							Models = list.Get( "mdls_pcspawn_switch" ) } )

		// Port configuration
		panel:AddControl( "ComboBox", { Label = "Configuration:",
							ConVar = "pcspawn_switch_mode",
							Category = "pcmod",
							Options = {
								Ethernet = { pcspawn_switch_mode = "ethernet" },
								Optical = { pcspawn_switch_mode = "optic" }
							} } )
	end

end
