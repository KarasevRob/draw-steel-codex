local mod = dmhub.GetModLoading()

-- Hero Token Extension
-- Additive integration for Draw Steel Hero Token uses. Load this Code Mod
-- after Draw Steel's resource, triggered-ability, and power-roll systems.

local HERO_TOKEN_ID = "2166c5fe-260e-4691-9743-06cf097a59f3"
local BENEFIT_USAGE_ID = "854e7cf2-ac22-4805-bd31-5d48dae6c926"

-- Current upstream Heroic Resources recovery implementation. These identities
-- are compatibility sentinels only; this module never edits the upstream data.
local OFFICIAL_HEROIC_RESOURCES_RULE_ID = "883c2fb1-c987-4954-8a05-d90b3412a8af"
local OFFICIAL_RECOVERY_MODIFIER_ID = "ff0601cb-c013-49bb-9404-5059c4bf17d2"
local OFFICIAL_RECOVERY_ABILITY_ID = "7a883c18-c43a-4472-921d-7cd7612a4639"
local OFFICIAL_RECOVERY_SOURCE = "heroic resources global rule mod feature"
local LEGACY_RECOVERY_TRIGGER = "creaturedeath"

HeroTokenExtension = HeroTokenExtension or {}
HeroTokenExtension.activeMod = mod
HeroTokenExtension.heroTokenId = HERO_TOKEN_ID
HeroTokenExtension.benefitUsageId = BENEFIT_USAGE_ID
HeroTokenExtension.integrationReady = false
HeroTokenExtension.recoveryCompatibilityFault = false
HeroTokenExtension.recoveryCompatibilityTrigger = nil
HeroTokenExtension.legacyRecoveryDetected = false
HeroTokenExtension._compatibilityWarningShown = false
HeroTokenExtension._legacySuppressionNoticeShown = false

local function SafeTryGet(obj, key, default)
    if obj == nil then
        return default
    end

    local ok, value = pcall(function()
        local tryGet = obj.try_get
        if tryGet ~= nil then
            return obj:try_get(key, default)
        end

        local result = obj[key]
        if result == nil then
            return default
        end
        return result
    end)

    if not ok or value == nil then
        return default
    end
    return value
end

function HeroTokenExtension.IsRuntimeReady()
    return HeroTokenExtension.integrationReady
        and HeroTokenExtension.activeMod ~= nil
        and not HeroTokenExtension.activeMod.unloaded
end

function HeroTokenExtension.IsCompatible()
    return not HeroTokenExtension.recoveryCompatibilityFault
end

function HeroTokenExtension.IsReady()
    return HeroTokenExtension.IsRuntimeReady()
        and HeroTokenExtension.IsCompatible()
end

function HeroTokenExtension.CanUseBenefit(creatureProps, tokenCost)
    if not HeroTokenExtension.IsReady() or creatureProps == nil then
        return false
    end

    tokenCost = tonumber(tokenCost) or 0
    if tokenCost <= 0 then
        return false
    end

    local availableTokens = CharacterResource.GetGlobalResource(HERO_TOKEN_ID) or 0
    if availableTokens < tokenCost then
        return false
    end

    return creatureProps:GetResourceUsage(BENEFIT_USAGE_ID, "turn") < 1
end

function HeroTokenExtension.MarkBenefitUsed(creatureProps, note)
    creatureProps:ConsumeResource(
        BENEFIT_USAGE_ID,
        "turn",
        1,
        note or "Hero Token benefit"
    )
end

-- triggerBefore runs locally when a completion callback is supplied. Keep its
-- payment acknowledgement in memory rather than the per-turn resource ledger:
-- outside initiative, GetResourceRefreshId("turn") deliberately returns a new
-- GUID on every call, which cannot be used for an immediate commit handshake.
HeroTokenExtension.pendingRerollCommits = {}

function HeroTokenExtension.MarkRerollCommitted(casterToken)
    if casterToken ~= nil and casterToken.charid ~= nil then
        HeroTokenExtension.pendingRerollCommits[casterToken.charid] = true
    end
end

function HeroTokenExtension.ConsumeRerollCommit(creatureProps)
    if not HeroTokenExtension.IsReady() or creatureProps == nil then
        return false
    end

    local token = dmhub.LookupToken(creatureProps)
    if token == nil or token.charid == nil then
        return false
    end

    local committed = HeroTokenExtension.pendingRerollCommits[token.charid] == true
    HeroTokenExtension.pendingRerollCommits[token.charid] = nil
    return committed
