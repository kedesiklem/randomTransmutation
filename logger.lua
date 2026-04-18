---@class logger
local logger = {}

logger.mod_name = "RandomTransmutation"
RandomTransmutation_RELEASE = true

local ERROR = 0
local WARN = 1
local INFO = 2
local DEBUG = 3


local CURRENT_LOG_MODE = DEBUG

if RandomTransmutation_RELEASE then
    CURRENT_LOG_MODE = ERROR
end

-- Get current timestamp in HH:MM:SS format
local function get_timestamp()
    local year, month, day, hour, minute, second = GameGetDateAndTimeLocal()
    return string.format("%02d:%02d:%02d", hour, minute, second)
end

-- Log basique
function logger.log(text)
    print("[" .. get_timestamp() .. "] [" .. logger.mod_name .. "] " .. text)
end

-- Log for different levels
function logger.debug(text)
    if(CURRENT_LOG_MODE >= DEBUG) then
        logger.log("[DEBUG] " .. text)
    end
end

function logger.info(text)
    if(CURRENT_LOG_MODE >= INFO) then
        logger.log("[INFO] " .. text)
    end
end

function logger.warn(text)
    if(CURRENT_LOG_MODE >= WARN) then
        logger.log("[WARN] " .. text)
    end
end

function logger.error(text)
    if(CURRENT_LOG_MODE >= ERROR) then
        print_error("[" .. get_timestamp() .. "] [" .. logger.mod_name .. "] [ERROR] " .. text)
    end
end

-- Deferred logging
local buffer = {}

local level_handlers = {
    [DEBUG] = logger.debug,
    [INFO]  = logger.info,
    [WARN]  = logger.warn,
    [ERROR] = logger.error,
}

local function buffer_push(level, text)
    table.insert(buffer, { level = level, text = text })
end

function logger.tmp_debug(text) buffer_push(DEBUG, text) end
function logger.tmp_info(text)  buffer_push(INFO,  text) end
function logger.tmp_warn(text)  buffer_push(WARN,  text) end
function logger.tmp_error(text) buffer_push(ERROR, text) end

function logger.flush()
    for _, entry in ipairs(buffer) do
        local handler = level_handlers[entry.level]
        if handler then handler(entry.text) end
    end
    buffer = {}
end

function logger.clear()
    buffer = {}
end


return logger