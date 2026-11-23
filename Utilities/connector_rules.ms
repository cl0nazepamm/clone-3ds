/*
	Quick Connect Nodes — rules file (loaded by connector.ms)

	Format: #(mapProperties, ignoreNormalBumpClasses, rules, standardMaterialSlots)
	  - mapProperties         : #names of texmap properties to read filenames from
	  - ignoreNormalBumpClasses: class values that skip Normal_Bump wrapping (e.g. #(VRayNormalMap))
	  - rules                 : each entry is #(patternsArr, propertiesArr, normalBumpBool)
	                            patterns are strings, properties are #names
	  - standardMaterialSlots : each entry is #(slotIndex, patternsArr)

	Pattern matching is case-insensitive and anchored to end of name.
*/
(
	#(
		-- mapProperties
		#(#fileName, #HDRIMapName),

		-- ignoreNormalBumpClasses
		#(),

		-- rules
		#(
			#( #("Base_Color","BaseColor","Albedo","_Alb","_Col","_C","_D","Diffuse"),
			   #(#diffuseMap,#base_color_map,#base_color_shader,#texmap_diffuse,#texmap_diffuse_color,#diffuseColor_map),
			   false ),

			#( #("Normal","Normals","_Nrm","_N","Normal_Map"),
			   #(#texmap_bump,#bump_map,#norm_map,#normal_shader,#texmap_normal,#normal_map,#bump_input,#geometry_normal_map),
			   true ),

			#( #("Metallic","Metal","Metalness","_Met","_M"),
			   #(#metalness_map,#texmap_metalness,#metalness_shader,#metallic_map,#base_metalness_map),
			   false ),

			#( #("Roughness","_Rgh","_R"),
			   #(#roughness_map,#texmap_roughness,#texmap_reflectionGlossiness,#specular_roughness_shader,#refl_roughness_map,#specular_roughness_map),
			   false ),

			#( #("Ambient_Occlusion","AO","_AO","_Occ","AmbientOcclusion","occlusion"),
			   #(#ao_map,#diffuse_roughness_shader,#ambient_occlusion_map,#texmap_ambient_occlusion,#occlusion_map),
			   false ),

			#( #("Height","Displacement","_Disp","_H"),
			   #(#texmap_displacement,#displacement_map,#displacement_texmap,#displacement_input),
			   false ),

			#( #("Alpha","Transparency","Opacity","Cutout","_Opac"),
			   #(#opacity_map,#cutout_map,#texmap_opacity,#opacity_texmap,#opacity_shader,#opacity_color_map,#geometry_opacity_map),
			   false ),

			#( #("Emissive","Emission","Self_Illumination","SelfIllumination","_Emit"),
			   #(#emit_color,#emit_color_map,#texmap_self_illumination,#emission_color_shader,#self_illumination_map,#emissiveColor_map),
			   false ),

			#( #("SSS","Subsurface"),
			   #(#sss_color_map,#texmap_sss_color,#subsurface_shader,#translucency_map,#ms_color_map,#ss_scatter_color_map,#subsurface_color_map),
			   false ),

			#( #("Clearcoat","Clear_Coat","_Coat"),
			   #(#clearcoat_map,#coat_weight_map),
			   false ),

			#( #("Coat_Roughness","CoatRoughness","Coating_Roughness","CoatingRoughness"),
			   #(#coat_roughness,#texmap_coat_glossiness,#coat_roughness_shader,#clearcoatRoughness_map,#coat_roughness_map),
			   false )
		),

		-- standardMaterialSlots
		#(
			#(1,  #("Ambient_Color","AmbientColor")),
			#(2,  #("Base_Color","BaseColor")),
			#(3,  #("Specular_Color","SpecularColor","Specular")),
			#(4,  #("Specular_Level","SpecularLevel")),
			#(5,  #("Glossiness")),
			#(6,  #("Emissive","Emission","Self_Illumination","SelfIllumination")),
			#(7,  #("Alpha","Transparency","Opacity")),
			#(8,  #("Filter_Color","FilterColor")),
			#(9,  #("Bump")),
			#(10, #("Reflection","Reflections","Reflection_Map","ReflectionMap")),
			#(11, #("Refraction","Refractions","Refraction_Map","RefractionMap")),
			#(12, #("Displacement"))
		)
	)
)
