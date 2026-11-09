// ---------------------------------------------------------------------------------------------------------
// pcwire.lua - Wire-tool style wiring for PCMod entities.
// Connects two ports (network / vga / usb / etc) between two PCMod entities with
// a rendered cable. Ports are shown in an on-screen HUD list (mouse wheel to
// cycle, left-click to pick), instead of the old popup.
// ---------------------------------------------------------------------------------------------------------

TOOL.Category		= "PCMod - Wiring"
TOOL.Name			= "#Wire Tool"
TOOL.Tab			= "PCMod 13"
TOOL.Command		= nil
TOOL.ConfigName		= ""

if (!ToolOnly) then cleanup.Register( "computers" ) end

if (CLIENT) then
	language.Add( "tool.pcwire.name", "Wire Tool" )
	language.Add( "tool.pcwire.desc", "Connect two ports on PCMod devices with a cable" )
	language.Add( "tool.pcwire.0", "Left-Click: Pick a port. Mouse wheel: Cycle ports. Right-Click: Disconnect a connected port." )
	language.Add( "tool.pcwire.1", "Left-Click: Pick the port to connect to. Right-Click: Reset." )
end

TOOL.ClientConVar = {
	material	= "cable/rope",
	width		= "2",
	r			= "255",
	g			= "210",
	b			= "90",
}

// Marker so the mouse-wheel bind hook can tell this exact tool is active.
TOOL.ScrollablePCWire = true

// ---------------------------------------------------------------------------------------------------------
// Server: validate the wiring and create the rope + logical port link.
// ---------------------------------------------------------------------------------------------------------
if (SERVER) then

	// In single player the toolgun does not fire LeftClick/RightClick/Reload on
	// the client side (Wiremod's "wtfgarry" workaround); forward them so the
	// client-side HUD tool still reacts.
	if (game.SinglePlayer()) then
		util.AddNetworkString( "pcwire_sp_click" )
		local function PCWireSPForward( ply, funcname )
			if ((!ply) || (!ply:IsPlayer())) then return end
			net.Start( "pcwire_sp_click" )
				net.WriteString( funcname )
			net.Send( ply )
		end
		// Return false so the server-side toolgun does NOT play its default
		// "Toolgun.Single" click (DoShootEffect) on top of the client's own sound.
		function TOOL:LeftClick( trace )  PCWireSPForward( self:GetOwner(), "LeftClick" ) return false end
		function TOOL:RightClick( trace ) PCWireSPForward( self:GetOwner(), "RightClick" ) return false end
		function TOOL:Reload( trace )     PCWireSPForward( self:GetOwner(), "Reload" ) return false end
	end

	util.AddNetworkString( "pcmod_reqports" )
	net.Receive( "pcmod_reqports", function( len, ply )
		local ent = net.ReadEntity()
		if ((IsValid( ent )) && (ent.IsPCMod)) then
			PC_BeamPorts( ent, ply )
		end
	end )

	util.AddNetworkString( "pcwire_unlink" )
	net.Receive( "pcwire_unlink", function( len, ply )
		if ((!ply) || (!ply:IsPlayer())) then return end
		local ent = net.ReadEntity()
		local port = net.ReadUInt( 8 )
		if ((!IsValid( ent )) || (!ent.IsPCMod)) then return end
		local prt = ent:Ports()[ port ]
		if ((!prt) || (!prt.Connected)) then return end
		local other = prt.ConEnt
		if (PCMod.Wiring.UnlinkPort( ent, port )) then
			PCMod.Notice( "Port disconnected", ply )
			// Refresh both endpoints immediately so the tool's HUD drops the
			// stale "connected" flag on this very step.
			PC_BeamPorts( ent, ply )
			if ((other) && (IsValid( other ))) then PC_BeamPorts( other, ply ) end
		end
	end )

	util.AddNetworkString( "pcwire_upload" )
	net.Receive( "pcwire_upload", function( len, ply )
		if ((!ply) || (!ply:IsPlayer())) then return end
		local ent1 = net.ReadEntity()
		local port1 = net.ReadUInt( 8 )
		local ent2 = net.ReadEntity()
		local port2 = net.ReadUInt( 8 )
		local lpos1 = net.ReadVector()
		local lpos2 = net.ReadVector()
		local material = net.ReadString()
		local width = net.ReadFloat()
		local r = net.ReadUInt( 8 )
		local g = net.ReadUInt( 8 )
		local b = net.ReadUInt( 8 )

		// Validate everything server-side (never trust the client).
		if ((!IsValid( ent1 )) || (!IsValid( ent2 ))) then PCMod.Notice( "Cannot wire: invalid entity", ply ) return end
		if ((!ent1.IsPCMod) || (!ent2.IsPCMod)) then PCMod.Notice( "Cannot wire: not a PCMod entity", ply ) return end
		if (ent1 == ent2) then PCMod.Notice( "Cannot wire: same entity", ply ) return end
		local p1 = ent1:Ports()[ port1 ]
		local p2 = ent2:Ports()[ port2 ]
		if ((!p1) || (!p2)) then PCMod.Notice( "Cannot wire: bad port", ply ) return end
		if (p1.Connected || p2.Connected) then return end
		if (p1.Type != p2.Type) then PCMod.Notice( "Cannot wire: port types differ", ply ) return end
		local sameKind = (ent1:GetClass() == ent2:GetClass())
		// Network ports are pure L2: computers, switches and modems may all
		// link to their own kind (PC-to-PC, switch-to-switch, etc.).
		local netLink = (p1.Type == "network")
		if (sameKind && (!p1.CanWireSameType) && (!netLink)) then PCMod.Notice( "Cannot wire: same-class ports cannot connect", ply ) return end

		// Physical cable (constraint rope) between the two hit points.
		local addlength = 100
		local length = (ent1:GetPos() - ent2:GetPos()):Length() + addlength
		local const, rope = constraint.Rope( ent1, ent2, 0, 0, lpos1, lpos2, length, 0, 0, width, material, false )
		local rps = {}
		if (const || rope) then rps = { { const, rope } } end

		PCMod.Wiring.LinkPorts( ent1, port1, ent2, port2, rps, nil )
		// Both devices changed state; push the new link flags back to the
		// player so the HUD is correct on the next step without waiting for an
		// aim change.
		PC_BeamPorts( ent1, ply )
		PC_BeamPorts( ent2, ply )
		PCMod.Notice( "Wiring complete", ply )
	end )

