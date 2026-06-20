setDefaultTab("Knight")

local defaults = {
  profile = "Balanced",
  manaReserve = 35,
  defensiveHp = 45,
  protectPlayers = true
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

local playerSafetyButton
local function updatePlayerSafetyButton()
  playerSafetyButton:setText("Area near players: " .. (config.protectPlayers and "blocked" or "allowed"))
end

playerSafetyButton = UI.Button("", function()
  config.protectPlayers = not config.protectPlayers
  updatePlayerSafetyButton()
end)
updatePlayerSafetyButton()

UI.Separator()
UI.Label("Disable TargetBot attack spells while this is active.")

local brainMacro = macro(500, "Knight Combat Brain", function()
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
