
// PCMod ScreenSpace Device | Notepad \\

DEV.Name = "window_notepad"

DEV.LastTick = 0
DEV.LastFrame = 0

DEV.Th = "basic"
DEV.TC = ""

DEV.St = 0
DEV.Status = ""
DEV.StatClose = 0
local saydir = 0

// ---------------------------------------------------------------------------
// Font settings. These are a client-side preference (shared by every Notepad
// this player opens), so applying them cannot round-trip through the server
// and reset unsaved text.
// ---------------------------------------------------------------------------
PCMod.NP = PCMod.NP or {}
PCMod.NP.FontFamily = PCMod.NP.FontFamily or "Tahoma"
PCMod.NP.FontScale = PCMod.NP.FontScale or 100

DEV.FONT_FAMILIES = { "Tahoma", "Arial", "Verdana", "Courier New", "Times New Roman", "Georgia" }
DEV.FONT_SCALES = { 75, 100, 125, 150, 200 }
DEV.ShowSettings = false

function DEV:GetFontFamily()
	local fam = PCMod.NP.FontFamily or "Tahoma"
	for _, v in ipairs( self.FONT_FAMILIES ) do
		if (v == fam) then return fam end
	end
	return "Tahoma"
end

function DEV:GetFontScale()
	local sc = tonumber( PCMod.NP.FontScale ) or 100
	return math.Clamp( sc, 50, 300 )
end

// Registers (once per family/size) the font used by the editor. The size is
// relative to the normal UI font, so it follows GUI scale and resolution.
function DEV:GetEditorFontName()
	local fam = self:GetFontFamily()
	local base = 20
	if (PCMod.Gui && PCMod.Gui.GetFontSize) then base = PCMod.Gui.GetFontSize( 20 ) end
	local size = math.floor( (base * (self:GetFontScale() / 100)) + 0.5 )
	if (size < 6) then size = 6 end
	local name = "pcmod_np_" .. string.gsub( fam, "[^%w]", "_" ) .. "_" .. size
	if (self.CurFontName != name) then
		surface.CreateFont( name, { font = fam, size = size, weight = 400 } )
		self.CurFontName = name
	end
	return name
end

function DEV:ReinitializeSelf()
	if (self.Int_Reinitialize) then
		self:Int_Reinitialize( self.win_x, self.win_y, self.win_w, self.win_h )
	end
end

// Geometry for the bottom filename row. The browse button is square (its
// width equals the row height) and sits just left of the resize grip, so it
// neither overlaps the filename textbox nor the resize handle.
function DEV:GetFilenameRowLayout( x, y, w, h )
	local rowH = h * 0.05
	local rowY = y + (h * 0.945)
	local btnSize = rowH
	// The bottom-right corner (ResizeGrip fraction of the window) belongs to
	// the resize handle, so keep the button fully to the left of it.
	local grip = self.ResizeGrip or 0.035
	local btnRight = x + (w * (1 - grip))
	local btnX = btnRight - btnSize
	local tbLeft = x + (w * 0.03)
	local tbRight = btnX - (w * 0.01)
	local tbW = math.max( w * 0.1, tbRight - tbLeft )
	return {
		BtnX = btnX,
		BtnY = rowY,
		BtnW = btnSize,
		BtnH = btnSize,
		TbX = tbLeft + (tbW * 0.5),
		TbY = rowY + (rowH * 0.5),
		TbW = tbW,
		TbH = rowH
	}
end

function DEV:OpenFontSettings()
	if (self.ShowSettings) then return end
	// Int_Reinitialize cannot preserve controls that the settings layout does
	// not create, so keep the unsaved document/filename here.
	self.PendingText = self:GetTextboxText( "txtMain" )
	self.PendingFilename = self:GetTextboxText( "txtFilename" )
	self.ShowSettings = true
	self:ReinitializeSelf()
end

function DEV:CloseFontSettings( apply )
	if (apply) then
		local fam = self:GetListboxSelRow( "lstFontFamily" )
		if ((fam) && (fam != "")) then PCMod.NP.FontFamily = fam end
		local sc = tonumber( self:GetListboxSelRow( "lstFontScale" ) )
		if (sc) then PCMod.NP.FontScale = sc end
	end
	self.ShowSettings = false
	self:ReinitializeSelf()
end

