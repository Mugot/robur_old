module("Humanizer", package.seeall, log.setup)
clean.module("Humanizer", package.seeall, log.setup)

local CoreEx = _G.CoreEx
local Libs = _G.Libs

local Menu = Libs.NewMenu
local Orbwalker = Libs.Orbwalker
local Game = CoreEx.Game
local Enums = CoreEx.Enums
local ObjectManager = CoreEx.ObjectManager
local EventManager = CoreEx.EventManager
local Input = CoreEx.Input
local Evade = CoreEx.EvadeAPI
local Renderer = CoreEx.Renderer

local Events = Enums.Events

local LocalPlayer = ObjectManager.Player.AsHero

local Humanizer = {}
local Utils = {}
local Globals = {
    NextMoveOrderTime = 0,
    NextAttackOrderTime = 0,
    NextCastSpellTime = 0
}

function Humanizer.LoadMenu()
    Menu.RegisterMenu(
        "Humanizer",
        "Humanizer",
        function()
            Menu.ColumnLayout(
                "IssueOrder",
                "IssueOrder",
                1,
                true,
                function()
                    Menu.ColoredText("> IssueOrder settings", 0x0066CCFF, false)
                    Menu.Slider("IssueOrder.MinDelay", "Minimum delay", 60, 0, 500, 3)
                    Menu.Slider("IssueOrder.MaxDelay", "Maximum delay", 160, 0, 500, 3)
                    Menu.Slider("IssueOrder.Target", "Target delay", 80, 0, 500, 3)
                    Menu.Slider("IssueOrder.Variance", "Variance", 80, 0, 100, 3)
                end
            )
            Menu.Separator()
            Menu.ColumnLayout(
                "CastSpell",
                "CastSpell",
                1,
                true,
                function()
                    Menu.ColoredText("> SpellCast settings", 0x0066CCFF, false)
                    Menu.Slider("CastSpell.MinDelay", "Minimum delay", 60, 0, 500, 3)
                    Menu.Slider("CastSpell.MaxDelay", "Maximum delay", 160, 0, 500, 3)
                    Menu.Slider("CastSpell.Target", "Target delay", 80, 0, 500, 3)
                    Menu.Slider("CastSpell.Variance", "Variance", 80, 0, 100, 3)
                end
            )
            Menu.Separator()
            Menu.ColumnLayout(
                "Orb",
                "Orb",
                1,
                true,
                function()
                    Menu.ColoredText("> Obwalker settings", 0x0066CCFF, false)
                    Menu.Slider("Orb.MinRange", "Minimum move range", 250, 0, 500, 3)
                end
            )
        end
    )
end

function Utils.Gaussian(_mean, _variance)
    return math.sqrt(-2 * _variance * math.log(math.random())) * math.cos(2 * math.pi * math.random()) + _mean
end

function Utils.NextGaussian()
    return Utils.Gaussian(0, 1)
end

function Utils.Clamp(_min, _max, _value)
    return math.max(_min, math.min(_max, _value))
end

function Utils.RandomDelay(_min, _max, _target, _deviation)
    return Utils.Clamp(_min, _max, (-math.log(math.abs(Utils.NextGaussian()))) * _deviation + _target) * 0.001
end

function Humanizer.OnCastSpell(Args)
    if os.clock() > Globals.NextCastSpellTime or Evade:IsEvading() then
        Globals.NextCastSpellTime =
            os.clock() +
            Utils.RandomDelay(
                Menu.Get("CastSpell.MinDelay"),
                Menu.Get("CastSpell.MaxDelay"),
                Menu.Get("CastSpell.Target"),
                Menu.Get("CastSpell.Variance")
            )
    else
        Args.Process = false
    end
end

function Humanizer.OnPreMove(Args)
    if LocalPlayer:Distance(Renderer:GetMousePos()) <= Menu.Get("Orb.MinRange") and not Evade:IsEvading() then
        if LocalPlayer.AsAI.IsMoving then
            Args.Position = LocalPlayer.Position
        else
            Args.Process = false
        end 
        return 
    end
    if os.clock() > Globals.NextMoveOrderTime or Evade:IsEvading() then
        Globals.NextMoveOrderTime =
            os.clock() +
            Utils.RandomDelay(
                Menu.Get("IssueOrder.MinDelay"),
                Menu.Get("IssueOrder.MaxDelay"),
                Menu.Get("IssueOrder.Target"),
                Menu.Get("IssueOrder.Variance")
            )
    else
        Args.Process = false
    end
end

function Humanizer.OnPreAttack(Args)
    if os.clock() > Globals.NextAttackOrderTime or Evade:IsEvading() then
        if Args.Target.IsHero then
            Globals.NextAttackOrderTime =
                os.clock() +
                Utils.RandomDelay(
                    Menu.Get("IssueOrder.MinDelay"),
                    Menu.Get("IssueOrder.MaxDelay"),
                    Menu.Get("IssueOrder.Target"),
                    Menu.Get("IssueOrder.Variance")
                ) *
                    0.0025
        else
            Globals.NextAttackOrderTime =
                os.clock() +
                Utils.RandomDelay(
                    Menu.Get("IssueOrder.MinDelay"),
                    Menu.Get("IssueOrder.MaxDelay"),
                    Menu.Get("IssueOrder.Target"),
                    Menu.Get("IssueOrder.Variance")
                ) *
                    0.005
        end
    else
        Args.Process = false
    end
end

function Humanizer.OnDraw()
    Renderer.DrawCircle3D(LocalPlayer.Position, Menu.Get("Orb.MinRange"), 30, 3, 0xFFFFFFFF)
end

function OnLoad()
    Humanizer.LoadMenu()
    for EventName, EventId in pairs(Events) do
        if Events[EventName] then
            EventManager.RegisterCallback(EventId, Humanizer[EventName])
        end
    end

    INFO("Humanizer Enabled")

    return true
end
