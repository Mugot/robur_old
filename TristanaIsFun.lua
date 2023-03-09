--[[
 ____  ____  ____  ___  ____   __    _  _    __        ____  ___      ____  __  __  _  _ 
(_  _)(  _ \(_  _)/ __)(_  _) /__\  ( \( )  /__\      (_  _)/ __)    ( ___)(  )(  )( \( )
  )(   )   / _)(_ \__ \  )(  /(__)\  )  (  /(__)\      _)(_ \__ \     )__)  )(__)(  )  ( 
 (__) (_)\_)(____)(___/ (__)(__)(__)(_)\_)(__)(__)    (____)(___/    (__)  (______)(_)\_)
 
]]
if Player.CharName ~= "Tristana" then
    return
end
module("TristanaIsFun", package.seeall, log.setup)
clean.module("TristanaIsFun", package.seeall, log.setup)

-- Globals
local CoreEx = _G.CoreEx
local Libs = _G.Libs

local Menu = Libs.NewMenu
local Prediction = Libs.Prediction
local Orbwalker = Libs.Orbwalker
local CollisionLib = Libs.CollisionLib
local DamageLib = Libs.DamageLib
local ImmobileLib = Libs.ImmobileLib
local SpellLib = Libs.Spell
local TargetSelector = Libs.TargetSelector
local HealthPrediction = Libs.HealthPred

local ObjectManager = CoreEx.ObjectManager
local EventManager = CoreEx.EventManager
local Input = CoreEx.Input
local Enums = CoreEx.Enums
local Game = CoreEx.Game
local Geometry = CoreEx.Geometry
local Evade = CoreEx.EvadeAPI
local Renderer = CoreEx.Renderer

local SpellSlots = Enums.SpellSlots
local SpellStates = Enums.SpellStates
local BuffTypes = Enums.BuffTypes
local Events = Enums.Events
local HitChance = Enums.HitChance
local HitChanceStrings = {
    "Collision",
    "OutOfRange",
    "VeryLow",
    "Low",
    "Medium",
    "High",
    "VeryHigh",
    "Dashing",
    "Immobile"
}

local LocalPlayer = ObjectManager.Player.AsHero

-- Globals
local Tristana = {}
 
Tristana.TargetSelector = nil
Tristana.Target = nil
Tristana.Logic = {}

Tristana.Q =
    SpellLib.Active(
    {
        Slot = SpellSlots.Q,
        Range = Orbwalker.GetTrueAutoAttackRange(LocalPlayer) - 80
    }
)

Tristana.W =
    SpellLib.Skillshot(
    {
        Slot = Enums.SpellSlots.W,
        Range = 900,
        Delay = 0.25,
        Speed = 1100,
        Radius = 350,
        Type = "Circular",
    }
)

Tristana.E =
    SpellLib.Targeted(
    {
        Slot = SpellSlots.E,
        Range = Orbwalker.GetTrueAutoAttackRange(LocalPlayer) - 80
    }
)

Tristana.R =
    SpellLib.Targeted(
    {
        Slot = SpellSlots.R,
        Range = Orbwalker.GetTrueAutoAttackRange(LocalPlayer)
    }
)

Tristana.Exhaust =
    SpellLib.Targeted(
    {
        Slot = nil,
        Range = 600
    }
)

function Tristana.LoadMenu()
    Menu.RegisterMenu(
        "TristanaIsFun",
        "Tristana Is Fun",
        function()
        Menu.ColumnLayout(
            "Combo",
            "Combo",
            1,
            true,
            function()
            Menu.Keybind("ForceR", "Force R Key", string.byte("Z"), false, false, false)
            Menu.Keybind("ForceW", "Force W Key", string.byte("T"), false, false, false)
            Menu.Slider("Exhaust.HealthW", "Exhaust on enemy health %", 40, 0, 100)
            Menu.Slider("Exhaust.HealthSelf", "Exhaust on self health %", 40, 0, 100)
            Menu.Slider("OverkillDamage", "Overkill Damage", 50, 0, 200)
            Menu.Checkbox("Killsteal.R", "R if killable", true)
            Menu.Checkbox("Drawing.DamageOnEnemy", "Draw Damage on Enemy", true)
        end)
        end
    )
end

function Tristana.CheckExhaustSlot()
    local slots = {SpellSlots.Summoner1, SpellSlots.Summoner2}

    local function IsExhaust(slot)
        return LocalPlayer:GetSpell(slot).Name == "SummonerExhaust" --or Player:GetSpell(slot).Name == "SummonerExhaust"
    end

    for i, slot in ipairs(slots) do
        if IsExhaust(slot) then
            if Tristana.Exhaust.Slot ~= slot then
                Tristana.Exhaust.Slot = slot
            end

            return
        end
    end

    if Tristana.Exhaust.Slot ~= nil then
        Tristana.Exhaust.Slot = nil
    end
