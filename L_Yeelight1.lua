--[[
    L_Yeelight1.lua - Core module for Yeelight
    Copyright 2017,2018 Patrick H. Rigney, All Rights Reserved.
    This file is part of the Yeelight for Vera HA controllers.
--]]
--luacheck: std lua51,module,read globals luup,ignore 542 611 612 614 111/_,no max line length

module("L_Yeelight1", package.seeall)

local debugMode = false

local _PLUGIN_ID = 99999
local _PLUGIN_NAME = "Yeelight"
local _PLUGIN_VERSION = "0.1develop"
local _PLUGIN_URL = "https://www.toggledbits.com/"
local _CONFIGVERSION = 000002

local math = require "math"
local string = require "string"
local socket = require "socket"
local json = require "dkjson"

local MYSID = "urn:toggledbits-com:serviceId:Yeelight1"
local MYTYPE = "urn:schemas-toggledbits-com:device:Yeelight:1"

local BULBTYPE = "urn:schemas-upnp-org:device:DimmableRGBLight:1"

local SWITCHSID = "urn:upnp-org:serviceId:SwitchPower1"
local DIMMERSID = "urn:upnp-org:serviceId:Dimming1"
local COLORSID = "urn:micasaverde-com:serviceId:Color1"
local HADEVICESID = "urn:micasaverde-com:serviceId:HaDevice1"

local pluginDevice
local tickTasks = {}
local devData = {}

local runStamp = 0
local isALTUI = false
local isOpenLuup = false

local DISCOVERYPERIOD = 15

local function dump(t, seen)
    if t == nil then return "nil" end
    if seen == nil then seen = {} end
    local sep = ""
    local str = "{ "
    for k,v in pairs(t) do
        local val
        if type(v) == "table" then
            if seen[v] then val = "(recursion)"
            else
                seen[v] = true
                val = dump(v, seen)
            end
        elseif type(v) == "string" then
            if #v > 255 then val = string.format("%q", v:sub(1,252).."...")
            else val = string.format("%q", v) end
        elseif type(v) == "number" and (math.abs(v-os.time()) <= 86400) then
            val = tostring(v) .. "(" .. os.date("%x.%X", v) .. ")"
        else
            val = tostring(v)
        end
        str = str .. sep .. k .. "=" .. val
        sep = ", "
    end
    str = str .. " }"
    return str
end

local function L(msg, ...) -- luacheck: ignore 212
    local str
    local level = 50
    if type(msg) == "table" then
        str = tostring(msg.prefix or _PLUGIN_NAME) .. ": " .. tostring(msg.msg)
        level = msg.level or level
    else
        str = _PLUGIN_NAME .. ": " .. tostring(msg)
    end
    str = string.gsub(str, "%%(%d+)", function( n )
            n = tonumber(n, 10)
            if n < 1 or n > #arg then return "nil" end
            local val = arg[n]
            if type(val) == "table" then
                return dump(val)
            elseif type(val) == "string" then
                return string.format("%q", val)
            elseif type(val) == "number" and math.abs(val-os.time()) <= 86400 then
                return tostring(val) .. "(" .. os.date("%x.%X", val) .. ")"
            end
            return tostring(val)
        end
    )
    luup.log(str, level)
end

local function D(msg, ...)
    if debugMode then
        local t = debug.getinfo( 2 )
        local pfx = _PLUGIN_NAME .. "(" .. tostring(t.name) .. "@" .. tostring(t.currentline) .. ")"
        L( { msg=msg,prefix=pfx }, ... )
    end
end

local function checkVersion(dev)
    local ui7Check = luup.variable_get(MYSID, "UI7Check", dev) or ""
    if isOpenLuup then
        return true
    end
    if luup.version_branch == 1 and luup.version_major == 7 then
        if ui7Check == "" then
            -- One-time init for UI7 or better
            luup.variable_set( MYSID, "UI7Check", "true", dev )
        end
        return true
    end
    L({level=1,msg="firmware %1 (%2.%3.%4) not compatible"}, luup.version,
        luup.version_branch, luup.version_major, luup.version_minor)
    return false
end

local function split( str, sep )
    if sep == nil then sep = "," end
    local arr = {}
    if #str == 0 then return arr, 0 end
    local rest = string.gsub( str or "", "([^" .. sep .. "]*)" .. sep, function( m ) table.insert( arr, m ) return "" end )
    table.insert( arr, rest )
    return arr, #arr
end

-- Array to map, where f(elem) returns key[,value]
local function map( arr, f, res )
    res = res or {}
    for _,x in ipairs( arr ) do
        if f then
            local k,v = f( x )
            res[k] = (v == nil) and x or v
        else
            res[x] = x
        end
    end
    return res
end

-- Initialize a variable if it does not already exist.
local function initVar( name, dflt, dev, sid )
    assert( dev ~= nil, "initVar requires dev" )
    assert( sid ~= nil, "initVar requires SID for "..name )
    local currVal = luup.variable_get( sid, name, dev )
    if currVal == nil then
        luup.variable_set( sid, name, tostring(dflt), dev )
        return tostring(dflt)
    end
    return currVal
end

-- Set variable, only if value has changed.
local function setVar( sid, name, val, dev )
    val = (val == nil) and "" or tostring(val)
    local s = luup.variable_get( sid, name, dev ) or ""
    -- D("setVar(%1,%2,%3,%4) old value %5", sid, name, val, dev, s )
    if s ~= val then
        luup.variable_set( sid, name, val, dev )
    end
    return s
end