function DEV:InitializeSettings( x, y, w, h )
	self:CreateButton2( self.Th, "btnSettingsClose", (x+w)-(h*0.06), y, h*0.06, h*0.06, "X" )

	self:CreateListbox( self.Th, "lstFontFamily", x+(w*0.06), y+(h*0.17), w*0.42, h*0.55 )
	for _, fam in ipairs( self.FONT_FAMILIES ) do
		self:AddListboxItem( "lstFontFamily", fam, fam )
	end
	self:SetListboxSelRow( "lstFontFamily", self:GetFontFamily() )

	self:CreateListbox( self.Th, "lstFontScale", x+(w*0.54), y+(h*0.17), w*0.40, h*0.55 )
	local cur = self:GetFontScale()
	local bestkey = tostring( self.FONT_SCALES[ 2 ] )
	local bestdiff = 999
	for _, sc in ipairs( self.FONT_SCALES ) do
		self:AddListboxItem( "lstFontScale", tostring( sc ), tostring( sc ) .. "%" )
		local diff = math.abs( sc - cur )
		if (diff < bestdiff) then
			bestdiff = diff
			bestkey = tostring( sc )
		end
	end
	self:SetListboxSelRow( "lstFontScale", bestkey )

	self:CreateButton2( self.Th, "btnFontApply", x+(w*0.54), y+(h*0.80), w*0.19, h*0.08, "Apply" )
	self:CreateButton2( self.Th, "btnFontCancel", x+(w*0.75), y+(h*0.80), w*0.19, h*0.08, "Cancel" )

	self.WinX = x
	self.WinY = y
	self.WinW = w
	self.WinH = h
end

function DEV:Initialize( x, y, w, h )
	if (self.ShowSettings) then
		self:InitializeSettings( x, y, w, h )
		return
	end

	// Make control buttons
	self:CreateButton2( self.Th, "btnExit", (x+w)-(h*0.06), y, h*0.06, h*0.06, "X" )
	self:CreateButton2( self.Th, "btnNew", x+(w*0.02), y+(h*0.88), w*0.20, h*0.05, "New" )
	self:CreateButton2( self.Th, "btnSave", x+(w*0.24), y+(h*0.88), w*0.20, h*0.05, "Save" )
	self:CreateButton2( self.Th, "btnOpen", x+(w*0.46), y+(h*0.88), w*0.18, h*0.05, "Open" )
	self:CreateButton2( self.Th, "btnPrint", x+(w*0.66), y+(h*0.88), w*0.16, h*0.05, "Print" )
	self:CreateButton2( self.Th, "btnFont", x+(w*0.84), y+(h*0.88), w*0.14, h*0.05, "Font" )
	local fl = self:GetFilenameRowLayout( x, y, w, h )
	self:CreateButton2( self.Th, "btnBrowse", fl.BtnX, fl.BtnY, fl.BtnW, fl.BtnH, "..." )
	
	// Make text area
	self:CreateTextEntry( self.Th, "txtMain", x+(w*0.02), y+(h*0.08), w*0.96, h*0.74 )
	self:SetTextboxFont( "txtMain", self:GetEditorFontName() )
	
	// Make filename textbox
	self:CreateTextbox( self.Th, "txtFilename", fl.TbX, fl.TbY, fl.TbW, fl.TbH, "Filename" )
	
	// Update
	self:OnUpdate()

	// Restore the unsaved document after leaving the settings panel.
	if (self.PendingText != nil) then
		self:SetTextboxText( "txtMain", self.PendingText )
		self.PendingText = nil
	end
	if (self.PendingFilename != nil) then
		self:SetTextboxText( "txtFilename", self.PendingFilename )
		self.PendingFilename = nil
	end
	
	// Record window data
	self.WinX = x
	self.WinY = y
	self.WinW = w
	self.WinH = h
end

function DEV:OnUpdate()
	PCMod.Msg( "Device reported update!", true )
	self.StatClose = CurTime()+3
	self.Status = ""
	local st = self.St
	if (st == 1) then self.Status = "File saved." end
	if (st == 2) then self.Status = "File opened." end
	if (st == 3) then self.Status = "File does not exist." end
	if (st == 4) then self.Status = "No printer hardware." end
	if (st == 5) then self.Status = "File printed." end
	if ((self.FN) && (self.FN != "")) then
		self:SetTextboxText( "txtFilename", self.FN )
	end
	if (self.Textboxes[ "txtMain" ]) then
		self:SetTextboxFont( "txtMain", self:GetEditorFontName() )
	end
	if (!self.TC) then return end
	self:SetTextboxText( "txtMain", self.TC )
end

