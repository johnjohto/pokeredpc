extends "res://scripts/MapScripts.gd"
## scripts/CeladonMansion3F.asm — the GAME FREAK dev floor. The game designer checks the
## POKéDEX: at NUM_POKEMON - 1 owned (150 — Mew doesn't count) his CompletedDexText leads
## into the DIPLOMA screen (callfar DisplayDiploma); below that the normal map text shows.


func on_interact(_front: Vector2i, npc) -> bool:
	if npc == null or npc.key != "SPRITE_SILPH_WORKER_M@2,3":
		return false
	main._sync_owned()
	if main.pokedex_owned.size() < 150:
		return false                       # the regular designer line (map text fallback)
	face_player(npc)
	_award_diploma()
	return true


func _award_diploma() -> void:
	main.cutscene_active = true
	await main.cutscene.say("Wow! Excellent!\nYou completed\nyour POKéDEX!\nCongratulations!\n...")
	main.modal = main.diploma
	main.diploma.open_card()
	await main.diploma.closed
	main.cutscene_active = false
