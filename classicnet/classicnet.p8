pico-8 cartridge // http://www.pico-8.com
version 29
__lua__
--~evercore~
--a celeste classic mod base
--v3.5 - title screen hotfix

--original game by:
--matt thorson + noel berry

--cart by: taco360
--based on meep's smalleste
--and akliant's hex loading
--with help from gonengazit

-- [data structures]

function vector(x,y)
  return {x=x,y=y}
end

function rectangle(x,y,w,h)
  return {x=x,y=y,w=w,h=h}
end

-- [globals]

objects,got_fruit,
freeze,delay_restart,sfx_timer,music_timer,
ui_timer=
{},{},
0,0,0,0,-99

-- [entry point]

function _init()
  poke(0x5f2d, 1)
  pid = stat(93)*1000+stat(94)*100+stat(95)
  frames,start_game_flash=0,0
  music(40,0,7)
  load_level(0)
end

function begin_game()
  max_djump,deaths,frames,seconds,minutes,music_timer,time_ticking=1,0,0,0,0,0,true
  music(0,0,7)
  if tonum(username) then username = "_"..username end
  send_msg("connect,"..pid..","..username)
  load_level(1)
end

function is_title()
  return lvl_id==0
end

-- [effects]

function rnd128()
  return rnd(128)
end

clouds={}
for i=0,16 do
  add(clouds,{
    x=rnd128(),
    y=rnd128(),
    spd=1+rnd(4),
    w=32+rnd(32)
  })
end

particles={}
for i=0,24 do
  add(particles,{
    x=rnd128(),
    y=rnd128(),
    s=flr(rnd(1.25)),
    spd=0.25+rnd(5),
    off=rnd(1),
    c=6+rnd(2),
  })
end

dead_particles={}

-- [player entity]

