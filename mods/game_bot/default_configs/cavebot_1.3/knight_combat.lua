setDefaultTab("Knight")

local defaults = {
  profile = "Balanced",
  manaReserve = 35,
  defensiveHp = 45,
  protectPlayers = true,
  survivalAssist = true,
  adaptiveSurvival = true,
  healSpellHp = 85,
  healthItemHp = 55,
  emergencyHp = 30,
  manaItemMp = 65,
  autoHaste = true,
  hasteMinMp = 45,
  autoFood = true,
  brainLogging = true,
  manaTraining = true,
  trainingStartMp = 98,
  trainingStopMp = 90,
  manualManaReserve = false,
  manualDefensiveHp = false,
  manualHealSpellHp = false,
  manualHealthItemHp = false,
  manualEmergencyHp = false,
  manualManaItemMp = false,
  manualHasteMinMp = false,
  manualTrainingStartMp = false,
  manualTrainingStopMp = false
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
config.adaptiveSurvival = true

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
local damageSamples = {}
local lastObservedHealth = player:getHealth()
local adaptiveThresholds = nil
local effectiveThresholds = {}
local lastDecision = "Waiting for target"
local lastLoggedDecision = ""
local lastSnapshotLog = 0
local lastSummaryLog = 0
local lastLogFlush = 0
local logLines = {}
local logStats = {
  attackSpells = 0,
  healingSpells = 0,
  healthItems = 0,
  manaItems = 0,
  healingRunes = 0,
  foods = 0,
  haste = 0,
  trainingSpells = 0
}
local resourceState = {
  pending = {},
  lastNotice = {},
  huntRisk = 0,
  huntSamples = 0
}
local logDirectory = configDir .. "/logs"
local logFileName = string.format(
  "knight_brain_%s_%s.log",
  player:getName():gsub("[^%w_-]", "_"),
  os.date("%Y%m%d_%H%M%S")
)
local logPath = logDirectory .. "/" .. logFileName

pcall(function()
  if not g_resources.directoryExists(logDirectory) then
    g_resources.makeDir(logDirectory)
  end
end)

local function flushBrainLog()
  if not config.brainLogging or #logLines == 0 then
    return
  end
  pcall(function()
    g_resources.writeFileContents(logPath, table.concat(logLines, "\n") .. "\n")
  end)
end

local function brainLog(event, details)
  if not config.brainLogging then
    return
  end
  table.insert(logLines, string.format(
    "%s | %-10s | %s",
    os.date("%Y-%m-%d %H:%M:%S"),
    event,
    details or ""
  ))
  if #logLines % 10 == 0 then
    flushBrainLog()
  end
end

brainLog("START", string.format(
  "player=%s level=%d vocation=%d profile=%s",
  player:getName(),
  player:getLevel(),
  player:getVocation(),
  config.profile
))

UI.Label("Knight Combat Brain")
local statusRow = UI.DualLabel("Decision", lastDecision, {maxWidth = 62})
local combatRow = UI.DualLabel("Combat", "-", {maxWidth = 62})
local adaptiveRow = UI.DualLabel("Adaptive", "-", {maxWidth = 62})

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

local percentWidgets = {}
local function addPercentControl(key, manualKey, label, minimum, maximum)
  percentWidgets[key] = UI.ManualPercent({
    label = label,
    value = config[key],
    manual = config[manualKey],
    minimum = minimum,
    maximum = maximum
  }, function(_, params)
    config[key] = params.value
    config[manualKey] = params.manual
  end)
end

addPercentControl("manaReserve", "manualManaReserve", "Mana reserve", 0, 90)
addPercentControl("defensiveHp", "manualDefensiveHp", "Defensive HP", 1, 95)
addPercentControl("healSpellHp", "manualHealSpellHp", "Healing spell HP", 1, 100)
addPercentControl("healthItemHp", "manualHealthItemHp", "Health item HP", 1, 100)
addPercentControl("emergencyHp", "manualEmergencyHp", "Emergency HP", 1, 100)
addPercentControl("manaItemMp", "manualManaItemMp", "Mana potion MP", 1, 100)
addPercentControl("hasteMinMp", "manualHasteMinMp", "Haste minimum MP", 1, 100)
addPercentControl("trainingStartMp", "manualTrainingStartMp", "Training start MP", 1, 100)
addPercentControl("trainingStopMp", "manualTrainingStopMp", "Training stop MP", 1, 100)

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

local loggingButton
local function updateLoggingButton()
  loggingButton:setText("Brain logging: " .. (config.brainLogging and "on" or "off"))
end

loggingButton = UI.Button("", function()
  config.brainLogging = not config.brainLogging
  updateLoggingButton()
  if config.brainLogging then
    brainLog("LOGGING", "enabled")
  else
    flushBrainLog()
  end
end)
updateLoggingButton()

UI.Button("Open Brain logs", function()
  flushBrainLog()
  g_platform.openDir(g_resources.getWriteDir() .. logDirectory)
end)

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
UI.Label("Check a percentage to override the Brain.")

if storage._macros["Knight Combat Brain"] == nil then
  storage._macros["Knight Combat Brain"] = true
end

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
  if lastSummaryLog + 60000 <= now then
    lastSummaryLog = now
    brainLog("SUMMARY", string.format(
      "attack=%d heal=%d hpItems=%d mpItems=%d runes=%d food=%d haste=%d training=%d",
      logStats.attackSpells,
      logStats.healingSpells,
      logStats.healthItems,
      logStats.manaItems,
      logStats.healingRunes,
      logStats.foods,
      logStats.haste,
      logStats.trainingSpells
    ))
    flushBrainLog()
  end
  if lastLogFlush + 5000 <= now then
    lastLogFlush = now
    flushBrainLog()
  end
end)

