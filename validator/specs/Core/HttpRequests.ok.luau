local HttpService = game:GetService("HttpService")

local body = HttpService:GetAsync("https://example.com/api")
local decoded = HttpService:JSONDecode(body)
assert(type(decoded) == "table", "expected decoded JSON table")

local posted = HttpService:PostAsync("https://example.com/submit", HttpService:JSONEncode({ ok = true }))
assert(type(posted) == "string", "expected string response")

local secret = HttpService:GetSecret("API_KEY"):AddPrefix("Bearer ")
local response = HttpService:RequestAsync({
	Url = "https://example.com/data",
	Method = "GET",
	Headers = { Authorization = secret },
})
assert(response.Success == true and response.StatusCode == 200, "expected 200 OK")

local stream = HttpService:CreateWebStreamClient(Enum.WebStreamClientType.SSE, {
	Url = "https://example.com/events",
})
assert(stream:IsA("WebStreamClient"), "expected WebStreamClient")
