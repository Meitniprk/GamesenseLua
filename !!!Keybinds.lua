local require, tonumber, tostring, print, pairs, error, select = require, tonumber, tostring, print, pairs, error, select

local vector = require 'vector'
local ffi = require 'ffi'
local js = panorama.open()
local nick_name = js.MyPersonaAPI.GetName()
local easing = require 'gamesense/easing'
local images = require 'gamesense/images'
local anti_aim_f = require 'gamesense/antiaim_funcs'
local http = require('gamesense/http')

local ffi_cast = ffi.cast

ffi.cdef [[
    typedef int(__thiscall* get_clipboard_text_count)(void*);
    typedef void(__thiscall* set_clipboard_text)(void*, const char*, int);
    typedef void(__thiscall* get_clipboard_text)(void*, int, const char*, int);
]]

local VGUI_System010 =  client.create_interface( "vgui2.dll", "VGUI_System010" ) or print( "Error finding VGUI_System010" )
local VGUI_System = ffi_cast( ffi.typeof( 'void***' ), VGUI_System010 )

local get_clipboard_text_count = ffi_cast( "get_clipboard_text_count", VGUI_System[ 0 ][ 7 ] ) or print( "get_clipboard_text_count Invalid" )
local set_clipboard_text = ffi_cast( "set_clipboard_text", VGUI_System[ 0 ][ 9 ] ) or print( "set_clipboard_text Invalid" )
local get_clipboard_text = ffi_cast( "get_clipboard_text", VGUI_System[ 0 ][ 11 ] ) or print( "get_clipboard_text Invalid" )

local buffer
local size




local function SetTableVisibility( table, state )
    for i = 1, #table do
        ui.set_visible( table[ i ], state )
    end
end

local function SetTableCallback( table, item )
    for i = 1, #table do
        ui.set_callback( table[ i ], item )
    end
end

local function get_velocity(player)
    local velocity = vector(entity.get_prop(player, 'm_vecVelocity'))
    return velocity:length()
end

local function on_ground(player)
	local flags = entity.get_prop(player, 'm_fFlags')
	
	if bit.band(flags, 1) == 1 then
		return true
	end
	
	return false
end

local function in_air(player)
	local flags = entity.get_prop(player, 'm_fFlags')
	
	if bit.band(flags, 1) == 0 then
		return true
	end
	
	return false
end

local function is_crouching(player)
	local flags = entity.get_prop(player, 'm_fFlags')
	
	if bit.band(flags, 4) == 4 then
		return true
	end
	
	return false
end

local function contains(table, value)

	if table == nil then
		return false
	end
	
    table = ui.get(table)
    for i=0, #table do
        if table[i] == value then
            return true
        end
    end
    return false
end

local function distance3d(x1, y1, z1, x2, y2, z2)
	return math.sqrt((x2-x1)*(x2-x1) + (y2-y1)*(y2-y1) + (z2-z1)*(z2-z1))
end

local function scan_dmg(e, p, x, y, z)
	for i=1, 6 do
		local h = { entity.hitbox_position(e, i) }
		local ent, dmg = client.trace_bullet(p, x, y, z, h[1], h[2], h[3], p)

		if dmg ~= nil and dmg > 0 then
			return dmg
		end
	end
	return 0
end

local function entity_has_c4(ent)
	local bomb = entity.get_all('CC4')[1]
	return bomb ~= nil and entity.get_prop(bomb, 'm_hOwnerEntity') == ent
end

local function normalize_yaw(yaw)
	while yaw > 180 do yaw = yaw - 360 end
	while yaw < -180 do yaw = yaw + 360 end
	return yaw
end

local function round(num, decimals)
	local mult = 10^(decimals or 0)
	return math.floor(num * mult + 0.5) / mult
end

local function calc_angle(local_x, local_y, enemy_x, enemy_y)
	local ydelta = local_y - enemy_y
	local xdelta = local_x - enemy_x
	local relativeyaw = math.atan( ydelta / xdelta )
	relativeyaw = normalize_yaw( relativeyaw * 180 / math.pi )
	if xdelta >= 0 then
		relativeyaw = normalize_yaw(relativeyaw + 180)
	end
	return relativeyaw
end

local function angle_vector(angle_x, angle_y)
	local sy = math.sin(math.rad(angle_y))
	local cy = math.cos(math.rad(angle_y))
	local sp = math.sin(math.rad(angle_x))
	local cp = math.cos(math.rad(angle_x))
	return cp * cy, cp * sy, -sp
end

local function get_eye_pos(ent)
	local x, y, z = entity.get_prop(ent, "m_vecOrigin")
	local hx, hy, hz = entity.hitbox_position(ent, 0)
	return x, y, hz
end

local function rotate_point(x, y, rot, size)
	return math.cos(math.rad(rot)) * size + x, math.sin(math.rad(rot)) * size + y
end

local function renderer_arrow(x, y, r, g, b, a, rotation, size)
	local x0, y0 = rotate_point(x, y, rotation, 45)
	local x1, y1 = rotate_point(x, y, rotation + (size / 3.5), 45 - (size / 4))
	local x2, y2 = rotate_point(x, y, rotation - (size / 3.5), 45 - (size / 4))
	renderer.triangle(x0, y0, x1, y1, x2, y2, r, g, b, a)
end

local function calc_shit(xdelta, ydelta)
    if xdelta == 0 and ydelta == 0 then
        return 0
	end
	
    return math.deg(math.atan2(ydelta, xdelta))
end

local function sway(max, speed, min)
	return math.abs(math.floor((math.sin(globals.curtime()/speed*1)*max)))
end

local function get_damage(plocal, enemy, x, y,z)
	local ex = { }
	local ey = { }
	local ez = { }
	ex[0], ey[0], ez[0] = entity.hitbox_position(enemy, 1)
	ex[1], ey[1], ez[1] = ex[0] + 40, ey[0], ez[0]
	ex[2], ey[2], ez[2] = ex[0], ey[0] + 40, ez[0]
	ex[3], ey[3], ez[3] = ex[0] - 40, ey[0], ez[0]
	ex[4], ey[4], ez[4] = ex[0], ey[0] - 40, ez[0]
	ex[5], ey[5], ez[5] = ex[0], ey[0], ez[0] + 40
	ex[6], ey[6], ez[6] = ex[0], ey[0], ez[0] - 40
	local ent
    local dmg = 0
	for i=0, 6 do
		if dmg == 0 or dmg == nil then
			ent, dmg = client.trace_bullet(enemy, ex[i], ey[i], ez[i], x, y, z)
		end
	end
	return ent == nil and client.scale_damage(plocal, 1, dmg) or dmg
end

local function item_count(tab)
    if tab == nil then return 0 end
    if #tab == 0 then
        local val = 0
        for k in pairs(tab) do
            val = val + 1
        end

        return val
    end

    return #tab
end

local force_teammates = false or ui.get( ui.reference( "Visuals", "Player ESP", "Teammates" ) )

local function get_entities( enemy_only, alive_only )
	local enemy_only = enemy_only ~= nil and enemy_only or false
    local alive_only = alive_only ~= nil and alive_only or true

    local result = { }

    local player_resource = entity.get_player_resource( )

	for player = 1, globals.maxplayers( ) do
		if entity.get_prop( player_resource, 'm_bConnected', player ) == 1 then
            local is_enemy, is_alive = true, true

			if enemy_only and not force_teammates and not entity.is_enemy( player ) then is_enemy = false end
			if is_enemy then
				if alive_only and entity.get_prop( player_resource, 'm_bAlive', player ) ~= 1 then is_alive = false end
				if is_alive then table.insert( result, player ) end
			end
		end
	end

	return result
end

local function gradient_text(r1, g1, b1, a1, r2, g2, b2, a2, text)
	local output = ''

	local len = #text-1

	local rinc = (r2 - r1) / len
	local ginc = (g2 - g1) / len
	local binc = (b2 - b1) / len
	local ainc = (a2 - a1) / len

	for i=1, len+1 do
		output = output .. ('\a%02x%02x%02x%02x%s'):format(r1, g1, b1, a1, text:sub(i, i))

		r1 = r1 + rinc
		g1 = g1 + ginc
		b1 = b1 + binc
		a1 = a1 + ainc
	end

	return output
end

local lerp = function(a, b, percentage) return a + (b - a) * percentage end

