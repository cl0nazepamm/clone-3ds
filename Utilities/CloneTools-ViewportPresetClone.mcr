macroScript ViewportPresetClone
category: "CloneTools"
tooltip: "Apply 'clone' Viewport Preset"
buttonText: "VP Clone"
(
	on execute do
	(
		local vs = NitrousGraphicsManager.GetActiveViewportSetting()

		-- Rendering Level: Realistic
		vs.VisualStyleMode = #Realistic

		-- Additional Settings
		vs.OverrideMaterialOption = #None
		vs.ShowMaterialOption = #Realistic
		vs.TransparencyEnabled = false

		-- Lighting & Shadows
		vs.ShowHighlightEnabled = true
		vs.LightOption = #DefaultLight
		vs.DefaultLightMode = #TwoLights
		vs.AutoDisplaySelectedLightEnabled = false
		vs.ShadowsEnabled = true
		vs.ShadowIntensity = 1.0
		vs.LightingAndShadowQualityMode = #HardShadows
		vs.UseSimplifiedSkyLight = true
		vs.ProgressiveFadingFactor = 4
		vs.ReflectionEnabled = true

		-- Ambient Occlusion
		vs.AmbientOcclusionEnabled = true
		vs.AmbientOcclusionSamples = 64
		vs.AmbientOcclusionRadius = 30.0
		vs.AmbientOcclusionIntensity = 1.0

		-- Bloom (disabled)
		vs.BloomEnabled = false

		redrawViews()
	)
)
