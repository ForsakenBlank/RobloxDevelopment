-- UIIcons
-- Every icon from the Velocity UI design (the icons/png folder), by file
-- name. Paste each image's id from the Asset Manager in as
-- "rbxassetid://123..." (right click an image > Copy Asset ID). Anything
-- left "" keeps whatever the game used before (or the drawn
-- placeholder), so they can be filled in one at a time.
--
-- Used by Shared.CoreData (core_*), Shared.LoadoutData (w_*, a_*),
-- Shared.SkinData (face_*), Client.Modules.LobbyMenu (cash) and the
-- menus still to come (gp_* in the shop, eq_* in the loadout, fx_* and
-- i_* in the game place's HUD).

local UIIcons = {
	-- Cores
	core_ruby = "rbxassetid://130645983715475",
	core_sapphire = "rbxassetid://130001874112817",
	core_amethyst = "rbxassetid://102735618783321",
	core_diamond = "rbxassetid://99203124602185",

	-- Weapons
	w_sword = "rbxassetid://98573010114569",
	w_pistol = "rbxassetid://117788625380707",
	w_shotgun = "rbxassetid://98305247292235",
	w_rpg = "rbxassetid://94055914676523",
	w_spear = "rbxassetid://80858427147576",
	w_fists = "rbxassetid://89729284214027",
	w_partygun = "rbxassetid://70620523754719",

	-- Abilities
	a_rage = "rbxassetid://103413912784025",
	a_heal = "rbxassetid://89528772297676",
	a_stun = "rbxassetid://74669819436201",
	a_teleport = "rbxassetid://72205367808144",
	a_zap = "rbxassetid://119599364943504",
	a_fireball = "rbxassetid://103977872770328",
	a_potion = "rbxassetid://96183644905354",
	a_lunge = "rbxassetid://103168876501348",

	-- Gamepasses
	gp_slots = "rbxassetid://76133942619422",
	gp_exp = "rbxassetid://106748137736001",
	gp_customise = "rbxassetid://119952776894834",
	gp_vip = "rbxassetid://74349931832930",

	-- Currency
	cash = "rbxassetid://86750143666516",
	timebux = "rbxassetid://129649960079641",

	-- Equipment
	eq_boots = "rbxassetid://114275051770330",
	eq_legs = "rbxassetid://110158646937233",
	eq_helmet = "rbxassetid://79413518730574",
	eq_acc = "rbxassetid://118046280264008",


	-- Armour and accessory slots (empty slot pictures)
	armour_helmet = "rbxassetid://75515295779197",
	armour_chest = "rbxassetid://99643852695954",
	armour_boots = "rbxassetid://81152330344730",
	acc_pin = "rbxassetid://135760305235171",
	acc_charm = "rbxassetid://94569660209484",
	acc_back = "rbxassetid://104915184023894",

	-- Armour sets (Velocity Equipment System)
	city_cap = "rbxassetid://109378459519453",
	city_jacket = "rbxassetid://112701503488606",
	city_sneakers = "rbxassetid://94618018363395",
	street_hood = "rbxassetid://132544810872322",
	street_hoodie = "rbxassetid://79909314165859",
	street_boots = "rbxassetid://106694275123241",
	retro_helmet = "rbxassetid://116035115016703",
	retro_torso = "rbxassetid://140321346350001",
	retro_boots = "rbxassetid://94343597995055",
	noob_cap = "rbxassetid://87389758538358",
	noob_shirt = "rbxassetid://89309806658267",
	noob_shoes = "rbxassetid://75153175002771",
	guest_mask = "rbxassetid://84588447220488",
	guest_jacket = "rbxassetid://100361763946040",
	guest_boots = "rbxassetid://113431179216190",

	-- City accessories
	city_delivery_bag = "rbxassetid://121419659687359",
	city_courier_watch = "rbxassetid://90063828724282",
	city_sunglasses = "rbxassetid://127002316145818",
	city_lanyard = "rbxassetid://122473895746725",
	city_wristband = "rbxassetid://92201235135800",
	city_metro_card = "rbxassetid://72271713351547",

	-- Retro accessories
	retro_cola = "rbxassetid://137084743816449",
	retro_brick_badge = "rbxassetid://86732683156412",
	retro_tix_coin = "rbxassetid://72768932401522",
	retro_visor = "rbxassetid://118450294183602",
	retro_tool_belt = "rbxassetid://115897587298135",
	retro_obby_medal = "rbxassetid://134422750518896",
	retro_cursor_pin = "rbxassetid://117134548398468",
	retro_orange_shades = "rbxassetid://129383508444482",
	retro_studs_chain = "rbxassetid://122501259905486",
	retro_guest_pin = "rbxassetid://101317196386084",

	-- Core charms
	charm_ruby = "rbxassetid://88961146142237",
	charm_sapphire = "rbxassetid://125709991137070",
	charm_amethyst = "rbxassetid://102163252051729",
	charm_diamond = "rbxassetid://72746534869074",

	-- Cosmetic accessories
	cos_party_hat = "rbxassetid://107444261397038",
	cos_traffic_cone = "rbxassetid://75184419198081",
	cos_bunny_ears = "rbxassetid://101148712059260",
	cos_pizza_pin = "rbxassetid://75536071827146",
	cos_paper_crown = "rbxassetid://134155343374482",

	-- Gear tools and menus
	star = "rbxassetid://89612642891877",
	scrap = "rbxassetid://137049297833248",
	reroll = "rbxassetid://72164371515824",
	dismantle = "rbxassetid://77650267214816",
	settings = "rbxassetid://100956196117015",
	-- Faces (the Customise gamepass)
	face_smile = "rbxassetid://71108226166232",
	face_grin = "rbxassetid://91498136206704",
	face_focused = "rbxassetid://115628918190673",
	face_smug = "rbxassetid://101012260412447",
	face_chill = "rbxassetid://126944425319116",
	face_angry = "rbxassetid://110685727344169",

	-- Status effects (game HUD)
	fx_poison = "rbxassetid://119530261579977",
	fx_fire = "rbxassetid://136482194676432",
	fx_frost = "rbxassetid://138663823094508",
	fx_stun = "rbxassetid://120671177050389",
	fx_bleed = "rbxassetid://101998296925132",
	fx_weak = "rbxassetid://83587664914259",
	fx_party = "rbxassetid://92943489664793",
	fx_regen = "rbxassetid://107998678815119",
	fx_resist = "rbxassetid://106057653078641",
	fx_strength = "rbxassetid://137173986443340",
	fx_speed = "rbxassetid://138443009878405",
	fx_rage = "rbxassetid://92075159478442",
	fx_link = "rbxassetid://91270742028549",

	-- Game HUD
	i_parry = "rbxassetid://88183805277474",
	i_skull = "rbxassetid://83896109330806",
	i_gate = "rbxassetid://74423374557298",
	i_boss = "rbxassetid://108537646573446",

	-- Logo
	logo_velocity = "rbxassetid://93456157990933",
}

-- The icon for Name, or Fallback if it hasn't been filled in.
function UIIcons.Get(Name: string, Fallback: string?): string
	local Id = UIIcons[Name]
	if type(Id) == "string" and Id ~= "" then
		return Id
	end
	return Fallback or ""
end

return UIIcons