local function setDecision(text, combat)
  lastDecision = text
  statusRow.right:setText(text)
  if combat then
    combatRow.right:setText(combat)
  end
  if text ~= lastLoggedDecision then
    lastLoggedDecision = text
    brainLog("DECISION", string.format(
      "%s hp=%d%% mp=%d%%",
      text,
      player:getHealthPercent(),
      manapercent()
    ))
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
  local reservePercent = effectiveThresholds.reserve or config.manaReserve
  return math.floor(player:getMaxMana() * reservePercent / 100)
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
  logStats.attackSpells = logStats.attackSpells + 1
  brainLog("ATTACK", string.format(
    "spell=%s hp=%d%% mp=%d%%",
    spell.words,
    player:getHealthPercent(),
    manapercent()
  ))
  setDecision(spell.words, combatRow.right:getText())
  return true
end

KnightCombatBrain = {}

local healthPotions = {
  {id = 23375, level = 200, name = "supreme health potion", estimate = 875},
  {id = 7643, level = 130, name = "ultimate health potion", estimate = 650},
  {id = 239, level = 80, name = "great health potion", estimate = 425},
  {id = 236, level = 50, name = "strong health potion", estimate = 250},
  {id = 266, level = 0, name = "health potion", estimate = 125},
  {id = 7876, level = 0, name = "small health potion", estimate = 75}
}

local manaPotions = {
  {id = 237, level = 50, name = "strong mana potion", estimate = 150},
  {id = 268, level = 0, name = "mana potion", estimate = 100}
}

local healingRunes = {
  {id = 3160, level = 24, magicLevel = 4, name = "ultimate healing rune", estimate = 250},
  {id = 3152, level = 15, magicLevel = 1, name = "intense healing rune", estimate = 140}
}

local healingSpells = {
  {
    key = "intense",
    words = "exura gran ico",
    name = "intense wound cleansing",
    level = 80,
    mana = 200,
    cooldown = 600000,
    emergencyOnly = true,
    estimate = 700
  },
  {
    key = "fair",
    words = "exura med ico",
    name = "fair wound cleansing",
    level = 300,
    mana = 90,
    cooldown = 1000,
    estimate = 450
  },
  {
    key = "wound",
    words = "exura ico",
    name = "wound cleansing",
    level = 8,
    mana = 40,
    cooldown = 1000,
    estimate = math.max(45, player:getLevel() * 1.5 + player:getMagicLevel() * 4)
  }
}

local function inventoryCount(itemId)
  local count = 0
  for _, container in pairs(g_game.getContainers()) do
    for _, item in ipairs(container:getItems()) do
      if item:getId() == itemId then
        count = count + math.max(1, item:getCount())
      end
    end
  end
  return count