-- Get numeric variable, or return default value if not set or blank
local function getVarNumeric( name, dflt, dev, sid )
    assert( dev ~= nil )
    assert( name ~= nil )
    assert( sid ~= nil )
    local s = luup.variable_get( sid, name, dev ) or ""
    if s == "" then return dflt end
    s = tonumber(s)
    return (s == nil) and dflt or s
end

-- Enabled?
local function isEnabled()
    return getVarNumeric( "Enabled", 1, pluginDevice, MYSID ) ~= 0
end

-- Schedule a timer tick for a future (absolute) time. If the time is sooner than
-- any currently scheduled time, the task tick is advanced; otherwise, it is
-- ignored (as the existing task will come sooner), unless repl=true, in which
-- case the existing task will be deferred until the provided time.
local function scheduleTick( tinfo, timeTick, flags )
    D("scheduleTick(%1,%2,%3)", tinfo, timeTick, flags)
    flags = flags or {}
    local function nulltick(d,p) L({level=1, "nulltick(%1,%2)"},d,p) end
    local tkey = tostring( type(tinfo) == "table" and tinfo.id or tinfo )
    assert(tkey ~= nil)
    if ( timeTick or 0 ) == 0 then
        D("scheduleTick() clearing task %1", tinfo)
        tickTasks[tkey] = nil
        return
    elseif tickTasks[tkey] then
        -- timer already set, update
        tickTasks[tkey].func = tinfo.func or tickTasks[tkey].func
        tickTasks[tkey].args = tinfo.args or tickTasks[tkey].args
        tickTasks[tkey].info = tinfo.info or tickTasks[tkey].info
        if tickTasks[tkey].when == nil or timeTick < tickTasks[tkey].when or flags.replace then
            -- Not scheduled, requested sooner than currently scheduled, or forced replacement
            tickTasks[tkey].when = timeTick
        end
        D("scheduleTick() updated %1", tickTasks[tkey])
    else
        assert(tinfo.owner ~= nil)
        assert(tinfo.func ~= nil)
        tickTasks[tkey] = { id=tostring(tinfo.id), owner=tinfo.owner, when=timeTick, func=tinfo.func or nulltick, args=tinfo.args or {},
            info=tinfo.info or "" } -- new task
        D("scheduleTick() new task %1 at %2", tinfo, timeTick)
    end
    -- If new tick is earlier than next plugin tick, reschedule
    tickTasks._plugin = tickTasks._plugin or {}
    if tickTasks._plugin.when == nil or timeTick < tickTasks._plugin.when then
        tickTasks._plugin.when = timeTick
        local delay = timeTick - os.time()
        if delay < 1 then delay = 1 end
        D("scheduleTick() rescheduling plugin tick for %1", delay)
        runStamp = runStamp + 1
        luup.call_delay( "yeelightTaskTick", delay, runStamp )
    end
    return tkey
end

-- Schedule a timer tick for after a delay (seconds). See scheduleTick above
-- for additional info.
local function scheduleDelay( tinfo, delay, flags )
    D("scheduleDelay(%1,%2,%3)", tinfo, delay, flags )
    if delay < 1 then delay = 1 end
    return scheduleTick( tinfo, delay+os.time(), flags )
end

local function gatewayStatus( m )
    setVar( MYSID, "Message", m or "", pluginDevice )
end

local function getChildDevices( typ, parent, filter )
    parent = parent or pluginDevice
    local res = {}
    for k,v in pairs(luup.devices) do
        if v.device_num_parent == parent and ( typ == nil or v.device_type == typ ) and ( filter==nil or filter(k, v) ) then
            table.insert( res, k )
        end
    end
    return res
end

local function findChildById( childId, parent )
    parent = parent or pluginDevice
    for k,v in pairs(luup.devices) do
        if v.device_num_parent == parent and v.id == childId then return k,v end
    end
    return false
end

--[[ Prep for adding new children via the luup.chdev mechanism. The existingChildren
     table (array) should contain device IDs of existing children that will be
     preserved. Any existing child not listed will be dropped. If the table is nil,
     all existing children in luup.devices will be preserved.
--]]
local function prepForNewChildren( existingChildren )
    D("prepForNewChildren(%1)", existingChildren)
    local dfMap = { [BULBTYPE]="D_DimmableRGBLight1.xml" }
    if existingChildren == nil then
        existingChildren = {}
        for k,v in pairs( luup.devices ) do
            if v.device_num_parent == pluginDevice then
                assert(dfMap[v.device_type]~=nil, "BUG: device type missing from dfMap: `"..tostring(v.device_type).."'")
                table.insert( existingChildren, k )
            end
        end
    end
    local ptr = luup.chdev.start( pluginDevice )
    for _,k in ipairs( existingChildren ) do
        local v = luup.devices[k]
        assert(v)
        assert(v.device_num_parent == pluginDevice)
        D("prepForNewChildren() appending existing child %1 (%2/%3)", v.description, k, v.id)
        luup.chdev.append( pluginDevice, ptr, v.id, v.description, "",
            dfMap[v.device_type] or error("Invalid device type in child "..k),
            "", "", false )
    end
    return ptr, existingChildren
end

