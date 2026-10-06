--[[
	Types

	Shared Luau type definitions so the same shapes are not written out
	again in every module. Holds the types for a player's stat table, a
	weapon entry, an ability entry, an enemy entry, an active status
	effect, a shop stock entry, and the run settings table.

	This module exports types only. It has no functions and no state, so
	requiring it costs nothing at runtime.
]]

--[[
	What connects to this

	Any module using --!strict should require this and use the types
	instead of writing its own. The main ones are
	Server.Game.Core.PlayerStats, Server.Game.Enemies.EnemyBase,
	Server.Game.Combat.Weapons.WeaponBase,
	Server.Game.Combat.Abilities.AbilityBase and
	Server.Game.Effects.StatusEffectService.

	When a field is added to a data table in Game.Data, the matching type
	in here needs the same field adding, otherwise strict mode will
	complain at the point it gets read.

	The existing framework modules under ReplicatedStorage.Modules.Shared
	declare their own local types, so do not try to move those in here.
	This is only for the new game systems.
]]

local Types = {}

----------------------------------------------------------------------
-- RUN
----------------------------------------------------------------------

export type DifficultyEntry = {
	Enabled: boolean,
	DisplayName: string,
	Description: string,
	EnemyHealth: number,
	EnemyDamage: number,
	Money: number,
	ShopPrice: number,
	WaveDelay: number,
	PlayerRegen: number,
}

export type RunSettings = {
	DifficultyName: string,
	Difficulty: DifficultyEntry,
	PlayerCount: number,
	EnemyHealthMultiplier: number,
	EnemyDamageMultiplier: number,
	StartedAt: number,
}

----------------------------------------------------------------------
-- PLAYER
----------------------------------------------------------------------

export type PlayerStatTable = {
	Health: number,
	MaxHealth: number,
	Energy: number,
	MaxEnergy: number,
	Money: number,
	Level: number,
	WalkSpeed: number,
	ExtraJumps: number,
	Inventory: { string },
	IsAlive: boolean,
}

export type LoadoutChoice = {
	Weapons: { string },
	Abilities: { string },
}

----------------------------------------------------------------------
-- WEAPONS
----------------------------------------------------------------------

export type AttackKind = "Melee" | "Area" | "Projectile" | "Hitscan"

export type Explosion = {
	Radius: number,
	Falloff: number,
}

export type ProjectileSettings = {
	Count: number,
	Spread: number,
	Speed: number,
	Lifetime: number,
	Gravity: number,
	ModelName: string,
	Pierce: number,
	Explosion: Explosion?,
}

export type StatusEffectRef = {
	Name: string,
	Duration: number?,
	Amount: number?,
}

export type WeaponAttack = {
	Name: string,
	Kind: AttackKind,
	Damage: number,
	Cooldown: number,
	WindUp: number,
	EnergyCost: number?,
	MaxTargets: number,
	Knockback: number,
	Range: number?,
	HitboxSize: Vector3?,
	Radius: number?,
	SelfDamage: number?,
	Projectile: ProjectileSettings?,
	Animation: string,
	Sound: string,
	HitSound: string,
	StatusEffect: StatusEffectRef?,
}

export type WeaponEntry = {
	Enabled: boolean,
	DisplayName: string,
	Description: string,
	ModelName: string,
	Icon: string,
	Grip: { Hand: string, Offset: CFrame },
	MB1: WeaponAttack,
	MB2: WeaponAttack,
}

----------------------------------------------------------------------
-- ABILITIES
----------------------------------------------------------------------

export type CameraShake = {
	Intensity: number,
	Duration: number,
}

-- The fields every ability shares. Each ability's own numbers sit on
-- top of these, so the modules read them with the entry typed as
-- AbilityEntry & { its own fields }.
export type AbilityEntry = {
	Enabled: boolean,
	DisplayName: string,
	Description: string,
	Icon: string,
	EnergyCost: number,
	Cooldown: number,
	CastTime: number,
	Animation: string,
	Sound: string,
	CameraShake: CameraShake?,
	[string]: any,
}

----------------------------------------------------------------------
-- ENEMIES
----------------------------------------------------------------------

