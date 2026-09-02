-- gamedata.lua - What the game itself says, rather than what a part looks like.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)
local Workspace = S.Workspace

-- =========================================================================
-- GAME KNOWLEDGE (3.0.0)
--
-- Read straight out of the place file (see game/GAME_NOTES.md). The game keeps
-- its own attack visuals in ReplicatedStorage.enemyProjectiles and the
-- player's in ReplicatedStorage.projectiles / .abilities, which is exactly the
-- "is this mine or theirs" question the appearance scorer used to guess at.
--
-- Names are matched on the part AND its ancestor models, because most of these
-- are Models whose individual parts carry their own names.
--
-- Gear and mob templates are deliberately absent: an Accessory named bossRifle
-- is a weapon an enemy is holding, not an attack, and fleeing from it would
-- mean fleeing from every enemy in the room.
-- =========================================================================

-- 238 enemy attack visuals. A name here IS an attack; no scoring needed.
local ENEMY_ATTACKS = {
    ["azrallik's heart"]=true,["energy source"]=true,["flame cyclone"]=true,
    ["kraken tentacle"]=true,["aggressivefreezepart"]=true,["aggressivelavawalkerhit"]=true,
    ["aoeswipe"]=true,["artillerymobshot"]=true,["artilleryrock"]=true,["azrallikpunch"]=true,
    ["azrallikpunchspread"]=true,["battlemageorb"]=true,["bellyflophit"]=true,
    ["biggolemrock"]=true,["bigmagebeam"]=true,["bigrock"]=true,["bonusbossbouncingorb"]=true,
    ["bonusbossbouncingorbbad"]=true,["bonusbossbouncingorbgood"]=true,
    ["bonusbossflameprecast"]=true,["bonusbossfreezingorbbeam"]=true,
    ["bonusbossgroundflame"]=true,["bonusbosslongline"]=true,["bonusbossmemorymodel"]=true,
    ["bonusbosssmallspiralflame"]=true,["bonusbosssweepingflames"]=true,
    ["bonusbosstallswirly"]=true,["bosshunterinnerflameshot"]=true,
    ["bosshuntermiddlefire"]=true,["bosshuntersidefire1"]=true,["bosshuntersidefire2"]=true,
    ["bossmagebigsideshot"]=true,["bossmagemainlaser"]=true,["bossmagesideshot"]=true,
    ["bossmelee"]=true,["bossrifleprecast"]=true,["bossrifleshot"]=true,["bossshot"]=true,
    ["canalsnpcmageshot"]=true,["cannonbarragecannonhit"]=true,["cannonbarragehit"]=true,
    ["cannoncrabshot"]=true,["chickenmage"]=true,["chickenmelee"]=true,["circlehit"]=true,
    ["cool placeholething?"]=true,["corruptlinefire"]=true,["corruptmolotov"]=true,
    ["crossshot"]=true,["crossshuriken"]=true,["doubleflamebeam"]=true,["droneshot"]=true,
    ["eastersecondbossrandomline"]=true,["electrictowerhit"]=true,["eliteswordsmanspin"]=true,
    ["enchantedfirstbossfolloworb"]=true,["explosivebomb"]=true,["explosivemobshot1"]=true,
    ["explosivemobshot2"]=true,["explosivemobshot3"]=true,["finalbossarrowshothitbox"]=true,
    ["finalbossexplosion"]=true,["finalbosslineblast"]=true,["finalbossorbshot"]=true,
    ["finalbossrotatingcircle"]=true,["fingerblasthit"]=true,["firstbossbeampart"]=true,
    ["firstbossbeamshot"]=true,["firstbossbeamtrackerline"]=true,["firstbossbigspike"]=true,
    ["firstbossblindingblastbeam"]=true,["firstbossbombexplosion"]=true,
    ["firstbosscrisscross"]=true,["firstbosscrystal"]=true,["firstbosscrystaldrop"]=true,
    ["firstbossflameshot"]=true,["firstbossfolloworb"]=true,["firstbossgatlinggunshot"]=true,
    ["firstbossiceradius"]=true,["firstbossjumpslam"]=true,["firstbosslaserprecast"]=true,
    ["firstbosslefthandshot"]=true,["firstbosslongline"]=true,["firstbossminionexplosion"]=true,
    ["firstbossmoveorb"]=true,["firstbossmovingorb"]=true,["firstbossorbprecastline"]=true,
    ["firstbosspassivecriclehitbox"]=true,["firstbossplayeronfire"]=true,
    ["firstbossrighthandshot"]=true,["firstbossrocket"]=true,["firstbossrockethitbox"]=true,
    ["firstbossseekingspikes"]=true,["firstbosssiegeshot"]=true,["firstbossskyshot"]=true,
    ["firstbossspinningrock"]=true,["firstbosssupplyoverhead"]=true,
    ["firstbossturretmodel"]=true,["firstbossturretshot"]=true,["firstbossupshot"]=true,
    ["flamebeam"]=true,["flameeffect"]=true,["flamelashpart"]=true,["flamelashprecast"]=true,
    ["flameshurikenhit"]=true,["flamingshuriken"]=true,["freezeplayerpart"]=true,["gank"]=true,
    ["gasball"]=true,["genericneonball"]=true,["ghastlyriflemanshot"]=true,["golemrock"]=true,
    ["golemrockclap"]=true,["golemrocksmall"]=true,["golemrockthrow"]=true,
    ["golemrockthrowsmall"]=true,["hammerbothit"]=true,["hitindicatoriceaoe"]=true,
    ["hitmanstrike"]=true,["horizontalbeam"]=true,["iceaoe"]=true,["icebeam"]=true,
    ["icebeamindicator"]=true,["icebomb"]=true,["initialhunterbossentry"]=true,
    ["initialkingbossentry"]=true,["initialmagebossentry"]=true,["kinglandingarea"]=true,
    ["kolvumarspit"]=true,["krakenhitbox"]=true,["krakeninkhit"]=true,["largeicespikes"]=true,
    ["laserbeam"]=true,["magebossminionspawneffect"]=true,["magebossstrraightshot"]=true,
    ["magehorizontalbeam"]=true,["mageprojectileball"]=true,["mediumicespikes"]=true,
    ["minionexplosion"]=true,["minionexplosionhitbox"]=true,["minionindicator"]=true,
    ["northernaggressivefreezepart"]=true,["npcmageshot"]=true,["npcmagespikes"]=true,
    ["npcshurikenthrow"]=true,["overgrowthlonglinespikes"]=true,["overgrowthspikes"]=true,
    ["overheadcannon"]=true,["pinkfreezepart"]=true,["poisonbomb"]=true,["precast"]=true,
    ["redfreezepart"]=true,["riflemanshot"]=true,["rock"]=true,["rockexplosion"]=true,
    ["rockexplosionsmall"]=true,["rockshatter"]=true,["secondbossbigcircle"]=true,
    ["secondbossbigrockdebris"]=true,["secondbosscheckeredline"]=true,
    ["secondbosscirclehit"]=true,["secondbosscrescent"]=true,["secondbosscriclehitbox"]=true,
    ["secondbosscrossbeam"]=true,["secondbossfailedexplosion"]=true,["secondbossgeyser"]=true,
    ["secondbossgeysershot"]=true,["secondbossgreenorb"]=true,["secondbossgroundaura"]=true,
    ["secondbossgroundslamcircle"]=true,["secondbosshorizontalline"]=true,
    ["secondbosslines"]=true,["secondbosslonglinepassive"]=true,
    ["secondbosslonglingeringline"]=true,["secondbossmark"]=true,["secondbossmovingbeam"]=true,
    ["secondbossorb"]=true,["secondbossoverheadrock"]=true,["secondbosspassivecircle"]=true,
    ["secondbosspulsewave"]=true,["secondbossrandomline"]=true,["secondbossrandompulse"]=true,
    ["secondbossredorb"]=true,["secondbossrock"]=true,["secondbossrockfall"]=true,
    ["secondbossrockhit"]=true,["secondbossspinninglaser"]=true,["secondbossverticalline"]=true,
    ["secondbosswave"]=true,["secondbossyelloworb"]=true,["serpentfirehitbox"]=true,
    ["serpentplayershot"]=true,["serpentwaterhitbox"]=true,["sharkthrowclient"]=true,
    ["sharkthrowhitbox"]=true,["shootershot"]=true,["shurikenthrow"]=true,["silkblast"]=true,
    ["smallicespikes"]=true,["spearmanfreezepart"]=true,["spearmanstrike"]=true,
    ["spikeprecast"]=true,["spinbotspin"]=true,["spiritorb"]=true,["spiritstrike"]=true,
    ["steampunkrangemobshot"]=true,["thirdbossbeampart"]=true,["thirdbossbeamshot"]=true,
    ["thirdbossbouncingorb"]=true,["thirdbossbouncingorbbeam"]=true,["thirdbosscirclehit"]=true,
    ["thirdbosscirclehit2"]=true,["thirdbosscrescent"]=true,["thirdbosscursering"]=true,
    ["thirdbossdualswingline"]=true,["thirdbossexplosionshot"]=true,["thirdbossflamewall"]=true,
    ["thirdbossflamewallhitbox"]=true,["thirdbossfrozencircle"]=true,["thirdbosslavaline"]=true,
    ["thirdbosslifestealbeams"]=true,["thirdbosslifestealhitbox"]=true,
    ["thirdbosslineshot"]=true,["thirdbossmemorydamagezone"]=true,["thirdbossmissile"]=true,
    ["thirdbossmultirings"]=true,["thirdbossoneshotbeam"]=true,["thirdbossorbshot"]=true,
    ["thirdbossoverheadringmodel"]=true,["thirdbosspassiveorb"]=true,
    ["thirdbossrandomline"]=true,["thirdbosssshapecircle"]=true,["thirdbosssmite"]=true,
    ["thirdbossspiralorb"]=true,["thirdbossspiralshot"]=true,["thirdbossspreadline"]=true,
    ["volcanicfirstbossflameshot"]=true,["volcanicsecondbossrandomline"]=true,
}

