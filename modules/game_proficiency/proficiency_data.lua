if not ProficiencyData then
	ProficiencyData = {}
	ProficiencyData.__index = ProficiencyData

	ProficiencyData.content = {}
end

function ProficiencyData:loadProficiencyJson()
  self.content = {}
  -- Create reverse index: itemName -> ProficiencyId
  self.nameToIdIndex = {}

  local file = "/json/proficiencies.json"
  if not g_resources.fileExists(file) then
    g_logger.error("Hunt config file not found: " .. file)
    return
  end

  local status, result = pcall(function()
    return json.decode(g_resources.readFileContents(file))
  end)

  if not status then
    return g_logger.error("Error while reading characterdata file. Details: " .. result)
  end

  for i, data in pairs(result) do
    local id = data["ProficiencyId"]
    if id then
      self.content[id] = data

      -- Create index by name (normalized)
      if data.Name then
        local normalizedName = data.Name:gsub("%s+", " "):lower()
        if normalizedName:match("^%s*(.-)%s*$") then
          normalizedName = normalizedName:match("^%s*(.-)%s*$")
        end
        self.nameToIdIndex[normalizedName] = id
        -- Also index by exact name
        self.nameToIdIndex[data.Name] = id

        -- Also index by base name (without "1H"/"2H")
        local baseName = normalizedName:gsub("%s*%d+%s*[hH]%s*", " "):gsub("%s+", " ")
        baseName = baseName:match("^%s*(.-)%s*$") or baseName
        if baseName ~= normalizedName and baseName ~= "" then
          self.nameToIdIndex[baseName] = id
        end
      end

      -- Registra arma na Weapon Proficiency UI (apenas entradas com ItemId)
      local itemId = tonumber(data.ItemId or data.ItemID or data.itemId)
      if itemId and itemId > 0 then
        local marketCategory = tonumber(data.MarketCategory or data.marketCategory or 0) or 0

        local WP = modules.game_proficiency and modules.game_proficiency.WeaponProficiency
        if WP and WP.registerServerWeapon then
          WP:registerServerWeapon(itemId, marketCategory)
        else
          g_logger.warning(string.format(
            "Weapon Proficiency: registerServerWeapon não disponível para itemId %d (categoria %d)",
            itemId, marketCategory
          ))
        end
      end
    else
      g_logger.warning("Proficiency sem ProficiencyId, ignorando entrada.")
    end
  end

  print("Weapon Proficiency: Loaded " .. table.size(self.content) .. " proficiency entries, created name index")

  -- Este client não tem g_things.getProficiencyThings, então não chama createItemCache
  -- WeaponProficiency:createItemCache()
  g_logger.warning("WeaponProficiency: cache de itens desativado (sem getProficiencyThings).")
end


function ProficiencyData:isValidProfiencyId(id)
	return self.content[id] ~= nil
end

function ProficiencyData:getContentById(id)
	local content = self.content[id]
	return content and content or nil
end

function ProficiencyData:getPerkLaneCount(id)
	local content = self.content[id]
	if not content then
		return 0
	end

	return table.size(content.Levels)
end

function ProficiencyData:formatFloatValue(value, roundFloat, perkType)
	local function isPercentageType(perkType)
		for _, v in ipairs(PercentageTypes) do
			if v == perkType then
				return true
			end
		end
		return false
	end

	local isInteger = math.floor(value) == value
	if not isInteger or (isInteger and isPercentageType(perkType)) then
		local percentage = value * 100
		if roundFloat then
			local intPart = math.floor(percentage)
			local decimal1 = math.floor(percentage * 10 + 0.5) / 10
			if percentage == intPart then
				return tostring(intPart)
			elseif percentage == decimal1 then
				return string.format("%.1f", percentage)
			else
				return string.format("%.2f", percentage)
			end
		else
			return string.format("%.2f", percentage)
		end
	else
		return tostring(value)
	end
end

function ProficiencyData:getImageSourceAndClip(perkData)
	local perkType = perkData.Type
	local data = PerkVisualData[perkType]
	local source = (data and data.source) or "icons-0"
	local imagePath = string.format("/images/game/proficiency/%s", source)

	if not data then
		return imagePath, "0 0"
	end

	if perkType == PERK_SPELL_AUGMENT then
		local spellData = SpellAugmentIcons[perkData.SpellId]
		return imagePath, spellData.imageOffset 
	end

	if perkType == PERK_BESTIARY_DAMAGE then
		local bestiaryType = BestiaryCategories[perkData.BestiaryName]
		return imagePath, bestiaryType.imageOffset or "0 0"
	end

	if perkType == PERK_MAGIC_BONUS then
		local elementData = MagicBoostMask[perkData.DamageType]
		return imagePath, elementData and elementData.imageOffset or "0 0"
	end

	if ElementalCritical_t[perkType] then
		local elementData = ElementalMask[perkData.ElementId]
		return imagePath, elementData.imageOffset or "0 0"
	end

	if FlatDamageBonus_t[perkType] then
		local skillData = SkillTypes[perkData.SkillId]
		return imagePath, skillData and skillData.imageOffset or "0 0"
	end

	return imagePath, data.offset or "0 0"
end