end

local function findAvailable(entries)
  for _, entry in ipairs(entries) do
    if player:getLevel() >= entry.level
      and player:getMagicLevel() >= (entry.magicLevel or 0)
      and g_game.findPlayerItem(entry.id, -1) then
      entry.stock = inventoryCount(entry.id)
      return entry
    end
  end
  return nil
end

local function pressureRank(pressure)
  local ranks = {stable = 1, guarded = 2, pressure = 3, high = 4, critical = 5}
  return ranks[pressure] or 1
end

local function resourceNotice(key, details)
  if (resourceState.lastNotice[key] or 0) + 5000 > now then
    return
  end
  resourceState.lastNotice[key] = now
  brainLog("RESOURCE", details)
end

local function beginRestorationLearning(key, before, entry)
  resourceState.pending[key] = {
    time = now,
    before = before,
    peak = before,
    entry = entry
  }
end

local function updateRestorationLearning()
  for key, pending in pairs(resourceState.pending) do
    local current = key == "mana" and player:getMana() or player:getHealth()
    pending.peak = math.max(pending.peak, current)
    if pending.time + 900 <= now then
      local gain = pending.peak - pending.before
      if gain > 0 then
        pending.entry.estimate = math.max(1, pending.entry.estimate * 0.75 + gain * 0.25)
        brainLog("LEARN", string.format(
          "resource=%s source=%s netGain=%d estimate=%.1f",
          key,
          pending.entry.name,
          gain,
          pending.entry.estimate
        ))
      end
      resourceState.pending[key] = nil
    end
  end
end

local function restorationIsEfficient(entry, kind, threshold, pressure)
  local current = kind == "mana" and player:getMana() or player:getHealth()
  local maximum = kind == "mana" and player:getMaxMana() or player:getMaxHealth()
  local percent = maximum > 0 and current * 100 / maximum or 100
  if percent > threshold then
    return false, "above threshold"
  end

  local missing = math.max(0, maximum - current)
  local urgency = pressureRank(pressure)
  local minimumEfficiency = urgency >= 5 and 0.25 or urgency >= 4 and 0.4 or urgency >= 3 and 0.6 or 0.75
  local stock = entry.stock or inventoryCount(entry.id)
  if stock <= 3 and urgency < 4 then
    minimumEfficiency = math.max(minimumEfficiency, 0.95)
  elseif stock <= 10 and urgency < 3 then
    minimumEfficiency = math.max(minimumEfficiency, 0.85)
  end

  local requiredMissing = math.min(maximum, entry.estimate * minimumEfficiency)
  if missing < requiredMissing then
    return false, string.format(
      "waste missing=%d expected=%.0f stock=%d efficiency=%d%%",
      missing,
      entry.estimate,
      stock,
      minimumEfficiency * 100
    )
  end
  return true, string.format(
    "missing=%d expected=%.0f stock=%d efficiency=%d%%",
    missing,
    entry.estimate,
    stock,
    minimumEfficiency * 100
  )
end

local function useRestorationItem(entry, kind)
  if not entry then
    return false
  end

  local lastAttempt = kind == "mana" and lastManaItemAttempt or lastHealthItemAttempt
  if lastAttempt + 1000 > now then
    return false
  end

  local before = kind == "mana" and player:getMana() or player:getHealth()
  TargetBot.useItem(entry.id, 0, player, 900)
  beginRestorationLearning(kind, before, entry)
  if kind == "mana" then
    lastManaItemAttempt = now
    logStats.manaItems = logStats.manaItems + 1
  else
    lastHealthItemAttempt = now
    logStats.healthItems = logStats.healthItems + 1
  end
  brainLog("ITEM", string.format(
    "kind=%s name=%s id=%d stock=%d estimate=%.0f hp=%d%% mp=%d%%",
    kind,
    entry.name,
    entry.id,
    entry.stock or 0,
    entry.estimate,
    player:getHealthPercent(),
    manapercent()
  ))
  setDecision("Using " .. entry.name, combatRow.right:getText())
  return true
end