function DEV:Paint( x, y, w, h )
	if (self.ShowSettings) then
		self:RenderWindow( self.Th, x, y, w, h, "Notepad - Font Settings", h*0.06 )
		self:RenderText( x+(w*0.27), y+(h*0.12), { "Font Family" }, Color( 0, 0, 0, 255 ), 1 )
		self:RenderText( x+(w*0.74), y+(h*0.12), { "Font Size" }, Color( 0, 0, 0, 255 ), 1 )
		self:Draw()
		return
	end
	self:RenderWindow( self.Th, x, y, w, h, "Notepad", h*0.06 )
	self:Draw()
	local status = self.Status
	if (!status) then status = "" end
	if ((status == "") && (self.TC != self:GetTextboxText( "txtMain" ))) then status = "Unsaved Changes" end
	self:RenderText( x+(w*0.5), y+(h*0.82), { status }, Color( 0, 0, 0, 255 ), 1 )
end

function DEV:ButtonClick( btn )
	local x, y, w, h = self.win_x, self.win_y, self.win_w, self.win_h
	if (btn == "btnFont") then
		self:OpenFontSettings()
		return
	end
	if ((btn == "btnSettingsClose") || (btn == "btnFontCancel")) then
		self:CloseFontSettings( false )
		return
	end
	if (btn == "btnFontApply") then
		self:CloseFontSettings( true )
		return
	end
	if (btn == "btnExit") then
		self:RunProgCommand( "notepad", "exit" )
	end
	if (btn == "btnSave") then
		local fn = self:GetTextboxText( "txtFilename" )
		if ((!fn) || (fn == "")) then
			fn = "untitled.txt"
			self:SetTextboxText( "txtFilename", fn )
		end
		self:SubmitContent( fn )
		// self:RunProgCommand( "notepad", "save", fn )
	end
	if (btn == "btnNew") then
		self:SetTextboxText( "txtMain", "" )
		self:SetTextboxText( "txtFilename", "newdocument.txt" )
		self:SubmitContent( "newdocument.txt" )
	end
	if (btn == "btnOpen") then
		local fn = self:GetTextboxText( "txtFilename" )
		if ((!fn) || (fn == "")) then
			fn = "untitled.txt"
			self:SetTextboxText( "txtFilename", fn )
		end
		self:RunProgCommand( "notepad", "open", fn )
	end
	if (btn == "btnBrowse") then
		self:RunProgCommand( "notepad", "browse" )
	end
	if (btn == "btnPrint") then
		local statusn = 0
		local status = self.Status
		if (!status) then status = "" end
		if ((status == "") && (self.TC != self:GetTextboxText( "txtMain" ))) then statusn = 1 end

		self:RunProgCommand( "notepad", "print", statusn )
		// self:SubmitCommand( "os_command", "sys_print", 
	end
end

function DEV:DoClick( x, y )
	self:ProcessClick( x, y )
end

function DEV:DataRecieved( name, data )
	if (name == "filename") then self:SetTextboxText( "txtFilename", data ) end
	if (name == "runcommand") then self:RunProgCommand( "notepad", data ) end
	if (name == "doprint") then self:RunProgCommand( "notepad", "printdoc", data ) end
end

function DEV:Tick()
	self.LastTick = CurTime()
	self.LastFrame = PCMod.SDraw.CFrame
	if ((self.StatClose != 0) && (CurTime() > self.StatClose)) then
		self.StatClose = 0
		self.Status = ""
	end
end

function DEV:KeyPress( key, txt )
	self:KeyPressTextboxes( key, txt )
end

function DEV:SubmitContent( filename )
	// Split our content into segments of 128
	local str = self:GetTextboxText( "txtMain" )
	//datastream.Send( "pc_stream", { PCMod.Gui.CamLockID, "input", "os_command", "prog_command", "notepad", "content", str } )
	self:StreamProgCommand( "notepad", "savecontent", filename, str )
	// RunConsoleCommand( "pc_command", PCMod.Gui.CamLockID, "input", ... )
	/*
	if ((!str) || (str == "")) then
		self:RunProgCommand( "notepad", "ct_clear" )
		return
	end
	local segs = PCMod.SplitString( str, 128 )
	local cnt
	self:RunProgCommand( "notepad", "ct_start" )
	for cnt=1, #segs do
		local seg = segs[ cnt ]
		if (seg) then
			self:RunProgCommand( "notepad", "ct_seg", seg )
		end
	end
	self:RunProgCommand( "notepad", "ct_end" )
	*/
end
