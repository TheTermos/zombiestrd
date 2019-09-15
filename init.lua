
local abr = minetest.get_mapgen_setting('active_block_range')

local zombiestrd = {}
--zombiestrd.spawn_rate = 0.4		-- less is more

local abs = math.abs
local pi = math.pi
local floor = math.floor
local random = math.random
local sqrt = math.sqrt
local max = math.max
local min = math.min
local pow = math.pow
local sign = math.sign

local time = os.time

local spawn_rate = 1 - max(min(minetest.settings:get('zombiestrd_spawn_chance') or 0.6,1),0)
local spawn_reduction = minetest.settings:get('zombiestrd_spawn_reduction') or 0.4

local function dot(v1,v2)
	return v1.x*v2.x+v1.y*v2.y+v1.z*v2.z
end

-- find zombie's head center and radius
local function get_head(luaent)
	local pos = luaent.object:get_pos()
	local off = luaent.collisionbox[6]
	local y=pos.y+luaent.collisionbox[5]-off
	pos.y = y
	return pos, off
end

-- custom behaviour
-- makes them move in stimulus' general direction for limited time
local function hq_attracted(self,prty,tpos)
	local timer = time() + random(10,20)	-- zombie's attention span
	local func = function(self)
		if time() > timer then return true end
		if mobkit.is_queue_empty_low(self) and self.isonground then
			local pos = mobkit.get_stand_pos(self)
			if vector.distance(pos,tpos) > 3 then
				mobkit.goto_next_waypoint(self,tpos)
			else
				return true
			end
		end
	end
	mobkit.queue_high(self,func,prty)
end

-- override built in behavior to increase idling time
function mobkit.lq_idle(self,duration)
	local init = true
	local duration=random(10,20)
	local func=function(self)
		if init then 
			mobkit.animate(self,'stand') 
			init=false
		end
		duration = duration-self.dtime
		if duration <= 0 then return true end
	end
	mobkit.queue_low(self,func)
end

local function alert(pos)
	objs = minetest.get_objects_inside_radius(pos,abr*16)
	for _,obj in ipairs(objs) do
		if not obj:is_player() then
			local luaent = obj:get_luaentity()
			if luaent and luaent.name == 'zombiestrd:zombie' then
				hq_attracted(luaent,10,pos)
			end
		end
	end
end

local function zombie_brain(self)
	-- vitals should be checked every step
	if self.hp <= 0 then	
		mobkit.clear_queue_high(self)									-- cease all activity
		mobkit.hq_die(self)												-- kick the bucket
		
		-- workaround for models bottom y being -1. Makes them blink white sometimes, why?
		local props = self.object:get_properties()
		props.collisionbox[2] = props.collisionbox[1]
		self.object:set_properties({collisionbox=props.collisionbox})
		return
	end
	
	if mobkit.timer(self,1) then 			-- decision making needn't happen every engine step
		local prty = mobkit.get_queue_priority(self)
		
		if prty < 50 and self.isinliquid then
			mobkit.hq_liquid_recovery(self,50)
			return
		end
		
		local pos=self.object:get_pos()
		
		if prty < 20 then
			local plyr=mobkit.get_nearby_player(self)
			if plyr then
				local pos2 = plyr:get_pos()
				if prty < 10 then	-- zombie not alert
					if vector.distance(pos,pos2) < self.view_range/3 and											
					(not mobkit.is_there_yet2d(pos,minetest.yaw_to_dir(self.object:get_yaw()),pos2) or 
					vector.length(plyr:get_player_velocity()) > 3) then
						mobkit.make_sound(self,'misc')
						mobkit.hq_hunt(self,20,plyr)
						if random()<=0.5 then alert(pos) end
					end
				else
					if vector.distance(pos,pos2) < self.view_range then
						mobkit.make_sound(self,'misc')
						mobkit.hq_hunt(self,20,plyr)
						if random()<=0.5 then alert(pos) end
					end
				end
			end
		end
		
		if mobkit.is_queue_empty_high(self) then
			mobkit.hq_roam(self,0)
		end
	end
end

-- spawning is too specific to be included in the api, this is an example.
-- a modder will want to refer to specific names according to games/mods they're using 
-- in order for mobs not to spawn on treetops, certain biomes etc.

