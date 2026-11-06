if (!PCTool) then include( "pcmod/sh_tool.lua" ) end

TOOL.Name = "Audio Amplifier"
TOOL.Class = "pcspawn_splitter"
TOOL.Desc = "Spawns an audio amplifier"
TOOL.Inst = {
	{ "Spawn an audio amplifier" }
}

TOOL.ModelList = {
	"models/props_lab/tpplug.mdl"
}

TOOL.Type = "spawner"
TOOL.SpawnType = "Hardware"

TOOL.EntName = "Audio Amplifier"
TOOL.EntClass = "pcmod_splitter"
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

if (SERVER) then

	function TOOL:BuildSetupData()
		return {}
	end

end

if (CLIENT) then

	function TOOL.BuildCPanel( panel )
		local pf = "Tool_pcspawn_splitter_"
	
		// Header
		panel:AddControl( "Header", { Text = "#" .. pf .. "name", Description = "#" .. pf .. "desc" } )
		
		// Model select
		panel:AddControl( "PropSelect", { Label = "Model:",
							ConVar = "pcspawn_splitter_model",
							Category = "pcmod",
							Models = list.Get( "mdls_pcspawn_splitter" ) } )
							
	end
	
end

// I suggest any people looking to learn to make STools do NOT look and learn from this code, it is not the conventional way of doing it. -thomasfn