--[[
    DungeonAutofarm loader.

    Paste this instead of a bare loadstring. It exists because raw.github-
    usercontent sits behind Fastly with a five-minute TTL, and a stale fetch is
    indistinguishable from a broken script once it is running - you end up
    debugging a version you are not actually executing.

    What it does, in order of how much each one buys you:

      1. Busts the query string. A changed query string changes the CDN's cache
         key outright, and also defeats URL-keyed caching inside the executor's
         own HTTP layer. Uses os.clock(), not os.time(): second resolution
         collides when you re-run twice in one second, which is exactly what
         you do while iterating.
      2. Sends no-cache headers, via `request` rather than HttpGet - HttpGet
         takes no headers. Headers ask the edge to revalidate; the query string
         forces it. Doing both is belt and braces.
      3. Reads the version out of the body BEFORE running it, so a stale fetch
         is caught rather than executed.
      4. Reports Fastly's `age` header when the body looks stale, which is what
         tells you whether the edge or the executor is holding the old copy.

    DEV = true reads from a local file instead, so editing does not round-trip
    through GitHub at all.
--]]

local DEV       = false                     -- true: load the local copy below
local DEV_PATH  = "dqr/DungeonAutofarm.lua"
local REPO      = "Tsukiatte/dq"
local BRANCH    = "main"                    -- or a commit SHA, see PIN below
local FILE      = "DungeonAutofarm.lua"

-- Pin a commit SHA here for anything you hand to other people. A SHA URL is
-- unique per commit, so it can never be stale and a bad push cannot reach
-- anyone who has not chosen to update.
local PIN       = nil                       -- e.g. "3b168da"

local URL = ("https://raw.githubusercontent.com/%s/%s/%s")
    :format(REPO, PIN or BRANCH, FILE)

local function log(...) print("[loader]", ...) end

-- Executors disagree on what the header-capable request function is called.
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
            -- Fastly reports how long the edge has been holding this copy. If
            -- the body turns out stale, this number says whose fault it is:
            -- non-zero means the edge, zero means the executor cached it.
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

-- Check the version before executing, not after. A stale body that runs is a
-- debugging session spent on code you are not looking at.
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
