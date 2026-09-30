-- EffectsController: sons e partículas provisórios (Etapa 1). Tudo local ao cliente.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local HapticService = game:GetService("HapticService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Effects = {}

local fxFolder: Folder
local templates: { [string]: Sound } = {}

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SQUARE = "rbxasset://textures/particles/SquareParticle.png"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local BURSTS = {
	Perfect = { Texture = SPARK, Count = 24, Color = Color3.fromRGB(255, 205, 90), Speed = NumberRange.new(5, 9), Life = NumberRange.new(0.35, 0.6), Size = 0.3, Light = 1, Gravity = -6 },
	Good = { Texture = SPARK, Count = 10, Color = Color3.fromRGB(235, 225, 205), Speed = NumberRange.new(3, 5), Life = NumberRange.new(0.25, 0.45), Size = 0.2, Light = 0.3, Gravity = -4 },
	Bad = { Texture = SMOKE, Count = 6, Color = Color3.fromRGB(110, 92, 72), Speed = NumberRange.new(1, 2), Life = NumberRange.new(0.4, 0.7), Size = 0.5, Light = 0, Gravity = 1 },
	Splash = { Texture = SQUARE, Count = 16, Color = Color3.fromRGB(120, 140, 120), Speed = NumberRange.new(4, 7), Life = NumberRange.new(0.3, 0.55), Size = 0.12, Light = 0, Gravity = -30 },
}

function Effects.Folder(): Folder
	return fxFolder
end

function Effects.Play(name: string, speed: number?, volume: number?)
	local t = templates[name]
	if not t then
		return
	end
	local s = t:Clone()
	s.PlaybackSpeed = speed or 1
	s.Volume = t.Volume * (volume or 1)
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 4)
end

function Effects.Burst(pos: Vector3, kind: string, dir: Vector3?)
	local b = BURSTS[kind]
	if not b then
		return
	end
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.1, 0.1, 0.1)
	holder.CFrame = if dir then CFrame.lookAt(pos, pos + dir) else CFrame.new(pos)
	holder.Parent = fxFolder
	local att = Instance.new("Attachment")
	att.Parent = holder
	local e = Instance.new("ParticleEmitter")
	e.Texture = b.Texture
	e.Rate = 0
	e.Color = ColorSequence.new(b.Color)
	e.LightEmission = b.Light
	e.Speed = b.Speed
	e.Lifetime = b.Life
	e.SpreadAngle = Vector2.new(70, 70)
	e.EmissionDirection = Enum.NormalId.Front
	e.Acceleration = Vector3.new(0, b.Gravity, 0)
	e.Drag = 2
	e.RotSpeed = NumberRange.new(-180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, b.Size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = att
	e:Emit(b.Count)
	Debris:AddItem(holder, 1.5)
end

-- Vibração curta: só existe API para controle.
function Effects.Haptic(strength: number, duration: number)
	local last = UserInputService:GetLastInputType()
	if last.Name:find("Gamepad") and HapticService:IsVibrationSupported(last) then
		HapticService:SetMotor(last, Enum.VibrationMotor.Small, strength)
		task.delay(duration, function()
			HapticService:SetMotor(last, Enum.VibrationMotor.Small, 0)
		end)
	end
end

function Effects.Init()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "LocalFX"
	fxFolder.Parent = Workspace
	local list = {}
	for name, def in Config.Sounds do
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = def.Id
		s.Volume = def.Volume
		templates[name] = s
		table.insert(list, s)
	end
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, list)
	end)
end

return Effects
