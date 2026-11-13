// ---------------------------------------------------------------------------------------------------------
// ssdevices/base_windowdrag.lua - window drag and resize handling
// Included by ssdevices/base.lua; extends the same DEV table.
// ---------------------------------------------------------------------------------------------------------

	function DEV:CanStartWindowDrag( x, y )
		if ((!self.WindowDrag) || (self.WindowDragging)) then return false end
		if ((!self.win_w) || (self.win_w <= 0) || (!self.win_h) || (self.win_h <= 0)) then return false end
		if ((y < 0) || (y > (self.DragBar or 0.06))) then return false end
		// Do not steal clicks from title-bar buttons (close, etc.).
		local cx = self.win_x + (self.win_w * x)
		local cy = self.win_y + (self.win_h * y)
		for _, v in pairs( self.Elements or {} ) do
			if ((v) && (v.CursorInside) && (v:CursorInside( cx, cy ))) then return false end
		end
		return true
	end

	function DEV:StartWindowDrag( x, y )
		self.WindowDragging = true
		self.SuppressClick = 0
		if (PCMod.SDraw) then PCMod.SDraw.GrabActive = true end
		self:RaiseLocal()
		self.DragUIScale = (PCMod.SDraw && PCMod.SDraw.WindowScale) or 1
		self.DragOffX = 0
		self.DragOffY = 0
		self.DragMouseX = gui.MouseX()
		self.DragMouseY = gui.MouseY()
		self.DragDevX = self.SSDevice and self.SSDevice.X or (self.win_x / math.max( 1, ScrW() ))
		self.DragDevY = self.SSDevice and self.SSDevice.Y or (self.win_y / math.max( 1, ScrH() ))
		self.DragDevW = self.SSDevice and self.SSDevice.W or (self.win_w / math.max( 1, ScrW() ))
		self.DragDevH = self.SSDevice and self.SSDevice.H or (self.win_h / math.max( 1, ScrH() ))
	end

	// Called by PCMod.SDraw.UpdateWindowGrab() on the actual mouse press.
	function DEV:TryStartWindowGrab( mx, my )
		if (!(self.WindowDrag || self.WindowResize)) then return false end
		local d = self.SSDevice
		if ((!d) || (!d.W) || (d.W <= 0) || (!d.H) || (d.H <= 0)) then return false end
		local sw, sh = ScrW(), ScrH()
		local S = (PCMod.SDraw && PCMod.SDraw.WindowScale) or 1
		if ((sw <= 0) || (sh <= 0)) then return false end
		local lx = (mx - (d.X * sw)) / (d.W * sw * S)
		local ly = (my - (d.Y * sh)) / (d.H * sh * S)
		if ((lx < 0) || (lx > 1) || (ly < 0) || (ly > 1)) then return false end
		if (self.WindowResize && self:CanStartWindowResize( lx, ly )) then
			self:StartWindowResize( lx, ly )
			return true
		end
		if (self.WindowDrag && self:CanStartWindowDrag( lx, ly )) then
			self:StartWindowDrag( lx, ly )
			return true
		end
		return false
	end

	function DEV:FinishWindowGrab()
		local move = self.WindowDragging
		local size = self.WindowResizing
		if ((!move) && (!size)) then return end
		self.WindowDragging = false
		self.WindowResizing = false
		// The release click is already swallowed by PCMod.SDraw.GrabActive in
		// RegisterClick (it stays true until this finishes, so the release can
		// never click through to a control). Do not set a long Suppress* window
		// here: a 0.3s one left a dead zone that ate the next legitimate click.
		self.SuppressClick = 0
		if (PCMod.SDraw) then
			PCMod.SDraw.GrabActive = false
			PCMod.SDraw.SuppressClicksUntil = 0
		end
		if ((self.ProgName) && (self.ProgName != "") && (self.SSDevice)) then
			if (move) then
				self:RunProgCommand( self.ProgName, "win_move", string.format( "%.4f", self.SSDevice.X ), string.format( "%.4f", self.SSDevice.Y ) )
			elseif (size) then
				self:RunProgCommand( self.ProgName, "win_resize", string.format( "%.4f", self.SSDevice.W or 0.62 ), string.format( "%.4f", self.SSDevice.H or 0.72 ) )
			end
		end
		// Raise the window for real after the move/resize, so the server's
		// screen update already carries the final geometry.
		self:FocusWindow()
	end

	// Minimum window size in viewport fractions. Returns safe defaults if a
	// malformed payload ever puts non-numeric values on the device.
	function DEV:GetMinWindowSize()
		local mw = tonumber( self.MinW ) or 0.5
		local mh = tonumber( self.MinH ) or 0.6
		return math.Clamp( mw, 0.05, 1 ), math.Clamp( mh, 0.05, 1 )
	end

	// Shared geometry model: SSDevice remains the wire-facing X/Y/W/H, while
	// the clamp/minimum rules come from PCMod.Window (same code as the server).
	function DEV:GetWindowModel()
		local win = self.WindowModel
		if ((!win) && (PCMod.Window)) then
			win = PCMod.Window.New()
			self.WindowModel = win
		end
		if (!win) then return nil end
		win:SetFromDevice( self.SSDevice )
		local mw, mh = self:GetMinWindowSize()
		win:SetMin( mw, mh )
		return win
	end

	function DEV:CanStartWindowResize( x, y )
		if ((!self.WindowResize) || (self.WindowResizing) || (self.WindowDragging)) then return false end
		if ((!self.win_w) || (self.win_w <= 0) || (!self.win_h) || (self.win_h <= 0)) then return false end
		local grip = self.ResizeGrip or 0.035
		return ((x >= (1 - grip)) && (y >= (1 - grip)))
	end

	function DEV:StartWindowResize( x, y )
		self.WindowResizing = true
		self.SuppressClick = 0
		if (PCMod.SDraw) then PCMod.SDraw.GrabActive = true end
		self:RaiseLocal()
		self.ResizeUIScale = (PCMod.SDraw && PCMod.SDraw.WindowScale) or 1
		self.ResizeOffX = 0
		self.ResizeOffY = 0
		self.ResizeMouseX = gui.MouseX()
		self.ResizeMouseY = gui.MouseY()
		self.ResizeStartW = self.win_w
		self.ResizeStartH = self.win_h
	end

	// Live resize: rebuild the control layout at the new pixel size while the
	// grip is dragged. Int_Reinitialize keeps the user's textbox contents.
	function DEV:UpdateWindowResize()
		if (!self.WindowResizing) then return end
		local down = false
		if (input && input.IsMouseDown) then down = input.IsMouseDown( MOUSE_LEFT ) end
		if (!down) then
			self:FinishWindowGrab()
			return
		end
		if ((!gui) || (!gui.MouseX) || (!ScrW) || (!ScrH)) then return end
		local sw, sh = ScrW(), ScrH()
		if ((sw <= 0) || (sh <= 0)) then return end
		local S = self.ResizeUIScale or 1
		local vw, vh = sw * S, sh * S
		// Pixel limits: the visible window may not leave the viewport/taskbar.
		// Near a corner the remaining space can be smaller than the nominal
		// minimum, so cap the minimum to it instead of pushing the window out.
		local maxW = math.max( 1, sw - self.win_x )
		local maxH = math.max( 1, (0.94 * sh) - self.win_y )
		local nw, nh
		local win = self:GetWindowModel()
		if (win) then
			local rawW = (self.ResizeStartW + (gui.MouseX() - self.ResizeMouseX)) / vw
			local rawH = (self.ResizeStartH + (gui.MouseY() - self.ResizeMouseY)) / vh
			nw, nh = win:ClampSize( rawW, rawH, maxW / vw, maxH / vh )
		else
			local minWf, minHf = self:GetMinWindowSize()
			local minW = math.min( minWf * vw, maxW )
			local minH = math.min( minHf * vh, maxH )
			local pxW = math.Clamp( self.ResizeStartW + (gui.MouseX() - self.ResizeMouseX), minW, maxW )
			local pxH = math.Clamp( self.ResizeStartH + (gui.MouseY() - self.ResizeMouseY), minH, maxH )
			nw = pxW / vw
			nh = pxH / vh
		end
		nw = tonumber( string.format( "%.4f", nw ) ) or nw
		nh = tonumber( string.format( "%.4f", nh ) ) or nh
		pxW = nw * vw
		pxH = nh * vh
		if ((math.abs( pxW - self.win_w ) < 2) && (math.abs( pxH - self.win_h ) < 2)) then return end
		if (self.SSDevice) then
			self.SSDevice.W = nw
			self.SSDevice.H = nh
		end
		self:Int_Reinitialize( self.win_x, self.win_y, pxW, pxH )
	end

	function DEV:DrawResizeGrip( x, y, w, h )
		local d = math.max( 5, math.min( w, h ) * 0.018 )
		local gx = x + w - 2
		local gy = y + h - 2
		surface.SetDrawColor( 255, 255, 255, 150 )
		for i = 1, 3 do
			surface.DrawLine( gx - (i * d), gy, gx, gy - (i * d) )
		end
		surface.SetDrawColor( 0, 0, 0, 120 )
		for i = 1, 3 do
			surface.DrawLine( gx - (i * d) - 1, gy - 1, gx - 1, gy - (i * d) - 1 )
		end
	end

	// Move every child control with the window. This lets the drag look right
	// without a network round-trip per frame.
	function DEV:TranslateWindow( dx, dy )
		if ((!dx) || (!dy) || ((dx == 0) && (dy == 0))) then return end
		self.win_x = self.win_x + dx
		self.win_y = self.win_y + dy
		for _, lb in pairs( self.Listboxes or {} ) do
			lb.X = (lb.X or 0) + dx
			lb.Y = (lb.Y or 0) + dy
			lb.MX = lb.X + ((lb.W or 0) * 0.5)
		end
		for _, tb in pairs( self.Textboxes or {} ) do
			if (tb.BX) then tb.BX = tb.BX + dx end
			if (tb.TX) then tb.TX = tb.TX + dx end
			if (tb.TMX) then tb.TMX = tb.TMX + dx end
			if (tb.X) then tb.X = tb.X + dx end
			if (tb.MX) then tb.MX = tb.MX + dx end
			tb.Y = (tb.Y or 0) + dy
			tb.MY = (tb.MY or 0) + dy
		end
		for _, el in pairs( self.Elements or {} ) do
			if ((el) && (el.SetLayout)) then el:SetLayout( el.X + dx, el.Y + dy, el.W, el.H ) end
		end
	end

	function DEV:UpdateWindowDrag()
		if (!self.WindowDragging) then return end
		local down = false
		if (input && input.IsMouseDown) then down = input.IsMouseDown( MOUSE_LEFT ) end
		if (!down) then
			self:FinishWindowGrab()
			return
		end
		if ((!gui) || (!gui.MouseX) || (!ScrW) || (!ScrH)) then return end
		local sw, sh = ScrW(), ScrH()
		if ((sw <= 0) || (sh <= 0)) then return end
		// X/Y are normalized to the viewport, so mouse movement maps through the
		// viewport size. The visible window is W*S wide, so the clamp must use
		// the scaled size too (otherwise small GUI scales stop the window at an
		// invisible border long before the screen edge).
		local S = self.DragUIScale or 1
		local visW = (self.DragDevW or 0.62) * S
		local visH = (self.DragDevH or 0.72) * S
		local mx, my = gui.MouseX(), gui.MouseY()
		local nx, ny
		local win = self:GetWindowModel()
		if (win) then
			nx, ny = win:ClampPosition( self.DragDevX + ((mx - self.DragMouseX) / sw), self.DragDevY + ((my - self.DragMouseY) / sh), visW, visH )
		else
			nx = math.Clamp( self.DragDevX + ((mx - self.DragMouseX) / sw), 0, math.max( 0, 1 - visW ) )
			ny = math.Clamp( self.DragDevY + ((my - self.DragMouseY) / sh), 0, math.max( 0, 0.94 - visH ) )
		end
		// Match the server's rounding/clamping exactly so the in-place update
		// does not look like a resize and rebuild the window.
		nx = tonumber( string.format( "%.4f", nx ) ) or nx
		ny = tonumber( string.format( "%.4f", ny ) ) or ny
		local px = nx * sw
		local py = ny * sh
		self:TranslateWindow( px - self.win_x, py - self.win_y )
		if (self.SSDevice) then
			self.SSDevice.X = nx
			self.SSDevice.Y = ny
		end
	end
