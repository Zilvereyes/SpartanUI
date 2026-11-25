--- **AceComm-3.0** allows you to send messages longer than one addon-message packet.
-- It'll automatically split messages into multiple parts and rebuild bounded messages on the receiving end.\\
-- **ChatThrottleLib** is of course being used to avoid being disconnected by the server.
--
-- **AceComm-3.0** can be embeded into your addon, either explicitly by calling AceComm:Embed(MyAddon) or by
-- specifying it as an embeded library in your AceAddon. All functions will be available on your addon object
-- and can be accessed directly, without having to explicitly call AceComm itself.\\
-- It is recommended to embed AceComm, otherwise you'll have to specify a custom `self` on all calls you
-- make into AceComm.
-- @class file
-- @name AceComm-3.0
-- @release $Id$

local CallbackHandler = LibStub("CallbackHandler-1.0")
local CTL = assert(ChatThrottleLib, "AceComm-3.0 requires ChatThrottleLib")

local MAJOR, MINOR = "AceComm-3.0", 15
local AceComm,oldminor = LibStub:NewLibrary(MAJOR, MINOR)

if not AceComm then return end

-- Lua APIs
local type, next, pairs, tostring = type, next, pairs, tostring
local rawget = rawget
local strsub, strfind = string.sub, string.find
local match = string.match
local tinsert, tconcat = table.insert, table.concat
local error, assert = error, assert

-- WoW APIs
local Ambiguate = Ambiguate
local GetTime = GetTime

AceComm.embeds = AceComm.embeds or {}

-- for my sanity and yours, let's give the message type bytes some names
local MSG_MULTI_FIRST = "\001"
local MSG_MULTI_NEXT  = "\002"
local MSG_MULTI_LAST  = "\003"
local MSG_ESCAPE = "\004"

-- remove old structures (pre WoW 4.0)
AceComm.multipart_origprefixes = nil
AceComm.multipart_reassemblers = nil

-- Bound incomplete remote messages. The byte limits include payload only; part and
-- stream limits also bound table/key overhead from empty or highly fragmented input.
local MAX_MULTIPART_BYTES = 1024 * 1024
local MAX_MULTIPART_PARTS = 4096
local MAX_SENDER_BYTES = 2 * 1024 * 1024
local MAX_SENDER_PARTS = 8192
local MAX_SENDER_STREAMS = 4
local MAX_GLOBAL_BYTES = 4 * 1024 * 1024
local MAX_GLOBAL_PARTS = 16384
local MAX_GLOBAL_STREAMS = 64
local MAX_GLOBAL_SENDERS = 64
local MAX_MULTIPART_AGE = 3600
local MAX_MULTIPART_IDLE = 120
local MULTIPART_CLEANUP_INTERVAL = 30

-- Discard any legacy, unaccounted reassembly state when upgrading the library.
AceComm.multipart_spool = {}

--- Register for Addon Traffic on a specified prefix
-- @param prefix A printable character (\032-\255) classification of the message (typically AddonName or AddonNameEvent), max 16 characters
-- @param method Callback to call on message reception: Function reference, or method name (string) to call on self. Defaults to "OnCommReceived"
function AceComm:RegisterComm(prefix, method)
	if method == nil then
		method = "OnCommReceived"
	end

	if #prefix > 16 then -- TODO: 15?
		error("AceComm:RegisterComm(prefix,method): prefix length is limited to 16 characters")
	end
	if C_ChatInfo then
		C_ChatInfo.RegisterAddonMessagePrefix(prefix)
	else
		RegisterAddonMessagePrefix(prefix)
	end

	return AceComm._RegisterComm(self, prefix, method)	-- created by CallbackHandler
end

local warnedPrefix=false

