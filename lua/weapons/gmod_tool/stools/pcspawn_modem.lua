if (!PCTool) then include( "pcmod/sh_tool.lua" ) end

TOOL.Name = "Modem"
TOOL.Class = "pcspawn_modem"
TOOL.Desc = "Spawns a fibre-to-Ethernet modem"
TOOL.Inst = {
	{ "Spawn a modem. It bridges one fibre uplink to one Ethernet port without routing." }
}

TOOL.ModelList = {
	"models/props_lab/reciever01b.mdl"
}

TOOL.Type = "spawner"
TOOL.SpawnType = "Networking"

TOOL.EntName = "Modem"
TOOL.EntClass = "pcmod_modem"
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
		local pf = "Tool_pcspawn_modem_"
	
		// Header
		panel:AddControl( "Header", { Text = "#" .. pf .. "name", Description = "#" .. pf .. "desc" } )
		
		// Model select
		panel:AddControl( "PropSelect", { Label = "Model:",
							ConVar = "pcspawn_modem_model",
							Category = "pcmod",
							Models = list.Get( "mdls_pcspawn_modem" ) } )
	end
	
end

// I suggest any people looking to learn to make STools do NOT look and learn from this code, it is not the conventional way of doing it. -thomasfn