export type EnemyProjectile = {
	Speed: number,
	ModelName: string,
	Gravity: number,
	Count: number?,
	Spread: number?,
}

export type EnemyAttack = {
	Damage: number,
	Range: number,
	MinRange: number,
	Cooldown: number,
	WindUp: number,
	Priority: number,
	Animation: string,
	Sound: string,
	StatusEffect: StatusEffectRef?,
	Knockback: number,
	Radius: number?,
	Projectile: EnemyProjectile?,
	SummonType: string?,
	Count: number?,
	MaxAlive: number?,
	SummonRewardMultiplier: number?,
}

export type EnemyEnrage = {
	Enabled: boolean,
	BelowHealthPercent: number,
	SpeedMultiplier: number,
	DamageMultiplier: number,
	CooldownMultiplier: number,
}

export type EnemyEntry = {
	Enabled: boolean,
	DisplayName: string,
	ModelName: string,
	Health: number,
	WalkSpeed: number,
	DetectRange: number,
	LoseRange: number,
	MoneyReward: number,
	IsBoss: boolean,
	Animations: { [string]: string },
	Sounds: { [string]: string },
	Attacks: { [string]: EnemyAttack },
	PreferredDistance: number?,
	Enrage: EnemyEnrage?,
}

----------------------------------------------------------------------
-- STATUS EFFECTS
----------------------------------------------------------------------

export type EffectKind = "Damage" | "Heal" | "Multiplier" | "Control"
export type StackingRule = "Refresh" | "Extend" | "Highest" | "Stack" | "Ignore"

export type StatusEffectEntry = {
	Enabled: boolean,
	DisplayName: string,
	Kind: EffectKind,
	TickRate: number,
	DefaultDuration: number,
	AmountPerTick: number?,
	Multiplier: number?,
	Stat: string?,
	Stacking: StackingRule,
	IsHarmful: boolean,
	AffectsPlayers: boolean,
	AffectsEnemies: boolean,
	ShowOnHUD: boolean,
	Colour: Color3,
	Icon: string,
	ParticleName: string?,
	AffectsBoss: boolean?,
	ImmunityAfter: number?,
}

-- One effect currently running on a target.
export type ActiveEffect = {
	Name: string,
	Target: Instance,
	Amount: number,
	Multiplier: number?,
	EndsAt: number,
	NextTickAt: number,
	Source: Player?,
}

----------------------------------------------------------------------
-- SHOP
----------------------------------------------------------------------

export type UseType = "Instant" | "Inventory"

export type RarityEntry = {
	DisplayName: string,
	Weight: number,
	Colour: Color3,
	PriceMultiplier: number,
}

export type ShopItemEntry = {
	Enabled: boolean,
	DisplayName: string,
	Description: string,
	Price: number,
	Rarity: string,
	UseType: UseType,
	ModelName: string,
	Icon: string,
	Weight: number?,
	MaxPerRun: number?,
	Sound: string,
	[string]: any,
}

-- What one podium is holding right now. Sent to the client over
-- GetShopStock and ShopStockChanged.
export type ShopStockEntry = {
	Podium: number,
	ItemId: string?,
	Price: number,
	Rarity: string,
	Sold: boolean,
}

----------------------------------------------------------------------
-- WAVES
----------------------------------------------------------------------

export type Wave = {
	Enemies: { [string]: number },
	Delay: number?,
	Interval: number?,
	Name: string?,
}

export type WaveArea = {
	Enabled: boolean,
	Banner: string,
	Waves: { Wave },
}

----------------------------------------------------------------------
-- ROOMS
----------------------------------------------------------------------

export type AreaKind = "Spawn" | "Combat" | "Shop" | "Boss"
export type OpenRule = "Clear" | "Prompt" | "Timer" | "Never"

export type AreaEntry = {
	Name: string,
	Kind: AreaKind,
	GateIn: string?,
	GateOut: string?,
	OpenRule: OpenRule,
	Banner: string?,
	Gate: { [string]: any }?,
	Podiums: number?,
	IsRunEnd: boolean?,
	OpenAfter: number?,
}

return Types
