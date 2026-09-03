-- zz_godmode.lua
--
-- Personal cheat menu for FreeSpace Open. Lives in the library root, so it is
-- available in every mod launched from Knossos, and does nothing until opened.
--
--   Shift+Alt+I   open / close the menu
--   1 2 3 4 5 6 7 pick an entry          (consumed, never reaches the game)
--   BKSP          back to the main menu
--   ESC           close
--
-- While FreeSpace's own comm menu (C) is open the cheat menu hides itself and
-- claims no keys at all, so the number keys give orders and ESC closes the comm
-- menu only. Shift+Alt+I still works. See commMenuOpen.
--
--   CHEAT MENU                      ESCORT SHIPS (3 on list)
--   1  God mode      [ON ]          1  Invulnerable   [OFF]
--   2  Guardian      [OFF]          2  Heal to full now
--   3  Escort ships...              3  Keep healing    [ON ]
--   4  Wingmen...
--   5  Stealth...
--   6  Scan target now
--   7  Mission vars [OFF]           WINGMEN (3 in Alpha)
--                                   1  Invulnerable   [OFF]
--                                   2  Heal to full now
--                                   3  Keep healing    [ON ]
--                                   4  Scope: my wing
--
--                                   STEALTH (you + 3 wingmen)
--                                   1  Enemies ignore me   [ON ]
--                                   2  Ghost (no sensors)  [OFF]
--                                   3  Drop enemy locks now
--                                   4  Hold IFF (no alarm) [OFF]
--                                   5  Reset IFF now
--
-- The escort options only affect ships on the player's own team: the escort
-- gauge is a monitor list and missions add hostiles to it as well.
--
-- The wingmen options default to the player's own wing (Alpha 2/3/4 when you fly
-- Alpha 1); your own ship is left to entry 1. Scope cycles that wider when the
-- allies who matter are not in your wing:
--   my wing              the wing you are flying in
--   all friendly wings   every wing on your team - the usual choice
--   every friendly ship  adds the ships that are in no wing: capships, stations
-- Narrowing the scope hands back whatever just left it.
--
-- Stealth stays on your own wing regardless of this setting.
--
-- Stealth covers you AND your wing:
--   Enemies ignore me = protect-ship + the turret weapon-type protections +
--     the stealth flag. You stay on radar and mission events fire as normal;
--     hostiles simply never select you. Existing locks are cleared each frame.
--   Ghost = hidden-from-sensors. Nothing in the mission can target you at all -
--     including your own wingmen and the support ship, and missions that gate
--     events on the player being detected can stall. Use it only if the first
--     level is not enough.
--   Neither level defuses homing missiles already in the air.
--
-- Stealth 4 and 5 solve a different problem. Sneaking missions usually do not
-- detect you with sensors at all - they run a SEXP that measures distance and
-- flips the enemy fleet to Hostile, which no stealth flag can touch. Hold IFF
-- snapshots every ship's team from mission start and puts back anything that
-- changes sides, so the alarm fires and is undone in the same frame. The
-- scripted chatter and directives that hang off the alarm still play; only the
-- hostility is reverted. In a mission where enemies are MEANT to reveal
-- themselves (an ambush, a defection) this suppresses that and can stall the
-- mission, so switch it on for the mission that needs it, not permanently.
--
-- Scan target now marks the targeted ship's cargo and every one of its
-- subsystems as scanned, for the missions that gate objectives - or a campaign
-- branch - on scans you would otherwise have to fly in and hold still for.
-- Scanning a SHIP and scanning its SUBSYSTEMS are different things, and missions
-- usually count the subsystems: Derelict's dl3-04 gives one @SSCount point per
-- Nyarlathotep subsystem (navigation, weapons, sensors, communication) and picks
-- the next mission from that, not from whether you were spotted.
--
-- Mission vars puts the mission's SEXP variables on the HUD, which is how you
-- check whether a scan actually registered instead of guessing.
--
-- God mode  = invulnerable + unlimited resources.
-- Guardian  = damage applies but hull never drops below 1%, + unlimited resources.
-- Resources = weapon energy, afterburner fuel, countermeasures, ballistic ammo.
--
-- Toggles persist across missions until switched off or the game is closed.
--
-- Every hook is wrapped (see guard): an uncaught Lua error inside an FSO hook is
-- escalated by the engine and takes a release build down, so a failure here has
-- to cost the menu and nothing else. The first distinct error goes to
-- fs2_open.log and on screen.
--
-- Mods pin their own FSO build (Blue Planet 3.3.3 pins 23.2.1, the rest of this
-- library runs 26.0.0), and the ADE surface differs between them. On 23.2.1 a
-- read of a missing index ABORTS THE GAME instead of raising a catchable error,
-- so newer calls are gated on the engine version - see MODERN_API. On 23.2.1:
--   heal              hull and shields only, subsystems are skipped
--   Scan target now   ship cargo only, subsystems are skipped
-- The engine version detected at load is written to fs2_open.log.
--
-- Uninstall: delete this file and data/tables/zz-godmode-sct.tbm

GodMode = GodMode or {}

GodMode.enabled      = GodMode.enabled      or false  -- god mode
GodMode.guardian     = GodMode.guardian     or false  -- 1% hull floor
GodMode.escortInvuln = GodMode.escortInvuln or false  -- escort list invulnerable
GodMode.escortHeal   = GodMode.escortHeal   or false  -- escort list auto-repair
GodMode.wingInvuln   = GodMode.wingInvuln   or false  -- wing options: invulnerable
GodMode.wingHeal     = GodMode.wingHeal     or false  -- wing options: auto-repair
-- who the wing options cover: "wing" | "wings" | "team"
GodMode.wingScope    = GodMode.wingScope    or "wing"
GodMode.stealthIgnore = GodMode.stealthIgnore or false -- enemies never engage us
GodMode.stealthGhost  = GodMode.stealthGhost  or false -- off sensors entirely
GodMode.iffHold       = GodMode.iffHold       or false -- undo mission IFF changes
GodMode.iffStart      = GodMode.iffStart      or {}    -- [name] = team at first sight
GodMode.showVars      = GodMode.showVars      or false -- SEXP variables on the HUD
-- nil | "root" | "escort" | "wing" | "stealth"
GodMode.menu         = nil
-- flags WE set: [flag][name] = { escort = true, wing = true, stealth = true }
GodMode.flagSet      = GodMode.flagSet      or {}
GodMode.wingName     = ""                             -- cached player wing name
GodMode.playerTeam   = GodMode.playerTeam   or ""     -- cached player team name
GodMode.appliedTo    = GodMode.appliedTo    or ""
GodMode.cmHigh       = GodMode.cmHigh       or 0      -- highest CM count seen
GodMode.cmSource     = "none"                         -- where the CM cap came from
GodMode.cmWarned     = false                          -- one-shot "refill failed" warning
-- set to true to report key strings and countermeasure state on screen
GodMode.debug        = false

