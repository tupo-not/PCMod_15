
// ---------------------------------------------------------------------------------------------------------
// cl_vgui.lua - Revision 1
// Client-Side
// Controls drawing operations on the client (specifically derma and the vgui library)
// ---------------------------------------------------------------------------------------------------------


// ---------------------------------------------------------------------------------------------------------
// ShowLockFrame - Shows / Hides the lock frame
// ---------------------------------------------------------------------------------------------------------



function PCMod.Gui.ShowLockFrame( show )
	if (!show) then
		if (PCMod.Gui.LFrame) then
			PCMod.Gui.LFrame:Remove()
			PCMod.Gui.LFrame = nil
		end
		return
	end
	local pn = vgui.Create( "DFrame" )
	pn:SetPos( ScrW()*0.86, ScrH()*0.1 )
	pn:SetSize( ScrW()*0.12, ScrH()*0.2 )
	pn:SetTitle( "PCMod 15" )
	pn:SetDraggable( false )
	pn:ShowCloseButton( false )
	PCMod.Gui.LFrame = pn
	
	local btn = vgui.Create( "DButton" )
	btn:SetParent( pn )
	btn:SetSize( pn:GetWide()-10, 20 )
	btn:SetPos( 5, 30 )
	btn:SetText( "Close" )
	btn.DoClick = function( self )
		PCMod.Beam.UnlockCam( LocalPlayer() )
	end

	local btn = vgui.Create( "DButton" )
	btn:SetParent( pn )
	btn:SetSize( pn:GetWide()-10, 20 )
	btn:SetPos( 5, 55 )
	btn:SetText( "Quick Type" )
	btn.DoClick = function( self )
	/*
	net.Start("ekrantazele")
	net.WriteEntity(LocalPlayer():GetEyeTrace().Entity)
	net.SendToServer()
	*/
	RunConsoleCommand( "pc_quicktype", PCMod.SDraw.KeyboardEntID )
	end
	
	local ent = ents.GetByIndex( PCMod.Gui.CamLockID )
	
	if ((ent) && (ent:IsValid()) && (ent:GetClass() == "pcmod_laptop")) then
		local btn = vgui.Create( "DButton" )
		btn:SetParent( pn )
		btn:SetSize( pn:GetWide()-10, 20 )
		btn:SetPos( 5, 80 )
		btn:SetText( "Toggle Power" )
		btn.DoClick = function( self )
			RunConsoleCommand( "pc_command", PCMod.Gui.CamLockID, "power" )
		end
	end
end

// ---------------------------------------------------------------------------------------------------------
// EnableHackyClicky - Toggles the HackyClicky control (lol)
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.EnableHackyClicky( on )
	if (on == false) then
		if (PCMod.Gui.HackyClicky) then
			PCMod.Gui.HackyClicky:Remove()
			PCMod.Gui.HackyClicky = nil
		end
		return
	end
	if (on == true) then
		// A partial reload may have left the keyboard hook unrun. Re-create
		// the panel if the keyboard code is loaded, so HackyClicky still sizes
		// itself correctly instead of erroring on a nil KeyBoard.
		if ((!PCMod.Gui.KeyBoard) && PCMod.Gui.InitKeyboard) then
			PCMod.Gui.InitKeyboard()
		end
		if (!PCMod.Gui.HackyClicky) then
			PCMod.Gui.HackyClicky = vgui.Create( "HackyClicky" )
			PCMod.Gui.HackyClicky:PerformLayout()
		end
	end
end

// ---------------------------------------------------------------------------------------------------------
// TestIcon - Tests the flashy icon
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.TestIcon( pl, com, args )
	local ico = "gui/silkicons/wrench"
	if (args[1]) then ico = args[1] end
	PCMod.Gui.FlashIcon( ico )
end
concommand.Add( "pc_testicon", PCMod.Gui.TestIcon )

