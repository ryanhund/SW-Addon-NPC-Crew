# Foucault's NPC Crew

## Description

This addon allows Stormworks players to give their vessels NPC crewmembers that follow orders, perform shipboard tasks, and can navigate the vessel while it is despawned. 

This addon is still WIP. As of yet there is no public release.

# To-do:

## Finish before beta-0.1

### Task logic
- [DONE 8/31] Give/take item primitive
- [DONE 8/29] Component branching
- [DONE 8/30] Helm interaction
- [DONE 8/29] Manually stop ongoing task
- [DONE 8/31] Stop all ongoing tasks
- [DONE 8/28] Wait for user input
- [DONE 9/01] Task overrides
- [DONE 9/08] Set keypad primitive
- More flexible task creation: see discussion below
- "Complete task" method for teardown tasks
- Add flag for whether multiple instances of a task can run simultaneously, check for duplicates at creation
- [DONE 8/31] Allow users to pass parameters to tasks

### Ship Features

- Distinguish between loaded and unloaded in ship and task logic
- Implement vehicle movement while unloaded

### Ship creation interface

- [DONE 8/30] Spawn zones
- [DONE 8/30] Tasks attached to ships rather than global
- [DONE 8/30] (except for routines) All data about a particular vehicle stored in one table
- Allow more than one ship of each type to spawn (custom names?)


### The Big Kahuna

- [DONE 8/31] Refactor ship, crew, and task objects to separate data from methods

### Bugfixes

- Ghost vessel spawning after save/load
- Investigate create_task method call inside onChatMessage (not passing task_name?)

## Finish before v1.0

- Help popups for tasks (prompt for next instruction) and basic program navigation
- Change important notifications from chat messages to popups
- Consider moving object spawn logic outside of Ship.init()
- Implement unit tests for all user-defined data

## Finish before v2.0

- Enhanced character realism with ability to change look direction
- Optional/required crewmembers 
- Check if any vehicle is in spawn zone before spawning, using server.isInTransformArea()
- Character dialogue through radio feature

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

# Copyright Notice

Foucault's NPC Crewmembers Addon
Copyright (C) 2021 Ryan Hund

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