local OPEN_KEYS = { ["SHIFT-ALT-I"] = true, ["ALT-SHIFT-I"] = true }
local ESC_KEYS  = { ["ESC"] = true, ["ESCAPE"] = true }
local BACK_KEYS = { ["BACKSPACE"] = true, ["BACK-SPACE"] = true, ["BKSP"] = true }

-- keys the menu swallows while it is open, so they never reach the game
local MENU_KEYS = {
	["1"] = true, ["2"] = true, ["3"] = true,
	["4"] = true, ["5"] = true, ["6"] = true, ["7"] = true,
}
for k in pairs(ESC_KEYS)  do MENU_KEYS[k] = true end
for k in pairs(BACK_KEYS) do MENU_KEYS[k] = true end

-- "Shift-Alt-I", "SHIFT+ALT+I", "Shift Alt I" all collapse to "SHIFT-ALT-I"
local function normKey(k)
	if k == nil then return "" end
	return (string.gsub(string.upper(tostring(k)), "[%s%+]", "-"))
end

-- One property access per protected call: on a build where an unknown field
-- raises a catchable error, chaining two reads inside one pcall means the first
-- bad one silently kills the second. This only protects reads of fields that
-- EXIST somewhere in the supported builds - see the rule below for why pcall is
-- not a licence to probe.
local function try(fn)
	local ok, res = pcall(fn)
	if ok then return res end
	return nil
end

-- THE RULE THIS FILE HAS TO FOLLOW, learned the hard way on Blue Planet:
--
-- On FSO 23.2.1, reading an ADE index that does not exist is NOT a catchable Lua
-- error. The engine's error path aborts the process (dialogs.cpp Int3), so pcall
-- does not make a speculative read safe - `try(function() return gr.getStringHeight() end)`
-- killed the game outright. On 26.0.0 the same read raises a normal Lua error and
-- pcall works, which is why the probe-and-fall-back style survived this long.
--
-- So: anything added after 23.2.1 must be gated on the engine version, never
-- probed. Fields present in every build in this library stay probe-safe.
local function engineMajor()
	local text = try(function() return ba.getVersionString() end)
	if type(text) ~= "string" then return 0 end
	return tonumber(string.match(text, "(%d+)%.%d+%.%d+")) or 0
end

-- Verified against the three builds installed here: 23.2.1 has none of
-- getStringHeight / getSubsystemList / CanonicalName, 25.0.0 and 26.0.0 have all
-- three. A build we cannot identify is treated as old, which only costs polish.
local ENGINE_MAJOR = engineMajor()
local MODERN_API   = ENGINE_MAJOR >= 25

-- ba.println does not exist before 23.0.0. The Aftermath Reboot pins FSO 22.0.0
-- and the Wings of Dawn build is older still, so on those the read is exactly the
-- fatal ADE index error described above - "Could not find index 'println' in type
-- 'Base'" - and neither pcall nor try can absorb it. ba.print is present in every
-- build in this install (17.0.1 through 26.0.0) and differs only in not adding the
-- newline itself, so all logging goes through here rather than being version-gated.
local function printLine(text)
	ba.print(text .. "\n")
end

-- Every hook below runs through this. An uncaught Lua error inside an FSO hook
-- is not a quiet failure: the engine escalates it, and a release build takes the
-- whole game down with it. A cheat menu must never be able to do that, so each
-- entry point is wrapped and a failure costs you the menu, not the mission.
--
-- The message is reported once per distinct error - it is the only diagnostic
-- there is when the game is not writing fs2_open.log.
GodMode.hookErrors = GodMode.hookErrors or {}

local function guard(name, fn)
	local ok, err = pcall(fn)
	if ok then return end

	local text = "[GodMode] " .. name .. " failed: " .. tostring(err)
	if not GodMode.hookErrors[text] then
		GodMode.hookErrors[text] = true
		pcall(function() printLine(text) end)
		pcall(function() mn.sendPlainMessage(text) end)
	end
end

local function numberOf(fn)
	local ok, v = pcall(fn)
	if ok and type(v) == "number" then return v end
	return nil
end

local function log(text)
	try(function() printLine("[GodMode] " .. text) end)
end

local function notify(text)
	try(function() mn.sendPlainMessage(text) end)
	log(text)
end

local function isValid(s)
	return s ~= nil and try(function() return s:isValid() end) == true
end

local function shipName(s)
	local name = try(function() return s.Name end)
	if type(name) == "string" then return name end
	return ""
end