player={
  init=function(this) 
    this.grace,this.jbuffer=0,0
    this.djump=max_djump
    this.dash_time,this.dash_effect_time=0,0
    this.dash_target_x,this.dash_target_y=0,0
    this.dash_accel_x,this.dash_accel_y=0,0
    this.hitbox=rectangle(1,3,6,5)
    this.spr_off=0
    this.solids=true
    create_hair(this)
  end,
  update=function(this)
    if pause_player then
      return
    end
    
    -- horizontal input
    local h_input=btn(➡️) and 1 or btn(⬅️) and -1 or 0
    
    -- spike collision / bottom death
    if spikes_at(this.x+this.hitbox.x,this.y+this.hitbox.y,this.hitbox.w,this.hitbox.h,this.spd.x,this.spd.y)
	   or	this.y>lvl_ph then
	    kill_player(this)
    end

    -- on ground checks
    local on_ground=this.is_solid(0,1)
    
    -- landing smoke
    if on_ground and not this.was_on_ground then
      this.init_smoke(0,4)
    end

    -- jump and dash input
    local jump,dash=btn(🅾️) and not this.p_jump,btn(❎) and not this.p_dash
    this.p_jump,this.p_dash=btn(🅾️),btn(❎)

    -- jump buffer
    if jump then
      this.jbuffer=4
    elseif this.jbuffer>0 then
      this.jbuffer-=1
    end
    
    -- grace frames and dash restoration
    if on_ground then
      this.grace=6
      if this.djump<max_djump then
        psfx(54)
        this.djump=max_djump
      end
    elseif this.grace>0 then
      this.grace-=1
    end

    -- dash effect timer (for dash-triggered events, e.g., berry blocks)
    this.dash_effect_time-=1

    -- dash startup period, accel toward dash target speed
    if this.dash_time>0 then
      this.init_smoke()
      this.dash_time-=1
      this.spd=vector(appr(this.spd.x,this.dash_target_x,this.dash_accel_x),appr(this.spd.y,this.dash_target_y,this.dash_accel_y))
    else
      -- x movement
      local maxrun=1
      local accel=this.is_ice(0,1) and 0.05 or on_ground and 0.6 or 0.4
      local deccel=0.15
    
      -- set x speed
      this.spd.x=abs(this.spd.x)<=1 and 
        appr(this.spd.x,h_input*maxrun,accel) or 
        appr(this.spd.x,sign(this.spd.x)*maxrun,deccel)
      
      -- facing direction
      if this.spd.x~=0 then
        this.flip.x=(this.spd.x<0)
      end

      -- y movement
      local maxfall=2
    
      -- wall slide
      if h_input~=0 and this.is_solid(h_input,0) and not this.is_ice(h_input,0) then
        maxfall=0.4
        -- wall slide smoke
        if rnd(10)<2 then
          this.init_smoke(h_input*6)
        end
      end

      -- apply gravity
      if not on_ground then
        this.spd.y=appr(this.spd.y,maxfall,abs(this.spd.y)>0.15 and 0.21 or 0.105)
      end

      -- jump
      if this.jbuffer>0 then
        if this.grace>0 then
          -- normal jump
          psfx(1)
          this.jbuffer=0
          this.grace=0
          this.spd.y=-2
          this.init_smoke(0,4)
        else
          -- wall jump
          local wall_dir=(this.is_solid(-3,0) and -1 or this.is_solid(3,0) and 1 or 0)
          if wall_dir~=0 then
            psfx(2)
            this.jbuffer=0
            this.spd.y=-2
            this.spd.x=-wall_dir*(maxrun+1)
            if not this.is_ice(wall_dir*3,0) then
              -- wall jump smoke
              this.init_smoke(wall_dir*6)
            end
          end
        end
      end
    
      -- dash
      local d_full=5
      local d_half=3.5355339059 -- 5 * sqrt(2)
    
      if this.djump>0 and dash then
        this.init_smoke()
        this.djump-=1   
        this.dash_time=4
        has_dashed=true
        this.dash_effect_time=10
        -- vertical input
        local v_input=btn(⬆️) and -1 or btn(⬇️) and 1 or 0
        -- calculate dash speeds
        this.spd=vector(h_input~=0 and 
        h_input*(v_input~=0 and d_half or d_full) or 
        (v_input~=0 and 0 or this.flip.x and -1 or 1)
        ,v_input~=0 and v_input*(h_input~=0 and d_half or d_full) or 0)
        -- effects
        psfx(3)
        freeze=2
        -- dash target speeds and accels
        this.dash_target_x=2*sign(this.spd.x)
        this.dash_target_y=(this.spd.y>=0 and 2 or 1.5)*sign(this.spd.y)
        this.dash_accel_x=this.spd.y==0 and 1.5 or 1.06066017177 -- 1.5 * sqrt()
        this.dash_accel_y=this.spd.x==0 and 1.5 or 1.06066017177
      elseif this.djump<=0 and dash then
        -- failed dash smoke
        psfx(9)
        this.init_smoke()
      end
    end
    
    -- animation
    this.spr_off+=0.25
    this.spr = not on_ground and (this.is_solid(h_input,0) and 5 or 3) or  -- wall slide or mid air
      btn(⬇️) and 6 or -- crouch
      btn(⬆️) and 7 or -- look up
      1+(this.spd.x~=0 and h_input~=0 and this.spr_off%4 or 0) -- walk or stand
    
   	--move camera to player
   	--this must be before next_level
   	--to avoid loading jank
    move_camera(this)
    
    -- exit level off the top (except summit)
    if this.y<-4 and levels[lvl_id+1] then
      --next_level()
    end
    
    -- was on the ground
    this.was_on_ground=on_ground

    if upd_send_timer > 0 then
      upd_send_timer-=1
      if upd_send_timer==0 then
        if tonum(username) then username = "_"..username end
        send_msg("update,"..pid..","..this.x..","..this.y..","..this.spr..","..this.djump..","..(this.flip.x and 1 or 0)..","..this.dash_time)
        upd_send_timer=UPDATE_SEND_RATE
      end
    end
  end,
  
  draw=function(this)
    -- clamp in screen
  		if this.x<-1 or this.x>lvl_pw-7 then
   		this.x=clamp(this.x,-1,lvl_pw-7)
   		this.spd.x=0
  		end
    -- draw player hair and sprite
    set_hair_color(this.djump)
    draw_hair(this,this.flip.x and -1 or 1)
    spr(this.spr,this.x,this.y,1,1,this.flip.x,this.flip.y)
    unset_hair_color()
    print(username, this.x+4-(#username*2), this.y-6, 7)
  end
}

function create_hair(obj)
  obj.hair={}
  for i=1,5 do
    add(obj.hair,vector(obj.x,obj.y))
  end
end

function set_hair_color(djump)
  pal(8,djump==1 and 8 or djump==2 and 7+(frames\3)%2*4 or 12)
end

function draw_hair(obj,facing)
  local last=vector(obj.x+4-facing*2,obj.y+(btn(⬇️) and 4 or 3))
  for i,h in pairs(obj.hair) do
    h.x+=(last.x-h.x)/1.5
    h.y+=(last.y+0.5-h.y)/1.5
    circfill(h.x,h.y,clamp(4-i,1,2),8)
    last=h
  end
end

function unset_hair_color()
  pal(8,8)
end

extern_player={
  init=function (this)
    this.dash_time=0
    create_hair(this)
  end,
  update=function(this)
    if this.dash_time > 0 then
      this.init_smoke()
    end
  end,
  draw=function(this)
    -- draw player hair and sprite
    set_hair_color(this.djump)
    draw_hair(this,this.flip.x and -1 or 1)
    spr(this.spr,this.x,this.y,1,1,this.flip.x,this.flip.y)
    unset_hair_color()
    print(this.name, this.x+4-(#(this.name)*2), this.y-6, 7)
  end
}

-- [other entities]

player_spawn={
  init=function(this)
    sfx(4)
    this.spr=3
    this.target=this.y
    this.y=min(this.y+48,lvl_ph)
		cam_x=clamp(this.x,64,lvl_pw-64)
		cam_y=clamp(this.y,64,lvl_ph-64)
    this.spd.y=-4
    this.state=0
    this.delay=0
    create_hair(this)
  end,
  update=function(this)
    -- jumping up
    if this.state==0 then
      if this.y<this.target+16 then
        this.state=1
        this.delay=3
      end
    -- falling
    elseif this.state==1 then
      this.spd.y+=0.5
      if this.spd.y>0 then
        if this.delay>0 then
          -- stall at peak
          this.spd.y=0
          this.delay-=1
        elseif this.y>this.target then
          -- clamp at target y
          this.y=this.target
          this.spd=vector(0,0)
          this.state=2
          this.delay=5
          this.init_smoke(0,4)
          sfx(5)
        end
      end
    -- landing and spawning player object
    elseif this.state==2 then
      this.delay-=1
      this.spr=6
      if this.delay<0 then
        destroy_object(this)
        init_object(player,this.x,this.y)
      end
    end
    move_camera(this)
  end,
  draw=function(this)
    set_hair_color(max_djump)
    draw_hair(this,1)
    spr(this.spr,this.x,this.y)
    unset_hair_color()
  end
}

spring={
  init=function(this)
    this.hide_in=0
    this.hide_for=0
  end,
  update=function(this)
    if this.hide_for>0 then
      this.hide_for-=1
      if this.hide_for<=0 then
        this.spr=18
        this.delay=0
      end
    elseif this.spr==18 then
      local hit=this.player_here()
      if hit and hit.spd.y>=0 then
        this.spr=19
        hit.y=this.y-4
        hit.spd.x*=0.2
        hit.spd.y=-3
        hit.djump=max_djump
        this.delay=10
        this.init_smoke()
        -- crumble below spring
        local below=this.check(fall_floor,0,1)
        if below then
          break_fall_floor(below)
        end
        psfx(8)
      end
    elseif this.delay>0 then
      this.delay-=1
      if this.delay<=0 then 
        this.spr=18 
      end
    end
    -- begin hiding
    if this.hide_in>0 then
      this.hide_in-=1
      if this.hide_in<=0 then
        this.hide_for=60
        this.spr=0
      end
    end
  end
}


balloon={
  init=function(this) 
    this.offset=rnd(1)
    this.start=this.y
    this.timer=0
    this.hitbox=rectangle(-1,-1,10,10)
  end,
  update=function(this) 
    if this.spr==22 then
      this.offset+=0.01
      this.y=this.start+sin(this.offset)*2
      local hit=this.player_here()
      if hit and hit.djump<max_djump then
        psfx(6)
        this.init_smoke()
        hit.djump=max_djump
        this.spr=0
        this.timer=60
      end
    elseif this.timer>0 then
      this.timer-=1
    else 
      psfx(7)
      this.init_smoke()
      this.spr=22 
    end
  end,
  draw=function(this)
    if this.spr==22 then
      spr(13+this.offset*8%3,this.x,this.y+6)
      spr(this.spr,this.x,this.y)
    end
  end
}

fall_floor={
  init=function(this)
    this.state=0
  end,
  update=function(this)
    -- idling
    if this.state==0 then
      if this.check(player,0,-1) or this.check(player,-1,0) or this.check(player,1,0) then
        break_fall_floor(this)
      end
    -- shaking
    elseif this.state==1 then
      this.delay-=1
      if this.delay<=0 then
        this.state=2
        this.delay=60--how long it hides for
        this.collideable=false
      end
    -- invisible, waiting to reset
    elseif this.state==2 then
      this.delay-=1
      if this.delay<=0 and not this.player_here() then
        psfx(7)
        this.state=0
        this.collideable=true
        this.init_smoke()
      end
    end
  end,
  draw=function(this)
    if this.state~=2 then
      if this.state~=1 then
        spr(23,this.x,this.y)
      else
        spr(26-this.delay/5,this.x,this.y)
      end
    end
  end
}

function break_fall_floor(obj)
 if obj.state==0 then
  psfx(15)
    obj.state=1
    obj.delay=15--how long until it falls
    obj.init_smoke()
    local hit=obj.check(spring,0,-1)
    if hit then
      hit.hide_in=15
    end
  end
end

smoke={
  init=function(this)
    this.spd=vector(0.3+rnd(0.2),-0.1)
    this.x+=-1+rnd(2)
    this.y+=-1+rnd(2)
    this.flip=vector(maybe(),maybe())
  end,
  update=function(this)
    this.spr+=0.2
    if this.spr>=32 then
      destroy_object(this)
    end
  end
}

fruit={
  if_not_fruit=true,
  init=function(this) 
    this.start=this.y
    this.off=0
  end,
  update=function(this)
    check_fruit(this)
    this.off+=0.025
    this.y=this.start+sin(this.off)*2.5
  end
}

fly_fruit={
  if_not_fruit=true,
  init=function(this) 
    this.start=this.y
    this.step=0.5
    this.sfx_delay=8
  end,
  update=function(this)
    --fly away
    if has_dashed then
     if this.sfx_delay>0 then
      this.sfx_delay-=1
      if this.sfx_delay<=0 then
       sfx_timer=20
       sfx(14)
      end
     end
      this.spd.y=appr(this.spd.y,-3.5,0.25)
      if this.y<-16 then
        destroy_object(this)
      end
    -- wait
    else
      this.step+=0.05
      this.spd.y=sin(this.step)*0.5
    end
    -- collect
    check_fruit(this)
  end,
  draw=function(this)
    draw_obj_sprite(this)
    for ox=-6,6,12 do
      spr(has_dashed or sin(this.off)>=0 and 45 or (this.y>this.start and 47 or 46),this.x+ox,this.y-2,1,1,ox==-6)
    end
  end
}

function check_fruit(this)
  local hit=this.player_here()
  if hit then
    hit.djump=max_djump
    sfx_timer=20
    sfx(13)
    got_fruit[lvl_id]=true
    init_object(lifeup,this.x,this.y)
    destroy_object(this)
  end
end

lifeup={
  init=function(this)
    this.spd.y=-0.25
    this.duration=30
    this.x-=2
    this.y-=4
    this.flash=0
  end,
  update=function(this)
    this.duration-=1
    if this.duration<=0 then
      destroy_object(this)
    end
  end,
  draw=function(this)
    this.flash+=0.5
    ?"1000",this.x-2,this.y,7+this.flash%2
  end
}

fake_wall={
  if_not_fruit=true,
  update=function(this)
    this.hitbox=rectangle(-1,-1,18,18)
    local hit=this.player_here()
    if hit and hit.dash_effect_time>0 then
      hit.spd=vector(sign(hit.spd.x)*-1.5,-1.5)
      hit.dash_time=-1
      for ox=0,8,8 do
        for oy=0,8,8 do
          this.init_smoke(ox,oy)
        end
      end
      init_fruit(this,4,4)
    end
    this.hitbox=rectangle(0,0,16,16)
  end,
  draw=function(this)
    sspr(0,32,16,16,this.x,this.y)
  end
}

function init_fruit(this,ox,oy)
  sfx_timer=20
  sfx(16)
  init_object(fruit,this.x+ox,this.y+oy,26)
  destroy_object(this)
end

key={
  if_not_fruit=true,
  update=function(this)
    local was=flr(this.spr)
    this.spr=9.5+sin(frames/30)
    if this.spr==10 and this.spr~=was then
      this.flip.x=not this.flip.x
    end
    if this.player_here() then
      sfx(23)
      sfx_timer=10
      destroy_object(this)
      has_key=true
    end
  end
}

chest={
  if_not_fruit=true,
  init=function(this)
    this.x-=4
    this.start=this.x
    this.timer=20
  end,
  update=function(this)
    if has_key then
      this.timer-=1
      this.x=this.start-1+rnd(3)
      if this.timer<=0 then
        init_fruit(this,0,-4)
      end
    end
  end
}

platform={
  init=function(this)
    this.x-=4
    this.hitbox.w=16
    this.last=this.x
    this.dir=this.spr==11 and -1 or 1
  end,
  update=function(this)
    this.spd.x=this.dir*0.65
    if this.x<-16 then this.x=lvl_pw
    elseif this.x>lvl_pw then this.x=-16 end
    if not this.player_here() then
      local hit=this.check(player,0,-1)
      if hit then
        hit.move(this.x-this.last,0,1)
      end
    end
    this.last=this.x
  end,
  draw=function(this)
    spr(11,this.x,this.y-1,2,1)
  end
}

message={
  draw=function(this)
    this.text="-- celeste mountain --#this memorial to those# perished on the climb"
    if this.check(player,4,0) then
      if this.index<#this.text then
       this.index+=0.5
        if this.index>=this.last+1 then
          this.last+=1
          sfx(35)
        end
      end
      local _x,_y=8,96
      for i=1,this.index do
        if sub(this.text,i,i)~="#" then
          rectfill(_x-2,_y-2,_x+7,_y+6 ,7)
          ?sub(this.text,i,i),_x,_y,0
          _x+=5
        else
          _x=8
          _y+=7
        end
      end
    else
      this.index=0
      this.last=0
    end
  end
}

big_chest={
  init=function(this)
    this.state=0
    this.hitbox.w=16
  end,
  draw=function(this)
    if this.state==0 then
      local hit=this.check(player,0,8)
      if hit and hit.is_solid(0,1) then
        music(-1,500,7)
        sfx(37)
        pause_player=true
        hit.spd=vector(0,0)
        this.state=1
        this.init_smoke()
        this.init_smoke(8)
        this.timer=60
        this.particles={}
      end
      sspr(0,48,16,8,this.x,this.y)
    elseif this.state==1 then
      this.timer-=1
      flash_bg=true
      if this.timer<=45 and #this.particles<50 then
        add(this.particles,{
          x=1+rnd(14),
          y=0,
          h=32+rnd(32),
          spd=8+rnd(8)
        })
      end
      if this.timer<0 then
        this.state=2
        this.particles={}
        flash_bg=false
        new_bg=true
        init_object(orb,this.x+4,this.y+4)
        pause_player=false
      end
      foreach(this.particles,function(p)
        p.y+=p.spd
        line(this.x+p.x,this.y+8-p.y,this.x+p.x,min(this.y+8-p.y+p.h,this.y+8),7)
      end)
    end
    sspr(0,56,16,8,this.x,this.y+8)
  end
}

orb={
  init=function(this)
    this.spd.y=-4
  end,
  draw=function(this)
    this.spd.y=appr(this.spd.y,0,0.5)
    local hit=this.player_here()
    if this.spd.y==0 and hit then
     music_timer=45
      sfx(51)
      freeze=10
      destroy_object(this)
      max_djump=2
      hit.djump=2
    end
    spr(102,this.x,this.y)
    for i=0,0.875,0.125 do
      circfill(this.x+4+cos(frames/30+i)*8,this.y+4+sin(frames/30+i)*8,1,7)
    end
  end
}

flag={
  init=function(this)
    this.x+=5
    this.score=0
    for _ in pairs(got_fruit) do
      this.score+=1
    end
  end,
  draw=function(this)
    this.spr=118+frames/5%3
    draw_obj_sprite(this)
    if this.show then
      rectfill(32,2,96,31,0)
      spr(26,55,6)
      ?"x"..this.score,64,9,7
      draw_time(49,16)
      ?"deaths:"..deaths,48,24,7
    elseif this.player_here() then
      sfx(55)
      sfx_timer,this.show,time_ticking=30,true,false
    end
  end
}

psfx=function(num)
  if sfx_timer<=0 then
   sfx(num)
  end
end

-- [tile dict]
tiles={
  [1]=player_spawn,
  [8]=key,
  [11]=platform,
  [12]=platform,
  [18]=spring,
  [20]=chest,
  [22]=balloon,
  [23]=fall_floor,
  [26]=fruit,
  [28]=fly_fruit,
  [64]=fake_wall,
  [86]=message,
  [96]=big_chest,
  [118]=flag
}

-- [object functions]

function init_object(type,x,y,tile)
  if type.if_not_fruit and got_fruit[lvl_id] then
    return
  end

  local obj={
    type=type,
    collideable=true,
    solids=false,
    spr=tile,
    flip=vector(false,false),
    x=x,
    y=y,
    hitbox=rectangle(0,0,8,8),
    spd=vector(0,0),
    rem=vector(0,0),
  }

  function obj.is_solid(ox,oy)
    return (oy>0 and not obj.check(platform,ox,0) and obj.check(platform,ox,oy)) or
           obj.is_flag(ox,oy,0) or 
           obj.check(fall_floor,ox,oy) or
           obj.check(fake_wall,ox,oy)
  end
  
  function obj.is_ice(ox,oy)
    return obj.is_flag(ox,oy,4)
  end
  
  function obj.is_flag(ox,oy,flag)
    return tile_flag_at(obj.x+obj.hitbox.x+ox,obj.y+obj.hitbox.y+oy,obj.hitbox.w,obj.hitbox.h,flag)
  end

  function obj.check(type,ox,oy)
    for other in all(objects) do
      if other and other.type==type and other~=obj and other.collideable and
        other.x+other.hitbox.x+other.hitbox.w>obj.x+obj.hitbox.x+ox and 
        other.y+other.hitbox.y+other.hitbox.h>obj.y+obj.hitbox.y+oy and
        other.x+other.hitbox.x<obj.x+obj.hitbox.x+obj.hitbox.w+ox and 
        other.y+other.hitbox.y<obj.y+obj.hitbox.y+obj.hitbox.h+oy then
        return other
      end
    end
  end

  function obj.player_here()
    return obj.check(player,0,0)
  end
  
  function obj.move(ox,oy,start)
    for axis in all({"x","y"}) do
      obj.rem[axis]+=axis=="x" and ox or oy
      local amt=flr(obj.rem[axis]+0.5)
      obj.rem[axis]-=amt
      if obj.solids then
        local step=sign(amt)
        local d=axis=="x" and step or 0
        for i=start,abs(amt) do
          if not obj.is_solid(d,step-d) then
            obj[axis]+=step
          else
            obj.spd[axis],obj.rem[axis]=0,0
            break
          end
        end
      else
        obj[axis]+=amt
      end
    end
  end

  function obj.init_smoke(ox,oy) 
    init_object(smoke,obj.x+(ox or 0),obj.y+(oy or 0),29)
  end

  add(objects,obj)

  if obj.type.init then
    obj.type.init(obj)
  end

  return obj
end

function destroy_object(obj)
  del(objects,obj)
end

function kill_player(obj)
  sfx_timer=12
  sfx(0)
  deaths+=1
  destroy_object(obj)
  dead_particles={}
  for dir=0,0.875,0.125 do
    add(dead_particles,{
      x=obj.x+4,
      y=obj.y+4,
      t=2,
      dx=sin(dir)*3,
      dy=cos(dir)*3
    })
  end
  delay_restart=15
end

-- [room functions]


function next_level()
  local next_lvl=lvl_id+1
  if next_lvl==3 then --wind music
    music(30,500,7)
  elseif next_lvl==2 then
    music(20,500,7)
  end
  load_level(next_lvl)
end

function load_level(lvl)
  has_dashed=false
  has_key=false
  
  --remove existing objects
  foreach(objects,destroy_object)
  
  --reset camera speed
  cam_spdx=0
		cam_spdy=0
		
  local diff_room=lvl_id~=lvl
  
		--set level index
  lvl_id=lvl
  
  --set level globals
  local tbl=get_lvl()
  lvl_x,lvl_y,lvl_w,lvl_h,lvl_title=tbl[1],tbl[2],tbl[3]*16,tbl[4]*16,tbl[5]
  lvl_pw=lvl_w*8
  lvl_ph=lvl_h*8
  
  
  --reload map
  --level title setup
  if not is_title() then
   if diff_room then reload() end 
  	ui_timer=5
  end
  
  --chcek for hex mapdata
  if diff_room and get_data() then
  	--replace old rooms with data
  	for i=0,get_lvl()[3]-1 do
      for j=0,get_lvl()[4]-1 do
        replace_room(lvl_x+i,lvl_y+j,get_data()[i*get_lvl()[4]+j+1])
      end
  	end
  end
  
  -- entities
  for tx=0,lvl_w-1 do
    for ty=0,lvl_h-1 do
      local tile=mget(lvl_x*16+tx,lvl_y*16+ty)
      if tiles[tile] then
        init_object(tiles[tile],tx*8,ty*8,tile)
      end
    end
  end

  if lvl ~= 0 then
    for c in all(clients) do
      local o=nil
      for v in all(objects) do
        if v.pid==c.pid then
          o=v
          break
        end
      end
      if not o then
        o = init_object(extern_player, 64, 64)
        o.pid = c.pid
        o.name = c.name
      end
    end
  end
end

-- [main update loop]

function _update()
  frames+=1
  if time_ticking then
    seconds+=frames\30
    minutes+=seconds\60
    seconds%=60
  end
  frames%=30
  
  if music_timer>0 then
    music_timer-=1
    if music_timer<=0 then
      music(10,0,7)
    end
  end
  
  if sfx_timer>0 then
    sfx_timer-=1
  end
  
  -- cancel if freeze
  if freeze>0 then 
    freeze-=1
    return
  end
  
  -- restart (soon)
  if delay_restart>0 then
  		cam_spdx,cam_spdy=0,0
    delay_restart-=1
    if delay_restart==0 then
      load_level(lvl_id)
    end
  end

  -- update each object
  foreach(objects,function(obj)
    obj.move(obj.spd.x,obj.spd.y,0)
    if obj.type.update then
      obj.type.update(obj)
    end
  end)
  
  -- start game
  if is_title() then
    if start_game then
      start_game_flash-=1
      if start_game_flash<=-30 then
        begin_game()
      end
    elseif btn(2) then
      music(-1)
      start_game_flash,start_game=50,true
      sfx(38)
    end
    if stat(30) then
      local c = stat(31)
      if c=="\b" then
        username = sub(username, 1, #username-1)
      elseif c ~= "," then
        username = username..c
      end
    end
  end
end

-- [drawing functions]

function _draw()
  if freeze>0 then
    return
  end
  
  -- reset all palette values
  pal()
  
  -- start game flash
  if is_title() and start_game then
    local c=start_game_flash>10 and (frames%10<5 and 7 or 10) or (start_game_flash>5 and 2 or start_game_flash>0 and 1 or 0)
    if c<10 then
      for i=1,15 do
        pal(i,c)
      end
    end
  end
		
		--set cam draw position
  local camx=is_title() and 0 or round(cam_x)-64
  local camy=is_title() and 0 or round(cam_y)-64
  camera(camx,camy)

  --local token saving
  local xtiles=lvl_x*16
  local ytiles=lvl_y*16
  
  -- draw bg color
  cls(flash_bg and frames/5 or new_bg and 2 or 0)

  -- bg clouds effect
  if not is_title() then
    foreach(clouds, function(c)
      c.x+=c.spd-cam_spdx
      rectfill(c.x+camx,c.y+camy,c.x+c.w+camx,c.y+16-c.w*0.1875+camy,new_bg and 14 or 1)
      if c.x>128 then
        c.x=-c.w
        c.y=rnd(120)
      end
    end)
  end

		-- draw bg terrain
  map(xtiles,ytiles,0,0,lvl_w,lvl_h,4)
		
		-- platforms
  foreach(objects, function(o)
    if o.type==platform then
      draw_object(o)
    end
  end)
		
  -- draw terrain
  map(xtiles,ytiles,0,0,lvl_w,lvl_h,2)
  
  -- draw objects
  foreach(objects, function(o)
    if o.type~=platform then
      draw_object(o)
    end
  end)
  
  -- particles
  foreach(particles, function(p)
    p.x+=p.spd-cam_spdx
    p.y+=sin(p.off)-cam_spdy
    p.off+=min(0.05,p.spd/32)
    rectfill(p.x+camx,p.y%128+camy,p.x+p.s+camx,p.y%128+p.s+camy,p.c)
    if p.x>132 then 
      p.x=-4
      p.y=rnd128()
   	elseif p.x<-4 then
     	p.x=128
     	p.y=rnd128()
    end
  end)
  
  -- dead particles
  foreach(dead_particles, function(p)
    p.x+=p.dx
    p.y+=p.dy
    p.t-=0.2
    if p.t<=0 then
      del(dead_particles,p)
    end
    rectfill(p.x-p.t,p.y-p.t,p.x+p.t,p.y+p.t,14+5*p.t%2)
  end)
  
  -- draw level title
  --if ui_timer>=-30 then
  	--if ui_timer<0 then
  if not connected and not is_title() then
    ?"not connected",camx+1,camy+1,8
  end
  draw_ui(camx,camy)
  	--end
  	--ui_timer-=1
  --end
  
  -- credits
  if is_title() then
				sspr(72,32,56,32,36,32)
    ?"⬆️ to start",44,80,5
    ?"matt thorson",42,96,5
    ?"noel berry",46,102,5
    ?"username: "..username,46-(#username*2),110,7
  end
    update_msgs()

end


function draw_object(obj)
  (obj.type.draw or draw_obj_sprite)(obj)
end

function draw_obj_sprite(obj)
  spr(obj.spr,obj.x,obj.y,1,1,obj.flip.x,obj.flip.y)
end

function draw_time(x,y)
  rectfill(x,y,x+32,y+6,0)
  ?two_digit_str(minutes\60)..":"..two_digit_str(minutes%60)..":"..two_digit_str(seconds),x+1,y+1,7
end

function draw_ui(camx,camy)
  --?#omsg_queue, camx+1, camy+8, 7
  --?#imsg_queue, camx+1, camy+16, 7
end

function two_digit_str(x)
  return x<10 and "0"..x or x
end

-- [helper functions]

function round(x)
  return flr(x+0.5)
end

function clamp(val,a,b)
  return max(a,min(b,val))
end

function appr(val,target,amount)
  return val>target and max(val-amount,target) or min(val+amount,target)
end

function sign(v)
  return v~=0 and sgn(v) or 0
end

function maybe()
  return rnd(1)<0.5
end

function tile_flag_at(x,y,w,h,flag)
  for i=max(0,x\8),min(lvl_w-1,(x+w-1)/8) do
    for j=max(0,y\8),min(lvl_h-1,(y+h-1)/8) do
      if fget(tile_at(i,j),flag) then
        return true
      end
    end
  end
end

function tile_at(x,y)
  return mget(lvl_x*16+x,lvl_y*16+y)
end

function spikes_at(x,y,w,h,xspd,yspd)
  for i=max(0,x\8),min(lvl_w-1,(x+w-1)/8) do
    for j=max(0,y\8),min(lvl_h-1,(y+h-1)/8) do
      local tile=tile_at(i,j)
      if (tile==17 and ((y+h-1)%8>=6 or y+h==j*8+8) and yspd>=0) or
         (tile==27 and y%8<=2 and yspd<=0) or
         (tile==43 and x%8<=2 and xspd<=0) or
         (tile==59 and ((x+w-1)%8>=6 or x+w==i*8+8) and xspd>=0) then
         return true
      end
    end
  end
end
-->8
--scrolling level stuff

--level table
--strings follow this format:
--"x,y,w,h,title"
levels={
	[0]="-1,-1,1,1", --title screen
	"0,0,4,4"
}

--mapdata table
--rooms separated by commas
mapdata={
	[2]="25252525332b000000000000000000002525252600000000000000000000000025253233001a0000000000000000000025261b1b0000000000000000000000002526000000000000000000000000000025330000000000000000000000000000332b0000000000000000000000000000280000000000000000000000002c000038390000000000000000003d3e3c0000282900002c000000000039212223393a2828293f3c000000003a38313233283828382122233d013f3a382829002a2a282222252525222223282828001600002925252525252532331029290000000000252525252526002a290000000000000025252525252600000000000000000000,0000000000000000000000000024252500000000000000000000000000242525000000000000000000000000003125250000003a0000003900000000000031320000002839003a38393f000000001b1b00000028103a28212223000000000000003e3a3828282831323300000000000000212223292a290000000000000000003a31323300000000160000000000000028102900000000000000000000000000282900000000000000000000000000002900000000000000000000000000000000000000000000000000000000000000000000000000000000000000001111110000000000000000000000111121222200000000000000000000002122252525"
}

function get_lvl()
	return split(levels[lvl_id])
end

function get_data()
	return split(mapdata[lvl_id],",",false)
end

--not using tables to conserve tokens
cam_x=0
cam_y=0
cam_spdx=0
cam_spdy=0
cam_gain=0.25

function move_camera(obj)
  --set camera speed
  cam_spdx=cam_gain*(4+obj.x+0*obj.spd.x-cam_x)
  cam_spdy=cam_gain*(4+obj.y+0*obj.spd.y-cam_y)

  cam_x+=cam_spdx
  cam_y+=cam_spdy

  if cam_x<64 or cam_x>lvl_pw-64 then
    cam_spdx=0
    cam_x=clamp(cam_x,64,lvl_pw-64)
  end
  if cam_y<64 or cam_y>lvl_ph-64 then
    cam_spdy=0
    cam_y=clamp(cam_y,64,lvl_ph-64)
  end
end

--replace mapdata with hex
function replace_room(x,y,room)
 for y_=1,32,2 do
  for x_=1,32,2 do
   local offset=4096+(y<2 and 4096 or -4096)
   local hex=sub(room,x_+(y_-1)*16,x_+(y_-1)*16+1)
   poke(offset+x*16+y*2048+(y_-1)*64+x_/2, "0x"..hex)
  end
 end
end

--[[

short on tokens?
everything below this comment
is just for grabbing data
rather than loading it
and can be safely removed!

--]]

--returns mapdata string of level
--printh(get_room(),"@clip")
function get_room(x,y)
  local reserve=""
  local offset=4096+(y<2 and 4096 or 0)
  y=y%2
  for y_=1,32,2 do
    for x_=1,32,2 do
      reserve=reserve..num2hex(peek(offset+x*16+y*2048+(y_-1)*64+x_/2))
    end
  end
  return reserve
end

--convert mapdata to memory data
function num2hex(number)
 local resultstr=""
 while number>0 do
  local remainder=1+number%16
  number\=16
  resultstr=sub("0123456789abcdef",remainder,remainder)..resultstr
 end
 return #resultstr==0 and "00" or #resultstr==1 and "0"..resultstr or resultstr
end

-->8
--networking
chars=" !\"#$%&'()*+,-./0123456789:;<=>?@abcdefghijklmnopqrstuvwxyz[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
s2c={} c2s={}
for i=1,95 do
  c=i+31
  s=sub(chars,i,i)
  c2s[c]=s
  s2c[s]=c
end

omsg_queue={} 
omsg=nil 
imsg=""

function split_str(str,sep)
 astr={} index=0
 for i=1,#str do
  if (sub(str,i,i)==sep) then
   chunk=sub(str,index,i-1)
   index=i+1
    add(astr,chunk)
  end
 end
 chunk=sub(str,index,#str)
 add(astr,chunk)
 return astr
end

function send_msg(msg)
  if #omsg_queue>4 then omsg_queue={} end
  add(omsg_queue,msg)
end

function update_msgs()
  update_omsgs()
  update_imsgs()
end

function update_omsgs()
  if (peek(0x5f80)==1) return
 
  if (omsg==nil and count(omsg_queue)>0) then
    omsg=omsg_queue[1]
    del(omsg_queue,omsg)
  end 
    
  if (omsg!=nil) then
   poke(0x5f80,1)
    memset(0x5f81,0,63)
    chunk=sub(omsg,0,63)
    for i=1,#chunk do
      poke(0x5f80+i,s2c[sub(chunk,i,i)])
    end
    omsg=sub(omsg,64)
    if (#omsg==0) then
      omsg=nil
      if (#chunk==63) poke(0x5f80,2)
    end
  end
end

function update_imsgs()
  control=peek(0x5fc0)
  if (control==1 or control==2) then
    for i=1,63 do
      char=peek(0x5fc0+i)
      if (char==0) then
        process_input()
        imsg=""
        break
      end
      imsg=imsg..c2s[char]
    end
    if (control==2) then
      process_input()
      imsg=""
    end
    poke(0x5fc0,0)
  end
end

clients={}
pid=0
username=""
upd_send_timer=1
UPDATE_SEND_RATE=1
connected = false

function process_input()
  data = split(imsg)
  if data[1]=="connect" then
    if data[2]==pid then 
      connected = true
      return
    end
    local c = {}
    c.pid = data[2]
    c.name = data[3]
    local o = init_object(extern_player, 64, 64)
    o.pid = c.pid
    o.name = c.name
    add(clients, c)
    if tonum(username) then username = "_"..username end
    send_msg("sync,"..pid..","..username)
  elseif data[1]=="sync" then
    if data[2]==pid then return end
    local c = {}
    c.pid = data[2]
    c.name = data[3]
    local o = init_object(extern_player, 64, 64)
    o.pid = c.pid
    o.name = c.name
    add(clients, c)
  elseif data[1]=="update" then
    if data[2]==pid then return end
    local o
    for v in all(objects) do
      if v.pid==data[2] then
        o=v
        break
      end
    end
    if not o then return end
    o.x = data[3]
    o.y = data[4]
    o.spr = data[5]
    o.djump = data[6]
    o.flip.x = data[7]==1
    o.dash_time = data[8]
  end
end

__gfx__
000000000000000000000000088888800000000000000000000000000000000000aaaaa0000aaa000000a0000007707770077700000060000000600000060000
000000000888888008888880888888880888888008888800000000000888888000a000a0000a0a000000a0000777777677777770000060000000600000060000
000000008888888888888888888ffff888888888888888800888888088f1ff1800a909a0000a0a000000a0007766666667767777000600000000600000060000
00000000888ffff8888ffff888f1ff18888ffff88ffff8808888888888fffff8009aaa900009a9000000a0007677766676666677000600000000600000060000
0000000088f1ff1888f1ff1808fffff088f1ff1881ff1f80888ffff888fffff80000a0000000a0000000a0000000000000000000000600000006000000006000
0000000008fffff008fffff00033330008fffff00fffff8088fffff8083333800099a0000009a0000000a0000000000000000000000600000006000000006000
00000000003333000033330007000070073333000033337008f1ff10003333000009a0000000a0000000a0000000000000000000000060000006000000006000
000000000070070000700070000000000000070000007000077333700070070000aaa0000009a0000000a0000000000000000000000060000006000000006000
55555555000000000000000000000000000000000000000000888800499999944999999449990994001111006665666500111100000000000000000070000000
55555555000000000000000000000000000000000000000008888880911111199111411991140919077117706765676501111110007700000770070007000007
550000550000000000000000000000000aaaaaa00000000008788880911111199111911949400419177117716770677011711711007770700777000000000000
55000055007000700499994000000000a998888a1111111108888880911111199494041900000044ee1991ee0700070011199111077777700770000000000000
55000055007000700050050000000000a988888a1000000108888880911111199114094994000000111111110700070011111111077777700000700000000000
55000055067706770005500000000000aaaaaaaa1111111108888880911111199111911991400499117777110000000011777711077777700000077000000000
55555555567656760050050000000000a980088a1444444100888800911111199114111991404119067777600000000006777760070777000007077007000070
55555555566656660005500004999940a988888a1444444100000000499999944999999444004994006666000000000000666600000000007000000000000000
5777777557777777777777777777777577cccccccccccccccccccc77577777755555555555555555555555555500000007777770000000000000000000000000
77777777777777777777777777777777777cccccccccccccccccc777777777775555555555555550055555556670000077777777000777770000000000000000
777c77777777ccccc777777ccccc7777777cccccccccccccccccc777777777775555555555555500005555556777700077777777007766700000000000000000
77cccc77777cccccccc77cccccccc7777777cccccccccccccccc7777777cc7775555555555555000000555556660000077773377076777000000000000000000
77cccc7777cccccccccccccccccccc777777cccccccccccccccc777777cccc775555555555550000000055555500000077773377077660000777770000000000
777cc77777cc77ccccccccccccc7cc77777cccccccccccccccccc77777cccc775555555555500000000005556670000073773337077770000777767007700000
7777777777cc77cccccccccccccccc77777cccccccccccccccccc77777c7cc77555555555500000000000055677770007333bb37000000000000007700777770
5777777577cccccccccccccccccccc7777cccccccccccccccccccc7777cccc77555555555000000000000005666000000333bb30000000000000000000077777
77cccc7777cccccccccccccccccccc77577777777777777777777775777ccc775555555550000000000000050000066603333330000000000000000000000000
777ccc7777cccccccccccccccccccc77777777777777777777777777777cc7775055555555000000000000550007777603b333300011110000ee0ee000000000
777ccc7777cc7cccccccccccc77ccc777777ccc7777777777ccc7777777cc77755550055555000000000055500000766033333300117171000eeeee000000030
77ccc77777ccccccccccccccc77ccc77777ccccc7c7777ccccccc77777ccc777555500555555000000005555000000550333b33001119910000e8e00000000b0
77ccc777777cccccccc77cccccccc777777ccccccc7777c7ccccc77777cccc7755555555555550000005555500000666003333001117771100eeeee000000b30
777cc7777777ccccc777777ccccc77777777ccc7777777777ccc777777cccc7755055555555555000055555500077776000440001117771100ee3ee003000b00
777cc777777777777777777777777777777777777777777777777777777cc7775555555555555550055555550000076600044000011777100000b00000b0b300
77cccc775777777777777777777777755777777777777777777777755777777555555555555555555555555500000055009999001199d9900000b00000303300
5777755777577775077777777777777777777770077777700000000000000000cccccccc00000000000000000000000000000000000000000000000000000000
7777777777777777700007770000777000007777700077770000000000000000c77ccccc00000000000000000000000000000000000000000000000000000000
7777cc7777cc777770cc777cccc777ccccc7770770c777070000000000000000c77cc7cc00000000000000000000000000000000000000000000000000000000
777cccccccccc77770c777cccc777ccccc777c0770777c070000000000000000cccccccc00000000000000000000000000006000000000000000000000000000
77cccccccccccc77707770000777000007770007777700070002eeeeeeee2000cccccccc00000000000000000000000000060600000000000000000000000000
57cc77ccccc7cc7577770000777000007770000777700007002eeeeeeeeee200cc7ccccc00000000000000000000000000d00060000000000000000000000000
577c77ccccccc7757000000000000000000c000770000c0700eeeeeeeeeeee00ccccc7cc0000000000000000000000000d00000c000000000000000000000000
777cccccccccc7777000000000000000000000077000000700e22222e2e22e00cccccccc000000000000000000000000d000000c000000000000000000000000
777cccccccccc7777000000000000000000000077000000700eeeeeeeeeeee000000000000000000000000000000000c0000000c000600000000000000000000
577cccccccccc7777000000c000000000000000770cc000700e22e2222e22e00000000000000000000000000000000d000000000c060d0000000000000000000
57cc7cccc77ccc7570000000000cc0000000000770cc000700eeeeeeeeeeee0000000000000000000000000000000c00000000000d000d000000000000000000
77ccccccc77ccc7770c00000000cc00000000c0770000c0700eee222e22eee0000000000000000000000000000000c0000000000000000000000000000000000
777cccccccccc7777000000000000000000000077000000700eeeeeeeeeeee005555555506666600666666006600c00066666600066666006666660066666600
7777cc7777cc777770000000000000000000000770c0000700eeeeeeeeeeee00555555556666666066666660660c000066666660666666606666666066666660
777777777777777770000000c0000000000000077000000700ee77eee7777e005555555566000660660000006600000066000000660000000066000066000000
57777577775577757000000000000000000000077000c007077777777777777055555555dd000000dddd0000dd000000dddd0000ddddddd000dd0000dddd0000
000000000000000070000000000000000000000770000007007777005000000000000005dd000dd0dd000000dd0000d0dd000000000000d000dd0000dd000000
00aaaaaaaaaaaa00700000000000000000000007700c0007070000705500000000000055ddddddd0dddddd00ddddddd0dddddd00ddddddd000dd0000dddddd00
0a999999999999a0700000000000c00000000007700000077077000755500000000005550ddddd00ddddddd0ddddddd0ddddddd00ddddd0000dd0000ddddddd0
a99aaaaaaaaaa99a7000000cc0000000000000077000cc077077bb07555500000000555500000000000000000000000000000000000000000000000000000000
a9aaaaaaaaaaaa9a7000000cc0000000000c00077000cc07700bbb0755555555555555550000000000000c000000000000000000000000000000c00000000000
a99999999999999a70c00000000000000000000770c00007700bbb075555555555555555000000000000c00000000000000000000000000000000c0000000000
a99999999999999a700000000000000000000007700000070700007055555555555555550000000000cc0000000000000000000000000000000000c000000000
a99999999999999a07777777777777777777777007777770007777005555555555555555000000000c000000000000000000000000000000000000c000000000
aaaaaaaaaaaaaaaa07777777777777777777777007777770004bbb00004b000000400bbb00000000c0000000000000000000000000000000000000c000000000
a49494a11a49494a70007770000077700000777770007777004bbbbb004bb000004bbbbb0000000100000000000000000000000000000000000000c00c000000
a494a4a11a4a494a70c777ccccc777ccccc7770770c7770704200bbb042bbbbb042bbb00000000c0000000000000000000000000000000000000001010c00000
a49444aaaa44494a70777ccccc777ccccc777c0770777c07040000000400bbb004000000000001000000000000000000000000000000000000000001000c0000
a49999aaaa99994a7777000007770000077700077777000704000000040000000400000000000100000000000000000000000000000000000000000000010000
a49444999944494a77700000777000007770000777700c0742000000420000004200000000000100000000000000000000000000000000000000000000001000
a494a444444a494a7000000000000000000000077000000740000000400000004000000000000000000000000000000000000000000000000000000000000000
a49499999999494a0777777777777777777777700777777040000000400000004000000000010000000000000000000000000000000000000000000000000010
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000525223232323232323
00000000000000a20182920013232352363636462535353545550000005525355284525262b20000000000004252525262828282425284525252845252525252
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000233300009200008392
000000000000110000a2000000a28213000000002636363646550000005525355252528462b2a300000000004252845262828382132323232323232352528452
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a200
0000000000b302b2002100000000a282000000000000000000560000005526365252522333b28292001111024252525262019200829200000000a28213525252
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000373737374711000061
000000110000b100b302b20000006182000000000000000000000000005600005252338282828201a31222225252525262820000a20011111100008283425252
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000222222222232b20000
0000b302b200000000b10000000000a200000000000000009300000000000000846282828283828282132323528452526292000000112434440000a282425284
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000232323232362b20000
000000b10000001100000000000000000000000093000086820000a3000000005262828201a200a282829200132323236211111111243535450000b312525252
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000829200a20173b20061
000000000000b302b2000061000000000000a385828286828282828293000000526283829200000000a20000000000005222222232263636460000b342525252
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000610000869200000000
00100000000000b1000000000000000086938282828201920000a20182a37686526282829300000000000000000000005252845252328283920000b342845252
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a20000000000
00021111111111111111111111110061828282a28382820000000000828282825262829200000000000000000000000052525252526201a2000000b342525252
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a300000000
0043535353535353535353535363b2008282920082829200061600a3828382a28462000000000000000000000000000052845252526292000011111142525252
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008293000000
0002828382828202828282828272b20083820000a282d3000717f38282920000526200000000000093000000000000005252525284620000b312223213528452
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009300008382000000
00b1a282820182b1a28283a28273b200828293000082122232122232820000a3233300000000000082920000000000002323232323330000b342525232135252
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008200008282920000
0000009261a28200008261008282000001920000000213233342846282243434000000000000000082000085860000008382829200000000b342528452321323
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009200000000a38292008282000000
00858600008282a3828293008292610082001000001222222252525232253535000000f3100000a3820000a2010000008292000000009300b342525252522222
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000828300a38201000000
00a282828292a2828283828282000000343434344442528452525252622535350000001263000083829300008200c1008210d3e300a38200b342525252845252
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009300000000828200828282930000
0000008382000000a28201820000000035353535454252525252528462253535000000032444008282820000829300002222223201828393b342525252525252
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000232323526282820000b342525252
52845252525252848452525262838242528452522333828292425223232352520000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a382426283920000b342232323
2323232323232323232323526201821352522333b1b1018241133383828242840000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000536382426282410000b30382a2a2
a1829200a2828382820182426200a2835262b1b10000831232b2000080014252000000000000a300000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000083828242522232b200b373928000
000100110092a2829211a2133300a3825262b2000000a21333b20000868242520000000000000100009300000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000092019242845262b2000000000000
00a2b302b2a36182b302b200110000825262b200000000b1b10000a283a2425200000000a30082000083000000000000000000000094a4b4c4d4e4f400000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000b30392000000829200000042525262b2000000000000
000000b100a2828200b100b302b211a25262b200000000000000000092b3428400000000827682000001009300000000000000000095a5b5c5d5e5f500000000
000000000000000000000000000000000000000000000000000000000000000000000000000000001100b303b2000000821111111142528462b2000000000000
000000000000110176851100b1b3026184621111111100000061000000b3135200000000828382670082768200000000000000000096a6b6c6d6e6f600000000
000000000000000000000000000000000000000000000000000000000000000000000000000000b37200b303b2000000824353535323235262b2000011000000
0000000000b30282828372b26100b100525232122232b200000000000000b14200000000a28282123282839200000000000000000097a7b7c7d7e7f700000000
000000000000000000000000000000000000000000000000000000000000000000000000000061b30300b3030000000092b1b1b1b1b1b34262b200b372b20000
001100000000b1a2828273b200000000232333132333b200001111000000b342000000868382125252328293a300000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000b30393b30361000000000000000000b34262b271b303b20000
b302b211000000110092b100000000a3b1b1b1b1b1b10011111232110000b342000000a282125284525232828386000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000b30382b37300000000000000000000b3426211111103b20000
00b1b302b200b372b200000000000082b21000000000b31222522363b200b3138585868292425252525262018282860000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000b3038282820000000011111111930011425222222233b20000
100000b10000b303b200000000858682b27100000000b3425233b1b1000000b182018283001323525284629200a2820000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000b30382839200000000222222328283432323232333b2000000
329300000000b373b200000000a20182111111110000b31333b100a30061000000a28293f3123242522333020000820000000000000000000000000000000000
000000000000000000000000000000000000d30000000000000000000000000000000000000000b30300a282760000005252526200828200a30182a2006100a3
62820000000000b100000093a382838222222232b20000b1b1000083000000860000122222526213331222328293827600000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000b373000083920000005284526200a282828283920000000082
62839321000000000000a3828282820152845262b261000093000082a300a3821000135252845222225252523201838200000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000083000082010000005252526271718283820000000000a382
628201729300000000a282828382828252528462b20000a38300a382018283821222324252525252525284525222223200000000000000000000000000000000
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000700000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000770000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000770000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000006000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000070000000000000000006000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000060600000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000d00060000000000000066000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000d00000c000000000000066000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000d000000c000000000000000000000000000000000000000000000000060000000000
00000000000000000000000000000000000000000000000000000000000c0000000c000600000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000d000000000c060d0000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000c00000000000d000d000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000006666600666666006600c00066666600066666006666660066666600000000000000000000000000000000000000
0000000000000000000000000000000000006666666066666660660c000066666660666666606666666066666660000000000000000000000000000000000000
00000000000000000000000000000000000066000660660000006600000066000000660000000066000066000000000000000000000000000000000000000000
000000000000000000000000000000000000dd000000dddd0000dd000000dddd0000ddddddd000dd0000dddd0000000000000000000000000000000000000000
000000000000000000000000000000000000dd000dd0dd000000dd0000d0dd000000000000d000dd0000dd000000000000000000000000000000000000000000
000000000000000000000000000000000000ddddddd0dddddd00ddddddd0dddddd00ddddddd000dd0000dddddd00000000000000000000000000000000000000
0000000000000000000000000000000000000ddddd00ddddddd0ddddddd0ddddddd00ddddd0000dd0000ddddddd0000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000c000000000000000000000000000000c00000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000c00000000000000000000000000000000c0000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000cc0000000000000000000000000000000000c000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000c000000000000000000000000000000000000c000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000c0000000000000000000000000000000000000c000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000100000000000000000000000000000000000000c00c000000000000000000000000000000000000000000
000000000000000000000000000000000000000000c0000000000000000000000000000000000000001010c00000000000000000000000000000000000000000
000000000000000000000000000000000000000001000000000000000000000000000000000000000001000c0000000000000000000000000000000000000000
00000000000000000000000000000000000000000100000000000000000000000000000000000000000000010000000600000000000000000000000000000000
00000000000000000000000000000000000000000100000000000000000000000000000000000000000000001000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000010000000000000000000000000000000000000000000000000010000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000060000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000005050000005500000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000005050050050006000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000500555050000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000005050050050000000000000600000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000005050000005500000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000070000000000660000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000660000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000055505550555055500000555050500550555005500550550000000000000000000000000000000000000000
00000000000000000000000000000000000000000055505050050005000000050050505050505050005050505000000000000000000000000000000000000000
00000000000000000000000000000000000000000050505550050005000000050055505050550055505050505000000000000000000000000000000000000000
00000000000000000000000000000000000000000050505050050005000000050050505050505000505050505000000000000000000000000000000000000000
00000000000000000000000000000000000000000050505050050005000000050050505500505055005500505000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000605500055055505000000055505550555055505050000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000005050505050005000000050505000505050505050000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000005050505055005000000055005500550055005550000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000005050505050005000000050505000505050500050000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000005050550055505550000055505550505050505550000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

__gff__
0000000000000000000000000000000004020000000000000000000200000000030303030303030304040402020000000303030303030303040404020202020200001313131302020302020202020002000013131313020204020202020202020000131313130004040202020202020200001313131300000002020202020202
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
2600000000000000000000000000000000000000002020202020200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002525482525252525252526282824252548252525262828282824254825252526282828283132323225482525252525
26000000270000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000025252525482525323232332828242525254825323338282a283132252548252628382828282a2a2831323232322525
261200003000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000253232323232332122222328282425252532332828282900002a283132252526282828282900002a28282838282448
25360000300000000000000000000000000000000011111111110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000026212223202123313232332828242548262b000000000000001c00003b242526282828000000000028282828282425
26000000300000000000000000000000000000000021222235360000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000033242526103133202828282838242525262b000000000000000000003b2425262a2828670016002a28283828282425
26000000300000003d3e00000000000000000000003125262b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000028313233282829002a002a2828242525332b0c00000011110000000c3b314826112810000000006828282828282425
2600000031353535353535353600000027000000000024262b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000281b1b1b282800000000002a2125482628390000003b34362b000000002824252328283a67003a28282829002a3132
2600000000160000000000000000000037000000000024262b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000028390000002a29000000000031323226101000000000282839000000002a2425332828283800282828390000001700
2600000000000000000000000000000000000000000024262b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002828290000000000163a67682828003338280b00000010382800000b00003133282828282868282828280000001700
261111111100001111111111270000000000000000002425222222232b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002900000000000000002a28282829002a2839000000002a282900000000000028282838282828282828290000000000
253535353600002135353535260000002700000000002425323232332b000021232b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003928390000000000282800000028290000002a2828000000000000002a282828281028282828675800000000
261b1b1b1b000030000000003700000030000000000024261b1b1b1b00000031262b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000013a28281028580000003a28290000002a280c0000003a380c00000000000c00002a2828282828292828290000003a
260000000000003000000000000000003000000000002426000000000000003b302b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000222328282828283900582838283d00003a290000000028280000000000000000002a28282a29000058100012002a28
260000111111113000000000000000003000000000002426000000000000003b302b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002525222222232828282810282821220b10000000000b28100000000b0000002c00002838000000002a283917000028
260000343535353235360000343535353300000000002425222300000000003b302b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004825252525262a28282122222225253a28013d0000006828390000000000003c0168282800171717003a2800003a28
2600001b1b1b1b1b1b1b0000000000000000000000003132323300000000003b3011111121230000000000000000000000000000000000000000000000000000000000000000000000000000000000000025252548252600002a2425252548252821222300000028282800000000000022222223286700000000282839002838
260000000000000000000000000000000000000100001b1b1b1b00000000003b313535353233000000000000000000000000000000000000000000000000000000000000000000000000000000002900262829286700000000002828313232322525253233282800312525482525254825254826283828313232323232322548
26000011000000000000000000000000000000270000000000000000000000001b1b1b1b1b1b00000000000000000000000000000000000000000000000000000000000000000000000000000000390026281a3820393d000000002a3828282825252628282829003b2425323232323232323233282828282828102828203125
261111270000000000000000000000000000003000000000160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001111000000000000290026283a2820102011111121222328281025252628382800003b24262b002a2a38282828282829002a2800282838282831
32353526000000000000000011111111111111301111111111111100000011111111111100000000000000000000000000000000000000000000000000000000000000000000212300000000002122222522222321222321222324482628282832323328282800003b31332b00000028102829000000000029002a2828282900
0000003000000000000000002122222235353532353535352222232b00003435353535360000000000000000000000000000000000000000000000000000000000000000003a242600001600002425252525482631323331323324252620283822222328292867000028290000000000283800111100001200000028292a1600
1c00003000000000000000003132323300000000000000003125262b0000000000000000000000002123000000000000000000000000000000000000000000000000000000282426111111111124252525482526201b1b1b1b1b24252628282825252600002a28143a2900000000000028293b21230000170000112867000000
0000003000000000000000001b1b1b1b00000000000000000024262b00000000000000000000404124260000000000000000000000000000000000000000000000000000382831323535353522254825252525252300000000003132332810284825261111113435361111111100000000003b3133111111111127282900003b
0000113000000000000000000000000000000000000000000031332b00000000000000000000501a24260000000000000000000000000000000000000000000000000000282829000000000031322525252525252667580000002000002a28282525323535352222222222353639000000003b34353535353536303800000017
000021261100000000000000111111110016000000000000001b1b00000011111111111100000000242600000000000000000000000000000000000000000000000000002900000000000000002831322525482526382900000017000058682832331028293b2448252526282828000000003b201b1b1b1b1b1b302800000017
00003132362b000000000000212222230000000000000000000000000000212222222223000000003126000000000000000000000000000000000000000000000000000000000000001100002a382829252525252628000000001700002a212228282908003b242525482628282912000000001b00000000000030290000003b
00001b1b1b000000000000002420252600000000000000000000000000002425252525263d3d123d3d300000000000000000000000000000000000000000000000000000000000003b202b00682828003232323233290000000000000000312528280000003b3132322526382800170000000000000000110000370000000000
000000000000000000000000242520260000000000000000000000000000242525252525222222222233000000000000000000000000000000000000000000000000000000110000001b002a2010292c1b1b1b1b0000000000000000000010312829160000001b1b1b313328106700000000001100003a2700001b0000000000
3535362b000000213600000031323233000000000000343600000000000031323232323232323232330000000000000000000000000000000000000000000000000000003b202b39000000002900003c000000000000000000000000000028282800000000000000001b1b2a2829000001000027390038300000000000000000
1b1b1b000000003700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000673a3900003f0000002a3829001100000000002101000000000000003a67000000002a382867586800000100000000682800000021230037282928300000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002838290000000000000828393b27000000001424230000001200000028290000000000282828102867001717171717282839000031333927101228370000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024262828282828283900000000003a28103b30000000212225260000002700003a28000000000000282838282828390000005868283828000022233830281728270000000000000000
__sfx__
0002000036370234702f3701d4702a37017470273701347023370114701e3700e4701a3600c46016350084401233005420196001960019600196003f6003f6003f6003f6003f6003f6003f6003f6003f6003f600
0002000011070130701a0702407000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000300000d07010070160702207000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000200000642008420094200b420224402a4503c6503b6503b6503965036650326502d6502865024640216401d6401a64016630116300e6300b62007620056100361010600106000060000600006000060000600
000400000f0701e070120702207017070260701b0602c060210503105027040360402b0303a030300203e02035010000000000000000000000000000000000000000000000000000000000000000000000000000
000300000977009770097600975008740077300672005715357003470034700347003470034700347003570035700357003570035700347003470034700337003370033700337000070000700007000070000700
00030000241700e1702d1701617034170201603b160281503f1402f120281101d1101011003110001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
00020000101101211014110161101a120201202613032140321403410000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
00030000070700a0700e0701007016070220702f0702f0602c0602c0502f0502f0402c0402c0302f0202f0102c000000000000000000000000000000000000000000000000000000000000000000000000000000
0003000005110071303f6403f6403f6303f6203f6103f6153f6003f6003f600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600
011000200177500605017750170523655017750160500605017750060501705076052365500605017750060501775017050177500605236550177501605006050177500605256050160523655256050177523655
002000001d0401d0401d0301d020180401804018030180201b0301b02022040220461f0351f03016040160401d0401d0401d002130611803018030180021f061240502202016040130201d0401b0221804018040
00100000070700706007050110000707007060030510f0700a0700a0600a0500a0000a0700a0600505005040030700306003000030500c0700c0601105016070160600f071050500a07005050030510a0700a060
000400000c5501c5601057023570195702c5702157037570285703b5702c5703e560315503e540315303e530315203f520315203f520315103f510315103f510315103f510315103f50000500005000050000500
000400002f7402b760267701d7701577015770197701c750177300170015700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700
00030000096450e655066550a6550d6550565511655076550c655046550965511645086350d615006050060500605006050060500605006050060500605006050060500605006050060500605006050060500605
011000001f37518375273752730027300243001d300263002a3001c30019300003000030000300003000030000300003000030000300003000030000300003000030000300003000030000300003000030000300
011000002953429554295741d540225702256018570185701856018500185701856000500165701657216562275142753427554275741f5701f5601f500135201b55135530305602454029570295602257022560
011000200a0700a0500f0710f0500a0600a040110701105007000070001107011050070600704000000000000a0700a0500f0700f0500a0600a0401307113050000000000013070130500f0700f0500000000000
002000002204022030220201b0112404024030270501f0202b0402202027050220202904029030290201601022040220302b0401b030240422403227040180301d0401d0301f0521f0421f0301d0211d0401d030
0108002001770017753f6253b6003c6003b6003f6253160023650236553c600000003f62500000017750170001770017753f6003f6003f625000003f62500000236502365500000000003f625000000000000000
002000200a1400a1300a1201113011120111101b1401b13018152181421813213140131401313013120131100f1400f1300f12011130111201111016142161321315013140131301312013110131101311013100
001000202e750377502e730377302e720377202e71037710227502b750227302b7301d750247501d730247301f750277501f730277301f7202772029750307502973030730297203072029710307102971030710
000600001877035770357703576035750357403573035720357103570000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700
001800202945035710294403571029430377102942037710224503571022440274503c710274403c710274202e450357102e440357102e430377102e420377102e410244402b45035710294503c710294403c710
0018002005570055700557005570055700000005570075700a5700a5700a570000000a570000000a5700357005570055700557000000055700557005570000000a570075700c5700c5700f570000000a57007570
010c00103b6352e6003b625000003b61500000000003360033640336303362033610336103f6003f6150000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000c002024450307102b4503071024440307002b44037700244203a7102b4203a71024410357102b410357101d45033710244503c7101d4403771024440337001d42035700244202e7101d4102e7102441037700
011800200c5700c5600c550000001157011560115500c5000c5700c5600f5710f56013570135600a5700a5600c5700c5600c550000000f5700f5600f550000000a5700a5600a5500f50011570115600a5700a560
001800200c5700c5600c55000000115701156011550000000c5700c5600f5710f56013570135600f5700f5600c5700c5700c5600c5600c5500c5300c5000c5000c5000a5000a5000a50011500115000a5000a500
000c0020247712477024762247523a0103a010187523a0103501035010187523501018750370003700037000227712277222762227001f7711f7721f762247002277122772227620070027771277722776200700
000c0020247712477024762247523a0103a010187503a01035010350101875035010187501870018700007001f7711f7701f7621f7521870000700187511b7002277122770227622275237012370123701237002
000c0000247712477024772247722476224752247422473224722247120070000700007000070000700007002e0002e0002e0102e010350103501033011330102b0102b0102b0102b00030010300123001230012
000c00200c3320c3320c3220c3220c3120c3120c3120c3020c3320c3320c3220c3220c3120c3120c3120c30207332073320732207322073120731207312073020a3320a3320a3220a3220a3120a3120a3120a302
000c00000c3300c3300c3200c3200c3100c3100c3103a0000c3300c3300c3200c3200c3100c3100c3103f0000a3300a3201333013320073300732007310113000a3300a3200a3103c0000f3300f3200f3103a000
00040000336251a605000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005
000c00000c3300c3300c3300c3200c3200c3200c3100c3100c3100c31000000000000000000000000000000000000000000000000000000000000000000000000a3000a3000a3000a3000a3310a3300332103320
001000000c3500c3400c3300c3200f3500f3400f3300f320183501834013350133401835013350163401d36022370223702236022350223402232013300133001830018300133001330016300163001d3001d300
000c0000242752b27530275242652b26530265242552b25530255242452b24530245242352b23530235242252b22530225242152b21530215242052b20530205242052b205302053a2052e205002050020500205
001000102f65501075010753f615010753f6152f65501075010753f615010753f6152f6553f615010753f61500005000050000500005000050000500005000050000500005000050000500005000050000500005
0010000016270162701f2711f2701f2701f270182711827013271132701d2711d270162711627016270162701b2711b2701b2701b270000001b200000001b2000000000000000000000000000000000000000000
00080020245753057524545305451b565275651f5752b5751f5452b5451f5352b5351f5252b5251f5152b5151b575275751b545275451b535275351d575295751d545295451d535295351f5752b5751f5452b545
002000200c2650c2650c2550c2550c2450c2450c2350a2310f2650f2650f2550f2550f2450f2450f2351623113265132651325513255132451324513235132351322507240162701326113250132420f2600f250
00100000072750726507255072450f2650f2550c2750c2650c2550c2450c2350c22507275072650725507245072750726507255072450c2650c25511275112651125511245132651325516275162651625516245
000800201f5702b5701f5402b54018550245501b570275701b540275401857024570185402454018530245301b570275701b540275401d530295301d520295201f5702b5701f5402b5401f5302b5301b55027550
00100020112751126511255112451326513255182751826518255182451d2651d2550f2651824513275162550f2750f2650f2550f2451126511255162751626516255162451b2651b255222751f2451826513235
00100010010752f655010753f6152f6553f615010753f615010753f6152f655010752f6553f615010753f61500005000050000500005000050000500005000050000500005000050000500005000050000500005
001000100107501075010753f6152f6553f6153f61501075010753f615010753f6152f6553f6152f6553f61500005000050000500005000050000500005000050000500005000050000500005000050000500005
002000002904029040290302b031290242b021290142b01133044300412e0442e03030044300302b0412b0302e0442e0402e030300312e024300212e024300212b0442e0412b0342e0212b0442b0402903129022
000800202451524515245252452524535245352454524545245552455524565245652457500505245750050524565005052456500505245550050524555005052454500505245350050524525005052451500505
000800201f5151f5151f5251f5251f5351f5351f5451f5451f5551f5551f5651f5651f575000051f575000051f565000051f565000051f555000051f555000051f545000051f535000051f525000051f51500005
000500000373005731077410c741137511b7612437030371275702e5712437030371275702e5712436030361275602e5612435030351275502e5512434030341275402e5412433030331275202e5212431030311
002000200c2750c2650c2550c2450c2350a2650a2550a2450f2750f2650f2550f2450f2350c2650c2550c2450c2750c2650c2550c2450c2350a2650a2550a2450f2750f2650f2550f2450f235112651125511245
002000001327513265132551324513235112651125511245162751626516255162451623513265132551324513275132651325513245132350f2650f2550f2450c25011231162650f24516272162520c2700c255
000300001f3302b33022530295301f3202b32022520295201f3102b31022510295101f3002b300225002950000000000000000000000000000000000000000000000000000000000000000000000000000000000
000b00002935500300293453037030360303551330524300243050030013305243002430500300003002430024305003000030000300003000030000300003000030000300003000030000300003000030000300
001000003c5753c5453c5353c5253c5153c51537555375453a5753a5553a5453a5353a5253a5253a5153a51535575355553554535545355353553535525355253551535515335753355533545335353352533515
00100000355753555535545355353552535525355153551537555375353357533555335453353533525335253a5753a5453a5353a5253a5153a51533575335553354533545335353353533525335253351533515
001000200c0600c0300c0500c0300c0500c0300c0100c0000c0600c0300c0500c0300c0500c0300c0100f0001106011030110501103011010110000a0600a0300a0500a0300a0500a0300a0500a0300a01000000
001000000506005030050500503005010050000706007030070500703007010000000f0600f0300f010000000c0600c0300c0500c0300c0500c0300c0500c0300c0500c0300c010000000c0600c0300c0100c000
0010000003625246150060503615246251b61522625036150060503615116253361522625006051d6250a61537625186152e6251d615006053761537625186152e6251d61511625036150060503615246251d615
00100020326103261032610326103161031610306102e6102a610256101b610136100f6100d6100c6100c6100c6100c6100c6100f610146101d610246102a6102e61030610316103361033610346103461034610
00400000302453020530235332252b23530205302253020530205302253020530205302153020530205302152b2452b2052b23527225292352b2052b2252b2052b2052b2252b2052b2052b2152b2052b2052b215
__music__
01 150a5644
00 0a160c44
00 0a160c44
00 0a0b0c44
00 14131244
00 0a160c44
00 0a160c44
02 0a111244
00 41424344
00 41424344
01 18191a44
00 18191a44
00 1c1b1a44
00 1d1b1a44
00 1f211a44
00 1f1a2144
00 1e1a2244
02 201a2444
00 41424344
00 41424344
01 2a272944
00 2a272944
00 2f2b2944
00 2f2b2c44
00 2f2b2944
00 2f2b2c44
00 2e2d3044
00 34312744
02 35322744
00 41424344
01 3d7e4344
00 3d7e4344
00 3d4a4344
02 3d3e4344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
01 383a3c44
02 393b3c44

