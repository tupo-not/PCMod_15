
SWEP.PrintName = "Install Disk"

SWEP.Author = "[GU]thomasfn"
SWEP.Contact = "Don't."
SWEP.Category = "PCMod"
SWEP.Purpose = "To install programs onto a PC."
SWEP.Instructions = "Left click a PC to install program onto. Right click to change program."

if (CLIENT) then
	
	SWEP.Slot = 0
	SWEP.SlotPos = 1
	
	SWEP.DrawAmmo = false
	// DrawCrosshair must be true so that WEAPON:DoDrawCrosshair is called and
	// draws our custom minimalistic crosshair instead of the default one.
	// See https://wiki.facepunch.com/gmod/WEAPON:DoDrawCrosshair
	SWEP.DrawCrosshair = true

	// No hands: the CD model is used directly as the viewmodel and has no hand
	// bones; do not let the gamemode draw the separate gmod_hands entity.
	// See https://wiki.facepunch.com/gmod/Using_Viewmodel_Hands
	SWEP.UseHands = false

	// Cached HUD fonts - created ONCE at load, never inside a render hook.
	// See https://wiki.facepunch.com/gmod/surface.CreateFont
	surface.CreateFont( "PCModInstallTitle", { font = "Arial", size = 18, weight = 700, antialias = true } )
	surface.CreateFont( "PCModInstallText", { font = "Arial", size = 15, weight = 500, antialias = true } )
	surface.CreateFont( "PCModInstallSmall", { font = "Arial", size = 12, weight = 400, antialias = true } )

end

if (SERVER) then

	AddCSLuaFile( "shared.lua" )

	SWEP.Weight = 5
	
	SWEP.AutoSwitchTo = true
	SWEP.AutoSwitchFrom = false

end

SWEP.Spawnable = true
SWEP.AdminSpawnable = true

// The CD model itself is the viewmodel: no C4 mesh, no hands.
SWEP.ViewModel = "models/pcmod/pcmodinstall.mdl"
SWEP.WorldModel = "models/pcmod/pcmodinstall.mdl"

util.PrecacheModel( SWEP.ViewModel )
util.PrecacheModel( SWEP.WorldModel )

// One-handed hold pose for the player model; the CD viewmodel has no
// animations of its own, so the pose does not need viewmodel sequences.
// See https://wiki.facepunch.com/gmod/Hold_Types
SWEP.HoldType = "slam"

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Primary.SoundEffect = ""

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"
SWEP.Secondary.SoundEffect = ""

if (SWEP.Primary.SoundEffect != "") then SWEP.Primary.SoundEffect = Sound( SWEP.Primary.SoundEffect ) end
if (SWEP.Secondary.SoundEffect != "") then SWEP.Secondary.SoundEffect = Sound( SWEP.Secondary.SoundEffect ) end

SWEP.Programs = {}
SWEP.ProgCnt = 0
SWEP.SelProg = 0
SWEP.PackName = ""

SWEP.LabelPos = 0
SWEP.ZipRat = 0.25

function SWEP:Initialize()
	if (SERVER) then
		self:SetWeaponHoldType( self.HoldType )
	end
end

function SWEP:Reset()
	self.Programs = {}
	self.ProgCnt = 0
	self:SetNWInt( "progs", 0 )
	self:SetNWInt( "selprog", 0 )
	self:SetPackName( "Install Disk" )
end

function SWEP:AddProgram( progname, nicename, osid, icon )
	if (CLIENT) then return end
	local id = self.ProgCnt + 1
	self.ProgCnt = id
	self:SetNWInt( "progs", id )
	self:SetNWString( "prog_" .. tostring( id ), nicename )
	self:SetNWString( "prog_" .. tostring( id ) .. "_os", osid )
	self:SetNWString( "prog_" .. tostring( id ) .. "_icon", icon or "" ) // optional, display only
	self.Programs[ id ] = progname
	if (self.SelProg == 0) then self.SelProg = 1 end
	self:SetNWInt( "selprog", self.SelProg )