local function useHealingRune(pressure)
  if lastHealingRuneAttempt + 1000 > now then
    return false
  end
  local rune = findAvailable(healingRunes)
  if not rune then
    return false
  end
  local efficient, reason = restorationIsEfficient(
    rune,
    "health",
    adaptiveThresholds.emergency,
    pressure
  )
  if not efficient then
    resourceNotice("rune-waste", "skip=" .. rune.name .. " reason=" .. reason)
    return false
  end
  local before = player:getHealth()
  TargetBot.useItem(rune.id, 0, player, 1000)
  beginRestorationLearning("health", before, rune)
  lastHealingRuneAttempt = now
  survivalLockUntil = now + 1000
  logStats.healingRunes = logStats.healingRunes + 1
  brainLog("RUNE", string.format(
    "name=%s id=%d stock=%d estimate=%.0f hp=%d%% mp=%d%%",
    rune.name,
    rune.id,
    rune.stock or 0,
    rune.estimate,
    player:getHealthPercent(),
    manapercent()
  ))
  setDecision("Using " .. rune.name, combatRow.right:getText())
  return true
end

local function castHealingSpell(hpPercent, pressure)
  local spell
  for _, candidate in ipairs(healingSpells) do
    local emergencyThreshold = adaptiveThresholds and adaptiveThresholds.emergency or config.emergencyHp
    if (not candidate.emergencyOnly or hpPercent <= emergencyThreshold)
      and player:getLevel() >= candidate.level
      and player:getMana() >= candidate.mana
      and (healingSpellReadyAt[candidate.key] or 0) <= now then
      local missing = player:getMaxHealth() - player:getHealth()
      local urgency = pressureRank(pressure)
      local minimumEfficiency = urgency >= 5 and 0.2 or urgency >= 4 and 0.35 or urgency >= 3 and 0.55 or 0.7
      if missing >= candidate.estimate * minimumEfficiency then
        spell = candidate
        break
      end
      resourceNotice("heal-waste", string.format(
        "skip=%s missing=%d expected=%.0f efficiency=%d%%",
        candidate.words,
        missing,
        candidate.estimate,
        minimumEfficiency * 100
      ))
    end
  end

  if not spell or not TargetBot.saySpell(spell.words, 1000) then
    return false
  end

  local before = player:getHealth()
  healingSpellReadyAt[spell.key] = now + spell.cooldown
  survivalLockUntil = now + 1000
  beginRestorationLearning("health", before, spell)
  logStats.healingSpells = logStats.healingSpells + 1
  brainLog("HEAL", string.format(
    "spell=%s estimate=%.0f hp=%d%% mp=%d%%",
    spell.words,
    spell.estimate,
    player:getHealthPercent(),
    manapercent()
  ))
  setDecision("Casting " .. spell.name, combatRow.right:getText())
  return true
end

KnightCombatBrain.handlesSurvival = function()
  return brainMacro:isOn() and config.survivalAssist and isKnight()
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, math.floor(value + 0.5)))
end

local function updateDamageTelemetry()
  local health = player:getHealth()
  if lastObservedHealth and health < lastObservedHealth then
    table.insert(damageSamples, {
      time = now,
      amount = lastObservedHealth - health
    })
  end
  lastObservedHealth = health

  while damageSamples[1] and damageSamples[1].time + 5000 < now do
    table.remove(damageSamples, 1)
  end

  local totalDamage = 0
  local largestHit = 0
  for _, sample in ipairs(damageSamples) do
    totalDamage = totalDamage + sample.amount
    largestHit = math.max(largestHit, sample.amount)
  end
  return totalDamage, largestHit
end

