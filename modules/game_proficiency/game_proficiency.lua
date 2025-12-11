dofile('const.lua')

-- FIX SANGUINE BOW - Crystal 15.x
local WEAPON_PROFICIENCY_FIX = {
  [43877] = {
    name = "sanguine bow",
    weaponType = WEAPON_BOW
  }
}

if not WeaponProficiency then
    WeaponProficiency = {}
    WeaponProficiency.__index = WeaponProficiency

    WeaponProficiency.window           = nil
    WeaponProficiency.warningWindow    = nil
    WeaponProficiency.displayItemPanel = nil
    WeaponProficiency.perkPanel        = nil
    WeaponProficiency.bonusDetailPanel = nil
    WeaponProficiency.starProgressPanel = nil
    WeaponProficiency.optionFilter     = nil
    WeaponProficiency.itemListScroll   = nil
    WeaponProficiency.vocationWarning  = nil
    WeaponProficiency.mainButton       = nil
    WeaponProficiency.topMenuButton    = nil

    WeaponProficiency.itemList  = WeaponProficiency.itemList or {}
    WeaponProficiency.cacheList = WeaponProficiency.cacheList or {} -- [itemId] = {experience, perks}

    WeaponProficiency.allProficiencyRequested = false
    WeaponProficiency.firstItemRequested      = nil

    WeaponProficiency.saveWeaponMissing = false

    -- usa as constantes de MarketCategory/WeaponStringToCategory
    WeaponProficiency.ItemCategory = {
        Axes            = 17,
        Clubs           = 18,
        DistanceWeapons = 19,
        Swords          = 20,
        WandsRods       = 21,
        FistWeapons     = 27,
        WeaponsAll      = 32,
    }


    WeaponProficiency.perkPanelsName = {
        "oneBonusIconPanel", "twoBonusIconPanel",
        "threeBonusIconPanel"
    }
    WeaponProficiency.filters = {
        ["levelButton"] = false,
        ["vocButton"]   = false,
        ["oneButton"]   = false,
        ["twoButton"]   = false,
    }

	-- Scrollable settings
	WeaponProficiency.listWidgetHeight = 34 -- 34x34
	WeaponProficiency.listCapacity = 0
	WeaponProficiency.listMinWidgets = 0
	WeaponProficiency.listMaxWidgets = 0
	WeaponProficiency.offset = 0
	WeaponProficiency.listPool = {}
	WeaponProficiency.listData = {}
end
local function safeGetThingType(item)
  if not item then
    return nil
  end

  local itemId = item:getId()

  -- Fix manual para sanguine bow
  if WEAPON_PROFICIENCY_FIX[itemId] then
    print("Weapon Proficiency: Sanguine Bow FIX ativado para itemId", itemId)
    return WEAPON_PROFICIENCY_FIX[itemId]
  end

  -- Caminho normal (usa thingType do client)
  local ok, thingType = pcall(function()
    return item:getThingType()
  end)

  if ok and thingType then
    return thingType
  end

  return nil
end

function WeaponProficiency:buildItemList()
    print("Weapon Proficiency: buildItemList() (weaponType scan) called")

    self.itemList = self.itemList or {}

    for _, cat in pairs(self.ItemCategory) do
        self.itemList[cat] = {}
    end
    self.itemList[self.ItemCategory.WeaponsAll] = {}

    local totalWeapons = 0
    local minId, maxId = 100, 30000

    for id = minId, maxId do
        local okItem, item = pcall(Item.create, id)
        if okItem and item and item:getId() ~= 0 then
            local okType, thingType = pcall(item.getThingType, item)
            if okType and thingType then
                local okW, weaponType = pcall(thingType.getWeaponType, thingType)
                if okW and weaponType and weaponType ~= WEAPON_NONE then
                    local cat = UnknownCategories[weaponType]
                    if cat then
                        local okMD, marketData = pcall(thingType.getMarketData, thingType)
                        local entry = {
                            displayItem = item,
                            marketData  = okMD and marketData or { name = "", showAs = id },
                        }

                        self.itemList[cat] = self.itemList[cat] or {}
                        table.insert(self.itemList[cat], entry)
                        table.insert(self.itemList[self.ItemCategory.WeaponsAll], entry)
                        totalWeapons = totalWeapons + 1
                    end
                end
            end
        end
    end

    print(string.format("Weapon Proficiency: buildItemList() - encontrados %d itens de arma via weaponType", totalWeapons))
end
function WeaponProficiency:registerServerWeapon(itemId, marketCategory)
  self.itemList = self.itemList or {}

  for _, cat in pairs(self.ItemCategory) do
    self.itemList[cat] = self.itemList[cat] or {}
  end
  self.itemList[self.ItemCategory.WeaponsAll] =
    self.itemList[self.ItemCategory.WeaponsAll] or {}

  if not marketCategory or marketCategory == 0 then
    print("Weapon Proficiency: WARNING - server sent marketCategory 0 for itemId " .. itemId)
    return
  end

  -- evita duplicados
  for _, entry in ipairs(self.itemList[marketCategory]) do
    if entry.marketData and entry.marketData.showAs == itemId then
      return
    end
  end

  -- cria displayItem só para mostrar ícone
  local okItem, item = pcall(Item.create, itemId)
  if not okItem or not item or item:getId() == 0 then
    print("Weapon Proficiency: WARNING - could not create item for itemId " .. itemId)
    return
  end

  -- pega thingType via g_things (API deste client)
  local thingType = g_things.getThingType(itemId)
  if not thingType then
    print("Weapon Proficiency: WARNING - could not get thingType for itemId " .. itemId)
    return
  end

  local okMD, marketData = pcall(function()
    return thingType:getMarketData()
  end)
  if not okMD or not marketData then
    marketData = { name = "", showAs = itemId, category = marketCategory }
  end

  local entry = {
    displayItem = item,
    marketData  = marketData
  }

  table.insert(self.itemList[marketCategory], entry)
  table.insert(self.itemList[self.ItemCategory.WeaponsAll], entry)

  print(string.format(
    "Weapon Proficiency: registered server weapon itemId=%d, cat=%d",
    itemId, marketCategory
  ))
end


-- Helper function to get equipped weapon (checks Left slot first, then Right slot)
-- This matches server behavior: getWeapon(true) checks LEFT first, then RIGHT
local function getEquippedWeapon(player)
	if not player then
		return nil
	end
	
	-- Try Left slot first (most weapons go here)
	local success, weapon = pcall(function()
		return player:getInventoryItem(InventorySlotLeft)
	end)
	if success and weapon and weapon ~= nil then
		-- Check if it's actually a weapon (not a shield or other item)
		local success2, thingType = pcall(function()
			return weapon:getThingType()
		end)
		if success2 and thingType then
			local success3, weaponType = pcall(function()
				return thingType:getWeaponType()
			end)
			if success3 and weaponType then
				-- If it's a weapon (not shield), return it
				if weaponType ~= WEAPON_SHIELD then
					return weapon
				end
			else
				-- If we can't determine weapon type, assume it's a weapon if it's in left slot
				return weapon
			end
		else
			-- If we can't get thingType, assume it's a weapon if it's in left slot
			return weapon
		end
	end
	
	-- Try Right slot (for 2-handed weapons or if left slot has shield)
	success, weapon = pcall(function()
		return player:getInventoryItem(InventorySlotRight)
	end)
	if success and weapon and weapon ~= nil then
		local success2, thingType = pcall(function()
			return weapon:getThingType()
		end)
		if success2 and thingType then
			local success3, weaponType = pcall(function()
				return thingType:getWeaponType()
			end)
			if success3 and weaponType then
				-- If it's a weapon (not shield), return it
				if weaponType ~= WEAPON_SHIELD then
					return weapon
				end
			else
				-- If we can't determine weapon type, assume it's a weapon if it's in right slot
				return weapon
			end
		else
			-- If we can't get thingType, assume it's a weapon if it's in right slot
			return weapon
		end
	end
	
	return nil
end

function init()
    local success, window = pcall(function()
        return g_ui.displayUI('weapon_proficiency')
    end)

    if not success or not window then
        print("Weapon Proficiency: ERROR - Failed to load UI, module will not function properly")
        return
    end
   

    WeaponProficiency.window            = window
    WeaponProficiency.displayItemPanel  = window:recursiveGetChildById("itemPanel")
	print("Weapon Proficiency: Window successfully initialized:", WeaponProficiency.window)
    WeaponProficiency.perkPanel         = window:recursiveGetChildById("bonusProgressBackground")
    WeaponProficiency.bonusDetailPanel  = window:recursiveGetChildById("bonusDetailBackground")
    WeaponProficiency.optionFilter      = window:recursiveGetChildById("classFilter")
    WeaponProficiency.starProgressPanel = window:recursiveGetChildById("starsPanelBackground")
    WeaponProficiency.itemListScroll    = window:recursiveGetChildById("itemListScroll")
    WeaponProficiency.vocationWarning   = window:recursiveGetChildById("vocationWarning")
    window:hide()
  -- NOVO: pré-carrega todas as armas usando weaponType scan
       WeaponProficiency:buildItemList()
    -- inicializa listas vazias (stub, sem getProficiencyThings)
    if WeaponProficiency.createItemCache then
        WeaponProficiency:createItemCache()
    end

    -- CRITICAL: callbacks diretos em g_game
    g_game.onWeaponProficiency       = onWeaponProficiency
    g_game.onProficiencyNotification = onProficiencyNotification
    print("Weapon Proficiency: Callbacks registered DIRECTLY on g_game (before connect)")

    -- e também via connect
    connect(g_game, {
        onInspection            = onInspection,
        onGameStart             = onGameStart,
        onGameEnd               = onGameEnd,
        onWeaponProficiency     = onWeaponProficiency,
        onProficiencyNotification = onProficiencyNotification
    })
    print("Weapon Proficiency: Callbacks also registered via connect()")

        -- aqui só carrega o JSON quando o .dat carregar
    connect(g_things, { onLoadDat = loadProficiencyJson })


    connect(LocalPlayer, { onInventoryChange = onInventoryChange })

    -- comando de debug
    _G.wpdebug = function()
        print("=== Weapon Proficiency Debug ===")
        print("Module loaded: " .. tostring(modules.game_proficiency ~= nil))
        if modules.game_proficiency then
            print("Main button exists: " .. tostring(WeaponProficiency.mainButton ~= nil))
            print("Top menu button exists: " .. tostring(WeaponProficiency.topMenuButton ~= nil))
            if WeaponProficiency.mainButton then
                print("Main button visible: " .. tostring(WeaponProficiency.mainButton:isVisible()))
                print("Main button ID: " .. tostring(WeaponProficiency.mainButton:getId()))
            end
            if WeaponProficiency.topMenuButton then
                print("Top menu button visible: " .. tostring(WeaponProficiency.topMenuButton:isVisible()))
            end
            print("game_mainpanel available: " .. tostring(modules.game_mainpanel ~= nil))
            print("client_topmenu available: " .. tostring(modules.client_topmenu ~= nil))
        else
            print("ERROR: Module game_proficiency is NOT loaded!")
            local module = g_modules.getModule("game_proficiency")
            if module then
                print("Module exists but not loaded. Is enabled: " .. tostring(module:isEnabled()))
                print("Is loaded: " .. tostring(module:isLoaded()))
            else
                print("Module does not exist in module manager!")
            end
        end
        print("================================")
    end

    -- limpar cache de experiência
    _G.wpclearcache = function()
        if WeaponProficiency then
            local cacheSize = table.size(WeaponProficiency.cacheList or {})
            WeaponProficiency.cacheList = {}
            print("Weapon Proficiency: Cache cleared! (was " .. cacheSize .. " entries)")
            print("All experience data has been removed from cache.")
            print("The UI will now request fresh data from server when opened.")
        else
            print("Weapon Proficiency module not loaded!")
        end
    end

    -- cria botões depois que outros módulos carregarem
    scheduleEvent(function()
        createProficiencyButtons()
    end, 200)