local function spawnstep(dtime)

	for _,plyr in ipairs(minetest.get_connected_players()) do
		if random()<dtime*0.2 then	-- each player gets a spawn chance every 5s on average
			local vel = plyr:get_player_velocity()
			local spd = vector.length(vel)
			local chance = spawn_rate * 1/(spd*0.75+1)  -- chance is quadrupled for speed=4
			local yaw
			if spd > 1 then
				-- spawn in the front arc
				yaw = minetest.dir_to_yaw(vel) + random()*0.35 - 0.75
			else
				-- random yaw
				yaw = random()*pi*2 - pi
			end
			local pos = plyr:get_pos()
			local dir = vector.multiply(minetest.yaw_to_dir(yaw),abr*16)
			local pos2 = vector.add(pos,dir)
			pos2.y=pos2.y-5
			local height, liquidflag = mobkit.get_terrain_height(pos2,32)
	
			if height and height >= 0 and not liquidflag -- and math.abs(height-pos2.y) <= 30 testin
			and mobkit.nodeatpos({x=pos2.x,y=height-0.01,z=pos2.z}).is_ground_content then

				local objs = minetest.get_objects_inside_radius(pos,abr*16+5)
				local wcnt=0
				local dcnt=0
				for _,obj in ipairs(objs) do				-- count mobs in abrange
					if not obj:is_player() then
						local entity = obj:get_luaentity()
						if entity and entity.name:find('zombiestrd:') then
							chance=chance + (1-chance)*spawn_reduction	-- chance reduced for every mob in range
						end
					end
				end
				if chance < random() then
					pos2.y = height+1.01
					objs = minetest.get_objects_inside_radius(pos2,abr*16-2)
					for _,obj in ipairs(objs) do				-- do not spawn if another player around
						if obj:is_player() then return end
					end
					local obj=minetest.add_entity(pos2,'zombiestrd:zombie')			-- ok spawn it already damnit
--[[					local props = obj:get_properties()
					if #props.textures > 1 then
--						local hp=obj:get_hp()			--wth?
						props.textures[1]=props.textures[math.random(#props.textures)]
						obj:set_properties(props) 
--						obj:set_hp(hp)					--wth?		
					end					--]]
				end
			end
		end
	end
end


minetest.register_globalstep(spawnstep)
-- minetest.register_globalstep(function(dtime)
	-- local spos=mobkit.get_spawn_pos_abr(dtime,5,10,0.5,0.4)
	-- if spos then minetest.add_entity(spos,'zombiestrd:zombie') end
-- end)

minetest.register_on_punchnode(
	function(pos, node, puncher, pointed_thing)
		if random()<=0.1 then
			alert(pos)
		end
	end
)

minetest.register_entity("zombiestrd:zombie",{
											-- common props
	physical = true,
	stepheight = 0.1,			
	collide_with_objects = true,
	collisionbox = {-0.25, -1, -0.25, 0.25, 0.75, 0.25},
	visual = "mesh",
	mesh = "zombie_normal.b3d",
	textures = {"mobs_zombie.png","mobs_zombi2.png"},
	visual_size = {x = 1, y = 1},
	static_save = true,
	timeout = 600,
	on_step = mobkit.stepfunc,	-- required
	on_activate = mobkit.actfunc,		-- required
	get_staticdata = mobkit.statfunc,
											-- api props
	springiness=0,
	buoyancy = 0.75,					-- portion of hitbox submerged
	max_speed = 3,
	jump_height = 1.26,
	view_range = 24,
	lung_capacity = 10, 		-- seconds
	max_hp = 14,
	attack={range=0.3,damage_groups={fleshy=7}},
	animation = {
		walk={range={x=41,y=101},speed=40,loop=true},
		stand={range={x=0,y=40},speed=1,loop=true},
	},
	-- animation = {
		-- walk={
			-- {range={x=41,y=101},speed=30,loop=true},
			-- {range={x=41,y=101},speed=90,loop=true},
			-- },
		-- stand={range={x=0,y=40},speed=1,loop=true},
	-- },
	
	sounds = {
		misc='zombie',
		attack='zombie_bite',
		warn = 'angrydog',
		headhit = 'splash_hit',
		bodyhit = 'body_hit',
		charge = 'zombie_charge',
		},
	armor_groups={immortal=100},
	brainfunc = zombie_brain,
	
	on_punch=function(self, puncher, time_from_last_punch, tool_caps, dir)
		if mobkit.is_alive(self) then
			
			-- head seeking
			if type(puncher)=='userdata' and puncher:is_player() then
				local pp = puncher:get_pos()
				pp.y = pp.y + puncher:get_properties().eye_height	-- pp is now camera pos
				local pm, radius = get_head(self)
				local look_dir = puncher:get_look_dir()
				local head_dir = vector.subtract(pm,pp)
				local dot = dot(look_dir,head_dir)
				local p2 = {x=pp.x+look_dir.x*dot, y=pp.y+look_dir.y*dot, z=pp.z+look_dir.z*dot}
				if vector.distance(pp,pm) <=2 then		-- a way to decrease punch range without dependences
					if mobkit.isnear3d(pm,p2,radius*0.8) and
					time_from_last_punch >= tool_caps.full_punch_interval-0.01 and
					tool_caps.damage_groups.fleshy > 3 then			-- valid headshot
						mobkit.make_sound(self,'headhit')
--						self.object:set_hp(99)
						self.hp=0
					else
						mobkit.make_sound(self,'bodyhit')
						if random()<=0.3 then alert(pp) end
						if mobkit.get_queue_priority(self) < 10 then
							mobkit.make_sound(self,'misc')
							mobkit.hq_hunt(self,10,puncher)
						end
					end
					-- kickback
					local hvel = vector.multiply(look_dir,4)
					self.object:set_velocity({x=hvel.x,y=max(hvel.y,1),z=hvel.z})
				end
			else
				local hvel = vector.multiply(vector.normalize({x=dir.x,y=0,z=dir.z}),4)
				self.object:set_velocity({x=hvel.x,y=2,z=hvel.z})
			end

		end
	end

})