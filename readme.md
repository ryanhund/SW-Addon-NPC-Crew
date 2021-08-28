## What can create a task?

- Players  
- Callbacks (world events such as proximity alarms, fires)  
- Timed (ex: shift changes)  
- Random (just for fun)  
- Other tasks

## What actions can be taken as part of a task?

- [x] Character movement 
- [x] Button presses  
- [?] Helm interaction  
- [x] Dialogue  
- [x] Waiting  
- [x] Conditional based on sensor data  
- Give/take items

## How do tasks interact with each other? 

- Tasks of higher priority supercede tasks of lower priority  
- Tasks also need to be able to supercede each other: "turn left" should automatically override "turn right"  
- Does supercede mean pause and wait to continue, or does it mean cancel task execution? Can this change during the course of a task?

## How can a task end? What should happen when a task ends?

- Timeout
- Player
- Completion of objectives
- Callback
 
##

- [x] Characters can return to an idle position  
- Or, they can remain in their current position  

## Should character positioning be part of the task system, or should it be connected to the characters?

- Would require a list of possible locations  
- If task is equal or higher priority as another task in the same location, perform both at the same time 

## Character ideas

- [x] Default routines instead of default locations - duty station, rest, sleep

# Tasks
- Navigation
    - Speed orders (ahead full, stop, etc)
    - course change orders (right full rudder)
    - Autopilot orders (navigate to x)
    - bow thrusters
    - Turn on/off navigation lights
    - Raise/lower mast
- Deck
    - Launch/Recover RHIB
    - Flight Deck operations - prepare for takeoff or landing 
    - Drop/Raise Anchor
    - Bunkering
- Engine 
    - Start engines
    - Shut down engines
    - Run generator
    - Switch to reserve fuel
- Operations
    - Operate radar 
    - Operate sonar 
    - Transponder contact readout
- Emergency
    - Fight fire (engine room)
    - Fight fire (general)
    - Abandon ship 
    - Damage control