end

function createProficiencyButtons()
  if not WeaponProficiency.mainButton then
    if modules.game_mainpanel and modules.game_mainpanel.addToggleButton then
      WeaponProficiency.mainButton = modules.game_mainpanel.addToggleButton(
        'weaponProficiencyButton',
        tr('Weapon Proficiency'),
        '/images/topbuttons/weaponProficiency',
        function()
          WeaponProficiency.toggle()
        end,
        false, 1
      )
      if WeaponProficiency.mainButton then
        WeaponProficiency.mainButton:setOn(false)
        print("Weapon Proficiency: Main panel button created successfully")
      else
        print("Weapon Proficiency: Failed to create main panel button")
      end
    else
      print("Weapon Proficiency: game_mainpanel not available")
    end
  end
end

function terminate()
	disconnect(g_game, {
		onInspection = onInspection,
		onGameStart = onGameStart,
		onGameEnd = onGameEnd,
		onWeaponProficiency = onWeaponProficiency,
		onProficiencyNotification = onProficiencyNotification
	})
	disconnect(g_things, { onLoadDat = loadProficiencyJson })
	disconnect(LocalPlayer, { onInventoryChange = onInventoryChange })
	
	-- Remove menu hook
	if modules.game_interface then
		modules.game_interface.removeMenuHook('item', 'Weapon Proficiency')
	end
	
	-- Clean up buttons
	if WeaponProficiency.mainButton then
		WeaponProficiency.mainButton = nil
	end
	if WeaponProficiency.topMenuButton then
		WeaponProficiency.topMenuButton = nil
	end
end

function onGameStart()
	print("Weapon Proficiency: ===== onGameStart CALLED =====")
	WeaponProficiency.allProficiencyRequested = false
	WeaponProficiency.saveWeaponMissing = false
	WeaponProficiency.firstItemRequested = nil
	
	-- Ensure cacheList exists
	if not WeaponProficiency.cacheList then
		WeaponProficiency.cacheList = {}
		print("Weapon Proficiency: Created cacheList in onGameStart")
	else
		print("Weapon Proficiency: cacheList already exists in onGameStart, size: " .. table.size(WeaponProficiency.cacheList))
	end
	
	-- Verify callback is registered
	if g_game.onWeaponProficiency then
		print("Weapon Proficiency: onWeaponProficiency callback is registered")
	else
		print("Weapon Proficiency: ERROR - onWeaponProficiency callback is NOT registered!")
		-- Try to register it again
		g_game.onWeaponProficiency = onWeaponProficiency
		print("Weapon Proficiency: Re-registered onWeaponProficiency callback")
	end
	
	-- Request all proficiency data from server after a short delay
	-- This ensures the module is fully initialized and the callback is available
	-- We do this because the automatic send during login might arrive before the module is ready
	scheduleEvent(function()
		print("Weapon Proficiency: Requesting all proficiency data from server (delayed request after login)")
		g_game.sendWeaponProficiencyAction(1) -- Request all weapons (action 1 = WEAPON_PROFICIENCY_LIST_INFO)
		WeaponProficiency.allProficiencyRequested = true
	end, 1000) -- 1 second delay to ensure module is ready
	print("Weapon Proficiency: ===== onGameStart COMPLETED =====")
	
	
	
	-- Load proficiency data if DAT is already loaded
	-- NOTE: We do NOT request proficiency data here on game start
	-- Data will be requested when:
	-- 1. User opens Weapon Proficiency UI (toggle function)
	-- 2. User selects a specific weapon (onItemListFocusChange)
	-- This ensures we always get fresh data from server database
	if g_things.isDatLoaded() then
		loadProficiencyJson()
	end
	
	-- Initialize UI elements when game starts
	setupUIElements()
	
	-- NOTE: We do NOT request proficiency data here on game start
	-- Data will be requested when:
	-- 1. User opens Weapon Proficiency UI (toggle function)
	-- 2. User selects a specific weapon (onItemListFocusChange)
	-- This ensures we always get fresh data from server database
end

function setupUIElements()
	-- Add menu hook for weapon proficiency option
	if modules.game_interface and modules.game_interface.addMenuHook then
		modules.game_interface.addMenuHook('item', 'Weapon Proficiency', function(menuPosition, lookThing, useThing, creatureThing)
			if useThing and isWeaponWithProficiency(useThing) then
				requestOpenWindow(useThing)
			end
		end, function(menuPosition, lookThing, useThing, creatureThing)
			-- Safely check if useThing is valid and is a weapon with proficiency
			if not useThing then
				return false
			end
			local success, result = pcall(function()
				return isWeaponWithProficiency(useThing)
			end)
			return success and result == true
		end, '(Ctrl)')
	end
	
	-- Button should already be created in init(), no need to create again
end

function onGameEnd()
	WeaponProficiency.window:hide()
	WeaponProficiency:reset()

	if WeaponProficiency.warningWindow then
		WeaponProficiency:destroy()
		WeaponProficiency.warningWindow = nil
	end
	g_client.setInputLockWidget(nil)
end

function loadProficiencyJson()
    ProficiencyData:loadProficiencyJson()
    -- Este client não usa createItemCache porque não há g_things.getProficiencyThings
    -- WeaponProficiency:createItemCache()
end


function show()
	if not WeaponProficiency.window then
		print("Weapon Proficiency: ERROR - Window not initialized! Cannot show UI.")
		return
	end
	
	WeaponProficiency.window:show(true)
	WeaponProficiency.window:raise()
	WeaponProficiency.window:focus()
	if WeaponProficiency.mainButton then
		WeaponProficiency.mainButton:setOn(true)
	end
	if WeaponProficiency.topMenuButton then
		WeaponProficiency.topMenuButton:setOn(true)
	end
end

function hide()
	WeaponProficiency.window:hide()
	if WeaponProficiency.mainButton then
		WeaponProficiency.mainButton:setOn(false)
	end
	if WeaponProficiency.topMenuButton then
		WeaponProficiency.topMenuButton:setOn(false)
	end
end

function getUnknownMarketCategory(item)
	if not item then
		return 0
	end
	
	-- Safely get thing type from item
	local success, thingType = pcall(function()
		return item:getThingType()
	end)
	if not success or not thingType then
		return 0
	end
	
	-- Safely get weapon type from thing type
	local success2, weaponType = pcall(function()
		return thingType:getWeaponType()
	end)
	if not success2 or not weaponType then
		return 0
	end
	
	local category = UnknownCategories[weaponType]
	return category or 0
end

function isWeaponWithProficiency(thing)
	if not thing then
		return false
	end
	
	-- Check if it's an item
	if not thing.isItem or not thing:isItem() then
		return false
	end
	
	-- Safely get thing type
	local thingType = nil
	local success, result = pcall(function()
		return thing:getThingType()
	end)
	if success and result then
		thingType = result
	else
		return false
	end
	
	if not thingType then
		return false
	end
	
	-- Check if it's in the proficiency things list (most reliable method)
	local proficiencyThings = g_things.getProficiencyThings()
	if proficiencyThings then
		for _, profType in pairs(proficiencyThings) do
			if profType:getId() == thing:getId() then
				return true
			end
		end
	end
	
	-- Fallback: check market category for weapon categories
	local marketData = thingType:getMarketData()
	if marketData and not table.empty(marketData) then
		local category = marketData.category
		-- Check standard weapon categories
		if category == MarketCategory.Axes or 
		   category == MarketCategory.Clubs or 
		   category == MarketCategory.DistanceWeapons or
		   category == MarketCategory.Swords or 
		   category == MarketCategory.WandsRods then
			return true
		end
		-- Check for FistWeapons (category 27) - may not be in MarketCategory enum
		if category == 27 then
			return true
		end
	end
	
	return false
end

function WeaponProficiency.toggle()
  if not WeaponProficiency.window then
    print("Weapon Proficiency: ERROR - Window not initialized!")
    return
  end

  if WeaponProficiency.window:isVisible() then
    hide()
  else
    -- sempre pede lista completa ao abrir
    WeaponProficiency.allProficiencyRequested = false
    g_game.sendWeaponProficiencyAction(1) -- WEAPON_PROFICIENCY_LIST_INFO
    WeaponProficiency.allProficiencyRequested = true
    WeaponProficiency.requestOpenWindow()
  end
end


-- Terminal command to open Weapon Proficiency UI (global function)
if not _G.weaponproficiency then
	_G.weaponproficiency = function()
		if modules.game_proficiency then
			modules.game_proficiency.toggle()
		else
			print("Weapon Proficiency module not loaded!")
		end
	end
end

-- Short alias for terminal command (global function)
if not _G.wp then
	_G.wp = function()
		_G.weaponproficiency()
	end
end

-- Debug command to check button status (register immediately, even if module not loaded)
_G.wpdebug = function()
	print("=== Weapon Proficiency Debug ===")
	print("Module loaded: " .. tostring(modules.game_proficiency ~= nil))
	if modules.game_proficiency then
		print("Main button exists: " .. tostring(WeaponProficiency.mainButton ~= nil))
		print("Top menu button exists: " .. tostring(WeaponProficiency.topMenuButton ~= nil))
		if WeaponProficiency.mainButton then
			print("Main button visible: " .. tostring(WeaponProficiency.mainButton:isVisible()))
			print("Main button ID: " .. tostring(WeaponProficiency.mainButton:getId()))
		end
		if WeaponProficiency.topMenuButton then
			print("Top menu button visible: " .. tostring(WeaponProficiency.topMenuButton:isVisible()))
		end
		print("game_mainpanel available: " .. tostring(modules.game_mainpanel ~= nil))
		print("client_topmenu available: " .. tostring(modules.client_topmenu ~= nil))
	else
		print("ERROR: Module game_proficiency is NOT loaded!")
		print("Checking if module exists...")
		local module = g_modules.getModule("game_proficiency")
		if module then
			print("Module exists but not loaded. Is enabled: " .. tostring(module:isEnabled()))
			print("Is loaded: " .. tostring(module:isLoaded()))
		else
			print("Module does not exist in module manager!")
		end
	end
	print("================================")
end

function sortWeaponProficiency(marketCategory)
	local itemList = WeaponProficiency.itemList[marketCategory]
	if not itemList then return end

	table.sort(itemList, function(a, b)
		local idA, idB = a.marketData.showAs, b.marketData.showAs

		local expA = WeaponProficiency.cacheList[idA] and WeaponProficiency.cacheList[idA].exp or 0
		local expB = WeaponProficiency.cacheList[idB] and WeaponProficiency.cacheList[idB].exp or 0

		if expA == expB then
			return a.marketData.name:lower() < b.marketData.name:lower()
		end
		return expA > expB
	end)
end