end

// ---------------------------------------------------------------------------------------------------------
// Client: interactive HUD-driven wiring tool.
// ---------------------------------------------------------------------------------------------------------
if (CLIENT) then

	TOOL.Stage = 0          -- 0 = picking first port, 1 = picking second port
	TOOL.SelIndex = 1       -- which port is highlighted in the HUD
	TOOL.Ent1 = nil
	TOOL.Port1 = nil
	TOOL.LPos1 = nil
	TOOL.AimedEnt = nil
	TOOL.Previewing = false

	// Human-readable name for a port (or a raw type string). Custom port names
	// such as the backbone's "MGMNT" take precedence over the type label.
	local function PortName( port )
		if (!port) then return "?" end
		if (type( port ) == "table") then
			if (port.Name && (port.Name != "")) then return port.Name end
			return PortName( port.Type )
		end
		local typ = port
		for _, wt in ipairs( PCMod.Cfg.WireTypes or {} ) do
			if (wt.Name == typ) then return wt.ExtName or wt.Name end
		end
		return typ
	end

	local function CanSameType( typ )
		for _, wt in ipairs( PCMod.Cfg.WireTypes or {} ) do
			if (wt.Name == typ) then return (wt.SameType == true) end
		end
		return false
	end

	// The ports of an entity as beamed from the server: { [n] = { Type, Connected } }.
	function TOOL:GetPorts( ent )
		if (!IsValid( ent )) then return nil end
		return PCMod.PortData && PCMod.PortData[ ent:EntIndex() ]
	end

	// First unconnected port on `ent` whose type matches the first selection, or nil.
	function TOOL:FindMatchingPort( ent )
		local pts = self:GetPorts( ent )
		if ((!pts) || (#pts == 0)) then return nil end
		for i, p in ipairs( pts ) do
			if ((p.Type == self.Port1Type) && (!p.Connected)) then return i end
		end
		return nil
	end

	function TOOL:RequestPorts( ent )
		if (!IsValid( ent )) then return end
		net.Start( "pcmod_reqports" )
			net.WriteEntity( ent )
		net.SendToServer()
	end

	function TOOL:Reset()
		self.Stage = 0
		self.SelIndex = 1
		self.Ent1 = nil
		self.Port1 = nil
		self.Port1Type = nil
		self.LPos1 = nil
		self.AutoSelectDone = false
		self:StopPreview()
	end

	function TOOL:Deploy() self:Reset() end
	function TOOL:Holster() self:Reset() end

	function TOOL:RightClick( trace )
		// Right-click a connected port to unwire it; otherwise reset the tool.
		if (self.Stage == 0) then
			local ent = trace.Entity
			local ports = (IsValid( ent )) && ent.IsPCMod && self:GetPorts( ent )
			local prt = ports && ports[ self.SelIndex ]
			if ((prt) && (prt.Connected)) then
				net.Start( "pcwire_unlink" )
					net.WriteEntity( ent )
					net.WriteUInt( self.SelIndex, 8 )
				net.SendToServer()
				self:RequestPorts( ent )
				self:Reset()
				return true
			end
		end
		self:Reset()
		return true
	end

	function TOOL:LeftClick( trace )
		if ((!game.SinglePlayer()) && (!IsFirstTimePredicted())) then return end
		local ent = trace.Entity
		if ((!IsValid( ent )) || (!ent.IsPCMod)) then self:Reset() return false end
		local ports = self:GetPorts( ent )
		if ((!ports) || (#ports == 0)) then return false end
		local prt = ports[ self.SelIndex ]
		if ((!prt) || (prt.Connected)) then
			if (prt && prt.Connected) then PCMod.Notice( "That port is already connected" ) end
			return false
		end

		if (self.Stage == 0) then
			self.Ent1 = ent
			self.Port1 = self.SelIndex
			self.Port1Type = ports[ self.Port1 ].Type
			self.LPos1 = ent:WorldToLocal( trace.HitPos )
			self.Stage = 1
			self.SelIndex = 1
			self.AutoSelectDone = false
			PCMod.Notice( "Port selected - aim at the second device and left-click" )
			self:BeginPreview()
			// Refresh the first device's link flags as the first wiring step.
			self:RequestPorts( ent )
			return true
		end

		// Stage 1: connect to the second entity.
		if (ent == self.Ent1) then
			PCMod.Notice( "Cannot wire: that's the same device" )
			self:Reset()
			return true
		end
		local p1 = (self.Ent1 && self:GetPorts( self.Ent1 )) and self:GetPorts( self.Ent1 )[ self.Port1 ]
		if (!p1) then self:Reset() return false end
		if (p1.Type != prt.Type) then
			PCMod.Notice( "Cannot wire: " .. tostring( PortName( p1 ) ) .. " and " .. tostring( PortName( prt ) ) .. " don't match" )
			return true
		end
		// Network ports are pure L2 and may link to their own kind: a direct
		// PC-to-PC cable, switch-to-switch cascade, etc.
		local sameKind = (ent:GetClass() == self.Ent1:GetClass())
		local netLink = (p1.Type == "network")
		if (sameKind && (!CanSameType( p1.Type )) && (!netLink)) then
			PCMod.Notice( "Cannot wire: " .. tostring( PortName( p1 ) ) .. " ports can't link to their own kind" )
			return true
		end

		net.Start( "pcwire_upload" )
			net.WriteEntity( self.Ent1 )
			net.WriteUInt( self.Port1, 8 )
			net.WriteEntity( ent )
			net.WriteUInt( self.SelIndex, 8 )
			net.WriteVector( self.LPos1 )
			net.WriteVector( ent:WorldToLocal( trace.HitPos ) )
			net.WriteString( self:GetClientInfo( "material" ) )
			net.WriteFloat( self:GetClientNumber( "width" ) )
			net.WriteUInt( self:GetClientNumber( "r" ), 8 )
			net.WriteUInt( self:GetClientNumber( "g" ), 8 )
			net.WriteUInt( self:GetClientNumber( "b" ), 8 )
		net.SendToServer()

		// Finish this wiring step with fresh state for both devices. The server
		// also re-beams them, but asking here keeps the HUD correct even if the
		// player keeps aiming at the same entity.
		local firstEnt = self.Ent1
		self:Reset()
		self:RequestPorts( firstEnt )
		self:RequestPorts( ent )
		return true
	end

	function TOOL:Scroll( trace, dir )
		local ent = trace.Entity
		if ((!IsValid( ent )) || (!ent.IsPCMod)) then return end
		local ports = self:GetPorts( ent )
		if ((!ports) || (#ports == 0)) then return end
		self.SelIndex = self.SelIndex + dir
		if (self.SelIndex > #ports) then self.SelIndex = 1 end
		if (self.SelIndex < 1) then self.SelIndex = #ports end
		self.AutoSelectDone = true -- the player chose manually; don't override
		self:GetOwner():EmitSound( "weapons/pistol/pistol_empty.wav" )
		return true
	end
	function TOOL:ScrollUp( trace ) return self:Scroll( trace, -1 ) end
	function TOOL:ScrollDown( trace ) return self:Scroll( trace, 1 ) end

	function TOOL:Think()
		local ent = self:GetOwner():GetEyeTrace().Entity
		if (ent != self.AimedEnt) then
			self.AimedEnt = ent
			self.SelIndex = 1
			self.AutoSelectDone = false
			self:RequestPorts( ent )
		end
		// Keep the HUD's link state fresh while aiming at the same device.
		// Links can change from the previous wiring step, another player, or
		// the server, and the cached port data would otherwise stay stale.
		local now = CurTime()
		if ((IsValid( ent )) && (ent.IsPCMod) && (now >= (self.NextPortRefresh or 0))) then
			self:RequestPorts( ent )
			self.NextPortRefresh = now + 0.5
		end
		// Once the second device's ports arrive, auto-select the port whose type
		// matches the first selection (so you don't have to scroll to find it).
		if ((self.Stage == 1) && (self.AutoSelectDone != true) && (IsValid( ent )) && (ent.IsPCMod) && (ent != self.Ent1)) then
			local idx = self:FindMatchingPort( ent )
			if (idx) then
				self.SelIndex = idx
				self.AutoSelectDone = true
			end
		end
	end

	// -------------------------------------------------------------------------
	// Beam preview of the cable being drawn.
	// -------------------------------------------------------------------------
	function TOOL:BeginPreview()
		if (self.Previewing) then return end
		self.Previewing = true
		hook.Add( "PostDrawOpaqueRenderables", "PCMod.WirePreview", function()
			if (!IsValid( self.Ent1 )) then self:StopPreview() return end
			local col = Color( self:GetClientNumber( "r" ), self:GetClientNumber( "g" ), self:GetClientNumber( "b" ) )
			local width = self:GetClientNumber( "width" )
			local start = self.Ent1:LocalToWorld( self.LPos1 )
			local tr = util.GetPlayerTrace( self:GetOwner() )
			tr.filter = { self:GetOwner() }
			local aim = util.TraceLine( tr ).HitPos
			render.SetMaterial( Material( self:GetClientInfo( "material" ) ) )
			render.StartBeam( 2 )
				render.AddBeam( start, width, 0, col )
				render.AddBeam( aim, width, 1, Color( 255, 255, 255 ) )
			render.EndBeam()
		end )
	end

	function TOOL:StopPreview()
		if (!self.Previewing) then return end
		self.Previewing = false
		hook.Remove( "PostDrawOpaqueRenderables", "PCMod.WirePreview" )
	end

	// -------------------------------------------------------------------------
	// HUD port list
	// -------------------------------------------------------------------------
	function TOOL:DrawHUD()
		local ent = self:AimedTarget()
		local ports = self:GetPorts( ent )
		if ((!ent) || (!IsValid( ent )) || (!ports) || (#ports == 0)) then return end

		surface.SetFont( "Trebuchet18" )
		local _, th = surface.GetTextSize( "X" )
		local w = 220
		local h = (#ports * th) + 34
		local x = (ScrW() / 2) + 24
		local y = (ScrH() / 2) - (h / 2)

		draw.RoundedBox( 6, x, y, w, h, Color( 40, 40, 60, 220 ) )

		local title = (self.Stage == 0) and "Ports:" or "Connect to (ports):"
		surface.SetTextColor( 255, 255, 255 )
		surface.SetTextPos( x + 8, y + 4 )
		surface.DrawText( title )

		for i, p in ipairs( ports ) do
			local yy = y + 24 + ((i - 1) * th)
			local typeName = PortName( p )
			local txt = tostring( i ) .. ": " .. typeName
			local col = Color( 255, 255, 255 )
			if (p.Connected) then
				col = Color( 255, 120, 120 )
				txt = txt .. "  (connected)"
			end
			if (i == self.SelIndex) then
				draw.RoundedBox( 4, x + 4, yy, w - 8, th + 2, Color( 0, 150, 0, 180 ) )
				col = Color( 255, 255, 255 )
			end
			surface.SetTextColor( col.r, col.g, col.b )
			surface.SetTextPos( x + 10, yy )
			surface.DrawText( txt )
		end
	end

	// The entity we're currently selecting ports on: in stage 1 we still aim at
	// the second entity, but stay showing the first entity in case aim is empty.
	function TOOL:AimedTarget()
		local tr = self:GetOwner():GetEyeTrace()
		if ((IsValid( tr.Entity )) && (tr.Entity.IsPCMod)) then return tr.Entity end
		return (self.Stage == 1) and self.Ent1 or nil
	end

	function TOOL.BuildCPanel( CPanel )
		CPanel:AddControl( "Header", { Text = "#Tool_pcwire_name", Description = "#Tool_pcwire_desc" } )
		CPanel:AddControl( "Slider", {
			Label = "Width:",
			Type = "Float",
			Min = "0",
			Max = "5",
			Command = "pcwire_width"
		} )
		CPanel:AddControl( "MatSelect", {
			Height = "1",
			Label = "Material:",
			ItemWidth = 24,
			ItemHeight = 64,
			ConVar = "pcwire_material",
			Options = list.Get( "WireMaterials" )
		} )
		CPanel:AddControl( "Color", {
			Label = "Colour:",
			Red = "pcwire_r",
			Green = "pcwire_g",
			Blue = "pcwire_b"
		} )
	end

	// Mouse-wheel cycles the highlighted port while this tool is active.
	local function GetPCWireTool( ply )
		local wep = ply:GetActiveWeapon()
		if ((!IsValid( wep )) || (wep:GetClass() != "gmod_tool")) then return nil end
		local obj = wep.GetToolObject && wep:GetToolObject()
		if ((obj) && (obj.ScrollablePCWire)) then return obj end
		return nil
	end

	local function ScrollBind( ply, bind, pressed )
		if (!pressed) then return end
		local self = GetPCWireTool( ply )
		if (!self) then return end
		if (bind == "invnext") then return self:ScrollDown( ply:GetEyeTraceNoCursor() ) end
		if (bind == "invprev") then return self:ScrollUp( ply:GetEyeTraceNoCursor() ) end
	end

	if (game.SinglePlayer()) then
		timer.Simple( 5, function()
			hook.Add( "PlayerBindPress", "pcwire_scroll", ScrollBind )
		end )
	else
		hook.Add( "PlayerBindPress", "pcwire_scroll", ScrollBind )
	end

	// Single-player click forward: the server relays LeftClick/RightClick/Reload
	// to us, since the toolgun does not run them client-side in single player.
	if (game.SinglePlayer()) then
		net.Receive( "pcwire_sp_click", function( len )
			local funcname = net.ReadString()
			// Use the activated tool object (toolgun injects GetOwner/SWEP/etc),
			// not the raw TOOL table - the latter has no GetOwner and errors.
			local ply = LocalPlayer()
			local tool = GetPCWireTool( ply )
			if (!tool) then return end
			local fn = tool[ funcname ]
			if (!fn) then return end
			local tr = ply:GetEyeTrace()
			// The toolgun skips its normal client callback in singleplayer, so
			// replicate DoShootEffect here when the tool reports success.
			if (!fn( tool, tr )) then return end
			local wep = ply:GetActiveWeapon()
			if (IsValid( wep )) then
				wep:SendWeaponAnim( ACT_VM_PRIMARYATTACK )
				wep:EmitSound( "Toolgun.Single" )
			end
			if (GetConVarNumber( "gmod_drawtooleffects" ) == 0) then return end
			local effectdata = EffectData()
			effectdata:SetOrigin( tr.HitPos )
			effectdata:SetNormal( tr.HitNormal )
			effectdata:SetEntity( tr.Entity )
			effectdata:SetAttachment( tr.PhysicsBone )
			util.Effect( "selection_indicator", effectdata )
			// Use an eye-relative muzzle position. The viewmodel's attachment is
			// not reliable inside a net callback and can resolve behind the view,
			// so approximate the toolgun muzzle in front/lower-right of the eye.
			local startPos = ply:GetShootPos() + ply:GetForward() * 14 + ply:GetRight() * 5 - ply:GetUp() * 3
			local effect_tr = EffectData()
			effect_tr:SetOrigin( tr.HitPos )
			effect_tr:SetStart( startPos )
			util.Effect( "ToolTracer", effect_tr )
		end )
	end

end