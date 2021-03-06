local votes = 0
local starting_game = false
local ingame = false
local force_init_warning = false
local grace = false
local countdown = false

local registrants = {}
local voters = {}
local currGame = {}

--[[ 
Sequence number of current round, will be incremented each round.
Used to determine whether minetest.after calls are still valid or should be discarded. 
]]
local gameSequenceNumber = 0	
local voteSequenceNumber = 0

local spots_shuffled = {}

local timer_hudids = {}

local timer = nil
local timer_updated = nil
local timer_mode = nil	-- nil, "vote", "starting", "grace"

local maintenance_mode = false		

minetest.setting_set("enable_damage", "false")
survival.disable()

hb.register_hudbar("votes", 0xFFFFFF, "Votes", { bar = "hungry_games_votebar.png", icon = "hungry_games_voteicon.png" }, 0, 0, false)

local update_timer_hud = function(text)
	local players = minetest.get_connected_players()
	for i=1,#players do
		local player = players[i]
		local name = player:get_player_name()
		if timer_hudids[name] ~= nil then
			player:hud_change(timer_hudids[name], "text", text)
		end
	end
end

local set_timer = function(args)
	local gsn = args[1]
	local name = args[2]
	local time = args[3]
	
	if gsn ~= gameSequenceNumber then
		return
	end
	
	timer_mode = name
	timer = time
	timer_updated = nil
end

local unset_timer = function()
	timer_mode = nil
	timer_updated = nil
	update_timer_hud("")
end

--[[
Ends the grace period. 

Enables pvp, informs players that the grace period is over and calls refill_chests
such that chests will be filled in hungry_games.chest_refill_interval
seconds.
]]
local end_grace = function(gsn)
	if ingame and gsn == gameSequenceNumber then
		minetest.setting_set("enable_pvp", "true")
		minetest.chat_send_all("Grace period over!")
		grace = false
		minetest.sound_play("hungry_games_grace_over")
	end
end

--[[
Returns the number of votes currently needed to start a game.
]]
local needed_votes = function()
	local num = #minetest.get_connected_players()
	if num <= hungry_games.vote_unanimous then
		return num
	else
		return math.ceil(num*hungry_games.vote_percent)
	end
end

--[[
Updates the vote hudbar. 
]]
local update_votebars = function()
	local players = minetest.get_connected_players()
	for i=1, #players do
		hb.change_hudbar(players[i], "votes", votes, needed_votes())
		if #players < 2 or ingame or starting_game or maintenance_mode then
			hb.hide_hudbar(players[i], "votes")
		else
			hb.unhide_hudbar(players[i], "votes")
		end
	end
end

--[[
Clears a player's inventory completely (including crafting and armor 
inventories) and drops their items.

If the clear argument is set to true, items will be removed from the player's
inventory, but not dropped on the ground.
]]
local drop_player_items = function(playerName, clear)
	if not playerName then
		return
	end

	local player = minetest.get_player_by_name(playerName)
	
	if not player then 
		return
	end
	
	local pos = player:getpos()
	local inv = player:get_inventory()

	if not clear then
		--Drop main and craft inventories
		local inventoryLists = {inv:get_list("main"), inv:get_list("craft")}
		
		for _,inventoryList in pairs(inventoryLists) do
			for i,v in pairs(inventoryList) do
				local obj = minetest.env:add_item({x=math.floor(pos.x)+math.random(), y=pos.y, z=math.floor(pos.z)+math.random()}, v)
				if obj ~= nil then
					obj:get_luaentity().collect = true
					local x = math.random(1, 5)
					if math.random(1,2) == 1 then
						x = -x
					end
					local z = math.random(1, 5)
					if math.random(1,2) == 1 then
						z = -z
					end
					obj:setvelocity({x=1/x, y=obj:getvelocity().y, z=1/z})
				end
			end
		end
	end

	inv:set_list("craft", {})
	inv:set_list("main", {})

	--Drop armor inventory
	local armor_inv = minetest.get_inventory({type="detached", name=player:get_player_name().."_armor"})
	local player_inv = player:get_inventory()
	local armorTypes = {"head", "torso", "legs", "feet", "shield"}
	for i,stackName in ipairs(armorTypes) do
		if not clear then
			local stack = inv:get_stack("armor_" .. stackName, 1)
			local x = math.random(0, 6)/3
			local z = math.random(0, 6)/3
			pos.x = pos.x + x
			pos.z = pos.z + z
			minetest.env:add_item(pos, stack)
			pos.x = pos.x - x
			pos.z = pos.z - z
		end
		armor_inv:set_stack("armor_"..stackName, 1, nil)
		player_inv:set_stack("armor_"..stackName, 1, nil)
	end
	armor:set_player_armor(player)
	return
