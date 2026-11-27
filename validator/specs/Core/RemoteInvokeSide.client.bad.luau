local fn = Instance.new("RemoteFunction")
fn.Parent = game:GetService("ReplicatedStorage")
fn.OnServerInvoke = function(player)
	return player.UserId
end
