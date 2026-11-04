// PCMod ScreenSpace Device | Browser \\

DEV.Name = "window_browser"

DEV.LastTick = 0
DEV.LastFrame = 0

DEV.Th = "basic"

DEV.Url = ""
DEV.Content = ""
DEV.Status = ""
DEV.Links = {}
DEV.Ctrl = {}
DEV.CreatedCtrl = {}
DEV.Rows = {}
DEV.InlineSig = ""

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

function DEV:InlineSignature()
	local s = ""
	for _, c in ipairs( self.Ctrl or {} ) do
		s = s .. tostring( c.gname ) .. ":" .. tostring( c.kind ) .. ":" .. tostring( c.value or "" ) .. ";"
	end
	return s
end

// Remove the controls we actually created last time (self.Ctrl is already the
// freshly measured list, so we track the created set separately).
function DEV:RemoveInlineControls()
	for _, c in ipairs( self.CreatedCtrl or {} ) do
		if (c.kind == "input") then
			self:RemoveTextbox( c.gname )
		elseif (c.kind == "submit") then
			self:RemoveElement( c.gname )
		end
	end
	self.CreatedCtrl = {}
end

// Create the inline input/submit controls for the current page. Rebuilds when
// the controls change, or when a resize/navigation wiped the previous ones.
function DEV:RebuildControls()
	local sig = self:InlineSignature()
	local missing = false
	for _, c in ipairs( self.CreatedCtrl or {} ) do
		if (c.kind == "input") && ((!self.Textboxes) || (!self.Textboxes[ c.gname ])) then missing = true end
		if (c.kind == "submit") && ((!self.Elements) || (!self.Elements[ c.gname ])) then missing = true end
	end
	if ((sig == self.InlineSig) && (!missing)) then return end
	self:RemoveInlineControls()
	self.InlineSig = sig
	self.CreatedCtrl = {}
	for _, c in ipairs( self.Ctrl or {} ) do
		if (c.kind == "input") then
			self:CreateTextbox( self.Th, c.gname, c.cx, c.cy, c.w, c.h, "" )
			self:SetTextboxText( c.gname, c.value or "" )
			table.insert( self.CreatedCtrl, { kind = "input", gname = c.gname, name = c.name } )
		elseif (c.kind == "submit") then
			self:CreateButton2( self.Th, c.gname, c.x, c.y, c.w, c.h, c.t or "Save" )
			table.insert( self.CreatedCtrl, { kind = "submit", gname = c.gname } )
		end
	end
end

function DEV:Paint( x, y, w, h )
	self:RenderWindow( self.Th, x, y, w, h, "Browser", h*0.06 )

	local c_bor = PCMod.Gui.GetThemeColour( self.Th, "Border" )
	local c_tbbg = PCMod.Gui.GetThemeColour( self.Th, "TextboxBG" )
	local c_tb_txt = PCMod.Gui.GetThemeColour( self.Th, "Textbox_Text" )
	local c_link = Color( 30, 90, 220, 255 )

	local ax, ay, aw, ah = x+(w*0.02), y+(h*0.16), w*0.96, h*0.74
	local maxBottom = ay + ah - 2

	surface.SetFont( "pcmod_3d2d" )
	local tw, th = surface.GetTextSize( "Xq" )
	local doc = PCMod.Web.Parse( self.Content or "" )

	// Measure: positions, link rectangles and inline control placement.
	self.Links = {}
	self.Ctrl = {}
	self.Rows = {}
	local inCount, btnCount = 0, 0
	local inW = w * 0.22
	local subW = w * 0.12
	local ypix = ay + 4

	local function advance( line )
		if ((ypix + th) <= maxBottom) then
			table.insert( self.Rows, line )
			ypix = ypix + th + 1
		end
	end

	for _, spans in ipairs( doc ) do
		local row = { y = ypix, spans = {} }
		local xcur = ax + 2
		for _, sp in ipairs( spans ) do
			if (sp.kind == "input") then
				inCount = inCount + 1
				local gname = "inp_" .. inCount
				table.insert( self.Ctrl, { kind = "input", gname = gname, name = sp.name, value = sp.value, cx = xcur + (inW * 0.5), cy = ypix + (th * 0.5), w = inW, h = th } )
				xcur = xcur + inW + 4
			elseif (sp.kind == "submit") then
				btnCount = btnCount + 1
				table.insert( self.Ctrl, { kind = "submit", gname = "btn_" .. btnCount, x = xcur, y = ypix, w = subW, h = th, t = sp.t } )
				xcur = xcur + subW + 4
			else
				table.insert( row.spans, sp )
				if (sp.href) then
					local sx = surface.GetTextSize( sp.t or "" )
					table.insert( self.Links, { x1 = (xcur - x) / w, y1 = (ypix - y) / h, x2 = (xcur + sx - x) / w, y2 = (ypix + th - y) / h, href = sp.href } )
				end
				xcur = xcur + surface.GetTextSize( sp.t or "" )
			end
		end
		row.xcur = xcur
		advance( row )
	end

	// The content box always fills the window (empty or full); text flows from
	// the top and is clipped by the box bounds.
	surface.SetDrawColor( c_tbbg.r, c_tbbg.g, c_tbbg.b, c_tbbg.a )
	surface.DrawRect( ax, ay, aw, ah )
	surface.DrawOutline( ax, ay, aw, ah, c_bor )

	self:RebuildControls()

	// Draw text (after controls, so the edit fields sit on their line).
	for _, row in ipairs( self.Rows ) do
		local xcur = ax + 2
		for _, sp in ipairs( row.spans ) do
			local txt = sp.t or ""
			local sx = surface.GetTextSize( txt )
			local col = sp.href and c_link or c_tb_txt
			draw.SimpleText( txt, "pcmod_3d2d", xcur, row.y, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
			if (sp.bold) then
				draw.SimpleText( txt, "pcmod_3d2d", xcur+1, row.y, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
			end
			xcur = xcur + sx
		end
	end

	if (self.Status != "") then
		self:RenderText( x+(w*0.5), y+(h*0.92), { self.Status }, Color( 0, 0, 0, 255 ), 1 )
	end

	self:Draw()
end

function DEV:OnUpdate()
	self:SetTextboxText( "txtUrl", self.Url )
end

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
	// Any submit button saves the form.
	if (string.sub( btn, 1, 4 ) == "btn_") then
		local parts = {}
		for _, c in ipairs( self.Ctrl or {} ) do
			if (c.kind == "input") then
				table.insert( parts, tostring( c.name ) .. "=" .. tostring( self:GetTextboxText( c.gname ) or "" ) )
			end
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