end

--[[ 
Puts the game into sudden death.

Informs all players of the sudden death via a chat message, empties all
player inventories and chests and gives each player the contents of 
hungry_games.sudden_death_items.
]]
local sudden_death = function(gsn)
	if gsn ~= gameSequenceNumber then
		return
	else
		minetest.chat_send_all("Sudden Death!")
		for playerName,_ in pairs(currGame) do
			drop_player_items(playerName, true)
			local inv = minetest.get_player_by_name(playerName):get_inventory()
			inv:set_list("main", hungry_games.sudden_death_items)
		end
		minetest.sound_play("hungry_games_sudden_death")
	end
end

--[[
Stops the game immediately.
]]
local stop_game = function()
	for _,player in ipairs(minetest.get_connected_players()) do
		local name = player:get_player_name()
		local privs = minetest.get_player_privs(name)
		player:set_nametag_attributes({color = {a=255, r=255, g=255, b=255}})
		privs.fast = nil
		privs.fly = nil
		privs.interact = nil
		minetest.set_player_privs(name, privs)
		drop_player_items(name, true)
		player:set_hp(20)
		spawning.spawn(player, "lobby")
	end
	registrants = {}
	currGame = {}
	ingame = false
	grace = false
	countdown = false
	starting_game = false
	force_init_warning = false
	survival.disable()
	minetest.setting_set("enable_damage", "false")
	unset_timer()
end

--[[
Checks if the current game has been won. If so, announces the winner's 
name and calls stop_game.
]]
local check_win = function()
	if ingame then
		local count = 0
		for _,_ in pairs(currGame) do
			count = count + 1
		end
		if count <= 1 then
			local winnerName
			for playerName,_ in pairs(currGame) do
				local winnerName = playerName
				minetest.chat_send_player(winnerName, "You won!")
				minetest.chat_send_all("The Hungry Games are now over, " .. winnerName .. " was the winner.")
				minetest.sound_play("hungry_games_victory")
			end
		
			local players = minetest.get_connected_players()
			for _,player in ipairs(players) do
				local name = player:get_player_name()
				local privs = minetest.get_player_privs(name)
				minetest.set_player_privs(name, privs)
			end
			
			stop_game()
			update_votebars()
		end
	elseif starting_game then
		local players = minetest.get_connected_players()
		if #players < 2 then
			if #players == 1 then
				local winnerName = players[1]:get_player_name()
				minetest.chat_send_player(winnerName, "You won! (All other players have left.)")
				minetest.sound_play("hungry_games_victory")

				local privs = minetest.get_player_privs(winnerName)
				minetest.set_player_privs(winnerName, privs)
			end
			stop_game()
		end
	end
end


--[[
Returns the number of spawn points available for players to spawn in.
]]
local get_spots = function()
	i = 1
	while true do
		if spawning.is_spawn("player_"..i) then
			i = i + 1
		else
			return i - 1
		end
	end
end

--[[
Sets the specified player's thirst and hunger to 0 and health to 20.
]]
local reset_player_state = function(player)
	local name = player:get_player_name()
	player:set_hp(20)
	survival.reset_player_state(name, "hunger")
	survival.reset_player_state(name, "thirst")
end

minetest.register_globalstep(function(dtime)
	if timer_mode ~= nil then
		timer = timer - dtime
		if timer_updated == nil or timer_updated - timer >= 1 then
			timer_updated = timer
			if timer >= 0 then
				if timer_mode == "grace" then
					update_timer_hud(string.format("Grace period: %ds", math.ceil(timer)))
				elseif timer_mode == "vote" then
					update_timer_hud(string.format("Next round in max. %ds.", math.ceil(timer)))
				elseif timer_mode == "starting" then
					update_timer_hud(string.format("Game starts in %ds.", math.ceil(timer)))
				elseif timer_mode == "chest_refill" then
					update_timer_hud(string.format("%ds to chest refill", math.ceil(timer)))
				elseif timer_mode == "sudden_death" then
					update_timer_hud(string.format("%ds to sudden death", math.ceil(timer)))
				else
					unset_timer()
				end
			else
				unset_timer()
			end
		end
	end
end)