local function calculateAdaptiveThresholds()
  local totalDamage, largestHit = updateDamageTelemetry()
  local maxHealth = math.max(1, player:getMaxHealth())
  local adjacent = countMonsters(1)
  local nearby = countMonsters(3)
  local damagePercent = totalDamage * 100 / maxHealth
  local largestHitPercent = largestHit * 100 / maxHealth
  local damagePerSecond = totalDamage / 5
  local timeToDeath = damagePerSecond > 0 and player:getHealth() / damagePerSecond or 999
  local risk = damagePercent * 1.15
    + largestHitPercent * 0.8
    + adjacent * 8
    + math.max(0, nearby - adjacent) * 3
  resourceState.huntSamples = resourceState.huntSamples + 1
  local learningRate = resourceState.huntSamples < 100 and 0.05 or 0.015
  resourceState.huntRisk = resourceState.huntRisk
    + (risk - resourceState.huntRisk) * learningRate
  local adaptiveRisk = risk * 0.8 + resourceState.huntRisk * 0.2

  local thresholds = {
    heal = clamp(65 + adaptiveRisk * 0.45, 60, 93),
    item = clamp(35 + adaptiveRisk * 0.5, 30, 80),
    emergency = clamp(23 + adaptiveRisk * 0.55, 20, 75),
    reserve = clamp(25 + adjacent * 4 + damagePercent * 0.35, 25, 65),
    haste = clamp(35 + adjacent * 3 + damagePercent * 0.2, 35, 72),
    mana = 30,
    trainingStart = 98,
    trainingStop = 90,
    pressure = "stable"
  }

  if timeToDeath < 5 then
    thresholds.heal = 93
    thresholds.item = 80
    thresholds.emergency = 75
    thresholds.mana = 50
    thresholds.reserve = 65
    thresholds.haste = 72
    thresholds.pressure = "critical"
  elseif timeToDeath < 9 then
    thresholds.heal = math.max(thresholds.heal, 88)
    thresholds.item = math.max(thresholds.item, 70)
    thresholds.emergency = math.max(thresholds.emergency, 60)
    thresholds.mana = 50
    thresholds.reserve = math.max(thresholds.reserve, 55)
    thresholds.haste = math.max(thresholds.haste, 64)
    thresholds.pressure = "high"
  elseif timeToDeath < 15 or adaptiveRisk >= 35 then
    thresholds.heal = math.max(thresholds.heal, 80)
    thresholds.item = math.max(thresholds.item, 55)
    thresholds.emergency = math.max(thresholds.emergency, 48)
    thresholds.mana = 40
    thresholds.reserve = math.max(thresholds.reserve, 45)
    thresholds.haste = math.max(thresholds.haste, 55)
    thresholds.pressure = "pressure"
  elseif adaptiveRisk >= 15 then
    thresholds.mana = 35
    thresholds.pressure = "guarded"
  end

  thresholds.item = math.min(thresholds.item, thresholds.heal)
  thresholds.emergency = math.min(thresholds.emergency, thresholds.item)
  thresholds.defensive = clamp(math.max(thresholds.emergency + 8, thresholds.item - 5), 35, 85)
  thresholds.damage5 = totalDamage
  thresholds.largestHit = largestHit
  thresholds.adjacent = adjacent
  thresholds.nearby = nearby
  thresholds.timeToDeath = timeToDeath
  thresholds.risk = risk
  thresholds.huntRisk = resourceState.huntRisk

  local overrides = {
    heal = {"manualHealSpellHp", "healSpellHp"},
    item = {"manualHealthItemHp", "healthItemHp"},
    emergency = {"manualEmergencyHp", "emergencyHp"},
    mana = {"manualManaItemMp", "manaItemMp"},
    defensive = {"manualDefensiveHp", "defensiveHp"},
    reserve = {"manualManaReserve", "manaReserve"},
    haste = {"manualHasteMinMp", "hasteMinMp"},
    trainingStart = {"manualTrainingStartMp", "trainingStartMp"},
    trainingStop = {"manualTrainingStopMp", "trainingStopMp"}
  }
  for thresholdKey, override in pairs(overrides) do
    if config[override[1]] then
      thresholds[thresholdKey] = config[override[2]]
    end
  end

  return thresholds
end

