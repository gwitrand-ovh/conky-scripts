#!/usr/bin/env lua

local config

function _load_config(path)
    local _env = {}
    setmetatable(_env, {
        __index = _G
    })
    local f = loadfile(path, "t", _env)
    if not f then
        return {}
    end
    assert(pcall(f))
    setmetatable(_env, nil)
    return _env
end

function conky_startup()
    local config_path = os.getenv("PWD") .. "/" .. conky_config
    print("conky: Loading config from " .. config_path .. "...")
    config = _load_config(config_path)
    print("conky: Script has started and is now runing!")
end

function conky_main()
    if conky_window == nil then
        return
    end
end

function conky_cpu()
    local cpu = tonumber(conky_parse('${cpu cpu0}'))
    if cpu < 10 then
        return "   " .. cpu .. " %"
    elseif cpu == 100 then
        return cpu .. " %"
    else
        return " " .. cpu .. " %"
    end
end

function conky_power()
    if io.open("/proc/acpi/battery/BAT0", "r") == nil and io.open("/sys/class/power_supply/BAT0", "r") == nil then
        return "N/A"
    end
    local battery_percent = conky_parse('${battery_percent}')
    local acpi_ac_adapter = conky_parse('${acpiacadapter}')
    if acpi_ac_adapter == "on-line" and battery_percent ~= "100" then
        return battery_percent .. "% (Charging)"
    elseif acpi_ac_adapter == "on-line" and battery_percent == "100" then
        return "Charged"
    elseif acpi_ac_adapter ~= "on-line" and battery_percent ~= "0" then
        return battery_percent .. "% (Discharging)"
    elseif acpi_ac_adapter ~= "on-line" and battery_percent == "0" then
        return "Error"
    end
    return "N/A"
end

function _query(url, method)
    -- http = require("socket.http")
    http = require("ssl.https")
    local json = require("json")

    local fnret = ""
    function collect(chunk)
        if chunk ~= nil then
            fnret = fnret .. chunk
        end
        return true
    end

    local _, statusCode, headers, statusText = http.request {
        url = url,
        method = method,
        headers = {
            ["Accept"] = "application/json",
            ["Accept-Language"] = "sk;q=0.8,en-US,en;q=0.6,cs;q=0.4",
            ["Accept-Charset"] = "UTF-8;q=0.8,*;q=0.7"
        },
        sink = collect
    }
    return json.decode(fnret)
end

function _query_get(url)
    return _query(url, "GET")
end

