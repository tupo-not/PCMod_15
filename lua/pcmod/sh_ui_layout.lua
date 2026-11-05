// ---------------------------------------------------------------------------------------------------------
// sh_ui_layout.lua - Shared
// Pure rectangle helpers for screen-space window layouts. No drawing and no
// networking lives here, so the same primitives can be reasoned about (and
// tested) on both sides.
// ---------------------------------------------------------------------------------------------------------

PCMod.UI = PCMod.UI or {}
local UI = PCMod.UI

// Accept either four numbers or an existing rect and always return a plain,
// numeric copy. This keeps callers from accidentally aliasing a rect.
function UI.Rect( x, y, w, h )
	if (type( x ) == "table") then
		local r = x
		return {
			x = tonumber( r.x or r.X ) or 0,
			y = tonumber( r.y or r.Y ) or 0,
			w = tonumber( r.w or r.W ) or 0,
			h = tonumber( r.h or r.H ) or 0
		}
	end
	return {
		x = tonumber( x ) or 0,
		y = tonumber( y ) or 0,
		w = tonumber( w ) or 0,
		h = tonumber( h ) or 0
	}
end

// A child rect expressed in fractions of its parent. This is the direct
// replacement for the old x+(w*fx), y+(h*fy) arithmetic.
function UI.Box( parent, x, y, w, h )
	local p = UI.Rect( parent )
	return {
		x = p.x + (p.w * (tonumber( x ) or 0)),
		y = p.y + (p.h * (tonumber( y ) or 0)),
		w = p.w * (tonumber( w ) or 0),
		h = p.h * (tonumber( h ) or 0)
	}
end

// Spread a rect into rows/columns. weights may be an array or a count (equal
// shares). gap is a fraction of the parent's length, not pixels.
function UI.Split( rect, axis, weights, gap )
	local r = UI.Rect( rect )
	if (type( weights ) == "number") then
		local n = math.max( 1, math.floor( weights ) )
		local tmp = {}
		for i = 1, n do tmp[ i ] = 1 end
		weights = tmp
	end
	if ((!weights) || (#weights < 1)) then weights = { 1 } end

	local total = 0
	for _, v in ipairs( weights ) do total = total + (tonumber( v ) or 0) end
	if (total <= 0) then total = #weights end

	local count = #weights
	local g = math.max( 0, tonumber( gap ) or 0 )
	local length = ((axis == "x") && r.w) || r.h
	g = g * length
	local avail = math.max( 0, length - (g * math.max( 0, count - 1 )) )
	local pos = ((axis == "x") && r.x) || r.y
	local out = {}

	for i, v in ipairs( weights ) do
		local size = avail * ((tonumber( v ) or 0) / total)
		if (axis == "x") then
			out[ i ] = { x = pos, y = r.y, w = size, h = r.h }
		else
			out[ i ] = { x = r.x, y = pos, w = r.w, h = size }
		end
		pos = pos + size + g
	end
	return out
end

function UI.SplitRows( rect, weights, gap )
	return UI.Split( rect, "y", weights, gap )
end

function UI.SplitColumns( rect, weights, gap )
	return UI.Split( rect, "x", weights, gap )
end

// Shrink a rect by fractional margins.
function UI.Inset( rect, left, top, right, bottom )
	local r = UI.Rect( rect )
	local l = tonumber( left ) or 0
	local t = tonumber( top ) or 0
	local rr = tonumber( right ) or 0
	local b = tonumber( bottom ) or 0
	return {
		x = r.x + (r.w * l),
		y = r.y + (r.h * t),
		w = math.max( 0, r.w * (1 - l - rr) ),
		h = math.max( 0, r.h * (1 - t - b) )
	}
end

// Explicit anchor alias: same result as Box, named for layout code that wants
// to make the relationship obvious.
function UI.Anchor( parent, fx, fy, fw, fh )
	return UI.Box( parent, fx, fy, fw, fh )
end

// Unpack helper for the legacy Create* functions that still take four numbers.
function UI.Fields( rect )
	local r = UI.Rect( rect )
	return r.x, r.y, r.w, r.h
end
