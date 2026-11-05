
// ---------------------------------------------------------------------------------------------------------
// cl_keyboard.lua - Revision 1
// Client-Side
// Controls the on-screen keyboard
// ---------------------------------------------------------------------------------------------------------


// ---------------------------------------------------------------------------------------------------------
// Load core stuff
// ---------------------------------------------------------------------------------------------------------

PCMod.Msg( "Keyboard Controller Loaded!", true )

include( "pcmod/cl_input.lua" )
--require( "keyboard" )

local KeyRepeatCvar = GetConVar( "pc_keyrepeat" )
if (!KeyRepeatCvar) then
	KeyRepeatCvar = CreateClientConVar( "pc_keyrepeat", "200", true, false, "PCMod keyboard repeat interval in milliseconds" )
end
local KeyHoldCvar = GetConVar( "pc_keyhold" )
if (!KeyHoldCvar) then
	KeyHoldCvar = CreateClientConVar( "pc_keyhold", "500", true, false, "PCMod keyboard delay before repeat starts in milliseconds" )
end

local function ApplyKeyRepeat( value )
	local ms = tonumber( value ) or 200
	if (ms < 20) then ms = 20 end
	if (ms > 1000) then ms = 1000 end
	keyboard.SetLatency( ms )
end

local function ApplyKeyHold( value )
	local ms = tonumber( value ) or 500
	if (ms < 0) then ms = 0 end
	if (ms > 2000) then ms = 2000 end
	keyboard.SetHoldTime( ms )
end

if (KeyRepeatCvar) then
	ApplyKeyRepeat( KeyRepeatCvar:GetFloat() )
end
if (KeyHoldCvar) then
	ApplyKeyHold( KeyHoldCvar:GetFloat() )
end
if (istable( cvars ) && cvars.AddChangeCallback) then
	cvars.AddChangeCallback( "pc_keyrepeat", function( convar_name, old, new )
		ApplyKeyRepeat( new )
	end, "PCMod.KeyRepeat" )
	cvars.AddChangeCallback( "pc_keyhold", function( convar_name, old, new )
		ApplyKeyHold( new )
	end, "PCMod.KeyHold" )
end


// ---------------------------------------------------------------------------------------------------------
// Add the keyboard hooks
// ---------------------------------------------------------------------------------------------------------


keyboard.SetCallback( function( key )
	PCMod.Msg( "Keypress '" .. key .. "'!", true )
	// Guard against a partial reload: cl_keyboard may not have redefined
	// this yet while the old keyboard module callback is still alive.
	if (PCMod.Gui.KBRegisterKeyPress) then
		PCMod.Gui.KBRegisterKeyPress( key, key )
	end
end )
// Round 32 (M-02): the "KeyPress" hook of the engine delivers the NUMERIC
// key code of the pressed key. It used to be forwarded to the device as the
// key AND as the text, so the number of the key (65 for "a", 130 for Enter,
// ...) ended up in the text field of the PC.
// The hook is not needed: the keyboard module above (which polls the keys)
// already delivers every key - the printable ones as the character and the
// control ones ("arrow_left", "arrow_right", "<--", "enter", "tab") with the
// names the devices understand. The real in-game test of Round 24 confirmed
// it: the arrow keys and Backspace worked and the typed text was clean.
// So the hook is removed - a numeric key code must never reach a text field.

// ---------------------------------------------------------------------------------------------------------
// EnableCapture - Enables keyboard input capture
// ---------------------------------------------------------------------------------------------------------
function PCMod.EnableCapture( enable )
	keyboard.EnableCapture( enable )
end

// ---------------------------------------------------------------------------------------------------------
// InitKeyboard - Sets up the derma keyboard
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.InitKeyboard()
	PCMod.Msg( "Creating Keyboard Derma Panel...", true )
	// A partial reload can run this again - don't leak the old panel.
	if (IsValid( PCMod.Gui.KeyBoard )) then
		PCMod.Gui.KeyBoard:Remove()
	end
	PCMod.Gui.KeyBoard = nil
	local kb = vgui.Create( "Keyboard" )
	if (!kb) then
		PCMod.Warning( "Failed to create on-screen keyboard!" )
		return
	end
	// Round 34 (M-44): vgui.Create already calls PANEL:Initialize - the extra
	// call created every key of the keyboard a second time (~60 buttons).
	kb:PerformLayout()
	kb:SetVisible( false )
	local w = ScrW()
	local h = ScrH()
	local kw, kh = kb:GetSize()
	kb:SetPos( (w/2)-(kw/2), (h*0.99)-kh )
	PCMod.Gui.KeyBoard = kb
end
hook.Add( "Initialize", "PCMod.Gui.InitKeyboard", PCMod.Gui.InitKeyboard )

