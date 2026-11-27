local ids = {}
for id = 1, 101 do
	table.insert(ids, id)
end
game:GetService("AvatarEditorService"):GetBatchItemDetailsAsync(ids, Enum.AvatarItemType.Asset)
