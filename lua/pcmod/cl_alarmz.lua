
// ---------------------------------------------------------------------------------------------------------
// cl_alarmz.lua - Client side: look-at overlay + E-key flow to manually connect
// Wiremod RT cameras to PCMod screens (server authority: sv_alarmz.lua)
// ---------------------------------------------------------------------------------------------------------

PCMod.AlarmzCL = PCMod.AlarmzCL or {}
PCMod.AlarmzCL.Target = 0        -- camera entindex under the crosshair (0 = none)
PCMod.AlarmzCL.PickCam = 0       -- camera being connected (monitor-pick mode), 0 = idle
PCMod.AlarmzCL.States = {}       -- [camIdx] = { hasPass, isOwner, links = {} }
PCMod.AlarmzCL.PendingBegin = 0  -- camera we sent "begin" for and await state for
PCMod.AlarmzCL.LastAction = ""

local CAM_CLASS = "gmod_wire_rt_camera"

// Overlay/interaction range for the camera context overlay. Client-side only
// (the server keeps its own, larger CONNECT_RANGE check in sv_alarmz.lua).
// 200 units = ~5 meters (1 unit = 1 inch): the overlay is an interaction hint,
// so it shows only when close enough to act. ReachDistance is 256 (~6.5 m).
local DEFAULT_OVERLAY_RANGE = 200
function PCMod.AlarmzCL.OverlayRange()
	if (PCMod.Cfg && PCMod.Cfg.AlarmzOverlayRange && (PCMod.Cfg.AlarmzOverlayRange > 0)) then
		return PCMod.Cfg.AlarmzOverlayRange
	end
	return DEFAULT_OVERLAY_RANGE
end

// --- pure helpers (unit-tested) ------------------------------------------------------------------------

function PCMod.AlarmzCL.IsCam( ent )
	return (IsValid( ent ) && (ent:GetClass() == CAM_CLASS))
end

function PCMod.AlarmzCL.IsScreenEnt( ent )
	return (IsValid( ent ) && ent.IsPCMod && (ent.IsScreen == true))
end

// The overlay and its keys are active only while the camera link tool is held.
function PCMod.AlarmzCL.HoldingTool()
	local wep = LocalPlayer():GetActiveWeapon()
	return (IsValid( wep ) && (wep:GetClass() == "gmod_tool") && (wep.Mode == "pc_camlink"))
end

function PCMod.AlarmzCL.InRange( ent )
	if (!IsValid( ent )) then return false end
	local r = PCMod.AlarmzCL.OverlayRange()
	local d = LocalPlayer():GetShootPos():DistToSqr( ent:GetPos() )
	return (d <= (r * r))
end

// Overlay text for a camera. Pure function - easy to test.
function PCMod.AlarmzCL.OverlayLines( camIdx, camEnt, state )
	local lines = {}
	table.insert( lines, "RT Camera #" .. camIdx )
	local status = "OFFLINE"
	if (IsValid( camEnt ) && camEnt.GetActive && (camEnt:GetActive() == true)) then status = "ONLINE" end
	table.insert( lines, "Status: " .. status )
	if (state) then
		local n = 0
		for _ in pairs( state.links or {} ) do n = n + 1 end
		if (n > 0) then
			local first = nil
			for pcIdx in pairs( state.links ) do if ((first == nil) || (pcIdx < first)) then first = pcIdx end end
			table.insert( lines, "Linked to PC #" .. tostring( first ) .. ((n > 1) and (" (+" .. (n - 1) .. " more)") or "") )
			table.insert( lines, "[E] Connect another PC  [RMB] Disconnect" )
		elseif (state.hasPass) then
			table.insert( lines, "Locked (password)" )
			if (state.isOwner) then
				table.insert( lines, "[E] Connect (owner)" )
			else
				table.insert( lines, "[E] Enter password" )
			end
		else
			table.insert( lines, "[E] Connect" )
		end
	else
		table.insert( lines, "[E] Connect" )
	end
	return lines
end

// What the client should do after a fresh camera state arrives.
// Returns "pass" (open password input), "pick" (enter monitor-pick mode) or "none".
function PCMod.AlarmzCL.DecideFlow( state )
	if (state.hasPass && (!state.isOwner)) then return "pass" end
	return "pick"
end

// --- net -------------------------------------------------------------------------------------------------

function PCMod.AlarmzCL.Send( action, camIdx, monIdx, pass )
	net.Start( "pcmod_alarmz_req" )
		net.WriteString( action )
		net.WriteUInt( camIdx or 0, 32 )
		net.WriteUInt( monIdx or 0, 32 )
		net.WriteString( pass or "" )
	net.SendToServer()
	PCMod.AlarmzCL.LastAction = action