// ---------------------------------------------------------------------------------------------------------
// ShowQuickType - Shows the Quick Type menu
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.ShowQuickType()
	// Create the frame
	local window = vgui.CreateWindow( 0.8, 0.8, "PCMod Quick Type" )
	window:ShowCloseButton( false )
	PCMod.Gui.QuickType = window
	
	// Create the textbox
	local pn = vgui.Create( "DTextEntry" )
	pn:SetParent( window )
	pn:SetPos( 5, 35 )
	pn:SetSize( window:GetWide()-10, window:GetTall()-70 )
	pn:SetMultiline( true )
	PCMod.Gui.QuickTypeText = pn
	
	// Create the buttons
	local btn = vgui.Create( "DButton" )
	btn:SetParent( window )
	btn:SetPos( 5, window:GetTall()-25 )
	btn:SetSize( window:GetWide()-10, 20 )
	btn:SetText( "Enter" )
	btn.DoClick = function( self )
		PCMod.Gui.QuickTypeEnter( PCMod.Gui.QuickTypeText:GetValue() )
		PCMod.Gui.HideQuickType()
	end

	local btn2 = vgui.Create( "DButton" )
	btn2:SetParent( window )
	btn2:SetPos( window:GetWide()-25, 5 )
	btn2:SetSize( 20, 20 )
	btn2:SetText( "X" )
	btn2.DoClick = function( self )
		PCMod.Gui.HideQuickType()
	end
	
	PCMod.EnableCapture( false )

	// Show the window
	window:SetVisible( true )
	window:MakePopup()
end
usermessage.Hook( "pcmod_quicktype", PCMod.Gui.ShowQuickType )

// ---------------------------------------------------------------------------------------------------------
// HideQuickType - Hides the Quick Type menu
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.HideQuickType()
	if (PCMod.Gui.QuickType) then
		PCMod.Gui.QuickType:Remove()
		PCMod.Gui.QuickType = nil
		PCMod.EnableCapture( true )
	end
end

// ---------------------------------------------------------------------------------------------------------
// QuickTypeEnter - Pass text to the focused device
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.QuickTypeEnter( text )
	if (!text) then text = "" end
	local devn = PCMod.SDraw.DevFocus
	if (!devn) then return end
	local dev_name = tostring( PCMod.Gui.CamLockID ) .. ":" .. devn
	if (!PCMod.SDraw.DevMap[ dev_name ]) then return end
	PCMod.SDraw.DevMap[ dev_name ]:Int_QuickType( text )
end

// ---------------------------------------------------------------------------------------------------------
// KBRegisterKeyPress - Parses a key press and passes it to server if needs be
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.KBRegisterKeyPress( key, txt )
	if (!PCMod.Gui.CamLocked) then return end
	local devn = PCMod.SDraw.DevFocus
	if (key == "shift") then
		PCMod.Gui.KBToggleShift()
		return
	end
	if (key == "caps") then
		PCMod.Gui.KBToggleShift(true)
		return
	end
	if (key == "ctrl") then
		PCMod.Gui.KBToggleCtrl()
		return
	end
	if ((!devn) || (devn == "")) then
		PCMod.Msg( "Nowhere to forward key press to!", true )
		return
	end
	local dev_name = tostring( PCMod.Gui.CamLockID ) .. ":" .. devn
	if (!PCMod.SDraw.DevMap[ dev_name ]) then
		PCMod.Msg( "Focus on unexistant device!", true )
		return
	end
	PCMod.SDraw.DevMap[ dev_name ]:Int_KeyPress( key, txt )
	// PCMod.SDraw.DevMap[ dev_name ]:KeyPress( key, txt )
	// RunConsoleCommand( "pc_keypress", key, PCMod.SDraw.KeyboardEntID, PCMod.SDraw.KB_Ctrl )
	if ((PCMod.SDraw.KB_Shift && !PCMod.SDraw.KB_Caps) || (PCMod.SDraw.KB_Shift && PCMod.SDraw.KB_UnShift)) then
		PCMod.Gui.KBToggleShift() -- We have pressed a key in shift mode, toggle it off
	end
end

// ---------------------------------------------------------------------------------------------------------
// KBToggleShift - Toggles shift on the keyboard
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.KBToggleShift(IsCaps)
	PCMod.Msg( "Toggling shift...", true )
	if (IsCaps) then
		if (PCMod.SDraw.KB_Caps) then
			PCMod.SDraw.KB_Caps = false
			PCMod.SDraw.KB_UnShift = false
			PCMod.SDraw.KB_Shift = false
		else
			PCMod.SDraw.KB_Caps = true
			PCMod.SDraw.KB_UnShift = false
			PCMod.SDraw.KB_Shift = true
		end
	else
		if (PCMod.SDraw.KB_Shift) then
			if (PCMod.SDraw.KB_Caps) then
				if (PCMod.SDraw.KB_UnShift) then
					PCMod.SDraw.KB_UnShift = false
				else
					PCMod.SDraw.KB_UnShift = true
				end
			else
				PCMod.SDraw.KB_Shift = false
			end
		else
			PCMod.SDraw.KB_Shift = true
		end
	end
