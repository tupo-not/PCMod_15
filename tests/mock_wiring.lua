-- Wiring invalid-port handling must fail cleanly instead of indexing nil.
PCMod = {
    Msg = function() end,
    Cfg = { WireTypes = {} },
}
dofile( "pcmod_wiring.lua" )

local ent = { IsPCMod = true }
function ent:IsValid() return true end
function ent:Ports() return {} end

local ok, result = pcall( PCMod.Wiring.UnlinkPort, ent, 99 )
if (not ok) then error( "FAILED: invalid unlink raised an error: " .. tostring( result ) ) end
if (result ~= false) then error( "FAILED: invalid unlink did not return false" ) end

print( "ALL WIRING TESTS PASSED" )
