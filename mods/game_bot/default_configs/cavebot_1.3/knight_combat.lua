setDefaultTab("Knight")

local defaults = {
  profile = "Balanced",
  manaReserve = 35,
  defensiveHp = 45,
  protectPlayers = true,
  survivalAssist = true,
  healSpellHp = 85,
  healthItemHp = 55,
  emergencyHp = 30,
  manaItemMp = 65,
  autoHaste = true,
  hasteMinMp = 45,
  autoFood = true,
  manaTraining = true,
  trainingStartMp = 98,
  trainingStopMp = 90
}

if type(storage.knightCombat) ~= "table" then
  storage.knightCombat = {}
end

local config = storage.knightCombat
for key, value in pairs(defaults) do
  if config[key] == nil then
    config[key] = value
  end
end

local profiles = {
  Safe = {
    areaTargets = 4,
    strongAreaTargets = 5,
    groundTargets = 5,
    strongSingleHealth = 70
  },
  Balanced = {
    areaTargets = 3,
    strongAreaTargets = 4,
    groundTargets = 4,
    strongSingleHealth = 60
  },
  Aggressive = {
    areaTargets = 2,
    strongAreaTargets = 3,
    groundTargets = 3,
    strongSingleHealth = 45
  }
}

local spells = {
  annihilation = {words = "exori gran ico", level = 110, mana = 300, cooldown = 30000},
  fierceBerserk = {words = "exori gran", level = 90, mana = 340, cooldown = 6000},
  frontSweep = {words = "exori min", level = 70, mana = 200, cooldown = 6000},
  berserk = {words = "exori", level = 35, mana = 115, cooldown = 4000},
  groundshaker = {words = "exori mas", level = 33, mana = 160, cooldown = 8000},
  whirlwind = {words = "exori hur", level = 28, mana = 40, cooldown = 6000},
  brutalStrike = {words = "exori ico", level = 16, mana = 30, cooldown = 6000}
}

local spellReadyAt = {}
local globalReadyAt = 0
local survivalLockUntil = 0
local lastHealthItemAttempt = 0
local lastManaItemAttempt = 0
local lastHealingRuneAttempt = 0
local healingSpellReadyAt = {}
local utilityReadyAt = {
  haste = 0,
  recovery = 0,
  trainingHeal = 0
}
local lastFoodAttempt = 0
local drainingOverflow = false
local lastDecision = "Waiting for target"

UI.Label("Knight Combat Brain")
local statusRow = UI.DualLabel("Decision", lastDecision, {maxWidth = 62})
local combatRow = UI.DualLabel("Combat", "-", {maxWidth = 62})

local profileButton
local profileOrder = {"Safe", "Balanced", "Aggressive"}

local function updateProfileButton()
  profileButton:setText("Profile: " .. config.profile)
end

profileButton = UI.Button("", function()
  local nextIndex = 1
  for index, name in ipairs(profileOrder) do
    if name == config.profile then
      nextIndex = index % #profileOrder + 1
      break
    end
  end
  config.profile = profileOrder[nextIndex]
  updateProfileButton()
end)
updateProfileButton()

UI.Label("Mana reserve %")
UI.TextEdit(tostring(config.manaReserve), function(widget, text)
  config.manaReserve = math.max(0, math.min(90, tonumber(text) or defaults.manaReserve))
end)

UI.Label("Defensive HP %")
UI.TextEdit(tostring(config.defensiveHp), function(widget, text)
  config.defensiveHp = math.max(1, math.min(95, tonumber(text) or defaults.defensiveHp))
end)

UI.Label("Healing spell below HP %")
UI.TextEdit(tostring(config.healSpellHp), function(widget, text)
  config.healSpellHp = math.max(1, math.min(100, tonumber(text) or defaults.healSpellHp))
end)

UI.Label("Health item below HP %")
UI.TextEdit(tostring(config.healthItemHp), function(widget, text)
  config.healthItemHp = math.max(1, math.min(100, tonumber(text) or defaults.healthItemHp))
end)

