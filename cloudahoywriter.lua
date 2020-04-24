-----------------------------------------------
-- CloudAhoy Writer
--  Original Python by Adrian Velicu
--  Lua version by Phil Verghese
-----------------------------------------------
local versionNum = '0.0.1'

require('graphics')

-- Data Table
--   Structure
--      - csvField: name of CloudAhoy CSV field
--      - dataRefs: names of X-Plane datarefs. Sometimes multiple datarefs
--                      have to be looked at to find which one is set. The
--                      list is traversed in the order declared.
--      - varNames: names of variables mapped to the dataRefs. Must be same
--                      length as dataRefs. These are globals, so prefix with
--                      CAWR_.
--      - conversion: optional function to convert units from datarefs to CSV
--                        (e.g. meters to feet). Only one per csvField.
local dataTable = {
    {
        csvField='seconds/t',
        dataRefs={'sim/time/total_flight_time_sec'},
        varNames={'CAWR_flightTimeSec'},
    },
    {
        csvField='degrees/LAT',
        dataRefs={'sim/flightmodel/position/latitude'},
        varNames={'LATITUDE'},
    },
    {
        csvField='degrees/LON',
        dataRefs={'sim/flightmodel/position/longitude'},
        varNames={'LONGITUDE'},
    },
    {
        csvField='feet/ALT (GPS)',
        dataRefs={'sim/flightmodel/position/elevation'},
        varNames={'ELEVATION'},
        conversion='CAWR_meters_to_feet',
    },
    {
        csvField='ft Baro/AltB',
        dataRefs={'sim/cockpit2/gauges/indicators/altitude_ft_pilot'},
        varNames={'CAWR_indAlt'},
    },
    {
        csvField='knots/GS',
        dataRefs={'sim/flightmodel/position/groundspeed'},
        varNames={'CAWR_groundSpeed'},
        conversion='CAWR_mps_to_knots',
    },
    {
        csvField='knots/IAS',
        dataRefs={'sim/flightmodel/position/indicated_airspeed'},
        varNames={'CAWR_indicatedSpeed'},
    },
    {
        csvField='knots/TAS',
        dataRefs={'sim/flightmodel/position/true_airspeed'},
        varNames={'CAWR_trueSpeed'},
        conversion='CAWR_mps_to_knots',
    },
    {
        csvField='degrees/HDG',
        dataRefs={'sim/flightmodel/position/mag_psi'},
        varNames={'CAWR_heading'},
    },
    {
        csvField='degrees/MagVar',
        dataRefs={'sim/flightmodel/position/magnetic_variation'},
        varNames={'CAWR_magVar'},
    },
    {
        csvField='degrees/Pitch',
        dataRefs={'sim/flightmodel/position/true_theta'},
        varNames={'CAWR_degreesPitch'},
    },
    {
        csvField='degrees/Roll',
        dataRefs={'sim/flightmodel/position/true_phi'},
        varNames={'CAWR_degreesRoll'},
    },
    {
        csvField='degrees/Yaw',
        dataRefs={'sim/flightmodel/position/beta'},
        varNames={'CAWR_degreesYaw'},
    },
    {
        csvField='degrees/TRK',
        dataRefs={'sim/cockpit2/gauges/indicators/ground_track_mag_pilot'},
        varNames={'CAWR_degreesTrack'},
    },

}

function CAWR_meters_to_feet(meters)
    return meters * 3.281
end

function CAWR_mps_to_knots(mps)
    return mps * 1.944
end

local function initialize_datarefs()
    for i,v in ipairs(dataTable) do
        print('csvField=' .. v.csvField)

        for i=1,#v.dataRefs do
            print('  dataRef=' .. v.dataRefs[i])
            print('  varName=' .. v.varNames[i])
            if string.find(v.varNames[i], 'CAWR_') then
                -- Only register variables that start with our prefix. Some dataRefs
                -- we want are already registered by FWL (e.g. ELEVATION, LATITUDE).
                DataRef(v.varNames[i], v.dataRefs[i])
            end
        end
        if v.conversion then print('  conversion=' .. v.conversion) end
    end

    print('CAWR_flightTimeSec=' .. CAWR_flightTimeSec)
    print('CAWR_indAlt=' .. CAWR_indAlt)
    print('LATITUDE=' .. LATITUDE)
    print('LONGITUDE=' .. LONGITUDE)
    print('ELEVATION=' .. ELEVATION)
    print('   converted ' .. _G['CAWR_meters_to_feet'](ELEVATION))
    print('CAWR_indAlt=' .. CAWR_indAlt)
end

-- Constants
local SECONDS_PER_MINUTE = 60
local SECONDS_PER_HOUR = SECONDS_PER_MINUTE * 60
local FLIGHTDATA_DIRECTORY_NAME = 'flightdata'
local OUTPUT_PATH_NAME =  SYSTEM_DIRECTORY .. 'Output/' .. FLIGHTDATA_DIRECTORY_NAME

-- State
local enable_auto_hide = true
local lua_run_counter = LUA_RUN -- Increments when aircraft or start position changes
local recording_start_time = nil
local recording_display_time = '0:00:00'

-- Bounds for control box
local width = measure_string('X9:99:99X')
local height = 90
local cawr_width = measure_string('CAWR')
local x1 = 0
local x2 = x1 + width
local y1 = (SCREEN_HIGHT / 2) - 50
local y2 = y1 + height
local centerX = x1 + (width / 2)
local centerY = y1 + ((y2 - y1) / 2)

-- background color
local bgR = 0.2
local bgG = 0.2
local bgB = 0.2
local bgA = 0.8

-- foreground color
local fgR = 0.8
local fgG = 0.8
local fgB = 0.8
local fgA = 0.8