end

net.Receive( "pcmod_alarmz_state", function()
	local camIdx = net.ReadUInt( 32 )
	local hasPass = net.ReadBool()
	local isOwner = net.ReadBool()
	local n = net.ReadUInt( 16 ) -- must match the server's WriteUInt( #links, 16 )
	local links = {}
	for i = 1, n do links[ net.ReadUInt( 32 ) ] = true end
	PCMod.AlarmzCL.States[ camIdx ] = { hasPass = hasPass, isOwner = isOwner, links = links }
	if (PCMod.AlarmzCL.PendingBegin == camIdx) then
		PCMod.AlarmzCL.PendingBegin = 0
		local flow = PCMod.AlarmzCL.DecideFlow( PCMod.AlarmzCL.States[ camIdx ] )
		if (flow == "pass") then
			PCMod.AlarmzCL.OpenPassWindow( camIdx, "auth" )
		else
			PCMod.AlarmzCL.PickCam = camIdx
		end
	end
end )

net.Receive( "pcmod_alarmz_result", function()
	local ok = net.ReadBool()
	local msg = net.ReadString()
	local camIdx = net.ReadUInt( 32 )
	local canSetPass = net.ReadBool()
	if (PCMod.Gui && PCMod.Gui.Notify) then PCMod.Gui.Notify( msg, !ok ) end
	if (ok) then
		if (PCMod.AlarmzCL.LastAction == "connect") then PCMod.AlarmzCL.PickCam = 0 end
		if (PCMod.AlarmzCL.LastAction == "auth") then PCMod.AlarmzCL.PickCam = camIdx end
		if (canSetPass) then PCMod.AlarmzCL.OpenPassWindow( camIdx, "setpass" ) end
	else
		// wrong password: reopen the input with the error visible
		if (PCMod.AlarmzCL.LastAction == "auth") then
			PCMod.AlarmzCL.OpenPassWindow( camIdx, "auth" )
			if (PCMod.AlarmzCL.PassErr) then PCMod.AlarmzCL.PassErr:SetText( "Wrong password" ) end
		end
	end
end )

// --- input -----------------------------------------------------------------------------------------------

// Returns true when the key was consumed by the Alarmz flow (so the engine
// does not also fire the default bind / ENT:Use on the looked-at entity).
// [E] always starts/continues the connect flow (a camera can be linked to
// several PCs at once); [RMB] on a linked camera disconnects it.
function PCMod.AlarmzCL.OnUse( bnd )
	if (PCMod.Gui.CamLocked) then return false end
	if (!PCMod.AlarmzCL.HoldingTool()) then return false end
	if (bnd == "+attack2") then
		if (PCMod.AlarmzCL.Target != 0) then
			local state = PCMod.AlarmzCL.States[ PCMod.AlarmzCL.Target ]
			local links = (state && state.links) or {}
			local hasLinks = false
			for _ in pairs( links ) do hasLinks = true break end
			if (hasLinks) then
				PCMod.AlarmzCL.Send( "disconnect", PCMod.AlarmzCL.Target, 0, "" )
				return true
			end
		end
		return false
	end
	if (PCMod.AlarmzCL.PickCam != 0) then
		local tr = LocalPlayer():GetEyeTrace()
		local ent = tr.Entity
		if (PCMod.AlarmzCL.IsScreenEnt( ent ) && PCMod.AlarmzCL.InRange( ent )) then
			PCMod.AlarmzCL.Send( "connect", PCMod.AlarmzCL.PickCam, ent:EntIndex(), "" )
		else
			// pressed E not on a screen: cancel the monitor pick
			PCMod.AlarmzCL.PickCam = 0
		end
		return true
	end
	if (PCMod.AlarmzCL.Target != 0) then
		PCMod.AlarmzCL.PendingBegin = PCMod.AlarmzCL.Target
		PCMod.AlarmzCL.Send( "begin", PCMod.AlarmzCL.Target, 0, "" )
		return true
	end
	return false
end

hook.Add( "PlayerBindPress", "PCMod.AlarmzCL.Use", function( ply, bnd )
	if ((bnd != "+use") && (bnd != "+attack2")) then return end
	if (ply != LocalPlayer()) then return end
	if (PCMod.AlarmzCL.OnUse( bnd )) then return true end
end )

// --- target tracking + overlay ---------------------------------------------------------------------------

