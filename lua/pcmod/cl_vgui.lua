
// ---------------------------------------------------------------------------------------------------------
// cl_vgui.lua - Revision 1
// Client-Side
// Controls drawing operations on the client (specifically derma and the vgui library)
// ---------------------------------------------------------------------------------------------------------


// ---------------------------------------------------------------------------------------------------------
// ShowLockFrame - Shows / Hides the lock frame
// ---------------------------------------------------------------------------------------------------------

// Dark "device menu" style for the lock frame (design mock): dark rounded panel,
// header with icon + title + subtitle + X, icon rows with chevrons, footer.
local MENU_BG = Color( 22, 24, 29, 255 )
local MENU_ROW = Color( 30, 33, 40, 255 )
local MENU_ROW_HOVER = Color( 14, 105, 96, 255 )
local MENU_ICON_BG = Color( 16, 88, 80, 255 )
local MENU_ICON = Color( 150, 235, 215, 255 )
local MENU_TEXT = Color( 240, 242, 245, 255 )
local MENU_DIM = Color( 140, 145, 155, 255 )
local MENU_LINE = Color( 45, 48, 56, 255 )
local MENU_FOOT = Color( 110, 115, 125, 255 )

local function DrawMonitorIcon( x, y, s, col )
	surface.SetDrawColor( col )
	surface.DrawOutlinedRect( x, y, s, s * 0.62 )
	surface.DrawRect( x + s * 0.35, y + s * 0.62, s * 0.3, s * 0.12 )
	surface.DrawRect( x + s * 0.2, y + s * 0.74, s * 0.6, s * 0.08 )
end

local function DrawKeyboardIcon( x, y, s, col )
	surface.SetDrawColor( col )
	surface.DrawOutlinedRect( x, y + s * 0.2, s, s * 0.6 )
	for i = 0, 2 do
		for j = 0, 1 do
			surface.DrawRect( x + s * (0.18 + i * 0.24), y + s * (0.34 + j * 0.24), s * 0.12, s * 0.12 )
		end
	end
	surface.DrawRect( x + s * 0.25, y + s * 0.68, s * 0.5, s * 0.1 )
end

local function DrawPowerIcon( x, y, s, col )
	surface.SetDrawColor( col )
	local cx, cy, r = x + s * 0.5, y + s * 0.55, s * 0.32
	for i = 0, 24 do
		local a1 = math.rad( -60 + i * 12 )
		local a2 = math.rad( -60 + (i + 1) * 12 )
		surface.DrawLine( cx + math.cos( a1 ) * r, cy + math.sin( a1 ) * r, cx + math.cos( a2 ) * r, cy + math.sin( a2 ) * r )
	end
	surface.DrawLine( cx, y + s * 0.08, cx, y + s * 0.55 )
end

local function DrawSlidersIcon( x, y, s, col )
	surface.SetDrawColor( col )
	for i = 0, 2 do
		local yy = y + s * (0.2 + i * 0.3)
		surface.DrawLine( x, yy, x + s, yy )
		surface.DrawRect( x + s * (0.25 + i * 0.25), yy - s * 0.08, s * 0.16, s * 0.16 )
	end
end

