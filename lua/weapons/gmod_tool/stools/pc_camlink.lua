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
	language.Add( "tool.pc_camlink.desc", "Connect Wiremod RT cameras to PCMod screens (shows in Alarmz)" )
	language.Add( "tool.pc_camlink.0", "Hold the tool to see the camera overlay. LMB/E on a camera: connect. LMB on a screen while picking: confirm. RMB on a linked camera: disconnect." )
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