end

function SWEP:SetPackName( name )
	self:SetNWString( "packname", name )
end

// Populate the disk with the default program list when it is spawned directly
// from the spawnmenu (the old Swep tool did this manually after giving it).
function SWEP:EnsureDefaultPrograms()
	if (!SERVER) then return end
	if ((self.ProgCnt) && (self.ProgCnt > 0)) then return end
	self:Reset()
	self:SetPackName( "Install Disk" )
	local list = PCMod.Cfg && PCMod.Cfg.FullProgramList
	if ((!list) || (list == "")) then return end
	local progs = string.Explode( ",", list )
	if (!progs) then return end
	for _, v in pairs( progs ) do
		local prog = PCMod.Progs && PCMod.Progs[ v ]
		if (prog) then
			self:AddProgram( v, prog.Title, prog.OS, prog.Icon )
		end
	end
end

// SyncClientState - reads the server-synced NW fields into the client display
// state. Called from Think() only (the original, proven mechanism - GMod calls
// WEAPON:Think clientside every tick while the weapon is active).
local function SyncClientState( self )
	self.ProgCnt = self:GetNWInt( "progs" )
	if (self.ProgCnt == 0) then
		self.SelProg = 0
		self.Programs = {}
		return
	end
	self.SelProg = self:GetNWInt( "selprog" )
	// Rebuild the table from scratch so stale entries disappear whenever the
	// server-side count shrinks (but stays > 0).
	local progs = {}
	for cnt = 1, self.ProgCnt do
		local id = "prog_" .. tostring( cnt )
		progs[ cnt ] = { self:GetNWString( id ), self:GetNWString( id .. "_os" ), self:GetNWString( id .. "_icon" ) }
	end
	self.Programs = progs
	if ((self.SelProg < 1) || (self.SelProg > self.ProgCnt)) then self.SelProg = 1 end
	self.PackName = self:GetNWString( "packname" )
end

function SWEP:Think()
	if (SERVER) then return end
	SyncClientState( self )
	if (self.ProgCnt == 0) then return end
	if (self.LabelPos != self.SelProg) then
		self.LabelPos = math.Mid( self.LabelPos, self.SelProg, self.ZipRat )
		if ((self.LabelPos > (self.SelProg-0.1)) && (self.LabelPos < (self.SelProg+0.1))) then self.LabelPos = self.SelProg end
	end
end

function SWEP:Deploy()
	if (SERVER) then self:EnsureDefaultPrograms() end
	return true
end

function SWEP:Holster()
	return true
end

function SWEP:CalcViewModelView( vm, oldPos, oldAng, pos, ang )
	// pcmodinstall.mdl geometry: the disc is thin along local X and wide in Y/Z,
	// so its face normal is local +X. Rotate around the camera's own axes so the
	// disc keeps a fixed screen-space orientation. Adding the offsets to the
	// Euler angles directly made the disc roll when the camera pitched.
	local viewAng = Angle( ang.p, ang.y, ang.r )
	viewAng:RotateAroundAxis( ang:Right(), 100 )
	viewAng:RotateAroundAxis( ang:Up(), -18 )
	viewAng:RotateAroundAxis( ang:Forward(), -10 )
	return pos + ang:Forward() * 18 + ang:Right() * 5 + ang:Up() * -4, viewAng
end