-- 293 player abilities and their projectiles. A name here is OURS, never dodged.
local OWN_EFFECTS = {
    ["agony orbs"]=true,["agony orbs main orb"]=true,["agony orbs small"]=true,
    ["agony orbs star explosion"]=true,["amethyst beam beam"]=true,
    ["amethyst beam ground part"]=true,["amethyst beam ground particles"]=true,
    ["amethyst beam orb"]=true,["amethyst beams"]=true,["amethyst blast"]=true,
    ["aquatic smite"]=true,["aquatic smite cast"]=true,["aquatic smite hit"]=true,
    ["arcane barrage"]=true,["arcane barrage hitbox"]=true,["arcane barrage1"]=true,
    ["arcane barrage2"]=true,["arcane spray"]=true,["arrow barrage"]=true,["arrow rain"]=true,
    ["arrow rain arrow"]=true,["aura of life"]=true,["battle shout"]=true,["berserk"]=true,
    ["berserk sounds"]=true,["big phase ball"]=true,["blade barrage"]=true,
    ["blade barrage sword"]=true,["blade fall"]=true,["blade fall sword"]=true,
    ["blade revolver"]=true,["blade storm"]=true,["blade throw"]=true,["blue fireball"]=true,
    ["carrot barrage"]=true,["carrot barrage carrot"]=true,["chain heal"]=true,
    ["chain lightning"]=true,["chain phase shock"]=true,["chained energy blasts"]=true,
    ["chromatic rain"]=true,["chromatic rain beam"]=true,["chromatic rain ring"]=true,
    ["concussive blast"]=true,["crystaline cannon blast"]=true,
    ["crystaline cannon spiral"]=true,["crystalline cannon"]=true,["demonic curse"]=true,
    ["demonic curse particles"]=true,["demonic spikes"]=true,["demonic strike"]=true,
    ["earth clap"]=true,["earth kick"]=true,["earth spikes"]=true,["egg bomb"]=true,
    ["electric boom"]=true,["electric field"]=true,["electric grinder"]=true,
    ["electric slash"]=true,["electric slash effect"]=true,["electric slash explosion"]=true,
    ["enchanted shuriken"]=true,["enchanted spinning blades"]=true,["energy orb"]=true,
    ["enhanced aura ring"]=true,["enhanced inner focus"]=true,["enhanced inner rage"]=true,
    ["explosive mine"]=true,["explosive punch"]=true,["explosive punch cone"]=true,
    ["explosive punch ring"]=true,["fire bomb"]=true,["fireball"]=true,["flame cyclone"]=true,
    ["flame shuriken"]=true,["flame strike"]=true,["focus beam"]=true,["forgotten army"]=true,
    ["forgotten army soldier"]=true,["frost cone"]=true,["fungal poison"]=true,
    ["fungal poison particles"]=true,["gale barrage"]=true,["gale slice"]=true,
    ["gale slice hitbox"]=true,["gale slice1"]=true,["gale slice2"]=true,["geyser"]=true,
    ["ghostly cannon barrage"]=true,["ghostly cannonball"]=true,["ghostly rampage"]=true,
    ["glacial blows"]=true,["god spear"]=true,["god spear debris"]=true,
    ["god spear debris ring"]=true,["god spear explosion cylinder"]=true,
    ["god spear model"]=true,["ground slam"]=true,["ground stomp"]=true,["guardian call"]=true,
    ["guardian roar"]=true,["guardian's blessing"]=true,["hand cannon"]=true,
    ["holy barrier"]=true,["holy circle"]=true,["ice barrage"]=true,["ice barrage ball"]=true,
    ["ice crash"]=true,["ice needles"]=true,["ice nova"]=true,["ice spikes"]=true,
    ["ice totem"]=true,["icicle barrage"]=true,["icicle barrage icicle"]=true,
    ["illusion blast"]=true,["infernal blast"]=true,["infernal blast cylinder"]=true,
    ["infernal orbs"]=true,["infernal strike"]=true,["inner focus"]=true,
    ["inner focus particle holder"]=true,["inner rage"]=true,
    ["inner rage particle holder"]=true,["innervate"]=true,["jade rain"]=true,
    ["jade rain circle"]=true,["jade rain crystal"]=true,["jade roller"]=true,
    ["lava barrage"]=true,["lava barrage ball"]=true,["lava barrage ring"]=true,
    ["lava barrage slash"]=true,["lava beam"]=true,["lava beam explosion cylinder"]=true,
    ["lava beam orb"]=true,["lava cage"]=true,["lava lash"]=true,["life dash"]=true,
    ["life pulse"]=true,["life pulse ring"]=true,["lightning beam"]=true,
    ["lightning burst"]=true,["lightning burst part"]=true,["lightning strikes"]=true,
    ["mighty leap"]=true,["mighty leap slam circle"]=true,["molten ball"]=true,
    ["molten shard"]=true,["molten shards"]=true,["mystery matter"]=true,
    ["orb of destruction"]=true,["orb of destruction holder"]=true,["overcharge"]=true,
    ["overcharged effects"]=true,["phantom blades"]=true,["phantom flames"]=true,
    ["phantom striker"]=true,["phantom striker ball"]=true,
    ["phantom striker spawn explosion"]=true,["phase ball"]=true,["phase barrage"]=true,
    ["phase ring"]=true,["piercing rain"]=true,["piercing roots"]=true,["poison cloud"]=true,
    ["pulse beam"]=true,["pulse waves"]=true,["pulsefire"]=true,["pulsefire explosion"]=true,
    ["redemption"]=true,["rejuvenating spray"]=true,["rending slice"]=true,["revitalize"]=true,
    ["runic strike"]=true,["searing beam"]=true,["skull flames"]=true,
    ["small molten ball"]=true,["smite"]=true,["smite beam"]=true,["smite ring"]=true,
    ["solar beam"]=true,["soul drain"]=true,["soul drain particles"]=true,["spear strike"]=true,
    ["spear strike ring"]=true,["spirit bomb"]=true,["spirit bomb shockwave"]=true,
    ["star barrage"]=true,["starfall"]=true,["taunt"]=true,["taunting aura"]=true,
    ["thunderous blast"]=true,["triple blade throw"]=true,["tsunami"]=true,["twin slash"]=true,
    ["universal heal"]=true,["void beam"]=true,["void sphere"]=true,["void spheres"]=true,
    ["vortex"]=true,["vortex grenade"]=true,["vortex grenade explosion"]=true,
    ["water orb"]=true,["whirlwind"]=true,["wind blast"]=true,["amethystblasthitbox"]=true,
    ["arrowbarragehitbox"]=true,["berserkhitbox"]=true,["bladerevolverhitbox"]=true,
    ["bladestormhitbox"]=true,["bladethrowhitbox"]=true,["bleed"]=true,["bluefireball"]=true,
    ["burn"]=true,["chainedenergyblastshitbox"]=true,["chromaticrainhitbox"]=true,
    ["concussiveblastexplosion"]=true,["concussiveblastring"]=true,
    ["concussiveblasttrail"]=true,["crystalinecannonhitbox"]=true,["demonspikeone"]=true,
    ["demonspikethree"]=true,["demonspiketwo"]=true,["demonicspikeshitbox"]=true,
    ["demonicstrikehitbox"]=true,["earthclaphitbox"]=true,["earthkickhitbox"]=true,
    ["earthspikeshitbox"]=true,["electricboomhitbox"]=true,["electricfieldhitbox"]=true,
    ["enchantedshurikenhitbox"]=true,["energyorbhitbox"]=true,["explorergemexplosion"]=true,
    ["explosivepunchhitbox"]=true,["fireball"]=true,["firebombhitbox"]=true,
    ["flamecyclonehitbox"]=true,["focusbeamhitbox"]=true,["forgottenarmyhitbox"]=true,
    ["fungalpoisonhitbox"]=true,["galeslicehitbox"]=true,["genericattachpart"]=true,
    ["genericneonball"]=true,["ghostlyrampagehitbox"]=true,["groundaura"]=true,
    ["groundslam"]=true,["guardianblessingball"]=true,["guardianroarhitbox"]=true,
    ["handcannonhitbox"]=true,["holybarrier"]=true,["holycircle"]=true,["icecrashhitbox"]=true,
    ["icenovahitbox"]=true,["icespikeshitbox"]=true,["icetotemhitbox"]=true,
    ["iciclebarragehitbox"]=true,["illusionblasthitbox"]=true,["infernalblasthitbox"]=true,
    ["infernalorbhitbox"]=true,["infernalstrikehitbox"]=true,["innervate"]=true,
    ["lavabarragehitbox"]=true,["lavacagehitbox"]=true,["lavalashhitbox"]=true,
    ["lightningbursthitbox"]=true,["lightningstrike"]=true,["mightyleaphitbox"]=true,
    ["moltenshardshitbox"]=true,["phantombladeshitbox"]=true,["phantomstrikerballhitbox"]=true,
    ["phantomstrikerhitbox"]=true,["phase ring"]=true,["phasebeammodel"]=true,
    ["piercingrootshitbox"]=true,["pulsebeamhitbox"]=true,["pulsewaveshitbox"]=true,
    ["pulsewaveswave"]=true,["redemption"]=true,["rendingslicehitbox"]=true,["revitalize"]=true,
    ["runicstrikehitbox"]=true,["skullflameshitbox"]=true,["smitehitbox"]=true,["sounds"]=true,
    ["spearstrikehitbox"]=true,["starfallstar"]=true,["taunt"]=true,
    ["thunderousblasthitbox"]=true,["triplebladethrowhitbox"]=true,["tsunamihitbox"]=true,
    ["voidspherehitbox"]=true,["voidspherespawn"]=true,["vortexhitbox"]=true,
}