UI.Label("Emergency below HP %")
UI.TextEdit(tostring(config.emergencyHp), function(widget, text)
  config.emergencyHp = math.max(1, math.min(100, tonumber(text) or defaults.emergencyHp))
end)

UI.Label("Mana potion below MP %")
UI.TextEdit(tostring(config.manaItemMp), function(widget, text)
  config.manaItemMp = math.max(1, math.min(100, tonumber(text) or defaults.manaItemMp))
end)

UI.Label("Haste minimum MP %")
UI.TextEdit(tostring(config.hasteMinMp), function(widget, text)
  config.hasteMinMp = math.max(1, math.min(100, tonumber(text) or defaults.hasteMinMp))
end)

UI.Label("Mana training start MP %")
UI.TextEdit(tostring(config.trainingStartMp), function(widget, text)
  config.trainingStartMp = math.max(1, math.min(100, tonumber(text) or defaults.trainingStartMp))
end)

UI.Label("Mana training stop MP %")
UI.TextEdit(tostring(config.trainingStopMp), function(widget, text)
  config.trainingStopMp = math.max(1, math.min(100, tonumber(text) or defaults.trainingStopMp))
end)

local playerSafetyButton
local function updatePlayerSafetyButton()
  playerSafetyButton:setText("Area near players: " .. (config.protectPlayers and "blocked" or "allowed"))
end

playerSafetyButton = UI.Button("", function()
  config.protectPlayers = not config.protectPlayers
  updatePlayerSafetyButton()
end)
updatePlayerSafetyButton()

local survivalButton
local function updateSurvivalButton()
  survivalButton:setText("Survival assist: " .. (config.survivalAssist and "on" or "off"))
end

survivalButton = UI.Button("", function()
  config.survivalAssist = not config.survivalAssist
  updateSurvivalButton()
end)
updateSurvivalButton()

local hasteButton
local function updateHasteButton()
  hasteButton:setText("Auto haste: " .. (config.autoHaste and "on" or "off"))
end

hasteButton = UI.Button("", function()
  config.autoHaste = not config.autoHaste
  updateHasteButton()
end)
updateHasteButton()

local foodButton
local function updateFoodButton()
  foodButton:setText("Auto food: " .. (config.autoFood and "on" or "off"))
end

foodButton = UI.Button("", function()
  config.autoFood = not config.autoFood
  updateFoodButton()
end)
updateFoodButton()

local trainingButton
local function updateTrainingButton()
  trainingButton:setText("Mana overflow training: " .. (config.manaTraining and "on" or "off"))
end

trainingButton = UI.Button("", function()
  config.manaTraining = not config.manaTraining
  drainingOverflow = false
  updateTrainingButton()
end)
updateTrainingButton()

UI.Separator()
UI.Label("Restoration is selected from inventory automatically.")

local brainMacro = macro(100, "Knight Combat Brain", function()
  if KnightCombatBrain and KnightCombatBrain.processSurvival then
    KnightCombatBrain.processSurvival()
  end
  if KnightCombatBrain and KnightCombatBrain.processFood then
    KnightCombatBrain.processFood()
  end
  if KnightCombatBrain and KnightCombatBrain.processUtility then
    KnightCombatBrain.processUtility()
  end
  if not g_game.getAttackingCreature() then
    lastDecision = "Waiting for target"
    statusRow.right:setText(lastDecision)
    combatRow.right:setText("-")
  end
end)

local function setDecision(text, combat)
  lastDecision = text
  statusRow.right:setText(text)
  if combat then
    combatRow.right:setText(combat)
  end
end

local function isKnight()
  return player and player.isKnight and player:isKnight()
end

local function hasNearbyPlayer(range)
  for _, spectator in ipairs(g_map.getSpectatorsInRange(player:getPosition(), false, range, range)) do
    if spectator:isPlayer() and not spectator:isLocalPlayer() then
      return true
    end
  end
  return false