function WeaponProficiency:requestOpenWindow(redirectItem)
    if not WeaponProficiency.window then
        print("Weapon Proficiency: ERROR - Window not initialized! Cannot open UI.")
        return
    end

    -- Sempre pede lista completa pro servidor
    WeaponProficiency.allProficiencyRequested = false
    g_game.sendWeaponProficiencyAction(1) -- WEAPON_PROFICIENCY_LIST_INFO
    WeaponProficiency.allProficiencyRequested = true
    WeaponProficiency.firstItemRequested = redirectItem

    local category = "Weapons: All"
    local targetItemId = nil

    -- Se veio redirectItem, só usa o ID dele
    if redirectItem then
        targetItemId = redirectItem:getId()
    end

    local focusFirstChild = true
    local focusVocation = false

    WeaponProficiency.filters["vocButton"] = focusVocation
    local vocButton = WeaponProficiency.window:recursiveGetChildById("vocButton")
    if vocButton then
        vocButton:setChecked(focusVocation, true)
    end

    WeaponProficiency:onClearSearch(true)
    WeaponProficiency:onWeaponCategoryChange(category, nil, targetItemId, focusFirstChild)

    print("Weapon Proficiency: Calling show()...")
    show()
    print("Weapon Proficiency: show() completed, window should be visible now")
end


function onInspection(inspectType, itemName, item, descriptions)
	if inspectType ~= 2 then
		return
	end

	-- Only update tooltip if window is already open
	-- Don't auto-open the window, user must click button or menu option
	if not WeaponProficiency.window:isVisible() then
		return
	end

	local infoWidget = WeaponProficiency.window:recursiveGetChildById("infoWidget")
	if infoWidget then
	local text = itemName
	for _, data in pairs(descriptions) do
		text = text .. string.format("\n%s: %s", data.detail, wrapTextByWords(data.description, 52))
		end
		infoWidget:setTooltip(text)
	end
end

function updateTopBarProficiency(itemId, hasUnusedPerk)
	-- Check if this is the currently equipped weapon
	local player = g_game.getLocalPlayer()
	if not player then return end

	local weapon = getEquippedWeapon(player)
	
	if weapon and weapon:getId() == itemId then
		local itemCache = WeaponProficiency.cacheList[itemId]
		if itemCache then
			if modules.game_proficiency_topbar and modules.game_proficiency_topbar.ProficiencyTopBar then
				modules.game_proficiency_topbar.ProficiencyTopBar.updateProficiencyBar(itemId, itemCache.exp, hasUnusedPerk or false)
			end
		end
	end
end

function onInventoryChange(player, slot, item, oldItem)
  -- Check if weapon slot changed (Left or Right)
  -- Only process valid slots to avoid "invalid slot" errors
  if slot == InventorySlotLeft or slot == InventorySlotRight then
    -- Let the topbar module handle inventory changes
    -- It will check for proficiency and update itself
    if modules.game_proficiency_topbar and modules.game_proficiency_topbar.ProficiencyTopBar then
      modules.game_proficiency_topbar.ProficiencyTopBar.checkEquippedWeapon()
    end

    -- Handle weapon equipped - WORKS FOR ALL WEAPONS
    if item then
      local itemId = item:getId()
      print("Weapon Proficiency: onInventoryChange - Item equipped in slot " .. slot .. ", itemId: " .. itemId)

      -- Usa safeGetThingType (com fix do sanguine bow)
      local thingType = safeGetThingType(item)

      if thingType then
        local weaponType

        -- Caso do FIX: vem como tabela simples com weaponType setado
        if thingType.weaponType then
          weaponType = thingType.weaponType
        else
          local success2, wt = pcall(function()
            return thingType:getWeaponType()
          end)
          if success2 then
            weaponType = wt
          end
        end

        if weaponType and weaponType ~= WEAPON_SHIELD then
          -- IMPORTANT: Always request fresh data from server database when equipping ANY weapon
          print("Weapon Proficiency: Weapon equipped (itemId: " .. itemId .. ", weaponType: " .. weaponType .. ") - requesting fresh data from server database")
          g_game.sendWeaponProficiencyAction(0, itemId) -- 0 = WEAPON_PROFICIENCY_ITEM_INFO

          -- UI will update automatically when server responds via onWeaponProficiency callback
          if WeaponProficiency.window and WeaponProficiency.window:isVisible() then
            local itemWidget = WeaponProficiency.displayItemPanel and WeaponProficiency.displayItemPanel:getChildById("item")
            if itemWidget then
              local currentItem = itemWidget:getItem()
              if currentItem and currentItem:getId() == itemId then
                print("Weapon Proficiency: UI is showing equipped weapon " .. itemId .. " - will update automatically when server responds")
              end
            end
          end
        else
          print("Weapon Proficiency: Item " .. itemId .. " is not a weapon (weaponType: " .. (weaponType or "nil") .. ") - skipping proficiency update")
        end
      else
        print("Weapon Proficiency: Could not get thingType for item " .. itemId .. " - skipping proficiency update (after safeGetThingType)")
      end

    elseif oldItem then
      -- Weapon was unequipped - WORKS FOR ALL WEAPONS
      local oldItemId = oldItem:getId()
      print("Weapon Proficiency: onInventoryChange - Weapon unequipped from slot " .. slot .. ", itemId: " .. oldItemId)

      -- If UI is open and showing this weapon, request fresh data from server
      if WeaponProficiency.window and WeaponProficiency.window:isVisible() then
        local itemWidget = WeaponProficiency.displayItemPanel and WeaponProficiency.displayItemPanel:getChildById("item")
        if itemWidget then
          local currentItem = itemWidget:getItem()
          if currentItem and currentItem:getId() == oldItemId then
            print("Weapon Proficiency: UI is showing unequipped weapon " .. oldItemId .. " - requesting fresh data from server database")
            g_game.sendWeaponProficiencyAction(0, oldItemId) -- Request fresh data from server
          end
        end
      end
    end
  end
end

---------------------------
----- Local Functions -----
---------------------------
local function canChangeWeaponPerks()
	local player = g_game.getLocalPlayer()
	if not player or not g_game.isOnline() then
		return false
	end
	
	-- Check if player is in protection zone by checking the tile
	-- Note: hasFlag is only available in editor mode, so for now allow changing perks anywhere
	-- TODO: Implement proper protection zone check when tile flags are exposed to Lua
	local pos = player:getPosition()
	if not pos then
		return false
	end
	
	local tile = g_map.getTile(pos)
	if not tile then
		return false
	end
	
	-- For now, allow changing perks anywhere (return true)
	-- In the future, we could check tile flags if they become available in Lua
	return true
end

local function isMasteryAchieved(targetItem)
	if not targetItem then
		return false
	end
	
	-- Check if targetItem is a valid Item
	if not targetItem.getId or not targetItem:getId() then
		return false
	end
	
	-- Get proficiency ID from thing type
	local thingType = nil
	local success, result = pcall(function()
		return targetItem:getThingType()
	end)
	if success and result then
		thingType = result
	else
		return false
	end
	
	if not thingType then
		return false
	end
	
	local proficiencyId = thingType:getProficiencyId()
	local maxExperience = ProficiencyData:getMaxExperience(ProficiencyData:getPerkLaneCount(proficiencyId), targetItem)
	local weaponEntry = WeaponProficiency.cacheList[targetItem:getId()]
	local currentExperience = weaponEntry and weaponEntry.exp or 0

	return currentExperience >= maxExperience
end

