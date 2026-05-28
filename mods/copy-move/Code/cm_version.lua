-- Copy Move version (canonical single source).
-- Every behavior-changing edit should bump this and the metadata.lua version.

CopyMove = rawget(_G, "CopyMove") or {}
local CM = CopyMove
_G.CopyMove = CM

CM.VERSION = { major = 0, minor = 1, revision = 0 }

-- Return the formatted version string, e.g. "0.1-0".
function CM.VersionString()
	local v = CM.VERSION or {}
	return tostring(v.major or 0) .. "." .. tostring(v.minor or 0) .. "-" .. tostring(v.revision or 0)
end