-- Bosses that invert the rule: these mark the one place you must STAND. A dodge
-- that only knows "avoid red" walks out of the safe circle and dies.
local SAFE_MARKERS = {
    ["cyansafezonemarker"]=true,["purplesafezonemarker"]=true,["safespotcircle"]=true,
    ["thirdbossmasssafespotcircles"]=true,["thirdbossmemorysafezone"]=true,
    ["thirdbosssafespot"]=true,["thirdbosssafespots"]=true,["yellowsafezonemarker"]=true,
}

-- Walks a part and its ancestor models against one of the tables above.
local function matchesGameName(part, tbl)
    if tbl[string.lower(part.Name)] then return true end
    local node = part.Parent
    for _ = 1, 4 do
        if not node or node == Workspace then break end
        if node:IsA("Model") or node:IsA("Folder") then
            if tbl[string.lower(node.Name)] then return true end
        end
        node = node.Parent
    end
    return false
end

local function isKnownEnemyAttack(part) return matchesGameName(part, ENEMY_ATTACKS) end
local function isKnownOwnEffect(part) return matchesGameName(part, OWN_EFFECTS) end
local function isSafeZoneMarker(part) return matchesGameName(part, SAFE_MARKERS) end

S.ENEMY_ATTACKS = ENEMY_ATTACKS
S.OWN_EFFECTS = OWN_EFFECTS
S.SAFE_MARKERS = SAFE_MARKERS
S.matchesGameName = matchesGameName
S.isKnownEnemyAttack = isKnownEnemyAttack
S.isKnownOwnEffect = isKnownOwnEffect
S.isSafeZoneMarker = isSafeZoneMarker
end
