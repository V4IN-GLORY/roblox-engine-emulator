local GroupService = game:GetService("GroupService")
local Pages = GroupService:GetEnemiesAsync(1)
-- Advancing past the last page must error
Pages:AdvanceToNextPageAsync()
