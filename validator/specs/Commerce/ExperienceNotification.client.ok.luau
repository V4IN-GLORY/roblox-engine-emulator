local ExperienceNotificationService = game:GetService("ExperienceNotificationService")
if ExperienceNotificationService:CanPromptOptInAsync() then
	ExperienceNotificationService:PromptOptIn()
end
