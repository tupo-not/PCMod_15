
SWEP.PrintName = "Install Disk"

SWEP.Author = "[GU]thomasfn"
SWEP.Contact = "Don't."
SWEP.Category = "PCMod 2"
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

end

if (SERVER) then

	AddCSLuaFile( "shared.lua" )

	SWEP.Weight = 5
	
	SWEP.AutoSwitchTo = true
	SWEP.AutoSwitchFrom = false

end

SWEP.Spawnable = false
SWEP.AdminSpawnable = false

// The CD model itself is the viewmodel: no C4 mesh, no hands, and no need to
// touch the shared viewmodel entity of other weapons.
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

function SWEP:AddProgram( progname, nicename, osid )
	if (CLIENT) then return end
	local id = self.ProgCnt + 1
	self.ProgCnt = id
	self:SetNWInt( "progs", id )
	self:SetNWString( "prog_" .. tostring( id ), nicename )
	self:SetNWString( "prog_" .. tostring( id ) .. "_os", osid )
	self.Programs[ id ] = progname
	if (self.SelProg == 0) then self.SelProg = 1 end
	self:SetNWInt( "selprog", self.SelProg )
end

function SWEP:SetPackName( name )
	self:SetNWString( "packname", name )
end

function SWEP:Think()
	if (SERVER) then return end
	self.ProgCnt = self:GetNWInt( "progs" )
	if (self.ProgCnt == 0) then
		self.SelProg = 0
		return
	end
	self.SelProg = self:GetNWInt( "selprog" )
	local cnt
	for cnt=1, self.ProgCnt do
		local id = "prog_" .. tostring( cnt )
		self.Programs[ cnt ] = { self:GetNWString( id ), self:GetNWString( id .. "_os" ) }
	end
	if ((self.SelProg < 1) || (self.SelProg > self.ProgCnt)) then self.SelProg = 1 end
	self.PackName = self:GetNWString( "packname" )
	if (self.LabelPos != self.SelProg) then
		self.LabelPos = math.Mid( self.LabelPos, self.SelProg, self.ZipRat )
		if ((self.LabelPos > (self.SelProg-0.1)) && (self.LabelPos < (self.SelProg+0.1))) then self.LabelPos = self.SelProg end
	end
end

function SWEP:Holster()
	return true
end

function SWEP:CalcViewModelView( vm, oldPos, oldAng, pos, ang )
	// pcmodinstall.mdl geometry (parsed from the MDL hull): the disc is thin
	// along local X (0.47) and wide in Y/Z (7.77 x 8.77), so the disc lies in
	// its local YZ plane and the face normal is local +X, diameter ~8.8 units.
	//
	// Orientation: adding pitch -90 to the view angles maps local +X to world
	// +Z, i.e. the face points straight up; the current offset Angle(-100,-18,-10)
	// tilts the face toward the player and adds slight yaw/roll. If the labelled
	// side turns out to face down, mirror the pitch sign (+90/+100).
	//
	// Position/size: at the default 62 viewmodel FOV, ~18 units in front of the
	// camera puts the ~8.8-unit disc at roughly 20-25% of screen width (16:9).
	// Right*5 + Up*-4 moves it to the lower-right corner, keeping the crosshair
	// free. No SetModelScale on the shared viewmodel entity is used.
	// Note: this hook only works if GM:CalcViewModelView is not overridden.
	// See https://wiki.facepunch.com/gmod/WEAPON:CalcViewModelView
	return pos + ang:Forward() * 18 + ang:Right() * 5 + ang:Up() * -4,
		ang + Angle( -100, -18, -10 )
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

function SWEP:DrawHUD()
	if (SERVER) then return end
	
	local w = ScrW()
	local h = ScrH()
	
	// Draw the select menu
	if (#self.Programs > 0) then
		local col = Color( 100, 100, 100, 255 )
		surface.SetFont( "ScoreboardText" )
		local tw, th = surface.GetTextSize( self.PackName .. " " )
		local mh = th + (th * #self.Programs)
		local my = (h*0.5)-(mh*0.5)
		local mw = w*0.2
		local mx = w - mw
		draw.RoundedBox( 6, mx, my, mw, mh, col )
		draw.SimpleText( self.PackName, "ScoreboardText", mx+(mw*0.5), my+(th*0.5), Color( 255, 255, 255, 255 ), 1, 1 )
		surface.SetDrawColor( 0, 0, 0, 255 )
		surface.DrawLine( mx, (h*0.5)-(mh*0.5)+th, w, (h*0.5)-(mh*0.5)+th )
		local ypos = self.LabelPos
		if (ypos != 0) then
			local ly = my+(th*ypos)
			draw.RoundedBox( 4, mx, ly, mw, th, Color( 255, 255, 255, 128 ) )
		end
		for k, v in pairs( self.Programs ) do
			draw.SimpleText( v[1], "ScoreboardText", mx+(mw*0.5), (h*0.5)-(mh*0.5)+(th*(k+0.5)), Color( 0, 0, 0, 255 ), 1, 1 )
		end
		
		// Draw the selected OS
		local ypos = my + mh + (h*0.02)
		draw.RoundedBox( 6, mx, ypos, mw, th, col )
		draw.SimpleText( self.Programs[ self.SelProg ][ 2 ], "ScoreboardText", mx+(mw*0.5), ypos+(th*0.5), Color( 255, 255, 255, 255 ), 1, 1 )
	end
end

function SWEP:GetShootTrace( dist )
	local trace = {}
	trace.startpos = self.Owner:GetShootPos()
	trace.endpos = trace.startpos + (self.Owner:GetAimVector() * dist)
	trace.filter = self.Owner
	return util.TraceLine( trace )
end