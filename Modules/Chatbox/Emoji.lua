---@class SUI
local SUI = SUI
---@class SUI.Module.Chatbox
local module = SUI:GetModule('Chatbox')

local EMOJI_PATH = 'Interface\\AddOns\\SpartanUI\\images\\chatbox\\emojis\\'
local EMOJI_SIZE = ':16:16'

local strtrim = strtrim
local gmatch = string.gmatch
local gsub = string.gsub
local strmatch = string.match
local strfind = string.find
local strsub = string.sub
local strlen = string.len

-- Emoji registry: pattern key -> texture markup (keys are Lua patterns)
module.Smileys = {}

-- Utility: escape Lua pattern special characters in a string
local function EscapeString(str)
	if not str or str == '' then
		return nil
	end
	return str:gsub('([%(%)%.%%%+%-%*%?%[%]%^%$])', '%%%1')
end

-- ElvUI-compatible: keys are stored as Lua patterns directly
local function AddSmiley(key, textureName)
	-- Reject keys that contain ':%%' (pre-escaped patterns passed by mistake)
	if key and type(key) == 'string' and not strfind(key, ':%%', 1, true) then
		module.Smileys[key] = ('|T%s%s%s|t'):format(EMOJI_PATH, textureName, EMOJI_SIZE)
	end
end

function module:DefaultSmileys()
	wipe(module.Smileys)

	-- Named shortcodes (ElvUI-compatible, no special chars so stored as-is)
	AddSmiley(':angry:', 'Angry.png')
	AddSmiley(':blush:', 'Blush.png')
	AddSmiley(':broken_heart:', 'BrokenHeart.png')
	AddSmiley(':call_me:', 'CallMe.png')
	AddSmiley(':cry:', 'Cry.png')
	AddSmiley(':facepalm:', 'Facepalm.png')
	AddSmiley(':grin:', 'Grin.png')
	AddSmiley(':heart:', 'Heart.png')
	AddSmiley(':heart_eyes:', 'HeartEyes.png')
	AddSmiley(':joy:', 'Joy.png')
	AddSmiley(':kappa:', 'Kappa.png')
	AddSmiley(':middle_finger:', 'MiddleFinger.png')
	AddSmiley(':murloc:', 'Smile.png')
	AddSmiley(':ok_hand:', 'OkHand.png')
	AddSmiley(':open_mouth:', 'OpenMouth.png')
	AddSmiley(':poop:', 'Poop.png')
	AddSmiley(':rage:', 'Rage.png')
	AddSmiley(':sadkitty:', 'SadKitty.png')
	AddSmiley(':scream:', 'Scream.png')
	AddSmiley(':scream_cat:', 'ScreamCat.png')
	AddSmiley(':slight_frown:', 'SlightFrown.png')
	AddSmiley(':slight_smile:', 'SlightSmile.png')
	AddSmiley(':smile:', 'Smile.png')
	AddSmiley(':smirk:', 'Smirk.png')
	AddSmiley(':sob:', 'Sob.png')
	AddSmiley(':sunglasses:', 'Sunglasses.png')
	AddSmiley(':thinking:', 'Thinking.png')
	AddSmiley(':thumbs_up:', 'ThumbsUp.png')
	AddSmiley(':semi_colon:', 'SemiColon.png')
	AddSmiley(':wink:', 'Wink.png')
	AddSmiley(':zzz:', 'ZZZ.png')
	AddSmiley(':stuck_out_tongue:', 'StuckOutTongue.png')
	AddSmiley(':stuck_out_tongue_closed_eyes:', 'StuckOutTongueClosedEyes.png')
	AddSmiley(':meaw:', 'Meaw.png')

	-- SUI extras
	AddSmiley(':thumbs_down:', 'ThumbsDown.png')
	AddSmiley(':wave:', 'Wave.png')
	AddSmiley(':party:', 'PartyPopper.png')
	AddSmiley(':fire:', 'Fire.png')
	AddSmiley(':clap:', 'Clap.png')
	AddSmiley(':pray:', 'Pray.png')
	AddSmiley(':skull:', 'Skull.png')

	-- Legacy ASCII shortcuts (pre-escaped as Lua patterns, matching ElvUI)
	AddSmiley(':%-@', 'Angry.png')
	AddSmiley(':@', 'Angry.png')
	AddSmiley('>:%(', 'Angry.png')
	AddSmiley(':%-%)', 'SlightSmile.png')
	AddSmiley(':%)', 'SlightSmile.png')
	AddSmiley(':D', 'Grin.png')
	AddSmiley(':%-D', 'Grin.png')
	AddSmiley(';%-D', 'Grin.png')
	AddSmiley(';D', 'Grin.png')
	AddSmiley('=D', 'Grin.png')
	AddSmiley('xD', 'Grin.png')
	AddSmiley('XD', 'Grin.png')
	AddSmiley(':%-%(', 'SlightFrown.png')
	AddSmiley(':%(', 'SlightFrown.png')
	AddSmiley(':o', 'OpenMouth.png')
	AddSmiley(':%-o', 'OpenMouth.png')
	AddSmiley(':%-O', 'OpenMouth.png')
	AddSmiley(':O', 'OpenMouth.png')
	AddSmiley(':%-0', 'OpenMouth.png')
	AddSmiley(':P', 'StuckOutTongue.png')
	AddSmiley(':%-P', 'StuckOutTongue.png')
	AddSmiley(':p', 'StuckOutTongue.png')
	AddSmiley(':%-p', 'StuckOutTongue.png')
	AddSmiley('=P', 'StuckOutTongue.png')
	AddSmiley('=p', 'StuckOutTongue.png')
	AddSmiley(';%-p', 'StuckOutTongueClosedEyes.png')
	AddSmiley(';p', 'StuckOutTongueClosedEyes.png')
	AddSmiley(';P', 'StuckOutTongueClosedEyes.png')
	AddSmiley(';%-P', 'StuckOutTongueClosedEyes.png')
	AddSmiley(';%-%)', 'Wink.png')
	AddSmiley(';%)', 'Wink.png')
	AddSmiley(':S', 'SlightFrown.png')
	AddSmiley(':%-S', 'SlightFrown.png')
	AddSmiley(':,%-(', 'Cry.png')
	AddSmiley(':,%(', 'Cry.png')
	AddSmiley(":'%(", 'Cry.png')
	AddSmiley(":'%-%(", 'Cry.png')
	AddSmiley('<3', 'Heart.png')
	AddSmiley('</3', 'BrokenHeart.png')
	AddSmiley(':%+1:', 'ThumbsUp.png')
	AddSmiley('8%-%)', 'Sunglasses.png')
	AddSmiley('8%)', 'Sunglasses.png')
	AddSmiley('XP', 'StuckOutTongueClosedEyes.png')
	AddSmiley('D:<', 'Rage.png')