end

function IsGameAvailable()
    return not (Game.IsChatOpen() or Game.IsMinimized() or LocalPlayer.IsDead or LocalPlayer.IsRecalling)
end

function Tristana.GetDamageW()
    return 45 + Tristana.W:GetLevel() * 50 + (0.5 * LocalPlayer.TotalAP)
end

function Tristana.GetDamageE(Charges)
    return 132 + Tristana.E:GetLevel() * 22 + (((55 + Tristana.E:GetLevel() * 55) / 100) * LocalPlayer.TotalAD) +
               (0.5 * LocalPlayer.TotalAP) * (Charges * 0.3)
end

function Tristana.GetDamageR()
    return (200 + Tristana.R:GetLevel() * 100 + (1 * LocalPlayer.TotalAP)) * 0.7
end

function DamageToDraw(Target)
    local damage = DamageLib.GetAutoAttackDamage(LocalPlayer, Target, true)
    if Tristana.W:IsReady() then
        damage = damage + DamageLib.CalculateMagicalDamage(LocalPlayer, Target, Tristana.GetDamageW())
    end
    if Tristana.E:IsReady() or IsCharged(Target) then
        damage = damage + DamageLib.CalculateMagicalDamage(LocalPlayer, Target, Tristana.GetDamageE(4))
    end
    if Tristana.R:IsReady() and Menu.Get("Killsteal.R") then
        damage = damage + DamageLib.CalculateMagicalDamage(LocalPlayer, Target, Tristana.GetDamageR())
    end
    return damage
end

function IsKillable(Target)
    local damage = DamageLib.GetAutoAttackDamage(LocalPlayer, Target, true)
    damage = damage + DamageLib.CalculatePhysicalDamage(LocalPlayer, Target, Tristana.GetDamageE(4))
    damage = damage + DamageLib.CalculateMagicalDamage(LocalPlayer, Target, Tristana.GetDamageR())
    damage = damage - Menu.Get("OverkillDamage")
    if Target.Health <= damage and DamageLib.CalculateMagicalDamage(LocalPlayer, Target, Tristana.GetDamageR()) > DamageLib.GetAutoAttackDamage(LocalPlayer, Target, true) then
        return true
    end
    return false
end

function IsCharged(Target)
    if Target:GetBuff("tristanaecharge") then
        return true
    end
    return false
end

function GetChargedMinion()
    for k, v in pairs(ObjectManager.GetNearby("all", "minions")) do
        local minion = v.AsMinion
        if minion.Position:Distance(LocalPlayer) <= Orbwalker.GetTrueAutoAttackRange(LocalPlayer) and minion.IsValid and not minion.IsDead and minion.IsTargetable and not minion.IsAlly and
            minion:GetBuff("tristanaecharge") then
            return minion
        end
    end
    return nil
end

function ChargeCount(Target)
    local buff = Target:GetBuff("tristanaecharge")
    if buff ~= nil and buff.Count > 0 then
        return buff.Count
    end
    return 0
end

function Tristana.UltClosest()
    if Tristana.R:IsReady() == false then return end
    local target = ObjectManager.Get("enemy", "heroes")
    local dist = 9999
    local curtarget = nil
    for i, v in pairs(target) do
        if v.Position:Distance(LocalPlayer) <= dist and v.Position:Distance(LocalPlayer) <= Tristana.R.Range then
            dist = v.Position:Distance(LocalPlayer)
            curtarget = v
        end
    end
    if curtarget ~= nil and Tristana.R:IsReady() then
        Tristana.R:Cast(curtarget)
    end
end

function Tristana.ForceW()
    if Menu.Get("ForceW") then
        local curtarget = Tristana.TargetSelector:GetTarget(Tristana.W.Range, true)
        if curtarget ~= nil and Tristana.W:IsReady() then
            Tristana.W:Cast(curtarget)
        end
        return true
    end
    return false
end

function Tristana.OnLowHealth()
    Tristana.Target = Tristana.TargetSelector:GetTarget(600, false)
    if Tristana.Target ~= nil then
    local ExhaustPercent = Menu.Get("Exhaust.HealthSelf") / 100
        if Tristana.Exhaust.Slot ~= nil and LocalPlayer.HealthPercent <= ExhaustPercent then
            if LocalPlayer.Position:Distance(Tristana.Target.AsHero) <= Tristana.Exhaust.Range and Tristana.Exhaust:IsReady() then
                Tristana.Exhaust:Cast(Tristana.Target)
            end
        end
    end
end

function Tristana.OnCombo()
end

function Tristana.OnHarass()
end

function Tristana.OnWaveclear()
end