KnightCombatBrain.processSurvival = function()
  updateRestorationLearning()
  adaptiveThresholds = calculateAdaptiveThresholds()
  effectiveThresholds = adaptiveThresholds
  percentWidgets.manaReserve:setEffectiveValue(adaptiveThresholds.reserve)
  percentWidgets.defensiveHp:setEffectiveValue(adaptiveThresholds.defensive)
  percentWidgets.healSpellHp:setEffectiveValue(adaptiveThresholds.heal)
  percentWidgets.healthItemHp:setEffectiveValue(adaptiveThresholds.item)
  percentWidgets.emergencyHp:setEffectiveValue(adaptiveThresholds.emergency)
  percentWidgets.manaItemMp:setEffectiveValue(adaptiveThresholds.mana)
  percentWidgets.hasteMinMp:setEffectiveValue(adaptiveThresholds.haste)
  percentWidgets.trainingStartMp:setEffectiveValue(adaptiveThresholds.trainingStart)
  percentWidgets.trainingStopMp:setEffectiveValue(adaptiveThresholds.trainingStop)
  adaptiveRow.right:setText(string.format(
    "H%d I%d E%d M%d %s",
    adaptiveThresholds.heal,
    adaptiveThresholds.item,
    adaptiveThresholds.emergency,
    adaptiveThresholds.mana,
    adaptiveThresholds.pressure
  ))
  if lastSnapshotLog + 10000 <= now then
    lastSnapshotLog = now
    brainLog("SNAPSHOT", string.format(
      "hp=%d%% mp=%d%% damage5=%d largest=%d adjacent=%d nearby=%d ttk=%.1f risk=%.1f huntRisk=%.1f thresholds=H%d/I%d/E%d/M%d/D%d/R%d pressure=%s",
      player:getHealthPercent(),
      manapercent(),
      adaptiveThresholds.damage5,
      adaptiveThresholds.largestHit,
      adaptiveThresholds.adjacent,
      adaptiveThresholds.nearby,
      adaptiveThresholds.timeToDeath,
      adaptiveThresholds.risk,
      adaptiveThresholds.huntRisk,
      adaptiveThresholds.heal,
      adaptiveThresholds.item,
      adaptiveThresholds.emergency,
      adaptiveThresholds.mana,
      adaptiveThresholds.defensive,
      adaptiveThresholds.reserve,
      adaptiveThresholds.pressure
    ))
  end

  if not KnightCombatBrain.handlesSurvival() or isInPz() then
    return false
  end

  local hpPercent = player:getHealthPercent()
  local manaPercent = manapercent()
  local usedHealth = false
  local usedSpell = false
  local usedRune = false
  local pressure = adaptiveThresholds.pressure
  local emergency = hpPercent <= adaptiveThresholds.emergency
  local healthPotion = findAvailable(healthPotions)

  if not resourceState.pending.health then
    if emergency then
      if healthPotion then
        local efficient, reason = restorationIsEfficient(
          healthPotion,
          "health",
          adaptiveThresholds.item,
          pressure
        )
        if efficient then
          usedHealth = useRestorationItem(healthPotion, "health")
        else
          resourceNotice("health-waste", "skip=" .. healthPotion.name .. " reason=" .. reason)
        end
      else
        resourceNotice("health-missing", "no usable health potion found")
      end
      if not usedHealth then
        usedRune = useHealingRune(pressure)
      end
      if not usedHealth and not usedRune then
        usedSpell = castHealingSpell(hpPercent, pressure)
      end
    elseif hpPercent <= adaptiveThresholds.heal then
      usedSpell = castHealingSpell(hpPercent, pressure)
      if not usedSpell and hpPercent <= adaptiveThresholds.item and healthPotion then
        local efficient, reason = restorationIsEfficient(
          healthPotion,
          "health",
          adaptiveThresholds.item,
          pressure
        )
        if efficient then
          usedHealth = useRestorationItem(healthPotion, "health")
        else
          resourceNotice("health-waste", "skip=" .. healthPotion.name .. " reason=" .. reason)
        end
      end
    end
  end

  if emergency then
    survivalLockUntil = math.max(survivalLockUntil, now + 750)
  end

  local usedMana = false
  local inCombat = g_game.getAttackingCreature() ~= nil or isInFight()
  local manaPotion = findAvailable(manaPotions)
  if not resourceState.pending.mana
    and resourceState.manaRearmBelow
    and manaPercent <= resourceState.manaRearmBelow then
    resourceState.manaRearmBelow = nil
  end
  if not resourceState.pending.mana
    and not resourceState.manaRearmBelow
    and manaPercent <= adaptiveThresholds.mana
    and (inCombat or manaPercent <= 15) then
    if manaPotion then
      local efficient, reason = restorationIsEfficient(
        manaPotion,
        "mana",
        adaptiveThresholds.mana,
        pressure
      )
      if efficient then
        usedMana = useRestorationItem(manaPotion, "mana")
        if usedMana then
          resourceState.manaRearmBelow = math.max(5, adaptiveThresholds.mana - 10)
        end
      else
        resourceNotice("mana-waste", "skip=" .. manaPotion.name .. " reason=" .. reason)
      end
    else
      resourceNotice("mana-missing", "no usable mana potion found")
    end
  end

  return usedHealth or usedSpell or usedRune or usedMana