local function sendDeviceCommand( cmd, params, bulb, leaveOpen )
    D("sendDeviceCommand(%1,%2,%3)", cmd, params, bulb)
    devData[tostring(bulb)].nextCmdId = ( devData[tostring(bulb)].nextCmdId or 0 ) + 1
    local pv = {}
    if type(params) == "table" then
        for k,v in ipairs(params) do
            if type(v) == "string" then
                pv[k] = string.format( "%q", v )
            else
                pv[k] = tostring( v )
            end
        end
    elseif type(params) == "string" then
        table.insert( pv, string.format( "%q", params ) )
    elseif params ~= nil then
        table.insert( pv, tostring( params ) )
    end
    local pstr = table.concat( pv, "," )
    local payload = string.format( "{ \"id\": %d, \"method\": %q, \"params\": [%s] }\r\n",
        devData[tostring(bulb)].nextCmdId, cmd or "ping", pstr )

    local s = luup.variable_get( MYSID, "Address", bulb ) or ""
    local addr,port = s:match("^([^:]+):(%d+)")
    if addr == nil then addr = s port = 55443 end

    D("sendDeviceCommand() sending payload %1 to %2:%3", payload, addr, port)
    local sock = socket.tcp()
    sock:settimeout( 5 )
    if not sock:connect( addr, tonumber(port) or 55443 ) then
        L({level=2,msg="%1 (%2) connection failed to %4:%5, can't %3"}, luup.devices[bulb].description,
            bulb, cmd, addr, port)
        luup.set_failure( 1, bulb )
        sock:close()
        return
    end
    sock:settimeout( 1 )
    sock:send( payload )
    luup.set_failure( 0, bulb )
    if leaveOpen then
        return sock
    end
    sock:close()
    scheduleDelay( tostring(bulb), 2 )
    return false
end

local checkBulb -- forward decl
local function checkBulbProp( bulb, taskid, argv )
    D("checkBulbProp(%1,%2,%3)", bulb, taskid, argv)
    local sock, startTime = unpack( argv )
    sock:settimeout( 0 )
    while true do
        local p, err, part = sock:receive()
        if p then
            D("checkBulbProp() handling response data")
            local data,pos,err = json.decode( p )
            if data and data.result and type(data.result) == "table" then
                setVar( SWITCHSID, "Status", (data.result[1]=="on") and 1 or 0, bulb )
                setVar( SWITCHSID, "Target", (data.result[1]=="on") and 1 or 0, bulb )
                setVar( DIMMERSID, "LoadLevelStatus", (data.result[1]=="on") and data.result[2] or 0, bulb )
                setVar( DIMMERSID, "LoadLevelTarget", data.result[2], bulb )
                local w,d,r,g,b = 0,0,0,0,0
                local targetColor = ""
                if data.result[5] == "1" then
                    -- Light in RGB mode
                    local v = tonumber( data.result[4] ) or 0
                    r = math.floor( v / 65536 )
                    g = math.floor( v / 256 ) % 256
                    b = v % 256
                    targetColor = string.format("%d,%d,%d", r, g, b)
                elseif data.result[5] == "2" then
                    -- Light in color temp mode
                    local v = tonumber( data.result[3] ) or 3000
                    if v >= 5500 then
                        -- Daylight (cool) range
                        d = math.floor( ( v - 5500 ) / 3500 * 255 )
                        targetColor = string.format("D%d", d)
                    else
                        -- Warm range
                        w = math.floor( ( v - 2000 ) / 3500 * 255 )
                        targetColor = string.format("W%d", w)
                    end
                end -- 3=HSV, we don't support
                setVar( COLORSID, "CurrentColor", string.format( "0=%d,1=%d,2=%d,3=%d,4=%d", w, d, r, g, b ), bulb )
                setVar( COLORSID, "TargetColor", targetColor, bulb )
                setVar( MYSID, "HexColor", string.format("%02x%02x%02x", r, g, b), bulb )

                if getVarNumeric( "AuthoritativeForDevice", 0, bulb, MYSID ) ~= 0 then
                    -- ??? to do
                end

                break
            elseif data and data.method and data.method == "props" then
                -- Notification message in response to another command.
                -- Ignore it and keep going.
            else
                L({level=2,msg="%1 (%2) malformed property response from bulb"},
                    luup.devices[bulb].description, bulb)
                luup.log( p, 2 )
            end
        elseif err ~= "timeout" then
            D("checkBulbProp() socket error %1 part %2, closing", err, part)
            break
        elseif os.time() < (startTime + 5) then
            D("checkBulbProp() %1 part %2, continuing...", err, part)
            scheduleDelay( taskid, 1 )
            return
        else
            -- Time expired waiting for response.
            break
        end
    end
    -- Terminate read cycle
    D("checkBulbProp() closing socket, ending prop update")
    sock:close()
    local updateInterval = getVarNumeric( "UpdateInterval", getVarNumeric( "UpdateInterval", 300, pluginDevice, MYSID ), bulb, MYSID )
    scheduleDelay( { id=taskid, info="check", owner=bulb, func=checkBulb, args={} }, updateInterval )
end

checkBulb = function( bulb, taskid )
    D("checkBulb(%1)", bulb)
    local sock = sendDeviceCommand( "get_prop", { "power", "bright", "ct", "rgb", "color_mode" }, bulb, true )
    if sock then
        scheduleDelay( { id=taskid, info="readprop", func=checkBulbProp, args={ sock, os.time() } }, 1 )
        return
    end
    local updateInterval = getVarNumeric( "UpdateInterval", getVarNumeric( "UpdateInterval", 300, pluginDevice, MYSID ), bulb, MYSID )
    scheduleDelay( { id=taskid, info="check", owner=bulb, func=checkBulb, args={} }, updateInterval )
end