end

----------------------------------------------------------------------------------------------------
-- Insert emoji into chat messages (ElvUI-compatible approach)
----------------------------------------------------------------------------------------------------

-- Replace emoji in a text segment (no hyperlinks in this segment)
local function InsertEmotions(msg)
	for word in gmatch(msg, '%s-%S+%s*') do
		word = strtrim(word)
		local pattern = EscapeString(word)
		local emoji = module.Smileys[pattern]
		if emoji and strmatch(msg, '[%s%p]-' .. pattern .. '[%s%p]*') then
			msg = gsub(msg, '([%s%p]-)' .. pattern .. '([%s%p]*)', '%1' .. emoji .. '%2')
		end
	end
	return msg
end

-- Process message, skipping hyperlink regions
local function GetSmileyReplacementText(msg)
	if not msg or strfind(msg, '/run') or strfind(msg, '/dump') or strfind(msg, '/script') then
		return msg
	end

	local outstr = ''
	local origlen = strlen(msg)
	local startpos = 1

	while startpos <= origlen do
		local pos = strfind(msg, '|H', startpos, true)
		if pos then
			-- Process text before the hyperlink
			if pos > startpos then
				outstr = outstr .. InsertEmotions(strsub(msg, startpos, pos - 1))
			end
			-- Find the end of the hyperlink (|H...|h...|h)
			local _, endpos = strfind(msg, '|h.-|h', pos + 2)
			if endpos then
				outstr = outstr .. strsub(msg, pos, endpos)
				startpos = endpos + 1
			else
				-- Malformed hyperlink, just append the rest
				outstr = outstr .. strsub(msg, pos)
				startpos = origlen + 1
			end
		else
			-- No more hyperlinks, process remaining text
			outstr = outstr .. InsertEmotions(strsub(msg, startpos))
			startpos = origlen + 1
		end
	end

	return outstr
end

----------------------------------------------------------------------------------------------------
-- Chat filter to process emoji in messages
----------------------------------------------------------------------------------------------------

local emojiEvents = {
	'CHAT_MSG_SAY',
	'CHAT_MSG_YELL',
	'CHAT_MSG_GUILD',
	'CHAT_MSG_OFFICER',
	'CHAT_MSG_PARTY',
	'CHAT_MSG_PARTY_LEADER',
	'CHAT_MSG_RAID',
	'CHAT_MSG_RAID_LEADER',
	'CHAT_MSG_INSTANCE_CHAT',
	'CHAT_MSG_INSTANCE_CHAT_LEADER',
	'CHAT_MSG_WHISPER',
	'CHAT_MSG_WHISPER_INFORM',
	'CHAT_MSG_BN_WHISPER',
	'CHAT_MSG_BN_WHISPER_INFORM',
	'CHAT_MSG_BN_CONVERSATION',
	'CHAT_MSG_CHANNEL',
	'CHAT_MSG_COMMUNITIES_CHANNEL',
	'CHAT_MSG_EMOTE',
	'CHAT_MSG_TEXT_EMOTE',
}

local function emojiFilter(chatFrame, event, msg, ...)
	if not module.CurrentSettings or not module.CurrentSettings.emoji or not module.CurrentSettings.emoji.enabled then
		return
	end
	if not SUI.BlizzAPI.canaccessvalue(msg) then
		return
	end
	local newMsg = GetSmileyReplacementText(msg)
	if newMsg ~= msg then
		return false, newMsg, ...
	end
end

function module:SetupEmoji()
	if SUI:IsModuleDisabled(module) then
		return
	end

	module:DefaultSmileys()

	local addFilter = (_G.ChatFrameUtil and _G.ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
	for _, event in ipairs(emojiEvents) do
		addFilter(event, emojiFilter)
	end
end