--[[
Refills all chests.

Informs all players of the chest refill and then calls random_chests.refill.
]]
local refill_chests = function(gsn)
	if gsn ~= gameSequenceNumber then
		return
	else
		random_chests.refill()
		minetest.chat_send_all("Chests have been refilled")
	end
end

--[[
Forces a draw.

Informs all players of the draw and the players remaining ingame via a 
chat message and calls stop_game.
]]
local force_draw = function(gsn)
	if gsn ~= gameSequenceNumber or not ingame then
		return
	else
		minetest.chat_send_all("The game has ended in a draw!")
		local playersRemaining = ""
		for playerName,_ in pairs(currGame) do
			playersRemaining = playersRemaining .. playerName .. " "
		end
		minetest.chat_send_all("Players remaining in game were: " .. playersRemaining)
	end
	stop_game()
	return
end

--[[
Starts the grace period.

Enables damage and sets a timer informing players of the time remaining 
until the end of the grace period. Also sets up chest refilling and 
the sudden death (if set).

Called when the countdown initiated by start_game is finished. 
]]
local start_game_now = function(input)
	local contestants = input[1]
	local gsn = input[2]
	if gsn ~= gameSequenceNumber or not starting_game then
		return false
	end
	for i,player in ipairs(contestants) do
		local name = player:get_player_name()
		if minetest.get_player_by_name(name) then
			currGame[name] = true
			player:set_nametag_attributes({color = {a=255, r=0, g=255, b=0}})
			local privs = minetest.get_player_privs(name)	
			privs.fast = nil
			privs.fly = nil
			privs.interact = true
			minetest.set_player_privs(name, privs)
			minetest.after(0.1, function(table)
				local player = table[1]
				local i = table[2]
				local gsn = table[3]
				if gsn ~= gameSequenceNumber then
					return
				end
				local name = player:get_player_name()
				if spawning.is_spawn("player_"..i) then
					spawning.spawn(player, "player_"..i)
				end
			end, {player, spots_shuffled[i], gameSequenceNumber})
		end
	end
	
	--Set up chest refilling and sudden death
	if hungry_games.chest_refill_interval > 0 then --Chest refilling enabled
		local numRefills;
		if hungry_games.sudden_death_time > 0 then
			numRefills = (hungry_games.sudden_death_time / hungry_games.chest_refill_interval) - 1
			minetest.after(hungry_games.grace_period + (hungry_games.chest_refill_interval*numRefills), set_timer, {gameSequenceNumber, "sudden_death", hungry_games.sudden_death_time - hungry_games.chest_refill_interval*numRefills})
			minetest.after(hungry_games.grace_period + hungry_games.sudden_death_time, sudden_death, gameSequenceNumber)
		else
			numRefills = (hungry_games.hard_time_limit / hungry_games.chest_refill_interval) - 1
		end
		
		for i=1,numRefills do
			minetest.after(hungry_games.grace_period+hungry_games.chest_refill_interval*i, refill_chests, gameSequenceNumber)
			minetest.after(hungry_games.grace_period+hungry_games.chest_refill_interval*(i-1), set_timer, {gameSequenceNumber, "chest_refill", hungry_games.chest_refill_interval})
		end
	else --Chest refilling disabled
		if hungry_games.sudden_death_time > 0 then
			minetest.after(hungry_games.grace_period, set_timer, {gameSequenceNumber, "sudden_death", hungry_games.sudden_death_time})
			minetest.after(hungry_games.grace_period + hungry_games.sudden_death_time, sudden_death, gameSequenceNumber)
		end
	end
	assert(type(hungry_games.hard_time_limit) == "number" and hungry_games.hard_time_limit > 0, "Invalid value for hungry_games.hard_time_limit. Must be a number > 0")
	minetest.after(hungry_games.hard_time_limit, force_draw, gameSequenceNumber)
	
	minetest.chat_send_all("The Hungry Games have begun!")
	if hungry_games.grace_period > 0 then
		if hungry_games.grace_period >= 60 then
			minetest.chat_send_all("You have "..(dump(hungry_games.grace_period)/60).."min until grace period ends!")
		else
			minetest.chat_send_all("You have "..dump(hungry_games.grace_period).."s until grace period ends!")
		end
		grace = true
		set_timer({gameSequenceNumber, "grace", hungry_games.grace_period})
		minetest.setting_set("enable_pvp", "false")
		minetest.after(hungry_games.grace_period, end_grace, gameSequenceNumber)
	else
		grace = false
		unset_timer()
	end
	minetest.setting_set("enable_damage", "true")
	survival.enable()
	votes = 0
	voters = {}
	update_votebars()
	ingame = true
	countdown = false
	starting_game = false
	minetest.sound_play("hungry_games_start")
	return true
