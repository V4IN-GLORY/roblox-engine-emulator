local Haptic = Instance.new("HapticEffect")
Haptic.Type = Enum.HapticEffectType.Custom
Haptic:SetWaveformKeys({ FloatCurveKey.new(0, 0.5), FloatCurveKey.new(100, 0) })
local Keys = Haptic:GetWaveformKeys()
assert(#Keys == 2)
