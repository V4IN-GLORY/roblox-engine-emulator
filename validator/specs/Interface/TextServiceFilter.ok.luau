local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local Chat = game:GetService("Chat")

local Player = Instance.new("Player")
Player.Name = "Alice"
Player.UserId = 42
Player.Parent = Players

local Filtered = TextService:FilterStringAsync("Hello world", Player.UserId)
assert(Filtered:GetNonChatStringForBroadcastAsync() == "Hello world")
assert(Filtered:GetNonChatStringForUserAsync(Player.UserId) == "Hello world")
assert(Filtered:GetChatForUserAsync(Player.UserId) == "Hello world")

local Translated = TextService:FilterAndTranslateStringAsync("Hello", Player.UserId, { "es-es", "fr" })
assert(Translated.SourceText:GetNonChatStringForBroadcastAsync() == "Hello")
assert(Translated:GetTranslationForLocale("es-mx"):GetNonChatStringForBroadcastAsync() == "Hello")
assert(Translated:GetTranslationForLocale("de") == nil)
assert(Translated:GetTranslations().fr ~= nil)

assert(Chat:FilterStringAsync("Hi there", Player, Player) == "Hi there")
assert(Chat:FilterStringForPlayerAsync("Hi there", Player) == "Hi there")
assert(Chat:FilterStringForBroadcast("Hi there", Player) == "Hi there")
assert(Chat:CanUserChatAsync(Player.UserId) == true)
assert(Chat:CanUsersChatAsync(Player.UserId, Player.UserId) == true)

local Generator = Instance.new("TextGenerator")
Generator.Parent = workspace
local Response = Generator:GenerateTextAsync({ UserPrompt = "Say hello", MaxTokens = 32 })
assert(#Response.GeneratedText > 0 and type(Response.ContextToken) == "string")
local Structured = Generator:GenerateTextAsync({ UserPrompt = "Say hello", JsonSchema = "{}" })
assert(game:GetService("HttpService"):JSONDecode(Structured.GeneratedText))