function SWEP:PrimaryAttack()
	local tr = self.Owner:GetEyeTrace()
	if ((tr.HitPos - self.Owner:GetPos()):Length() > 128) then
		if (CLIENT) then PCMod.Gui.Notify( "Too far", true ) end
		return
	end
	local ent = tr.Entity
	if ((tr.HitWorld) || (!ent) || (!ent:IsValid())) then
		if (CLIENT) then PCMod.Gui.Notify( "Aim at a PC", true ) end
		return
	end
	if ((!ent.IsPCMod) || ((ent.Class != "pcmod_tower") && (ent.Class != "pcmod_laptop"))) then
		if (CLIENT) then PCMod.Gui.Notify( "Aim at a PC", true ) end
		return
	end
	if (CLIENT) then return true end -- Client stops here; the server decides
	local prog = self.Programs[ self.SelProg ]
	if ((!prog) || (prog == "")) then
		self.Owner:SendLua( 'PCMod.Gui.Notify( "No program selected", true );' )
		return
	end
	// All install restrictions are enforced authoritatively on the server inside
	// ENT:InstallProgram -> OS:InstallProgram (device/OS compatibility, OS
	// presence, duplicates, validity). Here we only map its real result to the
	// notification text: false = the target PC has no OS installed.
	local result = ent:InstallProgram( prog )
	if (result == false) then
		self.Owner:SendLua( 'PCMod.Gui.Notify( "No operating system", true );' )
		return
	end
	if (type(result) == "string") then
		local msg = "Installation failed"
		if (string.find( result, "already" )) then msg = "Already installed"
		elseif (string.find( result, "invalid" )) then msg = "Invalid program"
		elseif (string.find( result, "operating system" )) then msg = "Incompatible device"
		elseif (string.find( result, "denied" )) then msg = "No operating system"
		end
		self.Owner:SendLua( string.format( 'PCMod.Gui.Notify( "%s", true );', msg ) )
		return
	end
	self.Owner:SendLua( 'PCMod.Gui.Notify( "Installed", false );' )
	local snd = self.Primary.SoundEffect
	if ((snd) && (snd != "")) then self:EmitSound( snd ) end
end

function SWEP:SecondaryAttack()
	if (CLIENT) then return end
	
	self.SelProg = self.SelProg + 1
	if ((self.SelProg < 1) || (self.SelProg > self.ProgCnt)) then self.SelProg = 1 end
	self:SetNWInt( "selprog", self.SelProg )
	local snd = self.Secondary.SoundEffect
	if ((snd) && (snd != "")) then self:EmitSound( snd ) end
end

function SWEP:DoDrawCrosshair( x, y )
	if (!CLIENT) then return true end
	// Minimalistic PCMod-style crosshair: 4 teal corner brackets + a small light
	// center dot, ~16 px total, thin lines, dark outline for readability on light
	// surfaces. Pixel-fixed size, so it looks the same at any resolution.
	// The old cross bars were removed from DrawHUD, and returning true here
	// suppresses the default engine crosshair.
	// See https://wiki.facepunch.com/gmod/WEAPON:DoDrawCrosshair
	local s = 8 // half-size: brackets sit at +-8 px from the center
	local a = 4 // bracket arm length
	local teal = Color( 0, 255, 220, 255 )
	local dark = Color( 0, 0, 0, 180 )
	local dot = Color( 240, 255, 255, 255 )
	local function brackets( ox, oy, col )
		surface.SetDrawColor( col )
		for _, dx in ipairs( { -1, 1 } ) do
			for _, dy in ipairs( { -1, 1 } ) do
				local cx = x + ox + dx * s
				local cy = y + oy + dy * s
				surface.DrawLine( cx, cy, cx - dx * a, cy ) // horizontal arm
				surface.DrawLine( cx, cy, cx, cy - dy * a ) // vertical arm
			end
		end
	end
	brackets( 1, 1, dark ) // outline pass, offset by 1 px
	brackets( 0, 0, teal )
	surface.SetDrawColor( dark )
	surface.DrawRect( x - 2, y - 2, 4, 4 ) // dot outline
	surface.SetDrawColor( dot )
	surface.DrawRect( x - 1, y - 1, 2, 2 ) // center dot
	return true
end

