-- mn_config.lua
-- Central configuration, feature flags, default-spam rules and protected groups.
-- This is the canonical configuration source for the mod. Do not duplicate these
-- values elsewhere.

MN_Config = {
	MOD_ID = "MuteNotifications",
	MOD_DISPLAY_NAME = "Mute Notifications",

	-- Canonical behaviour version (separate from metadata.lua mod 'version').
	VERSION = "0.8.3",

	-- Feature flags --------------------------------------------------------
	ENABLE_MOD = true,            -- master switch for voice suppression
	PATCH_AUDIO_OPTIONS = true,   -- try to add the row under Options -> Audio
	SHOW_PANEL_IN_MAIN_MENU = true,
	SHOW_PANEL_IN_INGAME_MENU = true,
	USE_TEXT_FALLBACK = true,     -- match by voiced text when id is unknown
	-- Vanilla behaviour: every notification voice is allowed. Keep false so the mod
	-- mutes nothing until the player chooses. Set true to auto-mute the known
	-- building/shuttle/drone spam lines on first run (see MN_DefaultSpamVoiceRules).
	DEFAULT_MUTE_SPAM = false,
	ENABLE_PLAY_PREVIEW = true,   -- per-row play/preview button in the panel

	-- Debug flags (must be real booleans) ----------------------------------
	DEBUG = false,                -- master debug flag
	DEBUG_CATALOG = false,        -- log full catalog on build
	DEBUG_SUPPRESSION = false,    -- log each allow/suppress decision
	DEBUG_UI = false,             -- log panel / options-patch UI work
	DEBUG_PERSISTENCE = false,    -- log load/save of user settings
	-- Independent of DEBUG: prints detailed Audio-options-patch diagnostics.
	DEBUG_AUDIO_PATCH = true,

	-- Custom options-row editor type used by the Audio-page patch. Must not
	-- collide with a vanilla editor (bool/number/choice/hotkey/...).
	AUDIO_OPTION_EDITOR = "mn_open_panel",
	AUDIO_OPTION_ID = "MN_ConfigureMutedVoices",
}

-- The game's localized voiced text is normally the recorded transcript, but a
-- small number of shipped recordings differ from that source text. Keep these
-- display-only corrections separate so voice lookup, preview playback and mute
-- persistence continue using the original game text and translation id.
MN_SpokenTextOverrides = {
	["Construct two Hydroponic Farms in the new Dome. They will be used as workplaces for the Colonists in the old Dome once the Domes are connected."] =
		"Construct two Farms in the new Dome. They will be used as workplaces for the Colonists in the old Dome once the Domes are connected.",
}