// ---------------------------------------------------------------------------------------------------------
// NOTIFY - shared constants for the Dynamic Island notification
// ---------------------------------------------------------------------------------------------------------
local NOTIFY = {
	Duration = 1.85, -- expand 0.15 s -> hold 1.5 s -> collapse 0.2 s
	ExpandTime = 0.15,
	HoldTime = 1.5,
	OffsetY = 48, -- below the crosshair
	Margin = 10, -- left/right padding inside the capsule
	DotD = 7, -- status indicator diameter
	Gap = 8, -- space between indicator and text
	Font = "ScoreboardText",
	Sound = "pcmod/install_ping.wav", -- original soft electronic ping, 0.42 s (addon's own sound/)
	AccentOK = Color( 102, 216, 207 ), -- teal #66D8CF for success
	AccentErr = Color( 255, 176, 80 ), -- muted amber for errors
}

// ---------------------------------------------------------------------------------------------------------
// CalcNotifyLayout - computes the FINAL (unscaled) capsule layout for a
// message: capsule width/height and text size.
// Layout: [margin][indicator dot][gap][text][margin], all left-to-right.
// Pure function (unit-tested by mock_notify).
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.CalcNotifyLayout( msg, scrW )
	surface.SetFont( NOTIFY.Font )
	local tw, th = surface.GetTextSize( tostring( msg ) )
	local w = NOTIFY.Margin + NOTIFY.DotD + NOTIFY.Gap + tw + NOTIFY.Margin // capsule width fits the text
	w = math.max( w, 90 ) // minimum width for short messages
	w = math.min( w, scrW * 0.6 ) // never wider than 60% of the screen
	local h = math.max( 30, th + 12 ) // capsule height follows the font
	return w, h, tw, th
end

// ---------------------------------------------------------------------------------------------------------
// Notify - Shows a compact "Dynamic Island"-style notification capsule under
// the crosshair. msg = text, isError = amber accent + no success sound.
//
// Rendered by a single HUDPaint hook (absolute screen coordinates, a proper 2D
// rendering context per the wiki) - NOT by a Derma panel: inside PANEL:Paint
// the surface/draw coordinates are already offset by the panel position, and
// combining that with cam.PushModelMatrix made the text placement
// context-dependent (that was the clipping bug). No panel means no panel
// lifecycle/leaks, and repeated notifications just overwrite the state.
// ---------------------------------------------------------------------------------------------------------
PCMod.Gui.NotifyState = nil

local function notifySmooth( t )
	t = math.Clamp( t, 0, 1 )
	return t * t * (3 - 2 * t)
end

function PCMod.Gui.Notify( msg, isError )
	// Final layout is computed once per message; a repeated notification just
	// overwrites the state (no stacking, no leftovers from the previous one).
	local w, h, tw, th = PCMod.Gui.CalcNotifyLayout( msg, ScrW() )
	PCMod.Gui.NotifyState = {
		Active = true,
		Message = tostring( msg ),
		IsError = (isError == true),
		StartTime = CurTime(),
		Duration = NOTIFY.Duration,
		W = w, H = h, TextW = tw, TextH = th,
	}
	// Success sound only on confirmed success, once per notification, client-side
	// (no multiplayer duplicates). See https://wiki.facepunch.com/gmod/surface.PlaySound
	if (!PCMod.Gui.NotifyState.IsError) then surface.PlaySound( NOTIFY.Sound ) end
end

// Kept for compatibility with older callers (pc_testicon, pcmod_hdcopier).
function PCMod.Gui.FlashIcon( ico, dir )
	PCMod.Gui.Notify( "Installed", false )
end

// ---------------------------------------------------------------------------------------------------------
// NotifyGeometry - final (world/screen) edges of every element after the shared
// scale p is applied around the capsule center. Pure function (mock-tested).
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.NotifyGeometry( st, scrW, scrH, p )
	local cx = scrW / 2
	local cy = scrH / 2 + NOTIFY.OffsetY
	local w = st.W * p
	local h = st.H * p
	local capL = cx - w / 2
	local capR = cx + w / 2
	local capT = cy - h / 2
	local capB = cy + h / 2
	local dotL = capL + NOTIFY.Margin * p
	local dotR = dotL + NOTIFY.DotD * p
	local textL = capL + (NOTIFY.Margin + NOTIFY.DotD + NOTIFY.Gap) * p
	local textR = textL + st.TextW * p
	local textT = cy - st.TextH * p / 2
	local textB = textT + st.TextH * p
	return capL, capR, capT, capB, dotL, dotR, textL, textR, textT, textB
end

local function DrawNotify()
	local st = PCMod.Gui.NotifyState
	if ((!st) || (!st.Active)) then return end
	local t = math.Clamp( CurTime() - st.StartTime, 0, st.Duration )
	if (t >= st.Duration) then
		st.Active = false
		return
	end
	// one shared time-based progress p (single smoothstep) drives everything
	local p, al
	if (t < NOTIFY.ExpandTime) then
		p = notifySmooth( t / NOTIFY.ExpandTime )
		al = p
	elseif (t < NOTIFY.ExpandTime + NOTIFY.HoldTime) then
		p = 1
		al = 1
	else
		p = 1 - notifySmooth( (t - NOTIFY.ExpandTime - NOTIFY.HoldTime) / (st.Duration - NOTIFY.ExpandTime - NOTIFY.HoldTime) )
		al = p
	end
	if (p <= 0.01) then return end
	// absolute screen coordinates (HUDPaint is a plain 2D rendering context)
	local capL, capR, capT, capB, dotL, dotR, textL, textR, textT, textB =
		PCMod.Gui.NotifyGeometry( st, ScrW(), ScrH(), p )
	// capsule
	draw.RoundedBox( (capB - capT) / 2, capL, capT, capR - capL, capB - capT, Color( 18, 22, 26, 220 * al ) )
	// status indicator (teal = success, amber = error)
	local acc = st.IsError && NOTIFY.AccentErr || NOTIFY.AccentOK
	draw.RoundedBox( (dotR - dotL) / 2, dotL, (capT + capB) / 2 - (dotR - dotL) / 2, dotR - dotL, dotR - dotL, Color( acc.r, acc.g, acc.b, 255 * al ) )
	// text: ONE matrix (translate to the text top-left, scale by the same p),
	// explicit LEFT/TOP alignment - no center-align inside a transform
	local m = Matrix()
	m:Translate( Vector( textL, textT, 0 ) )
	m:Scale( Vector( p, p, 1 ) )
	render.PushFilterMag( TEXFILTER.ANISOTROPIC )
	render.PushFilterMin( TEXFILTER.ANISOTROPIC )
	cam.PushModelMatrix( m, true )
	draw.SimpleText( st.Message, NOTIFY.Font, 0, 0, Color( 240, 255, 255, 255 * al ), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
	cam.PopModelMatrix()
	render.PopFilterMin()
	render.PopFilterMag()
end
hook.Add( "HUDPaint", "PCMod.Gui.Notify", DrawNotify )

// ---------------------------------------------------------------------------------------------------------
// VGUI: CreateWindow - Creates a DFrame and sets it all up
// ---------------------------------------------------------------------------------------------------------
function vgui.CreateWindow( w, h, title, draggable )
	local pn = vgui.Create( "DFrame" )
	local sw = ScrW()
	local sh = ScrH()
	pn:SetSize( w*sw, h*sh )
	pn:SetPos( (sw/2)-((w/2)*sw), (sh/2)-((h/2)*sh) )
	pn:SetTitle( title )
	pn:SetDraggable( false )
	if (draggable) then pn:SetDraggable( true ) end
	pn:ShowCloseButton( true )
	pn:SetScreenLock( true )
	return pn
end

// ---------------------------------------------------------------------------------------------------------
// VGUI: CreateSheet - Creates a DPropertySheet and sets it all up
// ---------------------------------------------------------------------------------------------------------
function vgui.CreateSheet( pframe )
	local pn = vgui.Create( "DPropertySheet" )
	local sw = pframe:GetWide()
	local sh = pframe:GetTall()
	pn:SetParent( pframe )
	pn:SetSize( sw-10, sh-35 )
	pn:SetPos( 5, 30 )
	return pn
end

// ---------------------------------------------------------------------------------------------------------
// VGUI: AddTab - Adds a tab to a property sheet, and returns the panel
// ---------------------------------------------------------------------------------------------------------
function vgui.AddTab( psheet, bgcol, title, icon, text )
	local pn = vgui.Create( "DPanelList" )
	pn:SetPos( 5, 30 )
	local w, h = psheet:GetSize()
	pn:SetSize( w-10, h-35 )
	pn:SetSpacing( 5 )
	pn:SetPadding( 5 )
	pn:EnableHorizontal( false )
	pn:EnableVerticalScrollbar( true )
	pn.Col = bgcol
	function pn:Paint()
		draw.RoundedBox( 6, 0, 0, self:GetWide(), self:GetTall(), self.Col )
	end
	if (!icon) then icon = "user" end
	if (!text) then text = title end
	psheet:AddSheet( title, pn, "icon16/" .. icon..".png", false, false, text )
	return pn
end

// ---------------------------------------------------------------------------------------------------------
// VGUI: AddText - Adds a text label to a panel list and sets it up
// ---------------------------------------------------------------------------------------------------------
function vgui.AddText( plist, text )
	local pn = vgui.Create( "DLabel" )
	pn:SetText( text )
	pn:SizeToContents()
	plist:AddItem( pn )
	return pn
end

// ---------------------------------------------------------------------------------------------------------
// VGUI: AddCheckbox - Adds a checkbox to a panel list and sets it up
// ---------------------------------------------------------------------------------------------------------
function vgui.AddCheckbox( plist, text, checked, oncheck )
	local pn = vgui.Create( "DCheckBoxLabel" )
	pn:SetText( text )
	if (checked) then pn:SetChecked( 1 ) end
	pn.OnChange = oncheck
	pn:SizeToContents()
	plist:AddItem( pn )
	return pn
end

// ---------------------------------------------------------------------------------------------------------
// VGUI: AddCombobox - Adds a combobox to a panel list and sets it up
// ---------------------------------------------------------------------------------------------------------
function vgui.AddCombobox( plist, options )
	local pn = vgui.Create( "DComboBox" )
	pn:SetMultiple( false )
	for _, v in pairs( options ) do
		pn:AddItem( v )
	end
	plist:AddItem( pn )
	return pn
end

// ---------------------------------------------------------------------------------------------------------
// VGUI: AddButton - Adds a button to a panel list and sets it up
// ---------------------------------------------------------------------------------------------------------
function vgui.AddButton( plist, text, onclick )
	local pn = vgui.Create( "DButton" )
	pn:SetText( text )
	pn.DoClick = onclick
	plist:AddItem( pn )
	return pn
end

// ---------------------------------------------------------------------------------------------------------
// VGUI: AddSI - Adds a spawnicon to a panel list and sets it up
// ---------------------------------------------------------------------------------------------------------
function vgui.AddSI( plist, mdl, onclick )
	local pn = vgui.Create( "SpawnIcon" )
	pn:SetModel( mdl )
	if (onclick) then pn.DoClick = onclick end
	plist:AddItem( pn )
	return pn
end

// ---------------------------------------------------------------------------------------------------------
// VGUI: AddSlider - Adds a slider to a panel list and sets it up
// ---------------------------------------------------------------------------------------------------------
function vgui.AddSlider( plist, txt, min, max, convar, changefunc, id )
	local pn = vgui.Create( "DNumSlider" )
	pn:SetText( txt )
	pn:SetMin( min )
	pn:SetMax( max )
	pn:SetDecimals( 0 )
	pn:SetConVar( convar )
	/*if (changefunc) then
		pn.ChangeID = id
		pn.ChangeFunc = changefunc
		function pn:OnValueChanged( val )
			self.ChangeFunc( self.ChangeID, val )
		end
	end*/
	plist:AddItem( pn )
	return pn
end


// ---------------------------------------------------------------------------------------------------------
// DERMA: UnlockButton - Unlocks the player cam
// ---------------------------------------------------------------------------------------------------------
local PANEL = {}
function PANEL:PerformLayout()
	self:SetText( "X" )
end
function PANEL:Paint()
	local w, h = self:GetSize()
	local col = Color( 50, 50, 50, 200 )
	if (self.Hovered) then col = Color( 100, 100, 100, 200 ) end
	draw.RoundedBox( 6, 0, 0, w, h, col )
	//draw.SimpleText( "X", "ScoreboardText", w/2, h/2, Color( 255, 255, 255, 255 ), 1, 1 )
end
function PANEL:DoClick()
	PCMod.Beam.UnlockCam( LocalPlayer() )
end
vgui.Register( "UnlockButton", PANEL, "DButton" )

// ---------------------------------------------------------------------------------------------------------
// DERMA: HackyClicky - A hacky way to sense mouse clicks
// ---------------------------------------------------------------------------------------------------------
local PANEL = {}
function PANEL:Initialize()
	self:SetText( "" )
end
function PANEL:Paint() end
function PANEL:DoClick()
	PCMod.Gui.RegisterClick( gui.MouseX(), gui.MouseY(), nil, false )
end
function PANEL:DoRightClick()
	PCMod.Gui.RegisterClick( gui.MouseX(), gui.MouseY(), nil, true )
end
function PANEL:PerformLayout()
	// The keyboard panel may not exist yet during a partial Lua reload (or if
	// InitKeyboard failed), so never index it directly.
	//
	// Only reserve space while the keyboard is actually visible. Hiding it used
	// to still subtract its height, which made the bottom of the screen (the
	// taskbar / Start button) unclickable - players had to pixel-hunt for a
	// spot that still hit this panel.
	local kh = 0
	if (PCMod.Gui.KeyBoard && PCMod.Gui.KeyBoard:IsVisible()) then
		kh = PCMod.Gui.KeyBoard:GetTall()
	end
	self:SetSize( ScrW(), ScrH() - kh )
	self:SetPos( 0, 0 )
	self:SetText( "" )
end
vgui.Register( "HackyClicky", PANEL, "DButton" )

// ---------------------------------------------------------------------------------------------------------
// DERMA: PrintedDoc - The screen for a printed document
// ---------------------------------------------------------------------------------------------------------
local PANEL = {}
function PANEL:SetText( text, font, padding )
	self:PerformLayout()
	if (!font) then font = "ScoreboardText" end
	if (!text) then text = "" end
	if (!padding) then padding = ScrW()*0.02 end
	surface.SetFont( font )
	local tw, th = surface.GetTextSize( string.Replace( text, "\n", "" ) )
	self.RH = th
	self.Font = font
	self.Text = PCMod.Gui.CalcTextWrap( text, font, self:GetWide()-(padding*2) )
	self.Padding = padding
	self:Initialize()
end
function PANEL:Initialize()
	if (self.CloseMe) then return end
	local pn = vgui.Create( "DButton" )
	pn:SetParent( self )
	pn:SetText( "" )
	pn:SetSize( 25, 25 )
	pn.Font = self.Font
	pn.Paint = function( self )
		surface.SetDrawColor( 255, 255, 255, 255 )
		surface.DrawRect( 0, 0, self:GetWide(), self:GetTall() )
		surface.SetDrawColor( 0, 0, 0, 255 )
		surface.DrawOutline( 0, 0, self:GetWide()-1, self:GetTall()-1, Color( 0, 0, 0, 255 ) )
		draw.SimpleText( "X", self.Font, self:GetWide()*0.5, self:GetTall()*0.5, Color( 0, 0, 0, 255 ), 1, 1 )
	end
	pn.DoClick = function() PCMod.Gui.HideDocument() end
	self.CloseMe = pn
	// self:InvalidateLayout()
end
function PANEL:PerformLayout()
	local w = ScrW()
	local h = ScrH()
	self:SetPos( w*0.25, h*0.1 )
	self:SetSize( w*0.5, h*0.8 )
	if (self.CloseMe) then self.CloseMe:SetPos( self:GetWide()-25, 0 ) end
end
function PANEL:Paint()
	surface.SetDrawColor( 255, 255, 255, 255 )
	surface.DrawRect( 0, 0, self:GetWide(), self:GetTall() )
	surface.SetDrawColor( 0, 0, 0, 255 )
	surface.DrawOutline( 0, 0, self:GetWide()-1, self:GetTall()-1, Color( 0, 0, 0, 255 ) )
	local txt = self.Text
	if ((txt) && (type(txt) == "table")) then
		local cnt
		for cnt=1, #txt do
			local t = string.Replace( txt[cnt], "\n", "" )
			local y = ((cnt-1) * self.RH) + self.Padding
			if ((y+self.RH) < self:GetTall()) then
				draw.SimpleText( t, self.Font, self.Padding, y, Color( 0, 0, 0, 255 ), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
			end
		end
	end
end
vgui.Register( "PrintedDoc", PANEL, "PANEL" )

// ---------------------------------------------------------------------------------------------------------
// DERMA: PopupWindow - A popup window
// ---------------------------------------------------------------------------------------------------------
local PANEL = {}
PANEL.Title = ""
PANEL.Padding = 0
PANEL.Description = ""
function PANEL:SetTitle( str )
	self.Title = str
end
function PANEL:Setup( description )
	self.Description = description
	self.Padding = ScrW()*0.01
	self:SetSize( ScrW()*0.4, ScrH()*0.25 )
	self:SetPos( (ScrW()*0.5) - (self:GetWide()*0.5), (ScrH()*0.5) - (self:GetTall()*0.5) )
	local btn = vgui.Create( "DButton", self )
	btn:SetSize( self:GetWide()-(self.Padding*2), 25 )
	btn:SetPos( self.Padding, self:GetTall()*0.7 )
	btn:SetText( "Ok" )
	btn.DoClick = function( self ) self:GetParent():Hide() end
end
function PANEL:MakePopup()
	self:SetVisible( true )
	gui.EnableScreenClicker( true )
end
function PANEL:Paint()
	//local border = Color( 100, 100, 140, 255 )
	local title = Color( 60, 60, 255, 255 )
	//local title = border
	local border = title
	local bg = Color( 128, 128, 128, 255 )
	draw.RoundedBox( 12, 0, 0, self:GetWide(), self:GetTall(), title )
	surface.SetDrawColor( border.r, border.g, border.b, border.a )
	surface.DrawRect( 0, 24, self:GetWide(), self:GetTall()-24 )
	surface.SetDrawColor( bg.r, bg.g, bg.b, bg.a )
	surface.DrawRect( self.Padding*0.5, 26, self:GetWide()-self.Padding, self:GetTall()-26-(self.Padding*0.5) )
	surface.DrawOutline( self.Padding*0.5, 26, self:GetWide()-self.Padding, self:GetTall()-26-(self.Padding*0.5), Color( 0, 0, 0, 255 ) )
	draw.SimpleText( "PCMod 2 - " .. self.Title, "ScoreboardText", 12+(self.Padding*0.5), 13, Color( 255, 255, 255, 255 ), TEXT_ALIGN_LEFT, 1 )
	draw.SimpleText( self.Description, "ScoreboardText", self:GetWide()*0.5, self:GetTall()*0.3, Color( 255, 255, 255, 255 ), 1, 1 )
end
function PANEL:Hide()
	self:Remove()
	gui.EnableScreenClicker( false )
end
vgui.Register( "PopupWindow", PANEL, "PANEL" )