end

local function countMonsters(range)
  local count = 0
  for _, spectator in ipairs(g_map.getSpectatorsInRange(player:getPosition(), false, range, range)) do
    if spectator:isMonster() then
      count = count + 1
    end
  end
  return count
end

local function countFrontMonsters()
  local position = player:getPosition()
  local direction = player:getDirection()
  local offsets = {
    [North] = {{-1, -1}, {0, -1}, {1, -1}},
    [East] = {{1, -1}, {1, 0}, {1, 1}},
    [South] = {{-1, 1}, {0, 1}, {1, 1}},
    [West] = {{-1, -1}, {-1, 0}, {-1, 1}}
  }
  local count = 0
  for _, offset in ipairs(offsets[direction] or {}) do
    local tile = g_map.getTile({x = position.x + offset[1], y = position.y + offset[2], z = position.z})
    if tile then
      for _, creature in ipairs(tile:getCreatures()) do
        if creature:isMonster() then
          count = count + 1
        end
      end
    end
  end
  return count
end

local function manaReserve()
  return math.floor(player:getMaxMana() * config.manaReserve / 100)
end

local function canCast(key)
  local spell = spells[key]
  return player:getLevel() >= spell.level
    and player:getMana() >= spell.mana + manaReserve()
    and (spellReadyAt[key] or 0) <= now
    and globalReadyAt <= now
end

local function cast(key)
  local spell = spells[key]
  if not canCast(key) then
    return false
  end
  if not TargetBot.sayAttackSpell(spell.words, 1900) then
    return false
  end
  spellReadyAt[key] = now + spell.cooldown
  globalReadyAt = now + 2000
  setDecision(spell.words, combatRow.right:getText())
  return true
end

KnightCombatBrain = {}

local healthPotions = {
  {id = 23375, level = 200, name = "supreme health potion"},
  {id = 7643, level = 130, name = "ultimate health potion"},
  {id = 239, level = 80, name = "great health potion"},
  {id = 236, level = 50, name = "strong health potion"},
  {id = 266, level = 0, name = "health potion"},
  {id = 7876, level = 0, name = "small health potion"}
}

local manaPotions = {
  {id = 237, level = 50, name = "strong mana potion"},
  {id = 268, level = 0, name = "mana potion"}
}

local healingRunes = {
  {id = 3160, level = 24, magicLevel = 4, name = "ultimate healing rune"},
  {id = 3152, level = 15, magicLevel = 1, name = "intense healing rune"}
}

local function findAvailable(entries)
  for _, entry in ipairs(entries) do
    if player:getLevel() >= entry.level
      and player:getMagicLevel() >= (entry.magicLevel or 0)
      and g_game.findPlayerItem(entry.id, -1) then
      return entry
    end
  end
  return nil
end

local function useRestorationItem(entry, kind)
  if not entry then
    return false
  end

  local lastAttempt = kind == "mana" and lastManaItemAttempt or lastHealthItemAttempt
  if lastAttempt + 1000 > now then
    return false
  end

  TargetBot.useItem(entry.id, 0, player, 900)
  if kind == "mana" then
    lastManaItemAttempt = now
  else
    lastHealthItemAttempt = now
  end
  setDecision("Using " .. entry.name, combatRow.right:getText())
  return true
end

local function useHealingRune()
  if lastHealingRuneAttempt + 1000 > now then
    return false
  end
  local rune = findAvailable(healingRunes)
  if not rune then
    return false
  end
  TargetBot.useItem(rune.id, 0, player, 1000)
  lastHealingRuneAttempt = now
  survivalLockUntil = now + 1000
  setDecision("Using " .. rune.name, combatRow.right:getText())
  return true
end

