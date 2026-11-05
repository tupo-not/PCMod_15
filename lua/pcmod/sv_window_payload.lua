// ---------------------------------------------------------------------------------------------------------
// sv_window_payload.lua - Server-Side
// Turns a declarative program window spec into the flat DeviceData payload the
// client already understands. This is deliberately network-only: no layout or
// drawing code belongs here.
// ---------------------------------------------------------------------------------------------------------

PCMod.WindowPayload = {}
local P = PCMod.WindowPayload

// Build a normalised spec. Programs may return the short form:
//   { Type = "window_x", Key = "window_x", Data = self.DeviceData }
// The defaults preserve the old base-program behaviour.
function P.Normalize( prog, spec )
	spec = spec or {}
	local minW, minH = prog:GetMinWindowSize()
	local out = {
		Type = spec.Type or spec.Device or prog.DeviceLink,
		Key = spec.Key or spec.Name or prog.DeviceName,
		Data = spec.Data or prog.DeviceData or {},
		Geometry = spec.Geometry,
		Drag = ((spec.Drag != nil) && spec.Drag) || ((spec.Drag == nil) && (prog.OS == "personal")),
		Resize = ((spec.Resize != nil) && spec.Resize) || ((spec.Resize == nil) && (prog.OS == "personal")),
		MinW = spec.MinW or minW,
		MinH = spec.MinH or minH,
		Priority = spec.Priority,
		Prepare = spec.Prepare,
		After = spec.After
	}
	return out
end

// Stamp the window-manager fields the device base reads. Kept out of the
// program so a client-side layout change can never silently drop them again.
function P.Stamp( prog, spec, data )
	data = data or spec.Data or {}
	data.ProgName = prog.Name
	data.WindowDrag = (spec.Drag == true)
	data.WindowResize = (spec.Resize == true)
	data.MinW = tonumber( spec.MinW ) or 0.5
	data.MinH = tonumber( spec.MinH ) or 0.6
	return data
end

// Prepare data, geometry and priority for one device. The returned table is
// the exact information the screen-space builder needs; no GUI objects leak in.
function P.Build( prog, spec )
	spec = P.Normalize( prog, spec )
	local data = spec.Data
	if (spec.Prepare) then spec.Prepare( prog, data ) end
	P.Stamp( prog, spec, data )

	local dms = spec.Geometry
	if (!dms) then
		local d = prog:GetDimensions()
		dms = { x = d.x, y = d.y, w = d.w, h = d.h }
	end
	local prio = spec.Priority
	if (prio == nil) then prio = prog:GetPriority() end

	return {
		Type = spec.Type,
		Key = spec.Key,
		Data = data,
		X = dms.x,
		Y = dms.y,
		W = dms.w,
		H = dms.h,
		Priority = prio,
		After = spec.After
	}
end
