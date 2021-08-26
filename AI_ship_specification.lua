--[[
AI SHIPS

General info and capabilities:
-AI crew capable of navigating, starting up, manipulating deck functions
-AI crew should have names, work locations, dialogue
-Players can issue general pathfinding commands (navigate to x location, navigate to my location), which can be fulfilled regardless of whether the ship is loaded
-Players can also issue specific orders (increase speed, right full rudder) while they are onboard, but not while the ship is unloaded

Structural outline:
-Ships are objects
    -Players spawn ships, then enter a command which associates the spawned object with the virtual object
        -On reflection, I don't think this will work - the ship will have to be spawned as a mission object 
    -Ships can be switched from manual (player) control to automatic (NPC) control
    -Control of ships happens via chat commands and (possibly) interactions with ship instruments
    -Ships have a set of state information (measurements such as speed, position, etc, as well as onboard state such as whether the lights are on) 
        and capabilities (turning engines on/off, navigation, preparing flight deck for landing, etc)
    -Specific capabilities are actualized in the form of tasks
        -Tasks have a priority level (in case of crew resource conflicts) and actions associated with setup, ongoing, and teardown phases
-Crewmembers are objects
    -Crewmember objects are spawned at the time of ship object creation
    -Crewmembers can access and manipulate ship methods (to simulate crewmembers interacting with duty stations)
    -Each crewmember object is associated with an NPC character, which may or may not be spawned in 
    -Crewmembers will have dialogue associated with their current actions

-Ships can spawn either on the nearest ocean tile or at a dock (denoted by a spawn zone)

Known limitations:
-All crew must be unique. Only a particular crewmember can perform a particular task, there is no way to have (say) two basic sailors who are totally interchangeable

TODO:
-Write own spawn function based on spawnAddonComponent - spawnObject and spawnObjects are unnecessary


]]

function Ship(ship_data) return {
    crew = {},
    tasks = {}, --task priority: 0 for emergencies, 1 for urgent, 2 for normal, 3 for routine/maintenance, math.huge for idle (crewmembers only)
    states = {
        addon_information = {} --includes the vehicle ID
        sensors = {}, --external sensor input (speed, GPS, etc)
        onboard_information = {}, --onboard states such as whether the lights are on
    },
    init = function(self, ship_data)
        --use iterObjects and getLocationData to find ship information - how is this passed from the spawn command? 
        
        --initialize the sensor readings
        for sensor_id, sensor_name in ipairs(ship_data.sensors) do 
            self.states.sensors[sensor_name] = {id = sensor_id, value=0}
        end 

        --Spawn the objects
        --TODO: we'll see

        --need:
        --spawn zone transform
        --location - refers to filesystem location with playlist and location index 
        --object descriptor (this is all in g_savedata.valid_ships[ship_name].objects)
        --parent_vehicle_id should be 0 or nil
        --  for crew, should be spawned_objects[0].id 
        local spawned_objects = {}
        
        --spawn the ship 
        spawnObject(spawn_transform, location, object, parent_vehicle_id, spawned_objects, g_spawned_objects),


        --spawn all of the crewmembers associated with the ship
        self.crew = ship_data.crew
        for crewmember_name, crewmember in pairs(self.crew) do 
            spawnObject(spawn_transform, location, object, parent_vehicle_id, spawned_objects, g_spawned_objects)
        end 



        self.states.addon_information.id = spawned_objects.vehicles[1].id 
        self.states.addon_information.transform = 
        self.states.addon_information.popups = {}

    end,

    tick = function(self)
        --update all sensors and onboard statuses
        for _, sensor_data in pairs(self.states.sensors) do 
            local value = server.getVehicleDial(self.states.addon_information.id, 'sensor'..tostring(sensor_data.id))
            sensor_data.value = value
        end 

        --loop through ongoing tasks and call each in turn
        for k, task in pairs(self.tasks) do 
            local is_complete = false 
            task.task_data, is_complete = task:tick(task.task_data, self.states)
            if is_complete then 
                --Return crew states to idle 
                for crew_name, crewmember in pairs(task.task_data.assigned_crew) do 
                    crewmember:complete_task()
                    server.setCharacterSeated(crewmember.id, self.states.addon_information.id, crewmember.idle_location)

                end
                self.tasks[k] = nil --remove the completed task 
            end 
        end
    end,

    create_task = function(self, task) --task is a string with the variable name of the task
        --Check to make sure task doesn't already exist

        --Create the task
        local task_data = g_tasks[task].init()

        --Populate the task with crewmembers
        for _,role in pairs(task_data.required_crew) do 
            local found = false 
            for crew_name, crew_object in pairs(self.crew) do 
                if crew_object.role == role then 
                    task_data.assigned_crew.role = crew_object --!! not sure if I should use the name or the object here
                    found = true 
                end 

                if found then break end 
            end 
        end 

        --Store the task in the ship's tasks table
        table.insert(self.tasks, {task, task_data}) --'task' is the variable name of the task (eg, g_tasks.turn_on_the_lights).
    end,

}
end 


function Crew(role, idle_location) return { 
    role = role,
    idle_location = idle_location,
    current_task = {t = 'idle', priority = math.huge}, --default task is 'idle'

    assign_to_task = function(self, task_name, task_priority)
        --Check if crewmember is already performing the task
        if task_name == self.current_task.t then return true end

        --Check for priority levels - if new task is higher priority (lower priority # than old task), the old task is overridden
        if self.current_task.priority > task_priority then 
            self.current_task.t = task_name 
            self.current_task.priority = task_priority
            return true 
        end 
        return false 
    end,

    complete_task = function(self)
        self.current_task.t = 'idle'
        self.current_task.priority = math.huge 

        return true
    end,

    tick = function(self)
        
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
        lifespan = 0,
    }
end

g_tasks = {

    --task method is responsible for allocating the crew (making sure that each one is doing the right thing)
    turn_on_the_lights = {
        init = new_task('Turn on the lights', 3, {'sailor'}),

        tick = function(self, task_data, ship_states)
            task_data.lifespan = task_data.lifespan + 1

            local is_success = true 
            for _,crewmember in task_data.assigned_crew do 
                is_success = crewmember:assign_to_task(task_data.task_name, task_data.task_priority)
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
    }
}

function create_ship_squirrel():
    local name = 'Squirrel'
    crew = {
        captain = Crew('helmsman', 'idle1'),
        engineer = Crew('engineer', 'idle2')
    }