-- One-time init for bulb
local function initBulb( bulb )
    D("initBulb(%1)", bulb)
    -- initVar( "Address", "", bulb, MYSID ) -- set by child creation
    initVar( "UpdateInterval", "", bulb, MYSID )
    initVar( "HexColor", "808080", bulb, MYSID )
    initVar( "AuthoritativeForDevice", "0", bulb, MYSID )
    
    initVar( "Target", "0", bulb, SWITCHSID )
    initVar( "Status", "-1", bulb, SWITCHSID )
    
    initVar( "LoadLevelTarget", "100", bulb, DIMMERSID )
    initVar( "LoadLevelStatus", "0", bulb, DIMMERSID )
    initVar( "TurnOnBeforeDim", "0", bulb, DIMMERSID )
    initVar( "AllowZeroLevel", "0", bulb, DIMMERSID )
    
    initVar( "TargetColor", "W51", bulb, COLORSID )
    initVar( "CurrentColor", "", bulb, COLORSID )
    
    local s = getVarNumeric( "Version", 0, bulb, MYSID )
    if s < 000002 then
        luup.attr_set( "category_num", "2", bulb )
        luup.attr_set( "subcategory_num", "4", bulb )
    end
    
    setVar( MYSID, "Version", _CONFIGVERSION, bulb )
end

-- Start bulb
local function startBulb( bulb )
    D("startBulb(%1)", bulb)

    devData[tostring(bulb)] = {}

    scheduleDelay( { id=tostring(bulb), info="check", owner=bulb, func=checkBulb }, 15 )
end

-- Check bulbs
local function startBulbs( dev )
    D("startBulbs()")
    local bulbs = getChildDevices( BULBTYPE, dev )
    for _,bulb in ipairs( bulbs ) do
        initBulb( bulb )

        startBulb( bulb )
    end
end

--[[
    D I S C O V E R Y   A N D   C O N N E C T I O N
--]]

-- Process discovery responses
local function processDiscoveryResponses( dev )
    D("processDiscoveryResponses(%1)", dev)
    gatewayStatus("Processing discovery results")
    local ptr,existing = prepForNewChildren()
    local seen = map( existing, function( n ) return luup.devices[n].id end )
    local hasNew = false
    for _,ndev in pairs(devData[tostring(dev)].discoveryResponses) do
        local newid = ndev.Id
        if not seen[newid] then
            L("Adding new device %1 found at %2...", newid, ndev.Address)
            local sv = { MYSID .. ",Address=" .. ndev.Address }
            if ndev.Info then
                if ndev.Info.model then table.insert( sv, MYSID .. ",Model="..ndev.Info.model ) end
                if ndev.Info.support then table.insert( sv, MYSID .. ",Supports="..ndev.Info.support ) end
            end
            luup.chdev.append( pluginDevice, ptr,
                newid, -- id (altid)
                ndev.Name, -- description
                BULBTYPE, -- device type
                "D_DimmableRGBLight1.xml", -- device file
                "", -- impl file
                table.concat( sv, "\n" ), -- state vars
                false -- embedded
            )
            hasNew = true
        else
            -- Existing device; update address.
            L("Updating IP for existing device %1 (%2 #%3) to %4", newid,
                (luup.devices[seen[newid]] or {}).description, seen[newid], ndev.Address)
            luup.variable_set( MYSID, "Address", ndev.Address, seen[newid] )
        end
    end

    -- Close children. This will cause a Luup reload if something changed.
    if hasNew then
        L("New bulb(s) added, Luup reload coming!")
        gatewayStatus("New device(s) created, reloading Luup...")
        luup.sleep(5000) -- The only time I would ever do this (before sync)
    else
        L("No new devices discovered.")
        gatewayStatus("No new devices discovered.")
    end
    luup.chdev.sync( pluginDevice, ptr )
end

-- Handle discovery message
local function handleDiscoveryResponse( response, dev )
    D("handleDiscoveryResponse(%1,%2)", response, dev)

    local addr,port = tostring( response or "" ):lower():match( "location: *yeelight://([^:]+):(%d+)" )
    if addr then
        -- Parse the response headers.
        local r = split( response, "[\r\n]+" )
        local rf = {}
        for _,v in ipairs( r or {} ) do
            local hh,hv = string.match( v, "^([^:]+): *(.*)" )
            if hh then
                rf[hh:lower()] = hv
            end
        end
        if ( rf.id or "" ) ~= "" then
            local id = rf.id:lower():gsub( "^0x", "" )
            local name = ( rf.name or "" ) ~= "" and rf.name or ( "yeelight-" .. id:gsub( "^0+", "" ) )
            L("Received discovery response from %1 at %2", id, addr)

            -- Store it.
            devData[tostring(dev)].discoveryResponses = devData[tostring(dev)].discoveryResponses or {}
            if devData[tostring(dev)].discoveryResponses[id] == nil then
                devData[tostring(dev)].discoveryResponses[id] = { Id=id, Name=name or id, Address=addr .. ":" .. port, Info=rf }
            end
        else
            L({level=2,msg="Skipping discovered device at %1 because it did not provide ID"}, addr)
        end
    else
        D("handleDiscoveryResponse() ignoring non-compliant response: %1", response)
    end
end

