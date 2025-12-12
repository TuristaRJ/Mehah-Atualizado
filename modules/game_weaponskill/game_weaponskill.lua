local weaponProficiencies = {}

local WEAPON_PROFICIENCY_FIX = {
  [43877] = {
    name = "sanguine bow",
    weaponType = WEAPON_BOW
  },
  [43864] = {
    name = "sanguine blade",
    weaponType = WEAPON_SWORD
  },
  [43874] = {
    name = "sanguine battleaxe",
    weaponType = WEAPON_AXE
  }
}


-- NOVA FUNÇÃO safeGetThingType (substitui TODAS as chamadas)
local function safeGetThingType(itemId)
  print("safeGetThingType called for itemId:", itemId)
  
  -- FIX Sanguine Bow
  if WEAPON_PROFICIENCY_FIX[itemId] then
    print("🎯 SANGUINE BOW FIX ativado!")
    return WEAPON_PROFICIENCY_FIX[itemId]
  end
  
  -- Tenta OTClient normal
  local thing = g_things.getThingType(itemId, ThingCategoryItem)
  if thing then
    print("✅ ThingType encontrado no OTClient:", thing:getName())
    return {
      name = thing:getName() or "Unknown",
      marketCategory = thing:getMarketData() and thing:getMarketData().category or 0,
      iconId = itemId
    }
  end
  
  print("❌ ThingType NÃO encontrado para:", itemId)
  return nil
end

print("Weapon Proficiency module loaded with Sanguine Bow FIX!")
