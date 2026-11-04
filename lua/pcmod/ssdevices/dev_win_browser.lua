// PCMod ScreenSpace Device | Browser \\

DEV.Name = "window_browser"

DEV.LastTick = 0
DEV.LastFrame = 0

DEV.Th = "basic"

DEV.Url = ""
DEV.Content = ""
DEV.Status = ""
DEV.Links = {}
DEV.Form = { action = "", fields = {} }
DEV.FormSig = ""

function DEV:Initialize( x, y, w, h )
	self:CreateButton2( self.Th, "btnExit", (x+w)-(h*0.06), y, h*0.06, h*0.06, "X" )
	self:CreateTextbox( self.Th, "txtUrl", x+(w*0.41), y+(h*0.11), w*0.82, h*0.06, "Address:" )
	self:CreateButton2( self.Th, "btnGo", x+(w*0.85), y+(h*0.10), w*0.13, h*0.06, "Go" )
	self:CreateButton2( self.Th, "btnHome", x+(w*0.02), y+(h*0.94), w*0.14, h*0.05, "Home" )

	self:OnUpdate()

	self.WinX = x
	self.WinY = y
	self.WinW = w
	self.WinH = h
end

function DEV:FormSignature( form )
	local s = tostring( #(form.fields or {}) ) .. ":"
	for _, f in ipairs( form.fields or {} ) do
		s = s .. tostring( f.name ) .. "=" .. tostring( f.value ) .. ";"
	end
	return s .. "|" .. tostring( form.action or "" )
end

function DEV:RemoveFormControls()
	for i = 1, 8 do self:RemoveTextbox( "frm_" .. i ) end
	self:RemoveElement( "btnFormSave" )
end

// (Re)build editable fields from the page's single <form>. Runs when the form
// signature changes OR when a resize wiped the controls (Int_Reinitialize calls
// OnCreate), so the fields survive window resizing.
function DEV:BuildForm( x, y, w, h )
	local form = PCMod.Web.ParseForm( self.Content or "" )
	local sig = self:FormSignature( form )
	local missing = false
	if (#(form.fields) > 0) then
		if ((!self.Textboxes) || (!self.Textboxes[ "frm_1" ])) then missing = true end
		if ((!self.Elements) || (!self.Elements[ "btnFormSave" ])) then missing = true end
	end
	if ((sig == self.FormSig) && (!missing)) then return end
	self.FormSig = sig
	self.Form = form
	self:RemoveFormControls()
	local yn = 0.53
	for i, f in ipairs( form.fields ) do
		self:CreateTextbox( self.Th, "frm_" .. i, x+(w*0.45), y+(h*yn), w*0.5, h*0.055, f.label or f.name )
		self:SetTextboxText( "frm_" .. i, f.value )
		yn = yn + 0.075
	end
	if (#(form.fields) > 0) then
		self:CreateButton2( self.Th, "btnFormSave", x+(w*0.78), y+(h*(yn - 0.075)), w*0.2, h*0.055, "Save" )
	end
end

function DEV:Paint( x, y, w, h )
	self:RenderWindow( self.Th, x, y, w, h, "Browser", h*0.06 )

	local c_bor = PCMod.Gui.GetThemeColour( self.Th, "Border" )
	local c_tbbg = PCMod.Gui.GetThemeColour( self.Th, "TextboxBG" )
	local c_tb_txt = PCMod.Gui.GetThemeColour( self.Th, "Textbox_Text" )
	local c_link = Color( 30, 90, 220, 255 )

	// Content area (pixels).
	local ax, ay, aw, ah = x+(w*0.02), y+(h*0.16), w*0.96, h*0.34
	surface.SetDrawColor( c_tbbg.r, c_tbbg.g, c_tbbg.b, c_tbbg.a )
	surface.DrawRect( ax, ay, aw, ah )
	surface.DrawOutline( ax, ay, aw, ah, c_bor )

	surface.SetFont( "pcmod_3d2d" )
	local tw, th = surface.GetTextSize( "Xq" )
	local doc = PCMod.Web.Parse( self.Content )

	self.Links = {}
	local ypix = ay + 2
	for _, line in ipairs( doc ) do
		if ((ypix + th) > (ay + ah - 2)) then break end
		local xcur = ax + 2
		for _, sp in ipairs( line ) do
			local txt = sp.t or ""
			local sx = surface.GetTextSize( txt )
			local col = sp.href and c_link or c_tb_txt
			draw.SimpleText( txt, "pcmod_3d2d", xcur, ypix, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
			if (sp.bold) then
				draw.SimpleText( txt, "pcmod_3d2d", xcur+1, ypix, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
			end
			if (sp.href) then
				table.insert( self.Links, { x1 = (xcur - x) / w, y1 = (ypix - y) / h, x2 = (xcur + sx - x) / w, y2 = (ypix + th - y) / h, href = sp.href } )
			end
			xcur = xcur + sx
		end
		ypix = ypix + th + 1
	end

	self:BuildForm( x, y, w, h )

	if (self.Status != "") then
		self:RenderText( x+(w*0.5), y+(h*0.92), { self.Status }, Color( 0, 0, 0, 255 ), 1 )
	end

	self:Draw()
end

function DEV:OnUpdate()
	self:SetTextboxText( "txtUrl", self.Url )
end

// Clicks arrive normalised (0..1) in the window. Hit-test links by their exact
// rectangle; anything else falls through to the textboxes/buttons.
function DEV:DoClick( x, y )
	for _, l in ipairs( self.Links or {} ) do
		if ((x >= l.x1) && (x <= l.x2) && (y >= l.y1) && (y <= l.y2)) then
			self:RunProgCommand( "browser", "go", l.href )
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
		return
	end
	if (btn == "btnFormSave") then
		local parts = {}
		for i, f in ipairs( self.Form.fields or {} ) do
			table.insert( parts, tostring( f.name ) .. "=" .. tostring( self:GetTextboxText( "frm_" .. i ) or "" ) )
		end
		if (#parts > 0) then
			self:RunProgCommand( "browser", "go", "?" .. table.concat( parts, "&" ) )
		end
	end
end

function DEV:Tick()
	self.LastTick = CurTime()
	self.LastFrame = PCMod.SDraw.CFrame
end

function DEV:KeyPress( key, txt )
	self:KeyPressTextboxes( key, txt )
end