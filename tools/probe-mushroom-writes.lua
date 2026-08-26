-- Who writes $2000-$20FF (the likely mushroom-field/playfield grid -- 256
-- bytes, changes constantly in play, but nothing in the currently-traced
-- code references it by a literal address)? PC-tagged so the exact writer
-- can be found even though it's clearly reached through a computed
-- pointer, not a literal STA/LDA absolute.
--
--   mame a7800 -rompath ../bios -cart <rom> -skip_gameinfo -video none \
--       -sound none -nothrottle -playback run-01.inp \
--       -autoboot_script tools/probe-mushroom-writes.lua -str 600
--
-- Writes mushroom-writes-out.json: {"pcs":{"$XXXX":count,...},
-- "addrs":{"$XXXX":count,...}} -- unlike the gap-reader probe, writes to
-- ordinary RAM can't be MARIA DMA misattribution (MARIA doesn't write to
-- $2000-$20FF), so every PC here is a real 6502 writer.

local MACHINE = (type(manager.machine) == "function")
                and manager:machine() or manager.machine
local mem = MACHINE.devices[":maincpu"].spaces["program"]
local cpu = MACHINE.devices[":maincpu"]

local pcs = {}
local addrs = {}
local total = 0

TAP = mem:install_write_tap(0x2000, 0x20FF, "mushroom", function(offset, data)
  local pc = cpu.state["PC"].value
  local pk = string.format("$%04X", pc)
  local ak = string.format("$%04X", offset)
  pcs[pk] = (pcs[pk] or 0) + 1
  addrs[ak] = (addrs[ak] or 0) + 1
  total = total + 1
  return data
end)

local F = 0
emu.register_frame_done(function()
  F = F + 1
  if F % 3000 == 0 then
    print(string.format("progress frame %d: hits=%d", F, total))
  end
  if F >= 30000 then
    dump_final()
    MACHINE:exit()
  end
end)

function dump_final()
  print(string.format("FINAL: hits=%d", total))
  local pk = {}
  for k in pairs(pcs) do pk[#pk+1] = k end
  table.sort(pk, function(a,b) return pcs[a] > pcs[b] end)
  print("top PCs:")
  for i = 1, math.min(#pk, 30) do
    print(string.format("  %s x%d", pk[i], pcs[pk[i]]))
  end
  local h = io.open("mushroom-writes-out.json", "w")
  if h then
    local pparts = {}
    for k,v in pairs(pcs) do pparts[#pparts+1] = string.format('"%s":%d', k, v) end
    local aparts = {}
    for k,v in pairs(addrs) do aparts[#aparts+1] = string.format('"%s":%d', k, v) end
    h:write(string.format('{"pcs":{%s},"addrs":{%s}}',
      table.concat(pparts, ","), table.concat(aparts, ",")))
    h:close()
  end
end
