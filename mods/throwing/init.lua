arrows = {
	{"throwing:arrow", "throwing:arrow_entity"},
	{"throwing:arrow_fire", "throwing:arrow_fire_entity"},
	{"throwing:arrow_teleport", "throwing:arrow_teleport_entity"},
	{"throwing:arrow_dig", "throwing:arrow_dig_entity"},
	{"throwing:arrow_build", "throwing:arrow_build_entity"}
}

local throwing_shoot_arrow = function(itemstack, player)
	for _,arrow in ipairs(arrows) do
		if player:get_inventory():get_stack("main", player:get_wield_index()+1):get_name() == arrow[1] then
			if not minetest.setting_getbool("creative_mode") then
				player:get_inventory():remove_item("main", arrow[1])
			end
			local playerpos = player:getpos()
			local obj = minetest.env:add_entity({x=playerpos.x,y=playerpos.y+1.5,z=playerpos.z}, arrow[2])
			local dir = player:get_look_dir()
			obj:setvelocity({x=dir.x*19, y=dir.y*19, z=dir.z*19})
			obj:setacceleration({x=dir.x*-3, y=-10, z=dir.z*-3})
			obj:setyaw(player:get_look_yaw()+math.pi)
			minetest.sound_play("throwing_sound", {pos=playerpos})
			if obj:get_luaentity().player == "" then
				obj:get_luaentity().player = player
			end
			obj:get_luaentity().node = player:get_inventory():get_stack("main", 1):get_name()
			return true
		end
	end
	return false
end

minetest.register_tool("throwing:bow_wood", {
	description = "Wood Bow",
	inventory_image = "throwing_bow_wood.png",
    stack_max = 1,
	on_use = function(itemstack, user, pointed_thing)
		if throwing_shoot_arrow(itemstack, user, pointed_thing) then
			if not minetest.setting_getbool("creative_mode") then
				itemstack:add_wear(65535/50)
			end
		end
		return itemstack
	end,
})

minetest.register_craft({
	output = 'throwing:bow_wood',
	recipe = {
		{'farming:string', 'group:wood', ''},
		{'farming:string', '', 'group:wood'},
		{'farming:string', 'group:wood', ''},
	}
})

minetest.register_tool("throwing:bow_stone", {
	description = "Stone Bow",
	inventory_image = "throwing_bow_stone.png",
    stack_max = 1,
	on_use = function(itemstack, user, pointed_thing)
		if throwing_shoot_arrow(item, user, pointed_thing) then
			if not minetest.setting_getbool("creative_mode") then
				itemstack:add_wear(65535/100)
			end
		end
		return itemstack
	end,
})

minetest.register_craft({
	output = 'throwing:bow_stone',
	recipe = {
		{'farming:string', 'group:stone', ''},
		{'farming:string', '', 'group:stone'},
		{'farming:string', 'group:stone', ''},
	}
})

minetest.register_tool("throwing:bow_steel", {
	description = "Steel Bow",
	inventory_image = "throwing_bow_steel.png",
    stack_max = 1,
	on_use = function(itemstack, user, pointed_thing)
		if throwing_shoot_arrow(item, user, pointed_thing) then
			if not minetest.setting_getbool("creative_mode") then
				itemstack:add_wear(65535/200)
			end
		end
		return itemstack
	end,
})

minetest.register_craft({
	output = 'throwing:bow_steel',
	recipe = {
		{'farming:string', 'default:steel_ingot', ''},
		{'farming:string', '', 'default:steel_ingot'},
		{'farming:string', 'default:steel_ingot', ''},
	}
})

dofile(minetest.get_modpath("throwing").."/arrow.lua")
dofile(minetest.get_modpath("throwing").."/fire_arrow.lua")
dofile(minetest.get_modpath("throwing").."/teleport_arrow.lua")
dofile(minetest.get_modpath("throwing").."/dig_arrow.lua")
dofile(minetest.get_modpath("throwing").."/build_arrow.lua")

if minetest.setting_get("log_mods") then
	minetest.log("action", "throwing loaded")
end