hook.Add( "Think", "PCMod.AlarmzCL.Track", function()
	if (!PCMod.AlarmzCL.HoldingTool()) then
		// tool not in hand: no overlay, cancel any pending pick
		PCMod.AlarmzCL.Target = 0
		PCMod.AlarmzCL.PickCam = 0
		return
	end
	local tr = LocalPlayer():GetEyeTrace()
	local t = 0
	if (PCMod.AlarmzCL.IsCam( tr.Entity ) && PCMod.AlarmzCL.InRange( tr.Entity )) then
		t = tr.Entity:EntIndex()
	end
	if (t != PCMod.AlarmzCL.Target) then
		PCMod.AlarmzCL.Target = t
		if (t != 0) then PCMod.AlarmzCL.Send( "state", t, 0, "" ) end
	end
end )

local function DrawOverlay()
	if (PCMod.Gui.CamLocked) then return end
	if (!PCMod.AlarmzCL.HoldingTool()) then return end
	local tr = LocalPlayer():GetEyeTrace()
	if (PCMod.AlarmzCL.PickCam != 0) then
		// monitor-pick mode: hint at the crosshair, plus the aimed screen's label
		local lines = { "Connect camera #" .. PCMod.AlarmzCL.PickCam, "Aim at a PCMod screen and press [E]", "[E] again (off screen) to cancel" }
		PCMod.Gui.DrawLabel( ScrW() * 0.5, ScrH() * 0.62, "ScoreboardText", lines, 10, Color( 50, 50, 50, 200 ), Color( 255, 255, 255, 255 ) )
		if (PCMod.AlarmzCL.IsScreenEnt( tr.Entity ) && PCMod.AlarmzCL.InRange( tr.Entity )) then
			local spos = tr.HitPos:ToScreen()
			PCMod.Gui.DrawLabel( spos.x, spos.y, "ScoreboardText", { "PCMod Screen #" .. tr.Entity:EntIndex(), "[E] Connect camera here" }, 10, Color( 50, 50, 50, 200 ), Color( 86, 214, 196, 255 ) )
		end
		return
	end
	if (PCMod.AlarmzCL.Target != 0) then
		local ent = ents.GetByIndex( PCMod.AlarmzCL.Target )
		// Range is enforced here too (every frame, at draw time): even if the
		// Think tracker is a frame behind, the overlay can never render beyond
		// cfg.AlarmzOverlayRange.
		if (PCMod.AlarmzCL.IsCam( ent ) && PCMod.AlarmzCL.InRange( ent )) then
			local spos = tr.HitPos:ToScreen()
			local lines = PCMod.AlarmzCL.OverlayLines( PCMod.AlarmzCL.Target, ent, PCMod.AlarmzCL.States[ PCMod.AlarmzCL.Target ] )
			PCMod.Gui.DrawLabel( spos.x, spos.y, "ScoreboardText", lines, 10, Color( 50, 50, 50, 200 ), Color( 255, 255, 255, 255 ) )
		else
			PCMod.AlarmzCL.Target = 0
		end
	end
end
hook.Add( "HUDPaint", "PCMod.AlarmzCL.Overlay", DrawOverlay )

// --- compact password window -------------------------------------------------------------------------------

// mode "auth"    -> submit sends "auth" (then monitor pick on success)
// mode "setpass" -> submit sends "setpass" (owner only; empty = leave open)
function PCMod.AlarmzCL.OpenPassWindow( camIdx, mode )
	if (PCMod.AlarmzCL.PassWin && PCMod.AlarmzCL.PassWin:IsValid()) then PCMod.AlarmzCL.PassWin:Remove() end
	local title = "Camera #" .. camIdx .. ((mode == "setpass") and " - set password (empty = open)" or " - password required")
	local win = vgui.CreateWindow( 0.22, 0.09, title )
	win:ShowCloseButton( true )
	local entry = vgui.Create( "DTextEntry" )
	entry:SetParent( win )
	entry:SetPos( 5, 35 )
	entry:SetSize( win:GetWide() - 10, 20 )
	local err = vgui.Create( "DLabel" )
	err:SetParent( win )
	err:SetPos( 5, 60 )
	err:SetSize( win:GetWide() - 10, 16 )
	err:SetText( "" )
	err:SetTextColor( Color( 220, 70, 60, 255 ) )
	local ok = vgui.Create( "DButton" )
	ok:SetParent( win )
	ok:SetPos( 5, win:GetTall() - 25 )
	ok:SetSize( win:GetWide() - 10, 20 )
	ok:SetText( "OK" )
	ok.DoClick = function()
		local pass = entry:GetValue() or ""
		PCMod.AlarmzCL.Send( mode, camIdx, 0, pass )
		if (win && win:IsValid()) then win:Remove() end
		PCMod.AlarmzCL.PassWin = nil
	end
	win:MakePopup()
	PCMod.AlarmzCL.PassWin = win
	PCMod.AlarmzCL.PassErr = err
end