end

local function RegisterSymbols()
    if creature == nil or creature.RegisterSymbol == nil then
        return false
    end

    creature.RegisterSymbol{
        symbol = "hteherotokenextensionready",
        lookup = function()
            return HeroTokenExtension.IsReady()
        end,
        help = {
            name = "HTEHeroTokenExtensionReady",
            type = "boolean",
            desc = "True when the Hero Token Extension runtime integration is active and compatible with the loaded Draw Steel Hero Token rules.",
            seealso = {"HeroTokens"},
        },
    }

    creature.RegisterSymbol{
        symbol = "hteherotokenextensioncompatible",
        lookup = function()
            return HeroTokenExtension.IsCompatible()
        end,
        help = {
            name = "HTEHeroTokenExtensionCompatible",
            type = "boolean",
            desc = "True when the loaded Draw Steel Hero Token recovery implementation matches the compatibility version expected by this extension.",
            seealso = {"HTEHeroTokenExtensionReady"},
        },
    }

    creature.RegisterSymbol{
        symbol = "hteherotokenbenefitavailable",
        lookup = function(c)
            if not HeroTokenExtension.IsReady() then
                return false
            end
            return c:GetResourceUsage(BENEFIT_USAGE_ID, "turn") < 1
        end,
        help = {
            name = "HTEHeroTokenBenefitAvailable",
            type = "boolean",
            desc = "True when this creature has not used a Hero Token benefit during the current combat turn.",
            seealso = {"HeroTokens"},
        },
    }

    creature.RegisterSymbol{
        symbol = "hteherotokenrerollcommitted",
        lookup = function(c)
            return HeroTokenExtension.ConsumeRerollCommit(c)
        end,
        help = {
            name = "HTEHeroTokenRerollCommitted",
            type = "boolean",
            desc = "True after this turn's Hero Token test-reroll payment has committed.",
            seealso = {"HTEHeroTokenBenefitAvailable"},
        },
    }

    return true
end

-- A tiny behavior used only by triggerBefore. It performs the shared-resource
-- payment and writes an exact commit marker before the outer forceReroll trigger
-- is allowed to proceed. This avoids the post-reroll payment race while keeping
-- the actual reroll in Draw Steel's native forceReroll implementation.
local function RegisterSpendBehavior()
    if ActivatedAbilityBehavior == nil or RegisterGameType == nil then
        return false
    end

    if HTEHeroTokenSpendBehavior == nil then
        HTEHeroTokenSpendBehavior = RegisterGameType(
            "HTEHeroTokenSpendBehavior",
            "ActivatedAbilityBehavior"
        )
    end

    HTEHeroTokenSpendBehavior.summary = "Spend Hero Token"
    HTEHeroTokenSpendBehavior.cost = 1
    HTEHeroTokenSpendBehavior.markRerollCommit = false
    HTEHeroTokenSpendBehavior.note = "Hero Token benefit"

    function HTEHeroTokenSpendBehavior:Cast(ability, casterToken, targets, options)
        if not HeroTokenExtension.IsReady()
                or casterToken == nil
                or not casterToken.valid
                or casterToken.properties == nil then
            return
        end

        local cost = tonumber(self:try_get("cost", 1)) or 0
        local markRerollCommit = self:try_get("markRerollCommit", false)
        local note = self:try_get("note", ability and ability.name or "Hero Token benefit")

        -- Clear any abandoned acknowledgement before attempting a new payment.
        -- A destroyed roll dialog must never leave a stale commit that can make
        -- a later reroll free if the shared pool changes between prompt/accept.
        if markRerollCommit and casterToken.charid ~= nil then
            HeroTokenExtension.pendingRerollCommits[casterToken.charid] = nil
        end

        if cost <= 0 then
            return
        end

        casterToken:ModifyProperties{
            description = note,
            undoable = false,
            execute = function()
                local creatureProps = casterToken.properties
                if not HeroTokenExtension.CanUseBenefit(creatureProps, cost) then
                    return
                end

                creatureProps:ConsumeResource(
                    HERO_TOKEN_ID,
                    "global",
                    cost,
                    note
                )
                HeroTokenExtension.MarkBenefitUsed(creatureProps, note)
                if markRerollCommit then
                    HeroTokenExtension.MarkRerollCommitted(casterToken)
                end
            end,
        }
    end

    return true