// ---------------------------------------------------------------------------------------------------------
// CalcPanelLayout - pure layout math for the program-selection panel.
// Returns panel rect + row metrics; unit-tested by mock_diskui.
// All coordinates are absolute screen pixels (WEAPON:DrawHUD draws in screen
// space - no panel-local offsets, no matrices).
// ---------------------------------------------------------------------------------------------------------
// NOTE: a file-local, so runtime code (DrawHUD) never touches the global SWEP
// (which only exists while the weapon class is being registered at load).
local function CalcPanelLayout( progCount, scrW, scrH )
	local rowH = 24
	local headerH = 50
	local footerH = 28
	local pad = 12
	local maxRows = math.max( 1, math.floor( (scrH * 0.55 - headerH - footerH - pad * 2) / rowH ) )
	local rows = math.min( math.max( progCount, 1 ), maxRows )
	local w = math.min( 340, math.max( 220, scrW * 0.18 ) )
	local h = headerH + rows * rowH + footerH + pad * 2
	local x = scrW - w - 24
	local y = (scrH - h) / 2
	return x, y, w, h, rowH, headerH, footerH, pad, maxRows
end
SWEP.CalcPanelLayout = CalcPanelLayout // exposed on the class for tests only

// FitText - truncate with "..." so the text never exceeds maxW pixels.
local function FitText( txt, font, maxW )
	surface.SetFont( font )
	if (surface.GetTextSize( txt ) <= maxW) then return txt end
	local base = txt
	while (#base > 0) do
		base = string.sub( base, 1, #base - 1 )
		if (surface.GetTextSize( base .. "..." ) <= maxW) then return base .. "..." end
	end
	return "..."
end

function SWEP:DrawHUD()
	if (SERVER) then return end

	// Appear animation (time-based, FPS-independent): DrawHUD stops while the
	// weapon is holstered, so a gap in drawing means a re-equip.
	if ((CurTime() - (self.LastDraw or 0)) > 0.1) then self.AppearTime = CurTime() end
	self.LastDraw = CurTime()
	local ap = math.Clamp( (CurTime() - (self.AppearTime or CurTime())) / 0.15, 0, 1 )
	local slide = (1 - ap) * 24 // px, panel slides in from the right

	local scrW = ScrW()
	local scrH = ScrH()
	local cnt = #self.Programs
	local px, py, pw, ph, rowH, headerH, footerH, pad, maxRows = CalcPanelLayout( cnt, scrW, scrH )

	// keep the selected row inside the visible window (scroll offset)
	local rows = math.min( math.max( cnt, 1 ), maxRows )
	local off = self.ScrollOff or 0
	if (cnt > 0) then
		if (self.SelProg < off + 1) then off = self.SelProg - 1 end
		if (self.SelProg > off + rows) then off = self.SelProg - rows end
	end
	off = math.Clamp( off, 0, math.max( 0, cnt - rows ) )
	self.ScrollOff = off

	// PCMod 1.5 palette: graphite panel, teal accents
	local bg = Color( 24, 28, 32, 210 * ap )
	local accent = Color( 102, 216, 207, 255 * ap )
	local hiBg = Color( 102, 216, 207, 42 * ap )
	local hiTxt = Color( 210, 255, 248, 255 * ap )
	local txt = Color( 235, 240, 245, 255 * ap )
	local dim = Color( 150, 160, 170, 255 * ap )

	local x = px + slide
	local y = py

	// panel background
	draw.RoundedBox( 10, x, y, pw, ph, bg )

	// header: disk icon + "Install Disk" + "Program selector" + category chip
	local hx = x + pad
	local hy = y + pad
	surface.SetTexture( surface.GetTextureID( "gui/icons/ico_harddrive" ) )
	surface.SetDrawColor( 255, 255, 255, 255 * ap )
	surface.DrawTexturedRect( hx, hy + 4, 20, 20 )
	draw.SimpleText( "Install Disk", "PCModInstallTitle", hx + 28, hy + 2, txt, 0, 3 )
	draw.SimpleText( "Program selector", "PCModInstallSmall", hx + 28, hy + 27, dim, 0, 3 )
	// category chip from the real per-program OS id of the selected program
	local sel = self.Programs[ self.SelProg ]
	local osid = (sel && sel[2]) or ""
	local cat = (osid == "server") && "Server" || "Personal"
	surface.SetFont( "PCModInstallSmall" )
	local cw, chh = surface.GetTextSize( cat )
	local chipX = x + pw - pad - cw - 12
	draw.RoundedBox( 6, chipX, hy + 4, cw + 12, chh + 6, Color( 102, 216, 207, 36 * ap ) )
	draw.SimpleText( cat, "PCModInstallSmall", chipX + 6, hy + 7, accent, 0, 3 )

	// program list
	local listY = y + pad + headerH
	// highlight follows the eased LabelPos (1-based), minus scroll offset
	local labelPos = self.LabelPos
	if (labelPos != 0) then
		local hyy = listY + (labelPos - 1 - off) * rowH
		if ((labelPos - off >= 1) && (labelPos - off <= rows)) then
			draw.RoundedBox( 4, x + pad, hyy, pw - pad * 2, rowH - 4, hiBg )
			surface.SetDrawColor( accent.r, accent.g, accent.b, accent.a )
			surface.DrawRect( x + pad, hyy, 3, rowH - 4 ) // thin teal indicator bar
		end
	end
	// Iterate the real table like the original UI did (pairs over
	// self.Programs), drawing only the visible window [off+1, off+rows].
	for k, prog in pairs( self.Programs ) do
		if ((k > off) && (k <= off + rows) && (prog)) then
			local ry = listY + (k - off - 1) * rowH
			// row icon (real program icon from PCMod data, fallback app icon)
			local icon = prog[3]
			local ipath = "gui/icons/ico_" .. tostring( icon ) .. ".vmt"
			if ((!icon) || (icon == "") || (!file.Exists( "materials/" .. ipath, "GAME" ))) then ipath = "gui/icons/ico_app.vmt" end
			surface.SetTexture( surface.GetTextureID( string.gsub( ipath, "%.vmt$", "" ) ) )
			surface.SetDrawColor( 255, 255, 255, 255 * ap )
			surface.DrawTexturedRect( x + pad + 4, ry + (rowH - 16) / 2, 16, 16 )
			// row text (truncated so it never leaves the panel)
			local name = FitText( prog[1], "PCModInstallText", pw - pad * 2 - 26 )
			local isSel = (k == self.SelProg)
			draw.SimpleText( name, "PCModInstallText", x + pad + 26, ry + rowH / 2, isSel && hiTxt || txt, 0, 1 )
		end
	end
	// scroll hints when the list is longer than the visible window
	if (off > 0) then draw.SimpleText( "^", "PCModInstallSmall", x + pw - pad - 8, listY - 12, dim, 0, 3 ) end
	if (off + rows < cnt) then draw.SimpleText( "v", "PCModInstallSmall", x + pw - pad - 8, listY + rows * rowH, dim, 0, 3 ) end

	// footer: controls + selection counter
	local fy = y + ph - pad - footerH
	surface.SetDrawColor( 255, 255, 255, 14 * ap )
	surface.DrawLine( x + pad, fy - 4, x + pw - pad, fy - 4 )
	draw.SimpleText( "LMB - Install    RMB - Next", "PCModInstallSmall", x + pad, fy + footerH / 2, dim, 0, 1 )
	if (cnt > 0) then
		draw.SimpleText( self.SelProg .. "/" .. cnt, "PCModInstallSmall", x + pw - pad, fy + footerH / 2, accent, 2, 1 )
	end
end

function SWEP:GetShootTrace( dist )
	local trace = {}
	trace.startpos = self.Owner:GetShootPos()
	trace.endpos = trace.startpos + (self.Owner:GetAimVector() * dist)
	trace.filter = self.Owner
	return util.TraceLine( trace )
end