-- Tick for SSDP discovery.
local function SSDPDiscoveryTask( dev, taskid )
    D("SSDPDiscoveryTask(%1,%2)", dev, taskid)

    local rem = math.max( 0, devData[tostring(dev)].discoveryTime - os.time() )
    gatewayStatus( string.format( "Discovery running (%d%%)...",
        math.floor((DISCOVERYPERIOD-rem)/DISCOVERYPERIOD*100)) )

    local udp = devData[tostring(dev)].discoverySocket
    if udp ~= nil then
        repeat
            udp:settimeout( 1 )
            local resp, peer, port = udp:receivefrom()
            if resp ~= nil then
                D("SSDPDiscoveryTask() received response from %1:%2", peer, port)
                if string.find( resp, "^M-SEARCH" ) then
                    -- Huh. There's an echo.
                else
                    handleDiscoveryResponse( resp, dev )
                end
            end
        until resp == nil

        D("SSDPDiscoveryTask() no more data")
        if os.time() < devData[tostring(dev)].discoveryTime then
            scheduleDelay( taskid, 1 )
            return
        else
            scheduleTick( taskid, 0 ) -- remove task
        end
        udp:close()
        devData[tostring(dev)].discoverySocket = nil
        devData[tostring(dev)].discoveryTime = nil
    end
    D("SSDPDiscoveryTask() end of discovery")
    processDiscoveryResponses( dev )
end

-- Launch SSDP discovery.
local function launchSSDPDiscovery( dev )
    D("launchSSDPDiscovery(%1)", dev)
    assert(dev ~= nil)
    assert(luup.devices[dev].device_type == MYTYPE, "Discovery much be launched with gateway device")

    -- Configure
    local addr = "239.255.255.250"
    local port = 1982
    local payload = string.format(
        "M-SEARCH * HTTP/1.1\r\nHOST: %s:%d\r\nMAN: \"ssdp:discover\"\r\nST: wifi_bulb\r\n\r\n",
        addr, port)

    -- Any of this can fail, and it's OK.
    local udp = socket.udp()
    udp:setsockname('*', port)
    D("launchSSDPDiscovery() sending discovery request %1", payload)
    local stat,err = udp:sendto( payload, addr, port)
    if stat == nil then
        gatewayStatus("Discovery failed! " .. tostring(err))
        L("Failed to send discovery req: %1", err)
        return
    end

    devData[tostring(dev)].discoverySocket = udp
    local now = os.time()
    devData[tostring(dev)].discoveryTime = now + DISCOVERYPERIOD
    devData[tostring(dev)].discoveryResponses = {}

    scheduleDelay( { id="discovery-"..dev, func=SSDPDiscoveryTask, owner=dev }, 1 )
    gatewayStatus( "Discovery running..." )
end

--[[
    ***************************************************************************
    A C T I O N   I M P L E M E N T A T I O N
    ***************************************************************************
--]]

-- Toggle state
function actionToggleState( bulb )
    assert(luup.devices[bulb].device_type == BULBTYPE)
    sendDeviceCommand( "toggle", nil, bulb )
end

-- Save current bulb settings as default power-on setting.
function actionSetDefault( bulb )
    assert(luup.devices[bulb].device_type == BULBTYPE)
    sendDeviceCommand( "set_default", nil, bulb )
end

function actionPower( state, dev )
    assert(luup.devices[dev].device_type == BULBTYPE)
    -- Switch on/off
    if type(state) == "string" then state = ( tonumber(state) or 0 ) ~= 0
    elseif type(state) == "number" then state = state ~= 0 end
    sendDeviceCommand( "set_power", { state and "on" or "off", "smooth", 500 }, dev )
    setVar( SWITCHSID, "Target", state and "1" or "0", dev )
    setVar( SWITCHSID, "Status", state and "1" or "0", dev )
    -- UI needs LoadLevelStatus to comport with state according to Vera's rules.
    if not state then
        setVar( DIMMERSID, "LoadLevelStatus", 0, dev )
    else
        -- Restore brightness
        local bright = getVarNumeric( "LoadLevelLast", 0, dev, DIMMERSID )
        if bright > 0 then
           sendDeviceCommand( "set_bright", { bright, "smooth", 500 }, dev )
        end
    end
end

function actionBrightness( newVal, dev )
    assert(luup.devices[dev].device_type == BULBTYPE)
    -- Dimming level change
    newVal = tonumber( newVal ) or 100
    if newVal < 0 then newVal = 0 elseif newVal > 100 then newVal = 100 end -- range
    if newVal > 0 then
        -- Level > 0, if light is off, turn it on.
        local status = getVarNumeric( "Status", 0, dev, SWITCHSID )
        if status == 0 then
            sendDeviceCommand( "set_power", { "on", "smooth", 500 }, dev )
            setVar( SWITCHSID, "Target", 1, dev )
            setVar( SWITCHSID, "Status", 1, dev )
        end
        sendDeviceCommand( "set_bright", { newVal, "smooth", 500 }, dev )
    elseif getVarNumeric( "AllowZeroLevel", 0, dev, DIMMERSID ) ~= 0 then
        -- Level 0 allowed as on state, just go with it.
        sendDeviceCommand( "set_bright", { 0, "smooth", 500 }, dev )
    else
        -- Level 0 (not allowed as an "on" state), switch light off.
        sendDeviceCommand( "set_power", { "off", "smooth", 500 }, dev )
        setVar( SWITCHSID, "Target", 0, dev )
        setVar( SWITCHSID, "Status", 0, dev )
    end
    setVar( DIMMERSID, "LoadLevelTarget", newVal, dev )
    setVar( DIMMERSID, "LoadLevelStatus", newVal, dev )
end