end

local commonFoods = {
  {id = 3731, name = "fire mushroom", seconds = 432},
  {id = 3582, name = "ham", seconds = 360},
  {id = 3726, name = "orange mushroom", seconds = 360},
  {id = 22187, name = "roasted meat", seconds = 300},
  {id = 21146, name = "glooth steak", seconds = 300},
  {id = 3725, name = "brown mushroom", seconds = 264},
  {id = 12310, name = "haunch of boar", seconds = 240},
  {id = 24382, name = "bug meat", seconds = 240},
  {id = 3593, name = "melon", seconds = 240},
  {id = 3580, name = "northern pike", seconds = 204},
  {id = 3577, name = "meat", seconds = 180},
  {id = 3578, name = "fish", seconds = 144},
  {id = 3600, name = "bread", seconds = 120},
  {id = 3607, name = "cheese", seconds = 108},
  {id = 3602, name = "brown bread", seconds = 96}
}

KnightCombatBrain.handlesFood = function()
  return brainMacro:isOn() and config.autoFood and isKnight()
end

KnightCombatBrain.processFood = function()
  if not KnightCombatBrain.handlesFood() or lastFoodAttempt + 1500 > now then
    return false
  end

  local regenerationTime = player:getRegenerationTime()
  if regenerationTime > 180 then
    return false
  end

  local remainingCapacity = math.max(0, 1200 - regenerationTime)
  for _, food in ipairs(commonFoods) do
    local item = g_game.findPlayerItem(food.id, -1)
    if item and food.seconds <= remainingCapacity then
      g_game.use(item)
      lastFoodAttempt = now
      logStats.foods = logStats.foods + 1
      brainLog("FOOD", string.format(
        "name=%s id=%d before=%ds expected=%ds",
        food.name,
        food.id,
        regenerationTime,
        math.min(1200, regenerationTime + food.seconds)
      ))
      setDecision("Eating " .. food.name, combatRow.right:getText())
      return true
    end
  end

  if lastFoodAttempt + 30000 <= now then
    lastFoodAttempt = now
    brainLog("FOOD", string.format(
      "no suitable common food regeneration=%ds capacity=%ds",
      regenerationTime,
      remainingCapacity
    ))
    setDecision("No suitable common food", combatRow.right:getText())
  end
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
  if key == "haste" then
    logStats.haste = logStats.haste + 1
  else
    logStats.trainingSpells = logStats.trainingSpells + 1
  end
  brainLog("UTILITY", string.format(
    "key=%s spell=%s hp=%d%% mp=%d%%",
    key,
    words,
    player:getHealthPercent(),
    manapercent()
  ))
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
    and manaPercent >= (effectiveThresholds.haste or config.hasteMinMp)
    and player:getMana() >= 60 + manaReserve()
    and hasMovementReason()
    and castUtility("utani hur", "haste", 60, 2000, "Auto haste") then
    return true
  end

  if not config.manaTraining or inCombat then
    drainingOverflow = false
    return false
  end

  local trainingStart = effectiveThresholds.trainingStart or config.trainingStartMp
  local trainingStop = effectiveThresholds.trainingStop or config.trainingStopMp
  if manaPercent >= trainingStart then
    drainingOverflow = true
  elseif manaPercent <= trainingStop then
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

  local defensiveThreshold = adaptiveThresholds and adaptiveThresholds.defensive or config.defensiveHp
  if hpPercent <= defensiveThreshold then
    setDecision("Defensive: preserve HP", summary)
    return true
  end

  if manaPercent <= (effectiveThresholds.reserve or config.manaReserve) then
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