local function castHealingSpell(hpPercent)
  local candidates = {
    {
      key = "intense",
      words = "exura gran ico",
      name = "intense wound cleansing",
      level = 80,
      mana = 200,
      cooldown = 600000,
      emergencyOnly = true
    },
    {
      key = "fair",
      words = "exura med ico",
      name = "fair wound cleansing",
      level = 300,
      mana = 90,
      cooldown = 1000
    },
    {
      key = "wound",
      words = "exura ico",
      name = "wound cleansing",
      level = 8,
      mana = 40,
      cooldown = 1000
    }
  }

  local spell
  for _, candidate in ipairs(candidates) do
    if (not candidate.emergencyOnly or hpPercent <= config.emergencyHp)
      and player:getLevel() >= candidate.level
      and player:getMana() >= candidate.mana
      and (healingSpellReadyAt[candidate.key] or 0) <= now then
      spell = candidate
      break
    end
  end

  if not spell or not TargetBot.saySpell(spell.words, 1000) then
    return false
  end

  healingSpellReadyAt[spell.key] = now + spell.cooldown
  survivalLockUntil = now + 1000
  setDecision("Casting " .. spell.name, combatRow.right:getText())
  return true
end

KnightCombatBrain.handlesSurvival = function()
  return brainMacro:isOn() and config.survivalAssist and isKnight()
end

KnightCombatBrain.processSurvival = function()
  if not KnightCombatBrain.handlesSurvival() or isInPz() then
    return false
  end

  local hpPercent = player:getHealthPercent()
  local manaPercent = manapercent()
  local usedHealth = false
  local usedSpell = false
  local usedRune = false

  if hpPercent <= config.healthItemHp then
    usedHealth = useRestorationItem(findAvailable(healthPotions), "health")
  end

  if hpPercent <= config.healSpellHp then
    usedSpell = castHealingSpell(hpPercent)
    if not usedSpell and hpPercent <= config.emergencyHp then
      usedRune = useHealingRune()
    end
  end

  if hpPercent <= config.emergencyHp then
    survivalLockUntil = math.max(survivalLockUntil, now + 750)
  end

  local usedMana = false
  if manaPercent <= config.manaItemMp then
    usedMana = useRestorationItem(findAvailable(manaPotions), "mana")
  end

  return usedHealth or usedSpell or usedRune or usedMana
end

local commonFoods = {
  {id = 3582, name = "ham"},
  {id = 3731, name = "fire mushroom"},
  {id = 3726, name = "orange mushroom"},
  {id = 22187, name = "roasted meat"},
  {id = 21146, name = "glooth steak"},
  {id = 3725, name = "brown mushroom"},
  {id = 12310, name = "haunch of boar"},
  {id = 24382, name = "bug meat"},
  {id = 3593, name = "melon"},
  {id = 3580, name = "northern pike"},
  {id = 3577, name = "meat"},
  {id = 3578, name = "fish"},
  {id = 3600, name = "bread"},
  {id = 3607, name = "cheese"},
  {id = 3602, name = "brown bread"}
}

KnightCombatBrain.handlesFood = function()
  return brainMacro:isOn() and config.autoFood and isKnight()
end

KnightCombatBrain.processFood = function()
  if not KnightCombatBrain.handlesFood() or not isHungry() or lastFoodAttempt + 3000 > now then
    return false
  end

  for _, food in ipairs(commonFoods) do
    local item = g_game.findPlayerItem(food.id, -1)
    if item then
      g_game.use(item)
      lastFoodAttempt = now
      setDecision("Eating " .. food.name, combatRow.right:getText())
      return true
    end
  end

  lastFoodAttempt = now
  setDecision("Hungry: no common food", combatRow.right:getText())
  return false
end

local function hasMovementReason()
  local target = g_game.getAttackingCreature()
  if player:isWalking() then
    return true
  end
  if target then
    return getDistanceBetween(player:getPosition(), target:getPosition()) > 1
  end
  return CaveBot and CaveBot.isOn and CaveBot.isOn()
end

local function castUtility(words, key, manaCost, cooldown, decision)
  if player:getMana() < manaCost or utilityReadyAt[key] > now then
    return false
  end
  if not TargetBot.saySpell(words, 1000) then
    return false
  end
  utilityReadyAt[key] = now + cooldown
  setDecision(decision, combatRow.right:getText())
  return true