-- recording off color
local recOffR = 0.05
local recOffG = 0.05
local recOffB = 0.05
local recOffA = 0.8

-- recording on color
local recOnR = 0.9
local recOnG = 0.2
local recOnB = 0.2
local recOnA = 0.8

local function write_csv_header(start_time)
    -- Metadata
    io.write('Metadata,CA_CSV.3\n')
    io.write(string.format('GMT,%d\n', start_time))
    io.write('TAIL,*UNK\n')
    io.write('GPS,XPlane\n')
    io.write('ISSIM,1\n')
    io.write('DATA,\n')

    -- Column identifiers
    local trailing_char = ','
    for i,v in ipairs(dataTable) do
        if i == #dataTable then trailing_char = '\n' end
        io.write(string.format('%s%s', v.csvField, trailing_char))
    end
end

local function start_recording()
    assert(recording_start_time == nil, 'start_recording called in wrong state')
    local start_time = os.time()
    local times = os.date('*t', start_time)
    local output_filename = string.format('CAWR-%4d-%02d-%02d_%02d-%02d-%02d.csv',
        times.year, times.month, times.day, times.hour, times.min, times.sec)
    io.output(OUTPUT_PATH_NAME .. '/' .. output_filename)
    write_csv_header(start_time)

    -- Don't set this until the header is written to avoid a race with the code that
    -- writes the data after the header.
    recording_start_time = start_time
end

local function stop_recording()
    assert(recording_start_time ~= nil, 'stop_recording called in wrong state')
    recording_start_time = nil
    io.close()
end

local function toggle_recording_state()
    if recording_start_time == nil then
        start_recording()
    else
        stop_recording()
    end
end

local function get_recording_display_time()
    if recording_start_time == nil then return '0:00:00' end
    local current_time = os.time()

    local elapsed_seconds = current_time - recording_start_time
    local hours = math.floor(elapsed_seconds / SECONDS_PER_HOUR)
    elapsed_seconds = elapsed_seconds - (hours * SECONDS_PER_HOUR)
    local minutes = math.floor(elapsed_seconds / SECONDS_PER_MINUTE)
    elapsed_seconds = elapsed_seconds - (minutes * SECONDS_PER_MINUTE)
    local seconds = math.floor(elapsed_seconds)

    return string.format('%01d:%02d:%02d', hours, minutes, seconds)
end

function CAWR_show_ui()
    if enable_auto_hide and (MOUSE_X > width * 3) then
        return
    end

    XPLMSetGraphicsState(0, 0, 0, 1, 1, 0, 0)

    -- Background rectangle
    graphics.set_color(bgR, bgG, bgB, bgA)
    graphics.draw_rectangle(x1, y1, x2, y2)

    -- Foreground lines and text
    graphics.set_color(fgR, fgG, fgB, fgA)
    draw_string(centerX - (cawr_width / 2), y2 - 16, 'CAWR')
    graphics.set_width(2)
    graphics.draw_line(x1, y2, x2, y2)
    graphics.draw_line(x1, y2 - 30, x2, y2 - 30)
    graphics.draw_line(x1 + 1, y2, x1 + 1, y1)
    graphics.draw_line(x2, y2, x2, y1)
    graphics.draw_line(x1, y1, x2, y1)

    -- Recording circle
    if (recording_start_time ~= nil) then
        graphics.set_color(recOnR, recOnG, recOnB, recOnA)
        recording_display_time = get_recording_display_time()
    else
        graphics.set_color(recOffR, recOffG, recOffB, recOffA)
    end
    graphics.draw_filled_circle(centerX, centerY - 5, 12)
    graphics.set_color(fgR, fgG, fgB, fgA)
    graphics.draw_circle(centerX, centerY - 5, 12, 2)

    -- Recording time
    draw_string(centerX - (measure_string(recording_display_time) / 2),
        y1 + 10, recording_display_time)
end

function CAWR_on_mouse_click()
    if MOUSE_X < x1 or MOUSE_X > x2 then return end
    if MOUSE_Y < y1 or MOUSE_Y > y2 then return end
    if MOUSE_STATUS == 'up' then
        toggle_recording_state()
    end

    RESUME_MOUSE_CLICK = true -- consume click
end

-- Creates the 'Output/flightdata' directory if it doesn't exist.
local function create_output_directory()
    local output_directory = SYSTEM_DIRECTORY .. 'Output' -- X-plane Output
    local output_contents = directory_to_table(output_directory)
    for i, name in ipairs(output_contents) do
        if name == FLIGHTDATA_DIRECTORY_NAME then
            return
        end
    end
    local mkdir_command = 'mkdir "' .. output_directory
            .. '/' .. FLIGHTDATA_DIRECTORY_NAME .. '"'
    print('executing: ' .. mkdir_command)
    os.execute(mkdir_command)
end

function CAWR_write_data()
    if not recording_start_time then return end
    local trailing_char = ','
    for i,v in ipairs(dataTable) do
        if i == #dataTable then trailing_char = '\n' end
        -- TODO: handle multiple data values and finding the best one
        --       This is always going to pick the first one.
        local data_value = _G[v.varNames[1]] or 0
        if v.conversion then data_value = _G[v.conversion](data_value) end
        io.write(data_value)
        io.write(trailing_char)
    end
end

function CAWR_do_sometimes()
    if not recording_start_time then return end
    io.flush()
end

local function main()
    create_output_directory()
    initialize_datarefs()
end

main()
do_every_draw('CAWR_show_ui()')
do_on_mouse_click('CAWR_on_mouse_click()')
do_often('CAWR_write_data()')
do_sometimes('CAWR_do_sometimes()')