--- Send a message over the Addon Channel
-- @param prefix A printable character (\032-\255) classification of the message (typically AddonName or AddonNameEvent)
-- @param text Data to send, nils (\000) not allowed. Any length.
-- @param distribution Addon channel, e.g. "RAID", "GUILD", etc; see SendAddonMessage API
-- @param target Destination for some distributions; see SendAddonMessage API
-- @param prio OPTIONAL: ChatThrottleLib priority, "BULK", "NORMAL" or "ALERT". Defaults to "NORMAL".
-- @param callbackFn OPTIONAL: callback function to be called as each chunk is sent. receives 3 args: the user supplied arg (see next), the number of bytes sent so far, and the number of bytes total to send.
-- @param callbackArg: OPTIONAL: first arg to the callback function. nil will be passed if not specified.
function AceComm:SendCommMessage(prefix, text, distribution, target, prio, callbackFn, callbackArg)
	prio = prio or "NORMAL"	-- pasta's reference implementation had different prio for singlepart and multipart, but that's a very bad idea since that can easily lead to out-of-sequence delivery!
	if not( type(prefix)=="string" and
			type(text)=="string" and
			type(distribution)=="string" and
			(target==nil or type(target)=="string" or type(target)=="number") and
			(prio=="BULK" or prio=="NORMAL" or prio=="ALERT")
		) then
		error('Usage: SendCommMessage(addon, "prefix", "text", "distribution"[, "target"[, "prio"[, callbackFn, callbackarg]]])', 2)
	end

	local textlen = #text
	local maxtextlen = 255  -- Yes, the max is 255 even if the dev post said 256. I tested. Char 256+ get silently truncated. /Mikk, 20110327
	local queueName = prefix

	local ctlCallback = nil
	if callbackFn then
		ctlCallback = function(sent, sendResult)
			return callbackFn(callbackArg, sent, textlen, sendResult)
		end
	end

	local forceMultipart
	if match(text, "^[\001-\009]") then -- 4.1+: see if the first character is a control character
		-- we need to escape the first character with a \004
		if textlen+1 > maxtextlen then	-- would we go over the size limit?
			forceMultipart = true	-- just make it multipart, no escape problems then
		else
			text = "\004" .. text
		end
	end

	if not forceMultipart and textlen <= maxtextlen then
		-- fits all in one message
		CTL:SendAddonMessage(prio, prefix, text, distribution, target, queueName, ctlCallback, textlen)
	else
		maxtextlen = maxtextlen - 1	-- 1 extra byte for part indicator in prefix(4.0)/start of message(4.1)

		-- first part
		local chunk = strsub(text, 1, maxtextlen)
		CTL:SendAddonMessage(prio, prefix, MSG_MULTI_FIRST..chunk, distribution, target, queueName, ctlCallback, maxtextlen)

		-- continuation
		local pos = 1+maxtextlen

		while pos+maxtextlen <= textlen do
			chunk = strsub(text, pos, pos+maxtextlen-1)
			CTL:SendAddonMessage(prio, prefix, MSG_MULTI_NEXT..chunk, distribution, target, queueName, ctlCallback, pos+maxtextlen-1)
			pos = pos + maxtextlen
		end

		-- final part
		chunk = strsub(text, pos)
		CTL:SendAddonMessage(prio, prefix, MSG_MULTI_LAST..chunk, distribution, target, queueName, ctlCallback, textlen)
	end
end


----------------------------------------
-- Message receiving
----------------------------------------

local cleanupMultipartSpool, clearMultipartPrefix

