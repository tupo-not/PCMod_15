// ---------------------------------------------------------------------------------------------------------
// pc_camlink.lua - Camera Link tool for Alarmz.
// Holding this tool enables the camera context overlay (cl_alarmz.lua); the
// actual connect/disconnect flow stays on the overlay keys.
//   LMB on a camera: start connecting (same as E). LMB on a screen while picking:
//   confirm. RMB on a linked camera: disconnect (same as RMB on the overlay).
// ---------------------------------------------------------------------------------------------------------

TOOL.Category		= "PCMod - Cameras"
TOOL.Name			= "#Camera Link"
TOOL.Tab			= "PCmod"
TOOL.Command		= nil
TOOL.ConfigName		= ""

if (CLIENT) then
	language.Add( "tool.pc_camlink.name", "Camera Link" )
	language.Add( "tool.pc_camlink.desc", "Connect Wiremod RT cameras to PCMod screens so they show up in the Alarmz program. Hold the tool to see the camera overlay." )
	language.Add( "tool.pc_camlink.0", "1) Hold this tool and look at a Wiremod RT camera - an overlay shows its ID and status." )
	language.Add( "tool.pc_camlink.1", "2) LMB or E on the camera - start connecting (a locked camera asks for its password first)." )
	language.Add( "tool.pc_camlink.2", "3) Aim at a PCMod screen and press LMB or E - the camera is linked and appears in Alarmz on that PC. One camera can be linked to several PCs." )
	language.Add( "tool.pc_camlink.3", "4) RMB on a linked camera (overlay) - disconnect it." )
	language.Add( "tool.pc_camlink.4", "The first player to connect a camera may set a password for it; only that player can change or remove it." )

	function TOOL:BuildCPanel( CPanel )
		CPanel:AddControl( "Header", { Text = "#Tool_pc_camlink_name", Description = "#Tool_pc_camlink_desc" } )
		CPanel:AddControl( "Help", { Text = "#tool.pc_camlink.0" } )
		CPanel:AddControl( "Help", { Text = "#tool.pc_camlink.1" } )
		CPanel:AddControl( "Help", { Text = "#tool.pc_camlink.2" } )
		CPanel:AddControl( "Help", { Text = "#tool.pc_camlink.3" } )
		CPanel:AddControl( "Help", { Text = "#tool.pc_camlink.4" } )
	end
end

function TOOL:LeftClick( trace )
	if ((!game.SinglePlayer()) && (!IsFirstTimePredicted())) then return end
	if (CLIENT && PCMod.AlarmzCL) then
		if (PCMod.AlarmzCL.OnUse( "+use" )) then return true end
	end
	return false
end

function TOOL:RightClick( trace )
	if ((!game.SinglePlayer()) && (!IsFirstTimePredicted())) then return end
	if (CLIENT && PCMod.AlarmzCL) then
		if (PCMod.AlarmzCL.OnUse( "+attack2" )) then return true end
	end
	return false
end

function TOOL:Reload( trace )
	return false
end

function TOOL:DrawHUD()
	// The overlay itself is drawn by cl_alarmz.lua while this tool is held.
end
