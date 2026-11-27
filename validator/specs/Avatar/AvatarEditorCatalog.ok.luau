local pages = game:GetService("AvatarEditorService"):SearchCatalogAsync(CatalogSearchParams.new())
while true do
	for _, item in pages:GetCurrentPage() do
		print(item.Name)
	end
	if pages.IsFinished then
		break
	end
	pages:AdvanceToNextPageAsync()
end
