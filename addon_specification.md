## AI SHIPS

[note: this is the original specification document for the addon, provided for historical purposes. These features may or may not be present in the current or final versions.]

General info and capabilities:
- AI crew capable of navigating, starting up, manipulating deck functions
- AI crew should have names, work locations, dialogue
- Players can issue general pathfinding commands (navigate to x location, navigate to my location), which can be fulfilled regardless of whether the ship is loaded
- Players can also issue specific orders (increase speed, right full rudder) while they are onboard, but not while the ship is unloaded

Structural outline:
- Ships are objects
    - Players spawn ships, then enter a command which associates the spawned object with the virtual object
        - On reflection, I don't think this will work - the ship will have to be spawned as a mission object 
    - Ships can be switched from manual (player) control to automatic (NPC) control
    - Control of ships happens via chat commands and (possibly) interactions with ship instruments
    - Ships have a set of state information (measurements such as speed, position, etc, as well as onboard state such as whether the lights are on) 
        and capabilities (turning engines on/off, navigation, preparing flight deck for landing, etc)
    - Specific capabilities are actualized in the form of tasks
        - Tasks have a priority level (in case of crew resource conflicts) and actions associated with setup, ongoing, and teardown phases
- Crewmembers are objects
    - Crewmember objects are spawned at the time of ship object creation
    - Crewmembers can access and manipulate ship methods (to simulate crewmembers interacting with duty stations)
    - Each crewmember object is associated with an NPC character, which may or may not be spawned in 
    - Crewmembers will have dialogue associated with their current actions

- Ships can spawn either on the nearest ocean tile or at a dock (denoted by a spawn zone)