end

--[[
Starts the game.

Spawns all players in random spawnpoints, starts a countdown that lasts
hungry_games.countdown seconds during which players cannot leave their
spawnpoints and calls start_game_now after the countdown has finished.
]]
local start_game = function()
	if starting_game or ingame then
		return
	end
	gameSequenceNumber = gameSequenceNumber + 1
	starting_game = true
	grace = false
	countdown = true
	votes = 0
	voters = {}
	update_votebars()
	
	local i = 1
	if hungry_games.countdown > 8.336 then
		minetest.after(hungry_games.countdown-8.336, function(gsn)
			if gsn == gameSequenceNumber and starting_game then
				minetest.sound_play("hungry_games_prestart")
			end
		end, gameSequenceNumber)
	end
	
	random_chests.clear()
	random_chests.refill()
	
	--Find out how many spots there are to spawn
	local nspots = get_spots()
	local diff =  nspots-table.getn(registrants)
	local contestants = {}

	-- Shuffle players
	local players = minetest.get_connected_players()
	local players_shuffled = {}
	local shuffle_free = {}
	for j=1,#players do
		shuffle_free[j] = j
	end
	for j=1,#players do
		local rnd = math.random(1, #shuffle_free)
		players_shuffled[j] = players[shuffle_free[rnd]]
		table.remove(shuffle_free, rnd)
	end

	-- Shuffle spots as well
	shuffle_free = {}
	spots_shuffled = {}
	for j=1,nspots do
		shuffle_free[j] = j
	end
	for j=1,nspots do
		local rnd = math.random(1, #shuffle_free)
		spots_shuffled[j] = shuffle_free[rnd]
		table.remove(shuffle_free, rnd)
	end

	-- Spawn players
	for p=1,#players_shuffled  do
		local player = players_shuffled[p]
		if diff > 0 then
			registrants[player:get_player_name()] = true
			diff = diff - 1
		end
		drop_player_items(player:get_player_name(), true)
		minetest.after(0.1, function(list)
			local player = list[1]
			local spawn_id = list[2]
			local gsn = list[3]
			if gsn ~= gameSequenceNumber or not starting_game then
				return
			end
			local name = player:get_player_name()
			if registrants[name] == true and spawn_id ~= nil and spawning.is_spawn("player_"..spawn_id) then
				table.insert(contestants, player)
				spawning.spawn(player, "player_"..spawn_id)
				reset_player_state(player)
				minetest.chat_send_player(name, "Get ready to fight!")
			else
				minetest.chat_send_player(name, "There are no spots for you to spawn!")
			end
		end, {player, spots_shuffled[i], gameSequenceNumber})
		if registrants[player:get_player_name()] then i = i + 1 end
	end
	minetest.setting_set("enable_damage", "false")
	if hungry_games.countdown > 0 then
		set_timer({gameSequenceNumber, "starting", hungry_games.countdown})
		for i=1, (hungry_games.countdown-1) do
			minetest.after(i, function(list)
				local contestants = list[1]
				local i = list[2]
				local gsn = list[3]
				if gsn ~= gameSequenceNumber or not starting_game then
					return
				end
				local time_left = hungry_games.countdown-i
				if time_left%4==0 and time_left >= 16 then
					minetest.sound_play("hungry_games_starting_drum")
				end
				for i,player in ipairs(contestants) do
					minetest.after(0.1, function(table)
						local player = table[1]
						local i = table[2]
						local name = player:get_player_name()
						if spawning.is_spawn("player_"..i) then
							spawning.spawn(player, "player_"..i)
						end
					end, {player, spots_shuffled[i]})
				end
			end, {contestants,i,gameSequenceNumber})
		end
		minetest.after(hungry_games.countdown, start_game_now, {contestants,gameSequenceNumber})
	else
		start_game_now({contestants,gameSequenceNumber})
	end
end

--[[
Starts the game if the number of votes is sufficent to start a game.

Gets the return value of needed_votes and compares it to the current amount
of votes cast. If the return value of needed_votes > current amount of 
votes, calls start_game.
]]
local check_votes = function()
	if not ingame then
		local players = minetest.get_connected_players()
		local num = table.getn(players)
		if num > 1 and (votes >= needed_votes()) then
			start_game()
			return true
		end
	end
	return false
end

--[[dieplayer
Handles everything when a player's dies.

Drops the player's items, if a game is currently underway, spawns player
in the lobby and calls check_win.
]]
minetest.register_on_dieplayer(function(player)
	local playerName = player:get_player_name()	
	local pos = player:getpos()
	
	local count = 0
	for _,_ in pairs(currGame) do
		count = count + 1
	end
	count = count - 1
	
	if ingame and currGame[playerName] and count ~= 1 then
		player:set_nametag_attributes({color = {a=255, r=255, g=0, b=0}})
		minetest.chat_send_all(playerName .. " has died! Players left: " .. tostring(count))		
	end	

	drop_player_items(playerName)
	currGame[playerName] = nil
	check_win()

   	local privs = minetest.get_player_privs(playerName)
	if privs.interact then
		minetest.sound_play("hungry_games_death", {pos = pos})
	end
	if privs.interact or privs.fly then
   		if privs.interact and hungry_games.spectate_after_death then 
		   	privs.fast = true
			privs.fly = true
			privs.interact = nil
			minetest.set_player_privs(playerName, privs)
			minetest.chat_send_player(playerName, "You are now spectating")
		end
   	end
end)

minetest.register_on_respawnplayer(function(player)
	player:set_hp(20)
	local name = player:get_player_name()
   	local privs = minetest.get_player_privs(name)
   	if hungry_games.spectate_after_death then
		spawning.spawn(player, "spawn")
	else
		spawning.spawn(player, "lobby")
	end
	return true
end)

minetest.register_on_joinplayer(function(player)
	local name = player:get_player_name()
   	local privs = minetest.get_player_privs(name)
	privs.vote = true
	privs.register = true
	privs.fast = nil
	privs.fly = nil
	privs.interact = nil
	minetest.set_player_privs(name, privs)

	if ingame then
		player:set_nametag_attributes({color = {a=255, r=255, g=0, b=0}})
		if hungry_games.spectate_after_death then
			minetest.chat_send_player(name, "You are now spectating")
		end
	end

	spawning.spawn(player, "lobby")
	reset_player_state(player)
	hb.init_hudbar(player, "votes", votes, needed_votes(), (maintenance_mode or ingame or starting_game or #minetest.get_connected_players() < 2))
	update_votebars()
	timer_hudids[name] = player:hud_add({
		hud_elem_type = "text",
		position = { x=0.5, y=0 },
		offset = { x=0, y=20 },
		direction = 0,
		text = "",
		number = 0xFFFFFF,
		alignment = {x=0,y=0},
		size = {x=100,y=24},
	})
end)

minetest.register_on_newplayer(function(player)
	local name = player:get_player_name()
   	local privs = minetest.get_player_privs(name)
	privs.register = true
	minetest.set_player_privs(name, privs)

end)

minetest.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	drop_player_items(player:get_player_name())
	currGame[name] = nil
	timer_hudids[name] = nil
   	local privs = minetest.get_player_privs(name)
	if voters[name] and votes > 0 then
		votes = votes - 1
		voters[name] = nil
	end
	if votes < 2 and timer_mode == "vote" then
		unset_timer()
		minetest.chat_send_all("Automatic game start has been aborted; there are less than 2 votes.")
		force_init_warning = false
	end
	update_votebars()
	if registrants[name] then registrants[name] = nil end
	minetest.after(1, function()
		check_votes()
		check_win()
	end)
end)

minetest.register_privilege("hg_admin", "Hungry Games Admin.")
minetest.register_privilege("hg_maker", "Hungry Games Map Maker.")
minetest.register_privilege("vote", "Privilege to vote.")
minetest.register_privilege("register", "Privilege to register.")

--Hungry Games Chat Commands.
minetest.register_chatcommand("hg", {
	params = "start | restart | stop | build | [un]set player_<n> | lobby | spawn | maintenance",
	description = "Manage Hungry Games. start: Start Hungry Games; restart: Restart Hungry Games; stop: Abort current game; build: Building mode to set up lobby, arena, etc.; set player_<n>: Set spawn position of player <n> (starting by 1); set lobby: Set spawn position in lobby; set spawn: Set initial spawn position for new players; unset: Like set, but removes spawn position; maintenance: Toggle maintenance mode",
	privs = {hg_admin=true},
	func = function(name, param)
		--Catch param.
		local parms = {}
		repeat
			v, p = param:match("^(%S*) (.*)")
			if p then
				param = p
			end
			if v then
				table.insert(parms,v)
			else
				v = param:match("^(%S*)")
				table.insert(parms,v)
				break
			end
		until false
		local ret
		local num_players  = #minetest.get_connected_players()
		--Restarts/Starts game.
		if parms[1] == "start" then
			if maintenance_mode then
				minetest.chat_send_player(name, "This server is currently in maintenance mode, no games can be started while it is in maintenance mode. Use \"/hg maintenance off\" to disable it.")
				return
			end
			if num_players < 2 then
				minetest.chat_send_player(name, "At least 2 players are needed to start a new round.")
				return
			end
			if get_spots() < 2 then
				minetest.chat_send_player(name, "There are less than 2 active spawn positions. Please set new spawn positions with \"/hg set player_#\".")
				return
			end
			local nostart
			if starting_game or ingame then
				nostart = true
			end
			if nostart then
				minetest.chat_send_player(name, "There is already a game running!")
			end
			ret = start_game()
			if ret == false then
				minetest.chat_send_player(name, "The game could not be started.")
			end
		elseif parms[1] == "restart" or parms[1] == 'r' then
			if maintenance_mode then
				minetest.chat_send_player(name, "This server is currently in maintenance mode, no games can be started while it is in maintenance mode. Use \"/hg maintenance off\" to disable it.")
				return
			end
			if starting_game or ingame then
				stop_game()
			end
			if num_players < 2 then
				minetest.chat_send_player(name, "At least 2 players are needed to start a new round.")
				return
			end
			if get_spots() < 2 then
				minetest.chat_send_player(name, "There are less than 2 active spawn positions. Please set new spawn positions with \"/hg set player_#\".")
				return
			end
			ret = start_game()
			if ret == false then
				minetest.chat_send_player(name, "The game could not be restarted.")
			end

		--Stops Game.
		elseif parms[1] == "stop" then
			if starting_game or ingame then
				stop_game()
				update_votebars()
				minetest.chat_send_all("The Hunger Games have been stopped!")
			else
				minetest.chat_send_player(name, "The game has already been stopped.")
			end
		elseif parms[1] == "build" then
			if not ingame then
				local privs = minetest.get_player_privs(name)
				privs.interact = true
				privs.fly = true
				privs.fast = true
				minetest.set_player_privs(name, privs)

				minetest.chat_send_player(name, "You now have interact and fly/fast!")
			else
				minetest.chat_send_player(name, "You cant build while in a match!")
				return
			end
		elseif parms[1] == "set" then
			if parms[2] ~= nil and (parms[2] == "spawn" or parms[2] == "lobby" or parms[2]:match("player_%d")) then
				local pos = {}
				if parms[3] and parms[4] and parms[5] then
					pos = {x=parms[3],y=parms[4],z=parms[5]}
					spawning.set_spawn(parms[2], pos)
				else
					pos = minetest.env:get_player_by_name(name):getpos()
					spawning.set_spawn(parms[2], pos)
				end
				minetest.chat_send_player(name, parms[2].." has been set to "..pos.x.." "..pos.y.." "..pos.z)
			else
				minetest.chat_send_player(name, "Set what?")
			end
		elseif parms[1] == "unset" then
			if parms[2] ~= nil and (parms[2] == "spawn" or parms[2] == "lobby" or parms[2]:match("player_%d")) then
				spawning.unset_spawn(parms[2])
				minetest.chat_send_player(name, parms[2].." has been unset.")
			else
				minetest.chat_send_player(name, "Unset what?")
			end
		elseif parms[1] == "maintenance" then
			local maintenance_action
			if parms[2] ~= nil then
				if parms[2] == "on" then
					maintenance_action = true
				elseif parms[2] == "off" then
					maintenance_action = false
				end
			else
				maintenance_action = not maintenance_mode
			end

			if maintenance_action == true then
				stop_game()
				votes = 0
				voters = {}
				maintenance_mode = true
				update_votebars()
				minetest.chat_send_all("This server is now in maintenance mode. The Hungry Games have been suspended until further notice.")
			elseif maintenance_action == false then
				votes = 0
				voters = {}
				maintenance_mode = false
				update_votebars()
				minetest.chat_send_all("Server maintenance finished. The Hungry Games can begin!")
			else
				minetest.chat_send_player(name, "Invalid command syntax! Syntax: \"/hg maintenance [on|off]\"")
			end
		else
			minetest.chat_send_player(name, "Unknown subcommand! Use /help hg for a list of available subcommands.")
		end
	end,
})

minetest.register_chatcommand("vote", {
	description = "Vote to start the Hungry Games.",
	privs = {vote=true},
	func = function(name, param)
		if maintenance_mode then
			minetest.chat_send_player(name, "This server is currently in maintenance mode, no games can be started at the moment. Please come back later when the server maintenance is over.")
			return
		end
		local players = minetest.get_connected_players()
		local num = #players
		if num < 2 then
			minetest.chat_send_player(name, "At least 2 players are needed to start a new round.")
			return
		end
		if get_spots() < 2 then
			minetest.chat_send_player(name, "Spawn positions haven't been set yet. The game can not be started at the moment.")
			return
		end
		if not ingame and not starting_game then
			if voters[name] ~= nil then
				minetest.chat_send_player(name, "You already have voted.")
				return
			end
			voters[name] = true
			votes = votes + 1
			update_votebars()
			minetest.chat_send_all(name.. " has voted to begin! Votes so far: "..votes.."; Votes needed: "..needed_votes())

			local cv = check_votes()
			if votes > 1 and force_init_warning == false and cv == false and hungry_games.vote_countdown ~= nil then
				minetest.chat_send_all("The match will automatically be initiated in " .. math.floor(hungry_games.vote_countdown/60) .. " minutes " .. math.fmod(hungry_games.vote_countdown, 60) .. " seconds.")
				force_init_warning = true
				set_timer({gameSequenceNumber, "vote", hungry_games.vote_countdown})
				voteSequenceNumber = voteSequenceNumber + 1
				minetest.after(hungry_games.vote_countdown, function (gsn, vsn)
					if not (starting_game or ingame and gsn == gameSequenceNumber) and timer_mode == "vote" and voteSequenceNumber == vsn then
						start_game()
					end
				end, gameSequenceNumber, voteSequenceNumber)
			end
		else
			minetest.chat_send_player(name, "Already ingame!")
			return
		end
	end,
})

minetest.register_chatcommand("register", {
	description = "Register to take part in the Hungry Games",
	privs = {register=true},
	func = function(name, param)
		--Catch param.
		local parms = {}
		repeat
			v, p = param:match("^(%S*) (.*)")
			if p then
				param = p
			end
			if v then
				table.insert(parms,v)
			else
				v = param:match("^(%S*)")
				table.insert(parms,v)
				break
			end
		until false
		if table.getn(registrants) < get_spots() then
			registrants[name] = true
			minetest.chat_send_player(name, "You have registered!")
		else
			minetest.chat_send_player(name, "Sorry! There are no spots left for you to spawn.")
		end
	end,
})

minetest.register_chatcommand("build", {
	description = "Give yourself interact",
	privs = {hg_maker=true},
	func = function(name, param)
		if not ingame then
				local privs = minetest.get_player_privs(name)
				privs.interact = true
				privs.fly = true
				privs.fast = true
				minetest.set_player_privs(name, privs)

				minetest.chat_send_player(name, "You now have interact and fly/fast!")
		else
			minetest.chat_send_player(name, "You cant build while in a match!")
			return
		end
	end,
})

minetest.register_tool(":default:admin_pick", {
	description = "Admin Pickaxe",
	inventory_image = "default_tool_mesepick.png",
	tool_capabilities = {
		full_punch_interval = 0.65,
		max_drop_level=3,
		groupcaps={
			crumbly = {times={[1]=0.5, [2]=0.5, [3]=0.5}, uses=0, maxlevel=3},
			cracky = {times={[1]=0.5, [2]=0.5, [3]=0.5}, uses=0, maxlevel=3},
			snappy = {times={[1]=0.5, [2]=0.5, [3]=0.5}, uses=0, maxlevel=3},
			choppy = {times={[1]=0.5, [2]=0.5, [3]=0.5}, uses=0, maxlevel=3},
			oddly_breakable_by_hand = {times={[1]=0.5, [2]=0.5, [3]=0.5}, uses=0, maxlevel=3},
		}
	},
})