-- Default spam mute rules. match_ids are checked first (preferred, stable);
-- match_text is a lowercase-substring fallback against the voiced text.
-- categories are panel filter labels; entries may have more than one.
--
-- IMPORTANT: the real, verified base-game voiced notification ids were
-- confirmed from C:\Games\Surviving Mars Relaunched\ModTools\Src\Data\NotificationPreset.lua.
-- The verified ids are listed FIRST in each rule. The remaining ids are
-- defensive supersets (other Surviving Mars variants / possible DLC ids); they
-- are harmless if absent and simply never match. Only entries that actually
-- exist in the runtime catalog can ever be muted.
MN_DefaultSpamVoiceRules = {
	BuildingNotWorking = {
		label = "Building not working",
		categories = { "Building", "Spam" },
		mute_by_default = true,
		match_ids = {
			"NotWorkingBuildings",        -- VERIFIED base game: "A building has stopped working"
			"BuildingNotWorking", "BuildingStoppedWorking", "WorkingBuildingNotWorking",
			"NonWorkingBuilding", "BuildingMalfunction", "BuildingDisabled",
			"BuildingNoPower", "BuildingNoWater", "BuildingNoOxygen", "BuildingFrozen",
			"BuildingNotEnoughWorkers", "BuildingNoWorkers",
		},
		match_text = {
			"building has stopped working", "building stopped working",
			"building not working", "buildings not working",
			"buildings are not working", "stopped working", "malfunctioned",
			"not enough workers", "no workers",
		},
	},
	ServiceBuildingNotWorking = {
		label = "Service building not working",
		categories = { "Building", "Service", "Spam" },
		mute_by_default = true,
		match_ids = {
			"ServiceBuildingNotWorking", "ServiceBuildingsNotWorking",
			"ServiceUnavailable", "MissingService", "NoServiceBuilding",
			"ComfortServiceUnavailable", "DomeServiceMissing",
		},
		match_text = {
			"service building not working", "service buildings are not working",
			"service buildings not working", "service unavailable", "missing service",
		},
	},
	HeavyShuttleLoad = {
		label = "Heavy shuttle load",
		categories = { "Shuttle", "Spam" },
		mute_by_default = true,
		match_ids = {
			"HeavyShuttleWorkload",       -- VERIFIED base game: "Heavy Shuttle workload"
			"HeavyShuttleLoad", "ShuttleHeavyLoad", "ShuttleLoadHeavy",
			"ShuttleHubHeavyLoad", "ShuttleHubOverloaded", "ShuttleOverload",
			"TooManyShuttleRequests",
		},
		match_text = {
			"heavy shuttle workload", "heavy shuttle load", "shuttle workload",
			"shuttle load heavy", "shuttle hub heavy load", "shuttle hub overloaded",
			"too many shuttle requests", "shuttles are overloaded",
		},
	},
	DroneLoadHeavy = {
		label = "Heavy drone load",
		categories = { "Drone", "Spam" },
		mute_by_default = true,
		match_ids = {
			"HeavyWorkload",              -- VERIFIED base game: "Heavy Drone workload"
			"HeavyDroneLoad", "DroneHeavyLoad", "DroneHubHeavyLoad",
			"DroneHubOverloaded", "TooManyDroneRequests",
		},
		match_text = {
			"heavy drone workload", "heavy drone load", "drone workload",
			"drone load heavy", "drone hub heavy load", "drone hub overloaded",
			"too many drone requests",
		},
	},
	OrphanedDrones = {
		label = "Orphaned / idle drones",
		categories = { "Drone", "Spam" },
		mute_by_default = true,
		match_ids = {
			"OrphanedDrones",             -- VERIFIED base game: "Orphaned drones"
			"DronesIdle", "IdleDrones", "NoDroneControl", "DroneControlMissing",
			"DroneHubNotWorking", "OutOfDroneControl",
		},
		match_text = {
			"orphaned drones", "idle drones", "no drone control", "drone control",
			"out of drone control", "drone hub not working",
		},
	},
	NoActiveResearch = {
		label = "No active research",
		categories = { "Research", "Reminder" },
		mute_by_default = true,
		match_ids = { "NoActiveResearch", "ResearchNotSet", "NoResearchSelected" },
		match_text = { "no active research", "no research selected", "research not set" },
	},
	NoSectorScanning = {
		label = "No sector set for scanning",
		categories = { "Scanning", "Reminder" },
		mute_by_default = true,
		match_ids = { "NoSectorScanning", "NoSectorSetForScanning", "SectorScanningNotSet" },
		match_text = { "no sector set for scanning", "no sector selected for scanning", "sector scanning" },
	},
	ColonistsUnemployed = {
		label = "Unemployed colonists",
		categories = { "Colonists", "Spam" },
		mute_by_default = true,
		match_ids = { "UnemployedColonists", "ColonistsUnemployed", "NoJobs", "NotEnoughJobs" },
		match_text = { "unemployed colonists", "colonists are unemployed", "not enough jobs", "no jobs" },
	},
	StorageFull = {
		label = "Storage full",
		categories = { "Storage", "Spam" },
		mute_by_default = true,
		match_ids = { "StorageFull", "DepotFull", "WasteRockStorageFull", "DumpingSiteFull" },
		match_text = { "storage full", "depot full", "waste rock storage full", "dumping site full" },
	},
}

-- Notification groups protected from DEFAULT (automatic) muting. The user may
-- still mute these manually from the panel. Keyed by the real runtime group
-- names (verified base-game groups: Anomalies, Colonists, Default, Disasters,
-- Mystery). Extra names are kept for forward-compatibility with DLC/mods.
MN_ProtectedVoiceGroups = {
	Mystery = true,
	Disasters = true,
	Disaster = true,
	StoryBit = true,
	StoryBits = true,
	ColonistCritical = true,
	Rocket = true,
	Rockets = true,
	Anomaly = true,
	Anomalies = true,
	Colonists = true,
	Evaluation = true,
	Tutorial = true,
	GameOver = true,
	Milestone = true,
	Milestones = true,
}

-- Entries to exclude from the catalog entirely. Use for voiced_text that has no
-- recorded audio (Play would be silent and there is nothing to actually mute),
-- or for verified duplicate preset ids where another working copy is kept.
MN_ExcludedVoiceIds = {
	Placeholder_1 = true, -- duplicate "Commander, one other thing."; keep recorded Tutorial2_Popup6_RCRover
	Placeholder_2 = true, -- T(9430): no English voice sample in English.fpk
	Placeholder_3 = true, -- T(9431): no English voice sample in English.fpk
	Tutorial1_Popup1_Intro = true, -- duplicate "Welcome to Mars!"; keep WelcomeGameInfo
	Tutorial2_Popup13_1_Research2 = true, -- T(237604843581) has no English sample; keep duplicate T(9429)
	AllMilestonesCompleted = true, -- Play preview is silent; keep commented in MN_CustomNames for reference
	ColonyViabilityExit_Delay_LastArk = true, -- duplicate "This will go down in history."; keep ColonyViabilityExit_Delay
	ColonyViabilityExit_MartianBorn_LastArk = true, -- duplicate Martian-born line; keep ColonyViabilityExit_MartianBorn
	ToxicRains = true,    -- duplicate Toxic Rain alert; keep DisasterToxicRains
	ToxicRains2 = true,   -- duplicate Toxic Rain alert; keep DisasterToxicRains
}
MN_ExcludedVoiceGroups = {
	Challenge = true,   -- challenge popups have voiced_text but no recorded voice audio
}

