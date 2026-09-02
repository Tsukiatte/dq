-- gamedata.lua - What the game itself says, rather than what a part looks like.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)
local Workspace = S.Workspace

-- =========================================================================
-- GAME KNOWLEDGE (3.0.0, rebuilt 3.2.5)
--
-- Read straight out of the place files (see game/GAME_NOTES.md). The game keeps
-- its own attack visuals in ReplicatedStorage.enemyProjectiles and the player's
-- in ReplicatedStorage.projectiles / .abilities, which is exactly the "is this
-- mine or theirs" question the appearance scorer used to guess at.
--
-- 3.2.5: read RECURSIVELY. Every boss keeps its attacks in a subfolder of its
-- own - enemyProjectiles.Steampunk.bossCannonBeam, and so on - and the first
-- version of this table only took top-level children and then dropped Folders
-- to avoid picking up gear. That threw away 111 attack models: every boss
-- attack in the game, which is precisely what went unnoticed in Steampunk
-- Sewers.
--
-- Note `hitbox` and `precast` in the list. Every one of those boss models is
-- built the same way - a PrimaryPart, a `hitBox` and a `precast` - so those two
-- names alone catch attacks from bosses nobody has dumped yet.
--
-- Names are matched on the part AND its ancestor models, because these are
-- Models whose individual parts carry their own names.
--
-- Equipment is still excluded, at any depth: an Accessory named bossRifle is a
-- weapon an enemy is holding, and fleeing from it would mean fleeing from every
-- enemy in the room.
-- =========================================================================