local function enableBonusIcon(bonusIcon, iconGrey, hightLightWidget, borderWidget, bonusDescWidget, bonusTooltip, augmentIconDarker, perkData)
	if bonusIcon.blocked or bonusIcon.active or bonusIcon.locked then
		return true
	end

	local visible = not iconGrey:isVisible()

	iconGrey:setVisible(false)
	hightLightWidget:setVisible(true)
	borderWidget:setImageSource("/images/game/proficiency/border-weaponmasterytreeicons-active")

	bonusDescWidget:setImageSource("")
	bonusDescWidget:setText(bonusTooltip)
	-- Check text length instead of wrapped lines (getWrappedLinesCount doesn't exist)
	if bonusTooltip and #bonusTooltip > 200 then
		bonusDescWidget:setText(short_text(bonusTooltip, 57))
		bonusDescWidget:setTooltip(bonusTooltip)
	end

	if perkData.Type == PERK_SPELL_AUGMENT then
		augmentIconDarker:setVisible(false)
	end

	bonusIcon.active = true
end

local function disableBonusIcon(iconGrey, hightLightWidget, borderWidget, bonusDescWidget, augmentIconDarker, perkData)
	iconGrey:setVisible(true)
	iconGrey:setOpacity(1)
	hightLightWidget:setVisible(false)
	borderWidget:setImageSource("/images/game/proficiency/border-weaponmasterytreeicons-inactive")

	bonusDescWidget:setImageSource("/images/game/proficiency/icon-lock-grey")
	bonusDescWidget:setText("")
	bonusDescWidget:removeTooltip()

	if perkData.Type == PERK_SPELL_AUGMENT then
		augmentIconDarker:setVisible(true)
		augmentIconDarker:setOpacity(1)
	end
end

local function disableOtherBonusIcons(currentPerkPanel, currentBonusIcon)
	-- Disable all other bonus icons in the same panel (only one can be active at a time)
	if not currentPerkPanel then
		return
	end
	
	for _, bonusIcon in pairs(currentPerkPanel:getChildren()) do
		if bonusIcon and bonusIcon ~= currentBonusIcon then
			-- Disable if active OR if it's not the current one being clicked
			if bonusIcon.active then
			bonusIcon.blocked = false
			bonusIcon.active = false
			local iconGrey = bonusIcon:getChildById("icon-grey")
			local hightLightWidget = bonusIcon:getChildById("highlight")
			local borderWidget = bonusIcon:getChildById("border")
			local augmentIconDarker = bonusIcon:getChildById("iconPerks-grey")
			local augmentIcon = bonusIcon:getChildById("iconPerks")
				local bonusDescWidget = bonusIcon:getParent():getParent():recursiveGetChildById("bonusName")

				if iconGrey then
			iconGrey:setVisible(true)
			iconGrey:setOpacity(1)
				end
				if hightLightWidget then
			hightLightWidget:setVisible(false)
				end
				if borderWidget then
			borderWidget:setImageSource("/images/game/proficiency/border-weaponmasterytreeicons-inactive")
				end
				if augmentIcon and augmentIcon:isVisible() then
					if augmentIconDarker then
				augmentIconDarker:setVisible(true)
				augmentIconDarker:setOpacity(1)
					end
				end
				-- Clear bonus description
				if bonusDescWidget then
					bonusDescWidget:setImageSource("")
					bonusDescWidget:setText("")
				end
			end
		end
	end
end

local function updatePercentWidgets(child, currentExperience, _index, itemType)
	if not child then
		return
	end

	local percentWidget = child:getChildById("bonusSelectProgress")
	local starWidget = WeaponProficiency.starProgressPanel:getChildById("starWidget" .. _index)
	local starProgress = starWidget:getChildById("starProgress")

	local expValue = currentExperience or 0
	local percent = ProficiencyData:getLevelPercent(expValue, _index, itemType)
	local maxLevelExperience = ProficiencyData:getMaxExperienceByLevel(_index, itemType)

	-- Calculate experience range for this specific level
	local prevLevelExp = 0
	if _index > 1 then
		prevLevelExp = ProficiencyData:getMaxExperienceByLevel(_index - 1, itemType) or 0
	end
	local levelExp = math.max(0, expValue - prevLevelExp)
	local levelMaxExp = maxLevelExperience - prevLevelExp

	-- Only show progress if there's experience
	if expValue > 0 then
		-- Calculate display percent: if level is completed (100%), show 100%, otherwise show progress within level
		local displayPercent = percent
	if percent >= 100 then
			displayPercent = 100
		elseif percent > 0 and levelMaxExp > 0 then
			-- Calculate percentage based on experience within this level's range
			displayPercent = math.min(100, math.floor((levelExp / levelMaxExp) * 100))
		end
		
		percentWidget:setPercent(displayPercent)
		starProgress:setPercent(displayPercent)
		starProgress:setTooltip(string.format("%s / %s", comma_value(expValue), comma_value(maxLevelExperience)))
	else
		percentWidget:setPercent(0)
		starProgress:setPercent(0)
		starProgress:setTooltip("No experience gained yet")
	end

	-- Star color: show based on level completion
	local starIcon = starWidget:getChildById("star")
	if starIcon then
		if expValue == 0 then
			-- No experience: show grey faint
			starIcon:setImageSource("/images/game/proficiency/icon-star-tiny-silver")
			starIcon:setOpacity(0.3)
		elseif percent >= 100 then
			-- Level completed: check if mastery achieved for gold, otherwise silver
			local masteryAchieved = false
			local success, result = pcall(function()
				return isMasteryAchieved(itemType)
			end)
			if success then
				masteryAchieved = result
			end
			local iconType = masteryAchieved and "gold" or "silver"
			starIcon:setImageSource(string.format("/images/game/proficiency/icon-star-tiny-%s", iconType))
			starIcon:setOpacity(1)
		else
			-- In progress: silver
			starIcon:setImageSource("/images/game/proficiency/icon-star-tiny-silver")
			starIcon:setOpacity(1)
		end
	end
	
	if percent >= 100 then
		for _, widget in pairs(child.currentPerkPanel:getChildren()) do
			widget.blocked = false
		end
	end
end

local function checkSortOptions(itemData)
	local player = g_game.getLocalPlayer()
	if not player then
		return false
	end

	local playerLevel = player:getLevel()
	local playerVocation = player:getVocation()

	if WeaponProficiency.filters["levelButton"] then
		if itemData.marketData.requiredLevel > playerLevel then
			return false
		end
	end

	if WeaponProficiency.filters["vocButton"] then
		local itemVocation = itemData.marketData.restrictVocation
		-- Check if itemVocation is a valid table before using it
		if type(itemVocation) == "table" and #itemVocation > 0 and not table.contains(itemVocation, playerVocation) then
			return false
		end
	end

	if WeaponProficiency.filters["oneButton"] then
		if itemData.thingType:getClothSlot() ~= 6 then
			return false
		end
	end

	if WeaponProficiency.filters["twoButton"] then
		if itemData.thingType:getClothSlot() ~= 0 then
			return false
		end
	end
	return true
end

local function setupPerkIconGrey(perkData, iconSource, iconClip, iconGrey, augmentIconNormal, augmentIconDarker)
	if perkData.Type == PERK_SPELL_AUGMENT then
		iconGrey:setImageSource(string.format("%s-off", iconSource))
		iconGrey:setImageClip(string.format("%s 64 64", iconClip))
		local augmentIconClip = ProficiencyData:getAugmentIconClip(perkData)
		augmentIconNormal:setVisible(true)
		augmentIconDarker:setVisible(true)
		augmentIconNormal:setImageClip(string.format("%s 32 32", augmentIconClip))
		local x = tonumber(augmentIconClip:match("^(%d+)")) or 0
		augmentIconDarker:setImageClip(string.format("%d 32 32 32", x))
	else
		local x = tonumber(iconClip:match("^(%d+)")) or 0
		iconGrey:setImageSource(iconSource)
		iconGrey:setImageClip(string.format("%d 64 64 64", x))
	end
end

local function createHoverHandler(bonusIcon, iconGrey, augmentIconDarker)
	return function(widget, hovered)
		if not bonusIcon.active and not bonusIcon.locked and not bonusIcon.blocked then
			local opacity = hovered and 0.5 or 1
			if iconGrey then
			iconGrey:setOpacity(opacity)
			end
			if augmentIconDarker then
			augmentIconDarker:setOpacity(opacity)
		end
		end
		-- Tooltip is handled automatically by the widget's tooltip property
	end
end

local function createClickHandler(bonusIcon, currentPerkPanel, bonusDetail, hightLightWidget, borderWidget, iconGrey, augmentIconDarker, bonusTooltip, perkData, itemId)
	return function()
		if bonusIcon.blocked or bonusIcon.active or bonusIcon.locked then return end
		
		-- First disable all other perks in the same panel (level)
		disableOtherBonusIcons(currentPerkPanel, bonusIcon)
		
		-- Then enable the clicked perk
		enableBonusIcon(bonusIcon, iconGrey, hightLightWidget, borderWidget, bonusDetail:recursiveGetChildById("bonusName"), bonusTooltip, augmentIconDarker, perkData)
		
		-- Check if perks match and update buttons
		WeaponProficiency:checkPerksMatch(itemId)
	end
end

----------------------------
------ Core Functions ------
----------------------------
function WeaponProficiency:reset()
	self.cacheList = {}
	self.allProficiencyRequested = false
end

function WeaponProficiency:updateMainButtons(currentData)
	if not WeaponProficiency.window then
		return
	end
	
	local enableReset = canChangeWeaponPerks() and table.size(currentData.perks) > 0
	local resetButton = WeaponProficiency.window:getChildById("reset")
	local applyButton = WeaponProficiency.window:getChildById("apply")
	local okButton = WeaponProficiency.window:getChildById("ok")
	local closeButton = WeaponProficiency.window:getChildById("close")

	resetButton:setOn(enableReset)
	applyButton:setOn(false)
	okButton:setOn(false)

	local resetTooltip = "Reset your perks"
	if not canChangeWeaponPerks() then
		resetTooltip = "You can only reset your perks in a protection zone."
	elseif table.empty(currentData.perks) then
		resetTooltip = "You don't have any perks to reset."
	end

	resetButton:setTooltip(resetTooltip)
	applyButton:setTooltip("No changes have been made to your perks.")
	closeButton:setText("Close")
end

function WeaponProficiency:createItemCache()
    self.itemList = self.itemList or {}

    -- garante lista para “Weapons All”
    self.itemList[32] = self.itemList[32] or {}

    for _, cat in pairs(self.ItemCategory) do
        self.itemList[cat] = self.itemList[cat] or {}
    end

    print("Weapon Proficiency: createItemCache() stub - listas vazias inicializadas (sem getProficiencyThings).")
end

function WeaponProficiency:onItemListValueChange(scroll, value, delta)
	if value == self.oldScrollValue then
		return
	end

	self.oldScrollValue = value
	if not WeaponProficiency.window then
		return
	end
	
	local itemListWidget = WeaponProficiency.window:recursiveGetChildById("itemList")

	-- Special case with half visible lines
	if #self.listData > 30 and #self.listData <= 35 then
    	itemListWidget:setVirtualOffset({x = 0, y = (delta > 0 and 8 or 0)})
		return true
	end

    local itemsPerRow = 5
    local rowsVisible = 8
    local itemsVisible = itemsPerRow * rowsVisible
    local totalItems = #self.listData

    local startLabel = (value * itemsPerRow) + 1
    local endLabel = startLabel + itemsVisible - 1

    local currentWidgetIndex = startLabel

    self.offset = self.offset + ((value % 5) * 2)

    if self.offset > 64 or value == 0 then
        self.offset = 0
    end

    if endLabel >= totalItems then
        self.offset = 7
    end

    itemListWidget:setVirtualOffset({x = 0, y = self.offset})

	local currentItem = nil
	if WeaponProficiency.displayItemPanel then
		local itemWidget = WeaponProficiency.displayItemPanel:getChildById("item")
		if itemWidget then
			currentItem = itemWidget:getItem()
		end
	end

    -- Update widgets based on scroll position
    for widgetIndex = 0, 44 do
        -- Try getChildById first (direct child), then recursiveGetChildById
        local widget = itemListWidget:getChildById("widget_" .. widgetIndex)
        if not widget then
            widget = itemListWidget:recursiveGetChildById("widget_" .. widgetIndex)
        end
        if not widget then
            goto continue
        end

        local dataIndex = startLabel + widgetIndex - 1
        if dataIndex > totalItems or dataIndex < 1 then
            widget:setVisible(false)
            goto continue
        end

        local entry = self.listData[dataIndex]
        if not entry then
            widget:setVisible(false)
            goto continue
        end

        widget:getChildById("item"):setItem(entry.displayItem)
        widget:setTooltip(entry.marketData.name)
        widget.cache = entry
        widget:setVisible(true)

		if widget:isFocused() then
			itemListWidget:focusChild(nil, MouseFocusReason, false, true)
		end

		if currentItem and currentItem:getId() == entry.marketData.showAs then
			itemListWidget:focusChild(widget, MouseFocusReason, false, true)
		end

		-- Check experience/stars
		local cacheEntry = self.cacheList[entry.marketData.showAs] or nil
		local weaponLevel = ProficiencyData:getCurrentLevelByExp(entry.displayItem, (cacheEntry and cacheEntry.exp or 0))
		local starPanel = widget:getChildById("starsBackground")

		if starPanel then
		starPanel:destroyChildren()
			
			local mastery = false
			if entry.displayItem then
				local success, result = pcall(function()
					return isMasteryAchieved(entry.displayItem)
				end)
				if success then
					mastery = result
				end
			end
			
		if weaponLevel > 0 then
			for i = 1, weaponLevel do
				local _star = g_ui.createWidget("MiniStar", starPanel)
					-- Show gold stars only if mastery is achieved (level 7), otherwise silver
					if mastery and weaponLevel >= 7 then
					_star:setImageSource("/images/game/proficiency/icon-star-tiny-gold")
					else
						_star:setImageSource("/images/game/proficiency/icon-star-tiny-silver")
				end
			end
		end
		end
        :: continue ::
    end
end

function WeaponProficiency:onWeaponCategoryChange(text, itemId, thing, fromServer, forceUpdate)
    -- text = "Weapons: Axes" / "Weapons: All" etc. vindo do ComboBox
    print("DEBUG onWeaponCategoryChange: self.window =", self.window)  -- <-- adiciona isso
    if not self.window then
        print("Weapon Proficiency: ERROR - Window not initialized in onWeaponCategoryChange")
        return
    end

    -- Prevent duplicate processing
    if self.isProcessingCategoryChange then
        return
    end
    self.isProcessingCategoryChange = true

    local selected = text

    -- Garante que a tabela de mapeamento existe
    if not WeaponStringToCategory then
        print("Weapon Proficiency: ERROR - WeaponStringToCategory is nil!")
        print("Weapon Proficiency: text received = " .. tostring(selected))
        self.isProcessingCategoryChange = false
        return
    end

    local weaponCategory = WeaponStringToCategory[selected]
    if not weaponCategory then
        print("Weapon Proficiency: ERROR - Invalid category text: " .. tostring(selected))
        self.isProcessingCategoryChange = false
        return
    end

    -- Garante que a categoria existe na itemList
    if not self.itemList or not self.itemList[weaponCategory] then
        print("Weapon Proficiency: ERROR - Category " .. tostring(weaponCategory) .. " not found in itemList!")
        self.isProcessingCategoryChange = false
        return
    end

    -- Variáveis auxiliares que a função usa mais abaixo
    local searchText      = ""       -- se tiver TextEdit de busca, depois você lê dele aqui
    local targetItemId    = nil
    local focusFirstChild = true
    local fromOptionChange = true

    print("Weapon Proficiency: Changing to category " .. selected .. " (ID: " .. weaponCategory .. "), items in category: " .. (#self.itemList[weaponCategory] or 0))

    sortWeaponProficiency(weaponCategory)

    -- Update current filter without propagation
    if self.optionFilter then
        self.optionFilter:setCurrentOption(selected, true)
    end

    local targetWidget = nil
    local itemListWidget = WeaponProficiency.window:recursiveGetChildById("itemList")
    if not itemListWidget then
        print("Weapon Proficiency: ERROR - itemList widget not found")
        self.isProcessingCategoryChange = false
        return
    end

    -- Ensure widgets are created if they don't exist
    local widgetCount = #itemListWidget:getChildren()
    print("Weapon Proficiency: itemListWidget has " .. widgetCount .. " children")
    if widgetCount == 0 then
        print("Weapon Proficiency: No widgets found, creating them...")
        for i = 0, 44 do
            local widget = g_ui.createWidget("ItemBox", itemListWidget)
            widget:setId("widget_" .. i)
        end
        print("Weapon Proficiency: Created " .. #itemListWidget:getChildren() .. " widgets")
    else
        -- Widgets exist but may not have IDs, set them
        local children = itemListWidget:getChildren()
        for i = 0, math.min(#children - 1, 44) do
            if children[i + 1] then
                children[i + 1]:setId("widget_" .. i)
            end
        end
        print("Weapon Proficiency: Set IDs for existing widgets")
    end

    local currentItem = nil
    if WeaponProficiency.displayItemPanel then
        local itemWidget = WeaponProficiency.displayItemPanel:getChildById("item")
        if itemWidget then
            currentItem = itemWidget:getItem()
        end
    end

    itemListWidget.onChildFocusChange = nil

    -- Calculate capacity based on widget height (minimum 45 widgets visible)
    local widgetHeight = itemListWidget:getHeight()
    local calculatedCapacity = ((math.floor(widgetHeight / self.listWidgetHeight)) + 2) * 5
    self.listCapacity   = math.max(calculatedCapacity, 45) -- Ensure at least 45 widgets
    self.listMinWidgets = 0
    self.oldScrollValue = 0
    self.listPool       = {}
    self.listData       = {}

    print("Weapon Proficiency: itemListWidget height: " .. widgetHeight .. ", calculated capacity: " .. calculatedCapacity .. ", final capacity: " .. self.listCapacity)

    -- Generate the filtered list (only items that pass filters)
    local totalInCategory = 0
    for _, data in pairs(self.itemList[weaponCategory]) do
        totalInCategory = totalInCategory + 1
        if not checkSortOptions(data) then
            goto continue
        end

        if searchText and searchText ~= "" then
            local itemName   = (data.marketData.name or ""):lower()
            local searchLower = searchText:lower()
            if not string.find(itemName, searchLower, 1, true) then
                goto continue
            end
        end

        table.insert(self.listData, data)
        ::continue::
    end

    print("Weapon Proficiency: Category " .. selected .. " - Total items: " .. totalInCategory .. ", Filtered: " .. #self.listData .. ", Capacity: " .. self.listCapacity)

    -- Now display all filtered items in the grid
    local currentIndex = 0
    for _, data in ipairs(self.listData) do
        if currentIndex >= self.listCapacity then
            break
        end

        local children = itemListWidget:getChildren()
        local widget   = nil
        if currentIndex < #children then
            widget = children[currentIndex + 1] -- Lua é 1-indexado
            if widget:getId() ~= "widget_" .. currentIndex then
                widget:setId("widget_" .. currentIndex)
            end
        else
            widget = itemListWidget:getChildById("widget_" .. currentIndex)
            if not widget then
                widget = itemListWidget:recursiveGetChildById("widget_" .. currentIndex)
            end
        end

        if not widget then
            print("Weapon Proficiency: Widget " .. currentIndex .. " not found! Total children: " .. #children)
            currentIndex = currentIndex + 1
            goto continue_display
        end

        local itemWidget = widget:getChildById("item")
        if not itemWidget then
            print("Weapon Proficiency: Item widget not found in widget " .. currentIndex)
            currentIndex = currentIndex + 1
            goto continue_display
        end

        if data.displayItem then
            local success, err = pcall(function()
                itemWidget:setItem(data.displayItem)
            end)
            if not success then
                print("Weapon Proficiency: Error setting item in widget " .. currentIndex .. ": " .. tostring(err))
                currentIndex = currentIndex + 1
                goto continue_display
            end
        else
            print("Weapon Proficiency: displayItem is nil for widget " .. currentIndex)
            currentIndex = currentIndex + 1
            goto continue_display
        end

        widget:setVisible(true)
        widget:setTooltip(data.marketData.name)
        widget.cache = data

        if not targetWidget then
            if targetItemId and targetItemId == data.marketData.showAs then
                targetWidget = widget
            elseif fromOptionChange and not focusFirstChild and currentItem and currentItem:getId() == data.marketData.showAs then
                targetWidget = widget
            end
        end

        local cacheEntry  = self.cacheList[data.marketData.showAs] or nil
        local weaponLevel = ProficiencyData:getCurrentLevelByExp(data.displayItem, (cacheEntry and cacheEntry.exp or 0))
        local starPanel   = widget:getChildById("starsBackground")

        if starPanel then
            starPanel:destroyChildren()

            local mastery = false
            if data.displayItem then
                local success, result = pcall(function()
                    return isMasteryAchieved(data.displayItem)
                end)
                if success then
                    mastery = result
                end
            end

            if weaponLevel > 0 then
                for i = 1, weaponLevel do
                    local _star = g_ui.createWidget("MiniStar", starPanel)
                    if mastery and weaponLevel >= 7 then
                        _star:setImageSource("/images/game/proficiency/icon-star-tiny-gold")
                    else
                        _star:setImageSource("/images/game/proficiency/icon-star-tiny-silver")
                    end
                end
            end
        end

        table.insert(self.listPool, widget)
        currentIndex = currentIndex + 1
        ::continue_display::
    end

    -- Hide remaining widgets
    for i = currentIndex, 44 do
        local widget = itemListWidget:recursiveGetChildById("widget_" .. i)
        if widget then
            widget:setVisible(false)
        end
    end

    self.listMaxWidgets = math.ceil((#self.listData / 5) - 7)
    local specialListSize = false
    if #self.listData > 30 and #self.listData <= 35 then
        self.listMaxWidgets = 1
        specialListSize = true
    end

    if self.itemListScroll then
        self.itemListScroll:setValue(0)
        self.itemListScroll:setMinimum(self.listMinWidgets)
        self.itemListScroll:setMaximum(math.max(0, self.listMaxWidgets))
        self.itemListScroll.onValueChange = function(list, value, delta)
            self:onItemListValueChange(list, value, delta)
        end
    end

    itemListWidget:setVirtualOffset({ x = 0, y = 0 })

    itemListWidget.onChildFocusChange = function(_, a)
  if a and a.cache then
    print("Weapon Proficiency: onItemListFocusChange called, itemId =", a.cache.marketData.showAs)
    WeaponProficiency:onItemListFocusChange(a.cache)
  else
    print("Weapon Proficiency: onChildFocusChange - focused widget has no cache")
  end
end


    if targetWidget or focusFirstChild then
        itemListWidget:focusChild(targetWidget or itemListWidget:getFirstChild(), MouseFocusReason, true)
    else
        itemListWidget:focusChild(nil, MouseFocusReason, false, true)
    end

    if targetItemId and not targetWidget then
        for _, data in pairs(self.itemList[weaponCategory]) do
            if targetItemId == data.marketData.showAs then
                self:onItemListFocusChange(data)
                break
            end
        end
    end

    self.isProcessingCategoryChange = false
end


function WeaponProficiency:onItemListFocusChange(selectedCache)
    if not selectedCache or not g_game.isOnline() then return end

    print("DEBUG onItemListFocusChange ENTER, selectedCache =", selectedCache)

    -- Only process if window is visible
    if not WeaponProficiency.displayItemPanel then
    scheduleEvent(function()
        WeaponProficiency:onItemListFocusChange(selectedCache)
    end, 50)
    return
end

    if not WeaponProficiency.displayItemPanel then
        return
    end

    local displayPanel = WeaponProficiency.displayItemPanel:getChildById("item")
    local oldItem = displayPanel:getItem()

    -- Display a warning message to save changes
    if self.saveWeaponMissing and oldItem then
        self:onCloseMessage(false, oldItem, function() self:onItemListFocusChange(selectedCache) end)
        return
    end

    -- Sempre usar o displayItem vindo do entry da lista
    local displayItem = selectedCache.displayItem
    if not displayItem then
        print("Weapon Proficiency: WARNING - selectedCache.displayItem is nil")
        return
    end

    local displayItemId = displayItem:getId()
    local itemName = selectedCache.marketData and selectedCache.marketData.name or "Unknown Item"
    print("DEBUG displayItemId =", displayItemId, "itemName =", itemName)

    displayPanel:setItem(displayItem)
    self.displayItemPanel:getChildById("itemNameTitle"):setText(itemName)

    -- Limpa UI de perks/estrelas
    self.perkPanel:destroyChildren()
    self.bonusDetailPanel:destroyChildren()
    self.starProgressPanel:destroyChildren()

    -- Vocation warning label
    local player = g_game.getLocalPlayer()
    local itemVocation = selectedCache.marketData and selectedCache.marketData.restrictVocation
    local requiredLevel = selectedCache.marketData and selectedCache.marketData.requiredLevel or 0
    local playerVocation = player and player:getVocation() or 0

    local showVocationWarning = false
    if type(itemVocation) == "table" and #itemVocation > 0 and not table.contains(itemVocation, playerVocation) then
        showVocationWarning = true
    elseif player and player:getLevel() < requiredLevel then
        showVocationWarning = true
    end

    self.vocationWarning:setVisible(showVocationWarning)

    -- Cache local (sempre garante entrada)
    local currentData = self.cacheList[displayItemId]
    if not currentData then
        currentData = { exp = 0, perks = {} }
        self.cacheList[displayItemId] = currentData
        print("Weapon Proficiency: No cached data for item " .. displayItemId .. ", created empty entry")
    else
        print("Weapon Proficiency: Found cached data for item " .. displayItemId ..
              ", exp: " .. tostring(currentData.exp) ..
              ", perks: " .. table.size(currentData.perks or {}))
    end

    -- SEMPRE pedir dados frescos pro servidor
    print("Weapon Proficiency: Requesting fresh proficiency data from server database for item " .. displayItemId)
    g_game.sendWeaponProficiencyAction(0, displayItemId) -- 0 = WEAPON_PROFICIENCY_ITEM_INFO

    if currentData.exp > 0 then
        print("Weapon Proficiency: Using cached data for item " .. displayItemId ..
              ", exp: " .. tostring(currentData.exp) ..
              " - UI will display immediately, then update when server responds")
    else
        print("Weapon Proficiency: No cached data for item " .. displayItemId .. " - will wait for server response")
    end

    ----------------------------------------------------------------
    -- Resolução de proficiencyId SEM usar displayItem:getThingType
    ----------------------------------------------------------------
    local proficiencyId = 0

    -- 1) Tenta direto de selectedCache.thingType (preenchido na build da lista)
    if selectedCache.thingType then
        local success, result = pcall(function()
            return selectedCache.thingType:getProficiencyId()
        end)
        if success and result then
            proficiencyId = result
        end
    end

    -- 2) Se ainda 0, tenta casar por nome usando índice reverso
    if proficiencyId == 0 then
        local resolvedName = itemName
        if (not resolvedName or resolvedName == "") and selectedCache.thingType then
            local success, result = pcall(function()
                return g_things.getCyclopediaItemName(selectedCache.thingType:getId())
            end)
            if success and result then
                resolvedName = result
            end
        end

        if resolvedName and resolvedName ~= "" then
            local normalizedItemName = resolvedName:gsub("%s+", " "):lower()
            if normalizedItemName:match("^%s*(.-)%s*$") then
                normalizedItemName = normalizedItemName:match("^%s*(.-)%s*$")
            end

            if ProficiencyData.nameToIdIndex then
                if ProficiencyData.nameToIdIndex[resolvedName] then
                    proficiencyId = ProficiencyData.nameToIdIndex[resolvedName]
                elseif ProficiencyData.nameToIdIndex[normalizedItemName] then
                    proficiencyId = ProficiencyData.nameToIdIndex[normalizedItemName]
                else
                    local baseItemName = normalizedItemName:gsub("%s*%d+%s*[hH]%s*", ""):gsub("%s+", " ")
                    baseItemName = baseItemName:match("^%s*(.-)%s*$") or baseItemName
                    if ProficiencyData.nameToIdIndex[baseItemName] then
                        proficiencyId = ProficiencyData.nameToIdIndex[baseItemName]
                    end
                end
            end

            -- Fallback: varre conteúdo se índice falhar
            if proficiencyId == 0 then
                for profId, profData in pairs(ProficiencyData.content) do
                    if profData.Name and profData.Name == resolvedName then
                        proficiencyId = profId
                        break
                    end
                end
            end
        end
    end

    if proficiencyId == 0 then
        print("Weapon Proficiency: WARNING - Could not get proficiency ID for item " ..
              displayItemId .. ", skipping perk display")
        self.perkPanel:destroyChildren()
        self.bonusDetailPanel:destroyChildren()
        self.starProgressPanel:destroyChildren()
        return
    end

    -------------------------------------------------------------
    -- Daqui pra baixo: uso normal de profEntry + cached exp/perks
    -------------------------------------------------------------
    local profEntry = ProficiencyData:getContentById(proficiencyId)
    if not profEntry then
        print("Weapon Proficiency: ERROR - Proficiency entry not found for ID " .. proficiencyId)
        return
    end

    local cachedExp = currentData.exp or 0
    print("Weapon Proficiency: Setting experience progress - using cached exp: " ..
          tostring(cachedExp) .. " (will update when server responds)")
    print("Weapon Proficiency: Item ID: " .. displayItemId ..
          ", levelsCount: " .. #profEntry.Levels)

    self:updateExperienceProgress(cachedExp, #profEntry.Levels, displayItem, proficiencyId)

    if currentData.perks and table.size(currentData.perks) > 0 then
        print("Weapon Proficiency: Found cached perks for item " .. displayItemId .. " - will be displayed")
    end

    for i, levelData in ipairs(profEntry.Levels) do
        local widget = g_ui.createWidget("BonusSelectPanel", self.perkPanel)
        if not widget then
            print("Weapon Proficiency: ERROR - Failed to create BonusSelectPanel widget for level " .. i)
            goto continue_level
        end
        local bonusDetail = g_ui.createWidget("BonusDetailPanel", self.bonusDetailPanel, "bonusDetail_" .. i)
        local starDetail = g_ui.createWidget("StarWidget", self.starProgressPanel)
        starDetail:setId("starWidget" .. i)
        widget:getChildById("bonusSelectProgress"):setPercent(0)

        local perkCount = levelData.Perks and #levelData.Perks or 0
        local currentPerkPanel = nil
        if perkCount > 0 and self.perkPanelsName[perkCount] then
            currentPerkPanel = widget:getChildById(self.perkPanelsName[perkCount])
            if currentPerkPanel then
                currentPerkPanel:setVisible(true)
                widget.currentPerkPanel = currentPerkPanel
            else
                print("Weapon Proficiency: ERROR - Perk panel '" ..
                      self.perkPanelsName[perkCount] .. "' not found in widget!")
            end
        else
            print("Weapon Proficiency: ERROR - No perk panel name for " .. perkCount .. " perks!")
        end

        if not currentPerkPanel then
            print("Weapon Proficiency: ERROR - currentPerkPanel is nil for level " .. i .. ", skipping perks")
            goto continue_level
        end

        local widgetIsBlocked = not canChangeWeaponPerks() and currentData.perks[i - 1]

        for index, perkData in ipairs(levelData.Perks) do
            local bonusIcon = currentPerkPanel:getChildById(string.format("bonusIcon%s", index - 1))
            if not bonusIcon then
                print("Weapon Proficiency: ERROR - bonusIcon" .. (index - 1) ..
                      " not found in currentPerkPanel!")
                goto continue_perk
            end

            local icon = bonusIcon:getChildById("icon")
            local iconGrey = bonusIcon:getChildById("icon-grey")
            local borderWidget = bonusIcon:getChildById("border")
            local hightLightWidget = bonusIcon:getChildById("highlight")
            local augmentIconNormal = bonusIcon:getChildById("iconPerks")
            local augmentIconDarker = bonusIcon:getChildById("iconPerks-grey")

            local iconSource, iconClip = ProficiencyData:getImageSourceAndClip(perkData)
            local bonusName, bonusTooltip = ProficiencyData:getBonusNameAndTooltip(perkData)

            bonusIcon:setTooltip(string.format("%s\n\n%s", bonusName, bonusTooltip))
            bonusIcon.blocked, bonusIcon.locked, bonusIcon.active = true, false, false
            bonusIcon.perkData = perkData

            local fullClip = string.format("%s 64 64", iconClip)
            icon:setImageSource(iconSource)
            icon:setImageClip(fullClip)

            setupPerkIconGrey(perkData, iconSource, iconClip, iconGrey,
                              augmentIconNormal, augmentIconDarker)

            if currentData.perks[i - 1] == index - 1 then
                bonusIcon.blocked = false
                disableOtherBonusIcons(currentPerkPanel, bonusIcon)
                enableBonusIcon(bonusIcon, iconGrey, hightLightWidget, borderWidget,
                                bonusDetail:recursiveGetChildById("bonusName"),
                                bonusTooltip, augmentIconDarker, perkData)
            end

            if widgetIsBlocked then
                bonusIcon:getChildById("locked-perk"):setVisible(true)
                bonusIcon.locked = true
            end

            bonusIcon.onHoverChange = createHoverHandler(bonusIcon, iconGrey, augmentIconDarker)
            bonusIcon.onClick = createClickHandler(bonusIcon, currentPerkPanel, bonusDetail,
                                                   hightLightWidget, borderWidget,
                                                   iconGrey, augmentIconDarker,
                                                   bonusTooltip, perkData, displayItemId)
            ::continue_perk::
        end

        updatePercentWidgets(widget, currentData.exp, i, displayItem)
        ::continue_level::
    end
end


function WeaponProficiency:onUpdateSelectedProficiency(itemId)
	if not WeaponProficiency.displayItemPanel then
		print("Weapon Proficiency: onUpdateSelectedProficiency - displayItemPanel not found")
		return
	end
	
	local itemWidget = WeaponProficiency.displayItemPanel:getChildById("item")
	if not itemWidget then
		print("Weapon Proficiency: onUpdateSelectedProficiency - item widget not found")
		return
	end
	
	local currentItem = itemWidget:getItem()
	if not currentItem or currentItem:getId() ~= itemId then
		print("Weapon Proficiency: onUpdateSelectedProficiency - item mismatch (current: " .. (currentItem and currentItem:getId() or "nil") .. ", expected: " .. itemId .. ")")
		return
	end

	-- IMPORTANT: Get data from cache - this should have been updated by onWeaponProficiency or onProficiencyNotification
	local currentData = self.cacheList[itemId]
	if not currentData then
		print("Weapon Proficiency: onUpdateSelectedProficiency - No cache data for item " .. itemId .. ", creating empty entry")
		currentData = {exp = 0, perks = {}}
		self.cacheList[itemId] = currentData
	end
	
	local experience = currentData.exp or 0
	print("Weapon Proficiency: onUpdateSelectedProficiency - itemId: " .. itemId .. ", exp: " .. experience .. " (from cache)")
	
	-- Get proficiency ID to determine number of levels
	local proficiencyId = 0
	local success, thingType = pcall(function()
		return currentItem:getThingType()
	end)
	if success and thingType then
		local success2, result = pcall(function()
			return thingType:getProficiencyId()
		end)
		if success2 and result then
			proficiencyId = result
		end
	end
	
	-- Get number of levels from proficiency data
	local levelsCount = #self.perkPanel:getChildren()
	if proficiencyId > 0 then
		local profEntry = ProficiencyData:getContentById(proficiencyId)
		if profEntry and profEntry.Levels then
			levelsCount = #profEntry.Levels
		end
	end
	
	self:updateExperienceProgress(experience, levelsCount, currentItem, proficiencyId)

	-- Setup window buttons
	self:updateMainButtons(currentData)

	for i, child in ipairs(self.perkPanel:getChildren()) do
		updatePercentWidgets(child, experience, i, currentItem)

		local activePerkIndex = currentData.perks[i - 1] -- Get the active perk index for this level (nil if no perk)
		-- IMPORTANT: Only show lock icon if there's an active perk AND we can't change perks
		local widgetIsBlocked = not canChangeWeaponPerks() and activePerkIndex ~= nil
		
		for index, widget in pairs(child.currentPerkPanel:getChildren()) do
			-- IMPORTANT: First, remove all locks and reset to inactive state
			local lockedIcon = widget:getChildById("locked-perk")
			local iconGrey = widget:getChildById("icon-grey")
			local borderWidget = widget:getChildById("border")
			local hightLightWidget = widget:getChildById("highlight")
			local augmentIconNormal = widget:getChildById("iconPerks")
			local augmentIconDarker = widget:getChildById("iconPerks-grey")
			local icon = widget:getChildById("icon")
			
			-- IMPORTANT: Always hide lock icon first - will show only if needed below
			if lockedIcon then
				lockedIcon:setVisible(false)
			end
			widget.locked = false
			widget.active = false
			
			-- IMPORTANT: If this is the active perk, enable it
			if activePerkIndex == index - 1 then
				widget.blocked = false
				widget.locked = widgetIsBlocked -- Lock only if we can't change perks

				-- Only show lock icon if locked AND active
				if widgetIsBlocked and lockedIcon then
					lockedIcon:setVisible(true)
				end

				local bonusDetail = self.bonusDetailPanel:getChildById("bonusDetail_" .. i)
				local _, bonusTooltip = ProficiencyData:getBonusNameAndTooltip(widget.perkData)

				-- Get the perk panel for this level to disable other perks
				local perkPanel = widget:getParent()
				if perkPanel then
					disableOtherBonusIcons(perkPanel, widget)
				end
				
				-- Only enable if bonusDetail exists
				if bonusDetail then
					local bonusNameWidget = bonusDetail:recursiveGetChildById("bonusName")
					if bonusNameWidget then
						enableBonusIcon(widget, iconGrey, hightLightWidget, borderWidget, bonusNameWidget, bonusTooltip, augmentIconDarker, widget.perkData)
					end
				end
			else
				-- IMPORTANT: If NOT the active perk, ensure it's in inactive state (no color, no lock icon)
				widget.blocked = true
				widget.locked = false
				
				-- Ensure lock icon is hidden
				if lockedIcon then
					lockedIcon:setVisible(false)
				end
				
				-- Ensure inactive visual state (grey icon, no highlight, inactive border)
				if icon then
					icon:setVisible(false)
				end
				if iconGrey then
					iconGrey:setVisible(true)
					iconGrey:setOpacity(1)
				end
				if hightLightWidget then
					hightLightWidget:setVisible(false)
				end
				if borderWidget then
					borderWidget:setImageSource("/images/game/proficiency/border-weaponmasterytreeicons-inactive")
				end
				if augmentIconDarker then
					augmentIconDarker:setVisible(true)
					augmentIconDarker:setOpacity(1)
				end
				if augmentIconNormal then
					augmentIconNormal:setVisible(false)
				end
			end
		end
		::continue::
	end
end

function WeaponProficiency:updateExperienceProgress(currentExp, levelsCount, displayItem, proficiencyId)
	print("Weapon Proficiency: updateExperienceProgress CALLED - currentExp: " .. tostring(currentExp) .. ", levelsCount: " .. tostring(levelsCount))
	
	local experienceWidget = self.window:recursiveGetChildById("progressDescription")
	local experienceLeftWidget = self.window:recursiveGetChildById("nextLevelDescription")
	local totalProgressWidget = self.window:recursiveGetChildById("proficiencyProgress")

	if not experienceWidget or not experienceLeftWidget then
		print("Weapon Proficiency: ERROR - Experience widgets not found!")
		return
	end

	local expValue = currentExp or 0
	print("Weapon Proficiency: updateExperienceProgress - expValue: " .. tostring(expValue))
	
	local currentCeilExperience = ProficiencyData:getCurrentCeilExperience(expValue, displayItem, proficiencyId)
	local maxExperience = ProficiencyData:getMaxExperience(levelsCount, displayItem)
	local masteryAchieved = expValue >= maxExperience

	print("Weapon Proficiency: updateExperienceProgress - currentCeilExperience: " .. tostring(currentCeilExperience) .. ", maxExperience: " .. tostring(maxExperience) .. ", masteryAchieved: " .. tostring(masteryAchieved))

	-- Format: "exp ganada / exp restante para subir"
	-- If no experience, show "0 / exp necesaria para primer nivel"
	if expValue == 0 then
		local firstLevelExp = ProficiencyData:getMaxExperienceByLevel(1, displayItem) or 0
		local text = string.format("%s / %s", comma_value(0), comma_value(firstLevelExp))
		print("Weapon Proficiency: updateExperienceProgress - Setting text (no exp): " .. text)
		experienceWidget:setText(text)
		experienceLeftWidget:setText(string.format("%s XP for next level", comma_value(firstLevelExp)))
	else
	if masteryAchieved then
			local text = string.format("%s / %s", comma_value(expValue), comma_value(maxExperience))
			print("Weapon Proficiency: updateExperienceProgress - Setting text (mastery): " .. text)
			experienceWidget:setText(text)
		experienceLeftWidget:setText("Mastery achieved")
	else
			local expRemaining = (currentCeilExperience or maxExperience) - expValue
			local text = string.format("%s / %s", comma_value(expValue), comma_value(expRemaining))
			print("Weapon Proficiency: updateExperienceProgress - Setting text (normal): " .. text)
			experienceWidget:setText(text)
			experienceLeftWidget:setText(string.format("%s XP for next level", comma_value(expRemaining)))
		end
	end
	
	self:updateItemAddons(currentExp, displayItem, masteryAchieved)

	-- Only show progress bar if there's experience
	if expValue > 0 then
		totalProgressWidget:setPercent(ProficiencyData:getTotalPercent(expValue, levelsCount, displayItem))
		totalProgressWidget:setTooltip(string.format("%s / %s", comma_value(expValue), comma_value(maxExperience)))
	else
		totalProgressWidget:setPercent(0)
		totalProgressWidget:setTooltip("No experience gained yet")
	end
end

function WeaponProficiency:updateItemAddons(currentExp, displayItem, masteryAchieved)
	local expValue = currentExp or 0
	local weaponLevel = 0
	
	-- Only calculate level if there's experience
	if expValue > 0 then
		weaponLevel = math.min(7, ProficiencyData:getCurrentLevelByExp(displayItem, expValue))
	end
	
	local iconLevelWidget = self.window:recursiveGetChildById("iconMasteryLevel")
	local weaponLevelWidget = self.window:recursiveGetChildById("itemMasteryLevel")

	-- Only show mastery level icon if there's experience
	if expValue > 0 and weaponLevel > 0 then
	iconLevelWidget:setImageSource("/images/game/proficiency/icon-masterylevel-" .. weaponLevel)
		weaponLevelWidget:setVisible(true)
		local color = masteryAchieved and "gold" or "silver"
		weaponLevelWidget:setImageSource(string.format("/images/game/proficiency/icon-masterylevel-%d-%s", weaponLevel, color))
	else
		iconLevelWidget:setImageSource("/images/game/proficiency/icon-masterylevel-0")
		weaponLevelWidget:setVisible(false)
	end
end

function WeaponProficiency:toggleFilterOption(filter)
	local filterId = filter:getId()
	local oneHandButton = self.window:recursiveGetChildById("oneButton")
	local twoHandButton = self.window:recursiveGetChildById("twoButton")

	if filterId == "oneButton" then
		if twoHandButton:isChecked() then
			twoHandButton:setChecked(false, true) -- (true) ignore lua call
			self.filters["twoButton"] = false
		end
	elseif filterId == "twoButton" then
		if oneHandButton:isChecked() then
			oneHandButton:setChecked(false, true)  -- (true) ignore lua call
			self.filters["oneButton"] = false
		end
	end

	self.filters[filterId] = not filter:isChecked()
	filter:setChecked(not filter:isChecked())

	if WeaponProficiency.window then
	self:onWeaponCategoryChange(self.optionFilter:getCurrentOption().text)
	end
end

function WeaponProficiency:onSearchTextChange(text)
	if not WeaponProficiency.window then
		return
	end
	
	-- Prevent duplicate calls by checking if we're already processing
	if self.isProcessingSearch then
		return
	end
	
	self.isProcessingSearch = true
	
	local currentCategory = self.optionFilter:getCurrentOption().text
	self:onWeaponCategoryChange(currentCategory, text)
	
	self.isProcessingSearch = false
end

function WeaponProficiency:onClearSearch()
	if not WeaponProficiency.window then
		return
	end
	
	local searchField = WeaponProficiency.window:recursiveGetChildById("searchText")
	if searchField then
		local text = searchField:getText()
		if text and text ~= "" then
		searchField:clearText()
		end
	end
end

function WeaponProficiency:onApplyChanges(button, targetItem)
	if button and not button:isOn() then return end

	local currentItem = nil
	if targetItem then
		currentItem = targetItem
	elseif WeaponProficiency.displayItemPanel then
		local itemWidget = WeaponProficiency.displayItemPanel:getChildById("item")
		if itemWidget then
			currentItem = itemWidget:getItem()
		end
	end

	if not currentItem then
		return
	end

	local toSend = {}
	for i, child in ipairs(self.perkPanel:getChildren()) do
		for k, v in pairs(child.currentPerkPanel:getChildren()) do
			if not v.blocked and v.active then 
				toSend[i - 1] = k - 1
			end
		end
	end

	if table.empty(toSend) then
		g_game.sendWeaponProficiencyAction(2, currentItem:getId())
		self.cacheList[currentItem:getId()].perks = {}
	else
		g_game.sendWeaponProficiencyApply(currentItem:getId(), toSend)
	end

	-- Lock perks after saving
	for i, child in ipairs(self.perkPanel:getChildren()) do
		for k, v in pairs(child.currentPerkPanel:getChildren()) do
			if v.active then
				local lockedIcon = v:getChildById("locked-perk")
				if lockedIcon then
					lockedIcon:setVisible(true)
				end
				v.locked = true
			end
		end
	end

	-- Update cache with the new perks that were just applied
	local itemId = currentItem:getId()
	if not self.cacheList[itemId] then
		self.cacheList[itemId] = {exp = 0, perks = {}}
	end
	
	-- Convert toSend to the cache format (level -> position mapping)
	local cachePerks = {}
	for level, position in pairs(toSend) do
		cachePerks[level] = position
	end
	self.cacheList[itemId].perks = cachePerks
	
	-- Update UI buttons state
	self.window:getChildById("apply"):setOn(false)
	self.window:getChildById("ok"):setOn(false)
	self.window:getChildById("close"):setText("Close")
	self.saveWeaponMissing = false
	
	-- IMPORTANT: If "OK" button was clicked, close the window after applying changes
	-- This saves the changes and closes the UI in one action
	if button and button:getId() == "ok" then
		print("Weapon Proficiency: OK button clicked - changes applied, closing window...")
		self:hide()
	end
end

function WeaponProficiency:onResetWeapon(button)
	if not WeaponProficiency.window or not WeaponProficiency.displayItemPanel then
		return
	end
	
	if not canChangeWeaponPerks() or not button:isOn() then
		return
	end

	local currentItem = WeaponProficiency.displayItemPanel:getChildById("item"):getItem()
	if not currentItem then
		return
	end

	local itemId = currentItem:getId()
	local applyButton = self.window:getChildById("apply")
	local okButton = self.window:getChildById("ok")
	local closeButton = self.window:getChildById("close")
	local weaponEntry = self.cacheList[itemId] or {}
	local perksSize = table.size(weaponEntry.perks)

	-- IMPORTANT: Clear perks from cache BEFORE resetting visuals
	-- This ensures onUpdateSelectedProficiency doesn't restore locked icons
	if self.cacheList[itemId] then
		self.cacheList[itemId].perks = {}
	end

	button:setOn(false)
	applyButton:setOn(perksSize > 0)
	okButton:setOn(perksSize > 0)

	button:setTooltip("You don't have any perks to reset.")

	if perksSize > 0 then
		local text = "Apply changes to your perks"
		applyButton:setTooltip(text)
		okButton:setTooltip(text)
		closeButton:setText("Cancel")
		self.saveWeaponMissing = true
	else
		local text = "No changes have been made to your perks."
		applyButton:setTooltip(text)
		okButton:setTooltip(text)
		closeButton:setText("Close")
	end

	-- Limpar as informa�oes (Reset all perks) - Reset ALL visual states completely
	for i, child in ipairs(self.perkPanel:getChildren()) do
		local bonusDetail = self.bonusDetailPanel:getChildById("bonusDetail_" .. i)

		for index, widget in pairs(child.currentPerkPanel:getChildren()) do
			-- IMPORTANT: Reset ALL states - no exceptions
				widget.blocked = false
				widget.locked = false
				widget.active = false

			-- Get all visual widgets
			local lockedIcon = widget:getChildById("locked-perk")
				local iconGrey = widget:getChildById("icon-grey")
				local borderWidget = widget:getChildById("border")
				local hightLightWidget = widget:getChildById("highlight")
			local augmentIconNormal = widget:getChildById("iconPerks")
				local augmentIconDarker = widget:getChildById("iconPerks-grey")
			local icon = widget:getChildById("icon")

			-- IMPORTANT: Remove lock icon completely - NO EXCEPTIONS
			if lockedIcon then
				lockedIcon:setVisible(false)
			end

			-- IMPORTANT: Reset icon to grey state (inactive) - hide main icon, show grey icon
			if icon then
				icon:setVisible(false)
			end
			if iconGrey then
				iconGrey:setVisible(true)
				iconGrey:setOpacity(1)
			end

			-- IMPORTANT: Hide highlight (active state indicator)
			if hightLightWidget then
				hightLightWidget:setVisible(false)
			end

			-- IMPORTANT: Reset border to inactive state (same as disableBonusIcon)
			if borderWidget then
				borderWidget:setImageSource("/images/game/proficiency/border-weaponmasterytreeicons-inactive")
			end

			-- IMPORTANT: Show augment icon darker (inactive state) with correct opacity
			if augmentIconDarker then
				augmentIconDarker:setVisible(true)
				augmentIconDarker:setOpacity(1)
			end
			if augmentIconNormal then
				augmentIconNormal:setVisible(false)
			end

			-- IMPORTANT: Clear bonus description completely (same as disableBonusIcon)
			if bonusDetail then
				local bonusNameWidget = bonusDetail:recursiveGetChildById("bonusName")
				if bonusNameWidget then
					bonusNameWidget:setImageSource("/images/game/proficiency/icon-lock-grey")
					bonusNameWidget:setText("")
					bonusNameWidget:removeTooltip()
				end
			end
		end
	end
	
	-- IMPORTANT: Update the display WITHOUT restoring perks from cache
	-- Since we cleared the cache, onUpdateSelectedProficiency will show empty state
	if WeaponProficiency.displayItemPanel then
		local itemWidget = WeaponProficiency.displayItemPanel:getChildById("item")
		if itemWidget then
			local currentItem = itemWidget:getItem()
			if currentItem then
				-- Refresh the display to show reset state (no perks, no locks)
				WeaponProficiency:onUpdateSelectedProficiency(itemId)
			end
		end
	end
end

function WeaponProficiency:onCloseWindow(button)
	if not WeaponProficiency.window then
		return
	end
	
	if button:getText() == "Close" then
		hide()
		-- Input lock is handled automatically by the window system
		return true
	end

	self:onCloseMessage(true)
end

function WeaponProficiency:onCloseMessage(userClosingWindow, targetItem, callbackFunction)
	-- Only show warning if window is already open
	if not self.window:isVisible() then
		if callbackFunction then
			callbackFunction()
		end
		return
	end
	
	if self.warningWindow then
		self.warningWindow:destroy()
	end

	self.window:hide()
	-- Input lock is handled automatically by the window system

	local noButton = function()
		if self.warningWindow then
			self.warningWindow:destroy()
			self.warningWindow = nil
		end
		self.saveWeaponMissing = false

		if not userClosingWindow then
			self.window:show()
			-- Input lock is handled automatically by the window system
			if callbackFunction then
				callbackFunction()
			end
		else
			-- Just close the window, don't do anything else that might crash
		end
	end

  	local yesButton = function()
    	if self.warningWindow then
      		self.warningWindow:destroy()
			self.warningWindow = nil
    	end

		self:onApplyChanges(nil, targetItem)
		
		if not userClosingWindow then
			if callbackFunction then
				callbackFunction()
			end

			self.window:show()
			-- Input lock is handled automatically by the window system
		else
			-- Just close the window, don't do anything else that might crash
		end
  	end

  	self.warningWindow = displayGeneralBox('Save?', "You did not save the changes you have made to your perks.\n\nWould you like to save your perks?",
		{{ text=tr('Yes'), callback = yesButton }, { text=tr('No'), callback = noButton }
	}, yesFunction, noFunction)
end

function WeaponProficiency:checkPerksMatch(itemId)
    local cachePerks = self.cacheList[itemId].perks
    local allPerksMatch = true

    -- Se o cache estiver vazio, n�o bate
    if table.empty(cachePerks) then
        allPerksMatch = false
    else
        -- Para cada linha de perks
        for levelIndex, perkRow in ipairs(self.perkPanel:getChildren()) do
            local expectedPerk = cachePerks[levelIndex - 1]
            local foundActive = nil

            for perkIndex, widget in pairs(perkRow.currentPerkPanel:getChildren()) do
                if widget.active then
                    foundActive = perkIndex - 1
                    break
                end
            end

            -- Se o cache possui perk esperado mas n�o h� ativo, ou h� ativo a mais que o cache
            if expectedPerk and foundActive ~= expectedPerk then
                allPerksMatch = false
                break
            elseif not expectedPerk and foundActive ~= nil then
                -- Ativo a mais, fora do que o cache esperava
                allPerksMatch = false
                break
            end
        end
    end

    -- Habilita ou desabilita os bot�es
    local applyButton = self.window:getChildById("apply")
    local okButton = self.window:getChildById("ok")
	local closeButton = self.window:getChildById("close")

	if canChangeWeaponPerks() and not allPerksMatch then
		local resetButton = self.window:getChildById("reset")
		resetButton:setOn(true)
		resetButton:setTooltip("Reset your perks")
	end

	local tooltip = not allPerksMatch and "No changes have been made to your perks." or "Apply changes to your perks"

    applyButton:setOn(not allPerksMatch)
    okButton:setOn(not allPerksMatch)
	applyButton:setTooltip(tooltip)
	okButton:setTooltip(tooltip)

	closeButton:setText(not allPerksMatch and "Cancel" or "Close")
	self.saveWeaponMissing = not allPerksMatch
end

function onWeaponProficiency(itemId, experience, perksTable, marketCategory)
    print("Weapon Proficiency: ===== onWeaponProficiency CALLED =====")
    print("Weapon Proficiency: itemId: " .. tostring(itemId) .. ", experience: " .. tostring(experience) .. ", marketCategory: " .. tostring(marketCategory))
    print("Weapon Proficiency: perksTable type: " .. type(perksTable) .. ", size: " .. tostring(perksTable and #perksTable or 0))

    -- registra arma vinda do servidor na lista da UI
    if WeaponProficiency and WeaponProficiency.registerServerWeapon then
        WeaponProficiency:registerServerWeapon(itemId, marketCategory)
    end

    -- IMPORTANT: Ensure module is initialized
    if not WeaponProficiency then
        print("Weapon Proficiency: ERROR - WeaponProficiency module not initialized!")
        return
    end

    -- IMPORTANT: Ensure cacheList exists
    if not WeaponProficiency.cacheList then
        WeaponProficiency.cacheList = {}
        print("Weapon Proficiency: Created cacheList in onWeaponProficiency")
    end

    -- perksTable -> perks (índices 0-based)
    local perks = {}
    if type(perksTable) == "table" then
        for i = 1, #perksTable do
            local perk = perksTable[i]
            if perk and type(perk) == "table" and perk.level and perk.position then
                local levelIndex = perk.level - 1
                local positionIndex = perk.position - 1
                perks[levelIndex] = positionIndex
            end
        end
    end

    -- Store proficiency data in cache (REPLACE, don't add)
    WeaponProficiency.cacheList[itemId] = { exp = experience, perks = perks }
    print("Weapon Proficiency: CACHE UPDATED - itemId: " .. itemId .. ", exp: " .. experience .. ", perks: " .. table.size(perks))
    print("Weapon Proficiency: DEBUG - Cache now has " .. table.size(WeaponProficiency.cacheList) .. " entries")
    print("Weapon Proficiency: DEBUG - Verifying cache entry - itemId: " .. itemId .. ", cached exp: " .. tostring(WeaponProficiency.cacheList[itemId].exp))

    -- Update topbar imediatamente
    updateTopBarProficiency(itemId)

    -- Ordena lista dessa categoria (se recebemos uma categoria válida)
    if marketCategory and marketCategory ~= 0 then
        sortWeaponProficiency(marketCategory)
    end

    -- Atualiza UI se a janela estiver aberta e o item atual for este
    if WeaponProficiency.window and WeaponProficiency.window:isVisible() then
        local itemWidget = WeaponProficiency.displayItemPanel and WeaponProficiency.displayItemPanel:getChildById("item")
        if itemWidget then
            local currentItem = itemWidget:getItem()
            if currentItem and currentItem:getId() == itemId then
                print("Weapon Proficiency: Window is visible and item " .. itemId .. " is currently displayed - updating UI with exp: " .. experience)
                WeaponProficiency:onUpdateSelectedProficiency(itemId)
            else
                print("Weapon Proficiency: Window is visible but item " .. itemId .. " is not currently displayed (displayed: " .. (currentItem and currentItem:getId() or "nil") .. ")")
            end
        else
            print("Weapon Proficiency: Window is visible but item widget not found")
        end
    else
        print("Weapon Proficiency: Window not visible - data saved in cache for when UI opens or item is selected")
    end

    print("Weapon Proficiency: ===== onWeaponProficiency COMPLETED =====")
end

function onProficiencyNotification(itemId, experience, hasUnusedPerk)
    -- This is called when experience is gained (opcode 0x5C)
    -- experience is the TOTAL experience (not just gained)

    -- Ensure cacheList exists
    if not WeaponProficiency.cacheList then
        WeaponProficiency.cacheList = {}
        print("Weapon Proficiency: Created cacheList in onProficiencyNotification")
    end

    -- Validate input
    if not itemId or itemId == 0 then
        print("Weapon Proficiency: ERROR - Invalid itemId in onProficiencyNotification!")
        return
    end

    if not experience then
        print("Weapon Proficiency: ERROR - Invalid experience in onProficiencyNotification!")
        return
    end

    local itemCache = WeaponProficiency.cacheList[itemId]
    if not itemCache then
        WeaponProficiency.cacheList[itemId] = { exp = experience, perks = {} }
        print("Weapon Proficiency: Created new cache entry for item " .. itemId .. " with exp: " .. experience)
    else
        local oldExp = itemCache.exp
        itemCache.exp = experience
        print("Weapon Proficiency: Updated cache entry for item " .. itemId .. " - old exp: " .. oldExp .. ", new exp: " .. experience)
    end

    print("Weapon Proficiency: Experience notification (opcode 0x5C) for item " .. itemId .. ", NEW TOTAL exp: " .. experience)

    -- Reordenar pela categoria (se existir market data)
    local thingType = g_things.getThingType(itemId, ThingCategoryItem)
    if thingType then
        local marketData = thingType:getMarketData()
        if marketData and marketData.category ~= 0 then
            sortWeaponProficiency(marketData.category)
        end
    end

    -- Atualizar UI se o item estiver selecionado
    if WeaponProficiency.window and WeaponProficiency.window:isVisible() then
        local itemWidget = WeaponProficiency.displayItemPanel and WeaponProficiency.displayItemPanel:getChildById("item")
        if itemWidget then
            local currentItem = itemWidget:getItem()
            if currentItem and currentItem:getId() == itemId then
                print("Weapon Proficiency: UI is open and showing item " .. itemId .. " - updating UI immediately with new exp: " .. experience)
                WeaponProficiency:onUpdateSelectedProficiency(itemId)
            else
                print("Weapon Proficiency: UI is open but showing different item (current: " .. (currentItem and currentItem:getId() or "nil") .. ", updated: " .. itemId .. ")")
            end
        else
            print("Weapon Proficiency: UI is open but item widget not found")
        end
    else
        print("Weapon Proficiency: UI is not open - data saved in cache for when UI opens")
    end

    -- Update topbar if this is the equipped weapon
    updateTopBarProficiency(itemId, hasUnusedPerk)
end
