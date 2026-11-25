local _, ns = ...
local P = ns.Plates
local L = P.L

-- Share strings (3.6, Phase 5 for the UI). Format:
--   !NP:<schema>:<kind>:raw!<base64(cbor(payload))>
-- The prefix names no product, so strings stay valid if the module ever ships on its own.
-- Built only with C_EncodingUtil (SerializeCBOR and Base64), documented on all six clients. A
-- string from a newer schema is refused, never imported quietly. Everything is upgraded through
-- the same chain as saved styles and checked by the part schema.
--
-- Payloads by kind:
--   style   { style = <style>, name = string, author? = string, version = integer }
--   colors  { scheme = string, colors = <profile.colors>, threat = <profile.threat> }
--   when    { when = <profile.when>, actions = <profile.actions> } (P.Actions:SharePayload; format 1
--           strings have no actions, and the reader leaves the player's own rules alone then)
--   profile { profile = <profile table>, styles = { [id] = <global.styles entry> } }

---@class Plates.Share
local Share = {}
P.Share = Share

Share.PREFIX = '!NP:'
Share.ENCODING = 'raw'
Share.KINDS = { style = true, colors = true, when = true, profile = true }

-- Size limits for text from other players. Share bodies are deliberately not compressed because
-- C_EncodingUtil.DecompressString cannot stop at an addon-provided output limit. Base64 has a
-- fixed expansion ratio, so its text can be capped before decoding and the decoded CBOR can be
-- checked again before the reader builds any table from it. A whole profile is far under the cap.
Share.MAX_SERIALIZED = 1000000
Share.MAX_ENCODED = math.ceil(Share.MAX_SERIALIZED / 3) * 4

---@class Plates.ShareDecoded
---@field kind string
---@field schema integer
---@field payload table

local function Codec()
	local E = C_EncodingUtil
	if not (E and E.SerializeCBOR and E.DeserializeCBOR and E.EncodeBase64 and E.DecodeBase64) then
		return nil
	end
	return E
end

---Build a share string.
---@param kind string
---@param payload table
---@return string|nil text
---@return string|nil reason 'kind' | 'unavailable' | 'encode' | 'tooLong'
function Share:Encode(kind, payload)
	if not self.KINDS[kind] then
		return nil, 'kind'
	end
	local E = Codec()
	if not E then
		return nil, 'unavailable'
	end
	local okRaw, raw = pcall(E.SerializeCBOR, payload)
	if not okRaw or type(raw) ~= 'string' then
		return nil, 'encode'
	end
	if #raw > self.MAX_SERIALIZED then
		return nil, 'tooLong'
	end
	local okText, body = pcall(E.EncodeBase64, raw)
	if not okText or type(body) ~= 'string' then
		return nil, 'encode'
	end
	if #body > self.MAX_ENCODED then
		return nil, 'tooLong'
	end
	return self.PREFIX .. P.Styles.Schema.CURRENT .. ':' .. kind .. ':' .. self.ENCODING .. '!' .. body
end

local function Clean(text)
	if type(text) ~= 'string' then
		return ''
	end
	local manager = LibAT and LibAT.ProfileManager
	if manager and manager.StripExportHeaders then
		local ok, stripped = pcall(manager.StripExportHeaders, text)
		if ok and type(stripped) == 'string' then
			text = stripped
		end
	end
	text = string.gsub(text, '^%s+', '')
	text = string.gsub(text, '%s+$', '')
	return text
end

---Read a share string. Never trusts the payload; callers validate it for their kind.
---@param text string
---@return Plates.ShareDecoded|nil decoded
---@return string|nil reason 'format' | 'newer' | 'kind' | 'unavailable' | 'decode' | 'tooLong'
function Share:Decode(text)
	text = Clean(text)
	local schema, kind, encoding, body = string.match(text, '^!NP:(%d+):(%a+):(%a+)!(.+)$')
	if not schema then
		return nil, 'format'
	end
	schema = tonumber(schema)
	if schema > P.Styles.Schema.CURRENT then
		return nil, 'newer'
	end
	if not self.KINDS[kind] then
		return nil, 'kind'
	end
	-- Unmarked legacy bodies are compressed. Never pass one to the unbounded native decompressor.
	if encoding ~= self.ENCODING then
		return nil, 'format'
	end
	local E = Codec()
	if not E then
		return nil, 'unavailable'
	end
	body = string.gsub(body, '%s', '')
	-- Base64 writes 4 characters for every 3 bytes
	if #body > self.MAX_ENCODED then
		return nil, 'tooLong'
	end
	local padding = string.match(body, '=+$')
	if padding and #padding > 2 then
		return nil, 'decode'
	end
	local decodedLimit = math.ceil(#body / 4) * 3 - (padding and #padding or 0)
	if decodedLimit > self.MAX_SERIALIZED then
		return nil, 'tooLong'
	end
	local okRaw, raw = pcall(E.DecodeBase64, body)
	if not okRaw or type(raw) ~= 'string' then
		return nil, 'decode'
	end
	if #raw > self.MAX_SERIALIZED then
		return nil, 'tooLong'
	end
	local okPayload, payload = pcall(E.DeserializeCBOR, raw)
	if not okPayload or type(payload) ~= 'table' then
		return nil, 'decode'
	end
	return { kind = kind, schema = schema, payload = payload }
end

---Player-facing text for a decode or import failure.
---@param reason string
---@return string
function Share:ReasonText(reason)
	if reason == 'newer' then
		return string.format(L['This style needs a newer version of %s.'], P:HostName())
	elseif reason == 'unavailable' then
		return L['This version of WoW cannot read shared styles.']
	elseif reason == 'kind' then
		return L['This text is not something this page can use.']
	elseif reason == 'cycle' then
		return L['This style has parts that point at each other in a loop.']
	elseif reason == 'tooLong' then
		return L['That text is too long to be a nameplate share string.']
	end
	return L['This text is not a nameplate style.']
end

---@class Plates.ImportPreview
---@field kind string
---@field style? table Cleaned, upgraded style (kind 'style')
---@field name? string
---@field author? string
---@field version? integer
---@field report Plates.ValidationReport
---@field updateOf? string Saved style id this string updates
---@field isNewer? boolean The string carries a newer version than the saved copy

---Check an already decoded style string without saving anything. Callers that have read the text
---with Decode use this, so a string is never unpacked twice.
---@param decoded Plates.ShareDecoded
---@return Plates.ImportPreview|nil preview
---@return string|nil reason
function Share:InspectDecoded(decoded)
	if type(decoded) ~= 'table' or decoded.kind ~= 'style' then
		return nil, 'kind'
	end
	local payload = decoded.payload
	local Schema = P.Styles.Schema
	local upgraded, why = Schema:Upgrade(type(payload.style) == 'table' and payload.style or {})
	if not upgraded then
		return nil, why
	end
	local cleaned, report, failed = Schema:ValidateStyle(upgraded)
	if not cleaned then
		return nil, failed
	end
	local preview = {
		kind = 'style',
		style = cleaned,
		name = type(payload.name) == 'string' and string.sub(payload.name, 1, 48) or cleaned.name,
		author = type(payload.author) == 'string' and string.sub(payload.author, 1, 48) or nil,
		version = tonumber(payload.version) or cleaned.version or 1,
		report = report,
	}
	local saved = P.db and P.db.global.styles or {}
	for id, entry in pairs(saved) do
		local source = entry.source
		if source and source.kind == 'import' and source.styleId == cleaned.id and source.author == preview.author then
			preview.updateOf = id
			preview.isNewer = (tonumber(source.version) or 0) < preview.version
		end
	end
	return preview
end

---Decode and check a style string without saving anything (for the live preview card).
---@param text string
---@return Plates.ImportPreview|nil preview
---@return string|nil reason
function Share:InspectStyle(text)
	local decoded, reason = self:Decode(text)
	if not decoded then
		return nil, reason
	end
	return self:InspectDecoded(decoded)
end

---Import a style string. mode 'new' adds a style (never overwrites); 'update' replaces the base
---of the saved copy it updates and keeps the player's changes.
---@param text string
---@param name? string
---@param mode? 'new'|'update'
---@return string|nil styleId
---@return string|nil reason
function Share:ImportStyle(text, name, mode)
	local preview, reason = self:InspectStyle(text)
	if not preview then
		return nil, reason
	end
	local source = { kind = 'import', author = preview.author, version = preview.version, styleId = preview.style.id }
	local Registry = P.Styles.Registry
	if mode == 'update' and preview.updateOf then
		Registry:UpdateSaved(preview.updateOf, preview.style, source)
		return preview.updateOf
	end
	return Registry:Save(preview.style, name or preview.name or L['Imported style'], source)
end

---Share string for a style: the base with the player's changes baked in.
---@param styleId string
---@param author? string
---@return string|nil text
---@return string|nil reason
function Share:ExportStyle(styleId, author)
	local style = P.Styles.Merge:Bake(styleId)
	if not style then
		return nil, 'missing'
	end
	return self:Encode('style', { style = style, name = style.name, author = author, version = style.version or 1 })
end