end

KnightCombatBrain.handlesHaste = function()
  return brainMacro:isOn() and config.autoHaste and isKnight()
end

KnightCombatBrain.processUtility = function()
  if not brainMacro:isOn() or not isKnight() or isInPz() or survivalLockUntil > now then
    drainingOverflow = false
    return false
  end

  local manaPercent = manapercent()
  local inCombat = g_game.getAttackingCreature() ~= nil or isInFight()

  if config.autoHaste
    and not hasHaste()
    and player:getLevel() >= 14
    and manaPercent >= config.hasteMinMp
    and player:getMana() >= 60 + manaReserve()
    and hasMovementReason()
    and castUtility("utani hur", "haste", 60, 2000, "Auto haste") then
    return true
  end

  if not config.manaTraining or inCombat then
    drainingOverflow = false
    return false
  end

  if manaPercent >= config.trainingStartMp then
    drainingOverflow = true
  elseif manaPercent <= config.trainingStopMp then
    drainingOverflow = false
  end

  if not drainingOverflow then
    return false
  end

  if player:getLevel() >= 50
    and castUtility("utura", "recovery", 75, 60000, "Training ML: recovery") then
    return true
  end

  if config.autoHaste
    and not hasHaste()
    and player:getLevel() >= 14
    and castUtility("utani hur", "haste", 60, 2000, "Training ML: haste") then
    return true
  end

  if player:getLevel() >= 8
    and castUtility("exura ico", "trainingHeal", 40, 2000, "Training ML: wound cleansing") then
    return true
  end

  return false
end

KnightCombatBrain.process = function(params, targets, isLooting)
  if not brainMacro:isOn() or not isKnight() then
    return false
  end

  local target = params and params.creature
  if not target or not target:isMonster() then
    setDecision("Invalid target")
    return true
  end

  if isLooting or isInPz() then
    setDecision(isLooting and "Looting" or "Protection zone")
    return true
  end

  local hpPercent = player:getHealthPercent()
  local manaPercent = manapercent()
  local targetHealth = target:getHealthPercent()
  local distance = getDistanceBetween(player:getPosition(), target:getPosition())
  local adjacent = countMonsters(1)
  local nearby = countMonsters(3)
  local front = countFrontMonsters()
  local playersNearby = config.protectPlayers and hasNearbyPlayer(8)
  local profile = profiles[config.profile] or profiles.Balanced
  local summary = adjacent .. " close, " .. manaPercent .. "% mana"
  combatRow.right:setText(summary)

  if survivalLockUntil > now then
    setDecision("Survival priority", summary)
    return true
  end

  if hpPercent <= config.defensiveHp then
    setDecision("Defensive: preserve HP", summary)
    return true
  end

  if manaPercent <= config.manaReserve then
    setDecision("Preserving mana", summary)
    return true
  end

  if distance > 1 then
    if targetHealth > 8 and cast("whirlwind") then
      return true
    end
    setDecision("Closing distance", summary)
    return true
  end

  if not playersNearby and targetHealth > 12 then
    if adjacent >= profile.strongAreaTargets and cast("fierceBerserk") then
      return true
    end
    if front >= profile.areaTargets and cast("frontSweep") then
      return true
    end
    if adjacent >= profile.areaTargets and cast("berserk") then
      return true
    end
    if nearby >= profile.groundTargets and cast("groundshaker") then
      return true
    end
  end

  if adjacent <= 2 and targetHealth >= profile.strongSingleHealth and cast("annihilation") then
    return true
  end

  if targetHealth > 8 and cast("brutalStrike") then
    return true
  end

  if playersNearby then
    setDecision("Player nearby: single target", summary)
  elseif targetHealth <= 8 then
    setDecision("Finishing with melee", summary)
  else
    setDecision("Waiting cooldown", summary)
  end
  return true
end