function actionSetColor( newVal, dev )
    assert(luup.devices[dev].device_type == BULBTYPE)
    setVar( COLORSID, "TargetColor", newVal, dev )
    local status = getVarNumeric( "Status", 0, dev, SWITCHSID )
    if status == 0 then
        sendDeviceCommand( "set_power", { "on", "smooth", 500 }, dev )
        setVar( SWITCHSID, "Target", 1, dev )
        setVar( SWITCHSID, "Status", 1, dev )
    end
    local w,c,r,g,b = 0,0,0,0,0
    local s = split( newVal )
    if #s == 3 then
        -- R,G,B
        r = tonumber(s[1])
        g = tonumber(s[2])
        b = tonumber(s[3])
        local rgb = r * 65536 + g * 256 + b
        sendDeviceCommand( "set_rgb", { rgb, "smooth", 500 }, dev )
        setVar( COLORSID, "CurrentColor", newVal, dev )
        setVar( MYSID, "HexColor", string.format("%02x%02x%02x", r, g, b), dev )
    else
        -- Wnnn, Dnnn (color range)
        local code,temp = newVal:upper():match( "([WD])(%d+)" )
        if code == "W" then
            w = tonumber(temp) or 128
            temp = 2000 + math.floor( w * 3500 / 255 )
        elseif code == "D" then
            c = tonumber(temp) or 128
            temp = 5500 + math.floor( c * 3500 / 255 )
        elseif code == nil then
            -- Try to evaluate as integer (2000-9000K)
            temp = tonumber(newVal) or 0
            if temp >= 2000 and temp <= 5500 then
                w = math.floor( ( temp - 2000 ) / 3500 * 255 )
            elseif temp > 5500 and temp <= 9000 then
                c = math.floor( ( temp - 5500 ) / 3500 * 255 )
            else
                L({level=1,msg="Unable to set color, target value %1 invalid"}, newVal)
                return
            end
        end
        sendDeviceCommand( "set_ct_abx", { temp, "smooth", 500 }, dev )
        -- Well this is... bizarre.
        setVar( COLORSID, "CurrentColor", string.format("0=%d,1=%d,2=%d,3=%d,4=%d", w, c, r, g, b), dev )
    end
end

-- Run Yeelight discovery
function jobRunDiscovery( pdev )
    if false and isOpenLuup then
        gatewayStatus( "SSDP discovery not available on openLuup; use IP discovery" )
        return 2,0
    end
    launchSSDPDiscovery( pdev )
    return 4,0
end

-- IP discovery. Connect/query, and if we succeed, add.
function jobDiscoverIP( pdev, addr )
    if devData[tostring(pdev)].discoverySocket then
        L{level=2,msg="SSDP discovery running, can't do direct IP discovery"}
        return 2,0
    end
    -- Clean and canonicalize
    addr = string.gsub( string.gsub( tostring(addr or ""), "^%s+", "" ), "%s+$", "" )
    local port
    D("jobDiscoverIP() checking %1", addr)
    addr,port = string.match( addr, "^([^:]+):(%d+)" )
    port = tonumber(port)
    if addr == nil or port == nil then
        gatewayStatus("Discovery IP invalid, must be A.B.C.D:port")
        return 2,0
    end
    L("Attempting direct IP discovery at %1:%2", addr, port)
    gatewayStatus("Contacting " .. addr)
    local sock = socket.tcp()
    if sock:connect( addr, port ) then
        sock:send("{ \"id\": 1, \"method\": \"get_prop\", \"params\": [ \"power\",\"id\",\"name\" ] }\r\n")
        sock:settimeout(5)
        local r,err = sock:receive()
        if r then
            D("jobDiscoverIP() got direct discovery response: %1", r)
            sock:close()
            local data = json.decode( r )
            if data and data.result then
                -- Looks real enough. We don't have an ID, so generate one.
                local pfx = string.char( 96 + math.random( 26 ) )
                local id = string.format( "%s%x", pfx, math.floor( socket.gettime() * 100 ) )
                local name = "yeelight" .. id
                devData[tostring(dev)].discoveryResponses = { [id]={ Id=id, Name=name, Address=addr..":"..port, Info={} } }
                processDiscoveryResponses( pdev )
                return 4,0
            end
        else
            D("jobDiscoverIP() receive error: %1", err)
            gatewayStatus("Invalid or no response from device at "..addr..":"..port)
        end
    else
        gatewayStatus("Can't connect to "..addr..":"..port)
    end
    sock:close()
    return 2,0
end

-- Enable or disable debug
function actionSetDebug( state, tdev )
    assert(tdev == pluginDevice) -- on master only
    if string.find( ":debug:true:t:yes:y:1:", string.lower(tostring(state)) ) then
        debugMode = true
    else
        local n = tonumber(state or "0") or 0
        debugMode = n ~= 0
    end
    if debugMode then
        D("Debug enabled")
    end
end

-- Dangerous debug stuff. Remove all child devices except bulbs.
function actionMasterClear( dev )
    assert( luup.devices[dev].device_type == MYTYPE )
    gatewayStatus( "Clearing children..." )
    local ptr = luup.chdev.start( pluginDevice )
    luup.sleep(5000) -- I would only ever do this here.
    luup.chdev.sync( pluginDevice, ptr )
end

--[[
    ***************************************************************************
    P L U G I N   B A S E
    ***************************************************************************
--]]
-- plugin_runOnce() looks to see if a core state variable exists; if not, a
-- one-time initialization takes place.
local function plugin_runOnce( pdev )
    local s = getVarNumeric("Version", 0, pdev, MYSID)
    if s ~= 0 and s == _CONFIGVERSION then
        -- Up to date.
        return
    elseif s == 0 then
        L("First run, setting up new plugin instance...")
        initVar( "Message", "", pdev, MYSID )
        initVar( "Enabled", "1", pdev, MYSID )
        initVar( "DebugMode", 0, pdev, MYSID )
        initVar( "DiscoveryBroadcast", "", pdev, MYSID )
        initVar( "UpdateInterval", "", pdev, MYSID )

        luup.attr_set('category_num', 1, pdev)

        luup.variable_set( MYSID, "Version", _CONFIGVERSION, pdev )
        return
    end

    -- Consider per-version changes.

    -- Update version last.
    if s ~= _CONFIGVERSION then
        luup.variable_set( MYSID, "Version", _CONFIGVERSION, pdev )
    end