function _command(cmd, idx)
    local handle = io.popen(cmd .. " 2>/dev/null")
    -- local fnret = handle:read("*all")
    local fnret = {}
    for line in handle:lines() do
        fnret[#fnret] = line
        if idx == #fnret then
            return line
        end
    end
    handle:close()
    return fnret
end

function conky_arch()
    return _command("arch", 0)
end

function conky_arch()
    return _command("arch", 0)
end

function conky_version_os()
    return _command("lsb_release -ds", 0)
end

function conky_version_gs()
    local fnret = _command("gnome-shell --version", 0)
    local version, occurencies = string.gsub(fnret, "GNOME Shell ", "")
    return version
end

function _round(num, decimalPlaces)
    local mult = 10 ^ (decimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end

function _currency2smbol(currency)
    local currency2smbol = {
        EUR = "€", --
        DOL = "$"
    }
    if currency2smbol[currency] == nil then
        return ""
    end
    return currency2smbol[currency]
end

function conky_auction()
    local url = "https://query1.finance.yahoo.com/v8/finance/chart/" .. helper.config.auction.code .. "?region=" .. helper.config.auction.region .. "&lang=" .. helper.config.auction.language .. "&interval=1m&range=1h"
    local fnret = _query_get(url).chart.result

    local regularMarketPrice = fnret[1].meta.regularMarketPrice
    local previousClose = fnret[1].meta.previousClose
    local currency = _currency2smbol(fnret[1].meta.currency)
    local symbol = fnret[1].meta.symbol
    local diff = _round(regularMarketPrice - previousClose, 2)
    regularMarketPrice = _round(regularMarketPrice, 2)

    local prefix = conky_parse("$font6${color0}") .. symbol .. conky_parse("${offset 8}$color")
    if diff < 0 then
        return prefix .. regularMarketPrice .. currency .. " " .. conky_parse("$color$font${voffset -10}${font9}${color " .. helper.config.auction.negativeColor .. "}") .. diff .. currency .. conky_parse("${voffset 10}$color")
    elseif diff > 0 then
        return prefix .. regularMarketPrice .. currency .. " " .. conky_parse("$color$font${voffset -10}${font9}${color " .. helper.config.auction.positiveColor .. "}") .. "+" .. diff .. currency .. conky_parse("${voffset 10}$color")
    else
        return prefix .. regularMarketPrice .. currency
    end
end

function _local_ip(version)
    local family = (version and "inet" .. (version == 6 and version or "") or "inet")
    local ips = {}

    if (version == nil or version == 4) then
        local fnretIp4 = _query_get("https://api.ipify.org/?format=json")
        if fnretIp4 then
            ips[#ips + 1] = {
                value = fnretIp4.ip .. "/32",
                version = 4,
                key = "WAN"
            }
        end
    end

    if (version == nil or version == 6) then
        local fnretIp6 = _query_get("https://api64.ipify.org/?format=json")
        if fnretIp6 then
            ips[#ips + 1] = {
                value = fnretIp6.ip .. "/128",
                version = 6,
                key = "WAN"
            }
        end
    end

    local json = require("json")
    local net_interfaces = json.decode(_command("ip -j address", 0))
    for k, net_interface in ipairs(net_interfaces) do
        if net_interface.operstate == "UNKNOWN" or net_interface.operstate == "UP" then
            local if_name = net_interface.ifname
            local addr_infos = net_interface.addr_info
            for k, addr_info in ipairs(addr_infos) do
                if addr_info["local"] ~= nil and addr_info.scope == "global" and (version == nil or addr_info.family == family) then
                    local ip = {}
                    ip.key = if_name
                    if addr_info.label ~= nil then
                        ip.key = addr_info.label
                    end
                    if version == nil and addr_info.family == "inet6" then
                        ip.version = 6
                    elseif version == nil then
                        ip.version = 4
                    end
                    ip.value = addr_info["local"] .. "/" .. addr_info.prefixlen
                    ips[#ips + 1] = ip
                end
            end
        end
    end

    return ips
end

function _debug_dump(o)
    if type(o) == "table" then
        local s = "{ "
        for k, v in pairs(o) do
            if type(k) ~= "number" then
                k = "\"" .. k .. "\""
            end
            s = s .. "[" .. k .. "] = " .. _dump(v) .. ","
        end
        return s .. "} "
    else
        return tostring(o)
    end
end

function _table_has_value(tab, val)
    for _, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end

function _merge(...)
    local result = {}
    local k = 1
    for _, t in ipairs {...} do
        for _, v in ipairs(t) do
            result[k] = v
            k = k + 1
        end
    end
    return result
end

function _add_attribute_value(table, attribute, value)
    for _, item in ipairs(table) do
        item[attribute] = (item.attribute and item.attribute or value)
    end
    return table
end

function _sort_routes(a, b)
    local ametric = (a.metric and a.metric or 0)
    ametric = (ametric == "default" and ametric - 1 or ametric)
    local bmetric = (b.metric and b.metric or 0)
    bmetric = (bmetric == "default" and bmetric - 1 or bmetric)
    if ametric == bmetric then
        bmetric = (a.dst == "default" and bmetric + 1 or bmetric)
        ametric = (b.dst == "default" and ametric + 1 or ametric)
    end
    return ametric < bmetric
end

function _local_routes(version)
    local routes = {}

    local json = require("json")
    local net_routesv4 = _add_attribute_value(json.decode(_command("ip -j route", 0)), "version", 4)
    local net_routesv6 = _add_attribute_value(json.decode(_command("ip -j -6 route", 0)), "version", 6)
    local net_routes = _merge(net_routesv4, net_routesv6)
    table.sort(net_routes, _sort_routes)
    for k, net_route in ipairs(net_routes) do
        if not _table_has_value(net_route.flags, "linkdown") and net_route.dev ~= "lo" and (not version or net_route.version == version) then
            local route = {}
            route.key = net_route.dev
            route.value = net_route.dst
            if route.value == "default" then
                route.value = (net_route.version == 4 and "0.0.0.0/0" or "::/0")
            end
            route.metric = (net_route.metric and net_route.metric or 0)
            if not version then
                route.version = net_route.version
            end
            routes[#routes + 1] = route
        end
    end
    return routes
end

function _table_format(items, width)
    local str_output = ""
    width = (width and width or helper.config.maxChars)
    local old_cursor_len = 0
    for _, item in ipairs(items) do
        local cursor = conky_parse("${offset 8}$color0") .. item.key .. conky_parse("$color${offset 8}") .. item.value .. conky_parse("$color${offset 20}")
        if old_cursor_len + #cursor > width then
            cursor = cursor .. "\n"
            old_cursor_len = 0
        end
        old_cursor_len = old_cursor_len + #cursor
        str_output = str_output .. cursor
    end
    return str_output
end

function conky_local_ip()
    return _table_format(_local_ip())
end

function conky_local_routes()
    return _table_format(_local_routes())
end

_debug_dump(conky_auction())