end

local function GetOfficialRecoveryAbility(modifier)
    if modifier == nil or SafeTryGet(modifier, "behavior", "") ~= "trigger" then
        return nil
    end

    local ability = SafeTryGet(modifier, "triggeredAbility")
    if ability == nil then
        return nil
    end

    if SafeTryGet(modifier, "guid", "") == OFFICIAL_RECOVERY_MODIFIER_ID
            or SafeTryGet(ability, "guid", "") == OFFICIAL_RECOVERY_ABILITY_ID then
        return ability
    end

    -- Fallback identity for a minor GUID migration. Keep this narrow: it must
    -- still be an upstream Heroic Resources trigger and describe Hero Tokens +
    -- Recovery Value. Do not suppress arbitrary third-party recovery abilities.
    local source = string.lower(SafeTryGet(modifier, "source", ""))
    if source ~= OFFICIAL_RECOVERY_SOURCE then
        return nil
    end

    local name = string.lower(SafeTryGet(ability, "name", ""))
    local description = string.lower(SafeTryGet(ability, "description", ""))
    local looksLikeRecovery = string.find(name, "recovery", 1, true) ~= nil
        or (string.find(description, "hero token", 1, true) ~= nil
            and string.find(description, "recovery value", 1, true) ~= nil)

    if looksLikeRecovery then
        return ability
    end

    return nil
end

local function ReportRecoveryCompatibilityFault(triggerId)
    if HeroTokenExtension.recoveryCompatibilityFault then
        return
    end

    HeroTokenExtension.recoveryCompatibilityFault = true
    HeroTokenExtension.recoveryCompatibilityTrigger = triggerId

    if not HeroTokenExtension._compatibilityWarningShown then
        HeroTokenExtension._compatibilityWarningShown = true
        printf(
            "HeroTokenExtension: Draw Steel's built-in Hero Token recovery trigger "
            .. "changed from '%s' to '%s'. The extension will fail closed and "
            .. "will not suppress the upstream recovery implementation until "
            .. "compatibility is reviewed.",
            LEGACY_RECOVERY_TRIGGER,
            tostring(triggerId)
        )
    end
end

local function IsLegacyOfficialRecoveryModifier(modifier)
    local ability = GetOfficialRecoveryAbility(modifier)
    if ability == nil then
        return false
    end

    local triggerId = SafeTryGet(ability, "trigger", "")
    if triggerId ~= LEGACY_RECOVERY_TRIGGER then
        ReportRecoveryCompatibilityFault(triggerId)
        return false
    end

    HeroTokenExtension.legacyRecoveryDetected = true
    return true
end

local function NoticeLegacySuppression()
    if HeroTokenExtension._legacySuppressionNoticeShown then
        return
    end

    HeroTokenExtension._legacySuppressionNoticeShown = true
    printf(
        "HeroTokenExtension: suppressing legacy Heroic Resources 'Recovery on Death' "
        .. "(%s); Hero Token Extension recovery replaces that duplicate path.",
        LEGACY_RECOVERY_TRIGGER
    )
end

-- Inspect the known upstream compendium record at load time so an upstream fix
-- changes compatibility before players can use extension abilities. The runtime
-- trigger wrappers below retain the narrow source/name fallback in case the
-- official rule or child GUIDs migrate without this constant being updated.
local function InspectOfficialRecoveryDefinition()
    if dmhub == nil or dmhub.GetTable == nil then
        return
    end

    local ruleMods = dmhub.GetTable("globalRuleMods") or {}
    local ruleMod = ruleMods[OFFICIAL_HEROIC_RESOURCES_RULE_ID]
    if ruleMod == nil then
        return
    end

    local modifierInfo = SafeTryGet(ruleMod, "modifierInfo")
    local features = SafeTryGet(modifierInfo, "features", {}) or {}
    for _, feature in ipairs(features) do
        local modifiers = SafeTryGet(feature, "modifiers", {}) or {}
        for _, modifier in ipairs(modifiers) do
            local ability = GetOfficialRecoveryAbility(modifier)
            if ability ~= nil then
                local triggerId = SafeTryGet(ability, "trigger", "")
                if triggerId == LEGACY_RECOVERY_TRIGGER then
                    HeroTokenExtension.legacyRecoveryDetected = true
                else
                    ReportRecoveryCompatibilityFault(triggerId)
                end
                return
            end
        end
    end
