# Feature Roadmap

## Default control scheme for player-created vehicles

- The expected vehicle-creation paradigm is for each creator to write their own extension to the addon and spawn it through the addon system. They would customize both their vehicle and the addon, and then release the vehicle to the workshop separately, or collaborate with me to release it as part of the main addon.
- However, some players may want to create their own vehicles e.g. in survival mode and use the addon 'plug and play,' without publishing their own version. 
- Thus, a limited featureset should be implemented with standardized variable names and processes, which would allow player-constructed career mode vessels to work with the addon.
- This default control scheme would have to be simplified significantly, with more work happening on the vehicle end. For example, an engine start sequence would be triggered by a single addon button press, with all of the sequencing done by the player. This resembles the default AI vehicle addon included in the base game.

## Hireable crewmembers

- Crewmembers would need to be separable from the ship
- Tasks could have required and optional crewmembers
- Crewmembers paid per day, with increasing rates for more expertise

Ideas:
- Helmsman allows you to send basic helm and navigation commands 
- Engineer allows for damage control, NPC engine startup, maybe gives a bonus to fuel efficiency via setVehicleTank
- Deckhand allows for operation of davits, extra damage control, etc
- Second deckhand opens up more complex evolutions like flight deck operations
- Officer of the Deck, plus helmsman and engineer, are required to let the vessel operate remotely (outside of load range)
- Night-shift crew allows the ship to operate 24 hours a day