// ---------------------------------------------------------------------------------------------------------
// web.lua - a tiny HTML subset for the in-game browser.
// Supported: <h1>/<h2>/<h3>, <p>, <br>, <b>/<strong>, <a href="...">, <ul>/<li>.
// Every other tag is ignored (its inner text is kept). No CSS/layout engine.
// ---------------------------------------------------------------------------------------------------------
PCMod.Web = PCMod.Web or {}

// PCMod.Web.Parse( html ) -> list of lines. Each line is a list of spans:
//   { t = text, bold = boolean, href = link target or nil }.
PCMod.Web.Parse = function( html )
	html = tostring( html or "" )
	local lines = {}
	local spans = {}
	local bold = false
	local href = nil
	local bullet = false

	local function appendLine()
		if (#spans > 0) then table.insert( lines, spans ) end
		spans = {}
		if (bullet) then spans[ 1 ] = { t = "• ", bold = false, href = nil } end
		bullet = false
	end

	local function emit( s )
		if ((!s) || (s == "")) then return end
		local last = spans[ #spans ]
		if (last && (last.bold == bold) && (last.href == href)) then
			last.t = last.t .. s
		else
			table.insert( spans, { t = s, bold = bold, href = href } )
		end
	end

	// Split on newlines too, so plain text and <br> both produce line breaks.
	local function addText( s )
		if ((!s) || (s == "")) then return end
		local pos = 1
		while (true) do
			local nl = string.find( s, "\n", pos, true )
			if (!nl) then
				emit( string.sub( s, pos ) )
				break
			end
			emit( string.sub( s, pos, nl - 1 ) )
			appendLine()
			pos = nl + 1
		end
	end

	local i = 1
	local n = string.len( html )
	while (i <= n) do
		local lt = string.find( html, "<", i, true )
		if (!lt) then
			addText( string.sub( html, i ) )
			break
		end
		if (lt > i) then addText( string.sub( html, i, lt - 1 ) ) end
		local gt = string.find( html, ">", lt, true )
		if (!gt) then break end
		local tag = string.lower( string.Trim( string.sub( html, lt + 1, gt - 1 ) ) )
		i = gt + 1

		if ((tag == "br") || (tag == "br/")) then
			appendLine()
		elseif ((tag == "p") || (tag == "/p")) then
			appendLine()
		elseif (tag == "li") then
			bullet = true
			appendLine()
		elseif ((tag == "h1") || (tag == "h2") || (tag == "h3")) then
			appendLine()
			bold = true
		elseif ((tag == "/h1") || (tag == "/h2") || (tag == "/h3")) then
			appendLine()
			bold = false
		elseif ((tag == "b") || (tag == "strong")) then
			bold = true
		elseif ((tag == "/b") || (tag == "/strong")) then
			bold = false
		elseif ((tag == "a") || (string.sub( tag, 1, 2 ) == "a ")) then
			href = string.match( tag, "href=[\"'](.-)[\"']" ) or href
		elseif (tag == "/a") then
			href = nil
		end
		// ul, /ul, /li, html, head, body, title and unknown tags are ignored.
	end
	appendLine()
	return lines
end