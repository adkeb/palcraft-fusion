-- Vanilla tick-based animation selection, including interpolation amount.
local M={}
function M.sample(metadata,seconds)
 local animation=metadata.animation
 if not animation or not animation.frames then return nil end
 local frames=animation.frames;local duration=0
 for _,frame in ipairs(frames)do duration=duration+frame.time end
 local position=(seconds*(animation.ticks_per_second or 20))%duration
 for i,frame in ipairs(frames)do
  if position<frame.time then
   local nextFrame=frames[i%#frames+1]
   return{index=frame.index,next_index=nextFrame.index,mix=animation.interpolate and position/frame.time or 0,
    path=animation.frames_dir and animation.frames_dir..string.format('%04d.png',frame.index)or nil,
    next_path=animation.frames_dir and animation.frames_dir..string.format('%04d.png',nextFrame.index)or nil,
    elapsed_ticks=position,duration_ticks=frame.time}
  end
  position=position-frame.time
 end
end
return M
