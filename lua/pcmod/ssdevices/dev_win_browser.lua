// PCMod ScreenSpace Device | Browser \\

DEV.Name = "window_browser"

DEV.LastTick = 0
DEV.LastFrame = 0

DEV.Th = "basic"

DEV.Url = ""
DEV.Content = ""
DEV.Status = ""

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

function DEV:WrapContent( text, width )
	text = text or ""
	if (type( text ) != "string") then text = tostring( text ) end
	local out = {}
	for _, line in ipairs( string.Explode( "\n", text ) ) do
		local wrapped = PCMod.Gui.CalcTextWrap( line, "pcmod_3d2d", width )
		for _, wl in ipairs( wrapped ) do
			// string.gsub returns (result, count); a bare call feeds both into
			// table.insert (3-arg form). string.Replace returns a single string.
			table.insert( out, string.Replace( wl, "\n", "" ) )
		end
	end
	return out
end

function DEV:Paint( x, y, w, h )
	self:RenderWindow( self.Th, x, y, w, h, "Browser", h*0.06 )

	local c_bor = PCMod.Gui.GetThemeColour( self.Th, "Border" )
	local c_tbbg = PCMod.Gui.GetThemeColour( self.Th, "TextboxBG" )
	local c_tb_txt = PCMod.Gui.GetThemeColour( self.Th, "Textbox_Text" )

	local a = {}
	a.x, a.y, a.w, a.h = x+(w*0.02), y+(h*0.20), w*0.96, h*0.70
	surface.SetDrawColor( c_tbbg.r, c_tbbg.g, c_tbbg.b, c_tbbg.a )
	surface.DrawRect( a.x, a.y, a.w, a.h )
	surface.DrawOutline( a.x, a.y, a.w, a.h, c_bor )

	surface.SetFont( "pcmod_3d2d" )
	local tw, th = surface.GetTextSize( "Xq" )
	local lines = self:WrapContent( self.Content, a.w - 4 )
	local max = math.floor( a.h / th )
	for i = 1, math.min( #lines, max ) do
		draw.SimpleText( lines[ i ], "pcmod_3d2d", a.x+2, a.y+((i-1)*th), c_tb_txt, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
	end

	if (self.Status != "") then
		self:RenderText( x+(w*0.5), y+(h*0.92), { self.Status }, Color( 0, 0, 0, 255 ), 1 )
	end

	self:Draw()
end

function DEV:OnUpdate()
	self:SetTextboxText( "txtUrl", self.Url )
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

function DEV:DoClick( x, y )
	self:ProcessClick( x, y )
end

function DEV:Tick()
	self.LastTick = CurTime()
	self.LastFrame = PCMod.SDraw.CFrame
end

function DEV:KeyPress( key, txt )
	self:KeyPressTextboxes( key, txt )
end