-- Literal QueueVoice/PlayVoicedText calls that do not have a discoverable preset.
-- The translation id is required both for localized display and accurate preview.
MN_AdditionalVoices = {
	{ id = "Direct:AssemblySessionOpen", translation_id = 798844974010, voiced_text = "Assembly session open", group = "Politics" },
	{ id = "Direct:BuildingDestroyed", translation_id = 900050882412, voiced_text = "Building destroyed", group = "Building" },
	{ id = "Direct:CouncilSessionOpen", translation_id = 772603092668, voiced_text = "Council session open", group = "Politics" },
	{ id = "Direct:DroneDestroyed", translation_id = 351249859666, voiced_text = "Drone destroyed", group = "Drone" },
	{ id = "Direct:FactionPromiseBroken", translation_id = 601655654776, voiced_text = "Faction promise broken", group = "Politics" },
	{ id = "Direct:FactionPromiseKept", translation_id = 484102048919, voiced_text = "Faction promise kept", group = "Politics" },
	{ id = "Direct:NewFactionOpportunity", translation_id = 611198153779, voiced_text = "New Faction opportunity", group = "Politics" },
	{ id = "Direct:PoliticalCrisisImminent", translation_id = 889796591446, voiced_text = "Political crisis imminent", group = "Politics" },
	{ id = "Direct:RoverDestroyed", translation_id = 935434970603, voiced_text = "Rover destroyed", group = "Building" },
	{ id = "Direct:VoteFailed", translation_id = 167929830600, voiced_text = "Vote failed", group = "Politics" },
	{ id = "Direct:VotePassed", translation_id = 947390378217, voiced_text = "Vote passed", group = "Politics" },
	{ id = "Direct:DomeFracture", translation_id = 917824125764, voiced_text = "Warning! Dome fracture", group = "Building" },
	{ id = "Direct:FoodShortage", translation_id = 7070, voiced_text = "Warning! Food shortage", group = "Colonist" },
}

-- Translation ids from Data/Scenario whose matching <id>.opus was verified in
-- Local/Voices/English.fpk. Runtime discovery admits only this set, excluding
-- silent voiced_text declarations and keeping the panel free of dead Play rows.
MN_RecordedScenarioVoiceIds = {
	[7156] = true, [7157] = true, [7158] = true, [7159] = true, [7160] = true, [7161] = true,
	[7162] = true, [7163] = true, [7164] = true, [7165] = true, [7166] = true, [7167] = true,
	[7168] = true, [7169] = true, [7170] = true, [7171] = true, [7172] = true, [7173] = true,
	[7174] = true, [7175] = true, [7176] = true, [7177] = true, [7178] = true, [7179] = true,
	[7180] = true, [7181] = true, [7182] = true, [7183] = true, [7184] = true, [7186] = true,
	[7187] = true, [7188] = true, [7189] = true, [7190] = true, [7192] = true, [7193] = true,
	[7194] = true, [7195] = true, [7196] = true, [7198] = true, [7201] = true, [7202] = true,
	[7203] = true, [7204] = true, [7205] = true, [7206] = true, [7207] = true, [7208] = true,
	[7209] = true, [7210] = true, [7211] = true, [7212] = true, [7213] = true, [7214] = true,
	[7215] = true, [7216] = true, [7217] = true, [7218] = true, [7219] = true, [7220] = true,
	[7221] = true, [7222] = true, [7223] = true, [7224] = true, [7225] = true, [7226] = true,
	[7227] = true, [7228] = true, [7229] = true, [7230] = true, [7231] = true, [7232] = true,
	[7233] = true, [7234] = true, [7235] = true, [7236] = true, [7237] = true, [7238] = true,
	[7239] = true, [7240] = true, [7241] = true, [7242] = true, [7243] = true, [7244] = true,
	[7245] = true, [7246] = true, [7247] = true, [7248] = true, [7249] = true, [7250] = true,
	[7251] = true, [7252] = true, [7253] = true, [7254] = true, [7255] = true, [7256] = true,
	[7257] = true, [7258] = true, [7259] = true, [7260] = true, [7261] = true, [7264] = true,
	[7265] = true, [7266] = true, [7269] = true, [7270] = true, [7272] = true, [7273] = true,
	[7274] = true, [7275] = true, [7276] = true, [7278] = true, [7282] = true, [7284] = true,
	[7286] = true, [7288] = true, [7290] = true, [7291] = true, [7448] = true, [7449] = true,
	[7450] = true, [7451] = true, [7452] = true, [7453] = true, [7454] = true, [7455] = true,
	[7456] = true, [7457] = true, [7458] = true, [7459] = true, [7460] = true, [7461] = true,
	[7462] = true, [7463] = true, [7464] = true, [7465] = true, [7466] = true, [7467] = true,
	[7468] = true, [7469] = true, [7470] = true, [7471] = true, [7472] = true, [7473] = true,
	[7474] = true, [7475] = true, [7476] = true, [7477] = true, [7478] = true, [7479] = true,
	[7480] = true, [7481] = true, [7482] = true, [7483] = true, [7484] = true, [7988] = true,
	[7989] = true, [7990] = true, [7991] = true, [7992] = true, [7993] = true, [7994] = true,
	[7995] = true, [7996] = true, [7997] = true, [7998] = true, [8159] = true, [8164] = true,
	[8169] = true, [8173] = true, [8178] = true, [8184] = true, [8189] = true, [8193] = true,
	[8198] = true, [8202] = true, [8207] = true, [8212] = true, [8216] = true, [8221] = true,
	[8225] = true, [8229] = true, [8233] = true, [8237] = true, [8243] = true, [8248] = true,
	[8256] = true, [8264] = true, [8277] = true, [8281] = true, [8285] = true, [8290] = true,
	[8294] = true, [8297] = true, [8301] = true, [8305] = true, [8309] = true, [8312] = true,
	[8320] = true, [8324] = true, [8328] = true, [8332] = true, [8336] = true, [8340] = true,
	[8345] = true, [8352] = true, [8360] = true, [8365] = true, [8370] = true, [8379] = true,
	[8388] = true, [8397] = true, [8402] = true, [8407] = true, [8412] = true, [8417] = true,
	[8426] = true, [8430] = true, [8434] = true, [8443] = true, [9439] = true, [9444] = true,
	[9449] = true, [9454] = true, [9458] = true, [9463] = true, [9467] = true, [9472] = true,
	[9477] = true, [9481] = true, [9487] = true, [9492] = true, [9497] = true, [9503] = true,
	[9507] = true, [9512] = true, [9517] = true, [9522] = true, [9527] = true, [9532] = true,
	[9537] = true, [9542] = true, [9546] = true, [9552] = true, [9557] = true, [9561] = true,
	[9566] = true, [9570] = true, [9575] = true, [9580] = true, [9585] = true, [9590] = true,
	[9593] = true, [9598] = true,
}

