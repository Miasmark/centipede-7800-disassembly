-- Who reads $F4F2-$FFFF? PC-tagged so a real reader can be told apart from
-- a shared-bus/DMA misattribution artifact (see docs/pitfalls.md in the
-- toolkit) -- check the reported PC's own instruction, don't trust the
-- raw hit count alone.

local MACHINE = (type(manager.machine) == "function")
                and manager:machine() or manager.machine
local mem = MACHINE.devices[":maincpu"].spaces["program"]
local cpu = MACHINE.devices[":maincpu"]

local hits = {}
local total = 0

TAP = mem:install_read_tap(0xF4F2, 0xFFFF, "gap", function(offset, data)
  local pc = cpu.state["PC"].value
  local key = string.format("$%04X", pc)
  hits[key] = (hits[key] or 0) + 1
  total = total + 1
  return data
end)

local F = 0
emu.register_frame_done(function()
  F = F + 1
  if F % 3000 == 0 then
    print(string.format("progress frame %d: hits=%d", F, total))
  end
  if F >= 53750 then
    dump_final()
    MACHINE:exit()
  end
end)

function dump_final()
  print(string.format("FINAL: hits=%d", total))
  local ks = {}
  for k in pairs(hits) do ks[#ks+1] = k end
  table.sort(ks, function(a,b) return hits[a] > hits[b] end)
  for i = 1, math.min(#ks, 30) do
    print(string.format("  %s x%d", ks[i], hits[ks[i]]))
  end
  local h = io.open("gap-readers-out.json", "w")
  if h then
    local parts = {}
    for k,v in pairs(hits) do parts[#parts+1] = string.format('"%s":%d', k, v) end
    h:write("{" .. table.concat(parts, ",") .. "}")
    h:close()
  end
end
