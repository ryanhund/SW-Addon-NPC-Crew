# To-do:

## Finish before beta-0.1

### Task logic
- Give/take item primitive
- [DONE 8/29] Component branching
- Helm interaction
- [DONE 8/29] Manually stop ongoing task
- Stop all ongoing tasks
- [DONE 8/28] Wait for user input
- Task overrides
- More flexible task creation: see discussion below
- "Complete task" method for teardown tasks
- Add flag for whether multiple instances of a task can run simultaneously, check for duplicates at creation

### Ship Features

- Distinguish between loaded and unloaded in ship and task logic

### Ship creation interface

- Tasks attached to ships rather than global
- All data about a particular vehicle stored in one table

### The Big Kahuna

- Refactor ship, crew, and task objects to separate data from methods

## Finish before v1.0

- Implement vehicle movement while unloaded
- Allow more than one ship of each type to spawn (custom names?)
- Consider moving object spawn logic outside of Ship.init()
- Implement unit tests for all user-defined data

## Finish before v2.0

- Optional/required crewmembers 

# Feature Discussion

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

## 
 
- When tasks complete, do they reset buttons, etc back to their initial values? 

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