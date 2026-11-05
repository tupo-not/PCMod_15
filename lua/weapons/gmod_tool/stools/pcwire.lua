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
	language.Add( "tool.pcwire.0", "Left-Click: Pick a port. Mouse wheel: Cycle ports. Right-Click: Reset." )
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
		function TOOL:LeftClick( trace )  PCWireSPForward( self:GetOwner(), "LeftClick" ) return true end
		function TOOL:RightClick( trace ) PCWireSPForward( self:GetOwner(), "RightClick" ) return true end
		function TOOL:Reload( trace )     PCWireSPForward( self:GetOwner(), "Reload" ) return true end
	end

	util.AddNetworkString( "pcmod_reqports" )
	net.Receive( "pcmod_reqports", function( len, ply )
		local ent = net.ReadEntity()
		if ((IsValid( ent )) && (ent.IsPCMod)) then
			PC_BeamPorts( ent, ply )
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
		if ((ent1:GetClass() == ent2:GetClass()) && (!p1.CanWireSameType)) then PCMod.Notice( "Cannot wire: same-class ports cannot connect", ply ) return end

		// Physical cable (constraint rope) between the two hit points.
		local addlength = 100
		local length = (ent1:GetPos() - ent2:GetPos()):Length() + addlength
		local const, rope = constraint.Rope( ent1, ent2, 0, 0, lpos1, lpos2, length, 0, 0, width, material, false )
		local rps = {}
		if (const || rope) then rps = { { const, rope } } end

		PCMod.Wiring.LinkPorts( ent1, port1, ent2, port2, rps, nil )
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

	// Human-readable name for a port type.
	local function PortName( typ )
		if (!typ) then return "?" end
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
		self.LPos1 = nil
		self:StopPreview()
	end

	function TOOL:Deploy() self:Reset() end
	function TOOL:Holster() self:Reset() end

	function TOOL:RightClick( trace )
		self:Reset()
		return false
	end

	function TOOL:LeftClick( trace )
		if ((!game.SinglePlayer()) && (!IsFirstTimePredicted())) then return end
		local ent = trace.Entity
		if ((!IsValid( ent )) || (!ent.IsPCMod)) then self:Reset() return false end
		local ports = self:GetPorts( ent )
		if ((!ports) || (#ports == 0)) then return false end
		local prt = ports[ self.SelIndex ]
		if ((!prt) || (prt.Connected)) then return false end

		if (self.Stage == 0) then
			self.Ent1 = ent
			self.Port1 = self.SelIndex
			self.LPos1 = ent:WorldToLocal( trace.HitPos )
			self.Stage = 1
			self.SelIndex = 1
			self:GetOwner():EmitSound( "weapons/airboat/airboat_gun_lastshot1.wav" )
			PCMod.Notice( "Port selected - aim at the second device and left-click" )
			self:BeginPreview()
			return
		end

		// Stage 1: connect to the second entity.
		if (ent == self.Ent1) then return false end
		local p1 = (self.Ent1 && self:GetPorts( self.Ent1 )) and self:GetPorts( self.Ent1 )[ self.Port1 ]
		if (!p1) then self:Reset() return false end
		if (p1.Type != prt.Type) then return false end
		if ((ent:GetClass() == self.Ent1:GetClass()) && (!CanSameType( p1.Type ))) then return false end

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

		self:Reset()
	end

	function TOOL:Scroll( trace, dir )
		local ent = trace.Entity
		if ((!IsValid( ent )) || (!ent.IsPCMod)) then return end
		local ports = self:GetPorts( ent )
		if ((!ports) || (#ports == 0)) then return end
		self.SelIndex = self.SelIndex + dir
		if (self.SelIndex > #ports) then self.SelIndex = 1 end
		if (self.SelIndex < 1) then self.SelIndex = #ports end
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
			self:RequestPorts( ent )
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
			local typeName = PortName( p.Type )
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
			local tool = GetPCWireTool( LocalPlayer() )
			if (!tool) then return end
			local fn = tool[ funcname ]
			if (fn) then fn( tool, LocalPlayer():GetEyeTrace() ) end
		end )
	end

end