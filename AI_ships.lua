g_savedata = {}
g_zones = {}
g_zones_hospital = {}
g_output_log = {}
g_objective_update_counter = 0
g_damage_tracker = {}

function Ship(ship_data) return {
    crew = {},
    tasks = {}, --task priority: 0 for emergencies, 1 for urgent, 2 for normal, 3 for routine/maintenance, math.huge for idle (crewmembers only)
    states = {
        addon_information = {}, --includes the vehicle ID
        sensors = {}, --external sensor input (speed, GPS, etc)
        onboard_information = {}, --onboard states such as whether the lights are on
    },
	map_markers = {},
    init = function(self, ship_data)        
        --initialize the sensor readings
        for sensor_id, sensor_name in ipairs(ship_data.sensors) do 
            self.states.sensors[sensor_name] = {id = sensor_id, value=0}
			debugLog('Created sensor '..sensor_name..' with ID '..sensor_id)
        end 

        --Spawn the objects
        --TODO: we'll see

        --need:
        --spawn zone transform DONE
        --location - refers to filesystem location with playlist and location index 
        --object descriptor (this is all in g_savedata.valid_ships[ship_name].objects)
        --parent_vehicle_id should be 0 or nil
        --  for crew, should be spawned_objects[0].id 
		
        local spawned_objects = {}
		local spawn_transform = ship_data.spawn_transform
		local location = ship_data.location()
		local object = location.objects.main_vehicle_component
		local parent_vehicle_id = nil
		
        
        --spawn the ship 
        spawnObject(spawn_transform, location, object, parent_vehicle_id, spawned_objects, g_savedata.spawned_objects)


        --spawn all of the crewmembers associated with the ship
        self.crew = ship_data.crew
		
		local parent_vehicle_id = spawned_objects[1].id
		local objects = location.objects.crew
        for _, crewmember in pairs(self.crew) do 
			--Make sure we're spawning the crewmember with the correct name 
			for index,potential_crewmember in pairs(objects) do 
				if potential_crewmember.display_name == crewmember.role then 
					spawnObject(spawn_transform, location, potential_crewmember, parent_vehicle_id, spawned_objects, g_savedata.spawned_objects)
					crewmember.id = spawned_objects[#spawned_objects].id
					break 
				end 
			end 

		end 
		printTable(self.crew, 'Crew		')
		--printTable(spawned_objects, 'spawned objects')

        self.states.addon_information.id = parent_vehicle_id 
		debugLog('Parent vehicle ID: '..self.states.addon_information.id)
        self.states.addon_information.transform = spawn_transform
        self.states.addon_information.popups = {}
		self.states.addon_information.sim = {}
		self.states.addon_information.name = ship_data.name

		if server.getVehicleSimulating(self.states.addon_information.id) then
			self.states.addon_information.sim.state = 'loaded'
		else 
			self.states.addon_information.sim.state = 'unloaded'
		end 

    end,

    tick = function(self)
		--update the vehicle's position
		local transform, is_success = server.getObjectPos(self.states.addon_information.id)
		self.states.addon_information.transform = transform
		if not is_success then debugLog('Failed to update position') end 

        --update all sensors and onboard statuses
        for sensor_name, sensor_data in pairs(self.states.sensors) do 
            local values, is_success = server.getVehicleDial(self.states.addon_information.id, 'sensor'..tostring(sensor_data.id))
			if is_success then 
				sensor_data.value = values['value']
			else 
				--debugLog('failed to get value for sensor '..sensor_name..' with ID '..sensor_data.id)
			end 
        end 

        --loop through ongoing tasks and call each in turn
        for k, task in pairs(self.tasks) do 
            local is_complete = false 
            task.task_data, is_complete = g_tasks[task.task_name]:tick(task.task_data, self.states)
            if is_complete then 
                --Return crew states to idle 
                for crew_name, crewmember in pairs(task.task_data.assigned_crew) do 
                    crewmember:complete_task()
                end
                self.tasks[k] = nil --remove the completed task 
            end 
        end

		for _,crewmember in pairs(self.crew) do 
			crewmember:tick(self.states.addon_information.id)
		end 
    end,

    create_task = function(self, task_name) --task is a string with the variable name of the task
        --Check to make sure task doesn't already exist

        --Create the task
        local task_data = g_tasks[task_name].init

        --Populate the task with crewmembers
        for _,role in pairs(task_data.required_crew) do 
            local found = false 
            for crew_name, crew_object in pairs(self.crew) do 
                if crew_object.role == role then 
                    task_data.assigned_crew[role] = crew_object --!! not sure if I should use the name or the object here
					debugLog('Assigned '..role.. ' to task '..task_name)
					found = true 
                end 

                if found then break end 
            end 
        end 
		debugLog('Created task '..task_name)
		printTable(task_data, 'Task data ')
        --Store the task in the ship's tasks table
        table.insert(self.tasks, {task_name = task_name, task_data = task_data}) --'task_name' is the variable name of the task (eg, g_tasks.turn_on_the_lights).
    end,

	on_vehicle_load = function(self)
		self.states.addon_information.sim.state = 'loaded'
	end,

	on_vehicle_unload = function(self)
		self.states.addon_information.sim.state = 'unloaded'
	end,

	rebuild_ui = function(self)
		--if self.states.addon_information.sim.state == 'loaded' then 
			local pos = self.states.addon_information.transform 
			printTable(pos, 'Current Location')
			local marker_x, marker_y, marker_z = matrix.position(pos)
			addMarker(self, createTutorialMarker(marker_x, marker_z, self.states.addon_information.name, ''))

		--end 
	end,

	--debug function to print sensor data
	print_sensor_data = function(self)
		for sensor_name, sensor_data in pairs(self.states.sensors) do 
			debugLog(sensor_name..': '..sensor_data.value)
		end
	end,



}
end 

-- CLOCK = server.getTime()
-- CLOCK = {
-- ["hour"] = hour (24),
-- ["minute"] = minute (60),
-- ["daylight_factor"] = midday factor (0-1),
-- ["percent"] = day_cycle_percent (0-1),
-- }

function parseTimeFactorToHM(factor)
	local minutes_in_a_day = 60 * 24
	local total_minutes = math.floor(factor * minutes_in_a_day)
	local minutes = total_minutes % 60
	local hours = math.tointeger((total_minutes - minutes) / 60)

	return string.format('%02d:%02d',hours,minutes)
end 

function parseTimeHMToFactor(timestring)
	local hours, minutes = timestring:match("([^:]+):([^:]+)")
	local hours, minutes = tonumber(hours), tonumber(minutes)

	local factor = (hours / 24) + (minutes / (60 * 24))
	return factor 
end 

-- Generator function for routines
function routine(time,location) return {time=parseTimeHMToFactor(time),location=location} end
-- List of seats and beds with corresponding times 
g_crew_routines = {
	officer_of_the_deck = {
		routine('08:00', 'Captain'),
		routine('20:00', 'idle1'),
		routine('23:00', 'bed1'),
	},
	engineer = {
		routine('07:15', 'idle2'),
		routine('08:00', 'Engineer'),
		routine('20:05', 'idle2'),
		routine('23:00', 'bed2'),
	},
}

-- routine: string representing the index of a routine in g_crew_routines
function Crew(role, routine) return { 
    role = role,
	routine = g_crew_routines[routine],
    current_task = {t = 'routine', priority = math.huge, location = g_crew_routines[routine][1].location}, --default task is 'routine',
	id = 0,

    assign_to_task = function(self, task_name, task_priority)
        --Check if crewmember is already performing the task
        if task_name == self.current_task.t then return true end

        --Check for priority levels - if new task is higher priority (lower priority # than old task), the old task is overridden
        debugLog(self.role..': Current task priority: '..self.current_task.priority..', New task priority: '..task_priority)
		if self.current_task.priority > task_priority then 
            self.current_task.t = task_name 
            self.current_task.priority = task_priority
            return true 
        end 
        return false 
    end,

    complete_task = function(self)
        self.current_task.t = 'routine'
        self.current_task.priority = math.huge 
        return true
    end,

    tick = function(self, vehicle_id)
		--Cycle crewmember through daily routine
        if self.current_task.t == 'routine' then 
			local time_pct = server.getTime().percent
			for index,routine in pairs(self.routine) do 
				if routine.time <= time_pct then 
					self.current_task.location = routine.location 
				elseif (routine.time >= time_pct) and index == 1 then 
					--Correctly handle the case when the vehicle spawns before the first routine in the list
					self.current_task.location = self.routine[#self.routine].location
				else break 
				end
			end 

			server.setCharacterSeated(self.id, vehicle_id, self.current_task.location)
		end
    end,
}
end

--template function for task
--never called directly, only subclassed
function new_task(name, priority, required_crew) 
    return {
        name = name, 
        priority = priority,
        required_crew = required_crew,
        assigned_crew = {},
        lifespan = 0
    }
end

g_tasks = {

    --task method is responsible for allocating the crew (making sure that each one is doing the right thing)
    turn_on_the_lights = {
        init = new_task('Turn on the lights', 3, {'sailor'}),

        tick = function(self, task_data, ship_states)
            task_data.lifespan = task_data.lifespan + 1

            local is_success = true 
            for _,crewmember in pairs(task_data.assigned_crew) do 
                is_success = crewmember:assign_to_task(task_data.task_name, task_data.priority)
                if not is_success then return task_data, false end 
            end

            local char_id = task_data.assigned_crew.sailor.id
            server.setCharacterSeated(char_id, ship_states.addon_information.id, 'Lighting control')

            task_data.wait_point = task_data.lifespan
            local five_seconds = 60 * 5
            if task_data.wait_point + five_seconds > task_data.lifespan then 
                return task_data, false
            end

            server.pressVehicleButton(ship_states.addon_information.id, 'Lights')
            return task_data, true 

        end,
    },

	take_stations = {
		init = new_task('Take stations', 3, {'Captain', 'Engineer'}),

		tick = function(self, task_data, ship_states)
			task_data.lifespan = task_data.lifespan + 1

			local is_success = true 
            for _,crewmember in pairs(task_data.assigned_crew) do 
                is_success = crewmember:assign_to_task(task_data.task_name, task_data.priority)
                if not is_success then return task_data, false end 
            end

			do 
				local char_id = task_data.assigned_crew.Captain.id 
				server.setCharacterSeated(char_id, ship_states.addon_information.id, 'Captain')
			end 

			do 
				local char_id = task_data.assigned_crew.Engineer.id 
				server.setCharacterSeated(char_id, ship_states.addon_information.id, 'Engineer')
			end 
			if not task_data.wait_point then 
				task_data.wait_point = task_data.lifespan
			end 
            local five_seconds = 60 * 5
            if task_data.wait_point + five_seconds > task_data.lifespan then 
                return task_data, false
            end
			debugLog('Task complete')
			task_data.wait_point = nil
			task_data.lifespan = 0 
			return task_data, true
		end,
	}
}




-------------------------------------------------------------------
--
--	Callbacks
--
-------------------------------------------------------------------

function onCreate(is_world_create)
	-- build mission type location data

	if g_savedata.ships == nil then
		debugLog('	overwriting g_savedata')
		g_savedata =
		{
			id_counter = 0,
			ships = {},
            valid_ships = {},
			spawned_objects = {},
		}
	end

	for i in iterPlaylists() do
		for j in iterLocations(i) do
			debugLog('	searching location...')
			local parameters, mission_objects = loadLocation(i, j)
			local location_data = server.getLocationData(i, j)

            local is_ship = (parameters.type == 'Ship')
            if is_ship then 
                if mission_objects.main_vehicle_component ~= nil and #mission_objects.crew > 0 then
                    debugLog("  found valid ship")
					local ship_name = parameters.title
					g_savedata.valid_ships[ship_name] = { playlist_index = i, location_index = j, data = location_data, objects = mission_objects, parameters = parameters }
                end
            end

		end
	end

	g_zones = server.getZones()
	g_zones_hospital = server.getZones("hospital")

	-- filter zones to only include mission zones
	for zone_index, zone_object in pairs(g_zones) do
		local is_mission_zone = false
		for zone_tag_index, zone_tag_object in pairs(zone_object.tags) do
			if zone_tag_object == "type=mission_zone" then
				is_mission_zone = true
			end
		end
		if is_mission_zone == false then
			g_zones[zone_index] = nil
		end
	end
end

function onPlayerJoin(steamid, name, peerid, admin, auth)
	if g_savedata.ships ~= nil then
		for k, mission_data in pairs(g_savedata.ships) do
			for k, marker in pairs(mission_data.map_markers) do
				if marker.archetype == "default" then
					server.addMapObject(peerid, marker.id, 0, marker.type, marker.x, marker.z, 0, 0, 0, 0, marker.display_label, marker.radius, marker.hover_label)
				elseif marker.archetype == "line" then
					server.addMapLine(-1, marker.id, marker.start_matrix, marker.dest_matrix, marker.width)
				end
			end
		end
	end
end

function onToggleMap(peer_id, is_open)
	for _, mission in pairs(g_savedata.ships) do
		removeMissionMarkers(mission)
		mission:rebuild_ui()
	end
end

function onTick(delta_worldtime)
	for _, ship in pairs(g_savedata.ships) do
        ship:tick()
    end 

end

function onCustomCommand(message, user_id, admin, auth, command, one, ...)
	math.randomseed(server.getTimeMillisec())

	local name = server.getPlayerName(user_id)

    if command == "?despawnall" and admin == true then
		despawnAllShips()
    end

	if command == "?spawnship" and admin == true then 
		local ship_id = create_ship_squirrel(user_id) --generalize this later 
		debugLog(ship_id)

	end 

	if command == '?createtaskdebug' and admin == true then 
		g_savedata.ships[#g_savedata.ships]:create_task('take_stations')		

	end 

	if command == '?printsensordata' then 
		for ship_id, ship in pairs(g_savedata.ships) do 
			ship:print_sensor_data()
		end 
	end 

    if command == "?log" and admin == true then
        printLog()
    end

    if command == "?printdata" and admin == true then
        server.announce("[Debug]", "---------------")
        printTable(g_savedata, "missions")
        server.announce("", "---------------")
    end

    if command == "?printtables" and admin == true then
        server.announce("[Debug]", "---------------")
        printTable(g_objective_types, "objective types")
        printTable(g_mission_types, "mission types")
        server.announce("", "---------------")
    end

    if command == "?printplaylists" and admin == true then
        for i, data in iterPlaylists() do
            printTable(data, "playlist_" .. i)
        end
    end

    if command == "?printlocations" and admin == true then
        for i, data in iterLocations(tonumber(one) or 0) do
            printTable(data, "location_" .. i)
        end
    end

    if command == "?printobjects" and admin == true then
        for i, data in iterObjects(tonumber(one) or 0, tonumber(two) or 0) do
            printTable(data, "object_" .. i)
        end
    end

	if command == "?loadlocations" and admin == true then
		for i in iterPlaylists() do
			for j in iterLocations(i) do
				_,_ = loadLocation(i,j)
			end 
		end 
	end

	if command == "?printships" and admin == true then
		for ship_name, ship_data in pairs(g_savedata.valid_ships) do 
			debugLog('	'..ship_name)
		end
		local len = tableLength(g_savedata.valid_ships)
		debugLog('	Total: '..tostring(len))
	end

	if command == "?printtestobjects" and admin == true then
		printTable(g_savedata.valid_ships.Squirrel.objects, 'object_')
	end

    if command == "?printtags" and admin == true then
        local location_tags = {}

        server.announce("", "Begin location tags")

        for i in iterPlaylists() do
            for j in iterLocations(i) do
                for _, object_data in iterObjects(i, j) do
                    local is_mission_object = false
                    for tag_index, tag_object in pairs(object_data.tags) do
                        if tag_object == "type=npc_ship" then
                            is_mission_object = true
                        end
                    end

                    if is_mission_object then
						debugLog('	Found mission objects')
                        for tag_index, tag_object in pairs(object_data.tags) do
                            if location_tags[tag_object] == nil then
                                location_tags[tag_object] = 1
                            else
                                location_tags[tag_object] = location_tags[tag_object] + 1
                            end
                        end
                    end
                end
            end
        end

        local location_tag_keys = {}
        -- populate the table that holds the keys
        for tag_index, tag_object in pairs(location_tags) do table.insert(location_tag_keys, tag_index) end
        -- sort the keys
        table.sort(location_tag_keys)
        -- use the keys to retrieve the values in the sorted order
        for _, key in ipairs(location_tag_keys) do
            server.announce(key, location_tags[key])
        end

        server.announce("", "End location tags")

        server.announce("", "Begin zone tags")

        local zone_tags = {}

        for zone_index, zone_object in pairs(g_zones) do
            for zone_tag_index, zone_tag_object in pairs(zone_object.tags) do
                if zone_tags[zone_tag_object] == nil then
                    zone_tags[zone_tag_object] = 1
                else
                    zone_tags[zone_tag_object] = zone_tags[zone_tag_object] + 1
                end
            end
        end

        local zone_tag_keys = {}
        -- populate the table that holds the keys
        for tag_index, tag_object in pairs(zone_tags) do table.insert(zone_tag_keys, tag_index) end
        -- sort the keys
        table.sort(zone_tag_keys)
        -- use the keys to retrieve the values in the sorted order
        for _, key in ipairs(zone_tag_keys) do
            server.announce(key, zone_tags[key])
        end

        server.announce("", "End zone tags")
    end

end

function onVehicleLoad(vehicle_id)
	for _, ship in pairs(g_savedata.ships) do
		if ship.states.addon_information.id == vehicle_id then 
			ship:on_vehicle_load()
		end 
	end
end

function onVehicleUnload(vehicle_id)
	for _, ship in pairs(g_savedata.ships) do
		if ship.states.addon_information.id == vehicle_id then 
			ship:on_vehicle_unload()
		end 
	end
end 


-------------------------------------------------------------------
--
--	Ship Creation
--
-------------------------------------------------------------------

function create_ship(ship_name)
	return g_ships[ship_name]
end 

function create_ship_squirrel(user_id)
	local ship_data = create_ship('squirrel')
	ship_data.spawn_transform = findSuitableZone(user_id, true)
	table.insert(g_savedata.ships, Ship(ship_data))
	local ship_id = #g_savedata.ships
	g_savedata.ships[ship_id]:init(ship_data)
	return ship_id 
end 

g_ships = {
	squirrel = {
		name = 'Squirrel',
		sensors = {
			'speed_kph',
			'gps_x',
			'gps_y',
			'compass',

		},
		crew = {
			captain = Crew('Captain','officer_of_the_deck'),
			engineer= Crew('Engineer', 'engineer'),
		},
		location = function() return g_savedata.valid_ships.Squirrel end,
	}
}



-------------------------------------------------------------------
--
--	Utility Functions
--
-------------------------------------------------------------------


function despawnAllShips() 
	despawnObjects(g_savedata.spawned_objects, true)
	local ship_count = tableLength(g_savedata.ships)
	for _,ship in pairs(g_savedata.ships) do 
		removeMissionMarkers(ship)
	end 
	g_savedata.spawned_objects = {}
	g_savedata.ships = {}
	debugLog('Despawned '..ship_count..' ships.')
end 

-- iterator function for iterating over all playlists, skipping any that return nil data
function iterPlaylists()
	local playlist_count = server.getPlaylistCount()
	local playlist_index = 0

	return function()
		local playlist_data = nil
		local index = playlist_count

		while playlist_data == nil and playlist_index < playlist_count do
			playlist_data = server.getPlaylistData(playlist_index)
			index = playlist_index
			playlist_index = playlist_index + 1
		end

		if playlist_data ~= nil then
			return index, playlist_data
		else
			return nil
		end
	end
end


-- iterator function for iterating over all locations in a playlist, skipping any that return nil data
function iterLocations(playlist_index)
	local playlist_data = server.getPlaylistData(playlist_index)
	local location_count = 0
	if playlist_data ~= nil then location_count = playlist_data.location_count end
	local location_index = 0

	return function()
		local location_data = nil
		local index = location_count

		while location_data == nil and location_index < location_count do
			location_data = server.getLocationData(playlist_index, location_index)
			index = location_index
			location_index = location_index + 1
		end

		if location_data ~= nil then
			return index, location_data
		else
			return nil
		end
	end
end

-- iterator function for iterating over all objects in a location, skipping any that return nil data
function iterObjects(playlist_index, location_index)
	local location_data = server.getLocationData(playlist_index, location_index)
	local object_count = 0
	if location_data ~= nil then object_count = location_data.component_count end
	local object_index = 0

	return function()
		local object_data = nil
		local index = object_count

		while object_data == nil and object_index < object_count do
			object_data = server.getLocationComponentData(playlist_index, location_index, object_index)
			object_data.index = object_index
			index = object_index
			object_index = object_index + 1
		end

		if object_data ~= nil then
			return index, object_data
		else
			return nil
		end
	end
end

function loadLocation(playlist_index, location_index)

	local mission_objects =
	{
		main_vehicle_component = nil,
		vehicles = {},
		crew = {},
	}

	local parameters = {
		type = "",
		title = "",
		rank = "", --officer or enlisted
	}

	for _, object_data in iterObjects(playlist_index, location_index) do
		-- investigate tags
		debugLog('	Investigating tags')
		local is_tag_object = false
		for tag_index, tag_object in pairs(object_data.tags) do
			if tag_object == "type=npc_ship" then
				debugLog('	Found NPC ship')
				is_tag_object = true
				parameters.type = "Ship"
			end

		end

		if is_tag_object then
			for tag_index, tag_object in pairs(object_data.tags) do
				if string.find(tag_object, "title=") ~= nil then
					parameters.title = string.sub(tag_object, 7)
				elseif string.find(tag_object, "rank=") ~= nil then
					parameters.rank = tag_object
				end
			end
		end

		if object_data.type == "vehicle" then
			debugLog('	Adding ship '..parameters.title..' to return package')
			table.insert(mission_objects.vehicles, object_data)
			mission_objects.main_vehicle_component = object_data
		elseif object_data.type == "character" then
			table.insert(mission_objects.crew, object_data)
		end
	end

	return parameters, mission_objects
end

-- calculates the size of non-contiguous tables and tables that use non-integer keys
function tableLength(T)
	local count = 0
	for _ in pairs(T) do count = count + 1 end
	return count
end

-- recursively outputs the contents of a table to the chat window for debugging purposes.
-- name is the name that should be displayed for the root of the table being passed in.
-- m is an optional parameter used when the function recurses to specify a margin string that will be prepended before printing for readability
function printTable(table, name, m)
	local margin = m or ""

	if tableLength(table) == 0 then
		server.announce("", margin .. name .. " = {}")
	else
		server.announce("", margin .. name .. " = {")

		for k, v in pairs(table) do
			local vtype = type(v)

			if vtype == "table" then
				printTable(v, k, margin .. "    ")
			elseif vtype == "string" then
				server.announce("", margin .. "    " .. k .. " = \"" .. tostring(v) .. "\",")
			elseif vtype == "number" or vtype == "function" or vtype == "boolean" then
				server.announce("", margin .. "    " .. k .. " = " .. tostring(v) .. ",")
			else
				server.announce("", margin .. "    " .. k .. " = " .. tostring(v) .. " (" .. type(v) .. "),")
			end
		end

		server.announce("", margin .. "},")
	end
end

-- pushes a string into the global output log table.
-- the log is cleared when a new mission is spawned.
-- the log for the previously spawned mission can be displayed using the command ?log
function debugLog(message)
	table.insert(g_output_log, message)
	server.announce('DEBUG	', message)
end


-- outputs everything in the debug log to the chat window
function printLog()
	for i = 1, #g_output_log do
		server.announce("[Debug Log] " .. i, g_output_log[i])
	end
end

-- despawn all objects in the list
function despawnObjects(objects, is_force_despawn)
	if objects ~= nil then
		for _, object in pairs(objects) do
			despawnObject(object.type, object.id, is_force_despawn)
		end
	end
end

-- despawn a specific object by type and id.
-- if is_force_despawn is true, the object will be instantly removed, otherwise it will be removed when it despawns naturally
function despawnObject(type, id, is_force_despawn)
	if type == "vehicle" then
		server.despawnVehicle(id, is_force_despawn)
	elseif type == "character" then
		server.despawnObject(id, is_force_despawn)
	end
end


-- spawn a list of object descriptors from a playlist location.
-- playlist_index is required to spawn vehicles from the correct playlist.
-- a table of spawned object data is returned, as well as the data being appended to an option out_spawned_objects table
function spawnObjects(spawn_transform, location, object_descriptors, out_spawned_objects, spawn_rarity, min_amount, max_amount)
	local spawned_objects = {}

	for _, object in pairs(object_descriptors) do
		if ((#spawned_objects < min_amount) or (math.random(1, spawn_rarity) == 1)) and #spawned_objects < max_amount then
			-- find parent vehicle id if set
			local parent_vehicle_id = 0
			if object.vehicle_parent_component_id > 0 then
				for spawned_object_id, spawned_object in pairs(out_spawned_objects) do
					if spawned_object.type == "Ship" and spawned_object.component_id == object.vehicle_parent_component_id then
						parent_vehicle_id = spawned_object.id
					end
				end
			end
			spawnObject(spawn_transform, location, object, parent_vehicle_id, spawned_objects, out_spawned_objects)
		end
	end

	debugLog("spawned " .. #spawned_objects .. "/" .. #object_descriptors .. " objects")

	return spawned_objects
end

function spawnObject(spawn_transform, location, object, parent_vehicle_id, spawned_objects, out_spawned_objects)
	-- spawn object

	local spawned_object_id = spawnObjectType(spawn_transform, location, object, parent_vehicle_id)

	-- add object to spawned object tables

	if spawned_object_id ~= nil and spawned_object_id ~= 0 then
		local object_data = { type = object.type, id = spawned_object_id, component_id = object.id }

		if spawned_objects ~= nil then
			table.insert(spawned_objects, object_data)
		end

		if out_spawned_objects ~= nil then
			table.insert(out_spawned_objects, object_data)
			debugLog('added object of type '..object.type..' to g_savedata.spawned_objects')
		end

		return object_data
	end

	return nil
end

-- spawn an individual object descriptor from a playlist location
function spawnObjectType(spawn_transform, location, object_descriptor, parent_vehicle_id)
	local component = server.spawnAddonComponent(matrix.multiply(spawn_transform, object_descriptor.transform), location.playlist_index, location.location_index, object_descriptor.index, parent_vehicle_id)
	return component.id
end

function findSuitableZone(player_id, is_ocean_zone)
	local min_range = 0 
	local max_range = 1500
	if is_ocean_zone then 
		local ocean_transform, is_ocean_found = server.getOceanTransform(server.getPlayerPos(player_id), min_range, max_range)
		return ocean_transform
	end
	--To be expanded with custom, non-ocean zones
end 

-------------------------------------------------------------------
--
--	 UI
--
-------------------------------------------------------------------

-- adds a marker to a mission
function addMarker(mission_data, marker_data)
	marker_data.archetype = "default"
	table.insert(mission_data.map_markers, marker_data)
	server.addMapObject(-1, marker_data.id, 1, marker_data.type, marker_data.x, marker_data.z, 0, 0, mission_data.states.addon_information.id, 0, marker_data.display_label, marker_data.radius, marker_data.hover_label)
end

-- creates a search zone marker and sends it to all connected players
function createTutorialMarker(x, z, display_label, hover_label)
	local map_id = server.getMapID()

	return {
		id = map_id,
		type = 4,
		x = x,
		z = z,
		radius = 0,
		display_label = display_label,
		hover_label = hover_label
	}
end

function removeMissionMarkers(mission)
	for k, obj in pairs(mission.map_markers) do
		server.removeMapID(-1, obj.id)
	end
	mission.map_markers = {}
end

