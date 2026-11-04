-- PCMod.Web HTML subset parser tests (plain Lua after translation).
function string.Trim( s )
	return (string.gsub( s, "^%s*(.-)%s*$", "%1" ))
end

PCMod = {}
dofile( "pcmod_web.lua" )

local function assertTrue( v, m )
	if (not v) then error( "FAILED: " .. m, 2 ) end
end
local function assertEq( a, b, m )
	if (a ~= b) then error( "FAILED: " .. m .. " got " .. tostring( a ) .. " want " .. tostring( b ), 2 ) end
end

local doc = PCMod.Web.Parse( '<h1>Title</h1><p><b>Model:</b> pcmod_router</p><ul><li><a href="fd00:1::1">Backbone</a></li></ul>' )

-- h1 -> a single bold span.
assertEq( #doc[ 1 ], 1, "heading is one span" )
assertTrue( doc[ 1 ][ 1 ].bold, "heading is bold" )
assertEq( doc[ 1 ][ 1 ].t, "Title", "heading text" )

-- <p><b>label</b> value -> two spans.
assertEq( #doc[ 2 ], 2, "paragraph has two spans" )
assertTrue( doc[ 2 ][ 1 ].bold, "label is bold" )
assertEq( doc[ 2 ][ 1 ].t, "Model:", "label text" )
assertTrue( not doc[ 2 ][ 2 ].bold, "value is normal" )
assertTrue( string.find( doc[ 2 ][ 2 ].t, "pcmod_router", 1, true ) ~= nil, "value text" )

-- <li><a href> -> bullet prefix + link span.
assertEq( doc[ 3 ][ 1 ].t, "• ", "list item has a bullet" )
assertEq( doc[ 3 ][ 2 ].href, "fd00:1::1", "link target parsed" )
assertTrue( string.find( doc[ 3 ][ 2 ].t, "Backbone", 1, true ) ~= nil, "link text" )

-- Newlines and <br> both break lines.
local plain = PCMod.Web.Parse( "line one\nline two<br>line three" )
assertEq( #plain, 3, "newline + br split lines" )
assertEq( plain[ 2 ][ 1 ].t, "line two", "newline line kept" )

print( "ALL WEB TESTS PASSED" )