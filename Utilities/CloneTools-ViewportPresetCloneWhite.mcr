macroScript ViewportPresetCloneWhite
category: "CloneTools"
tooltip: "Apply 'clone_white' Viewport Preset"
buttonText: "VP Clone White"
(
	on execute do
	(
		local vs = NitrousGraphicsManager.GetActiveViewportSetting()

		-- Rendering Level: Basic (Shaded)
		vs.VisualStyleMode = #Shaded

		-- Additional Settings
		vs.OverrideMaterialOption = #FastShader
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