end

-- The upstream Heroic Resources rule currently owns a misconfigured recovery
-- TriggeredAbility on creaturedeath. Leaving that legacy path live would both
-- fire at the wrong rules phase and bypass this extension's shared once-per-turn
-- ledger. Suppress only that exact legacy shape. If upstream changes the trigger,
-- do not mask the new behavior; fail the extension closed instead.
--
-- Wrappers cover automatic dispatch and manual-trigger enumeration. They are
-- installed idempotently so Code Mod reloads do not accumulate wrapper layers.
local function InstallOfficialRecoverySuppression()
    if CharacterModifier == nil
            or CharacterModifier.HasTriggeredEvent == nil
            or CharacterModifier.TriggerEvent == nil
            or CharacterModifier.FillTriggeredAbilities == nil then
        return false
    end

    local function ShouldSuppress(modifier)
        local legacy = IsLegacyOfficialRecoveryModifier(modifier)
        if legacy and HeroTokenExtension.IsReady() then
            NoticeLegacySuppression()
            return true
        end
        return false
    end

    local currentHasTriggeredEvent = CharacterModifier.HasTriggeredEvent
    if currentHasTriggeredEvent ~= HeroTokenExtension._hasTriggeredEventWrapper then
        HeroTokenExtension._baseHasTriggeredEvent = currentHasTriggeredEvent
    end
    local baseHasTriggeredEvent = HeroTokenExtension._baseHasTriggeredEvent
    local hasTriggeredEventWrapper = function(self, ...)
        if ShouldSuppress(self) then
            return false
        end
        return baseHasTriggeredEvent(self, ...)
    end
    HeroTokenExtension._hasTriggeredEventWrapper = hasTriggeredEventWrapper
    CharacterModifier.HasTriggeredEvent = hasTriggeredEventWrapper

    local currentTriggerEvent = CharacterModifier.TriggerEvent
    if currentTriggerEvent ~= HeroTokenExtension._triggerEventWrapper then
        HeroTokenExtension._baseTriggerEvent = currentTriggerEvent
    end
    local baseTriggerEvent = HeroTokenExtension._baseTriggerEvent
    local triggerEventWrapper = function(self, ...)
        if ShouldSuppress(self) then
            return false
        end
        return baseTriggerEvent(self, ...)
    end
    HeroTokenExtension._triggerEventWrapper = triggerEventWrapper
    CharacterModifier.TriggerEvent = triggerEventWrapper

    local currentFillTriggeredAbilities = CharacterModifier.FillTriggeredAbilities
    if currentFillTriggeredAbilities ~= HeroTokenExtension._fillTriggeredAbilitiesWrapper then
        HeroTokenExtension._baseFillTriggeredAbilities = currentFillTriggeredAbilities
    end
    local baseFillTriggeredAbilities = HeroTokenExtension._baseFillTriggeredAbilities
    local fillTriggeredAbilitiesWrapper = function(self, ...)
        if ShouldSuppress(self) then
            return
        end
        return baseFillTriggeredAbilities(self, ...)
    end
    HeroTokenExtension._fillTriggeredAbilitiesWrapper = fillTriggeredAbilitiesWrapper
    CharacterModifier.FillTriggeredAbilities = fillTriggeredAbilitiesWrapper

    return true
end

local symbolsReady = RegisterSymbols()
local behaviorReady = RegisterSpendBehavior()
local suppressionReady = InstallOfficialRecoverySuppression()
local powerTriggerReady = CharacterModifier ~= nil
    and CharacterModifier.TypeInfo ~= nil
    and CharacterModifier.TypeInfo.powertabletrigger ~= nil
    and CharacterModifier.TypeInfo.power ~= nil
    and TriggeredAbility ~= nil
    and CharacterResource ~= nil
    and CharacterResource.GetGlobalResource ~= nil

HeroTokenExtension.integrationReady = symbolsReady
    and behaviorReady
    and suppressionReady
    and powerTriggerReady

InspectOfficialRecoveryDefinition()

if not HeroTokenExtension.integrationReady then
    printf(
        "HeroTokenExtension: required Draw Steel APIs are unavailable. "
        .. "Hero Token Extension abilities will fail closed; load this Code Mod after Draw Steel."
    )
elseif HeroTokenExtension.legacyRecoveryDetected and HeroTokenExtension.IsReady() then
    NoticeLegacySuppression()
end
