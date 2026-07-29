-- mn_config.lua
-- Central configuration, feature flags, default-spam rules and protected groups.
-- This is the canonical configuration source for the mod. Do not duplicate these
-- values elsewhere.

MN_Config = {
	MOD_ID = "MuteNotifications",
	MOD_DISPLAY_NAME = "Mute Notifications",

	-- Canonical behaviour version (separate from metadata.lua mod 'version').
	VERSION = "0.6.34",

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
	Placeholder_1 = true, -- duplicate "Commander, one other thing."; keep Tutorial2_Popup13_1_Research2
	Placeholder_2 = true, -- T(9430): no English voice sample in English.fpk
	Placeholder_3 = true, -- T(9431): no English voice sample in English.fpk
	Tutorial1_Popup1_Intro = true, -- duplicate "Welcome to Mars!"; keep WelcomeGameInfo
	Tutorial2_Popup6_RCRover = true, -- duplicate "Commander, one other thing."; keep Tutorial2_Popup13_1_Research2
	AllMilestonesCompleted = true, -- Play preview is silent; keep commented in MN_CustomNames for reference
	ColonyViabilityExit_Delay_LastArk = true, -- duplicate "This will go down in history."; keep ColonyViabilityExit_Delay
	ToxicRains = true,    -- duplicate Toxic Rain alert; keep DisasterToxicRains
	ToxicRains2 = true,   -- duplicate Toxic Rain alert; keep DisasterToxicRains
}
MN_ExcludedVoiceGroups = {
	Challenge = true,   -- challenge popups have voiced_text but no recorded voice audio
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
	["extremely successful"] = "Mission Evaluation: The Exodus",
	["Humanity as a multi-planetary species"] = "Mission Evaluation: The Exodus",
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
	["In a display reminiscent to formation flying shows back on Earth, special shuttles flew wave after wave in and out of the water vapor clouds above our colony.\\n\\n"] = "Cloud Seeding",
	["The beauty of a space mirror can give pause to even the most seasoned astro-engineer. \\n\\n"] = "Launch Space Mirror",
	["The warheads detonated in a magnificent display of light, brighter than a thousand suns.  We watched in awe from the safety of our labs.\\n\\n"] = "Melt the Polar Caps",
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
	--["There are Earthsick Colonists"] = "Earthsick Colonists",
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
	-- ["Commander, one other thing."] = "Commander, one other thing.",
	-- ["The capturing of Ice Asteroids has been successfully completed!"] = "Capture Ice Asteroids",
	-- ["We have succeeded in capturing and diverting meteors towards our general vicinity in a gambit to bring precious resources and even scientific insight withing our reach."] = "Capture Meteors",
	-- ["The remote scientific outpost is set and has started transmitting intriguing data from the Red Planet."] = "Contract Exploration Access",
	-- ["Our high-speed Comm Satellite is now online."] = "High-speed Comm Satellite",
	-- ["Just a few of the falling rocks, delivered by autonomous crafts from Earth, were visible to the naked eye."] = "Import Greenhouse Gasses",
	-- ["The Magnetic Shield settled in its orbit and slowly began expanding its sun-blocking appendages."] = "Launch Magnetic Shield",
	-- ["Three, two, one... a collective gasp and then cheers. The Project was successful."] = "Seed Vegetation",
	-- ["Our very own SETI Satellite has been delivered and launched into Martian orbit."] = "SETI Satellite",
	-- ["Surviving Mars has been recently updated. You can check the full patch notes online, but here are a few highlights:"] = "New Update",
	-- ["For the first time, a human has been born on Mars. It's truly a unique miracle."] = "The Door Towards the Stars", -- duplicate; the "This will go down in history." copy is the working version.
	-- ["Let's set up a small expand some distance away from the main base."] = "RC Transport - Transport Routes", -- duplicate; the "Nice work!" OnScreenHint copy is the working version.
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
	-- entry is matched. When this table is non-empty it acts as a whitelist: only the
	-- listed (uncommented) lines are shown. Regenerate the full current list with
	-- MN_ExportCustomNames() in the in-game Lua console.
}