function Tristana.OnPreAttack(args)
    if not IsGameAvailable() then return false end
    if Menu.Get("ForceR") then
        Tristana.UltClosest()
        Orbwalker.Move(Renderer.GetMousePos())
        args.Process = false
        return
    end
    if Orbwalker.GetMode() == "Combo" then
        if args.Target.IsHero then
            local Target = args.Target.AsHero
            if Tristana.E:IsReady() and IsCharged(Target) == false and (LocalPlayer.Position:Distance(Target) < Tristana.E.Range or Target:IsFacing(LocalPlayer.Position, 40) or Target.MoveSpeed <= LocalPlayer.MoveSpeed or IsKillable(Target)) then
                Tristana.E:Cast(Target)
            end
            if Tristana.Q:IsReady() then
                Tristana.Q:Cast()
            end
            if Menu.Get("Killsteal.R") and Tristana.R:IsReady() and ChargeCount(Target) >= 2 and IsKillable(Target) then
                Tristana.R:Cast(Target)
            end
        end
    end
    if Orbwalker.GetMode() == "Waveclear" then
        if args.Target.IsTurret then
            local Target = args.Target.AsTurret
            if Tristana.E:IsReady() then
                Tristana.E:Cast(Target)
            end
            if Tristana.Q:IsReady() then
                Tristana.Q:Cast()
            end
        end
        if args.Target.IsMinion then
           local ChargedMinion = GetChargedMinion()
           if ChargedMinion ~= nil then
            args.Target = GetChargedMinion()
           end
        end
    end
end

function Tristana.OnGapclose(obj, dash)
    if not IsGameAvailable() then return false end
    if obj == LocalPlayer and Tristana.Target then
        local paths = dash:GetPaths()
        local endPos = paths[#paths].EndPos
        if Tristana.Target.Position:Distance(endPos) < Tristana.Target.Position:Distance(dash.StartPos) then
            local ExhaustPercent = Menu.Get("Exhaust.HealthW") / 100
            if Tristana.Exhaust.Slot ~= nil and Tristana.Target.HealthPercent <= ExhaustPercent then
                if LocalPlayer.Position:Distance(Tristana.Target) < Tristana.Exhaust.Range and Tristana.Exhaust:IsReady() then
                    Tristana.Exhaust:Cast(Tristana.Target)
                end
            end
            if LocalPlayer.Position:Distance(Tristana.Target) < Tristana.E.Range and Tristana.E:IsReady() then
                Tristana.E:Cast(Tristana.Target)
            end
        end
    end
end

function Tristana.OnHighPriority()
    if not IsGameAvailable() then return false end
    Tristana.Target = Tristana.TargetSelector:GetTarget(Orbwalker.GetTrueAutoAttackRange(LocalPlayer), true)
    if Orbwalker.GetMode() == "Waveclear" and Orbwalker.CanAttack() then
       local ChargedMinion = GetChargedMinion()
       if ChargedMinion ~= nil then
        Orbwalker.Attack(ChargedMinion)
       end
    end
    Tristana.OnLowHealth()
end

function Tristana.OnNormalPriority()
    if not IsGameAvailable() then return false end
    Tristana.Target = Tristana.TargetSelector:GetTarget(Orbwalker.GetTrueAutoAttackRange(LocalPlayer), true)
    if Menu.Get("ForceR") then
        Tristana.UltClosest()
        Orbwalker.Move(Renderer.GetMousePos())
    end
    if Tristana.ForceW() then
        Orbwalker.Orbwalk(Renderer.GetMousePos(), Tristana.Target)
    end
end

function Tristana.OnDraw()
    if not IsGameAvailable() then return false end
    if Menu.Get("Drawing.DamageOnEnemy") then
        local heroes = ObjectManager.Get("enemy", "heroes")
        for k, hero in pairs(heroes) do
            local heroAI = hero.AsAI
            if hero.IsVisible and hero.IsOnScreen and not hero.IsDead then
                local damage = DamageToDraw(hero) - Menu.Get("OverkillDamage")
                local hpBarPos = heroAI.HealthBarScreenPos
                local x = 106 / (heroAI.MaxHealth + heroAI.ShieldAll)
                local position = (heroAI.Health + heroAI.ShieldAll) * x
                local value = math.min(position, damage * x)
                position = position - value
                Renderer.DrawFilledRect(Geometry.Vector(hpBarPos.x + position - 45, hpBarPos.y - 23), Geometry.Vector(value, 11), 1, 0xFFFFFFFF)
            end
        end
    end
    if not LocalPlayer.IsOnScreen then
        return false
    end
    Renderer.DrawCircle3D(LocalPlayer.Position, Tristana.W.Range, 30, 1, 0xFFFFFFFF)
end

function OnLoad()
    Tristana.LoadMenu()
    Tristana.TargetSelector = TargetSelector()
    for EventName, EventId in pairs(Events) do
        if Tristana[EventName] then
            EventManager.RegisterCallback(EventId, Tristana[EventName])
        end
    end

    INFO("Now playing: Tristana is Fun")
    Tristana.CheckExhaustSlot()
    return true
end