-- 519 enemy attack names. A name here IS an attack; no scoring needed.
local ENEMY_ATTACKS = {
    ["000"]=true,["001"]=true,["002"]=true,["003"]=true,["004"]=true,["005"]=true,["007"]=true,
    ["008"]=true,["009"]=true,["012"]=true,["013"]=true,["014"]=true,["016"]=true,["017"]=true,
    ["018"]=true,["019"]=true,["020"]=true,["021"]=true,["022"]=true,["023"]=true,["024"]=true,
    ["025"]=true,["026"]=true,["027"]=true,["034"]=true,["036"]=true,["037"]=true,["038"]=true,
    ["042"]=true,["046"]=true,["056"]=true,["059"]=true,["061"]=true,["063"]=true,["077"]=true,
    ["078"]=true,["079"]=true,["080"]=true,["081"]=true,["082"]=true,["083"]=true,["084"]=true,
    ["086"]=true,["087"]=true,["088"]=true,["089"]=true,["090"]=true,["091"]=true,["092"]=true,
    ["093"]=true,["094"]=true,["095"]=true,["096"]=true,["097"]=true,["099"]=true,["1"]=true,
    ["10"]=true,["102"]=true,["11"]=true,["110"]=true,["112"]=true,["118"]=true,["119"]=true,
    ["120"]=true,["121"]=true,["123"]=true,["124"]=true,["125"]=true,["126"]=true,["127"]=true,
    ["128"]=true,["129"]=true,["130"]=true,["131"]=true,["132"]=true,["133"]=true,["134"]=true,
    ["135"]=true,["136"]=true,["137"]=true,["138"]=true,["139"]=true,["140"]=true,["141"]=true,
    ["142"]=true,["143"]=true,["144"]=true,["145"]=true,["148"]=true,["156"]=true,["157"]=true,
    ["158"]=true,["159"]=true,["160"]=true,["161"]=true,["180"]=true,["185"]=true,["193"]=true,
    ["194"]=true,["2"]=true,["200"]=true,["201"]=true,["203"]=true,["270"]=true,["271"]=true,
    ["272"]=true,["273"]=true,["276"]=true,["3"]=true,["4"]=true,["5"]=true,["6"]=true,
    ["7"]=true,["8"]=true,["9"]=true,["aggressivefreezepart"]=true,
    ["aggressivelavawalkerhit"]=true,["aoeswipe"]=true,["arm1"]=true,["arm2"]=true,
    ["arm3"]=true,["arm4"]=true,["arm5"]=true,["arm6"]=true,["armormesh"]=true,
    ["artillerymobshot"]=true,["artilleryrock"]=true,["attachpart"]=true,
    ["azrallik's heart"]=true,["azrallikpunch"]=true,["azrallikpunchspread"]=true,["ball"]=true,
    ["ball1"]=true,["ball2"]=true,["battlemageorb"]=true,["bellyflophit"]=true,
    ["biggolemrock"]=true,["bigmagebeam"]=true,["bigrock"]=true,["black hole"]=true,
    ["bonusbossbouncingorb"]=true,["bonusbossbouncingorbbad"]=true,
    ["bonusbossbouncingorbgood"]=true,["bonusbossflameprecast"]=true,
    ["bonusbossfreezingorbbeam"]=true,["bonusbossgroundflame"]=true,["bonusbosslongline"]=true,
    ["bonusbossmemorymodel"]=true,["bonusbosssmallspiralflame"]=true,
    ["bonusbosssweepingflames"]=true,["bonusbosstallswirly"]=true,["bosscannonbeam"]=true,
    ["bossforwardbeam"]=true,["bosshorizontalbeam"]=true,["bosshunterinnerflameshot"]=true,
    ["bosshuntermiddlefire"]=true,["bosshuntersidefire1"]=true,["bosshuntersidefire2"]=true,
    ["bossmagebigsideshot"]=true,["bossmagemainlaser"]=true,["bossmagesideshot"]=true,
    ["bossmelee"]=true,["bossrandomstrike"]=true,["bossrifleprecast"]=true,
    ["bossrifleshot"]=true,["bossshot"]=true,["canalsnpcmageshot"]=true,
    ["cannonbarragecannonhit"]=true,["cannonbarragehit"]=true,["cannoncrabshot"]=true,
    ["chickenmage"]=true,["chickenmelee"]=true,["circle"]=true,["circlehit"]=true,
    ["circleprecast"]=true,["cog"]=true,["cog1"]=true,["cog2"]=true,["cogmodel"]=true,
    ["colorblindrune"]=true,["concussiveblast"]=true,["cool placeholething?"]=true,
    ["corruptlinefire"]=true,["corruptmolotov"]=true,["crescent"]=true,["cross"]=true,
    ["crossbeam"]=true,["crossshot"]=true,["crossshuriken"]=true,["crystal"]=true,
    ["crystalflash"]=true,["crystalneon"]=true,["cylinder"]=true,["damageprecast"]=true,
    ["decal"]=true,["doubleflamebeam"]=true,["droneshot"]=true,["e"]=true,
    ["eastersecondbossrandomline"]=true,["eggpart"]=true,["electrictowerhit"]=true,
    ["eliteswordsmanspin"]=true,["enchantedfirstbossfolloworb"]=true,["enchantpart"]=true,
    ["energy source"]=true,["explosion"]=true,["explosivebomb"]=true,["explosivemobshot1"]=true,
    ["explosivemobshot2"]=true,["explosivemobshot3"]=true,["eye"]=true,
    ["finalbossarrowshothitbox"]=true,["finalbossexplosion"]=true,["finalbosslineblast"]=true,
    ["finalbossorbshot"]=true,["finalbossrotatingcircle"]=true,["fingerblasthit"]=true,
    ["firstbossbeampart"]=true,["firstbossbeamshot"]=true,["firstbossbeamtrackerline"]=true,
    ["firstbossbigspike"]=true,["firstbossblindingblastbeam"]=true,
    ["firstbossbombexplosion"]=true,["firstbosscrisscross"]=true,["firstbosscrystal"]=true,
    ["firstbosscrystaldrop"]=true,["firstbossdebrifall"]=true,["firstbossflameshot"]=true,
    ["firstbossfolloworb"]=true,["firstbossgatlinggunshot"]=true,["firstbossiceradius"]=true,
    ["firstbossjumpslam"]=true,["firstbosslaserprecast"]=true,["firstbosslefthandshot"]=true,
    ["firstbosslongline"]=true,["firstbossminionexplosion"]=true,["firstbossmoveorb"]=true,
    ["firstbossmovingorb"]=true,["firstbossorbprecastline"]=true,
    ["firstbosspassivecriclehitbox"]=true,["firstbossplayeronfire"]=true,
    ["firstbossrighthandshot"]=true,["firstbossrocket"]=true,["firstbossrockethitbox"]=true,
    ["firstbossseekingspikes"]=true,["firstbossshootplayer"]=true,["firstbosssiegeshot"]=true,
    ["firstbossskyshot"]=true,["firstbossslamground"]=true,["firstbossspinningrock"]=true,
    ["firstbosssupplyoverhead"]=true,["firstbossturretmodel"]=true,["firstbossturretshot"]=true,
    ["firstbossupshot"]=true,["flame"]=true,["flame cyclone"]=true,["flamebeam"]=true,
    ["flameeffect"]=true,["flamelashpart"]=true,["flamelashprecast"]=true,
    ["flameshurikenhit"]=true,["flamingshuriken"]=true,["freezeplayerpart"]=true,["fuse"]=true,
    ["gank"]=true,["gasball"]=true,["genericneonball"]=true,["ghastlyriflemanshot"]=true,
    ["glow"]=true,["glowpart"]=true,["glowy"]=true,["golemrock"]=true,["golemrockclap"]=true,
    ["golemrocksmall"]=true,["golemrockthrow"]=true,["golemrockthrowsmall"]=true,
    ["groundpart"]=true,["growingprecast"]=true,["hammerbothit"]=true,["harpoon"]=true,
    ["harpoonmodel"]=true,["hat"]=true,["helix"]=true,["hitbox"]=true,
    ["hitindicatoriceaoe"]=true,["hitmanstrike"]=true,["hitmodel"]=true,["horizontalbeam"]=true,
    ["humanoidrootpart"]=true,["ice"]=true,["iceaoe"]=true,["icebeam"]=true,
    ["icebeamindicator"]=true,["icebomb"]=true,["initialhunterbossentry"]=true,
    ["initialkingbossentry"]=true,["initialmagebossentry"]=true,["innerarm1"]=true,
    ["innerarm2"]=true,["innerarm3"]=true,["innerarm4"]=true,["innerarm5"]=true,
    ["innerarm6"]=true,["innerball"]=true,["innerbeam"]=true,["innerhitbox"]=true,
    ["innerprecast"]=true,["innersphere"]=true,["insidebook"]=true,["kinglandingarea"]=true,
    ["kolvumarspit"]=true,["kraken tentacle"]=true,["krakenhitbox"]=true,["krakeninkhit"]=true,
    ["largeicespikes"]=true,["laserbeam"]=true,["lefthand"]=true,["lefthitbox"]=true,
    ["leftprecast"]=true,["leftprecastgood"]=true,["lionshot"]=true,
    ["magebossminionspawneffect"]=true,["magebossstrraightshot"]=true,
    ["magehorizontalbeam"]=true,["mageprojectileball"]=true,["mainbeam"]=true,["mainpart"]=true,
    ["mediumicespikes"]=true,["meshes/beveled"]=true,["meshes/beveledinverted"]=true,
    ["meshes/daggerss_circle"]=true,["meshes/haunted ten"]=true,
    ["meshes/mgguard_icosphere"]=true,["meshes/mgmage_plane"]=true,["meshes/portal1"]=true,
    ["meshes/sphere"]=true,["meshpart"]=true,["middle"]=true,["middlebeam"]=true,
    ["minionexplosion"]=true,["minionexplosionball"]=true,["minionexplosionhitbox"]=true,
    ["minionindicator"]=true,["neon1"]=true,["neon2"]=true,["neonpart"]=true,["newpart"]=true,
    ["northernaggressivefreezepart"]=true,["npcmageshot"]=true,["npcmagespikes"]=true,
    ["npcshurikenthrow"]=true,["orb"]=true,["outer"]=true,["outerbeam"]=true,
    ["outerhitbox"]=true,["outerprecast"]=true,["outerring"]=true,["outersphere"]=true,
    ["outerspherewind"]=true,["outwardblastsize1"]=true,["outwardblastsize2"]=true,
    ["outwardblastsize3"]=true,["outwardblastsize4"]=true,["outwardblastsize5"]=true,
    ["overgrowthlonglinespikes"]=true,["overgrowthspikes"]=true,["overheadcannon"]=true,
    ["particlepart"]=true,["particles"]=true,["pinkfreezepart"]=true,
    ["playerpulledbubble"]=true,["poison mushroom"]=true,["poisonbomb"]=true,["portal"]=true,
    ["precast"]=true,["precasts"]=true,["projectile"]=true,["pullplayerpart"]=true,
    ["redfreezepart"]=true,["riflemanshot"]=true,["righthand"]=true,["righthitbox"]=true,
    ["rightprecast"]=true,["rightprecastgood"]=true,["ring"]=true,["ring1"]=true,["ring2"]=true,
    ["rock"]=true,["rock mesh"]=true,["rockdebri"]=true,["rockexplosion"]=true,
    ["rockexplosionsmall"]=true,["rockshatter"]=true,["row"]=true,["secondbossbigcircle"]=true,
    ["secondbossbigrockdebris"]=true,["secondbosscheckeredline"]=true,
    ["secondbosscirclehit"]=true,["secondbosscrescent"]=true,["secondbosscriclehitbox"]=true,
    ["secondbosscrossbeam"]=true,["secondbossdebrifall"]=true,
    ["secondbossfailedexplosion"]=true,["secondbossgeyser"]=true,["secondbossgeysershot"]=true,
    ["secondbossgreenorb"]=true,["secondbossgroundaura"]=true,
    ["secondbossgroundslamcircle"]=true,["secondbosshorizontalbeam"]=true,
    ["secondbosshorizontalline"]=true,["secondbosslines"]=true,["secondbosslocalrockfall"]=true,
    ["secondbosslocalspike"]=true,["secondbosslonglinepassive"]=true,
    ["secondbosslonglingeringline"]=true,["secondbossmark"]=true,["secondbossmovingbeam"]=true,
    ["secondbossorb"]=true,["secondbossorbshot"]=true,["secondbossoverheadrock"]=true,
    ["secondbosspassivecircle"]=true,["secondbosspull"]=true,["secondbosspulsewave"]=true,
    ["secondbosspunchcircle"]=true,["secondbosspunchhorizontalbeam"]=true,
    ["secondbossrandomline"]=true,["secondbossrandomlineshot"]=true,
    ["secondbossrandompulse"]=true,["secondbossrandomsquare"]=true,["secondbossredorb"]=true,
    ["secondbossrock"]=true,["secondbossrockfall"]=true,["secondbossrockhit"]=true,
    ["secondbossshootplayer"]=true,["secondbossspinninglaser"]=true,
    ["secondbossstabprojectile"]=true,["secondbossverticalbeam"]=true,
    ["secondbossverticalline"]=true,["secondbosswave"]=true,["secondbossyelloworb"]=true,
    ["secondbosszigzag"]=true,["serpentfirehitbox"]=true,["serpentplayershot"]=true,
    ["serpentwaterhitbox"]=true,["shark1"]=true,["shark2"]=true,["sharkthrowclient"]=true,
    ["sharkthrowhitbox"]=true,["shootershot"]=true,["shot"]=true,["shuriken"]=true,
    ["shurikens"]=true,["shurikenthrow"]=true,["silkblast"]=true,["smallicespikes"]=true,
    ["spearmanfreezepart"]=true,["spearmanstrike"]=true,["spike"]=true,["spikeprecast"]=true,
    ["spikes"]=true,["spinbotspin"]=true,["spiritorb"]=true,["spiritstrike"]=true,
    ["spore tree"]=true,["steampunkrangemobshot"]=true,["sucker1a"]=true,["sucker2a"]=true,
    ["sucker2b"]=true,["sucker3a"]=true,["sucker3b"]=true,["sucker4a"]=true,["sucker4b"]=true,
    ["sucker5a"]=true,["sucker5b"]=true,["sucker6a"]=true,["sucker6b"]=true,["swirlpart"]=true,
    ["t"]=true,["tail"]=true,["tallswirl"]=true,["thirdbossbeampart"]=true,
    ["thirdbossbeamshot"]=true,["thirdbossbouncingorb"]=true,["thirdbossbouncingorbbeam"]=true,
    ["thirdbosscirclehit"]=true,["thirdbosscirclehit2"]=true,["thirdbosscrescent"]=true,
    ["thirdbosscursering"]=true,["thirdbossdualswingline"]=true,["thirdbossexplosionshot"]=true,
    ["thirdbossflamewall"]=true,["thirdbossflamewallhitbox"]=true,
    ["thirdbossfrozencircle"]=true,["thirdbosslavaline"]=true,["thirdbosslifestealbeams"]=true,
    ["thirdbosslifestealhitbox"]=true,["thirdbosslineshot"]=true,
    ["thirdbossmemorydamagezone"]=true,["thirdbossmissile"]=true,["thirdbossmultirings"]=true,
    ["thirdbossoneshotbeam"]=true,["thirdbossorbshot"]=true,["thirdbossoverheadringmodel"]=true,
    ["thirdbosspassiveorb"]=true,["thirdbossrandomline"]=true,["thirdbosssmite"]=true,
    ["thirdbossspiralorb"]=true,["thirdbossspiralshot"]=true,["thirdbossspreadline"]=true,
    ["thirdbosssshapecircle"]=true,["tornado"]=true,["trail1"]=true,["trail2"]=true,
    ["uppertorso"]=true,["volcanicfirstbossflameshot"]=true,
    ["volcanicsecondbossrandomline"]=true,["wave"]=true,["whirl1"]=true,["whirl2"]=true,
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

-- The parts every attack Model in this game is built from. The hitBox is the
-- damage and it is INVISIBLE; the precast is the telegraph and it is not. Both
-- are recognised by structure, which is the only way to see the hitBox at all.
local ATTACK_PARTS = { hitbox = true, precast = true, precasthitbox = true }

-- Structure rather than appearance: is this part a known attack volume?
--
-- Returns true for a part whose own name or whose ancestor model's name is a
-- known attack, and for the hitBox/precast pair inside any model that is not
-- ours. That second rule is what generalises: every boss in this game builds
-- its attacks the same way, so it catches bosses nobody has dumped.
local function isAttackStructure(part)
    if ATTACK_PARTS[string.lower(part.Name)] then
        -- Only inside a model. A loose part called "hitBox" in the map is
        -- scenery; one inside hammerBotHit is the thing that kills you.
        local model = part:FindFirstAncestorOfClass("Model")
        if model and not model:FindFirstChildOfClass("Humanoid") then return true end
    end
    return false
end

local function isKnownEnemyAttack(part) return matchesGameName(part, ENEMY_ATTACKS) end
local function isKnownOwnEffect(part) return matchesGameName(part, OWN_EFFECTS) end
local function isSafeZoneMarker(part) return matchesGameName(part, SAFE_MARKERS) end

-- Names too generic to identify anything. A MeshPart called MeshPart, an
-- ice part called Ice, a wave, a ball: the dump has attacks built from parts
-- with these names, and matching the map by them made scenery into hazards.
-- Structure (hitBox/precast under a Model) still catches the attacks.
for _, generic in ipairs({ "meshpart", "part", "model", "union", "unionoperation", "ball", "wave", "ice",
    "hitbox", "precast", "primarypart", "attachment", "glow", "effect", "beam" }) do
    ENEMY_ATTACKS[generic] = nil
end
S.ENEMY_ATTACKS = ENEMY_ATTACKS
S.OWN_EFFECTS = OWN_EFFECTS
S.SAFE_MARKERS = SAFE_MARKERS
S.matchesGameName = matchesGameName
S.isAttackStructure = isAttackStructure
S.ATTACK_PARTS = ATTACK_PARTS

-- Arming delays measured or read from the client script, by attack Model
-- name (lowercased). Seeded into RT.armDelays only where nothing has been
-- learned yet, so the FIRST cast of these is time-aware too. 0 = live from
-- the moment it appears. Anything learned in play overrides these.
--   beam                  Steampunk second boss pulse wave: six beams per
--                         cast, fired 4.8s after the strips appear (video,
--                         2026-09-02). 4.5 keeps the margin on the safe side.
--   secondbossrandompulse the ball: the client brightens its precast 0.2s
--                         after it appears; it is live from the start.
local DEFAULT_ARM_DELAYS = {
    beam = 4.5,
    secondbossrandompulse = 0,
    -- Northern Lands, from the captures of 2026-09-02: the mage shot's
    -- precast appears and the hit lands 0.9s after the Model does; the
    -- spearman and warrior strikes land at 0.88s.
    northernmageshot = 0.9,
    spearmanstrikehitbox = 0.85,
    northernwarriorlinestrike = 0.85,
    northernwarriorcirclestrike = 0.85,
}
-- Windows: first and last age at which an attack has been seen to hurt. A
-- window makes the attack floor before its lead and floor again after
-- `last` plus the linger, whatever its visuals are doing.
local DEFAULT_ARM_SPANS = {
    northernmageshot = { first = 0.9, last = 1.2 },
    spearmanstrikehitbox = { first = 0.85, last = 1.2 },
    northernwarriorlinestrike = { first = 0.85, last = 1.2 },
    northernwarriorcirclestrike = { first = 0.85, last = 1.2 },
}
-- Attacks that keep hurting after their warning fades: the fade does not
-- end them. The Midgardian Champion's passive beams burn for seconds after
-- their precast goes (Studio recreation, 2026-09-02).
local DEFAULT_LONG_LIVED = {
    firstbosspassivebeam = true,
}
S.DEFAULT_ARM_DELAYS = DEFAULT_ARM_DELAYS
S.DEFAULT_ARM_SPANS = DEFAULT_ARM_SPANS
S.DEFAULT_LONG_LIVED = DEFAULT_LONG_LIVED
for name, delay in pairs(DEFAULT_ARM_DELAYS) do
    if S.RT.armDelays[name] == nil then S.RT.armDelays[name] = delay end
end
for name, span in pairs(DEFAULT_ARM_SPANS) do
    if S.RT.armSpans[name] == nil then S.RT.armSpans[name] = { first = span.first, last = span.last } end
end
for name in pairs(DEFAULT_LONG_LIVED) do
    if S.RT.armLongLived[name] == nil then S.RT.armLongLived[name] = true end
end
S.isKnownEnemyAttack = isKnownEnemyAttack
S.isKnownOwnEffect = isKnownOwnEffect
S.isSafeZoneMarker = isSafeZoneMarker
end