end

// ---------------------------------------------------------------------------------------------------------
// KBToggleCtrl - Toggles ctrl on the keyboard
// ---------------------------------------------------------------------------------------------------------
function PCMod.Gui.KBToggleCtrl()
	PCMod.Msg( "Toggling ctrl...", true )
	if (PCMod.SDraw.KB_Ctrl) then
		PCMod.SDraw.KB_Ctrl = false
	else
		PCMod.SDraw.KB_Ctrl = true
	end
end

// ---------------------------------------------------------------------------------------------------------
// DERMA: Keyboard - OnScreen Keyboard
// ---------------------------------------------------------------------------------------------------------
local PANEL = {}
PANEL.Keys = {}
PANEL.KeySize = 32
PANEL.Spacing = 4
PANEL.Shift = false
function PANEL:Initialize()
	PCMod.Msg( "Creating keyboard keys...", true )
	
	// Row 0
	self:MakeKey( "1", 1, 1, 0.5, 0, nil, "!" )
	self:MakeKey( "2", 1, 1, 1.5, 0, nil, "\"" )
	self:MakeKey( "3", 1, 1, 2.5, 0, nil, "#" )
	self:MakeKey( "4", 1, 1, 3.5, 0, nil, "$" )
	self:MakeKey( "5", 1, 1, 4.5, 0, nil, "%" )
	self:MakeKey( "6", 1, 1, 5.5, 0, nil, "^" )
	self:MakeKey( "7", 1, 1, 6.5, 0, nil, "&" )
	self:MakeKey( "8", 1, 1, 7.5, 0, nil, "*" )
	self:MakeKey( "9", 1, 1, 8.5, 0, nil, "(" )
	self:MakeKey( "0", 1, 1, 9.5, 0, nil, ")" )
	self:MakeKey( "-", 1, 1, 10.5, 0, nil, "_" )
	self:MakeKey( "=", 1, 1, 11.5, 0, nil, "+" )
	self:MakeKey( "<--", 1.5, 1, 12.5, 0 )

	// Row 1
	self:MakeKey( "tab", 1, 1, 0, 1, "<->" )
	self:MakeKey( "q", 1, 1, 1, 1, nil, "Q" )
	self:MakeKey( "w", 1, 1, 2, 1, nil, "W" )
	self:MakeKey( "e", 1, 1, 3, 1, nil, "E" )
	self:MakeKey( "r", 1, 1, 4, 1, nil, "R" )
	self:MakeKey( "t", 1, 1, 5, 1, nil, "T" )
	self:MakeKey( "y", 1, 1, 6, 1, nil, "Y" )
	self:MakeKey( "u", 1, 1, 7, 1, nil, "U" )
	self:MakeKey( "i", 1, 1, 8, 1, nil, "I" )
	self:MakeKey( "o", 1, 1, 9, 1, nil, "O" )
	self:MakeKey( "p", 1, 1, 10, 1, nil, "P" )
	self:MakeKey( "[", 1, 1, 11, 1, nil, "{" )
	self:MakeKey( "]", 1, 1, 12, 1, nil, "}" )
	self:MakeKey( "#", 1, 1, 13, 1, nil, "~" )
	
	// Row 2
	self:MakeKey( "caps", 1.5, 1, 0, 2, "Caps", "[Caps]", true, true )
	self:MakeKey( "a", 1, 1, 1.5, 2, nil, "A" )
	self:MakeKey( "s", 1, 1, 2.5, 2, nil, "S" )
	self:MakeKey( "d", 1, 1, 3.5, 2, nil, "D" )
	self:MakeKey( "f", 1, 1, 4.5, 2, nil, "F" )
	self:MakeKey( "g", 1, 1, 5.5, 2, nil, "G" )
	self:MakeKey( "h", 1, 1, 6.5, 2, nil, "H" )
	self:MakeKey( "j", 1, 1, 7.5, 2, nil, "J" )
	self:MakeKey( "k", 1, 1, 8.5, 2, nil, "K" )
	self:MakeKey( "l", 1, 1, 9.5, 2, nil, "L" )
	self:MakeKey( ";", 1, 1, 10.5, 2, nil, ":" )
	self:MakeKey( "'", 1, 1, 11.5, 2, nil, "@" )
	self:MakeKey( "enter", 1.5, 1, 12.5, 2, "<-" )
	
	// Row 3
	self:MakeKey( "shift", 2, 1, 0, 3, "Shift", "[Shift]", true )
	self:MakeKey( "z", 1, 1, 2, 3, nil, "Z" )
	self:MakeKey( "x", 1, 1, 3, 3, nil, "X" )
	self:MakeKey( "c", 1, 1, 4, 3, nil, "C" )
	self:MakeKey( "v", 1, 1, 5, 3, nil, "V" )
	self:MakeKey( "b", 1, 1, 6, 3, nil, "B" )
	self:MakeKey( "n", 1, 1, 7, 3, nil, "N" )
	self:MakeKey( "m", 1, 1, 8, 3, nil, "M" )
	self:MakeKey( ",", 1, 1, 9, 3, nil, "<" )
	self:MakeKey( ".", 1, 1, 10, 3, nil, ">" )
	self:MakeKey( "/", 1, 1, 11, 3, nil, "?" )
	self:MakeKey( "shift", 2, 1, 12, 3, "Shift", "[Shift]", true )
	
	// Row 4
	self:MakeKey( "ctrl", 1, 1, 0, 4, "Ctrl" )
	self:MakeKey( "alt", 1, 1, 2, 4, "Alt" )
	self:MakeKey( "space", 5, 1, 4, 4, " " )
	self:MakeKey( "arrow_left", 1, 1, 9, 4, "<<" )
	self:MakeKey( "arrow_right", 1, 1, 10, 4, ">>" )
	self:MakeKey( "\\", 1, 1, 11, 4, nil, "|" )
	
	self:InvalidateLayout()
