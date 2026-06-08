return PlaceObj('ModDef', {
	'title', "Force Delete",
	'description', [[Delete what normal demolition cannot: stuck objects such as bugged train tracks, and advanced targets such as colonists, deposits, scenario decorations, etc.

------------------------------------------------------------

Level 1 — Standard Force Delete

For normal demolishable objects. It uses the game’s standard demolition path when possible, making it the safer option.

Shortcuts:

PC: Ctrl + Delete
Xbox [not tested]: LB + RB + X
PlayStation [not tested]: L1 + R1 + Square
------------------------------------------------------------

Level 2 — Advanced Force Delete

For harder cases that may need extra cleanup, including colonists, deposits, scenario decorations, and staged domes. This mode is more aggressive and may cause crashes, especially when deleting fully functioning domes.

Shortcuts:

PC: Ctrl + Shift + Delete
Xbox [not tested]: LB + RB + Y
PlayStation [not tested]: L1 + R1 + Triangle
------------------------------------------------------------

Tested only on Surviving Mars Relaunched v1.0.7 on Windows 11.
Please complain! I can’t fix what I don’t know is broken: https://github.com/facazevedo/surviving-mars-relaunched-mods/issues]],
	'short_description', "Ctrl+Delete force-deletes the selected object.",
	'image', "Mod/ForceDelete/Images/force_delete.jpg",
	'last_changes', "Fixed a Mod Manager load error by deferring Force Delete shortcut registration until the game shortcut host is ready",
	'id', "ForceDelete",
	'author', "fredware",
	'version', 7,
	'lua_revision', 350453,
	'saved_with_revision', 392284,
	'code', {
		"Code/ForceDelete.lua",
		"Code/fd_config.lua",
		"Code/fd_display_attributes.lua",
		"Code/fd_colonist.lua",
		"Code/fd_drone.lua",
		"Code/fd_animal.lua",
		"Code/fd_shuttle.lua",
		"Code/fd_rover.lua",
		"Code/fd_train.lua",
		"Code/fd_rocket.lua",
		"Code/fd_deposit.lua",
		"Code/fd_decoration.lua",
		"Code/fd_infrastructure.lua",
		"Code/fd_internal_building.lua",
		"Code/fd_external_building.lua",
		"Code/fd_dome.lua",
	},
	'saved', 1779116850,
	'code_hash', 6476367783130840546,
	'pdx_id', 144462,
	'pdx_version', "2",
	'TagInterface', true,
})