-- The player's ship handle, or nil. hv.Player is not used directly because its
-- handle type differs between hooks; it is only a fallback for the name lookup.
local function playerShip(hv)
	local count = numberOf(function() return #mn.Ships end)
	if count ~= nil then
		for i = 1, count do
			local s = try(function() return mn.Ships[i] end)
			if isValid(s) and try(function() return s:isPlayer() end) then
				return s
			end
		end
	end

	if hv ~= nil then
		local name = try(function() return hv.Player.Name end)
		if name ~= nil then
			local s = try(function() return mn.Ships[name] end)
			if isValid(s) then return s end
		end
	end

	return nil
end

-- Flags this build may not accept through ship:setFlag, and the SEXP pair that
-- does the same job. Tried only when the setFlag write does not take.
local FLAG_SEXP = {
	["protect-ship"]        = { on = "protect-ship",      off = "unprotect-ship" },
	["beam-protect-ship"]   = { on = "beam-protect-ship", off = "beam-unprotect-ship" },
	["stealth"]             = { on = "ship-stealthy",     off = "ship-unstealthy" },
	["hidden-from-sensors"] = { on = "ship-invisible",    off = "ship-visible" },
}

local function runShipSEXP(s, op)
	local name = shipName(s)
	if name == "" then return end
	try(function() mn.runSEXP('(' .. op .. ' "' .. name .. '")') end)
end

-- setFlag first; if the flag name is unknown to this build the write throws or
-- silently does nothing, so read it back and fall through to the SEXP. Flags
-- with no SEXP equivalent (the flak/laser/missile turret protections) are just
-- skipped on builds that do not know them.
local function setShipFlag(s, flag, on)
	try(function() s:setFlag(on, flag) end)

	local now = try(function() return s:getFlag(flag) end)
	if now == on then return end

	local sexp = FLAG_SEXP[flag]
	if sexp ~= nil then
		runShipSEXP(s, on and sexp.on or sexp.off)
	end
end

local function setInvulnerable(s, on)
	setShipFlag(s, "invulnerable", on)
end

-- "guardian" is a parse-object flag, not one of the flags ship:setFlag accepts,
-- so it always goes through the SEXP.
local function setGuardian(s, on)
	runShipSEXP(s, on and "ship-guardian" or "ship-no-guardian")
end

-- ---------------------------------------------------------------- resources --

-- Weapon banks moved onto the ship handle in newer builds; fall back to the
-- older ship.Weapons.<bank> form if this build still uses it.
local function banksOf(s, which)
	local banks = try(function() return s[which] end)
	if banks == nil then
		banks = try(function() return s.Weapons[which] end)
	end
	return banks
end

local function refillBanks(s, which)
	local banks = banksOf(s, which)
	if banks == nil then return end
	local count = numberOf(function() return #banks end)
	if count == nil then return end
	for i = 1, count do
		try(function()
			local bank = banks[i]
			if bank ~= nil and bank.AmmoMax ~= nil and bank.AmmoMax > 0 then
				bank.AmmoLeft = bank.AmmoMax
			end
		end)
	end
end

-- Countermeasure capacity lives on the ship CLASS; the ship handle only carries
-- CountermeasuresLeft. Reading s.CountermeasuresMax throws.
local function countermeasureCap(s)
	local cap = numberOf(function() return s.Class.CountermeasuresMax end)
	if cap ~= nil and cap > 0 then
		GodMode.cmSource = "class"
		return cap
	end

	-- fallback: the highest count seen this mission, so a renamed API still works
	local cur = numberOf(function() return s.CountermeasuresLeft end)
	if cur ~= nil and cur > GodMode.cmHigh then
		GodMode.cmHigh = cur
	end
	if GodMode.cmHigh > 0 then
		GodMode.cmSource = "high-water"
		return GodMode.cmHigh
	end

	GodMode.cmSource = "none"
	return nil
end

local function refillCountermeasures(s)
	local cap = countermeasureCap(s)
	if cap == nil then return end

	local before = numberOf(function() return s.CountermeasuresLeft end)
	if before ~= nil and before >= cap then return end

	try(function() s.CountermeasuresLeft = cap end)

	-- read back: if the write did not take, the property is read-only on this
	-- build. Say so once per mission, since there is no log to check.
	if not GodMode.cmWarned then
		local after = numberOf(function() return s.CountermeasuresLeft end)
		if after ~= nil and before ~= nil and after <= before and before < cap then
			GodMode.cmWarned = true
			notify("GodMode: countermeasure refill unsupported on this build")
		end
	end
end

local function topUp(s)
	try(function()
		if s.WeaponEnergyMax ~= nil and s.WeaponEnergyMax > 0 then
			s.WeaponEnergyLeft = s.WeaponEnergyMax
		end
	end)
	try(function()
		if s.AfterburnerFuelMax ~= nil and s.AfterburnerFuelMax > 0 then
			s.AfterburnerFuelLeft = s.AfterburnerFuelMax
		end
	end)
	refillCountermeasures(s)
	refillBanks(s, "SecondaryBanks")
	refillBanks(s, "PrimaryBanks")  -- ballistic primaries; others report AmmoMax 0
end

-- ------------------------------------------------------------------ escorts --

-- The escort list is really a monitor list: missions put hostiles on it too (the
-- gauge colours them differently). Only ships on the player's own team are
-- touched, or the cheat would protect the target you are meant to destroy.
local function teamNameOf(s)
	local team = try(function() return s.Team end)
	if team == nil then return "" end
	local name = try(function() return team.Name end)
	if type(name) == "string" then return name end
	return ""
end

local function playerTeamName()
	local s = playerShip()
	if s ~= nil then
		local team = teamNameOf(s)
		if team ~= "" then
			GodMode.playerTeam = team
			return team
		end
	end
	if GodMode.playerTeam ~= "" then return GodMode.playerTeam end
	return "Friendly"  -- last resort; the player is Friendly in stock campaigns
end

local function escortCount()
	local n = numberOf(function() return #mn.EscortShips end)
	if n == nil then return 0 end
	return n
end

local function escortShip(i)
	local s = try(function() return mn.EscortShips[i] end)
	if isValid(s) then return s end
	return nil
end

local function friendlyEscorts(team)
	local ships = {}
	for i = 1, escortCount() do
		local s = escortShip(i)
		if s ~= nil and teamNameOf(s) == team then
			ships[#ships + 1] = s
		end
	end
	return ships
end

-- ------------------------------------------------------------------ wingmen --

-- The player's own wing only. "Alpha 1" -> the other ships named "Alpha <n>".
-- The player's ship is left out: entry 1 of the main menu already covers it.

local function wingShipsFrom(w, ships, selfName, team)
	local count = numberOf(function() return #w end)
	if count == nil then return end
	for i = 1, count do
		local s = try(function() return w[i] end)
		if isValid(s) and shipName(s) ~= selfName and teamNameOf(s) == team then
			ships[#ships + 1] = s
		end
	end
end

-- "Alpha 1" -> "Alpha". Wing names themselves may contain spaces, so only a
-- trailing wing-position number is stripped.
local function wingNameFromShip(name)
	local base = string.match(name, "^(.-)%s+%d+$")
	if base ~= nil and base ~= "" then return base end
	return ""
end

local function wingmen(team)
	local ships = {}
	local me = playerShip()
	if me == nil then
		GodMode.wingName = ""
		return ships
	end

	local selfName = shipName(me)

	-- 1. the wing handle on the ship, where this build exposes it
	local w = try(function() return me.Wing end)
	if isValid(w) then
		local name = try(function() return w.Name end)
		GodMode.wingName = type(name) == "string" and name or ""
		wingShipsFrom(w, ships, selfName, team)
		if #ships > 0 then return ships end
	end

	-- prefer the name read off the ship we are flying now; the cached one may be
	-- left over from the ship we flew before a swap
	local wname = wingNameFromShip(selfName)
	if wname == "" then wname = GodMode.wingName end
	if wname == "" then
		GodMode.wingName = ""
		return ships
	end
	GodMode.wingName = wname

	-- 2. look the wing up by name
	local byName = try(function() return mn.Wings[wname] end)
	if isValid(byName) then
		wingShipsFrom(byName, ships, selfName, team)
		if #ships > 0 then return ships end
	end

	-- 3. last resort: match ship names against the wing prefix
	local count = numberOf(function() return #mn.Ships end)
	if count == nil then return ships end
	for i = 1, count do
		local s = try(function() return mn.Ships[i] end)
		if isValid(s) then
			local name = shipName(s)
			if name ~= selfName and wingNameFromShip(name) == wname
					and teamNameOf(s) == team then
				ships[#ships + 1] = s
			end
		end
	end
	return ships
end

-- -------------------------------------------------------------------- scope --

-- Your own wing is the default, but plenty of missions hand you allies you care
-- about who are not in it - Blue Planet's "Darkest Hour" flies you as Beta 1
-- alongside Alpha wing and a station full of friendly capships.
local SCOPE_WING  = "wing"
local SCOPE_WINGS = "wings"
local SCOPE_TEAM  = "team"

local SCOPE_NEXT = {
	[SCOPE_WING]  = SCOPE_WINGS,
	[SCOPE_WINGS] = SCOPE_TEAM,
	[SCOPE_TEAM]  = SCOPE_WING,
}

local SCOPE_LABEL = {
	[SCOPE_WING]  = "my wing",
	[SCOPE_WINGS] = "all friendly wings",
	[SCOPE_TEAM]  = "every friendly ship",
}

-- every ship in every wing on our team. #mn.Wings works on 23.2.1 and 26.0.0
-- alike, and wingShipsFrom already drops the player and anyone off-team.
local function friendlyWingShips(team)
	local ships = {}
	local me = playerShip()
	local selfName = me ~= nil and shipName(me) or ""

	local count = numberOf(function() return #mn.Wings end)
	if count == nil then return ships end

	for i = 1, count do
		local w = try(function() return mn.Wings[i] end)
		if isValid(w) then
			wingShipsFrom(w, ships, selfName, team)
		end
	end
	return ships
end

-- everything on our team, wing or not: cruisers, stations, transports
local function friendlyShips(team)
	local ships = {}
	local me = playerShip()
	local selfName = me ~= nil and shipName(me) or ""

	local count = numberOf(function() return #mn.Ships end)
	if count == nil then return ships end

	for i = 1, count do
		local s = try(function() return mn.Ships[i] end)
		if isValid(s) and shipName(s) ~= selfName and teamNameOf(s) == team then
			ships[#ships + 1] = s
		end
	end
	return ships
end

local function wingTargets(team)
	if GodMode.wingScope == SCOPE_WINGS then return friendlyWingShips(team) end
	if GodMode.wingScope == SCOPE_TEAM  then return friendlyShips(team) end
	return wingmen(team)
end

-- --------------------------------------------------------- shared flag book --

-- Set flags on ships, but never touch a flag the mission itself already set -
-- clearing that on toggle-off would break mission scripting. Only ships recorded
-- in flagSet get cleared, and only once every source that claimed them (a wingman
-- is often on the escort list too, and both cheats set "invulnerable") let go.

local function flagBook(flag)
	local book = GodMode.flagSet[flag]
	if book == nil then
		book = {}
		GodMode.flagSet[flag] = book
	end
	return book
end

local function applyFlag(source, flag, ships, team)
	local book = flagBook(flag)

	for i = 1, #ships do
		local s = ships[i]
		local name = shipName(s)
		if name ~= "" then
			local entry = book[name]
			if entry ~= nil then
				entry[source] = true          -- already ours, just add the claim
			else
				local already = try(function() return s:getFlag(flag) end)
				if already ~= true then
					setShipFlag(s, flag, true)
					book[name] = { [source] = true }
				end
			end
		end
	end

	-- a ship we flagged may have switched sides (change-iff); drop it
	for name, entry in pairs(book) do
		if entry[source] then
			local s = try(function() return mn.Ships[name] end)
			if isValid(s) and teamNameOf(s) ~= team then
				setShipFlag(s, flag, false)
				book[name] = nil
			end
		end
	end
end

local function releaseFlag(source, flag)
	local book = flagBook(flag)
	for name, entry in pairs(book) do
		if entry[source] then
			entry[source] = nil
			if next(entry) == nil then
				local s = try(function() return mn.Ships[name] end)
				if isValid(s) then
					setShipFlag(s, flag, false)
				end
				book[name] = nil
			end
		end
	end
end

local function applyFlags(source, flags, ships, team)
	for i = 1, #flags do
		applyFlag(source, flags[i], ships, team)
	end
end

local function releaseFlags(source, flags)
	for i = 1, #flags do
		releaseFlag(source, flags[i])
	end
end

local function healShip(s)
	local hpMax = numberOf(function() return s.HitpointsMax end)
	if hpMax ~= nil and hpMax > 0 then
		try(function() s.HitpointsLeft = hpMax end)
		try(function() s.SimHitpointsLeft = hpMax end)
	end

	local shields = try(function() return s.Shields end)
	if shields ~= nil then
		local shMax = numberOf(function() return shields.CombinedMax end)
		if shMax ~= nil and shMax > 0 then
			try(function() shields.CombinedLeft = shMax end)
		end
	end

	-- getSubsystemList arrived in 25.0.0; on older builds hull and shields still
	-- heal and the subsystems are simply left alone
	if not MODERN_API then return end

	-- the subsystem iterator is only valid for this frame; guard the whole loop
	pcall(function()
		for sub in s:getSubsystemList() do
			local subMax = numberOf(function() return sub.HitpointsMax end)
			if subMax ~= nil and subMax > 0 then
				try(function() sub.HitpointsLeft = subMax end)
			end
		end
	end)
end

local function healList(ships)
	for i = 1, #ships do
		healShip(ships[i])
	end
	return #ships
end

-- friendly count, total count - the menu header shows both when they differ
local function escortStats(team)
	return #friendlyEscorts(team), escortCount()
end

-- ------------------------------------------------------------------ stealth --

-- Level 1: the AI never picks us as a target. "protect-ship" covers fighters and
-- ordinary turrets; the weapon-type protections cover the turrets that check
-- their own flag; "stealth" additionally drops us off enemy sensors while leaving
-- us visible to our own side.
local STEALTH_FLAGS = {
	"protect-ship",
	"beam-protect-ship",
	"flak-protect-ship",
	"laser-protect-ship",
	"missile-protect-ship",
	"stealth",
}

-- Level 2: off every sensor in the mission. Nothing can target us at all - which
-- includes our own wingmen and the support ship.
local GHOST_FLAGS = { "hidden-from-sensors" }

-- the player plus their own wing
local function stealthTargets(team)
	local ships = wingmen(team)
	local me = playerShip()
	if me ~= nil then
		table.insert(ships, 1, me)
	end
	return ships
end

local function nameSet(ships)
	local names = {}
	for i = 1, #ships do
		local name = shipName(ships[i])
		if name ~= "" then names[name] = true end
	end
	return names
end

-- "protect-ship" stops an enemy *choosing* us; one that already locked on keeps
-- its target until it retargets on its own. Clearing the target forces that now.
-- Orders are deliberately left alone: wiping them would leave enemies inert and
-- ignoring our wingmen too, which is a much bigger change than intended.
local function dropLocks(protectedNames, team)
	local count = numberOf(function() return #mn.Ships end)
	if count == nil then return 0 end

	local dropped = 0
	for i = 1, count do
		local s = try(function() return mn.Ships[i] end)
		if isValid(s) and teamNameOf(s) ~= team then
			local target = try(function() return s.Target end)
			if isValid(target) and protectedNames[shipName(target)] then
				try(function() s.Target = nil end)
				dropped = dropped + 1
			end
		end
	end
	return dropped
end

-- ---------------------------------------------------------------- iff alarm --

-- Sneaking missions rarely use sensors for detection - they use a SEXP that
-- measures distance and flips the whole enemy fleet to Hostile, which no stealth
-- flag can touch. Derelict's "Said the Spider to the Fly" is the model:
--   ( when ( < ( distance "<any friendly>" "Aries" ) 200 )
--          ( change-iff "Hostile" <the entire fleet> ) )
-- The event cannot be blocked - mn.Events is read-only - but it can be undone by
-- putting every ship back on the team it started the mission on.

local function setShipTeam(s, team)
	local name = shipName(s)
	if name == "" or team == "" then return end
	try(function() mn.runSEXP('(change-iff "' .. team .. '" "' .. name .. '")') end)
end

-- Recorded every frame from mission start, whether or not the toggle is on: the
-- snapshot is worthless unless it predates the alarm. A ship that arrives later
-- is recorded on arrival, already-hostile ones included - which is what we want,
-- since those were never non-hostile to begin with.
local function snapshotIff()
	local count = numberOf(function() return #mn.Ships end)
	if count == nil then return end

	for i = 1, count do
		local s = try(function() return mn.Ships[i] end)
		if isValid(s) then
			local name = shipName(s)
			if name ~= "" and GodMode.iffStart[name] == nil then
				local team = teamNameOf(s)
				if team ~= "" then GodMode.iffStart[name] = team end
			end
		end
	end
end

local function restoreIff()
	local count = numberOf(function() return #mn.Ships end)
	if count == nil then return 0 end

	local restored = 0
	for i = 1, count do
		local s = try(function() return mn.Ships[i] end)
		if isValid(s) then
			local was = GodMode.iffStart[shipName(s)]
			if was ~= nil and was ~= teamNameOf(s) then
				setShipTeam(s, was)
				restored = restored + 1
			end
		end
	end
	return restored
end

-- --------------------------------------------------------------------- scan --

-- Missions gate objectives - and sometimes the campaign branch itself - on cargo
-- and subsystem scans. Derelict's "Said the Spider to the Fly" picks the next
-- mission from how many Nyarlathotep subsystems were scanned, not from whether
-- you were spotted. set-scanned marks them without the fly-close-and-hold-still
-- routine. Returns the message to show; the caller notifies it.
local function scanTarget()
	local me = playerShip()
	if me == nil then return "No ship to scan from" end

	local target = try(function() return me.Target end)
	if not isValid(target) then return "No target selected" end

	local name = shipName(target)
	if name == "" then return "Target has no name" end

	-- the target comes back as an object handle; the ship handle is what carries
	-- the subsystem list
	local s = try(function() return mn.Ships[name] end)
	if not isValid(s) then return "Target is not a ship" end

	-- ship-level first: this is the cargo scan that is-cargo-known checks
	try(function() mn.runSEXP('(set-scanned "' .. name .. '")') end)

	-- then every subsystem, one call each so a name this build rejects does not
	-- take the rest of the list with it.
	--
	-- CanonicalName is the one documented as usable to reference a subsystem from
	-- a SEXP; Name can differ (multi-word entries like "fighterbay 1" are the
	-- ones that bite), and a name the SEXP does not recognise fails silently -
	-- which looks exactly like the cheat working while nothing gets scanned.
	-- getSubsystemList and CanonicalName both arrived in 25.0.0, and on 23.2.1
	-- reading either is fatal, so the subsystem pass is skipped entirely there
	if not MODERN_API then
		return "Scanned " .. name .. " (cargo only - engine too old for subsystems)"
	end

	local subs = 0
	pcall(function()
		for sub in s:getSubsystemList() do
			local subName = try(function() return sub.CanonicalName end)
			if type(subName) ~= "string" or subName == "" then
				subName = try(function() return sub.Name end)
			end
			if type(subName) == "string" and subName ~= "" then
				try(function()
					mn.runSEXP('(set-scanned "' .. name .. '" "' .. subName .. '")')
				end)
				subs = subs + 1
			end
		end
	end)

	if subs > 0 then
		return "Scanned " .. name .. " (" .. tostring(subs) .. " subsystems)"
	end
	return "Scanned " .. name
end

-- ---------------------------------------------------------- mission vars --

-- Missions keep their bookkeeping in SEXP variables, and campaign branches are
-- usually decided by them (dl3-04 routes on @SSCount, one point per Nyarlathotep
-- subsystem scanned). Putting them on the HUD turns "did that cheat do anything?"
-- into something you can watch while you fly.
--
-- No isValid() call here: it is not clear this handle type has one, and the
-- helper treats a missing method as invalid, which would hide every variable.

local MAX_VARS = 8

-- Only Value is read. The old .Text / .Number fallbacks were exactly the kind of
-- speculative read that aborts the game on 23.2.1, and Value is present in every
-- build here ("SEXP variable contents, or nil if the variable is of an invalid
-- type"), so a nil means an odd variable, not a missing property.
local function varValue(v)
	local val = try(function() return v.Value end)
	if val == nil then return "?" end
	return tostring(val)
end

local function missionVars()
	local out = {}
	local count = numberOf(function() return #mn.SEXPVariables end)
	if count == nil then return out end

	for i = 1, count do
		if #out >= MAX_VARS then break end
		local v = try(function() return mn.SEXPVariables[i] end)
		if v ~= nil then
			local name = try(function() return v.Name end)
			if type(name) == "string" and name ~= "" then
				out[#out + 1] = name .. " = " .. varValue(v)
			end
		end
	end
	return out
end

-- --------------------------------------------------------------------- menu --

local function toggleGod()
	GodMode.enabled = not GodMode.enabled
	local s = playerShip()
	if s ~= nil then
		setInvulnerable(s, GodMode.enabled)
		GodMode.appliedTo = GodMode.enabled and shipName(s) or ""
	end
	if GodMode.debug and GodMode.enabled and s ~= nil then
		local cap  = countermeasureCap(s)
		local left = numberOf(function() return s.CountermeasuresLeft end)
		notify("CM " .. tostring(left) .. "/" .. tostring(cap)
			.. " src=" .. GodMode.cmSource)
	end
end

local function toggleGuardian()
	GodMode.guardian = not GodMode.guardian
	local s = playerShip()
	if s ~= nil then
		setGuardian(s, GodMode.guardian)
	end
end

local function toggleEscortInvuln()
	GodMode.escortInvuln = not GodMode.escortInvuln
	if GodMode.escortInvuln then
		local team = playerTeamName()
		applyFlag("escort", "invulnerable", friendlyEscorts(team), team)
	else
		releaseFlag("escort", "invulnerable")
	end
end

local function toggleWingInvuln()
	GodMode.wingInvuln = not GodMode.wingInvuln
	if GodMode.wingInvuln then
		local team = playerTeamName()
		applyFlag("wing", "invulnerable", wingTargets(team), team)
	else
		releaseFlag("wing", "invulnerable")
	end
end

-- Narrowing the scope has to hand back the ships that just left it, so release
-- the whole claim and re-apply to the new set rather than letting the old one
-- keep a flag nobody is asking for any more.
local function cycleWingScope()
	GodMode.wingScope = SCOPE_NEXT[GodMode.wingScope] or SCOPE_WING
	if GodMode.wingInvuln then
		releaseFlag("wing", "invulnerable")
		local team = playerTeamName()
		applyFlag("wing", "invulnerable", wingTargets(team), team)
	end
end

local function toggleStealthIgnore()
	GodMode.stealthIgnore = not GodMode.stealthIgnore
	if GodMode.stealthIgnore then
		local team  = playerTeamName()
		local ships = stealthTargets(team)
		applyFlags("stealth", STEALTH_FLAGS, ships, team)
		dropLocks(nameSet(ships), team)
	else
		releaseFlags("stealth", STEALTH_FLAGS)
	end
end

local function toggleStealthGhost()
	GodMode.stealthGhost = not GodMode.stealthGhost
	if GodMode.stealthGhost then
		local team = playerTeamName()
		applyFlags("ghost", GHOST_FLAGS, stealthTargets(team), team)
	else
		releaseFlags("ghost", GHOST_FLAGS)
	end
end

-- The comm menu (C) owns the number keys and ESC while it is up, and it reads
-- them on a path the scripting override does not intercept - so ordering Alpha 2
-- to attack ALSO toggled god mode, and ESC closed both menus at once. Whenever
-- it is open the cheat menu goes inert: it claims no keys and draws nothing.
--
-- Unlike the calls gated on MODERN_API, this one needs no version gate: the
-- symbol is present in every build in this library, 23.2.1 included (checked
-- against the binaries), so the read is safe on Blue Planet too.
local function commMenuOpen()
	return try(function() return hu.isCommMenuOpen() end) == true
end

function GodMode_KeyOverride(hv)
	local ok, res = pcall(function()
		if GodMode.menu == nil then return false end
		if commMenuOpen() then return false end
		return MENU_KEYS[normKey(hv ~= nil and hv.Key or nil)] == true
	end)
	if ok then return res end
	return false  -- never swallow a key we failed to understand
end

local function keyPressed(hv)
	local key = normKey(hv ~= nil and hv.Key or nil)

	if GodMode.debug and key ~= "" then
		notify("GodMode key: " .. key)
	end

	-- Shift+Alt+I is handled before the comm-menu check below: it cannot collide
	-- with anything the comm menu reads, and leaving it live means a build where
	-- isCommMenuOpen ever got stuck true could not lock us out of the menu.
	if OPEN_KEYS[key] then
		GodMode.menu = (GodMode.menu == nil) and "root" or nil
		return
	end

	if GodMode.menu == nil then return end

	-- give orders without toggling cheats, and let ESC close only the comm menu
	if commMenuOpen() then return end

	if ESC_KEYS[key] then
		GodMode.menu = nil
	elseif GodMode.menu == "root" then
		if key == "1" then
			toggleGod()
		elseif key == "2" then
			toggleGuardian()
		elseif key == "3" then
			GodMode.menu = "escort"
		elseif key == "4" then
			GodMode.menu = "wing"
		elseif key == "5" then
			GodMode.menu = "stealth"
		elseif key == "6" then
			notify(scanTarget())
		elseif key == "7" then
			GodMode.showVars = not GodMode.showVars
		end
	elseif GodMode.menu == "escort" then
		if BACK_KEYS[key] then
			GodMode.menu = "root"
		elseif key == "1" then
			toggleEscortInvuln()
		elseif key == "2" then
			local n = healList(friendlyEscorts(playerTeamName()))
			notify(n > 0 and ("Repaired " .. tostring(n) .. " escort ship(s)")
				or "No friendly ships on the escort list")
		elseif key == "3" then
			GodMode.escortHeal = not GodMode.escortHeal
		end
	elseif GodMode.menu == "wing" then
		if BACK_KEYS[key] then
			GodMode.menu = "root"
		elseif key == "1" then
			toggleWingInvuln()
		elseif key == "2" then
			local n = healList(wingTargets(playerTeamName()))
			if n == 0 then
				notify("Nothing in scope to repair")
			else
				notify("Repaired " .. tostring(n)
					.. (n == 1 and " ship" or " ships"))
			end
		elseif key == "3" then
			GodMode.wingHeal = not GodMode.wingHeal
		elseif key == "4" then
			cycleWingScope()
		end
	elseif GodMode.menu == "stealth" then
		if BACK_KEYS[key] then
			GodMode.menu = "root"
		elseif key == "1" then
			toggleStealthIgnore()
		elseif key == "2" then
			toggleStealthGhost()
		elseif key == "3" then
			local team = playerTeamName()
			local n = dropLocks(nameSet(stealthTargets(team)), team)
			notify(n > 0 and ("Dropped " .. tostring(n) .. " enemy lock(s)")
				or "Nothing has us targeted")
		elseif key == "4" then
			GodMode.iffHold = not GodMode.iffHold
			if GodMode.iffHold then restoreIff() end
		elseif key == "5" then
			local n = restoreIff()
			notify(n > 0 and ("Restored IFF on " .. tostring(n) .. " ship(s)")
				or "No ship has changed sides")
		end
	end
end

-- --------------------------------------------------------------------- hooks --

function GodMode_KeyPressed(hv)
	guard("KeyPressed", function() keyPressed(hv) end)
end

-- Each section below is guarded separately. They are independent cheats, and a
-- wingman must not die because the IFF snapshot tripped over an API this build
-- does not have - which is exactly what one shared guard around the lot would do
-- to every section after the one that threw.

local function frameIff()
	-- unconditional: a snapshot taken after the alarm has fired is worthless
	snapshotIff()
	if GodMode.iffHold then restoreIff() end
end

local function frameEscort(team)
	if not (GodMode.escortInvuln or GodMode.escortHeal) then return end

	local ships = friendlyEscorts(team)
	if GodMode.escortInvuln then applyFlag("escort", "invulnerable", ships, team) end
	if GodMode.escortHeal   then healList(ships)                                  end
end

local function frameWing(team)
	if not (GodMode.wingInvuln or GodMode.wingHeal) then return end

	local ships = wingTargets(team)
	if GodMode.wingInvuln then applyFlag("wing", "invulnerable", ships, team) end
	if GodMode.wingHeal   then healList(ships)                                end
end

-- re-applied every frame so respawns, ship swaps and fresh wing waves are
-- covered; applyFlags only writes a flag the first time it claims a ship
local function frameStealth(team)
	if not (GodMode.stealthIgnore or GodMode.stealthGhost) then return end

	local ships = stealthTargets(team)
	if GodMode.stealthIgnore then
		applyFlags("stealth", STEALTH_FLAGS, ships, team)
		dropLocks(nameSet(ships), team)
	end
	if GodMode.stealthGhost then
		applyFlags("ghost", GHOST_FLAGS, ships, team)
	end
end

local function framePlayer()
	if not (GodMode.enabled or GodMode.guardian) then return end

	local s = playerShip()
	if s == nil then return end

	-- respawn, ship swap or a fresh mission: re-apply the persistent flags
	local name = shipName(s)
	if name ~= GodMode.appliedTo then
		if GodMode.enabled then setInvulnerable(s, true) end
		if GodMode.guardian then setGuardian(s, true) end
		GodMode.appliedTo = name
	end

	if GodMode.enabled then
		setInvulnerable(s, true)
	end

	-- resources are topped up by either toggle
	topUp(s)
end

function GodMode_Frame()
	local team = "Friendly"
	guard("Frame/team", function() team = playerTeamName() end)

	guard("Frame/iff",     frameIff)
	guard("Frame/escort",  function() frameEscort(team) end)
	guard("Frame/wing",    function() frameWing(team) end)
	guard("Frame/stealth", function() frameStealth(team) end)
	guard("Frame/player",  framePlayer)
end

local function onOff(flag)
	if flag then return "[ON ]" end
	return "[OFF]"
end

local function menuLines()
	if GodMode.menu == "root" then
		return {
			"CHEAT MENU",
			"",
			"1  God mode      " .. onOff(GodMode.enabled),
			"2  Guardian      " .. onOff(GodMode.guardian),
			"3  Escort ships...",
			"4  Wingmen...",
			"5  Stealth...",
			"6  Scan target now",
			"7  Mission vars " .. onOff(GodMode.showVars),
			"",
			"ESC  close",
		}
	end

	if GodMode.menu == "stealth" then
		local n = #wingmen(playerTeamName())
		local header = "STEALTH (you only)"
		if n == 1 then
			header = "STEALTH (you + 1 wingman)"
		elseif n > 1 then
			header = "STEALTH (you + " .. tostring(n) .. " wingmen)"
		end

		return {
			header,
			"",
			"1  Enemies ignore me   " .. onOff(GodMode.stealthIgnore),
			"2  Ghost (no sensors)  " .. onOff(GodMode.stealthGhost),
			"3  Drop enemy locks now",
			"4  Hold IFF (no alarm) " .. onOff(GodMode.iffHold),
			"5  Reset IFF now",
			"",
			"BKSP  back      ESC  close",
		}
	end

	if GodMode.menu == "wing" then
		local ships = wingTargets(playerTeamName())
		local header

		if GodMode.wingScope ~= SCOPE_WING then
			-- the wing name means nothing once we are past our own wing
			header = "WINGMEN (" .. tostring(#ships) .. " ships in scope)"
		elseif #ships > 0 then
			header = "WINGMEN (" .. tostring(#ships) .. " in " .. GodMode.wingName .. ")"
		elseif GodMode.wingName ~= "" then
			header = "WINGMEN (none left in " .. GodMode.wingName .. ")"
		else
			header = "WINGMEN (wing not found)"
		end

		return {
			header,
			"",
			"1  Invulnerable   " .. onOff(GodMode.wingInvuln),
			"2  Heal to full now",
			"3  Keep healing    " .. onOff(GodMode.wingHeal),
			"4  Scope: " .. (SCOPE_LABEL[GodMode.wingScope] or "?"),
			"",
			"BKSP  back      ESC  close",
		}
	end

	local friendly, total = escortStats(playerTeamName())
	local header = "ESCORT SHIPS (none on list)"
	if total > 0 then
		if friendly == total then
			header = "ESCORT SHIPS (" .. tostring(total) .. " on list)"
		else
			-- the list also holds hostiles; only the friendly ones are affected
			header = "ESCORT SHIPS (" .. tostring(friendly)
				.. " friendly of " .. tostring(total) .. ")"
		end
	end

	return {
		header,
		"",
		"1  Invulnerable   " .. onOff(GodMode.escortInvuln),
		"2  Heal to full now",
		"3  Keep healing    " .. onOff(GodMode.escortHeal),
		"",
		"BKSP  back      ESC  close",
	}
end

local function drawMenu(r, g, b, a)
	local lines = menuLines()

	-- gr.getStringHeight does not exist before 25.0.0, and reading it there is
	-- fatal rather than catchable - this is the call that crashed Blue Planet
	local lineH = nil
	if MODERN_API then
		lineH = numberOf(function() return gr.getStringHeight("Ay") end)
	end
	if lineH == nil or lineH <= 0 then lineH = 16 end
	lineH = lineH + 2

	local width = 0
	for i = 1, #lines do
		local w = numberOf(function() return gr.getStringWidth(lines[i]) end)
		if w ~= nil and w > width then width = w end
	end
	if width <= 0 then width = 280 end

	local pad = 12
	local x1  = 0.06 * gr.getScreenWidth()
	local y1  = 0.28 * gr.getScreenHeight()
	local x2  = x1 + width + pad * 2
	local y2  = y1 + lineH * #lines + pad * 2

	try(function()
		gr.setColor(0, 0, 0, 160)
		gr.drawRectangle(x1, y1, x2, y2, true)
	end)
	try(function()
		gr.setColor(r, g, b, a)
		gr.drawRectangle(x1, y1, x2, y2, false)
	end)

	for i = 1, #lines do
		local ly = y1 + pad + (i - 1) * lineH
		try(function()
			gr.setColor(r, g, b, a)
			gr.drawString(lines[i], x1 + pad, ly)
		end)
	end
end

local function statusLabel()
	local parts = {}
	if GodMode.enabled      then parts[#parts + 1] = "GOD MODE" end
	if GodMode.guardian     then parts[#parts + 1] = "GUARDIAN" end
	if GodMode.escortInvuln then parts[#parts + 1] = "ESCORT INVUL" end
	if GodMode.escortHeal   then parts[#parts + 1] = "ESCORT HEAL" end
	if GodMode.wingInvuln   then parts[#parts + 1] = "WING INVUL" end
	if GodMode.wingHeal     then parts[#parts + 1] = "WING HEAL" end
	if GodMode.stealthIgnore then parts[#parts + 1] = "STEALTH" end
	if GodMode.stealthGhost then parts[#parts + 1] = "GHOST" end
	if GodMode.iffHold      then parts[#parts + 1] = "IFF HOLD" end
	return table.concat(parts, " + ")
end

-- lines are drawn upwards from just above the status label
local function drawVars(r, g, b, a)
	local vars = missionVars()
	if #vars == 0 then return end

	local lineH = nil
	if MODERN_API then
		lineH = numberOf(function() return gr.getStringHeight("Ay") end)
	end
	if lineH == nil or lineH <= 0 then lineH = 16 end
	lineH = lineH + 2

	local x = 0.02 * gr.getScreenWidth()
	local y = 0.88 * gr.getScreenHeight() - lineH * #vars

	for i = 1, #vars do
		try(function()
			gr.setColor(r, g, b, a)
			gr.drawString(vars[i], x, y + (i - 1) * lineH)
		end)
	end
end

local function hudColor()
	-- pcall directly: the color getter returns four values and try() keeps only one
	local r, g, b, a = 0, 255, 0, 255
	local ok, cr, cg, cb, ca = pcall(function()
		return hu.getHUDGaugeColorInMission(0)
	end)
	if ok and cr ~= nil and cg ~= nil and cb ~= nil then
		r, g, b = cr, cg, cb
		if ca ~= nil then a = ca end
	end
	return r, g, b, a
end

local function drawStatus(label, r, g, b, a)
	try(function()
		gr.setColor(r, g, b, a)
		gr.drawString(label,
			0.02 * gr.getScreenWidth(),
			0.90 * gr.getScreenHeight())
	end)
end

-- guarded piece by piece for the same reason the frame hook is: a broken
-- variable readout must not cost you the menu you are trying to read
function GodMode_HudDraw()
	local label = ""
	guard("HudDraw/label", function() label = statusLabel() end)

	if GodMode.menu == nil and label == "" and not GodMode.showVars then return end

	local hidden = false
	guard("HudDraw/hud", function()
		hidden = (hu ~= nil and hu.HUDDrawn == false)
	end)
	if hidden then return end

	local r, g, b, a = 0, 255, 0, 255
	guard("HudDraw/color", function() r, g, b, a = hudColor() end)

	-- The menu box sits at 6%/28%, right where the comm menu draws, and it is
	-- inert anyway while that is up - so take it off screen instead of stacking
	-- two menus on top of each other. It comes back when the comm menu closes.
	if GodMode.menu ~= nil and not commMenuOpen() then
		guard("HudDraw/menu", function() drawMenu(r, g, b, a) end)
	end

	if GodMode.showVars then
		guard("HudDraw/vars", function() drawVars(r, g, b, a) end)
	end

	if label ~= "" then
		guard("HudDraw/status", function() drawStatus(label, r, g, b, a) end)
	end
end

function GodMode_MissionStart()
	guard("MissionStart", function()
		-- ships do not exist yet; clear the markers so the first frame re-applies
		GodMode.appliedTo  = ""
		GodMode.cmHigh     = 0
		GodMode.cmWarned   = false
		GodMode.flagSet    = {}
		GodMode.iffStart   = {}
		GodMode.wingName   = ""
		GodMode.menu       = nil
		GodMode.hookErrors = {}
	end)
end

-- the engine reading is worth having in the log: if it comes out 0 the version
-- string did not parse, and the modern-API features are being skipped silently
log("loaded (Shift+Alt+I opens the cheat menu) - engine major "
	.. tostring(ENGINE_MAJOR)
	.. (MODERN_API and ", modern API" or ", legacy API"))