end
function PANEL:PerformLayout()
	local tp_x = 0
	local tp_y = 0
	for _, v in pairs( self.Keys ) do
		if (v.Y > tp_y) then tp_y = v.Y end
		if (v.X > tp_x) then tp_x = v.X end
		if ((v) && (v.Key)) then
			v.Key:SetPos( v.X, v.Y )
		end
	end
	self:SetSize( tp_x + self.KeySize + (2*self.Spacing), tp_y + self.KeySize + (2*self.Spacing) )
end
function PANEL:MakeKey( key, w, h, x, y, txt, txtonshift, shift, isCaps )
	local pn = vgui.Create( "DButton" )
	pn:SetParent( self )
	pn:SetText( "" )
	pn:SetTextColor( Color( 0, 0, 0, 255 ) )
	local xp = ((self.KeySize+self.Spacing)*x) + self.Spacing
	local yp = ((self.KeySize+self.Spacing)*y) + self.Spacing
	pn:SetSize( self.KeySize*w, self.KeySize*h )
	pn:SetPos( xp, yp )
	if (!txt) then txt = key end
	if (!txtonshift) then txtonshift = txt end
	pn.Text = txt
	pn.TextOnShift = txtonshift
	pn.IsShift = shift
	pn.IsCaps = isCaps
	pn.Paint = function( self )
		//local sid = PCMod.Res.Mats[ "gui/keyboard_key" ]
		//surface.SetTexture( sid )
		local col = Color( 255, 255, 255, 255 )
		if ((self.Depressed) || (PCMod.SDraw.KB_Shift && self.IsShift && (!PCMod.SDraw.KB_UnShift || self.IsCaps))) then
			if((self.IsCaps && PCMod.SDraw.KB_Caps) || !self.IsCaps) then
				col = Color( 100, 100, 255, 255 )
			end
		end
		//surface.SetDrawColor( col.r, col.g, col.b, col.a )
		//surface.DrawTexturedRect( 0, 0, self:GetWide(), self:GetTall() )
		draw.RoundedBox( 6, 0, 0, self:GetWide(), self:GetTall(), col )
		local t = self.Text
		if (PCMod.SDraw.KB_Shift && (!PCMod.SDraw.KB_UnShift || self.IsCaps)) then
			if((self.IsCaps && PCMod.SDraw.KB_Caps) || !self.IsCaps) then
				t = self.TextOnShift
			end
		end
		draw.SimpleText( t, "ScoreboardText", self:GetWide()/2, self:GetTall()/2, Color( 0, 0, 0, 255 ), 1, 1 )
	end
	pn.Key = key
	pn.DoClick = function( self )
		local t = self.Text
		if (PCMod.SDraw.KB_Shift && (!PCMod.SDraw.KB_UnShift || self.IsCaps)) then
			if((self.IsCaps && PCMod.SDraw.KB_Caps) || !self.IsCaps) then
				t = self.TextOnShift
			end
		end
		if (PCMod.Gui.KBRegisterKeyPress) then
			PCMod.Gui.KBRegisterKeyPress( self.Key, t )
		end
	end
	local tmp = {}
		tmp.Key = pn
		tmp.X = xp
		tmp.Y = yp
	self.Keys[ key ] = tmp
	return pn
end
function PANEL:Paint()
	draw.RoundedBox( 6, 0, 0, self:GetWide(), self:GetTall(), Color( 128, 128, 255, 255 ) )
end
vgui.Register( "Keyboard", PANEL, "PANEL" )