MN_CustomNames = {
	["Breakthrough discovered"] = "Breakthrough Discovered",
	["We gather here today to bid a final farewell to one of our finest."] = "A Eulogy for an Everyday Hero",
	["Full of hope and determination, the first Founders have set foot on the Red Planet."] = "A New Beginning",
	["Living in cramped quarters, tinkering with intricate machinery day-in, day-out. There's plenty of opportunities for slip-ups."] = "Call It What You Will",
	["It takes more than bravery to be a pioneer of the Martian frontier. Or at least it should."] = "Courage Has Layers",
	["The Colonists are on the brink of dehydration! We need to figure out something quick before they die."] = "Dehydration!",
	["Today was a tough one. We lost one of our Founders."] = "Do Not Go Gentle Into That Good Night",
	["The day claimed our last living Founder, spelling the end of an era for us all."] = "End of an Age",
	["Mars has ways of crushing the hope out of our very best."] = "End of an Age",
	["The first Colonists are all gamblers coming to Mars. It's the ultimate roll of the dice."] = "Gambling Amid The Stars",
	["Our Colonists are suffering from hypothermia!"] = "Hypothermia!",
	["The Founders are supposed to be the pillars of the future Colony - destined to be remembered for generations."] = "In Space, No One Can Hear you Whine",
	["A Colonist just snapped!"] = "Mental Breakdown",
	["It's a rough life here on Mars. You can't prepare for addiction."] = "Nobody Knows The Trouble I've Seen...",
	["Our Colonists are starving!"] = "Starvation!",
	["Our Colonists are suffocating! We only have a few hours to get them more Oxygen before they run out!"] = "Suffocation!",
	["Building a new home on an alien world? That takes guts, to say the least."] = "When Life Gives You Lemons...",
	["New Colonists have arrived"] = "Colonists Arriving",
	["A Colonist has died"] = "Deaths in the Colony",
	["Departing colonists"] = "Departing Colonists",
	["Tourists are departing"] = "Departing Tourists",
	["Colonists deported"] = "Deported Colonists",
	["Overstaying Tourists"] = "Overstaying Tourists",
	["A rocket has arrived"] = "Rocket Arrival",
	["A rocket is departing"] = "Rocket Lift Off",
	["New Tourists have arrived"] = "Tourists Arriving",
	["Deposit running low"] = "Almost Depleted",
	["Warning! Missile incoming"] = "Bombard Impact",
	["Broken train tracks"] = "Broken train tracks",
	["A building has stopped working"] = "Building Not Working",
	["Well done! Now observe how the Drones will carry all the resources to the site and then construct the Concrete Extractor."] = "Construction Sites",
	["Warning! Crop failure"] = "Crop Failure",
	["You can also queue sectors for scanning."] = "Exploration - Scanning Queue",
	["Construct two Hydroponic Farms in the new Dome. They will be used as workplaces for the Colonists in the old Dome once the Domes are connected."] = "Farms",
	["It's been a stellar day. Not just for the mission, but for humanity itself."] = "First Dome Constructed!",
	["Warning! Fuel destroyed"] = "Fuel Explosion",
	["Funding received"] = "Funding Received",
	["Humanity had such high hopes and we failed them. We failed the Founders. But is this really the end?"] = "Game Over",
	["The Colony has failed. The lives and the dreams of our Colonists are lost, washed away by despair and grief."] = "Game Over",
	["Heavy Drone workload"] = "Heavy Drone workload",
	["Heavy Shuttle workload"] = "Heavy Shuttle workload",
	["Hints such as this one will appear throughout the training process, giving useful information on how to advance in your current tasks."] = "Hints",
	["With the Rocket selected, designate a landing site on the indicated location."] = "Land the Rocket",
	["Warning! Insufficient resources"] = "Low Storage",
	["Anomaly found"] = "New Anomalies",
	["There's more to the barren environs of the Red Planet than meets the eye - a veritable treasure trove of undiscovered knowledge and wonder... So long as you know where to look."] = "New Techs Available for Research",
	["Not enough Fuel for Shuttles"] = "Not enough Fuel for Shuttles",
	["Orphaned drones"] = "Orphaned drones",
	["Connect the Stirling Generator and the Concrete Extractor using a <em>Power Cable</em> from the Build Menu to power up the Extractor."] = "Power Cables",
	["Nice work!"] = "RC Transport - Transport Routes",
	["Now order the RC Transport to unload the Fuel next to the Rocket."] = "RC Transport - Unloading Resources",
	["Research complete"] = "Research Complete",
	["Now let's try moving around."] = "Rover Basics",
	["Don't forget to provide basic services for the citizens of your new Dome."] = "Services",
	["Space Elevator delivery"] = "Space Elevator Delivery",
	["Warning! Cable Fault"] = "Warning! Cable Fault",
	["Warning! Pipe leak"] = "Warning! Pipe leak",
	["Warning! Split life-support grid"] = "Warning! Split life-support grid",
	["Warning! Split power grid"] = "Warning! Split power grid",
	["Use the Build Menu to construct a Water Extractor near the Water deposit, then power it up."] = "Water Extractor",
	["Cold Wave approaching"] = "Cold Wave",
	["Dust Storm approaching"] = "Dust Storm",
	["Electrostatic Dust Storm approaching"] = "Electrostatic Dust Storm",
	["Great Dust Storm approaching"] = "Great Dust Storm",
	["Warning! Meteor incoming"] = "Incoming Meteor",
	["Warning! Marsquake"] = "Marsquake",
	["Meteor Shower approaching"] = "Meteor Storm",
	["Toxic Rain approaching"] = "Toxic Rain",
	["The recent Colonist deaths are a worrisome trend which cannot be ignored!"] = "A Mission In Jeopardy",
	["Our civilization, in all its glory, still bears the mark of obsolete cultural and ideological beliefs, from times when people didn't know any better. If we remain ignorant of our own flaws we risk destroying the future for our children."] = "Mission Evaluation: A Fresh Start",
	["The Mission Evaluation period is over and the progress we've made was marked as... sub-optimal, to say the least."] = "Mission Evaluation: A Fresh Start",
	["The Mission Evaluation period is over and the results we have achieved are quite satisfactory."] = "Mission Evaluation: A Fresh Start",
	["The Mission Evaluation period is over and it's not wrong to say that we managed to outdo ourselves."] = "Mission Evaluation: A Fresh Start",
	["At the end of the Mission Evaluation period we have to admit that the pursuit of technological progress on a hostile alien world is an unaccessible luxury, when we're preoccupied with short-term survival."] = "Mission Evaluation: New Dawn",
	["Humankind might be on the verge of a new Golden Age! And we have to be the ones who ride the crest of that wave!"] = "Mission Evaluation: New Dawn",
	["The Mission Evaluation period is over and the results of our efforts are visible - a steady track of technological milestones can be traced back to the moment the very first rocket landed on the Red Planet."] = "Mission Evaluation: New Dawn",
	["Our contribution towards the scientific advancement of humankind will be forever remembered. The Evaluation Day report shows accomplishments beyond even our wildest expectations."] = "Mission Evaluation: New Dawn",
	["We have to admit that we failed to accomplish one of the main goals set before our mission. Sadly, we underestimated the difficulties of sustaining a large population on the Red Planet."] = "Mission Evaluation: The Exodus",
	["As the Evaluation Day dawns upon us we can clearly say that the mission to Mars was a success."] = "Mission Evaluation: The Exodus",
	["Congratulations! Everyone at Mission Control rejoices as the Colony has been marked as \"extremely successful\" in the Evaluation Report."] = "Mission Evaluation: The Exodus",
	['Scientists and visionaries have promoted the idea of "Humanity as a multi-planetary species" as the only way to prevent a possible mass extinction.'] = "Mission Evaluation: The Exodus",
	["The Mission Evaluation report confirms what we knew - the target goals were far off from the very beginning."] = "Mission Evaluation: The Final Frontier",
	["We are all descendants of those who dared to look beyond the nice, cozy valley they inhabited and enter a world full of mystery and wonder. "] = "Mission Evaluation: The Final Frontier",
	["The final Mission Evaluation report concludes that the Colony has scored a significant progress in the exploration of the Red Planet."] = "Mission Evaluation: The Final Frontier",
	["Dredgers detected"] = "Dredger Detected",
	["Dredgers landed"] = "Dredger Landed",
	["Warning! Drone attack"] = "Hostile Attack",
	["Ion storm approaching"] = "Ion Storm Detected",
	["Warning! Sinkhole detected"] = "Sinkhole Detected",
	["The Spheres just keep dividing. This level of technology... We can't even begin to comprehend it."] = "Spheres: 3 Up, More to Come",
	["A short dig following an off-the-charts reading revealed a metallic spheroid buried just beneath the surface."] = "Spheres: A Buried Secret",
	["The humming's less than subtle now, with the added bonus that it's clearly harming any Colonists that come too close."] = "Spheres: Bad Vibrations",
	["Humanity applied its knowledge of an alien technology for the first time ever. And it was a complete success."] = "Spheres: Choose Your Poison",
	["The Colony is expecting some sort of artificial cold wave. How's that even possible?"] = "Spheres: Climate Change",
	["Definitive contact with an extraterrestrial being, for the first time in the history of mankind."] = "Spheres: Hello, Goodbye",
	["Our running hypothesis seems to be correct. It's releasing energy to charge faster. Maybe it's alive?"] = "Spheres: Is it Alive?",
	["Those decoy buildings worked just like we planned, much to the dismay of our hardworking engineers. We've captured our first Sphere!"] = "Spheres: It Works!",
	["Our test results tell us the Sphere accumulates energy by absorbing radio waves,"] = "Spheres: Metallic Silence",
	["The Mirror Sphere has Mission Control in total chaos. Though that's expected given what we saw."] = "Spheres: More to Come",
	["We tried interacting with it, which triggered some sort of response. The Sphere isn't dormant anymore."] = "Spheres: System Shock",
	["It seems to be absorbing any sort of electrical current in close proximity. In other words, it's feeding on our batteries."] = "Spheres: The Sphere is a Sucker!",
	["Our attempts to penetrate the outer layer of the Sphere were unsuccessful, though they did yield some interesting results."] = "Spheres: The Trusty Screwdriver",
	["We've dismantled the last Sphere, yet our unease with the alien technology still lingers."] = "Spheres: To Future Generations",
	["Bad news, Commander!"] = "Bad news, Commander!",
	["Commander, good news!"] = "Commander, good news!",
	["On another note, Commander..."] = "On another note, Commander...",
	["Our Explorer just stumbled upon something fascinating."] = "Our Explorer just stumbled upon something fascinating.",
	["Things just took a turn for the weird."] = "Things just took a turn for the weird.",
	["What just transpired has left us speechless."] = "What just transpired has left us speechless.",
	-- These three POI declarations have no corresponding English voice recording.
	-- ["In a display reminiscent to formation flying shows back on Earth, special shuttles flew wave after wave in and out of the water vapor clouds above our colony.\n\n"] = "Cloud Seeding",
	-- ["The beauty of a space mirror can give pause to even the most seasoned astro-engineer. \n\n"] = "Launch Space Mirror",
	-- ["The warheads detonated in a magnificent display of light, brighter than a thousand suns.  We watched in awe from the safety of our labs.\n\n"] = "Melt the Polar Caps",
	["Good job! However we need more than just Metals. Fortunately we can call a resupply Rocket from Earth."] = "Advanced Resources and Resupply",
	["Well done! Now it's time to use our fully operational RC Explorer to analyze the Anomaly."] = "Anomalies",
	["From this screen you can inspect all available applicants and determine which ones will travel to the Colony."] = "Applicants Filter",
	["We have some Power but it's not enough. We should prioritize the Drone Hub."] = "Building Priority",
	["Buildings with higher priority will be allocated workers, Power and Maintenance before others.  "] = "Building Priority",
	["You need to master the camera controls and familiarize yourself with the terrain around the prospective colony site."] = "Camera Controls",
	["Let's do some cleaning up around the base while we wait for the Rocket to arrive."] = "Clearing Buildings",
	["Healthy colonists at working age are able to fill any position but how well they perform at a certain position varies between colonists.  "] = "Colonist Specializations",
	["The Command Center is a treasure trove of information about the colony."] = "Command Center",
	["Along with Metals, Concrete is the other vital basic construction resource."] = "Concrete Extractor",
	["Now let's remove some of the unnecessary Cables."] = "Deleting Cables & Pipes",
	["The time has finally come to build the first Dome that will house our Colonists."] = "Domes",
	["The Dome is complete but we have to supply it with Water, Power and Oxygen before we can use it."] = "Domes - Water, Power and Oxygen",
	["Drones run on batteries that have to be recharged periodically."] = "Drone Batteries",
	["You are trying to place a construction outside of the work range of your Drones."] = "Drone Range",
	["Drones will pick pending tasks on their own within the range of the drone controllers they are assigned to."] = "Drones and Drone Hubs",
	["...and we have touchdown! The Rocket has landed on Mars."] = "Drones and Resources",
	["It is time to learn about scanning sectors and exploration."] = "Exploration",
	["You can scan sectors of the map to discover new resources and Anomalies."] = "Exploration",
	["Water is essential for a sustainable Martian colony. Fortunately there is a Water deposit nearby."] = "Extracting Water",
	["You can setup filters for every Dome to attract colonists with desired traits and block or push out colonists with undesired ones."] = "Filter Colonists",
	["Colonists will arrive on Mars with a small amount of Food, but it will not last long. We need to make sure that they will be able to produce their own Food on the red planet. The Hydroponic Farm can produce Food. Although the Colonists can take Food directly from a Food Depot, they will be happier if they can pick it up from a Grocer."] = "Food",
	["Fuel production is now underway and the Drones will begin to deliver the Fuel to the Rocket."] = "Fuel",
	["The foundations for bringing your first Colonists have already been laid down. One of the final things left to do is to provide the Founders with living space."] = "Housing",
	["There are no Colonists in the mining Dome. We must provide living space for the Colonists so they can move there."] = "Housing",
	["We don't have sufficient Power for all the buildings in the colony."] = "Insufficient Power",
	["Now it's time to land your first Rocket."] = "Landing the Rocket",
	["You managed to get things operational, but this won't last as buildings require maintenance and we are out of Resources."] = "Maintenance",
	["Great! Now that you have a Spacebar you can customize its work settings."] = "Managing Jobs",
	["Being near a Rare Metals Deposit, this Dome is best suited as a mining hub so it's best to encourage Geologists to migrate here."] = "Mining Dome",
	["Congratulations, Commander! You have graduated from the International Mars Mission training simulation! "] = "Mission Complete",
	["Congratulations, you have finished the first tutorial!"] = "Mission Complete!",
	["Nice work! Now you know how to handle Rovers."] = "Mission Complete!",
	["Well done! You have completed the simulation successfully."] = "Mission Complete!",
	["You have completed the tutorial for the Founder Stage."] = "Mission Complete!",
	["Welcome back, Commander! In this tutorial you will manage a larger colony that consists of multiple Domes."] = "Multiple Domes Tutorial",
	["We need to construct a new Sensor Tower to scan the nearby environment."] = "New Expand",
	["Some Drones are left without a controller after the Rocket launch."] = "Orphaned Drones",
	["Domes positioned closely to each other may be connected with Passages."] = "Passages",
	["With all preparations complete, the Colony is ready for the arrival of the Founders."] = "Passenger Rocket",
	["A system of Pipes is used to deliver resources such as Water and Air where they are needed."] = "Pipes",
	["Like most buildings, the Concrete Extractor needs  power in order to operate. Having a reliable electrical grid and supply is essential for the success of the colony."] = "Power",
	["The supplies from Earth have arrived and we can use them to expand the base."] = "Power Accumulators",
	["Now let's get that Drone Hub operational."] = "Powering The Drone Hub",
	["The RC Transport can load and carry resources around the map. Let's use it to refuel the nearby Rocket."] = "RC Transport",
	["The RC Transport is able to gather resources directly from surface deposits without the help of Drones."] = "RC Transport - Gathering Metals",
	["We need more Metals to secure this base. Use the RC Transport to collect some Metals and transport them back."] = "RC Transport - Gathering Metals",
	["Maintaining a steady supply chain between Earth and Mars is essential, especially during the early colonization stages. "] = "Refueling the Rocket",
	["The Anomaly has yielded interesting insights into new technologies."] = "Research",
	["This is the Research screen. From here you can choose and queue techs for Research."] = "Research",
	["With the Research Lab up and running let's begin researching some technologies."] = "Research",
	["This Dome has been designated for research purposes so it's best to attract more colonists with the Scientist specialization."] = "Research Dome",
	["You may want to review and hand pick individual candidates for the Founders."] = "Review Applicants",
	["Welcome, Commander! In this training exercise you will get acquainted with one of your most valuable tools - Rovers."] = "Rovers",
	["First things first! Let's remove some unnecessary structures."] = "Salvaging Buildings",
	["Good Job!"] = "Sensor Tower",
	["Colonists need service buildings to keep them comfortable on Mars. The Grocer that you already constructed is one such service building."] = "Service Buildings",
	["Even with the Wind Turbine there won't be enough electricity to power the base, especially during the night."] = "Shifts & Power Management",
	["Shuttles can transport resources and colonists across great distances. "] = "Shuttles",
	["Welcome Commander! It looks like this forward base has gone through a major dust storm. "] = "The Aftermath",
	["Congratulations! A baby has been born on Mars and the Founder stage is completed!"] = "The First Baby",
	["Congratulations! You have provided everything needed for a successful Founder Stage."] = "The Founder Stage",
	["Welcome back, Commander! In this tutorial you will finally familiarize yourself with the challenges of sustaining a society on Mars."] = "The Founders",
	["Colonists can migrate between Domes using shuttles or walking when they are positioned close to one another. However, they cannot usually visit buildings in nearby Domes on a daily basis, unless they are connected to their own Dome."] = "Third Dome",
	["Our Rocket carries valuable resources that will be essential for the construction and maintenance of the Colony. Initially it's best to designate a Universal Depot, so the Drones have a place to store them."] = "Unloading the Payload",
	["The Upgrade has been constructed."] = "Upgrade Complete",
	["Some buildings can have upgrades that can improve them in various ways."] = "Upgrades",
	["Congratulations - with the research complete, a new upgrade for your Extractors is now available. It is not automatically activated in your buildings, you must construct it first."] = "Upgrades",
	["Waste Rock is a byproduct of all extractors and is best stored at designated locations. This way you can ensure that it will not be in the way of future construction."] = "Waste Rock and the Concrete Depot",
	["The Water Extractor is ready but we don't have a storage for the Water it will extract."] = "Water Storage",
	["We can use the Machine Parts left from the Concrete Extractor to build a Wind Turbine."] = "Wind Turbines",
	["Work Shifts, among other things, are a way to manage your work force. The more shifts a building has open the more colonists it will attract to work there.  "] = "Work Shifts",
	["Now that we have operational Shuttles it's time to establish a mining Dome."] = "Workplaces Outside the Domes",
	["Welcome to Mars!"] = "Welcome to Mars, Commander!",
	["This will go down in history."] = "The Door Towards the Stars",
	-- Inactive/commented entries; not shown in the panel while commented out.
	["There are Earthsick Colonists"] = "Earthsick Colonists",
	-- ["Congratulations! You have successfully completed all the goals your sponsor had set for you to accomplish on Mars. "] = "Mission Evaluation",
	-- ["Dear shareholders, dear board directors! Let's applaud the Commander, whose name has become a guarantee for reliability, ambition and prosperity! A person who made our shared goals of profit and growth a paramount!"] = "Mission Evaluation",
	-- ["Commander, your name will top the lists of humanity's heroes for ages - probably forever. We salute you!"] = "Mission Evaluation",
	-- ["You, Commander, remained true to our original aspiration and succeeded in securing a decisive victory for the entire humankind, with China as its vanguard. We congratulate you!"] = "Mission Evaluation",
	-- ["Commander, the collective effort of the united European nations has culminated with your extraordinary success! Congratulations!"] = "Mission Evaluation",
	-- ["Congratulations, Commander! Our people look upon you as a herald of new age of prosperity, marked by the colonization of the Red Planet!"] = "Mission Evaluation",
	-- ["Japanese innovation has proven paramount to humanity's desire to live amidst the stars. You have made your people proud, Commander."] = "Mission Evaluation",
	-- ["Congratulations Commander, you have successfully fulfilled all tasks set before you by Congress and the entire mission is deemed an absolute success!"] = "Mission Evaluation",
	-- ["Humanity has reached far, surviving the dark ages of ignorance through the guidance of the prophets of enlightenment. You, Commander, are truly one of those individuals, touched by the divine spark, whose example shines like a torch for all of us."] = "Mission Evaluation",
	-- ["Thank you for completing your mission goals, Commander. Once again your submission documentation is up to par and we enjoyed reading through it. The team at Paradox Interactive HQ is grateful for your patience and determination."] = "Mission Evaluation",
	-- ["Commander! You achieved all mission goals, regardless of the adversities you faced on Mars! A true pioneer - well done!"] = "Mission Evaluation",
	-- ["Congratulations Commander! You have achieved that which the cynics said cannot be done by a non-governmental entity - and yet here we are."] = "Mission Evaluation",
	["Commander, one other thing."] = "Research Points",
	-- ["The capturing of Ice Asteroids has been successfully completed!"] = "Capture Ice Asteroids",
	-- ["We have succeeded in capturing and diverting meteors towards our general vicinity in a gambit to bring precious resources and even scientific insight withing our reach."] = "Capture Meteors",
	-- ["The remote scientific outpost is set and has started transmitting intriguing data from the Red Planet."] = "Contract Exploration Access",
	-- ["Our high-speed Comm Satellite is now online."] = "High-speed Comm Satellite",
	-- ["Just a few of the falling rocks, delivered by autonomous crafts from Earth, were visible to the naked eye."] = "Import Greenhouse Gasses",
	-- ["The Magnetic Shield settled in its orbit and slowly began expanding its sun-blocking appendages."] = "Launch Magnetic Shield",
	-- ["Three, two, one... a collective gasp and then cheers. The Project was successful."] = "Seed Vegetation",
	-- ["Our very own SETI Satellite has been delivered and launched into Martian orbit."] = "SETI Satellite",
	-- ["Surviving Mars has been recently updated. You can check the full patch notes online, but here are a few highlights:"] = "New Update",
	["For the first time, a human has been born on Mars. It's truly a unique miracle."] = "The Door Towards the Stars",
	["Let's set up a small expand some distance away from the main base."] = "RC Transport - Transport Routes",
	-- ["Good job!"] = "Passages", -- duplicate; the "Good Job!" Sensor Tower copy is the working version.
	-- ["Nice Work!"] = "Upgrade Extractor", -- duplicate; the "Nice work!" RC Transport copy is the working version.
	-- ["In the beginning, it was just a dream - setting foot on another planet, surviving it, building a new future for humanity."] = "A dream fulfilled", -- Play preview is silent.
	-- ["A new situation has arisen."] = "A new situation has arisen.",
	-- ["Commander, some interesting readings are just in."] = "Commander, some interesting readings are just in.",
	-- List notes:
	--   * Edit the RIGHT-hand value to rename how a line appears in the panel.
	--   * COMMENT OUT (or delete) a line to REMOVE that item from the panel.
	--   * An empty value ("") keeps the item but uses the game's own title.
	-- Keys are the spoken (English) line and must not be changed; they are how each
	-- original preset entry is matched. HUD, direct, and verified scenario sources
	-- are always shown. Regenerate the full current list with
	-- MN_ExportCustomNames() in the in-game Lua console.
}
