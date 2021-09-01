g_savedata = {}
g_zones = {}
g_zones_hospital = {}
g_output_log = {}
g_objective_update_counter = 0
g_damage_tracker = {}

DEFAULT_POPUP_LIFESPAN = 120

Ship = {
    init = function(self, ship_data)        
        --initialize the sensor readings
        for sensor_id, sensor_name in ipairs(ship_data.sensors) do 
			if string.find(sensor_name,'bool') then 
				ship_data.states.sensors[sensor_name] = {id = sensor_id, value=false, bool=true}
			else 
            	ship_data.states.sensors[sensor_name] = {id = sensor_id, value=0, bool=false}
			end 
			debugLog('Created sensor '..sensor_name..' with ID '..sensor_id)
        end 

        --Spawn the objects
        local spawned_objects = {}
		local spawn_transform = ship_data.spawn_transform
		local location = ship_data.location()
		local object = location.objects.main_vehicle_component
		local parent_vehicle_id = nil
		
        
        --spawn the ship 
        spawnObject(spawn_transform, location, object, parent_vehicle_id, spawned_objects, g_savedata.spawned_objects)


        --spawn all of the crewmembers associated with the ship
        --self.crew = ship_data.crew
		
		local parent_vehicle_id = spawned_objects[1].id
		local objects = location.objects.crew
        for _, crewmember in pairs(ship_data.crew) do 
			--Make sure we're spawning the crewmember with the correct name 
			for index,potential_crewmember in pairs(objects) do 
				if potential_crewmember.display_name == crewmember.role then 
					spawnObject(spawn_transform, location, potential_crewmember, parent_vehicle_id, spawned_objects, g_savedata.spawned_objects)
					crewmember.id = spawned_objects[#spawned_objects].id
					break 
				end 
			end 

		end 
		--printTable(self.crew, 'Crew		')
		--printTable(spawned_objects, 'spawned objects')

        ship_data.states.addon_information.id = parent_vehicle_id 
		debugLog('Parent vehicle ID: '..ship_data.states.addon_information.id)
        ship_data.states.addon_information.transform = spawn_transform
        ship_data.states.addon_information.popups = {}
		ship_data.states.addon_information.sim = {}
		ship_data.states.addon_information.name = ship_data.name
		--self.states.available_tasks = ship_data.available_tasks

		if server.getVehicleSimulating(ship_data.states.addon_information.id) then
			ship_data.states.addon_information.sim.state = 'loaded'
		else 
			ship_data.states.addon_information.sim.state = 'unloaded'
		end 

    end,

    tick = function(self, ship_data)
		--update the vehicle's position
		local transform, is_success = server.getObjectPos(ship_data.states.addon_information.id)
		ship_data.states.addon_information.transform = transform
		if not is_success then debugLog('Failed to update position') end 

        --update all sensors and onboard statuses
        for sensor_name, sensor_data in pairs(ship_data.states.sensors) do 
            local values, is_success = server.getVehicleDial(ship_data.states.addon_information.id, 'sensor'..tostring(math.tointeger(sensor_data.id)))
			if is_success then 
				if sensor_data.bool then 
					sensor_data.value = (values['value'] > 0)
				else
					sensor_data.value = values['value']
				end
			else 
				--debugLog('failed to get value for sensor '..sensor_name..' with ID '..sensor_data.id)
			end 
        end 

        --loop through ongoing tasks and update each in turn
        for task_id, task in pairs(ship_data.tasks) do 
            local is_complete = false 
            is_complete = Task:update(task.task_object)

			-- Check to make sure the crewmembers are still assigned to the task
			-- If not, remove them from the list of assigned crew
			-- This lets the task object know that it no longer has the crew required to complete the task
			for crew_name, crewmember in pairs(task.task_object.assigned_crew) do 
				if (crewmember.current_task.t ~= task.task_object.name) and (crewmember.current_task.t ~= 'routine') then 
					debugLog(crew_name..' is no longer assigned to '..task.task_object.name..'. Now assigned to '..crewmember.current_task.t)
					task.task_object.assigned_crew[crew_name] = nil 
				end 
			end 

            if is_complete then 
                Ship:complete_task(ship_data, task.task_name)
            end 
        end

		for _,crewmember in pairs(ship_data.crew) do 
			Crew:tick(crewmember, ship_data.states.addon_information.id)
		end 

		-- Popup lifespan management
		for _, popup in ipairs(ship_data.states.popups) do 
			popup.lifespan = popup.lifespan - 1

			if popup.lifespan <= 0 and popup.active then
				server.removePopup(-1,popup.id)
				popup.active = false
			end
		end
    end,

    create_task = function(self, ship_data, task_name, params) --task_name is a string with the variable name of the task
        --Check to make sure task doesn't already exist

        --Create an instance of the task object
		--debugLog('params at ship object: '..params)
        local task = create_task(task_name, ship_data.states, ship_data.available_tasks, (params and params or nil))

        --Populate the task object with crewmembers
        for _,role in pairs(task.required_crew) do 
            local found = false 
            for crew_name, crew_object in pairs(ship_data.crew) do 
                if crew_object.role == role then 
                    task.assigned_crew[role] = crew_object
					debugLog('Assigned '..role.. ' to task '..task_name)
					found = true 
                end 

                if found then break end 
            end 
        end 
		debugLog('Created task '..task_name)
		--printTable(task, 'Task data ')
        --Store the task in the ship's tasks table
        table.insert(ship_data.tasks, {task_name = task_name, task_object = task}) --'task_name' is the variable name of the task (eg, turn_on_the_lights).
    end,

	complete_task = function(self, ship_data, task_name, task_id)
		local task_id = task_id or find_task_by_name(task_name, ship_data.tasks)
		-- Sanity check for existence of task
		if not task_id then 
			debugLog('Could not find task '..task_name..'.')
			return false 
		end
		-- Return crew states to idle, or return them to their previous task
		for crew_name, crewmember in pairs(ship_data.tasks[task_id].task_object.assigned_crew) do 
			local task_len = #ship_data.tasks
			local found 
			debugLog('Determining whether to idle or reassign '..crewmember.role)
			for i = task_len, 1, -1 do --iterate backwards - prioritize recency
				if i ~= task_id then --don't reassign to the same task (duh)
					local task = ship_data.tasks[i]
					if task.task_object.override_behavior == 'cancel' then break end 
					for _, role in pairs(task.task_object.required_crew) do 
						if crewmember.role == role then 
							task.task_object.assigned_crew[role] = crewmember 
							Crew:assign_to_task(crewmember, task.task_object.name, task.task_object.priority, true)
							Task:return_to_task(task.task_object, crewmember)
							debugLog('Reassigned '..role.. ' to task '..task.task_name)
							found = true 
						end 
					end 
					if found then break end 
				end 
			end 

			if not found then 
				debugLog('Idling character '..crewmember.role)
				Crew:complete_task(crewmember)
			end 
		end
		
		ship_data.tasks[task_id] = nil --remove the completed task 
		return true 
	end,

	on_vehicle_load = function(self, ship_data)
		ship_data.states.addon_information.sim.state = 'loaded'
	end,

	on_vehicle_unload = function(self, ship_data)
		ship_data.states.addon_information.sim.state = 'unloaded'
	end,

	rebuild_ui = function(self, ship_data)
		--if self.states.addon_information.sim.state == 'loaded' then 
			local pos = ship_data.states.addon_information.transform 
			--printTable(pos, 'Current Location')
			local marker_x, marker_y, marker_z = matrix.position(pos)
			addMarker(ship_data, createTutorialMarker(marker_x, marker_z, ship_data.states.addon_information.name, ''))

		--end 
	end,

	--debug function to print sensor data
	print_sensor_data = function(self, ship_data)
		for sensor_name, sensor_data in pairs(ship_data.states.sensors) do 
				debugLog(sensor_name..': '..tostring(sensor_data.value))
		end
	end,



} 

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
function create_crew(role, routine) return { 
    role = role,
	routine = g_crew_routines[routine],
    current_task = {t = 'routine', priority = math.huge, location = g_crew_routines[routine][1].location}, --default task is 'routine',
	id = 0,
}
end

Crew = {
    assign_to_task = function(self, crew_data, task_name, task_priority, is_force)
        --Check if crewmember is already performing the task
        if task_name == crew_data.current_task.t then return true end

        --Check for priority levels - if new task is higher priority (lower priority # than old task), the old task is overridden
        debugLog(crew_data.role..': Current task priority: '..crew_data.current_task.priority..', New task priority: '..task_priority)
		if (crew_data.current_task.priority > task_priority) or is_force then 
            crew_data.current_task.t = task_name 
            crew_data.current_task.priority = task_priority
            return true 
        end 
        return false 
    end,

	--- Set the crew object to return to its default routine. Reset task priority to infinity.
    complete_task = function(self, crew_data)
        crew_data.current_task.t = 'routine'
        crew_data.current_task.priority = math.huge 
        return true
    end,

    tick = function(self, crew_data, vehicle_id)
		--Cycle crewmember through daily routine
        if crew_data.current_task.t == 'routine' then 
			local time_pct = server.getTime().percent
			for index,routine in pairs(crew_data.routine) do 
				if routine.time <= time_pct then 
					crew_data.current_task.location = routine.location 
				elseif (routine.time >= time_pct) and index == 1 then 
					--Correctly handle the case when the vehicle spawns before the first routine in the list
					crew_data.current_task.location = crew_data.routine[#crew_data.routine].location
				else break 
				end
			end 

			server.setCharacterSeated(crew_data.id, vehicle_id, crew_data.current_task.location)
		end
    end,
}



--- Base class for tasks. Never called directly, only subclassed
Task = {
	update = function(self, task_data)
		task_data.lifespan = task_data.lifespan + 1
		-- Check for task completion
		if task_data.current_task_component == #task_data.task_components + 1 then return true end 

		-- Check if crew are still assigned to task
		-- If not, throw a warning and end the task
		if tableLength(task_data.required_crew) ~= tableLength(task_data.assigned_crew) then 
			local is_cancel = task_data.override_behavior == 'cancel'
			if is_cancel then debugLog('One or more crewmembers no longer assigned to task '..task_data.name..'. Ending task...') end 
			return is_cancel
		end 

		-- Task component methods return two values: 
		-- is_complete denotes the completion of the individual component, and will return false until it is true 
		-- task_failure is an optional return value that denotes if the entire task should fail
		local component = task_data.task_components[task_data.current_task_component]
		--printTable(task_data, 'task_data in update')
		local is_complete, task_failure = Task[component.component](Task, task_data, table.unpack(component.args))
		
		-- If the task has failed, throw a warning and end the task
		if task_failure then 
			debugLog('Task failed at step '..task_data.current_task_component..': '..component.component)
			return true 
		end 
		
		if is_complete then 
			task_data.current_task_component = task_data.current_task_component + 1
			debugLog('Completed task component '..component.component) 
		end 
		return false 
	end,

	return_to_task = function(self, task_data, crew_data) --What to do if returning to an overridden task
		for i = task_data.current_task_component, 1, -1 do 
			local component = task_data.task_components[i]
			if component.component == 'set_seated' then
				if component.args[1] == crew_data.role then 
					debugLog('Re-seating crewmember '..crew_data.role..' in seat '..component.args[2])
					Task[component.component](Task, task_data, table.unpack(component.args))
					break
				end 
			end 
		end 
	end, 

	--- Teardown method
	terminate = function(self, task_data)

	end,
	
	assign_crew = function(self, task_data)
		--printTable(task_data, 'task_data in assign_crew')
		for _,crewmember in pairs(task_data.assigned_crew) do
			local is_success = Crew:assign_to_task(crewmember, task_data.name, task_data.priority)
			if not is_success then return false, true end 
		end 
		return true
	end,
	
	set_seated = function(self, task_data, char_name, seat_name)
		local char_id = task_data.assigned_crew[char_name].id
		server.setCharacterSeated(char_id, task_data.ship_states.addon_information.id, seat_name)
		return true
	end,
	
	wait = function(self, task_data, wait_point_name, wait_time) --in seconds
		local wait_time_ticks = math.floor(wait_time * 60)
		if not task_data.wait_points[wait_point_name] then 
			task_data.wait_points[wait_point_name] = task_data.lifespan
		elseif task_data.wait_points[wait_point_name] + wait_time_ticks < task_data.lifespan then 
			return true
		end 
		
		return false 
	end,
	
	press_button = function(self, task_data, button_name) --in seconds
		server.pressVehicleButton(task_data.ship_states.addon_information.id, button_name)
		return true 
	end,

	--- Create a dialogue popup over a given character. 
	--- popup_lifespan is optional, and is in ticks (1 seconds ~= 60 ticks). 
	--- Default value can be set in DEFAULT_POPUP_LIFESPAN
	create_popup = function(self, task_data, char_name, popup_text, popup_lifespan)
		local lifespan = popup_lifespan or DEFAULT_POPUP_LIFESPAN
		local popup_id = #task_data.ship_states.popups + 1
		local char_id = task_data.assigned_crew[char_name].id
		addPopup(popup_id, char_id, task_data.ship_states.popups, popup_text, lifespan)
		return true 
	end,

	--- Returns true if and only if the entire function is true.
	--- Function is evaluated left to right.
	--- Args are alternating information to evaluate (sensors) and conditionals.
	evaluate_conditional = function(self, task_data, ...) 
		local conditionals = {
			['and'] = function(a,b) return (a and b) end,
			['or']  = function(a,b) return (a or b) end,
			['>']   = function(a,b) return (a > b) end,
			['<']   = function(a,b) return (a < b) end,
			['>=']   = function(a,b) return (a >= b) end,
			['<=']   = function(a,b) return (a <= b) end,
			['==']   = function(a,b) return (a == b) end,
		}
		local terms = {...}
		if #terms == 1 then return (task_data.ship_states.sensors[terms[1]].value) end 
		for i=1,#terms-1,2 do 
			local a = (type(terms[i]) ~= 'string') and terms[i] or task_data.ship_states.sensors[terms[i]].value
			local b = (type(terms[i+2]) ~= 'string') and terms[i+2] or task_data.ship_states.sensors[terms[i+2]].value
			if not conditionals[terms[i+1]](a,b) then return false end
		end 
		return true
	end,

	--- Implements basic branching - execute one task component if the condition is true, a different component if false.
	--- This method always returns true, meaning it will only execute once.
	--- @param condition any String or Table to pass to self:evaluate_conditional()
	--- @param component_if_true table Task component and optional args if statement evaluates to true
	--- @param component_if_false table Task component and optional args if statement evaluates to false
	if_then_else = function(self, task_data, condition, component_if_true, component_if_false)
		-- pass the conditional to evaluate_conditional, can handle multiple arguments
		local is_success = Task:evaluate_conditional(task_data, type(condition) == 'table' and table.unpack(condition) or condition)
		local args = is_success and component_if_true or component_if_false 
		local component = make_task_component(table.unpack(args))
		if not component.component then return true end 
		local is_complete, task_failure = Task[component.component](Task, task_data, table.unpack(component.args))
		return true, task_failure
	end,

	--- Halt task execution to wait for a specific command from a player
	await_user_input = function(self, task_data, command)
		if not task_data.ship_states.user_input_stack[command] then 
			-- Initialize await: add a new command to the stack
			task_data.ship_states.user_input_stack[command] = {called = false}
			debugLog('New command added: '..command)
			printTable(task_data.ship_states.user_input_stack, 'Stack')
		elseif task_data.ship_states.user_input_stack[command].called then 
			--remove the command from the stack
			task_data.ship_states.user_input_stack[command] = nil
			return true 
		end 
		
		return false 
	end,

	--- Set one or more helm values. 
	--- If the helm is occupied by a character, the helm will retain the values until they are overwritten. 
	--- Warning: This method will overwrite all helm values to 0 or false unless explicitly specified otherwise.
	--- Number inputs must be set to reset, otherwise they cannot be set to 0. 
	--- @param seat_name string The name of the seat as it appears on the vehicle.
	--- @param commands table A table of buttons and values to send to the helm.
	--- @param stop_command string Optional, if set the order will be repeatedly sent to the helm until the player types in the stop command.
	manipulate_helm = function(self, task_data, seat_name, commands, stop_command)
		local this_helm = task_data.ship_states.helms[seat_name] 
		local to_vehicle = this_helm or {0, 0, 0, 0, false, false, false, false, false, false,}
	
		local map_name_to_num = {
			['axis_ws'] = 1,
			['axis_da'] = 2,
			['axis_ud'] = 3,
			['axis_rl'] = 4,
			['button_1'] = 5,
			['button_2'] = 6,
			['button_3'] = 7,
			['button_4'] = 8,
			['button_5'] = 9,
			['button_6'] = 10,
		}
		
		for button_name, button_value in pairs(commands) do 
			to_vehicle[map_name_to_num[button_name]] = button_value
		end 

		local vehicle_id = task_data.ship_states.addon_information.id
		server.setVehicleSeat(vehicle_id, seat_name, table.unpack(to_vehicle))
		
		task_data.ship_states.helms[seat_name] = to_vehicle

		if stop_command then 
			local received_command = Task:await_user_input(task_data, stop_command)
			if not received_command then return false end 
		end 
		return true 
	end,

	give_item = function(self, task_data, char_name, item, is_remove, is_active, integer_value, float_value)
		local function slot(id, slot) return {id = id, slot = slot} end 
		local item_slots = {
			fire_extinguisher = slot(10,1),
			firefighter = slot(2,6),

		}
		local item = item_slots[item] or slot(0,0)

		if is_remove then item.id = 0 end 

		local char_id = task_data.assigned_crew[char_name].id
		local is_success = server.setCharacterItem(char_id, item.slot, item.id, is_active or false, integer_value, float_value)

		return is_success
	end, 

}


function conc(t1,t2) 
	for k,v in pairs(t2) do 
		t1[k] = v
	end 
	return t1
end 

--- Generator function that creates a task component.
--- @param component string A primitive or user-defined component method to execute
--- @param args string The arguments to pass to the component method
--- Include the string 'custom' as the last parameter to indicate the task component is user-defined, 
--- rather than a provided primitive.




function make_task_component(component, ...)
	local args = {...} 
	local output = {component = component}
	if (args[#args] == 'custom') then 
		output.custom = true 
		output.args = subset(args, 1, #args - 1)
	else 
		output.args = args or {}
	end 
	return output
end

function create_task(task_name, ship_states, task_list, ...)
	local args = ...
	local base = {
		name = '',
		priority = math.huge,
		required_crew = {},
		assigned_crew = {},
		lifespan = 0,
		ship_states = ship_states,
		wait_points = {},
		task_components = {},
		current_task_component = 1,
		override_behavior = 'cancel', --'cancel' or 'wait'
		
	}
	return conc(base, task_list[task_name](table.unpack(args)))
end 

-------------------------------------------------------------------
--
--	Ship Creation
--
-------------------------------------------------------------------

function create_ship(user_id, ship_name, custom_name, is_ocean_zone)
	local ship_data = {
		crew = {},
    	tasks = {}, --task priority: 0 for emergencies, 1 for urgent, 2 for normal, 3 for routine/maintenance, math.huge for idle (crewmembers only)
		states = {
			addon_information = {}, --includes the vehicle ID
			sensors = {}, --external sensor input (speed, GPS, etc)
			onboard_information = {}, --onboard states such as whether the lights are on
			popups = {},
			user_input_stack = {}, --a list of trigger phrases created by tasks awaiting user input
			available_tasks = {}, --a list of all tasks associated with the ship
			helms = {}, --A dynamically-generated table of all controllable seats or helms and their values
		},
		map_markers = {},
	}

	if not g_ships[ship_name] then
		debugLog('Ship not found.')
		return false 
	end
	local ship_data = conc(ship_data, g_ships[ship_name]())
	ship_data.custom_name = custom_name or ship_data.name 
	ship_data.spawn_name = ship_name
	ship_data.spawn_transform = findSuitableZone(user_id, ship_data, is_ocean_zone)
	table.insert(g_savedata.ships, ship_data)
	local ship_id = #g_savedata.ships
	--g_savedata.ships[ship_id]:init(ship_data)
	Ship:init(ship_data)
	return ship_id 
end 

g_ships = {
	squirrel = function() return {
		name = 'Squirrel',
		sensors = {
			'speed_kph',
			'gps_x',
			'gps_y',
			'compass',
			'fuel',
			'fuel_capacity',
			'bool_main_power',
			'engine1_rps',
			'engine2_rps',

		},
		size = 'small', --small, medium, or large
		vehicle_type = 'boat', --boat, fixed_wing, rotorcraft, ground
		crew = {
			captain = create_crew('Captain','officer_of_the_deck'),
			engineer= create_crew('Engineer', 'engineer'),
		},
		location = function() return g_savedata.valid_ships.Squirrel end, --This shouldn't be a problem, since it's only used in init
		available_tasks =  {
			['turn on the lights'] = function() return { --This function can support an arbitrary number of args
				name = 'turn on the lights', -- This is the name that will be used to spawn the task
				priority = 3,
				required_crew = {'Engineer'}, --Has to be a table even if there's only one
				can_override = {
		
				},
		
				task_components = {
					make_task_component('assign_crew'),
					make_task_component('set_seated', 'Engineer', 'Electrical Control'),
					make_task_component('create_popup', 'Engineer', 'Waiting for main power', 60),
					make_task_component('evaluate_conditional', 'bool_main_power'),
					make_task_component('create_popup', 'Engineer', 'Turning on the lights'),
					make_task_component('wait', 'pre_switch_wait', 1.5),
					make_task_component('press_button', 'Console Lights'),
					make_task_component('wait', 'wait_for_console_lights', 0.7),
					make_task_component('press_button', 'Exterior Lights'),
					make_task_component('wait', 'wait_end', 2.5),
		
				},
			} end,
		
			['cold start'] = function() return {
				name = 'cold start',
				priority = 2,
				required_crew = {'Captain', 'Engineer'},
		
				task_components = {
					make_task_component('assign_crew'),
					make_task_component('set_seated', 'Captain', 'Captain'),
					make_task_component('set_seated', 'Engineer', 'Electrical Control'),
					make_task_component('wait', 'wait1', 1.5),
					make_task_component('create_popup', 'Captain', 'Begin cold start procedure'),
					make_task_component('wait', 'wait2', 2),
					make_task_component('create_popup','Captain','Turn on main power'),
					make_task_component('wait', 'wait3', 1.5),
					make_task_component('if_then_else', 'bool_main_power', {'create_popup', 'Engineer', 'Main power is already on'}, {'press_button', 'master_power'}),
					make_task_component('wait', 'wait4', 1.2),
					make_task_component('create_popup', 'Engineer', 'Turning on electrical systems'),
					make_task_component('wait', 'wait5', 0.75),
					make_task_component('press_button', 'Console Lights'),
					make_task_component('wait', 'wait_for_console_lights', 0.3),
					make_task_component('press_button', 'Exterior Lights'),
					make_task_component('wait', 'wait6', 1),
					make_task_component('create_popup', 'Engineer', 'Electrical systems online'),
					make_task_component('wait', 'wait7', 1),
					make_task_component('set_seated', 'Engineer', 'Engineer'),
					make_task_component('create_popup', 'Captain', 'Copy, starting the engine'),
					make_task_component('press_button', 'throttle_up'),
					make_task_component('wait', 'wait8', 2.5),
					make_task_component('press_button','Engine Start'),
					make_task_component('wait', 'wait9', 2.5),
					make_task_component('evaluate_conditional','engine1_rps','>',10),
					make_task_component('evaluate_conditional','engine2_rps','>',10),
					make_task_component('create_popup','Engineer','Both engines holding at 20 RPS'),
					make_task_component('wait', 'wait10', 2),
					make_task_component('create_popup', 'Captain', 'Understood, looks like we\'re ready to go'),
				}
			} end,
		
			['emergency naptime'] = function() return {
				name = 'emergency nap',
				priority = 0,
				required_crew = {'Captain'},
		
				task_components = {
					make_task_component('assign_crew'),
					make_task_component('set_seated', 'Captain', 'bed1'),
					make_task_component('wait', 'wait1', 7.5)
				},
			} end,
		
			['undefined naptime'] = function() return{
				name = 'undefined naptime',
				priority = 2,
				required_crew = {'Captain'},
				override_behavior = 'wait',
		
				task_components = {
					make_task_component('assign_crew'),
					make_task_component('set_seated', 'Captain', 'bed1'),
					make_task_component('await_user_input', 'wake up'),
			}
		
			} end,
		
			['check power status'] = function() return{
				name = 'check power',
				priority = 2,
				required_crew = {'Engineer'},
		
				task_components = {
					make_task_component('assign_crew'),
					make_task_component('set_seated', 'Engineer', 'Electrical Control'),
					make_task_component('evaluate_conditional', 'bool_main_power'),
					make_task_component('create_popup','Engineer','Main power is on'),
		
		
				}
			} end,
		
			['ahead'] = function(order) 
				
				local orders = {
					['slow'] = 0.55,
					['half'] = 0.7,
					['full'] = 1,
				}

				local order = order or 'slow'

				return{
				name = 'throttle ahead',
				priority = 1,
				required_crew = {'Captain'},
		
				task_components = {
					make_task_component('assign_crew'),
					make_task_component('wait','wait1',1),
					make_task_component('create_popup','Captain','All ahead '..order..', aye'),
					make_task_component('set_seated', 'Captain', 'Captain'),
					--make_task_component('press_button', 'clutch_up'),
					make_task_component('manipulate_helm', 'Captain', {axis_ws = orders[order]}),

				}
			} end,
		
			['all stop'] = function() return{
				name = 'all stop',
				priority = 1,
				required_crew = {'Captain'},
		
				task_components = {
					make_task_component('assign_crew'),
					make_task_component('wait','wait1',1),
					make_task_component('create_popup','Captain','All stop, aye'),
					make_task_component('set_seated', 'Captain', 'Captain'),
					--make_task_component('press_button', 'clutch_down'),
					make_task_component('manipulate_helm', 'Captain', {axis_ws = 0}),

				}
			} end,

			['left'] = function(angle) 			
				local params = {
					['15'] = -0.17,
					['30'] = -0.33,
					['full'] = -0.5
				}
				local dialogue_params = {
					['15'] = 'Left 15 degrees, aye',
					['30'] = 'Left standard rudder, aye',
					['full'] = 'Left full rudder, aye',
					['unknown'] = 'Didn\'t catch that, say again please?'
				}
				return{
				name = 'left rudder',
				priority = 1,
				required_crew = {'Captain'},

				task_components = {
					make_task_component('assign_crew'),
					make_task_component('wait','wait1',1),
					make_task_component('create_popup','Captain',dialogue_params[angle] or dialogue_params['unknown']),
					make_task_component('set_seated', 'Captain', 'Captain'),
					make_task_component('manipulate_helm', 'Captain', {axis_da = params[angle] or 0}),
				}
			} end,

			['right'] = function(angle) 
				local params = {
					['15'] = 0.17,
					['30'] = 0.33,
					['full'] = 0.5
				}
				local dialogue_params = {
					['15'] = 'Right 15 degrees, aye',
					['30'] = 'Right standard rudder, aye',
					['full'] = 'Right full rudder, aye',
					['unknown'] = 'Didn\'t catch that, say again please?'
				}
				return{
				name = 'right rudder',
				priority = 1,
				required_crew = {'Captain'},

				task_components = {
					make_task_component('assign_crew'),
					make_task_component('wait','wait1',1),
					make_task_component('create_popup','Captain',dialogue_params[angle] or dialogue_params['unknown']),
					make_task_component('set_seated', 'Captain', 'Captain'),
					make_task_component('manipulate_helm', 'Captain', {axis_da = params[angle] or 0}),
				}
			} end,

			['rudder midships'] = function() return{
				name = 'rudder midships',
				priority = 1,
				required_crew = {'Captain'},

				task_components = {
					make_task_component('assign_crew'),
					make_task_component('wait','wait1',0.5),
					make_task_component('create_popup','Captain','Rudder midships, aye'),
					make_task_component('set_seated', 'Captain', 'Captain'),
					make_task_component('manipulate_helm', 'Captain', {axis_da = 0}),
				}
			} end,

			['fight fire'] = function() return{
				name = 'fight fire',
				priority = 0,
				required_crew = {'Engineer'},

				task_components = {
					make_task_component('assign_crew'),
					make_task_component('give_item', 'Engineer', 'fire_extinguisher', false, true),
					make_task_component('give_item', 'Engineer', 'firefighter'),
					make_task_component('wait', 'wait1', 5),
					make_task_component('give_item', 'Engineer', 'fire_extinguisher', true, true),
					make_task_component('give_item', 'Engineer', 'firefighter', true)
				}
			} end,

		}
	} end,
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

	-- Hack to maintain the available tasks constructor methods (and the conditional methods lol nothing is real)
	for ship_id, ship_object in pairs(g_savedata.ships) do 
		ship_object.available_tasks = {}
		ship_object.available_tasks = g_ships[ship_object.spawn_name]().available_tasks
		debugLog(ship_object.name..' task reinitialization complete. Sanity check: ')
		for task_name, task_object in pairs(ship_object.available_tasks) do 
			debugLog(task_name..' type: '..type(task_object))
		end 

		for task_id, task_object in pairs(ship_object.tasks) do 
			debugLog('Dumping task '..task_object.task_name..' on ship '..ship_object.name)
			if Ship:complete_task(ship_object, task_object.task_name, task_id) then 
				debugLog('Success!')
			else 
				debugLog('Failed to stop task.')
			end 
		end

		for crew_name, crew_object in pairs(ship_object.crew) do 
			Crew:complete_task(crew_object)
		end 

		printTable(ship_object.tasks, 'tasks after load')
	end 

	g_zones = server.getZones('spawn_location')
	g_zones_hospital = server.getZones("hospital")

	-- Add spawn orientation to zone parameters
	for zone_index, zone_object in pairs(g_zones) do 
		for tag_index, tag_object in pairs(zone_object.tags) do
			if string.find(tag_object, "spawn_orientation=") ~= nil then 
				zone_object.orientation = tonumber(string.sub(tag_object, 19))
			else 
				zone_object.orientation = 0
			end 
		end 
	end 
end

--End all tasks prior to quitting save
function onDestroy()
	--Why doesn't this work??
	for ship_id, ship_object in pairs(g_savedata.ships) do
		for task_id, task_object in pairs(ship_object.tasks) do 
			debugLog('Dumping task '..task_object.task_name..' on ship '..ship_object.name)
			if Ship:complete_task(ship_object, task_object.task_name, task_id) then 
				debugLog('Success!')
			else 
				debugLog('Failed to stop task.')
			end 
		end 
	end 
end 

function onPlayerJoin(steamid, name, peerid, admin, auth)
	if g_savedata.ships ~= nil then
		for k, ship_data in pairs(g_savedata.ships) do
			for k, marker in pairs(ship_data.map_markers) do
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
	for _, ship_data in pairs(g_savedata.ships) do
		removeMissionMarkers(ship_data)
		Ship:rebuild_ui(ship_data)
	end
end

function onTick(delta_worldtime)
	for _, ship_data in pairs(g_savedata.ships) do
        Ship:tick(ship_data)
    end 
end

function onChatMessage(peer_id, sender_name, message)
	local command = split(message)
	local ship_id = find_ship_id(command[1]) 
	if ship_id then 
		local task_name = table.concat(command, ' ', 2)
		local ship_data = g_savedata.ships[ship_id]
		local is_task_found, params = is_task_string(task_name, ship_data.available_tasks) --This could change if tasks become ship-specific
		if is_task_found and params then
			debugLog('params found') 
			Ship:create_task(ship_data, is_task_found, params)
		elseif is_task_found and not params then 
			Ship:create_task(ship_data, is_task_found, task_name)
		elseif ship_data.states.user_input_stack[task_name] then
			ship_data.states.user_input_stack[task_name].called = true 
		elseif command[2] == 'stop' then 
			if command[3] == 'all' then 
				for task_id, task_object in pairs(ship_data.tasks) do 
					Ship:complete_task(ship_data, '', task_id)
				end
				return true  
			end 
			local task_name = table.concat(command, ' ', 3)
			if Ship:complete_task(ship_data, task_name) then 
				debugLog('Stopped task '..task_name..' on vehicle '..ship_id..'.')
			else
				debugLog('Could not end task: no task found with that name')
			end  
		else
			debugLog('No task found with that name')
		end 
	end 
end

function onCustomCommand(message, user_id, admin, auth, command, one, ...)
	math.randomseed(server.getTimeMillisec())

	local name = server.getPlayerName(user_id)

    if command == "?despawnall" and admin == true then
		despawnAllShips()
    end

	if command == "?spawnship" and admin == true then 
		local params = {...}
		--WIP
		local custom_name = params[1] 
		local is_ocean_zone = (params[2] == 'ocean')
		local ship_id = create_ship(user_id, one, custom_name, is_ocean_zone)
		debugLog(ship_id)
	end 

	if command == '?printsensordata' then 
		for ship_id, ship_data in pairs(g_savedata.ships) do 
			Ship:print_sensor_data(ship_data)
		end 
	end 

    if command == "?log" and admin == true then
        printLog()
    end

    if command == "?printdata" and admin == true then
        server.announce("[Debug]", "---------------")
        printTable(g_savedata, "g_savedata")
        server.announce("", "---------------")
    end

	if command == '?printtasks' and admin == true then 
		server.announce("[Debug]", "---------------")
		for ship_id, ship_object in pairs(g_savedata.ships) do
			debugLog('Vehicle '..ship_object.name)
			printTable(ship_object.tasks, 'tasks') 
		end 
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
			printTable(ship_data, 'Ship ')
		end
		local len = tableLength(g_savedata.valid_ships)
		debugLog('	Total: '..tostring(len))
	end

	if command == "?unittest" and admin == true then
		if one == 'tasks' then 
			test_tasks()
		end 
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
	for _, ship_data in pairs(g_savedata.ships) do
		if ship_data.states.addon_information.id == vehicle_id then 
			Ship:on_vehicle_load(ship_data)
		end 
	end
end

function onVehicleUnload(vehicle_id)
	for _, ship_data in pairs(g_savedata.ships) do
		if ship_data.states.addon_information.id == vehicle_id then 
			Ship:on_vehicle_unload(ship_data)
		end 
	end
end 


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

-- checks if a specific tag string appears in a table of tag strings
function hasTag(tags, tag)
	for k, v in pairs(tags) do
		if v == tag then
			return true
		end
	end

	return false
end

function findSuitableZone(player_id, vehicle_data, is_ocean_zone)
	local min_range = 0 
	local max_range = 1500
	if is_ocean_zone then --Sanity check
		local ocean_transform, is_ocean_found = server.getOceanTransform(server.getPlayerPos(player_id), min_range, max_range)
		return ocean_transform
	else 
		-- Find all qualifying zones
		local zones = findSuitableZones(vehicle_data)

		-- Find the nearest zone among qualifying zones
		local player_transform = server.getPlayerPos(player_id)
		local distance_to_zone = math.huge
		local selected_zone_index

		for zone_index, zone_object in pairs(zones) do 
			local d = matrix.distance(player_transform, zone_object.transform)
			if d < distance_to_zone then 
				distance_to_zone = d 
				selected_zone_index = zone_index 
			end 
		end 

		debugLog('Spawning vehicle at zone '..zones[selected_zone_index].name..'.')
		local spawn_transform = zones[selected_zone_index].transform
		local spawn_direction = zones[selected_zone_index].orientation 

		local x, z = bearing_to_vector(spawn_direction) 
		local rotation_matrix = matrix.rotationToFaceXZ(x, z)
		local spawn_transform = matrix.multiply(spawn_transform, rotation_matrix)
		return spawn_transform
	end 
end 

--- Returns a table of suitable zones
function findSuitableZones(vehicle_data)
	local zones = {}
	for zone_index, zone_object in pairs(g_zones) do 
		local is_filter = false 

		-- Filter size
		if vehicle_data.size == "small" then
			if hasTag(zone_object.tags, "size=small") == false and hasTag(zone_object.tags, "size=medium") == false and hasTag(zone_object.tags, "size=large") == false then
				is_filter = true
			end
		elseif vehicle_data.size == "medium" then
			if hasTag(zone_object.tags, "size=medium") == false and hasTag(zone_object.tags, "size=large") == false then
				is_filter = true
			end
		elseif vehicle_data.size == "large" then
			if hasTag(zone_object.tags, "size=large") == false then
				is_filter = true
			end
		end

		-- Filter for type of vehicle
		if not hasTag(zone_object.tags, 'vehicle_type='..vehicle_data.vehicle_type) then 
			is_filter = true 
		end 

		if is_filter == false then 
			table.insert(zones, zone_object)
		end 
	end 

	debugLog('Found '..tableLength(zones)..' qualifying zones out of '..tableLength(g_zones)..' total.')
	return zones 
end 

-- Splits string, default separator is whitespace (%s)
function split(inputstr, sep)
	if sep == nil then
			sep = "%s"
	end
	local t={}
	for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
			table.insert(t, str)
	end
	return t
end

--- Find a given ship from the list of spawned ships
function find_ship_id(ship_name)
	local _ = false
	
	for index,ship in pairs(g_savedata.ships)do
	_ = (ship_name==ship.states.addon_information.name) and index or _
	end

	return _
end

--- Find a given task ID by the task's name
function find_task_by_name(task_name, t)
	local _ = false
	if t then
		for index,value in pairs(t)do
		_=(task_name==value.task_name) and index or _
		end
	end
	return _
end

function subset(input_table, j, k)
	local output = {}
	for i=j,k do 
		table.insert(output,input_table[i])
	end 
	return output
end 

--- Takes a possible task string and determines whether it is part of a valid task,
--- as well as whether there are custom parameters to be passed to the task
function is_task_string(task_name, available_tasks)
	local task_name = split(task_name)
	for k,v in ipairs(task_name) do 
		local candidate_string = table.concat(subset(task_name, 1, k), ' ')
		if find_table_index(candidate_string, available_tasks) then 
			if k == #task_name then 
				return candidate_string, nil 
			else 
				return candidate_string, subset(task_name, k+1, #task_name)
			end 
		end 
	end 

	return false, nil 
end 

--- Check if a given key exists in an unordered table
--- @param v The key to find
--- @param t table The table to search
function find_table_index(v,t)
	local _ = false
	if t then
		for index,value in pairs(t)do
		_=_ or (v==index)
		end
	end
	return _
end

--- Check if a given value exists in an unordered table
--- @param v The value to find
--- @param t table The table to search
function find_table_value(v,t)
	local _ = false
	if t then
		for index,value in pairs(t)do
		_=_ or (v==value)
		end
	end
	return _
end

--- Convert compass bearing (north as 0, clockwise) to a unit vector
--- @param compass_bearing number The compass bearing to read
--- @return number x The x-component of the unit vector
--- @return number y The y-component of the unit vector
function bearing_to_vector(compass_bearing)
	local currentHeadingDeg = 450 - compass_bearing % 360 --convert compass bearing to degrees
	local unit_x,unit_y = math.cos(math.rad(currentHeadingDeg)),math.sin(math.rad(currentHeadingDeg))

	return unit_x, unit_y
end 

--- Recursively looks through a given table and finds all of the functions. Returns a parallel table with values of true if the input value is a table, false otherwise.
function find_functions(table)
	local output_table = {}

	for k, v in pairs(table) do 
		if k ~= 'methods' then --Ignore the output table (which is also in g_savedata)
			local vtype = type(v) 
			if vtype == 'table' then 
				-- Continue traversing the table
				output_table[k] = find_functions(v)
			elseif vtype == 'function' then 
				output_table[k] = (vtype == 'function')
			end 
		end
	end 

	return output_table
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

function addPopup(popup_id, char_id, table_to_store, popup_text, popup_lifespan )
	-- Add a character dialogue popup
	server.setPopup(-1, popup_id, '', true, popup_text, 0, 0, 0, 10, nil, char_id)
	table.insert(table_to_store, {text=popup_text, id=popup_id, active=true, lifespan = popup_lifespan})
end	

-------------------------------------------------------------------
--
--	 Unit Testing
--
-------------------------------------------------------------------

function test_tasks()
	local tests = {
		{name = 'Has name?', arg = 'name', test = function(name) if name then return true else return false end end},
		{name = 'Valid priority?', arg = 'priority', test = function(priority) if priority >= 0 and priority <= 3 then return true else return false end end},
		{name = 'Is crew value a table?', arg = 'required_crew', test = function(required_crew) if type(required_crew) == 'table' then return true else return false end end},
		{name = 'Are the task components of valid type?', arg = 'task_components', test = function(components) for k,v in ipairs(components) do 
																					if type(v) == 'table' and v.component then return true else return false end end end},
		{name = 'Is the task name a restricted word?', arg = 'name', test = function(name) return (name == 'stop') and false or true end},
		{name = 'Valid override behavior parameter?', arg = 'override_behavior', test = function(arg) return (arg == 'wait') or (arg == nil) end},
	}
	for ship_name, ship_data in pairs(g_ships) do 
		local ship_data = ship_data()
		debugLog('Testing tasks for ship: '..ship_data.name)
		local tasks = ship_data.available_tasks
		for task_name, task_subclass in pairs(tasks) do 
			task_object = task_subclass()
			debugLog('Testing task '..task_name..'...')
			local test_results = {}
			local passed = 0
			for index, test in ipairs(tests) do 
				local is_success = test.test(task_object[test.arg])
				if is_success then passed = passed + 1 end 
				table.insert(test_results, {name = test.name, passed = is_success})
			end 
			debugLog('Passed '..passed..'/'..#test_results..' tests.')
			for index, result in ipairs(test_results) do 
				if not result.passed then 
					debugLog('Failed test #'..index..': '..result.name)
				end 
			end 
		end 
	end 
end 