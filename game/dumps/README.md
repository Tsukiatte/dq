Place-file dumps made with tools/rbxl.py (scripts.txt = every LocalScript/ModuleScript source the client had; tree.tsv = class + full path of every instance).

nl_fight_save/        Northern Lands, saved MID-FIGHT on the Midgardian Champion (place 85776757589518 Level(2).rbxl)
aquatic_temple_save/  Aquatic Temple (place 85776757589518 Level(4).rbxl)

Server Scripts are never in a client save. Look in scripts.txt for mapSpecificLocals (client handlers of every *BossSpecficEvents remote), the abilities, and StarterCharacterScripts.HumanoidStates (the client anticheat, obfuscated).
