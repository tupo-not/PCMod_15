-- sh_json hardening: malformed input must come back as nil + error (pcall),
-- never as an infinite loop or an uncaught crash; cycles must error on Encode.
local function assertTrue(v,m) if not v then error('FAILED: '..m,2) end end
local function assertEq(a,b,m) if a~=b then error('FAILED: '..m..' got '..tostring(a)..' want '..tostring(b),2) end end

dofile('pcmod_sh_json.lua')
assertTrue(Json ~= nil, "Json module loaded")

-- roundtrip
local src = { a = 1, b = "x y", c = { 1, 2, 3 }, d = true }
local enc = Json.Encode(src)
local dec = Json.Decode(enc)
assertEq(dec.a, 1, "roundtrip number")
assertEq(dec.b, "x y", "roundtrip string")
assertEq(#dec.c, 3, "roundtrip array len")
assertEq(dec.d, true, "roundtrip bool")

local d2 = Json.Decode('{"k":"v"}')
assertEq(d2.k, "v", "simple object")

-- malformed inputs: nil + err, and no hang
local v, err = Json.Decode('// only a comment')
assertTrue(v == nil and err ~= nil, "line comment at EOF returns nil,err")
v, err = Json.Decode('/* unterminated')
assertTrue(v == nil and err ~= nil, "unterminated block comment returns nil,err")
v, err = Json.Decode('{"a')
assertTrue(v == nil and err ~= nil, "unterminated string returns nil,err")
v, err = Json.Decode(string.rep('[', 500))
assertTrue(v == nil and err ~= nil, "deep nesting returns nil,err")
v, err = Json.Decode(nil)
assertTrue(v == nil and err ~= nil, "non-string input returns nil,err")

-- cyclic table must error on Encode (caught), not recurse forever
local cyc = {} cyc.self = cyc
local ok = pcall(Json.Encode, cyc)
assertTrue(ok == false, "cyclic table encode errors")

-- a shared (non-cyclic) reference must still encode fine
local shared = { 1 }
local ok2 = pcall(Json.Encode, { shared, shared })
assertTrue(ok2 == true, "shared table reference encodes fine")

print("JSON TESTS PASSED")