do
	local compost = setmetatable({}, {__mode = "k"})
	local function new()
		local t = next(compost)
		if t then
			compost[t]=nil
			for i=#t,1,-1 do
				t[i]=nil
			end
			return t
		end

		return {}
	end

	local spool = AceComm.multipart_spool
	local senderUsage = {}
	local activeBytes, activeParts, activeStreams, activeSenders = 0, 0, 0, 0

	local function streamKey(prefix, distribution, sender)
		return prefix.."\t"..distribution.."\t"..sender
	end

	local function discardStream(key, recycleParts)
		local stream = spool[key]
		if not stream then
			return
		end

		spool[key] = nil
		activeBytes = activeBytes - stream.bytes
		activeParts = activeParts - stream.partCount
		activeStreams = activeStreams - 1

		local usage = senderUsage[stream.sender]
		usage.bytes = usage.bytes - stream.bytes
		usage.parts = usage.parts - stream.partCount
		usage.streams = usage.streams - 1
		if usage.streams == 0 then
			senderUsage[stream.sender] = nil
			activeSenders = activeSenders - 1
		end

		if recycleParts ~= false then
			compost[stream.parts] = true
		end

		return stream
	end

	local function cleanupExpiredStreams(now)
		for key, stream in pairs(spool) do
			if now - stream.started >= MAX_MULTIPART_AGE or now - stream.updated >= MAX_MULTIPART_IDLE then
				discardStream(key)
			end
		end
	end

	local function canStartStream(sender, bytes)
		local usage = senderUsage[sender]
		if bytes > MAX_MULTIPART_BYTES or activeBytes + bytes > MAX_GLOBAL_BYTES
			or activeParts + 1 > MAX_GLOBAL_PARTS or activeStreams + 1 > MAX_GLOBAL_STREAMS then
			return false
		end
		if not usage then
			return activeSenders + 1 <= MAX_GLOBAL_SENDERS
		end
		return usage.bytes + bytes <= MAX_SENDER_BYTES
			and usage.parts + 1 <= MAX_SENDER_PARTS
			and usage.streams + 1 <= MAX_SENDER_STREAMS
	end

	local function canAppendStream(stream, bytes, now)
		local usage = senderUsage[stream.sender]
		return now - stream.started < MAX_MULTIPART_AGE
			and now - stream.updated < MAX_MULTIPART_IDLE
			and stream.bytes + bytes <= MAX_MULTIPART_BYTES
			and stream.partCount + 1 <= MAX_MULTIPART_PARTS
			and usage.bytes + bytes <= MAX_SENDER_BYTES
			and usage.parts + 1 <= MAX_SENDER_PARTS
			and activeBytes + bytes <= MAX_GLOBAL_BYTES
			and activeParts + 1 <= MAX_GLOBAL_PARTS
	end

	local function appendStream(stream, message, now)
		local bytes = #message
		stream.bytes = stream.bytes + bytes
		stream.partCount = stream.partCount + 1
		stream.updated = now
		tinsert(stream.parts, message)

		local usage = senderUsage[stream.sender]
		usage.bytes = usage.bytes + bytes
		usage.parts = usage.parts + 1
		activeBytes = activeBytes + bytes
		activeParts = activeParts + 1
	end

	function AceComm:OnReceiveMultipartFirst(prefix, message, distribution, sender)
		local now = GetTime()
		local key = streamKey(prefix, distribution, sender)
		cleanupExpiredStreams(now)
		discardStream(key)

		local bytes = #message
		if not canStartStream(sender, bytes) then
			return
		end

		local usage = senderUsage[sender]
		if not usage then
			usage = { bytes = 0, parts = 0, streams = 0 }
			senderUsage[sender] = usage
			activeSenders = activeSenders + 1
		end

		local parts = new()
		parts[1] = message
		spool[key] = {
			bytes = bytes,
			partCount = 1,
			parts = parts,
			prefix = prefix,
			sender = sender,
			started = now,
			updated = now,
		}
		usage.bytes = usage.bytes + bytes
		usage.parts = usage.parts + 1
		usage.streams = usage.streams + 1
		activeBytes = activeBytes + bytes
		activeParts = activeParts + 1
		activeStreams = activeStreams + 1
	end

	function AceComm:OnReceiveMultipartNext(prefix, message, distribution, sender)
		local now = GetTime()
		local key = streamKey(prefix, distribution, sender)
		cleanupExpiredStreams(now)
		local stream = spool[key]

		if not stream then
			return
		end
		if not canAppendStream(stream, #message, now) then
			discardStream(key)
			return
		end

		appendStream(stream, message, now)
	end

	function AceComm:OnReceiveMultipartLast(prefix, message, distribution, sender)
		local now = GetTime()
		local key = streamKey(prefix, distribution, sender)
		cleanupExpiredStreams(now)
		local stream = spool[key]

		if not stream then
			return
		end
		if not canAppendStream(stream, #message, now) then
			discardStream(key)
			return
		end

		appendStream(stream, message, now)
		stream = discardStream(key, false)
		local parts = stream.parts
		local completed = tconcat(parts, "")
		compost[parts] = true
		AceComm.callbacks:Fire(prefix, completed, distribution, sender)
	end

	cleanupMultipartSpool = function(now)
		cleanupExpiredStreams(now or GetTime())
	end

	clearMultipartPrefix = function(prefix)
		for key, stream in pairs(spool) do
			if stream.prefix == prefix then
				discardStream(key)
			end
		end
	end
end






----------------------------------------
-- Embed CallbackHandler
----------------------------------------

if not AceComm.callbacks then
	AceComm.callbacks = CallbackHandler:New(AceComm,
						"_RegisterComm",
						"UnregisterComm",
						"UnregisterAllComm")
end

AceComm.callbacks.OnUsed = nil
AceComm.callbacks.OnUnused = function(_, _, prefix)
	clearMultipartPrefix(prefix)
end

local function IsCommRegistered(prefix)
	local handlers = rawget(AceComm.callbacks.events, prefix)
	return handlers and next(handlers) ~= nil
end

local function OnEvent(self, event, prefix, message, distribution, sender)
	if event == "CHAT_MSG_ADDON" then
		-- CHAT_MSG_ADDON is global. Ignore multipart control bytes unless an
		-- AceComm consumer has explicitly registered this prefix.
		if not IsCommRegistered(prefix) then
			return
		end
		sender = Ambiguate(sender, "none")
		local control, rest = match(message, "^([\001-\009])(.*)")
		if control then
			if control==MSG_MULTI_FIRST then
				AceComm:OnReceiveMultipartFirst(prefix, rest, distribution, sender)
			elseif control==MSG_MULTI_NEXT then
				AceComm:OnReceiveMultipartNext(prefix, rest, distribution, sender)
			elseif control==MSG_MULTI_LAST then
				AceComm:OnReceiveMultipartLast(prefix, rest, distribution, sender)
			elseif control==MSG_ESCAPE then
				AceComm.callbacks:Fire(prefix, rest, distribution, sender)
			else
				-- unknown control character, ignore SILENTLY (dont warn unnecessarily about future extensions!)
			end
		else
			-- single part: fire it off immediately and let CallbackHandler decide if it's registered or not
			AceComm.callbacks:Fire(prefix, message, distribution, sender)
		end
	else
		assert(false, "Received "..tostring(event).." event?!")
	end
end

local cleanupElapsed = 0
local function OnUpdate(self, elapsed)
	cleanupElapsed = cleanupElapsed + elapsed
	if cleanupElapsed >= MULTIPART_CLEANUP_INTERVAL then
		cleanupElapsed = 0
		cleanupMultipartSpool()
	end
end

AceComm.frame = AceComm.frame or CreateFrame("Frame", "AceComm30Frame")
AceComm.frame:SetScript("OnEvent", OnEvent)
AceComm.frame:SetScript("OnUpdate", OnUpdate)
AceComm.frame:UnregisterAllEvents()
AceComm.frame:RegisterEvent("CHAT_MSG_ADDON")


----------------------------------------
-- Base library stuff
----------------------------------------

local mixins = {
	"RegisterComm",
	"UnregisterComm",
	"UnregisterAllComm",
	"SendCommMessage",
}

-- Embeds AceComm-3.0 into the target object making the functions from the mixins list available on target:..
-- @param target target object to embed AceComm-3.0 in
function AceComm:Embed(target)
	for k, v in pairs(mixins) do
		target[v] = self[v]
	end
	self.embeds[target] = true
	return target
end

function AceComm:OnEmbedDisable(target)
	target:UnregisterAllComm()
end

-- Update embeds
for target, v in pairs(AceComm.embeds) do
	AceComm:Embed(target)
end
