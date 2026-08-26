-- Periodic full snapshots (not per-write logging, which produced an
-- unworkable 2.9M-entry / 79MB log and never finished the recording) of
-- every RAM page ENTRY_Reset clears at boot ($1E00,$1F00,$2000,$2100,$2700),
-- taken every 60 frames (1 second), so gameplay events (lives lost/gained,
-- difficulty, poison-mushroom state, bottom-loop spawns) can be spotted as
-- step changes in a specific byte's value over time.
--
--   mame a7800 -rompath ../bios -cart <rom> -skip_gameinfo -video none \
--       -sound none -nothrottle -playback run-01.inp \
--       -autoboot_script tools/probe-ram-snapshots.lua -str 600
--
-- Writes ram-snapshots-out.json: {frames:[60,120,...], pages:{"1E00":[[a,v],...], ...}}
-- where each page's list only records BYTES THAT EVER CHANGED across the
-- whole run (constant bytes are dropped to keep the file small), as
-- [addr, v_at_frame_60, v_at_frame_120, ...] rows aligned to `frames`.

local MACHINE = (type(manager.machine) == "function")
                and manager:machine() or manager.machine
local mem = MACHINE.devices[":maincpu"].spaces["program"]

local PAGES = {0x1E00, 0x1F00, 0x2000, 0x2100, 0x2700}
local F = 0
local frames = {}
-- series[page][addr] = { value_at_each_checkpoint... }
local series = {}
for _, p in ipairs(PAGES) do series[p] = {} end

local function snapshot()
  frames[#frames + 1] = F
  for _, p in ipairs(PAGES) do
    local s = series[p]
    for a = p, p + 255 do
      local v = mem:read_u8(a)
      local rec = s[a]
      if not rec then rec = {} s[a] = rec end
      rec[#frames] = v
    end
  end
end

local function dump()
  local parts = {}
  for _, p in ipairs(PAGES) do
    local rows = {}
    for a, rec in pairs(series[p]) do
      -- only keep bytes that ever changed
      local changed = false
      local first = rec[1]
      for i = 1, #frames do
        if rec[i] ~= first then changed = true break end
      end
      if changed then
        local vs = {}
        for i = 1, #frames do vs[i] = tostring(rec[i] or 0) end
        rows[#rows + 1] = string.format('"%d":[%s]', a, table.concat(vs, ","))
      end
    end
    parts[#parts + 1] = string.format('"%04X":{%s}', p, table.concat(rows, ","))
  end
  local h = io.open("ram-snapshots-out.json", "w")
  if h then
    h:write(string.format('{"frames":[%s],"pages":{%s}}',
      table.concat(frames, ","), table.concat(parts, ",")))
    h:close()
    print(string.format("wrote ram-snapshots-out.json: frame=%d checkpoints=%d", F, #frames))
  end
end

emu.register_frame_done(function()
  F = F + 1
  if F % 60 == 0 then snapshot() end
  if F % 6000 == 0 then dump() end
  if F >= 53750 then
    dump()
    MACHINE:exit()
  end
end)
