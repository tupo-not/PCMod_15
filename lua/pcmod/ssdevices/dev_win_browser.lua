// PCMod ScreenSpace Device | Browser \\

DEV.Name = "window_browser"

DEV.LastTick = 0
DEV.LastFrame = 0

DEV.Th = "basic"

DEV.Url = ""
DEV.Content = ""
DEV.Status = ""
DEV.LineY = {}
DEV.LineHref = {}
DEV.LineH = 0

function DEV:Initialize( x, y, w, h )
	// Exit button
	self:CreateButton2( self.Th, "btnExit", (x+w)-(h*0.06), y, h*0.06, h*0.06, "X" )

	// Address bar + Go
	self:CreateTextbox( self.Th, "txtUrl", x+(w*0.41), y+(h*0.11), w*0.82, h*0.06, "Address:" )
	self:CreateButton2( self.Th, "btnGo", x+(w*0.85), y+(h*0.10), w*0.13, h*0.06, "Go" )

	// Home
	self:CreateButton2( self.Th, "btnHome", x+(w*0.02), y+(h*0.94), w*0.14, h*0.05, "Home" )

	self:OnUpdate()

	self.WinX = x
	self.WinY = y
	self.WinW = w
	self.WinH = h
end

function DEV:Paint( x, y, w, h )
	self:RenderWindow( self.Th, x, y, w, h, "Browser", h*0.06 )

	local c_bor = PCMod.Gui.GetThemeColour( self.Th, "Border" )
	local c_tbbg = PCMod.Gui.GetThemeColour( self.Th, "TextboxBG" )
	local c_tb_txt = PCMod.Gui.GetThemeColour( self.Th, "Textbox_Text" )
	local c_link = Color( 30, 90, 220, 255 )

	// Content area (pixels).
	local ax, ay, aw, ah = x+(w*0.02), y+(h*0.20), w*0.96, h*0.70
	surface.SetDrawColor( c_tbbg.r, c_tbbg.g, c_tbbg.b, c_tbbg.a )
	surface.DrawRect( ax, ay, aw, ah )
	surface.DrawOutline( ax, ay, aw, ah, c_bor )

	surface.SetFont( "pcmod_3d2d" )
	local tw, th = surface.GetTextSize( "Xq" )
	local doc = PCMod.Web.Parse( self.Content )

	self.LineY = {}
	self.LineHref = {}
	self.LineH = (th + 1) / h

	local ypix = ay + 2
	local lineIndex = 0
	for _, line in ipairs( doc ) do
		if ((ypix + th) > (ay + ah - 2)) then break end
		lineIndex = lineIndex + 1
		self.LineY[ lineIndex ] = (ypix - y) / h
		local xcur = ax + 2
		for _, sp in ipairs( line ) do
			local txt = sp.t or ""
			local col = sp.href and c_link or c_tb_txt
			draw.SimpleText( txt, "pcmod_3d2d", xcur, ypix, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
			if (sp.bold) then
				draw.SimpleText( txt, "pcmod_3d2d", xcur+1, ypix, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
			end
			xcur = xcur + surface.GetTextSize( txt )
			if (sp.href) then self.LineHref[ lineIndex ] = sp.href end
		end
		ypix = ypix + th + 1
	end

	if (self.Status != "") then
		self:RenderText( x+(w*0.5), y+(h*0.92), { self.Status }, Color( 0, 0, 0, 255 ), 1 )
	end

	self:Draw()
end

function DEV:OnUpdate()
	self:SetTextboxText( "txtUrl", self.Url )
end

// Clicks arrive normalised (0..1) within the window. A click on a link line
// navigates; anything else falls through to the textbox/buttons.
function DEV:DoClick( x, y )
	for i, href in pairs( self.LineHref or {} ) do
		local ly = self.LineY[ i ]
		if (ly && (y >= ly) && (y < (ly + self.LineH))) then
			self:RunProgCommand( "browser", "go", href )
			return
		end
	end
	self:ProcessClick( x, y )
end

function DEV:ButtonClick( btn )
	if (btn == "btnExit") then
		self:RunProgCommand( "browser", "exit" )
		return
	end
	if (btn == "btnGo") then
		self:RunProgCommand( "browser", "go", self:GetTextboxText( "txtUrl" ) )
		return
	end
	if (btn == "btnHome") then
		self:RunProgCommand( "browser", "home" )
	end
end

function DEV:Tick()
	self.LastTick = CurTime()
	self.LastFrame = PCMod.SDraw.CFrame
end

function DEV:KeyPress( key, txt )
	self:KeyPressTextboxes( key, txt )
end