function ProficiencyData:getBonusNameAndTooltip(perkData)
	local perkType = perkData.Type
	local data = PerkTextData[perkType]
	local value = self:formatFloatValue(perkData.Value, false, perkType)
	local bonusName = data and data.name or "Empty"

	if not data then
		return bonusName, "Empty"
	end

	if perkType == PERK_SPELL_AUGMENT then
		local spellData = SpellAugmentIcons[perkData.SpellId]
		local augmentData = AugmentPerkIcons[perkData.AugmentType]

		value = self:formatFloatValue(perkData.Value, true, perkType)
		if perkData.AugmentType == AUGMENT_COOLDOWN then
			value = value / 100
		end

		local description = string.format(augmentData.desc, value, spellData.name)
		return bonusName, description
	end

	if perkType == PERK_BESTIARY_DAMAGE then
		local description = string.format(data.desc, value, perkData.BestiaryName)
		return bonusName, description
	end

	if perkType == PERK_MAGIC_BONUS then
		local elementData = MagicBoostMask[perkData.DamageType]
		local description = string.format(data.desc, value, elementData.name)
		return bonusName, description
	end

	if perkType == PERK_PERFECT_SHOT then
		local description = string.format(data.desc, value, perkData.Range)
		return bonusName, description
	end

	if ElementalCritical_t[perkType] then
		local elementData = ElementalMask[perkData.ElementId]
		local description = string.format(data.desc, value, elementData.name)
		return bonusName, description
	end

	if FlatDamageBonus_t[perkType] then
		local skillData = SkillTypes[perkData.SkillId]
		local description = string.format(data.desc, value, skillData.name)
		return bonusName, description
	end
	return bonusName, string.format(data.desc, value)
end

function ProficiencyData:getAugmentIconClip(perkData)
	local augmentData = AugmentPerkIcons[perkData.AugmentType]
	if not augmentData then
		g_logger.warning(string.format("Missing augmentId %d data", perkData.AugmentType))
		return "0 0"
	end
	return augmentData.imageOffset
end

function ProficiencyData:getCurrentCeilExperience(exp, displayItem, proficiencyId)
	local best = nil
	local vocation = self:getWeaponProfessionType(displayItem)
	local lastExp = nil
	local profId = proficiencyId or 0
	if displayItem then
		local success, result = pcall(function()
			local thingType = displayItem:getThingType()
			if thingType then
				return thingType:getProficiencyId()
			end
			return 0
		end)
		if success and result then
			profId = result
		end
	end
	local limitIndex = self:getPerkLaneCount(profId) + 2

	for index, stage in ipairs(ExperienceTable) do
		if index > limitIndex then
			break
		end

		local stageExp = stage[vocation]
		if stageExp then
			if stageExp > exp then
				if not best or stageExp < best then
					best = stageExp
				end
			end
			lastExp = stageExp
		end
	end

	return best or lastExp
end

function ProficiencyData:getMaxExperience(perkCount, displayItem)
	local vocation = self:getWeaponProfessionType(displayItem)
	local lastLevel = ExperienceTable[perkCount + 2]
	return lastLevel[vocation] or 0
end

function ProficiencyData:getLevelPercent(currentExperience, level, displayItem)
	local vocation = self:getWeaponProfessionType(displayItem)
	local prevLevel = math.max(level - 1, 0)
	
	-- Get xpMin safely
	local xpMin = 0
	if prevLevel > 0 then
		local prevLevelData = ExperienceTable[prevLevel]
		if prevLevelData and prevLevelData[vocation] then
			xpMin = prevLevelData[vocation]
		end
	end
	
	-- Get xpMax safely
	local xpMax = xpMin + 1
	local levelData = ExperienceTable[level]
	if levelData and levelData[vocation] then
		xpMax = levelData[vocation]
	end

	-- Prevent division by zero
	if xpMax <= xpMin then
		return 0
	end

	local progress = math.max(0, math.min(1, (currentExperience - xpMin) / (xpMax - xpMin)))
	return math.floor(progress * 100)
end

function ProficiencyData:getTotalPercent(currentExperience, perkCount, displayItem)
	-- If no experience gained yet, return 0%
	if not currentExperience or currentExperience == 0 then
		return 0
	end
	
	local vocation = self:getWeaponProfessionType(displayItem)
	local maxExperience = ExperienceTable[perkCount + 2][vocation] or 1
	
	-- Prevent division by zero
	if maxExperience <= 0 then
		return 0
	end
	
	local progress = math.max(0, math.min(1, currentExperience / maxExperience))
	return math.floor(progress * 100)
end

function ProficiencyData:getMaxExperienceByLevel(level, displayItem)
	local vocation = self:getWeaponProfessionType(displayItem)
	return ExperienceTable[level][vocation] or 0
end

function ProficiencyData:getCurrentLevelByExp(displayItem, currentExperience, includeMastery)
	local vocation = self:getWeaponProfessionType(displayItem)
	local currentLevel = 0

	for level, data in pairs(ExperienceTable) do
		local requiredExp = data[vocation]
		if requiredExp and currentExperience >= requiredExp then
			if level > currentLevel then
				currentLevel = level
			end
		end
	end

	local level = math.min(7, currentLevel)
	if includeMastery then
		level = currentLevel
	end

	return level
end

function ProficiencyData:getWeaponProfessionType(displayItem)
	if not displayItem then
		return "regular" -- Default fallback
	end
	
	local marketData = displayItem:getMarketData()
	if not marketData then
		return "regular" -- Default fallback
	end

	-- Check if restrictVocation is a valid table
	if type(marketData.restrictVocation) == "table" then
		for _, vocationId in pairs(marketData.restrictVocation) do
			if vocationId == 1 then
				return "knight"
			end
		end
	end

	-- Check weapon type for crossbow (need to get it from ThingType)
	local weaponType = nil
	local success, result = pcall(function()
		local thingType = displayItem:getThingType()
		if thingType then
			return thingType:getWeaponType()
		end
		return nil
	end)
	if success and result then
		weaponType = result
	end
	
	if weaponType == WEAPON_CROSSBOW then
		return "crossbow"
	end
	
	-- Default to regular (always return a valid ExperienceTable key)
	return "regular"
end
