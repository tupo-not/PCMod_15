// Browser Program for PCMod 2 \\
// Fetches and displays a page over the PCMod network (for now, the router's
// built-in web server on port 80). No DNS: type an IPv4 or IPv6 address.

PROG.Name = "browser"
PROG.Author = "PCMod"
PROG.Title = "Browser"
PROG.Icon = "app"
PROG.OS = "personal"

PROG.SimpleMode = true

PROG.DeviceLink = "window_browser"
PROG.DeviceName = "window_browser"
PROG.DeviceData = {}

PROG.Home = "PCMod Browser\n\nType an address (IPv4 or IPv6) above and press Go."

function PROG:OnInstall()
	self:GetOS():AddProg( self.Icon, self.Title, "sys_openprog browser" )
end

function PROG:OnStart()
	self:GetOS():OpenNetPort( 80, "prog", self.Name )
	// Reset every visit: close/reopen and power toggles must not leave a stale
	// page, status, address or pending request behind.
	self.DeviceData.Url = ""
	self.DeviceData.Content = self.Home
	self.DeviceData.Status = ""
	self.Pending = false
	self.Timeout = nil
end

function PROG:OnEnd()
	self:GetOS():CloseNetPort( 80 )
	self.Pending = false
end

// Split "http://1.2.3.4/path" into (address, path). Scheme + leading/trailing
// whitespace are ignored. A relative target (leading "?" or "/") has no
// address, so it returns (nil, path) for the caller to resolve.
function PROG:ParseUrl( url )
	url = tostring( url or "" )
	url = string.Trim( url )
	url = string.gsub( url, "^%a+://", "" )
	local path = ""
	if (string.sub( url, 1, 1 ) == "?") then
		path = url
		url = ""
	else
		local slash = string.find( url, "/", 1, true )
		if (slash) then
			path = string.sub( url, slash )
			url = string.sub( url, 1, slash - 1 )
		end
	end
	if ((url == "") && (path == "")) then return nil, "" end
	if (url == "") then return nil, path end
	return url, path
end

function PROG:DoCommand( com, args )
	if (com == "exit") then
		self:Exit()
		return
	end
	if (com == "home") then
		self.DeviceData.Url = ""
		self.DeviceData.Content = self.Home
		self.DeviceData.Status = ""
		self:UpdateSS()
		return
	end
	if (com == "go") then
		local url = args[1] or ""
		local addr, path = self:ParseUrl( url )
		// Relative links ("/path" or "?query") resolve against the last address.
		if ((!addr) && (path != "") && self.CurrentAddr) then addr = self.CurrentAddr end
		if ((!addr) || (!PCMod.IPv6.IsIP( addr ))) then
			self.DeviceData.Url = url
			self.DeviceData.Status = "Invalid address."
			self:UpdateSS()
			return
		end
		self.CurrentAddr = addr
		self.DeviceData.Url = (path == "") and addr or (addr .. path)
		self.DeviceData.Status = "Loading " .. addr .. "..."
		self.Pending = true
		self.Timeout = CurTime() + 10
		self:GetOS():SendNetMessage( addr, 80, { "http", path } )
		self:UpdateSS()
		return
	end
end

function PROG:ProcessPacket( pt, dat, hdl )
	if (pt != 80) then return end
	if (dat[1] == "http-response") then
		self.Pending = false
		self.DeviceData.Content = dat[2] or ""
		self.DeviceData.Status = ""
		self:UpdateSS()
	elseif ((dat[1] == "netPortClosed") || (dat[1] == "netPortLocked")) then
		self.Pending = false
		self.DeviceData.Status = "Connection refused."
		self:UpdateSS()
	end
end

function PROG:Think()
	if (self.Pending && self.Timeout && (CurTime() > self.Timeout)) then
		self.Pending = false
		self.DeviceData.Status = "Timed out."
		self:UpdateSS()
	end
end