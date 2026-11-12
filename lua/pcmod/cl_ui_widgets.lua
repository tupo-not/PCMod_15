// ---------------------------------------------------------------------------------------------------------
// cl_ui_widgets.lua - Client-Side
// One widget contract for the three control stores (textboxes, listboxes and
// screen-space elements). The device base keeps the stores, but drawing and
// hit-testing run through this registry.
// ---------------------------------------------------------------------------------------------------------

PCMod.UI = PCMod.UI or {}
PCMod.UI.Widgets = PCMod.UI.Widgets or {}
local W = PCMod.UI.Widgets

W.Order = { "textbox", "listbox", "element" }
W.Kinds = W.Kinds or {}

function W.Register( kind, def )
	W.Kinds[ kind ] = def
end

function W.Get( kind )
	return W.Kinds[ kind ]
end

function W.NewSet()
	local set = {}
	for _, kind in ipairs( W.Order ) do set[ kind ] = {} end
	return set
end

function W.Add( set, kind, ctrl )
	if (!set[ kind ]) then set[ kind ] = {} end
	table.insert( set[ kind ], ctrl )
	return ctrl
end

function W.Remove( set, kind, ctrl )
	local list = set[ kind ]
	if ((!list) || (!ctrl)) then return end
	for i = #list, 1, -1 do
		if (list[ i ] == ctrl) then table.remove( list, i ) end
	end
end

function W.Each( set, order, fn )
	for _, kind in ipairs( order or W.Order ) do
		local list = set[ kind ]
		if (list) then
			for i = 1, #list do fn( kind, list[ i ], i ) end
		end
	end
end

function W.Paint( dev, kind, ctrl )
	local def = W.Get( kind )
	if (def && def.Paint) then def.Paint( dev, ctrl ) end
end

function W.Hit( dev, kind, ctrl, x, y )
	local def = W.Get( kind )
	if (def && def.Hit) then return def.Hit( dev, ctrl, x, y ) end
	return false
end

function W.Click( dev, kind, ctrl, x, y, right )
	local def = W.Get( kind )
	if (def && def.Click) then def.Click( dev, ctrl, x, y, right ) end
end

function W.AllowRight( kind )
	local def = W.Get( kind )
	return ((def) && (def.Right == true))
end

function W.StopLayer( kind )
	local def = W.Get( kind )
	return ((def) && (def.StopLayer == true))
end

// ---------------------------------------------------------------------------------------------------------
// Control kinds
// ---------------------------------------------------------------------------------------------------------

W.Register( "textbox", {
	Paint = function( dev, ctrl ) dev:RenderTextbox( ctrl ) end,
	Hit = function( dev, ctrl, x, y ) return dev:CursorInTextbox( ctrl, x, y ) end,
	Click = function( dev, ctrl, x, y, right )
		if (!right) then dev:Int_TextboxClick( ctrl.Name, x, y ) end
	end,
	Right = false,
	// The old ClickTextboxes stopped after the first textbox but the other
	// layers still ran; keep that behaviour byte-for-byte.
	StopLayer = true
} )

W.Register( "listbox", {
	Paint = function( dev, ctrl ) dev:RenderListbox( ctrl ) end,
	Hit = function( dev, ctrl, x, y ) return dev:CursorInListbox( ctrl, x, y ) end,
	Click = function( dev, ctrl, x, y, right ) dev:Int_ListboxClick( ctrl.Name, x, y, right ) end,
	Right = true,
	// Every overlapping listbox used to receive the click.
	StopLayer = false
} )

W.Register( "element", {
	Paint = function( dev, ctrl )
		if ((ctrl) && (ctrl:IsValid())) then ctrl:Paint() end
	end,
	Hit = function( dev, ctrl, x, y )
		if ((!ctrl) || (!ctrl.CursorInside)) then return false end
		local cx = dev.win_x + (dev.win_w * x)
		local cy = dev.win_y + (dev.win_h * y)
		return ctrl:CursorInside( cx, cy )
	end,
	Click = function( dev, ctrl, x, y, right )
		if (!right) then ctrl:OnClick() end
	end,
	Right = false,
	StopLayer = true
} )
