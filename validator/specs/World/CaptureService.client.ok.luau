local CaptureService = game:GetService("CaptureService")

local capturedId = nil
CaptureService:CaptureScreenshot(function(contentId)
	capturedId = contentId
end)
task.wait()
assert(type(capturedId) == "string")

local shared = false
CaptureService:PromptShareCapture(Content.fromUri(capturedId), "launch", function()
	shared = true
end, function() end)

local saved = nil
CaptureService:PromptSaveCapturesToGallery({ Content.fromUri(capturedId) }, function(res)
	saved = res
end)

local status, assetId = CaptureService:CheckUploadCaptureStatusAsync("token")
assert(typeof(status) == "EnumItem" and type(assetId) == "number")

local readStatus = CaptureService:ReadCapturesFromGalleryAsync({}, false)
assert(typeof(readStatus) == "EnumItem")

local screenshotCapture = nil
CaptureService:TakeScreenshotCaptureAsync(function(res, cap)
	assert(res == Enum.ScreenshotCaptureResult.Success)
	screenshotCapture = cap
end, {})
task.wait()
assert(shared == true and saved ~= nil and screenshotCapture ~= nil)
