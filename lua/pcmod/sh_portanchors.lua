// ---------------------------------------------------------------------------------------------------------
// sh_portanchors.lua - hardcoded cable attachment points
//
// The wire tool normally attaches a rope where the player clicked. Models with
// visible connectors should instead use a fixed local-space point per port, so
// cables attach to the actual socket. Coordinates are entity-local Vectors
// (X forward, Y left, Z up), measured in-game with:
//   ent:WorldToLocal( trace.HitPos )
//
// Resolution order for a port:
//   1. An explicit class+model order (Orders), when the entity's port order
//      differs from the physical connector order.
//   2. The identity order when the model has exactly as many anchors as ports.
//   3. The measured connector nearest to the click, within SnapDistance.
//   4. The raw click point (models without anchors).
// ---------------------------------------------------------------------------------------------------------

PCMod = PCMod or {}
PCMod.PortAnchors = PCMod.PortAnchors or {}

PCMod.PortAnchors.SnapDistance = 4

local function A( x, y, z ) return { x, y, z } end

local function V( x, y, z )
	if (Vector) then return Vector( x, y, z ) end
	return { x = x, y = y, z = z }
end

// Coordinates are entity-local, so a model swap only needs a new list here.
PCMod.PortAnchors.Models = {
	// Wireless router: WAN + 4 LAN, in physical order.
	[ "models/pcmod/wrt54g.mdl" ] = {
		A( -4.965077, 2.111526, 1.963680 ),
		A( -4.964931, 1.085988, 1.996364 ),
		A( -4.964931, 0.740192, 1.996584 ),
		A( -4.964881, 0.075850, 1.998447 ),
		A( -4.965222, -1.960532, 1.930744 ),
	},
	// reciever01a: 14 connectors (7 columns, 2 rows).
	[ "models/props_lab/reciever01a.mdl" ] = {
		A( 7.041405, -1.304876, 1.573960 ),
		A( 7.041400, -1.362088, -1.006053 ),
		A( 7.041412, -0.020347, 1.396607 ),
		A( 7.041397, 0.088821, -1.033851 ),
		A( 7.041402, 1.566760, 1.447372 ),
		A( 7.041402, 1.596706, -1.000529 ),
		A( 7.041403, 3.083433, 1.423141 ),
		A( 7.041400, 3.049738, -0.934892 ),
		A( 7.041407, 4.679512, 1.387665 ),
		A( 7.041402, 4.627891, -0.718827 ),
		A( 7.041397, 6.183957, 1.274413 ),
		A( 7.041406, 6.249622, -0.942673 ),
		A( 7.041393, 7.578494, 1.366193 ),
		A( 7.041404, 7.607103, -1.061710 ),
	},
	// reciever01b: 12 connectors (4 columns, 3 rows).
	[ "models/props_lab/reciever01b.mdl" ] = {
		A( 6.133074, 0.053380, 1.984272 ),
		A( 6.133066, 1.291140, 2.002663 ),
		A( 6.133067, 2.470242, 1.984941 ),
		A( 6.133070, 3.845762, 2.014839 ),
		A( 6.133075, -0.075011, 0.367817 ),
		A( 6.133069, 1.397246, 0.299575 ),
		A( 6.133070, 2.680174, 0.326125 ),
		A( 6.133080, 3.994045, 0.318949 ),
		A( 6.133073, -0.334035, -1.508853 ),
		A( 6.133072, 1.228987, -1.523286 ),
		A( 6.133071, 2.574473, -1.559472 ),
		A( 6.133076, 3.949629, -1.482561 ),
	},
	// reciever01d: connectors plus the I/O device's single back port (last).
	[ "models/props_lab/reciever01d.mdl" ] = {
		A( 5.905417, 0.778751, -1.453126 ),
		A( 5.905410, 1.745954, -1.462399 ),
		A( 5.905408, 3.015019, -1.477060 ),
		A( 5.905412, 4.010360, -1.393382 ),
		A( 5.905415, 0.784698, -0.063663 ),
		A( 5.905405, 1.698112, -0.049786 ),
		A( 5.905410, 2.688199, -0.046861 ),
		A( 5.905406, 3.678791, -0.133491 ),
		A( -2.654403, -0.101303, -1.106946 ),
	},
	// Laptop: two Ethernet, three USB, two audio, one VGA.
	[ "models/pcmod/eeepc.mdl" ] = {
		A( -7.932076, -12.207993, 0.823788 ),
		A( -6.562766, -12.205594, 0.842386 ),
		A( -3.748228, -12.200676, 0.960748 ),
		A( -3.479539, 12.188160, 1.194810 ),
		A( -1.573181, 12.191455, 1.143570 ),
		A( 3.972728, -12.187094, 1.458587 ),
		A( 5.636311, -12.184182, 1.522816 ),
		A( -8.106808, 12.180088, 1.057196 ),
	},
	// Monitors.
	[ "models/props_lab/monitor01a.mdl" ] = {
		A( -13.048763, -5.394324, 0.039976 ),
	},
	[ "models/props/cs_office/computer_monitor.mdl" ] = {
		A( 0.463554, -3.238800, 14.860355 ),
	},
	// Speaker and audio amplifier.
	[ "models/props_junk/metalbucket01a.mdl" ] = {
		A( -0.020303, 10.159960, 2.993814 ),
	},
	[ "models/props_lab/tpplug.mdl" ] = {
		A( 12.115396, -0.188299, -0.036500 ),
	},
	// Printers.
	[ "models/props_lab/plotter.mdl" ] = {
		A( 22.686144, 4.993898, 36.332069 ),
	},
	[ "models/pcmod/kopierer.mdl" ] = {
		A( -12.492884, 16.031263, 6.047641 ),
	},
	// Keyboards.
	[ "models/props_c17/computer01_keyboard.mdl" ] = {
		A( -3.217418, -2.120340, 2.403453 ),
	},
	[ "models/props/cs_office/computer_keyboard.mdl" ] = {
		A( -5.508957, -0.335751, 0.564931 ),
	},
	// Tower: VGA, PS/2, eth 1, eth 2, USB, USB, mini jack.
	[ "models/props_lab/harddrive02.mdl" ] = {
		A( -9.958773, -1.485112, -4.195036 ),
		A( -9.958774, -2.514746, -0.811839 ),
		A( -9.958769, -0.930452, -5.002792 ),
		A( -9.958768, 0.245026, -5.812474 ),
		A( -9.958767, -1.156871, -5.805075 ),
		A( -9.958742, 0.141477, -8.425164 ),
		A( -9.958731, -1.694248, -8.392694 ),
	},
	// Office tower: PS/2, USB 1, USB 2, VGA, eth 1, eth 2, mini jack.
	[ "models/props/cs_office/computer_case.mdl" ] = {
		A( -12.994721, 3.473204, 17.021378 ),
		A( -12.994724, 3.536302, 16.114511 ),
		A( -12.994700, 3.159037, 16.032677 ),
		A( -12.994639, 1.821546, 8.408161 ),
		A( -12.994677, 1.798737, 4.010719 ),
		A( -12.994631, 1.820751, 6.194795 ),
		A( -12.994639, 0.470484, 5.193108 ),
	},
}

