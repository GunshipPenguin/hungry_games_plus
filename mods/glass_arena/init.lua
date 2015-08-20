local arena_size = 200
arena_size = arena_size/2
local replace = {}

glass_arena = {}

--Set size of the arena
function glass_arena.set_size(n)
	arena_size = (n/2)
end

--Set arena texture
function glass_arena.set_texture(name)
	minetest.override_item("glass_arena:wall", {
		tiles = {name},
	})
end


--Node defs
minetest.register_node("glass_arena:wall",{
	drawtype = "glasslike",
	tiles = {"default_glass.png"},
	inventory_image = minetest.inventorycube("default_glass.png"),
	paramtype = "light",
	sunlight_propagates = true,
	is_ground_content = false,
	diggable = false,
	drop = "",
	groups = {not_in_creative_inventory=1},
})

minetest.register_node("glass_arena:wall_middle",{
	drawtype = "glasslike",
	tiles = {"blank.png"},
	inventory_image = minetest.inventorycube("default_glass.png"),
	paramtype = "light",
	sunlight_propagates = true,
	is_ground_content = false,
	diggable = false,
	drop = "",
	groups = {not_in_creative_inventory=1},
})

minetest.register_node("glass_arena:wall_end",{
	drawtype = "glasslike",
	tiles = {"blank.png"},
	inventory_image = minetest.inventorycube("default_glass.png"),
	paramtype = "light",
	sunlight_propagates = true,
	is_ground_content = false,
	diggable = false,
	drop = "",
	groups = {not_in_creative_inventory=1},
})

--Teleport player within boundary
glass_arena.rise = function(player)
	local pos = player:getpos()
	if minetest.get_node({x=pos.x,y=pos.y+1,z=pos.z}) == "air" then
		return
	end
	for y=0, 100 do
		local node = minetest.get_node({x=pos.x,y=y,z=pos.z})
		if node.name == "ignore" then
			player:setpos({x=pos.x,y=pos.y+y+1,z=pos.z})
			minetest.after(2, glass_arena.rise, player)
			return
		end
		if minetest.get_node_light({x=pos.x,y=y,z=pos.z}, 0.5) > 5 then
			if node.name == "air" then
				player:setpos({x=pos.x,y=pos.y+y+1,z=pos.z})
				return
			end
			if node.name == "default:water_source" then
				player:setpos({x=pos.x,y=pos.y+y+1,z=pos.z})
				return
			end
		end
	end
	player:setpos({x=pos.x,y=pos.y+200,z=pos.z})
end

function glass_arena.teleport(player)
	player:setpos({x=math.random(-arena_size+1,arena_size-1),y=0,z=math.random(-arena_size+1,arena_size-1)})
	minetest.after(1, glass_arena.rise, player)
	return true
end

function glass_arena.replace(list)
	replace = list
end

--[[
local function table_find(t,v)
	for i = 1,#t do
		if t[i] == v then
			return true
		end
	end
	return false
end
--]]

local function mid_pos(pos)
	for a,b in pairs({x="z", z="x"}) do
		if math.abs(pos[a]) == arena_size+1
		and math.abs(pos[b]) <= arena_size+1 then
			return true
		end
	end
end

local function should_replace(pos)
	if not mid_pos(pos) then
		return
	end
	local name = minetest.get_node(pos).name
	if name == "glass_arena:wall_middle" then
		return
	end
	local def = minetest.registered_nodes[name]
	if not def then
		return
	end
	return def.drawtype and def.drawtype ~= "normal"
end

--Regenerate walls if pieces are missing
minetest.register_abm({
    nodenames = {"glass_arena:wall_middle"},
    neighbors = {"air","default:water_source","default:water_flowing","default:lava_source","default:lava_flowing"},
    interval = 10,
    chance = 1,
    action = function(pos, node, active_object_count, active_object_count_wider)
        local env = minetest.env
     	if should_replace({x=pos.x,y=pos.y+1,z=pos.z}) then
    		env:add_node({x=pos.x,y=pos.y+1,z=pos.z},{name="glass_arena:wall_middle"})
    	end
    	if should_replace({x=pos.x,y=pos.y-1,z=pos.z}) then
    		env:add_node({x=pos.x,y=pos.y-1,z=pos.z},{name="glass_arena:wall_middle"})
    	end
    	if should_replace({x=pos.x+1,y=pos.y,z=pos.z}) then
    		if pos.x == arena_size + 1 then
    			env:add_node({x=pos.x+1,y=pos.y,z=pos.z},{name="glass_arena:wall_end"})
    		elseif pos.x == -arena_size - 1 then
    			env:add_node({x=pos.x+1,y=pos.y,z=pos.z},{name="glass_arena:wall"})
    		else
    			env:add_node({x=pos.x+1,y=pos.y,z=pos.z},{name="glass_arena:wall_middle"})
    		end
    	end
    	if should_replace({x=pos.x-1,y=pos.y,z=pos.z}) then
    		if pos.x == arena_size + 1 then
    			env:add_node({x=pos.x-1,y=pos.y,z=pos.z},{name="glass_arena:wall"})
    		elseif pos.x == -arena_size - 1 then
    			env:add_node({x=pos.x-1,y=pos.y,z=pos.z},{name="glass_arena:wall_end"})
    		else
    			env:add_node({x=pos.x-1,y=pos.y,z=pos.z},{name="glass_arena:wall_middle"})
    		end
    	end
    	if should_replace({x=pos.x,y=pos.y,z=pos.z+1}) then
    		if pos.z == arena_size + 1 then
    			env:add_node({x=pos.x,y=pos.y,z=pos.z+1},{name="glass_arena:wall_end"})
    		elseif pos.z == -arena_size - 1 then
    			env:add_node({x=pos.x,y=pos.y,z=pos.z+1},{name="glass_arena:wall"})
    		else
    			env:add_node({x=pos.x,y=pos.y,z=pos.z+1},{name="glass_arena:wall_middle"})
    		end
    	end
    	if should_replace({x=pos.x,y=pos.y,z=pos.z-1}) then
    		if pos.z == arena_size + 1 then
    			env:add_node({x=pos.x,y=pos.y,z=pos.z-1},{name="glass_arena:wall"})
    		elseif pos.z == -arena_size - 1 then
    			env:add_node({x=pos.x,y=pos.y,z=pos.z-1},{name="glass_arena:wall_end"})
    		else
    			env:add_node({x=pos.x,y=pos.y,z=pos.z-1},{name="glass_arena:wall_middle"})
    		end
    	end
    end,
})


