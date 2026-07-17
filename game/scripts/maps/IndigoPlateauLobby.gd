extends "res://scripts/MapScripts.gd"
## scripts/IndigoPlateauLobby.asm — the reset that makes the Elite Four a *gauntlet*.
##
## Coming back down here wipes the whole Indigo Plateau event range
## (`ResetEventRange INDIGO_PLATEAU_EVENTS_START, EVENT_LANCES_ROOM_LOCK_DOOR`) whenever the challenge
## was already under way (`BIT_STARTED_ELITE_4`, set when LORELEI's room loads). So the four must be
## beaten in one run: step back into the lobby to heal and every one of them stands up again, their exit
## seals close, and LANCE's door unlocks. `EVENT_BEAT_CHAMPION_RIVAL` sits past the end of the range and
## survives. The lobby also clears Victory Road 1F's boulder switch on the way through.
##
## The unlock is what makes a whiteout recoverable: a lost fight sends you to the last Center you healed
## at, and the walk back always passes through here.

func on_enter() -> void:
	clear_event("VR1_SWITCH")                     # ResetEvent EVENT_VICTORY_ROAD_1_BOULDER_ON_SWITCH
	if not has_event("STARTED_ELITE_4"):
		return                                    # the challenge was never begun — nothing to undo
	main.reset_elite4_gauntlet()