end

-- Tick handler for master device
local function masterTick(pdev,taskid)
    D("masterTick(%1,%2)", pdev,taskid)
    assert(pdev == pluginDevice)
    -- Set default time for next master tick
    local nextTick = math.floor( os.time() / 60 + 1 ) * 60

    -- Do master tick work here

    -- Schedule next master tick.
    -- This plugin doesn't need one, so we let it die.
    -- scheduleTick( taskid, nextTick )
end

-- Start plugin running.
function startPlugin( pdev )
    L("plugin version %2, device %1 (%3)", pdev, _PLUGIN_VERSION, luup.devices[pdev].description)

    luup.variable_set( MYSID, "Message", "Initializing...", pdev )

    -- Early inits
    pluginDevice = pdev
    isALTUI = false
    isOpenLuup = false
    tickTasks = {}
    devData[tostring(pdev)] = {}

    math.randomseed( os.time() )

    -- Debug?
    if getVarNumeric( "DebugMode", 0, pdev, MYSID ) ~= 0 then
        debugMode = true
        D("startPlugin() debug enabled by state variable DebugMode")
    end

    -- Check for ALTUI and OpenLuup
    local failmsg = false
    for k,v in pairs(luup.devices) do
        if v.device_type == "urn:schemas-upnp-org:device:altui:1" and v.device_num_parent == 0 then
            D("start() detected ALTUI at %1", k)
            isALTUI = true
            --[[
            local rc,rs,jj,ra = luup.call_action("urn:upnp-org:serviceId:altui1", "RegisterPlugin",
                {
                    newDeviceType=MYTYPE,
                    newScriptFile="",
                    newDeviceDrawFunc="",
                    newStyleFunc=""
                }, k )
            D("startSensor() ALTUI's RegisterPlugin action for %5 returned resultCode=%1, resultString=%2, job=%3, returnArguments=%4", rc,rs,jj,ra, MYTYPE)
            --]]
        elseif v.device_type == "openLuup" then
            D("start() detected openLuup")
            isOpenLuup = true
        end
    end
    if failmsg then
        return false, failmsg, _PLUGIN_NAME
    end

    -- Check UI version
    if not checkVersion( pdev ) then
        L({level=1,msg="This plugin does not run on this firmware."})
        luup.variable_set( MYSID, "Message", "Unsupported firmware "..tostring(luup.version), pdev )
        luup.set_failure( 1, pdev )
        return false, "Incompatible firmware " .. luup.version, _PLUGIN_NAME
    end

    -- One-time stuff
    plugin_runOnce( pdev )

    -- More inits
    if not isEnabled( pdev ) then
        clearChildren( pdev )
        gatewayStatus("DISABLED")
        return true, "Disabled", _PLUGIN_NAME
    end

    -- Initialize and start the plugin timer and master tick
    runStamp = 1
    scheduleDelay( { id="master", func=masterTick, owner=pdev }, 5 )

    -- Start bulbs
    startBulbs( pdev )

    -- Return success
    gatewayStatus( nil )
    luup.set_failure( 0, pdev )
    return true, "Ready", _PLUGIN_NAME
end

-- Plugin timer tick. Using the tickTasks table, we keep track of tasks that
-- need to be run and when, and try to stay on schedule. This keeps us light on
-- resources: typically one system timer only for any number of devices.
local functions = { [tostring(masterTick)]="masterTick", [tostring(checkBulb)]="checkBulb", [tostring(checkBulbProp)]="checkBulbProp" }
function taskTickCallback(p)
    D("taskTickCallback(%1) pluginDevice=%2", p, pluginDevice)
    local stepStamp = tonumber(p,10)
    assert(stepStamp ~= nil)
    if stepStamp ~= runStamp then
        D( "taskTickCallback() stamp mismatch (got %1, expecting %2), newer thread running. Bye!",
            stepStamp, runStamp )
        return
    end

    if not isEnabled( pluginDevice ) then
        clearChildren( pluginDevice )
        gatewayStatus( "DISABLED" )
        return
    end

    local now = os.time()
    local nextTick = nil
    tickTasks._plugin.when = 0

    -- Since the tasks can manipulate the tickTasks table, the iterator
    -- is likely to be disrupted, so make a separate list of tasks that
    -- need service, and service them using that list.
    local todo = {}
    for t,v in pairs(tickTasks) do
        if t ~= "_plugin" and v.when ~= nil and v.when <= now then
            -- Task is due or past due
            D("taskTickCallback() inserting eligible task %1 when %2 now %3", v.id, v.when, now)
            v.when = nil -- clear time; timer function will need to reschedule
            table.insert( todo, v )
        end
    end

    -- Run the to-do list.
    D("taskTickCallback() to-do list is %1", todo)
    for _,v in ipairs(todo) do
        D("taskTickCallback() calling task function %3(%4,%5) for %1 (%2)", v.owner, (luup.devices[v.owner] or {}).description, functions[tostring(v.func)] or tostring(v.func),
            v.owner,v.id)
        local success, err = pcall( v.func, v.owner, v.id, v.args )
        if not success then
            L({level=1,msg="Yeelight device %1 (%2) tick failed: %3"}, v.owner, (luup.devices[v.owner] or {}).description, err)
        else
            D("taskTickCallback() successful return from %2(%1)", v.owner, functions[tostring(v.func)] or tostring(v.func))
        end
    end

    -- Things change while we work. Take another pass to find next task.
    for t,v in pairs(tickTasks) do
        if t ~= "_plugin" and v.when ~= nil then
            if nextTick == nil or v.when < nextTick then
                nextTick = v.when
            end
        end
    end

    -- Have we been disabled?
    if not isEnabled( pluginDevice ) then
        gatewayStatus("DISABLED")
        return
    end

    -- Figure out next master tick, or don't resched if no tasks waiting.
    if nextTick ~= nil then
        D("taskTickCallback() next eligible task scheduled for %1", os.date("%x %X", nextTick))
        now = os.time() -- Get the actual time now; above tasks can take a while.
        local delay = nextTick - now
        if delay < 1 then delay = 1 end
        tickTasks._plugin.when = now + delay
        D("taskTickCallback() scheduling next tick(%3) for %1 (%2)", delay, tickTasks._plugin.when,p)
        luup.call_delay( "yeelightTaskTick", delay, p )
    else
        D("taskTickCallback() not rescheduling, nextTick=%1, stepStamp=%2, runStamp=%3", nextTick, stepStamp, runStamp)
        tickTasks._plugin.when = nil
    end