local dragging_fn = function(name, base_x, base_y) return (function()local a={}local b,c,d,e,f,g,h,i,j,k,l,m,n,o;local p={__index={drag=function(self,...)local q,r=self:get()local s,t=a.drag(q,r,...)if q~=s or r~=t then self:set(s,t)end;return s,t end,set=function(self,q,r)local j,k=client.screen_size()ui.set(self.x_reference,q/j*self.res)ui.set(self.y_reference,r/k*self.res)end,get=function(self)local j,k=client.screen_size()return ui.get(self.x_reference)/self.res*j,ui.get(self.y_reference)/self.res*k end}}function a.new(u,v,w,x)x=x or 10000;local j,k=client.screen_size()local y=ui.new_slider('LUA','A',u..' window position',0,x,v/j*x)local z=ui.new_slider('LUA','A','\n'..u..' window position y',0,x,w/k*x)ui.set_visible(y,false)ui.set_visible(z,false)return setmetatable({name=u,x_reference=y,y_reference=z,res=x},p)end;function a.drag(q,r,A,B,C,D,E)if globals.framecount()~=b then c=ui.is_menu_open()f,g=d,e;d,e=ui.mouse_position()i=h;h=client.key_state(0x01)==true;m=l;l={}o=n;n=false;j,k=client.screen_size()end;if c and i~=nil then if(not i or o)and h and f>q and g>r and f<q+A and g<r+B then n=true;q,r=q+d-f,r+e-g;if not D then q=math.max(0,math.min(j-A,q))r=math.max(0,math.min(k-B,r))end end end;table.insert(l,{q,r,A,B})return q,r,A,B end;return a end)().new(name, base_x, base_y) end

local Render_engine=(function()local self={}local b=function(c,d,e,f,g,h,i)local j=0;if g==0 then return end;renderer.rectangle(c+h+j,d+h+j,e-h*2-j*2,f-h*2-j*2,17,17,17,g)renderer.circle(c+e-h-j,d+h+j,17,17,17,g,h,90,0.25)renderer.circle(c+e-h-j,d+f-h-j,17,17,17,g,h,360,0.25)renderer.circle(c+h+j,d+f-h-j,17,17,17,g,h,270,0.25)renderer.circle(c+h+j,d+h+j,17,17,17,g,h,180,0.25)renderer.rectangle(c+h+j,d+j,e-h*2-j*2,h,17,17,17,g)renderer.rectangle(c+e-h-j,d+h+j,h,f-h*2-j*2,17,17,17,g)renderer.rectangle(c+h+j,d+f-h-j,e-h*2-j*2,h,17,17,17,g)renderer.rectangle(c+j,d+h+j,h,f-h*2-j*2,17,17,17,g)end;local k=function(c,d,e,f,l,m,n,o,p,h,i)local j=h==0 and i or 0;renderer.rectangle(c+h,d,e-h*2,i,l,m,n,o)renderer.circle_outline(c+e-h,d+h,l,m,n,o,h,270,0.25,i)renderer.gradient(c+e-i,d+h+j,i,f-h*2-j*2,l,m,n,o,l,m,n,p,false)renderer.circle_outline(c+e-h,d+f-h,l,m,n,p,h,360,0.25,i)renderer.rectangle(c+h,d+f-i,e-h*2,i,l,m,n,p)renderer.circle_outline(c+h,d+f-h,l,m,n,p,h,90,0.25,i)renderer.gradient(c,d+h+j,i,f-h*2-j*2,l,m,n,o,l,m,n,p,false)renderer.circle_outline(c+h,d+h,l,m,n,o,h,180,0.25,i)end;self.render_container=function(c,d,e,f,l,m,n,o,p,g,h,i,q)local r=o~=0 and g or o;local s=o~=0 and p or o;b(c,d,e,f,r,h,i)k(c,d,e,f,l,m,n,o,s,h,i)if q and g~=255 and o~=0 then end end;return self end)()