function PCMod.Gui.ShowLockFrame( show )
	if (!show) then
		if (PCMod.Gui.LFrame) then
			PCMod.Gui.LFrame:Remove()
			PCMod.Gui.LFrame = nil
		end
		return
	end

	local ent = ents.GetByIndex( PCMod.Gui.CamLockID )
	local isLaptop = (IsValid( ent ) && (ent:GetClass() == "pcmod_laptop"))

	local W = math.Clamp( ScrW() * 0.14, 230, 320 )
	local HEADER_H = 56
	local ROW_H = 52
	local ROW_GAP = 6
	local FOOTER_H = 30
	local rowCount = 1 + (isLaptop && 1 or 0)
	local H = HEADER_H + 8 + rowCount * (ROW_H + ROW_GAP) + FOOTER_H

	local pn = vgui.Create( "DFrame" )
	pn:SetPos( ScrW() * 0.86, ScrH() * 0.1 )
	pn:SetSize( W, H )
	pn:SetTitle( "" )
	pn:SetDraggable( true ) -- the custom-painted header bar is the drag area
	pn:ShowCloseButton( false )
	PCMod.Gui.LFrame = pn

	pn.Paint = function( self, w, h )
		draw.RoundedBox( 8, 0, 0, w, h, MENU_BG )
		draw.RoundedBox( 6, 10, 11, 34, 34, MENU_ICON_BG )
		DrawMonitorIcon( 17, 19, 20, MENU_ICON )
		draw.SimpleText( "PCMod", "PCModMenuTitle", 52, 17, MENU_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
		draw.SimpleText( "Computer controls", "PCModMenuSub", 52, 37, MENU_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
		surface.SetDrawColor( MENU_LINE )
		surface.DrawLine( 8, HEADER_H - 4, w - 8, HEADER_H - 4 )
		draw.SimpleText( "PCMod • Device menu", "PCModMenuFoot", 12, h - 17, MENU_FOOT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
		DrawSlidersIcon( w - 26, h - 24, 14, MENU_FOOT )
	end

	local xbtn = vgui.Create( "DButton" )
	xbtn:SetParent( pn )
	xbtn:SetPos( W - 34, 10 )
	xbtn:SetSize( 24, 24 )
	xbtn:SetText( "" )
	xbtn.Paint = function( self, w, h )
		if (self:IsHovered()) then draw.RoundedBox( 4, 0, 0, w, h, Color( 60, 64, 72, 255 ) ) end
		surface.SetDrawColor( MENU_DIM )
		surface.DrawLine( 7, 7, w - 7, h - 7 )
		surface.DrawLine( w - 7, 7, 7, h - 7 )
	end
	xbtn.DoClick = function( self )
		PCMod.Beam.UnlockCam( LocalPlayer() )
	end


	// icon row button
	local function MakeRow( y, iconFn, label, sublabel, onClick )
		local b = vgui.Create( "DButton" )
		b:SetParent( pn )
		b:SetPos( 8, y )
		b:SetSize( W - 16, ROW_H )
		b:SetText( "" )
		b.Paint = function( self, w, h )
			draw.RoundedBox( 6, 0, 0, w, h, (self:IsHovered() && MENU_ROW_HOVER) or MENU_ROW )
			iconFn( 16, h * 0.5 - 8, 16, MENU_ICON )
			draw.SimpleText( label, "PCModMenuRow", 44, h * 0.32, MENU_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
			draw.SimpleText( sublabel, "PCModMenuSub", 44, h * 0.72, MENU_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
			draw.SimpleText( ">", "PCModMenuRow", w - 16, h * 0.5, MENU_DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
		end
		b.DoClick = onClick
		return b
	end

	local y = HEADER_H + 4
	MakeRow( y, DrawKeyboardIcon, "Clipboard", "Open typing interface", function( self )
		RunConsoleCommand( "pc_quicktype", PCMod.SDraw.KeyboardEntID )
	end )
	y = y + ROW_H + ROW_GAP

	if (isLaptop) then
		MakeRow( y, DrawPowerIcon, "Toggle Power", "Change computer power state", function( self )
			RunConsoleCommand( "pc_command", PCMod.Gui.CamLockID, "power" )
		end )
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
	// Always cover the whole screen. Shrinking this panel while the on-screen
	// keyboard is visible left the bottom corners (taskbar / Start button)
	// covered by no panel at all, because the keyboard is centered and does
	// not reach them - clicks there never reached the screenspace. Instead the
	// keyboard panel is moved to the front when shown (see sh_beam LockKeyboard),
	// so its keys keep receiving clicks and everything else falls through to
	// this fullscreen catcher.
	self:SetSize( ScrW(), ScrH() )
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