end

-- Watch callback. Dispatches to child-specific handling.
function watchCallback( dev, sid, var, oldVal, newVal )
    D("watchCallback(%1,%2,%3,%4,%5)", dev, sid, var, oldVal, newVal)
    assert(var ~= nil) -- nil if service or device watch (can happen on openLuup)
end

local EOL = "\r\n"

local function getDevice( dev, pdev, v )
    if v == nil then v = luup.devices[dev] end
    if json == nil then json = require("dkjson") end
    local devinfo = {
          devNum=dev
        , ['type']=v.device_type
        , description=v.description or ""
        , room=v.room_num or 0
        , udn=v.udn or ""
        , id=v.id
        , parent=v.device_num_parent or pdev
        , ['device_json'] = luup.attr_get( "device_json", dev )
        , ['impl_file'] = luup.attr_get( "impl_file", dev )
        , ['device_file'] = luup.attr_get( "device_file", dev )
        , manufacturer = luup.attr_get( "manufacturer", dev ) or ""
        , model = luup.attr_get( "model", dev ) or ""
    }
    local rc,t,httpStatus,uri
    if isOpenLuup then
        uri = "http://localhost:3480/data_request?id=status&DeviceNum=" .. dev .. "&output_format=json"
    else
        uri = "http://localhost/port_3480/data_request?id=status&DeviceNum=" .. dev .. "&output_format=json"
    end
    rc,t,httpStatus = luup.inet.wget(uri, 15)
    if httpStatus ~= 200 or rc ~= 0 then
        devinfo['_comment'] = string.format( 'State info could not be retrieved, rc=%s, http=%s', tostring(rc), tostring(httpStatus) )
        return devinfo
    end
    local d = json.decode(t)
    local key = "Device_Num_" .. dev
    if d ~= nil and d[key] ~= nil and d[key].states ~= nil then d = d[key].states else d = nil end
    devinfo.states = d or {}
    return devinfo
end

local function alt_json_encode( st )
    str = "{"
    local comma = false
    for k,v in pairs(st) do
        str = str .. ( comma and "," or "" )
        comma = true
        str = str .. '"' .. k .. '":'
        if type(v) == "table" then
            str = str .. alt_json_encode( v )
        elseif type(v) == "number" then
            str = str .. tostring(v)
        elseif type(v) == "boolean" then
            str = str .. ( v and "true" or "false" )
        else
            str = str .. string.format("%q", tostring(v))
        end
    end
    str = str .. "}"
    return str
end

function handleLuupRequest( lul_request, lul_parameters, lul_outputformat )
    D("request(%1,%2,%3) luup.device=%4", lul_request, lul_parameters, lul_outputformat, luup.device)
    local action = lul_parameters['action'] or lul_parameters['command'] or ""
    local deviceNum = tonumber( lul_parameters['device'], 10 )
    if action == "debug" then
        debugMode = not debugMode
        D("debug set %1 by request", debugMode)
        return "Debug is now " .. ( debugMode and "on" or "off" ), "text/plain"

    elseif action == "status" then
        local st = {
            name=_PLUGIN_NAME,
            plugin=_PLUGIN_ID,
            version=_PLUGIN_VERSION,
            configversion=_CONFIGVERSION,
            author="Patrick H. Rigney (rigpapa)",
            url=_PLUGIN_URL,
            ['type']=MYTYPE,
            responder=luup.device,
            timestamp=os.time(),
            system = {
                version=luup.version,
                isOpenLuup=isOpenLuup,
                isALTUI=isALTUI
            },
            devices={}
        }
        for k,v in pairs( luup.devices ) do
            if v.device_type == MYTYPE or v.device_num_parent == pluginDevice then
                local devinfo = getDevice( k, pluginDevice, v ) or {}
                if k == pluginDevice then
                    devinfo.tickTasks = tickTasks
                    devinfo.devData = devData
                end
                table.insert( st.devices, devinfo )
            end
        end
        return alt_json_encode( st ), "application/json"

    else
        error("Not implemented: " .. action)
    end
end

-- Return the plugin version string
function getPluginVersion()
    return _PLUGIN_VERSION, _CONFIGVERSION
end