minetest.register_on_generated(function(minp, maxp, seed)
	local database = minetest.registered_nodes
	local replace = replace
	local function should_replace(pos)
		local node = minetest.env:get_node(pos)
		local name = node.name
		if (not replace) or #replace == 0 then
			return true
		else
			for i,v in pairs(replace) do
				if name == v then
					return true
				end
			end
		end
		if not database[name].walkable then
			return true
		else
			return false
		end
	end
	--Speed up generation by checking if this chunk needs to be proccesed.
	if not ((minp.x > arena_size or minp.z > arena_size) or (maxp.x < -arena_size or maxp.z < -arena_size)) and
	   not ((minp.x > -arena_size and maxp.x < arena_size) and (minp.z > -arena_size and maxp.z < arena_size)) then

			--Should make things a bit faster.
			local env = minetest.env
			local gen

			-- Assume X and Z lengths are equal
			local divlen = 16
			local divs = (maxp.x-minp.x);
			local x0 = minp.x
			local z0 = minp.z
			local x1 = maxp.x
			local z1 = maxp.z
			local y0 = minp.y

			--Loop through chunk.
			for j=0,divs do
			for i=0,divs do

			local x = x0+j
			local z = z0+i

			--Build Wall
			if x == arena_size and z <= arena_size and z >= -arena_size then
				for y = 0,divs do
					local pos = {x=x,y=y0+y,z=z}
					if should_replace(pos) then
						env:add_node(pos,{name="glass_arena:wall"})
					end
					pos.x = pos.x + 1
					if should_replace(pos) then
						env:add_node(pos,{name="glass_arena:wall_middle"})
					end
					pos.x = pos.x + 1
					if should_replace(pos) then
						env:add_node(pos,{name="glass_arena:wall_end"})
					end
				end
			end

			if z == arena_size and x <= arena_size and x >= -arena_size then
				for y=0, (maxp.y-minp.y) do

					local y = y0+y

						local pos = {x=x,y=y,z=z}
						if should_replace(pos) then
							env:add_node(pos,{name="glass_arena:wall"})
						end
						pos.z = pos.z + 1
						if should_replace(pos) then
							env:add_node(pos,{name="glass_arena:wall_middle"})
						end
						pos.z = pos.z + 1
						if should_replace(pos) then
							env:add_node(pos,{name="glass_arena:wall_end"})
						end

				end
			end

			if x == -arena_size and z >= -arena_size and z <= arena_size then
				for y=0, (maxp.y-minp.y) do

					local y = y0+y

						local pos = {x=x,y=y,z=z}
						if should_replace(pos) then
							env:add_node(pos,{name="glass_arena:wall"})
						end
						pos.x = pos.x - 1
						if should_replace(pos) then
							env:add_node(pos,{name="glass_arena:wall_middle"})
						end
						pos.x = pos.x - 1
						if should_replace(pos) then
							env:add_node(pos,{name="glass_arena:wall_end"})
						end

				end
			end

			if z == -arena_size and x >= -arena_size and x <= arena_size then
				for y=0, (maxp.y-minp.y) do

					local y = y0+y

						local pos = {x=x,y=y,z=z}
						if should_replace(pos) then
							env:add_node(pos,{name="glass_arena:wall"})
						end
						pos.z = pos.z - 1
						if should_replace(pos) then
							env:add_node(pos,{name="glass_arena:wall_middle"})
						end
						pos.z = pos.z - 1
						if should_replace(pos) then
							env:add_node(pos,{name="glass_arena:wall_end"})
						end

				end
			end

			end
		end
	end
end)

