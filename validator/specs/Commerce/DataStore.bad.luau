local DataStoreService = game:GetService("DataStoreService")
-- Options must be a DataStoreOptions instance, not a Folder
DataStoreService:GetDataStore("PlayerData", "global", Instance.new("Folder"))