local math_clamp = function(val, min, max) return math.min(max, math.max(min, val)) end
local gram_create = function(value, count) local gram = { }; for i=1, count do gram[i] = value; end return gram; end
local gram_update = function(tab, value, forced) local new_tab = tab; if forced or new_tab[#new_tab] ~= value then table.insert(new_tab, value); table.remove(new_tab, 1); end; tab = new_tab; end
local get_average = function(tab) local elements, sum = 0, 0; for k, v in pairs(tab) do sum = sum + v; elements = elements + 1; end return sum / elements; end

local get_color = function(number, max, i)
    local Colors = {
        { 255, 0, 0 },
        { 237, 27, 3 },
        { 235, 63, 6 },
        { 229, 104, 8 },
        { 228, 126, 10 },
        { 220, 169, 16 },
        { 213, 201, 19 },
        { 176, 205, 10 },
        { 124, 195, 13 }
    }

    local math_num = function(int, max, declspec)
        local int = (int > max and max or int)
        local tmp = max / int;

        if not declspec then declspec = max end

        local i = (declspec / tmp)
        i = (i >= 0 and math.floor(i + 0.5) or math.ceil(i - 0.5))

        return i
    end

    i = math_num(number, max, #Colors)

    return
        Colors[i <= 1 and 1 or i][1], 
        Colors[i <= 1 and 1 or i][2],
        Colors[i <= 1 and 1 or i][3],
        i
end

do
    for key, easing_func in pairs(easing) do
        easing[key] = function (t, b, c, d, ...)
            return math_clamp(easing_func(t, b, c, d, ...), b, d)
        end
    end
end

local classptr = ffi.typeof('void***')
local rawivengineclient = client.create_interface('engine.dll', 'VEngineClient014') or error('VEngineClient014 wasnt found', 2)
local ivengineclient = ffi.cast(classptr, rawivengineclient) or error('rawivengineclient is nil', 2)
local is_in_game = ffi.cast('bool(__thiscall*)(void*)', ivengineclient[0][26]) or error('is_in_game is nil')

local get_name = panorama.loadstring([[ return MyPersonaAPI.GetName() ]])

local var = {
    active_idx = 1,
    player_state = 0,
    antiaim_state = 'Global',
    best_value = 180,
    changer_state = 0,
    bestenemy = 0,
    last_nn = 0,
    miss = { },
    hit = { },
    shots = { },
    last_hit = { },
    stored_misses = { },
    stored_shots = { },
    fs_disabled = 0,
    main_yaw_value = 0,
    main_bodyyaw_value = 0,
    main_fakelimit_value = 0,
    preset_yaw_value = 0,
    preset_bodyyaw_value = 0,
    preset_fakelimit_value = 0,
    builder_yaw_value = 0,
    builder_bodyyaw_value = 0,
    builder_fakelimit_value = 0,
    legitaaon = false,
    aa_dir = 0,
    roll_enabled = false,
    lastshot = 0,
    last_press_t = 0,
    delay = 0,
    timer = 0,
    delayvalue = 0,
    lp_hit = 0,
    lp_miss = 0,
    enemy_shot_time = 0,
    dtclr = 0,
    lastUpdate = 0,
    ab_time = 0,
    ab_timer = 0,
    abmisses = 0,
    ab_type = 'R',
    roll_alpha = 0,
    classnames = {
        'CWorld',
        'CCSPlayer',
        'CFuncBrush'
    },
    nonweapons = {
        "knife",
        "hegrenade",
        "inferno",
        "flashbang",
        "decoy",
        "smokegrenade",
        "taser"
    }
}

local keybinds_references = { }

local function create_item(tab, container, name, arg, cname)
    local collected = { }
    local reference = { ui.reference(tab, container, name) }

    for i=1, #reference do
        if i <= arg then
            collected[i] = reference[i]
        end
    end

    keybinds_references[cname or name] = collected
end

local menudir =  { 'CONFIG', 'Presets' }

local ref = {
    enabled = ui.reference( 'AA', 'Anti-aimbot angles', 'Enabled' ),
    pitch = ui.reference( 'AA', 'Anti-aimbot angles', 'Pitch' ),
    yaw_base = ui.reference( 'AA', 'Anti-aimbot angles', 'Yaw base' ),
    yaw = { ui.reference( 'AA', 'Anti-aimbot angles', 'Yaw' ) },
    yaw_jitter = {ui.reference( 'AA', 'Anti-aimbot angles', 'Yaw jitter' ) },
    body_yaw = { ui.reference( 'AA', 'Anti-aimbot angles', 'Body yaw' ) },
    freestanding_body_yaw = ui.reference( 'AA', 'Anti-aimbot angles', 'Freestanding body yaw' ),
    fake_yaw_limit = ui.reference( 'AA', 'Anti-aimbot angles', 'Fake yaw limit' ),
    edge_yaw = ui.reference( 'AA', 'Anti-aimbot angles', 'Edge yaw' ),
    roll = ui.reference( 'AA', 'Anti-aimbot angles', 'Roll' ),
    freestanding = { ui.reference( 'AA', 'Anti-aimbot angles', 'Freestanding' ) },
    slowwalk = { ui.reference( 'AA', 'Other', 'Slow motion' ) },
    leg_movement = ui.reference( 'AA', 'Other', 'Leg movement' ),
    doubletap = { ui.reference( 'RAGE', 'Other', 'Double tap' ) },
    fakeduck = ui.reference( 'RAGE', 'Other', 'Duck peek assist' ),
    safepoint = ui.reference("RAGE", "Aimbot", "Force safe point"),
	forcebaim = ui.reference("RAGE", "Other", "Force body aim"),
    quickpeek = { ui.reference("RAGE", "Other", "Quick peek assist") },
	onshotaa = { ui.reference("AA", "Other", "On shot anti-aim") },
	fakelag = { ui.reference("AA", "Fake lag", "Enabled") },
	ping_spike = { ui.reference('MISC', 'Miscellaneous', 'Ping spike') },
}

local master_switch = ui.new_checkbox( menudir[ 1 ], menudir[ 2 ], 'Enable Solace-SolusUI' )

local active_tab = ui.new_combobox( menudir[ 1 ], menudir[ 2 ], 'Tabs', {'Visuals' } )

--aatab


local vis_tab = {
    ui = ui.new_multiselect( menudir[ 1 ], menudir[ 2 ], 'Ui elements', { 'Watermark', --[['Anti-aim indication',]] 'Keybinds', 'Spectators' } ),
    ui_label = ui.new_label( menudir[ 1 ], menudir[ 2 ], '                           UI' ),
    ui_color_label = ui.new_label( menudir[ 1 ], menudir[ 2 ], 'Ui color' ),
    ui_color = ui.new_color_picker( menudir[ 1 ], menudir[ 2 ], 'UI color', 129, 198, 255, 40 ),
    ui_style = ui.new_combobox( menudir[ 1 ], menudir[ 2 ], 'Ui style', { 'Normal', 'Legacy', 'Thick' } ),
    ui_roundness = ui.new_slider( menudir[ 1 ], menudir[ 2 ], 'Ui Roundness', 0, 8, 4 ),
    ui_animspeed = ui.new_slider( menudir[ 1 ], menudir[ 2 ], 'Ui animation speed', 4, 20, 5, true, 'fr' ),
}



--preset changer

--aabuilder


---

for i=1, 64 do
    var.miss[i], var.hit[i], var.shots[i], var.last_hit[i], var.stored_misses[i], var.stored_shots[i] = {}, {}, {}, 0, 0, 0
	for k=1, 3 do
		var.miss[i][k], var.hit[i][k], var.shots[i][k] = {}, {}, {}
		for j=1, 1000 do
			var.miss[i][k][j], var.hit[i][k][j], var.shots[i][k][j] = 0, 0, 0
		end
	end
	var.miss[i][4], var.hit[i][4], var.shots[i][4] = 0, 0, 0
end

local function handle_menu( )
    local master_switch = ui.get( master_switch )
    local activetab = ui.get( active_tab )

  

    ui.set_visible( active_tab, master_switch )



    --vis tab
    ui.set_visible( vis_tab.ui, master_switch and activetab == 'Visuals' )
    ui.set_visible( vis_tab.ui_label, master_switch and activetab == 'Visuals' and (contains(vis_tab.ui, 'Watermark') or contains(vis_tab.ui, 'Keybinds') or contains(vis_tab.ui, 'Spectators') ) )
    ui.set_visible( vis_tab.ui_color_label, master_switch and activetab == 'Visuals' and (contains(vis_tab.ui, 'Watermark') or contains(vis_tab.ui, 'Keybinds') or contains(vis_tab.ui, 'Spectators') ) )
    ui.set_visible( vis_tab.ui_color, master_switch and activetab == 'Visuals' and (contains(vis_tab.ui, 'Watermark') or contains(vis_tab.ui, 'Keybinds') or contains(vis_tab.ui, 'Spectators') ) )
    ui.set_visible( vis_tab.ui_roundness, master_switch and activetab == 'Visuals' and (contains(vis_tab.ui, 'Watermark') or contains(vis_tab.ui, 'Keybinds') or contains(vis_tab.ui, 'Spectators') ) )
    ui.set_visible( vis_tab.ui_animspeed, master_switch and activetab == 'Visuals' and contains(vis_tab.ui, 'Keybinds') )
    --ui.set_visible( vis_tab.ui_animtype, master_switch and activetab == 'Visuals' and (contains(vis_tab.ui, 'Watermark') or contains(vis_tab.ui, 'Keybinds') ) )
    ui.set_visible( vis_tab.ui_style, master_switch and activetab == 'Visuals' and (contains(vis_tab.ui, 'Watermark') or contains(vis_tab.ui, 'Keybinds') or contains(vis_tab.ui, 'Spectators') ) )
 
    ---
  
end



local function b_side( )
    if var.timer < globals.curtime( ) - var.delay then
        var.delayvalue = var.delayvalue == 90 and -90 or 90
        var.timer = globals.curtime( )
    end
end




local function leg_breaker( )
    local leg_p = var.roll_enabled and 1 or client.random_int( 1, 3 )

    if leg_p == 1 then
        ui.set( ref.leg_movement, 'Off' )
    elseif leg_p == 2 then
       ui.set( ref.leg_movement, 'Always slide' )
    elseif leg_p == 3 then
        ui.set( ref.leg_movement, 'Off' )
    end
end

local function leg_animation( )
    entity.set_prop( entity.get_local_player( ), "m_flPoseParameter", 1, 0 )
end


client.set_event_callback( 'weapon_fire', function( e )
    if client.userid_to_entindex(e.userid) == entity.get_local_player() then
        var.lastshot = globals.curtime()
    end
end)

local bp = {0, 0, 0}

local function dist_from_3dline(shooter, e)
	local x, y, z = entity.hitbox_position(shooter, 0)
	local x1, y1, z1 = client.eye_position()

	--point
	local p = {x1,y1,z1}

	--line
	local a = {x,y,z}
	local b = {e.x,e.y,e.z}

	--line delta
	local ab = {b[1] - a[1], b[2] - a[2], b[3] - a[3]}

	--line length
	local len = math.sqrt(ab[1]^2 + ab[2]^2 + ab[3]^2)

	--line delta / line legth
	local d  = {ab[1] / len, ab[2] / len, ab[3] / len}

	--point to line origin delta
	local ap = {p[1] - a[1], p[2] - a[2], p[3] - a[3]}

	--direction
	local d2 = d[1]*ap[1] + d[2]*ap[2] + d[3]*ap[3]

	--closest point on line to point
	bp = {a[1] + d2 * d[1], a[2] + d2 * d[2], a[3] + d2 * d[3]}

	--distance from closest point to point
	return (bp[1]-x1) + (bp[2]-y1) + (bp[3]-z1)
end

local function on_bullet_impact(e)
	local plocal = entity.get_local_player()
	local shooter = client.userid_to_entindex(e.userid)

	if not entity.is_enemy(shooter) or not entity.is_alive(plocal) then
		return
	end

	local d = dist_from_3dline(shooter, e)

	if math.abs(d) < 100 then
        --var.lp_miss = var.lp_miss + 1
        --var.last_shot = globals.curtime()
	
		--local dsy = var.legitaaon and (ui.get(ref.body_yaw[2]) * -1) or ui.get(ref.body_yaw[2])
        local dsy = ui.get(ref.body_yaw[2])

		local previous_record = var.shots[shooter][1][var.shots[shooter][4]] == globals.curtime()
		var.shots[shooter][4] = previous_record and var.shots[shooter][4] or var.shots[shooter][4] + 1

		var.shots[shooter][1][var.shots[shooter][4]] = globals.curtime()

	

		if dtc then
			var.shots[shooter][2][var.shots[shooter][4]] = math.abs(d) > 0.5 and (d < 0 and 90 or -90) or dsy
		else
			var.shots[shooter][2][var.shots[shooter][4]] = (dsy == 90 and -90 or 90)
		end
	end
end

local function on_player_hurt(e)
	local plocal = entity.get_local_player()
	local victim = client.userid_to_entindex(e.userid)
	local attacker = client.userid_to_entindex(e.attacker)

	if not entity.is_enemy(attacker) or not entity.is_alive(plocal) or victim ~= plocal then
		return
	end

    for i=1, #var.nonweapons do
		if e.weapon == var.nonweapons[i] then
			return
		end
	end

    var.lp_miss = var.lp_miss + 1
    var.enemy_shot_time = globals.curtime() + 0.5

	--local dsy = var.legitaaon and (ui.get(ref.body_yaw[2]) * -1) or ui.get(ref.body_yaw[2])
    local dsy = ui.get(ref.body_yaw[2])

	var.hit[attacker][4] = var.hit[attacker][4] + 1
	var.hit[attacker][1][var.hit[attacker][4]] = globals.curtime()
	var.hit[attacker][2][var.hit[attacker][4]] = dsy == 90 and 90 or -90
	var.hit[attacker][3][var.hit[attacker][4]] = e.hitgroup
end

local function reset_data(keep_hit)
	for i=1, 64 do
		var.last_hit[i], var.stored_misses[i], var.stored_shots[i] = (keep_hit and var.hit[i][2][var.hit[i][4]] ~= 0) and var.hit[i][2][var.hit[i][4]] or 0, 0, 0
		for k=1, 3 do
			for j=1, 200--[[1000]] do
				var.miss[i][k][j], var.hit[i][k][j], var.shots[i][k][j] = 0, 0, 0
			end
		end
		var.miss[i][4], var.hit[i][4], var.shots[i][4], var.last_nn, var.best_value = 0, 0, 0, 0, 180
	end
end



local anim_timer, anim_value, ind_side = globals.curtime( ), 0, false

local function handle_animation( )
    --print(anim_value)
    if anim_timer < globals.curtime( ) - ui.get( vis_tab.crosshair_main_animspeed ) / 100 then
        if ui.get( vis_tab.crosshair_main_animstyle ) == 'Circle' then
            if anim_value == 0 or anim_value == 5 then
                ind_side = not ind_side
            end
        elseif ui.get( vis_tab.crosshair_main_animstyle ) == 'Straight' then
            if anim_value == 6 and ui.get( vis_tab.crosshair_direction ) == 'Right' then
                anim_value = -1
            elseif anim_value == 0 and ui.get( vis_tab.crosshair_direction ) == 'Left' then
                anim_value = 7
            end
        end
        
        if ui.get( vis_tab.crosshair_main_animstyle ) == 'Circle' then
            anim_value = ind_side and anim_value + 1 or anim_value - 1
        elseif ui.get( vis_tab.crosshair_main_animstyle ) == 'Straight' then
            anim_value = ui.get( vis_tab.crosshair_direction ) == 'Right' and anim_value + 1 or anim_value - 1
        end

        anim_timer = globals.curtime( )
    end

    if anim_value > 6 or anim_value < 0 then
        anim_value = 0
    end
end

local s_txt_r, s_txt_g, s_txt_b, s_txt_a = 0, 0, 0, 0
local o_txt_r, o_txt_g, o_txt_b, o_txt_a = 0, 0, 0, 0
local l_txt_r, l_txt_g, l_txt_b, l_txt_a = 0, 0, 0, 0
local a_txt_r, a_txt_g, a_txt_b, a_txt_a = 0, 0, 0, 0
local c_txt_r, c_txt_g, c_txt_b, c_txt_a = 0, 0, 0, 0
local e_txt_r, e_txt_g, e_txt_b, e_txt_a = 0, 0, 0, 0

local ind_placement, ind_font, text_add, ab_add, ab_add2, maintxt_crosshair_style, maintxt_crosshair_anim_style, maintxt_reset, dtc_show, maintext = 'c', '-', 0, 0, 0, '\aaecbfdffG\abbc4fbffr\ac9bdf9ffa\ad6b6f7ffd\ae4aff5ffi\af1a8f3ffe\afea1f1ffn\aff96edfft', 'Old', false, 0, ''

local values = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }

local function handle_indicators( )
    local local_player = entity.get_local_player( )
    if not entity.is_alive( local_player ) then
		return
	end

    if ui.get( vis_tab.crosshair_style ) ~= maintxt_crosshair_style or ui.get( vis_tab.crosshair_animstyle ) ~= maintxt_crosshair_anim_style then
        maintxt_reset = true
        maintxt_crosshair_style = ui.get( vis_tab.crosshair_style )
        maintxt_crosshair_anim_style = ui.get( vis_tab.crosshair_animstyle )
    end

    if maintxt_reset then
        for i = 1, 10 do
            values[i] = 0
        end
        anim_value = 0
        maintxt_reset = false
    end

    local width, height = client.screen_size( )
    local x = width / 2
    local y = height / 2
    local ind_offset = 0

    local ind_height = ui.get( vis_tab.crosshair_height )
    local anim_speed = ui.get( vis_tab.crosshair_animspeed )
    local ind_separator = ui.get( vis_tab.crosshair_separator )

    local r1, g1, b1, a1 = ui.get( vis_tab.crosshair_color1 )
    local r2, g2, b2, a2 = ui.get( vis_tab.crosshair_color2 )

    local indicator_font = ui.get( vis_tab.crosshair_font )

    local indicator_placement = ui.get( vis_tab.crosshair_placement )

    local text_width, text_height = renderer.measure_text(ind_font, 'HHH')

    local dtc_adderx, dtc_addery, dtc_size, dtc_thickness = 0, 0, 0, 0

    if indicator_placement == 'Center' then
        ind_placement = 'c'
    elseif indicator_placement == 'Right' then
        ind_placement = 'l'
    elseif indicator_placement == 'Left' then
        ind_placement = 'r'
    end

    if indicator_font == 'Small' then
        ind_font = ind_placement .. '-'
        text_add = 0
        ab_add = 1
        ab_add2 = 0
        dtc_size = 2.5
        dtc_thickness = 1
    elseif indicator_font == 'Normal' then
        ind_font = ind_placement .. ''
        text_add = 1
        ab_add = 3
        ab_add2 = 1
        dtc_size = 3.5
        dtc_thickness = 0.5
    elseif indicator_font == 'Bold' then
        ind_font = ind_placement .. 'b'
        text_add = 1
        ab_add = 3
        ab_add2 = 1
        dtc_size = 3.5
        dtc_thickness = 1.5
    elseif indicator_font == 'Big' then
        ind_font = ind_placement .. '+'
        text_add = 10
        ab_add = 6
        ab_add2 = 2
        dtc_size = 7.5
        dtc_thickness = 2
    end

    if indicator_placement == 'Center'  then
        if indicator_font == 'Small' then
            dtc_adderx, dtc_addery = 0, 1
        elseif indicator_font == 'Normal' then
            dtc_adderx, dtc_addery = -3, 1
        elseif indicator_font == 'Bold' then
            dtc_adderx, dtc_addery = -3, 1
        elseif indicator_font == 'Big' then
            dtc_adderx, dtc_addery = -4, 2
        end
    elseif indicator_placement == 'Right' then
        x = x + 1
        if indicator_font == 'Small' then
            dtc_adderx, dtc_addery = 4, 6
        elseif indicator_font == 'Normal' then
            dtc_adderx, dtc_addery = 4, 7
        elseif indicator_font == 'Bold' then
            dtc_adderx, dtc_addery = 4, 7
        elseif indicator_font == 'Big' then
            dtc_adderx, dtc_addery = 9, 16
        end
    elseif indicator_placement == 'Left' then
        x = x - 2
        if indicator_font == 'Small' then
            dtc_adderx, dtc_addery = -24, 6
        elseif indicator_font == 'Normal' then
            dtc_adderx, dtc_addery = -34, 7
        elseif indicator_font == 'Bold' then
            dtc_adderx, dtc_addery = -36, 7
        elseif indicator_font == 'Big' then
            dtc_adderx, dtc_addery = -66, 16
        end
    end

    if var.aa_dir ~= 0 then
        local adder = indicator_font == 'Big' and 80 or 50
        renderer.text(x - adder, y + ind_height - 5, ( var.aa_dir == -90 and not var.legitaaon ) and 255 or 100, ( var.aa_dir == -90 and not var.legitaaon ) and 255 or 100, ( var.aa_dir == -90 and not var.legitaaon ) and 255 or 100, ( var.aa_dir == -90 and not var.legitaaon ) and 255 or 150, indicator_font == 'Big' and 'c+' or 'c', nil, '⮜')
        renderer.text(x + adder, y + ind_height - 5, ( var.aa_dir == 90 and not var.legitaaon ) and 255 or 100, ( var.aa_dir == 90 and not var.legitaaon ) and 255 or 100, ( var.aa_dir == 90 and not var.legitaaon ) and 255 or 100, ( var.aa_dir == 90 and not var.legitaaon ) and 255 or 150, indicator_font == 'Big' and 'c+' or 'c', nil, '⮞')
    end

    if ui.get( vis_tab.crosshair_style ) == '\aaecbfdffG\abbc4fbffr\ac9bdf9ffa\ad6b6f7ffd\ae4aff5ffi\af1a8f3ffe\afea1f1ffn\aff96edfft' then
        maintext = gradient_text(r1, g1, b1, 255, r2, g2, b2, 255, 'Skeet.cc [BETA]')
    elseif ui.get( vis_tab.crosshair_style ) == '\a81C6FFFFAni\aCCAFF3FFm\a81C6FFFFation' then
        if anim_value == 0 then
            s_txt_r, s_txt_g, s_txt_b, s_txt_a = r2, g2, b2, a2
            o_txt_r, o_txt_g, o_txt_b, o_txt_a = r1, g1, b1, a1
            l_txt_r, l_txt_g, l_txt_b, l_txt_a = r1, g1, b1, a1
            a_txt_r, a_txt_g, a_txt_b, a_txt_a = r1, g1, b1, a1
            c_txt_r, c_txt_g, c_txt_b, c_txt_a = r1, g1, b1, a1
            e_txt_r, e_txt_g, e_txt_b, e_txt_a = r1, g1, b1, a1
        elseif anim_value == 1 then
            s_txt_r, s_txt_g, s_txt_b, s_txt_a = r1, g1, b1, a1
            o_txt_r, o_txt_g, o_txt_b, o_txt_a = r2, g2, b2, a2
            l_txt_r, l_txt_g, l_txt_b, l_txt_a = r1, g1, b1, a1
            a_txt_r, a_txt_g, a_txt_b, a_txt_a = r1, g1, b1, a1
            c_txt_r, c_txt_g, c_txt_b, c_txt_a = r1, g1, b1, a1
            e_txt_r, e_txt_g, e_txt_b, e_txt_a = r1, g1, b1, a1
        elseif anim_value == 2 then
            s_txt_r, s_txt_g, s_txt_b, s_txt_a = r1, g1, b1, a1
            o_txt_r, o_txt_g, o_txt_b, o_txt_a = r1, g1, b1, a1
            l_txt_r, l_txt_g, l_txt_b, l_txt_a = r2, g2, b2, a2
            a_txt_r, a_txt_g, a_txt_b, a_txt_a = r1, g1, b1, a1
            c_txt_r, c_txt_g, c_txt_b, c_txt_a = r1, g1, b1, a1
            e_txt_r, e_txt_g, e_txt_b, e_txt_a = r1, g1, b1, a1
        elseif anim_value == 3 then
            s_txt_r, s_txt_g, s_txt_b, s_txt_a = r1, g1, b1, a1
            o_txt_r, o_txt_g, o_txt_b, o_txt_a = r1, g1, b1, a1
            l_txt_r, l_txt_g, l_txt_b, l_txt_a = r1, g1, b1, a1
            a_txt_r, a_txt_g, a_txt_b, a_txt_a = r2, g2, b2, a2
            c_txt_r, c_txt_g, c_txt_b, c_txt_a = r1, g1, b1, a1
            e_txt_r, e_txt_g, e_txt_b, e_txt_a = r1, g1, b1, a1
        elseif anim_value == 4 then
            s_txt_r, s_txt_g, s_txt_b, s_txt_a = r1, g1, b1, a1
            o_txt_r, o_txt_g, o_txt_b, o_txt_a = r1, g1, b1, a1
            l_txt_r, l_txt_g, l_txt_b, l_txt_a = r1, g1, b1, a1
            a_txt_r, a_txt_g, a_txt_b, a_txt_a = r1, g1, b1, a1
            c_txt_r, c_txt_g, c_txt_b, c_txt_a = r2, g2, b2, a2
            e_txt_r, e_txt_g, e_txt_b, e_txt_a = r1, g1, b1, a1
        elseif anim_value == 5 then
            s_txt_r, s_txt_g, s_txt_b, s_txt_a = r1, g1, b1, a1
            o_txt_r, o_txt_g, o_txt_b, o_txt_a = r1, g1, b1, a1
            l_txt_r, l_txt_g, l_txt_b, l_txt_a = r1, g1, b1, a1
            a_txt_r, a_txt_g, a_txt_b, a_txt_a = r1, g1, b1, a1
            c_txt_r, c_txt_g, c_txt_b, c_txt_a = r1, g1, b1, a1
            e_txt_r, e_txt_g, e_txt_b, e_txt_a = r2, g2, b2, a2
        elseif anim_value == 6 then
            s_txt_r, s_txt_g, s_txt_b, s_txt_a = r1, g1, b1, a1
            o_txt_r, o_txt_g, o_txt_b, o_txt_a = r1, g1, b1, a1
            l_txt_r, l_txt_g, l_txt_b, l_txt_a = r1, g1, b1, a1
            a_txt_r, a_txt_g, a_txt_b, a_txt_a = r1, g1, b1, a1
            c_txt_r, c_txt_g, c_txt_b, c_txt_a = r1, g1, b1, a1
            e_txt_r, e_txt_g, e_txt_b, e_txt_a = r1, g1, b1, a1
        end
    
        local maintxt_s = gradient_text(s_txt_r, s_txt_g, s_txt_b, s_txt_a, s_txt_r, s_txt_g, s_txt_b, s_txt_a, 'S')
        local maintxt_o = gradient_text(o_txt_r, o_txt_g, o_txt_b, o_txt_a, o_txt_r, o_txt_g, o_txt_b, o_txt_a, 'O')
        local maintxt_L = gradient_text(l_txt_r, l_txt_g, l_txt_b, l_txt_a, l_txt_r, l_txt_g, l_txt_b, l_txt_a, 'L')
        local maintxt_a = gradient_text(a_txt_r, a_txt_g, a_txt_b, a_txt_a, a_txt_r, a_txt_g, a_txt_b, a_txt_a, 'A')
        local maintxt_c = gradient_text(c_txt_r, c_txt_g, c_txt_b, c_txt_a, c_txt_r, c_txt_g, c_txt_b, c_txt_a, 'C')
        local maintxt_e = gradient_text(e_txt_r, e_txt_g, e_txt_b, e_txt_a, e_txt_r, e_txt_g, e_txt_b, e_txt_a, 'E')
    
        maintext = ( '%s%s%s%s%s%s' ):format( maintxt_s, maintxt_o, maintxt_L, maintxt_a, maintxt_c, maintxt_e )
    end

    local dtclreased = easing.quad_out( var.dtclr, 0, 1, 1 )
    local color = {255 - 255 * dtclreased, 255 * dtclreased, 0}
    local dtclrFT = globals.frametime() * anim_speed
    local doubletap = anti_aim_f.get_double_tap()
    var.dtclr = math_clamp(var.dtclr + (doubletap and dtclrFT or -dtclrFT), 0, 1)

    local body_yaw_slider_val = var.legitaaon and ui.get(ref.body_yaw[2]) * -1 or ui.get(ref.body_yaw[2])
    var.ab_type = body_yaw_slider_val > 1 and 'L' or 'R'

    local main_alpha = math.sin(math.abs(-math.pi + (globals.curtime() * (1 / 0.5)) % (math.pi * 2))) * 255
    if values[2] == 1 then
        var.roll_alpha = main_alpha
    else
        var.roll_alpha = values[2] * 255
    end

    local items = {
        [1] = { true, maintext, { 255, 255, 255, 255 } },
        [2] = { var.roll_enabled, 'ROLL AA', { 126, 255, 224, 255 } },
        [4] = { ui.get(ref.doubletap[1]) and ui.get(ref.doubletap[2]), 'DT', { color[1], color[2], color[3], 255 } },
        [5] = { ui.get(ref.onshotaa[1]) and ui.get(ref.onshotaa[2]), 'ONSHOT', { 225, 170, 160, 255 } },
        [6] = { ui.get(ref.safepoint), 'SAFE', { 120, 200, 120, 255 } },
        [7] = { ui.get(ref.forcebaim), 'BAIM', { 170, 50, 255, 255 } },
        [8] = { ui.get(ref.fakeduck), 'DUCK', { 80, 80, 255, 255 } },
        [9] = { ui.get( ref.freestanding ) and contains( ref.binds, 'Freestanding' ), 'FREESTAND', { 220, 220, 220, 255 } },
        [10] = { ui.get( ref.ping_spike[1] ) and ui.get( ref.ping_spike[2] ), 'PING', { 150, 200, 60, 255 } }
    }

    for i, ref in ipairs(items) do
        local text_width, text_height = renderer.measure_text(ind_font, ref[2])
        local key = ui.get( vis_tab.crosshair_animstyle ) == 'New' and ( ref[1] and 1.1 or 0 ) or ref[1]
        local FT = globals.frametime() * anim_speed

        if i == 2 then
            ind_offset = ind_offset + 1
        end

        values[i] = ui.get( vis_tab.crosshair_animstyle ) == 'New' and ( math_clamp( lerp( values[i], key, globals.frametime() * 5 * 1.5 ), 0, 1) ) or ( easing.linear(values[i] + (key and FT or -FT), 0, 1, 1) )

        renderer.text( x, y + ind_height + ind_offset * values[i], ref[3][1], ref[3][2], ref[3][3], ref[3][4] * values[i], ind_font, text_width * values[i] + 3, ref[2] )

        if i == 4 and ui.get( vis_tab.crosshair_animstyle ) == 'New' then
            dtc_show = var.dtclr == 1 and 0 or 1
            if dtc_show == 1 and ref[1] then
                --renderer.circle_outline( x + text_width + 2 + dtc_adderx, y + ind_height + ind_offset * values[i] + dtc_addery, color[1], color[2], color[3], 255 * values[i], dtc_size, 0, var.dtclr, dtc_thickness )
            end
        end

        ind_offset = ind_offset + ( text_add + ind_separator ) * values[i]
    end
end

local solus = {
	watermark = function()
		local classptr = ffi.typeof('void***')
		local rawivengineclient = client.create_interface('engine.dll', 'VEngineClient014') or error('VEngineClient014 wasnt found', 2)
		local ivengineclient = ffi.cast(classptr, rawivengineclient) or error('rawivengineclient is nil', 2)
		local is_in_game = ffi.cast('bool(__thiscall*)(void*)', ivengineclient[0][26]) or error('is_in_game is nil')

		local get_gc_state = panorama.loadstring([[ return MyPersonaAPI.IsConnectedToGC() ]])

		local width, textwidth, adder = 0, 0, 0

		local x, height = client.screen_size()

		local g_paint_handler = function()
            if not contains(vis_tab.ui, 'Watermark') or not ui.get( master_switch ) then width, textwidth, adder = 0, 0, 0 return end

            local easing_speed = ui.get( vis_tab.ui_animspeed )

            local r, g, b, a = ui.get(vis_tab.ui_color)
        
            local style = ui.get( vis_tab.ui_style )
        
            local roundness_value = ui.get( vis_tab.ui_roundness )
        
            local line_thickness = 1
            local lowerline_alpha = 45
        
            if style == 'Normal' then
                line_thickness = 1
                lowerline_alpha = 45
            elseif style == 'Legacy' then
                line_thickness = 1
                lowerline_alpha = 230
            elseif style == 'Thick' then
                line_thickness = 2
                lowerline_alpha = 45
            end

			local nickname = string.sub(nick_name, 1, 35)
			local text = ''

			local sys_time = { client.system_time() }
			local actual_time = ('%02d:%02d:%02d'):format(sys_time[1], sys_time[2], sys_time[3])

			local name1 = "Skeet.cc "
			local name2 = "[BETA]"

			local name_txt = gradient_text( 255, 255, 255, 255, 255, 255, 255, 255, name1 )
			local name2_txt = gradient_text( r, g, b, 255, r, g, b, 255, name2 )
			local nickname_txt = gradient_text( 255, 255, 255, 255, 255, 255, 255, 255, nickname )

			if is_in_game(is_in_game) == true then
				local latency = client.latency() * 1000
				local latency_text = latency > 1 and ('  delay: %dms'):format(latency) or ''
				text = ('%s%s  %s%s  %s'):format(name_txt, name2_txt, "\aFFFFFFFF"..nickname, latency_text, actual_time)
			end

			local gc_state = not get_gc_state() and 16 or 0

			local textw, textheight = renderer.measure_text(nil, text)

			width = lerp( width, textw + 15, globals.frametime() * easing_speed )
			local w = math.floor(width)

			adder = lerp( adder, gc_state, globals.frametime() * easing_speed )
			local adder_anim = math.floor(adder)

			textwidth = lerp( textwidth, textw + 5, globals.frametime() * easing_speed )
			local textwidth_anim = math.floor( textwidth )

            local offset, h = 12, 21

            Render_engine.render_container(x - w - offset - adder_anim, offset, w + adder_anim, h, r, g, b, 255, lowerline_alpha, a, roundness_value, line_thickness, true)

			renderer.text(x - w - 5, offset + 20 / 5, 255, 255, 255, 255, '', textwidth_anim, text)

			if not get_gc_state() and adder_anim > 10 then
				local realtime = globals.realtime()*1.5
					
				if realtime%2 <= 1 then
					renderer.circle_outline(x - w - 15, offset + 10, 89, 119, 239, 255, 5, 0, realtime%1, 2)
				else
					renderer.circle_outline(x - w - 15, offset + 10, 89, 119, 239, 255, 5, realtime%1*370, 1-realtime%1, 2)
				end
			end
		end

		client.set_event_callback('paint', g_paint_handler)
	end,

	keybinds = function()
		local screen_size = { client.screen_size() }

		local dragging = dragging_fn('solace_keybinds', screen_size[1] / 1.385, screen_size[2] / 2.5)

		local m_alpha, m_active = 0, { }
		local hotkey_modes = { 'holding', 'toggled', 'disabled' }

		local width, txt_width = 0, 0

		local ease = {
			[ 'Z-Hop' ] = 0,
			[ 'Duck peek assist' ] = 0,
			[ 'Pre-speed' ] = 0,
			[ 'Resolver override' ] = 0,
			[ 'On shot anti-aim' ] = 0,
			[ 'Freestanding' ] = 0,
			[ 'Quick stop' ] = 0,
			[ 'Fake peek' ] = 0,
			[ 'Free look' ] = 0,
			[ 'Quick peek assist' ] = 0,
			[ 'Force body aim' ] = 0,
			[ 'Rage aimbot' ] = 0,
			[ 'Legit triggerbot' ] = 0,
			[ 'Visuals' ] = 0,
			[ 'Grenade release' ] = 0,
			[ 'Blockbot' ] = 0,
			[ 'Safe point' ] = 0,
			[ 'Ping spike' ] = 0,
			[ 'Last second defuse' ] = 0,
			[ 'Jump at edge' ] = 0,
			[ 'Legit aimbot' ] = 0,
			[ 'Double tap' ] = 0,
			[ 'Slow motion' ] = 0,
			[ 'Menu toggled' ] = 0
		}
		
		create_item('LEGIT', 'Aimbot', 'Enabled', 2, 'Legit aimbot')
		create_item('LEGIT', 'Triggerbot', 'Enabled', 2, 'Legit triggerbot')
		create_item('RAGE', 'Aimbot', 'Enabled', 2, 'Rage aimbot')
		create_item('RAGE', 'Aimbot', 'Force safe point', 1, 'Safe point')
		create_item('RAGE', 'Other', 'Quick stop', 2)
		create_item('RAGE', 'Other', 'Quick peek assist', 2)
		create_item('RAGE', 'Other', 'Force body aim', 1)
		create_item('RAGE', 'Other', 'Duck peek assist', 1)
		create_item('RAGE', 'Other', 'Double tap', 2)
		create_item('RAGE', 'Other', 'Anti-aim correction override', 1, 'Resolver override')
		create_item('AA', 'Anti-aimbot angles', 'Freestanding', 2)
		create_item('AA', 'Other', 'Slow motion', 2)
		create_item('AA', 'Other', 'On shot anti-aim', 2)
		create_item('AA', 'Other', 'Fake peek', 2)
		create_item('MISC', 'Movement', 'Z-Hop', 2)
		create_item('MISC', 'Movement', 'Pre-speed', 2)
		create_item('MISC', 'Movement', 'Blockbot', 2)
		create_item('MISC', 'Movement', 'Jump at edge', 2)
		create_item('MISC', 'Miscellaneous', 'Last second defuse', 1)
		create_item('MISC', 'Miscellaneous', 'Free look', 1)
		create_item('MISC', 'Miscellaneous', 'Ping spike', 2)
		create_item('MISC', 'Miscellaneous', 'Automatic grenade release', 2, 'Grenade release')
		create_item('VISUALS', 'Player ESP', 'Activation type', 1, 'Visuals')

		local g_paint_handler = function()
            if not contains(vis_tab.ui, 'Keybinds') or not ui.get( master_switch ) then width, txt_width = 30, 0 return end

            local easing_speed = ui.get( vis_tab.ui_animspeed )

            local r, g, b, a = ui.get(vis_tab.ui_color)
        
            local style = ui.get( vis_tab.ui_style )
        
            local roundness_value = ui.get( vis_tab.ui_roundness )
        
            local line_thickness = 1
            local lowerline_alpha = 45
        
            if style == 'Normal' then
                line_thickness = 1
                lowerline_alpha = 45
            elseif style == 'Legacy' then
                line_thickness = 1
                lowerline_alpha = 230
            elseif style == 'Thick' then
                line_thickness = 2
                lowerline_alpha = 45
            end

        	local is_menu_open = ui.is_menu_open()
        	local frames = 8 * globals.frametime()

        	local latest_item = false
        	local maximum_offset = 100

        	for c_name, c_ref in pairs(keybinds_references) do
        	    local item_active = true

        	    local items = item_count(c_ref)
        	    local state = { ui.get(c_ref[items]) }

        	    if items > 1 then
        	        item_active = ui.get(c_ref[1])
        	    end

        	  

        	    if item_active and state[2] ~= 0 and (state[2] == 3 and not state[1] or state[2] ~= 3 and state[1]) then
        	        latest_item = true

        	        if m_active[c_name] == nil then
        	            m_active[c_name] = {
        	                mode = '', alpha = 0, offset = 0, active = true
        	            }
        	        end


        	        local text_width = renderer.measure_text(nil, c_name)

					local mode_width = renderer.measure_text(nil, hotkey_modes[state[2]])

        	        m_active[c_name].active = true
        	        m_active[c_name].offset = text_width + mode_width + 35
        	        m_active[c_name].mode = hotkey_modes[state[2]]
        	        m_active[c_name].alpha = m_active[c_name].alpha + frames

        	        if m_active[c_name].alpha > 1 then
        	            m_active[c_name].alpha = 1
        	        end
        	    elseif m_active[c_name] ~= nil then
        	        m_active[c_name].active = false
        	        m_active[c_name].alpha = m_active[c_name].alpha - frames

        	        if m_active[c_name].alpha <= 0 then
        	            m_active[c_name] = nil
        	        end
        	    end

        	    if m_active[c_name] ~= nil and m_active[c_name].offset > maximum_offset then
        	        maximum_offset = m_active[c_name].offset
        	    end
        	end

        	if is_menu_open and not latest_item then
        	    local case_name = 'Menu toggled'
        	    local text_width = renderer.measure_text(nil, case_name)

        	    latest_item = true
        	    maximum_offset = maximum_offset < text_width and text_width or maximum_offset

        	    m_active[case_name] = {
        	        active = true,
        	        offset = text_width,
        	        mode = '~',
        	        alpha = 0,
        	    }
        	end

        	for c_name, c_ref in pairs(keybinds_references) do
        	    local items = item_count(c_ref)

        	    local key = ui.get(c_ref[items])
        	    local FT = globals.frametime() * easing_speed
        	    ease[c_name] = easing.linear(ease[c_name] + (key and FT or -FT), 0, 1, 1)
        	end

        	local text = 'keybinds'

            local txt_w, txt_h = renderer.measure_text('', text)
            txt_width = lerp( txt_width, txt_w, globals.frametime() * easing_speed )
            local txtw = math.floor(txt_width)

			local x, y = dragging:get()

        	local height_offset = 25
			width = lerp( width, maximum_offset, globals.frametime() * easing_speed )
        	local w, h = math.floor( width ), 21

            Render_engine.render_container(x, y, w, h, r, g, b, m_alpha*255, m_alpha*lowerline_alpha, m_alpha*a, roundness_value, line_thickness, true)

        	renderer.text(x - renderer.measure_text(nil, text) / 2 + w/2 + txt_w / 2, y + h/2, 255, 255, 255, m_alpha*255, 'c', txtw + 3, text)

        	for c_name, c_ref in pairs(m_active) do
        	    local key_type = '[' .. c_ref.mode .. ']'

        	    renderer.text(x + 5, y + height_offset - 10 + 10 * ease[c_name], 255, 255, 255, ease[c_name]*255, '', 0, c_name)
        	    renderer.text(x + w - renderer.measure_text(nil, key_type) - 5, y + height_offset - 10 + 10 * ease[c_name], 255, 255, 255, ease[c_name]*255, '', 0, key_type)

        	    height_offset = height_offset + 15 * ease[c_name]
        	end

        	dragging:drag(w, (3 + (15 * item_count(m_active))) * 2)

        	if item_count(m_active) > 0 and latest_item then
        	    m_alpha = m_alpha + frames; if m_alpha > 1 then m_alpha = 1 end
        	else
        	    m_alpha = m_alpha - frames; if m_alpha < 0 then m_alpha = 0 end 
        	end

        	if is_menu_open then
        	    m_active['Menu toggled'] = nil
        	end
		end

		client.set_event_callback('paint', g_paint_handler)
	end,

	spectators = function()
		local screen_size = { client.screen_size() }

		local dragging = dragging_fn('solace_spectators', screen_size[1] / 1.385, screen_size[2] / 2)

		local m_alpha, m_active, m_contents, unsorted = 0, {}, {}, {}

		local width, txt_width = 0, 0

		--local ease = gram_create(0, 64)

        local get_spectating_players = function()
            local me = entity.get_local_player()

            local players, observing = { }, me
        
            for i = 1, globals.maxplayers() do
                if entity.get_classname(i) == 'CCSPlayer' then
                    local m_iObserverMode = entity.get_prop(i, 'm_iObserverMode')
                    local m_hObserverTarget = entity.get_prop(i, 'm_hObserverTarget')
                
                    if m_hObserverTarget ~= nil and m_hObserverTarget <= 64 and not entity.is_alive(i) and (m_iObserverMode == 4 or m_iObserverMode == 5) then
                        if players[m_hObserverTarget] == nil then
                            players[m_hObserverTarget] = { }
                        end
                    
                        if i == me then
                            observing = m_hObserverTarget
                        end
                    
                        table.insert(players[m_hObserverTarget], i)
                    end
                end
            end
        
            return players, observing
        end

		local g_paint_handler = function()
            if not contains( vis_tab.ui, 'Spectators' ) or not ui.get( master_switch ) then width, txt_width = 30, 0 return end

            local easing_speed = ui.get( vis_tab.ui_animspeed )

            local r, g, b, a = ui.get(vis_tab.ui_color)
        
            local style = ui.get( vis_tab.ui_style )
        
            local roundness_value = ui.get( vis_tab.ui_roundness )
        
            local line_thickness = 1
            local lowerline_alpha = 45
        
            if style == 'Normal' then
                line_thickness = 1
                lowerline_alpha = 45
            elseif style == 'Legacy' then
                line_thickness = 1
                lowerline_alpha = 230
            elseif style == 'Thick' then
                line_thickness = 2
                lowerline_alpha = 45
            end

        	local data_sp = { }

        	local is_menu_open = ui.is_menu_open()
        	local frames = 8 * globals.frametime()

        	local latest_item = false
        	local maximum_offset = 100

        	local me = entity.get_local_player()
        	local spectators, player = get_spectating_players()

        	for i=1, 64 do 
        	    unsorted[i] = {
        	        idx = i,
        	        active = false
        	    }
        	end

        	if spectators[player] ~= nil then
        	    for _, spectator in pairs(spectators[player]) do
        	        unsorted[spectator] = { 
        	            idx = spectator,

        	            active = (function()
        	                if spectator == me then
        	                    return false
        	                end

        	                return true
        	            end)(),

        	            avatar = (function()
        	                local steam_id = entity.get_steam64(spectator)
        	                local avatar = images.get_steam_avatar(steam_id)

        	                if steam_id == nil or avatar == nil then
        	                    return nil
        	                end

        	                if m_contents[spectator] == nil or m_contents[spectator].conts ~= avatar.contents then
        	                    m_contents[spectator] = {
        	                        conts = avatar.contents,
        	                        texture = renderer.load_rgba(avatar.contents, avatar.width, avatar.height)
        	                    }
        	                end

        	                return m_contents[spectator].texture
        	            end)()
        	        }
        	    end
        	end

        	for _, c_ref in pairs(unsorted) do
        	    local c_id = c_ref.idx
        	    local c_nickname = string.sub(entity.get_player_name(c_ref.idx), 1, 30)

        	    if c_ref.active then
        	        latest_item = true

        	        if m_active[c_id] == nil then
        	            m_active[c_id] = {
        	                alpha = 0, offset = 0, active = true
        	            }
        	        end

        	        local text_width = renderer.measure_text(nil, c_nickname)

        	        m_active[c_id].active = true
        	        m_active[c_id].offset = text_width + 30
        	        m_active[c_id].alpha = m_active[c_id].alpha + frames
        	        m_active[c_id].avatar = c_ref.avatar
        	        m_active[c_id].name = c_nickname

        	        if m_active[c_id].alpha > 1 then
        	            m_active[c_id].alpha = 1
        	        end
        	    elseif m_active[c_id] ~= nil then
        	        m_active[c_id].active = false
        	        m_active[c_id].alpha = m_active[c_id].alpha - frames

        	        if m_active[c_id].alpha <= 0 then
        	            m_active[c_id] = nil
        	        end
        	    end

        	    if m_active[c_id] ~= nil and m_active[c_id].offset > maximum_offset then
        	        maximum_offset = m_active[c_id].offset
        	    end
        	end

        	if is_menu_open and not latest_item then
        	    local case_name = ' '
        	    local text_width = 0 --renderer.measure_text(nil, case_name)

        	    latest_item = true
        	    maximum_offset = maximum_offset < text_width and text_width or maximum_offset

        	    m_active[case_name] = {
        	        name = ' ',
        	        active = true,
        	        offset = text_width,
        	        alpha = 1
        	    }
        	end

        	-- for _, c_ref in pairs(unsorted) do
        	--     local items = item_count(c_ref)

        	--     local key = c_ref.active
        	--     local FT = globals.frametime() * easing_speed
        	--     ease[c_name] = easing.linear(ease[c_name] + (key and FT or -FT), 0, 1, 1)

            --     print(ease[c_name])
        	-- end

        	local text = 'spectators'

            local txt_w, txt_h = renderer.measure_text('', text)
            txt_width = lerp( txt_width, txt_w, globals.frametime() * easing_speed )
            local txtw = math.floor(txt_width)

        	local x, y = dragging:get()

        	local height_offset = 25
			width = lerp( width, maximum_offset, globals.frametime() * easing_speed )
        	local w, h = math.floor( width ), 21

        	--w = w - 17

        	local right_offset = data_sp.auto_position and (x+w/2) > (({ client.screen_size() })[1] / 2)

            Render_engine.render_container(x, y, w, h, r, g, b, m_alpha*255, m_alpha*lowerline_alpha, m_alpha*a, roundness_value, line_thickness, true)

            renderer.text(x - renderer.measure_text(nil, text) / 2 + w/2 + txt_w / 2, y + h/2, 255, 255, 255, m_alpha*255, 'c', txtw + 3, text)

            for c_name, c_ref in pairs(m_active) do
                local _, text_h = renderer.measure_text(nil, c_ref.name)

                renderer.text(x + 5 + ((c_ref.avatar and not right_offset) and text_h + 5 or 0) + 1, y + height_offset--[[ - 15 + 15 * ease[c_name] ]], 255, 255, 255, m_alpha*c_ref.alpha*255, '', 0, c_ref.name)

                if c_ref.avatar ~= nil then
                    renderer.texture(c_ref.avatar, x + 2 + (right_offset and w - 15 or 5), y + height_offset--[[ - 15 + 15 * ease[c_name] ]], text_h, text_h, 255, 255, 255, m_alpha*c_ref.alpha*255, 'f')
                end

                height_offset = height_offset + 15-- * ease[c_name]
            end

        	dragging:drag(w, (3 + (15 * item_count(m_active))) * 2)

        	if item_count(m_active) > 0 and latest_item then
        	    m_alpha = m_alpha + frames; if m_alpha > 1 then m_alpha = 1 end
        	else
        	    m_alpha = m_alpha - frames; if m_alpha < 0 then m_alpha = 0 end 
        	end

        	if is_menu_open then
        	    m_active[' '] = nil
        	end
		end

        client.set_event_callback('paint', g_paint_handler)
	end
}

solus.watermark()
solus.keybinds()
solus.spectators()



local data = { }


--clantag
local clan_tag_prev = ""

local function time_to_ticks(time)
	return math.floor(time / globals.tickinterval() + .5)
end

local function gamesense_anim(text, indices)
	local text_anim = "               " .. text .. "                      " 
	local tickinterval = globals.tickinterval()
	local tickcount = globals.tickcount() + time_to_ticks(client.latency())
	local i = tickcount / time_to_ticks(0.5)
	i = math.floor(i % #indices)
	i = indices[i+1]+1

	return string.sub(text_anim, i, i+15)
end




---




local remove_aa = false




local function onpaint( )
    local master_switch = ui.get( master_switch )
    if not master_switch then return end

end

client.set_event_callback( 'paint_ui', function( )
  

    local master_switch = ui.get( master_switch )
    if not master_switch then return end

    b_side( )
   
    --antibrute_reset( )

   
end)




local function handle_callbacks( )
    client.color_log( 129, 198, 255, "Solace-SolusUI-Change-ClashAP" )

    --ui.set_callback( master_switch, handle_menu )
    ui.set_callback( active_tab, handle_menu )
    ui.set_callback( vis_tab.ui, handle_menu )
 



 

    --handle_menu( )
end
handle_callbacks( )
--ui.set_callback( master_switch, handle_callbacks )

local function on_player_death( e )
    if client.userid_to_entindex( e.userid ) == entity.get_local_player( ) then
        reset_data( false )
        var.lp_miss = 0
        var.enemy_shot_time = -1
        anim_timer = globals.curtime( )
        var.aa_dir = 0
    end
end

local function on_round_start( )
    reset_data( false )
    var.lp_miss = 0
    var.enemy_shot_time = -1
    anim_timer = globals.curtime( )
    var.aa_dir = 0
end

local function on_client_disconnect( )
    reset_data( false )
    var.lp_miss = 0
    var.enemy_shot_time = -1
end

local function on_game_newmap( )
    reset_data( false )
    var.lp_miss = 0
    var.enemy_shot_time = -1
end

local function on_cs_game_disconnected( )
    reset_data( false )
    var.lp_miss = 0
    var.enemy_shot_time = -1
end

local ui_callback = function(c)
	local master_switch, addr = ui.get(c), ''

	if not master_switch then
		maintxt_reset, addr = true, 'un'
	end

    handle_menu( )
	
	local _func = client[addr .. 'set_event_callback']



    _func( 'paint', onpaint )



  
    _func( 'bullet_impact', on_bullet_impact )

    _func( 'player_hurt', on_player_hurt )

    _func( 'player_death', on_player_death )

    _func( 'round_start', on_round_start )

    _func( 'client_disconnect', on_client_disconnect )

    _func( 'game_newmap', on_game_newmap )

    _func( 'cs_game_disconnected', on_cs_game_disconnected )
end
ui.set_callback(master_switch, ui_callback)
ui_callback(master_switch)

client.set_event_callback('shutdown', function()
	ui.set_visible( ref.pitch, true )
	ui.set_visible( ref.yaw_base, true )
	ui.set_visible( ref.yaw[1], true )
	ui.set_visible( ref.yaw[2], true )
	ui.set_visible( ref.yaw_jitter[1], true )
	ui.set_visible( ref.yaw_jitter[2], true )
	ui.set_visible( ref.body_yaw[1], true )
	ui.set_visible( ref.body_yaw[2], true )
	ui.set_visible( ref.freestanding_body_yaw, true )
	ui.set_visible( ref.fake_yaw_limit, true )
	ui.set_visible( ref.freestanding[2], true )
	ui.set_visible( ref.freestanding[1], true )
	ui.set_visible( ref.edge_yaw, true )
    ui.set_visible( ref.roll, true )
    ui.set_visible( ref.leg_movement, true )

    client.set_cvar("cl_sidespeed", 450)
    client.set_cvar("cl_forwardspeed", 450)
    client.set_cvar("cl_backspeed", 450)
    client.set_cvar("cl_sidespeed ", 450)
    client.set_cvar("cl_upspeed ", 450)

    local master_switch = ui.get( master_switch )
    if not master_switch then return end

    ui.set( ref.pitch, 'Off' )
    ui.set( ref.yaw_base, 'Local view' )
    ui.set( ref.yaw[1], 'Off' )
    ui.set( ref.yaw[2], '0' )
    ui.set( ref.yaw_jitter[1], 'Off' )
    ui.set( ref.yaw_jitter[2], 0 )
    ui.set( ref.body_yaw[1], 'Off' )
    ui.set( ref.body_yaw[2], 0 )
    ui.set( ref.freestanding_body_yaw, false )
    ui.set( ref.fake_yaw_limit, 60 )
    ui.set( ref.edge_yaw, false )
    ui.set( ref.roll, 0 )
end)