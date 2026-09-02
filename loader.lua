
local DEV       = false                     
local DEV_PATH  = "dqr/DungeonAutofarm.lua"
local REPO      = "Tsukiatte/dq"
local BRANCH    = "main"                    
local FILE      = "DungeonAutofarm.lua"

local PIN       = nil                       

local URL = ("https://raw.githubusercontent.com/%s/%s/%s")
    :format(REPO, PIN or BRANCH, FILE)

local function log(...) print("[loader]", ...) end

local function getRequest()
    local fn = (syn and syn.request)
        or (http and http.request)
        or http_request
        or request
        or fluxus and fluxus.request
    return typeof(fn) == "function" and fn or nil
end

local function fetch()
    local bust = URL .. "?nocache=" .. tostring(os.clock()):gsub("%.", "")
    local req = getRequest()

    if req then
        local ok, res = pcall(req, {
            Url = bust,
            Method = "GET",
            Headers = {
                ["Cache-Control"] = "no-cache, no-store, max-age=0",
                ["Pragma"] = "no-cache",
            },
        })
        if ok and res and (res.Success or res.StatusCode == 200) and res.Body then

            local headers = res.Headers or {}
            return res.Body, tonumber(headers["age"] or headers["Age"])
        end
        log(("request failed (%s %s), falling back to HttpGet"):format(
            tostring(res and res.StatusCode), tostring(res and res.StatusMessage)))
    end
    local ok, body = pcall(function() return game:HttpGet(bust) end)
    if ok and body then return body, nil end
    return nil, nil, tostring(body)
end
local source, age, err
if DEV and isfile and isfile(DEV_PATH) then
    source = readfile(DEV_PATH)
    log("DEV: loaded " .. DEV_PATH .. " (" .. #source .. " bytes), no network involved")
else
    source, age, err = fetch()
    if not source then
        return log("could not fetch: " .. tostring(err))
    end
end

local version = source:match('SCRIPT_VERSION%s*=%s*"([%d%.]+)"') or "unknown"
log(("v%s, %d bytes%s"):format(version, #source,
    age and (", edge age " .. age .. "s") or ""))
if age and age > 0 then
    log("the CDN served a cached copy; if this version is not what you just "
        .. "pushed, wait for the 5 minute TTL or pin the commit SHA")
end
local chunk, compileErr = loadstring(source, "=DungeonAutofarm")
if not chunk then
    return log("did not compile: " .. tostring(compileErr))
end
local ok, runErr = pcall(chunk)
if not ok then
    log("threw on startup: " .. tostring(runErr))
end