// Explicit port -> anchor index maps, keyed by "class|model". Only needed when
// the entity's logical port order differs from the connector layout.
PCMod.PortAnchors.Orders = {
	[ "pcmod_tower|models/props_lab/harddrive02.mdl" ] = { 1, 2, 3, 4, 5, 6, 7 },
	[ "pcmod_tower|models/props/cs_office/computer_case.mdl" ] = { 4, 1, 5, 6, 2, 3, 7 },
	[ "pcmod_laptop|models/pcmod/eeepc.mdl" ] = { 1, 3, 6 },
	[ "pcmod_iodevice|models/props_lab/reciever01d.mdl" ] = { 9 },
}

local function ModelKey( ent )
	if ((!ent) || (!ent.GetModel)) then return nil end
	local model = string.lower( ent:GetModel() or "" )
	if (model == "") then return nil end
	if (!string.find( model, "^models/" )) then model = "models/" .. model end
	return model
end

function PCMod.PortAnchors.List( ent )
	local model = ModelKey( ent )
	return model && PCMod.PortAnchors.Models[ model ] or nil
end

// Anchor for port `index` using only an explicit order or a 1:1 model.
function PCMod.PortAnchors.Get( ent, index )
	local list = PCMod.PortAnchors.List( ent )
	if ((!list) || (!index)) then return nil end
	local model = ModelKey( ent )
	local cls = (ent.GetClass && ent:GetClass()) or ""
	local order = PCMod.PortAnchors.Orders[ cls .. "|" .. model ]
	local pick = order && order[ index ]
	if ((!pick) && (#list == #(ent.Ports && ent:Ports() or {}))) then pick = index end
	local a = pick && list[ pick ]
	if ((!a) || (!a[ 1 ])) then return nil end
	return V( a[ 1 ], a[ 2 ], a[ 3 ] )
end

// Measured connector nearest to a local-space point, or nil when none is
// within `maxDist`. A single-anchor model always snaps, so clicking anywhere
// on e.g. a monitor still attaches to its VGA socket.
function PCMod.PortAnchors.Snap( ent, lpos, maxDist )
	local list = PCMod.PortAnchors.List( ent )
	if ((!list) || (!lpos) || (#list == 0)) then return nil end
	if (#list == 1) then return V( list[ 1 ][ 1 ], list[ 1 ][ 2 ], list[ 1 ][ 3 ] ) end
	maxDist = maxDist or PCMod.PortAnchors.SnapDistance
	local limit = maxDist * maxDist
	local best
	local bestd = limit
	for _, a in ipairs( list ) do
		local dx = a[ 1 ] - (lpos.x or 0)
		local dy = a[ 2 ] - (lpos.y or 0)
		local dz = a[ 3 ] - (lpos.z or 0)
		local d = (dx * dx) + (dy * dy) + (dz * dz)
		if (d <= bestd) then best = a bestd = d end
	end
	if (!best) then return nil end
	return V( best[ 1 ], best[ 2 ], best[ 3 ] )
end

// Best attachment point for port `index`: fixed when the port order is known,
// otherwise the nearest measured connector to the click.
function PCMod.PortAnchors.Resolve( ent, index, lpos )
	local a = PCMod.PortAnchors.Get( ent, index )
	if (a) then return a end
	local s = PCMod.PortAnchors.Snap( ent, lpos )
	if (s) then return s end
	return lpos
end
