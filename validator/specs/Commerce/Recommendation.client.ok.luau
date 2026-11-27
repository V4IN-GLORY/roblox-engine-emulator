local RecommendationService = game:GetService("RecommendationService")
RecommendationService:LogActionEvent(
	Enum.RecommendationActionType.Play,
	"00000000-0000-4000-8000-000000000001",
	"trace_1"
)
RecommendationService:LogImpressionEvent(
	Enum.RecommendationImpressionType.View,
	"00000000-0000-4000-8000-000000000001",
	"trace_1"
)
