// ---------------------------------------------------------------------------------------------------------
// web.lua - a tiny HTML subset for the in-game browser.
// Supported: <h1>/<h2>/<h3>, <p>, <br>, <hr>, <b>/<strong>, <a href="...">, <ul>/<li>,
// <input type="text"> and <input type="submit">. Everything else is ignored.
// ---------------------------------------------------------------------------------------------------------
PCMod.Web = PCMod.Web or {}

// PCMod.Web.Parse( html ) -> list of lines. Each line is a list of spans:
//   text  : { kind="text",  t=text, bold=false/true, href=nil or target }
//   input : { kind="input", name=..., value=..., form=<n> }
//   submit: { kind="submit", t=label, form=<n> }
// Multiple <form> sections are tracked; a submit only submits its own form.
PCMod.Web.Parse = function( html )
	html = tostring( html or "" )
	local lines = {}
	local spans = {}
	local bold = false
	local href = nil
	local bullet = false
	local formId = 0

	local function appendLine()
		if (#spans > 0) then table.insert( lines, spans ) end
		spans = {}
		if (bullet) then spans[ 1 ] = { kind = "text", t = "• ", bold = false, href = nil } end
		bullet = false
	end

	local function emit( s )
		if ((!s) || (s == "")) then return end
		local last = spans[ #spans ]
		if (last && (last.kind == "text") && (last.bold == bold) && (last.href == href)) then
			last.t = last.t .. s
		else
			table.insert( spans, { kind = "text", t = s, bold = bold, href = href } )
		end
	end

	local function addText( s )
		if ((!s) || (s == "")) then return end
		local pos = 1
		while (true) do
			local nl = string.find( s, "\n", pos, true )
			if (!nl) then emit( string.sub( s, pos ) ) break end
			emit( string.sub( s, pos, nl - 1 ) )
			appendLine()
			pos = nl + 1
		end
	end

	local i = 1
	local n = string.len( html )
	while (i <= n) do
		local lt = string.find( html, "<", i, true )
		if (!lt) then addText( string.sub( html, i ) ) break end
		if (lt > i) then addText( string.sub( html, i, lt - 1 ) ) end
		local gt = string.find( html, ">", lt, true )
		if (!gt) then break end
		local rawtag = string.Trim( string.sub( html, lt + 1, gt - 1 ) )
		local tag = string.lower( string.match( rawtag, "^%S+" ) or rawtag )
		i = gt + 1

		if ((tag == "br") || (tag == "br/")) then
			appendLine()
		elseif (tag == "hr") then
			// Section separator: a full line of dashes.
			appendLine()
			emit( string.rep( "-", 28 ) )
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
			href = string.match( rawtag, "href=[\"'](.-)[\"']" ) or href
		elseif (tag == "/a") then
			href = nil
		elseif (tag == "form") then
			formId = formId + 1
		elseif (tag == "/form") then
			if (formId > 0) then formId = formId - 1 end
		elseif ((tag == "input") || (string.sub( tag, 1, 6 ) == "input ")) then
			local itype = string.match( rawtag, "type=[\"'](.-)[\"']" ) or "text"
			local name = string.match( rawtag, "name=[\"'](.-)[\"']" )
			if (itype == "submit") then
				table.insert( spans, { kind = "submit", t = string.match( rawtag, "value=[\"'](.-)[\"']" ) or "Save", form = formId } )
			elseif (name) then
				table.insert( spans, { kind = "input", name = name, value = string.match( rawtag, "value=[\"'](.-)[\"']" ) or "", form = formId } )
			end
		end
	end
	appendLine()
	return lines
end