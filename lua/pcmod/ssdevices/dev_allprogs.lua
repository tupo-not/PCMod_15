
// PCMod ScreenSpace Device | All Programs Menu \\

DEV.Name = "menu_allprogs"

DEV.LastTick = 0
DEV.LastFrame = 0

DEV.ShortcutHeight = 0.06

DEV.Progs = {}

DEV.Th = "basic"
local entoku
local tablooku
local bunubelirle
net.Receive( 'programyolla', function()
// Round 19 (AUDIT2 A-06): validate before use - net.ReadEntity can return a
// NULL entity and net.ReadTable an arbitrary value.
local ent = net.ReadEntity()
local tbl = net.ReadTable()
if (!IsValid( ent ) || !istable( tbl )) then return end
ent.Programlar = tbl
entoku = ent
tablooku = tbl
end)
 

function DEV:Initialize( x, y, w, h )
	// Round 19 (AUDIT2 A-03/A-08): debug print removed; the program list may
	// not have arrived yet (NULL entoku / non-table data) - fall back to an
	// empty list instead of crashing the device.
	local progs
	if (IsValid( self.Entity ) && self.Entity:GetClass() == "pcmod_laptop") then
	progs = self.Entity.Programlar
	elseif (IsValid( entoku )) then
	progs = entoku.Programlar
	end
	if (!istable( progs )) then progs = {} end
	bunubelirle = progs
	
	for k, v in pairs( bunubelirle ) do
		local ypos = y + ((k-1) * h * self.ShortcutHeight )
		self:CreateButton2( self.Th, "btn_p_" .. tostring( k ), x, ypos, w, self.ShortcutHeight*h, v[2], v[1] )
	end
	
	
	self.WinX = x
	self.WinY = y
	self.WinW = w
	self.WinH = h
end

function DEV:Paint( x, y, w, h )
	// PCMOD15 E5: same design language as the start menu - the
	// panel is theme-hookable ("startmenu"); themes that do not
	// handle the id fall through to the original painting.
	if (!PCMod.Gui.ThemeDraw( self.Th, "startmenu", x, y, w, h )) then
		local c_sm = PCMod.Gui.GetThemeColour( self.Th, "StartMenuBG" )
		local c_bor = PCMod.Gui.GetThemeColour( self.Th, "Border" )
		surface.SetDrawColor( c_sm.r, c_sm.g, c_sm.b, c_sm.a )
		surface.DrawRect( x, y, w, h )
		surface.DrawOutline( x, y, w, h, c_bor )
	end
	self:Draw()
end

function DEV:ButtonClick( btn )
	local x, y, w, h = self.win_x, self.win_y, self.win_w, self.win_h
	for k, v in pairs( bunubelirle ) do
		local bname = "btn_p_" .. tostring( k )
		if (btn == bname) then
			self:SubmitCommand( "os_command", "startmenu_close" )
			// Round 35: the program command is stored as ONE string
			// ("sys_openprog mycomputer", see programs/base.lua OnInstall).
			// Since Round 28 (M-53) the server takes an os_command from a
			// VECTOR and does not re-split the first value, while
			// RunConsoleCommand delivers a value with a space as a single
			// token - so the server saw the whole string as the command
			// name, matched no OS:RunCommand branch and silently did
			// nothing (no Lua error, the item just did not start).
			// Split the command here into separate arguments - that is the
			// format OS:RunCommand( com, args ) expects, and it works no
			// matter how the engine tokenises the console line.
			local coms = {}
			for _, w in ipairs( string.Explode( " ", v[3] or "" ) ) do
				if (w != "") then table.insert( coms, w ) end
			end
			if (#coms > 0) then
				self:SubmitCommand( "os_command", unpack( coms ) )
			end
		end
	end
end

function DEV:DoClick( x, y )
	self:ProcessClick( x, y )
end

function DEV:Tick()
	self.LastTick = CurTime()
	self.LastFrame = PCMod.SDraw.CFrame
end

function DEV:Kill()
	
end

function DEV:KeyPress( key, txt )
	//self:KeyPressTextboxes( key, txt )
end