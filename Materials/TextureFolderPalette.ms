/*
    TextureFolderPalette
    Loads image files from a folder into Compact Material Editor slots.

    Modes:
    - OpenPBR Preview: creates one OpenPBR-first preview material per image,
      wires the image to base color, and sets specular color to black.
    - Raw Bitmaps: places Bitmaptexture maps directly into Material Editor slots.
    - Grouped PBR: groups texture sets by filename tokens, creates one fully
      wired PBR material per set, and sets specular color to white.
    - MaterialX renderer mode: builds OpenPBR materials using MaterialX OSL
      tiledimage/normalmap nodes for the texture graph.

    Listener usage:
    fileIn @"C:\path\to\TextureFolderPalette.ms"
    CloneTextureFolderPalette.loadFolder @"C:\textures" mode:#material
    CloneTextureFolderPalette.loadFolder @"C:\textures" mode:#bitmap
    CloneTextureFolderPalette.loadFolder @"C:\textures" mode:#pbr recursive:true renderer:#openpbr
    CloneTextureFolderPalette.loadFolder @"C:\textures" mode:#pbr recursive:true renderer:#openpbr includeDisplacement:false
    CloneTextureFolderPalette.loadFolder @"C:\textures" mode:#pbr recursive:true renderer:#vray
    CloneTextureFolderPalette.loadFolder @"C:\textures" mode:#pbr recursive:true renderer:#materialx
    CloneTextureFolderPalette.loadFolder @"C:\textures" mode:#pbr recursive:true renderer:#octaneStandard
    CloneTextureFolderPalette.loadFolder @"C:\textures" mode:#pbr recursive:true renderer:#octanePbr
    CloneTextureFolderPalette.loadFolder @"C:\textures" mode:#pbr recursive:true renderer:#octaneUniversal

    Octane variants build with Image_MTX, Channel_picker (ORM split), Multiply_MTX
    (diffuse x AO), Invert_MTX (gloss -> roughness), and flip every assigned slot's
    *_input_type to 2 so the texture actually drives the channel.
*/

global CloneTextureFolderPalette

struct CloneTextureFolderPaletteStruct
(
    imageExtensions = #(".png", ".jpg", ".jpeg", ".tif", ".tiff", ".exr", ".tga", ".hdr", ".bmp", ".dds", ".tx"),
    commonVariantTokens = #("2k", "4k", "8k", "16k", "1k", "512", "1024", "2048", "4096", "8192", "png", "jpg", "jpeg", "tif", "tiff", "exr", "tga", "hdr", "bmp", "dds", "tx"),
    colorChannels = #(#diffuse, #specular, #emission),
    channelPatterns = #(
        #(#diffuse, #("_basecolor", "_base_color", "basecolor", "base color", "_albedo", "albedo", "_diffuse", "diffuse", "_diff", "diff", "_color", "color", "_col", "col", "_rgb", "rgb", "_clr", "clr", "_alb", "alb", "_dif", "dif", "_d")),
        #(#orm, #("_occlusionroughnessmetallic", "occlusion roughness metallic", "_ambientocclusionroughnessmetallic", "ambient occlusion roughness metallic", "_orm", "orm", "_arm", "arm")),
        #(#ao, #("_ambientocclusion", "ambient occlusion", "_ambient_occlusion", "_occlusion", "occlusion", "_amb_occ", "amb occ", "_ao", "ao")),
        #(#roughness, #("_roughness", "roughness", "_rough", "rough", "_rgh", "rgh", "_r")),
        #(#glossiness, #("_glossiness", "glossiness", "_smoothness", "smoothness", "_gloss", "gloss", "_smooth", "smooth", "_gls", "gls", "_g")),
        #(#metallic, #("_metallic", "metallic", "_metalness", "metalness", "_metal", "metal", "_met", "met", "_mtl", "mtl", "_m")),
        #(#normal, #("_normal_opengl", "normal opengl", "_normal_open_gl", "normal open gl", "_normal_directx", "normal directx", "_normal_direct_x", "normal direct x", "_normalgl", "normalgl", "normal gl", "_normaldx", "normaldx", "normal dx", "_normal", "normal", "_nrm", "nrm", "_nor", "nor", "_n")),
        #(#displacement, #("_displacement", "displacement", "_displace", "displace", "_height", "height", "_depth", "depth", "_hght", "hght", "_hgt", "hgt", "_disp", "disp", "_dis", "dis", "_h")),
        #(#bump, #("_bump", "bump", "_bmp", "bmp", "_b")),
        #(#opacity, #("_opacity", "opacity", "_alpha", "alpha", "_alphamasked", "alphamasked", "_opa", "opa", "_alph", "alph", "_o")),
        #(#emission, #("_emissive", "emissive", "_emission", "emission", "_emisive", "emisive", "_illumination", "illumination", "_illum", "illum", "_emit", "emit", "_light", "light", "_emi", "emi", "_ill", "ill", "_lght", "lght", "_e")),
        #(#translucency, #("_translucency", "translucency", "_translucent", "translucent", "_transmission", "transmission", "_transparency", "transparency", "_transparancy", "transparancy", "_trans", "trans", "_trns", "trns", "_t")),
        #(#ior, #("_ior", "ior", "_i")),
        #(#specular, #("_specular", "specular", "_spec", "spec", "_spc", "spc", "_reflection", "reflection", "_reflect", "reflect", "_refl", "refl", "_ref", "ref", "_s"))
    ),

    fn normalizedFolder folder =
    (
        local f = folder as string
        if f.count == 0 then return ""
        f = trimRight f "\\/"
        f
    ),

    fn isImageFile filepath =
    (
        local ext = toLower (getFilenameType filepath)
        findItem imageExtensions ext > 0
    ),

    fn appendFolderImages folder recursive:false outFiles:#() =
    (
        local root = normalizedFolder folder
        if root.count == 0 then return outFiles

        local files = getFiles (root + "\\*.*")
        for f in files where isImageFile f do append outFiles f

        if recursive do
        (
            local dirs = getDirectories (root + "\\*")
            for d in dirs do appendFolderImages d recursive:true outFiles:outFiles
        )

        outFiles
    ),

    fn getImageFiles folder recursive:false =
    (
        local files = appendFolderImages folder recursive:recursive outFiles:#()
        sort files
        files
    ),

    fn createOpenPbrPreferred matName =
    (
        local m = undefined
        try (m = OpenPBRMaterial name:matName) catch ()
        if m == undefined do try (m = OpenPBR_Material name:matName) catch ()
        if m == undefined do try (m = OpenPBR_Mtl name:matName) catch ()
        if m == undefined do try (m = PhysicalMaterial name:matName) catch ()
        if m == undefined do throw "OpenPBRMaterial/OpenPBR_Material/OpenPBR_Mtl/PhysicalMaterial are unavailable"
        m
    ),

    fn isOctaneRenderer renderer =
    (
        renderer == #octaneStandard or renderer == #octanePbr or renderer == #octaneUniversal
    ),

    fn createRendererMaterial renderer matName =
    (
        case renderer of
        (
            #physical: (PhysicalMaterial name:matName)
            #arnold:
            (
                local m = undefined
                try (m = ai_standard_surface name:matName) catch ()
                if m == undefined do throw "Arnold ai_standard_surface is unavailable in this 3ds Max session."
                m
            )
            #redshift:
            (
                local m = undefined
                try (m = RS_Standard_Material name:matName) catch ()
                if m == undefined do throw "Redshift RS_Standard_Material is unavailable in this 3ds Max session."
                m
            )
            #vray:
            (
                local m = undefined
                try (m = VRayMtl name:matName) catch ()
                if m == undefined do throw "V-Ray VRayMtl is unavailable in this 3ds Max session."
                m
            )
            #materialx:
            (
                createOpenPbrPreferred matName
            )
            #octaneStandard:
            (
                local m = undefined
                try (m = Std_Surface_Mtl name:matName) catch ()
                if m == undefined do throw "Octane Std_Surface_Mtl is unavailable in this 3ds Max session."
                m
            )
            #octanePbr:
            (
                local m = undefined
                try (m = Open_PBR_Surf__Mtl name:matName) catch ()
                if m == undefined do throw "Octane Open_PBR_Surf__Mtl is unavailable in this 3ds Max session."
                m
            )
            #octaneUniversal:
            (
                local m = undefined
                try (m = Universal_material name:matName) catch ()
                if m == undefined do throw "Octane Universal_material is unavailable in this 3ds Max session."
                m
            )
            default: (createOpenPbrPreferred matName)
        )
    ),

    fn rendererLabel renderer =
    (
        case renderer of
        (
            #physical: "PhysicalMaterial"
            #arnold: "Arnold ai_standard_surface"
            #redshift: "Redshift RS_Standard_Material"
            #vray: "V-Ray VRayMtl"
            #materialx: "OpenPBR + MaterialX OSL"
            #octaneStandard: "Octane Std Surface (Std_Surface_Mtl)"
            #octanePbr: "Octane Open PBR Surface (Open_PBR_Surf__Mtl)"
            #octaneUniversal: "Octane Universal (Universal_material)"
            default: "OpenPBR-first"
        )
    ),

    fn rendererFromSelection index =
    (
        case index of
        (
            2: #physical
            3: #arnold
            4: #redshift
            5: #vray
            6: #materialx
            7: #octaneStandard
            8: #octanePbr
            9: #octaneUniversal
            default: #openpbr
        )
    ),

    fn setFirstMap target propNames tex =
    (
        for propName in propNames do
        (
            try
            (
                setProperty target (propName as name) tex
                return propName
            )
            catch ()
        )
        undefined
    ),

    fn setFirstValue target propNames value =
    (
        for propName in propNames do
        (
            try
            (
                setProperty target (propName as name) value
                return propName
            )
            catch ()
        )
        undefined
    ),

    fn enableMapSlot target slotName =
    (
        if slotName != undefined do
        (
            try (setProperty target ((slotName + "_on") as name) true) catch ()
            try (setProperty target ((slotName + "_enable") as name) true) catch ()
            -- Octane _tex slots ignore the texture until *_input_type is flipped to 2 (texture mode).
            try
            (
                local s = slotName as string
                if matchPattern s pattern:"*_tex" do
                (
                    local prefix = substring s 1 (s.count - 4)
                    setProperty target ((prefix + "_input_type") as name) 2
                )
            )
            catch ()
        )
    ),

    fn putInMaterialEditor item slotIndex =
    (
        try (medit.PutMtlToMtlEditor item slotIndex) catch (meditMaterials[slotIndex] = item)
        try (medit.SetActiveMtlSlot slotIndex true) catch (activeMeditSlot = slotIndex)
        item
    ),

    fn makeBitmap filepath =
    (
        local stem = getFilenameFile filepath
        Bitmaptexture name:stem filename:filepath
    ),

    fn materialXOslRoot =
    (
        local roots = #(
            "C:\\ProgramData\\Autodesk\\ApplicationPlugins\\USD for 3ds Max 2027\\Contents\\MaterialX_plugin\\Contents\\OSL\\MaterialX",
            "C:\\ProgramData\\Autodesk\\ApplicationPlugins\\USD for 3ds Max 2026\\Contents\\MaterialX_plugin\\Contents\\OSL\\MaterialX",
            "C:\\ProgramData\\Autodesk\\ApplicationPlugins\\USD for 3ds Max 2025\\Contents\\MaterialX_plugin\\Contents\\OSL\\MaterialX"
        )

        for root in roots where doesFileExist (root + "\\tiledimage_color3.osl") do return root
        throw "USD MaterialX OSL nodes are unavailable. Expected tiledimage_color3.osl under ProgramData Autodesk ApplicationPlugins."
    ),

    fn materialXOslPath fileName =
    (
        local path = (materialXOslRoot()) + "\\" + fileName
        if not (doesFileExist path) do throw ("MaterialX OSL file is unavailable: " + path)
        path
    ),

    fn makeMaterialXOslMap fileName nodeName =
    (
        local m = OSLMap()
        m.name = nodeName
        m.OSLPath = materialXOslPath fileName
        m.OSLAutoUpdate = true
        m
    ),

    fn makeMaterialXTiledImage filepath channel =
    (
        local stem = getFilenameFile filepath
        local isColor = (findItem colorChannels channel > 0)
        local fileName = case channel of
        (
            #normal: "tiledimage_vector3.osl"
            default: (if isColor then "tiledimage_color3.osl" else "tiledimage_float.osl")
        )
        local tex = makeMaterialXOslMap fileName stem
        tex.file = filepath
        tex.file_colorspace = if isColor then "srgb_texture" else ""
        if channel == #normal do tex.default1 = [0.5, 0.5, 1.0]
        tex
    ),

    fn makeRendererBitmap filepath channel renderer =
    (
        local stem = getFilenameFile filepath
        if renderer == #materialx then
        (
            makeMaterialXTiledImage filepath channel
        )
        else if renderer == #arnold then
        (
            local colorSpace = if findItem colorChannels channel > 0 then "sRGB" else "Raw"
            local img = undefined
            try (img = ai_image name:stem filename:filepath color_space:colorSpace) catch ()
            if img != undefined then img else makeBitmap filepath
        )
        else if isOctaneRenderer renderer then
        (
            local img = undefined
            try
            (
                img = Image_MTX()
                img.name = stem
                img.filename = filepath
                -- Leave colorSpace at the Octane built-in default (_OctaneBuildIn_LINEAR_sRGB).
                -- Any other string triggers OCIO lookup and errors when no OCIO config is loaded.
                -- Octane's material slot semantics handle data vs color textures correctly.
            )
            catch ()
            if img != undefined then img else makeBitmap filepath
        )
        else makeBitmap filepath
    ),

    fn makePreviewMaterial filepath materialPrefix:"tex_" =
    (
        local stem = getFilenameFile filepath
        local tex = makeBitmap filepath
        local mat = createOpenPbrPreferred (materialPrefix + stem)
        local baseSlot = setFirstMap mat #("base_color_map", "baseColor_map", "basecolor_map", "base_map", "diffuse_map") tex
        if baseSlot == undefined do try (mat.base_color_map = tex) catch ()
        setFirstValue mat #("specular_color", "specularColor", "specular", "refl_color") (color 0 0 0)
        mat
    ),

    fn isAlphaNumeric ch =
    (
        findString "abcdefghijklmnopqrstuvwxyz0123456789" ch != undefined
    ),

    fn makeTokens value =
    (
        local s = toLower (value as string)
        local tokens = #()
        local token = ""
        for i = 1 to s.count do
        (
            local ch = s[i]
            if isAlphaNumeric ch then
            (
                token += ch
            )
            else if token.count > 0 do
            (
                append tokens token
                token = ""
            )
        )
        if token.count > 0 do append tokens token
        tokens
    ),

    fn joinTokens tokens sep:"" =
    (
        local out = ""
        for i = 1 to tokens.count do
        (
            if i > 1 do out += sep
            out += tokens[i]
        )
        out
    ),

    fn endsWith value suffix =
    (
        if suffix.count > value.count then false else (substring value (value.count - suffix.count + 1) suffix.count) == suffix
    ),

    fn patternMatchScore stem alias tokens =
    (
        local patternTokens = makeTokens alias
        if patternTokens.count == 0 then return undefined

        local patternCompact = joinTokens patternTokens sep:""
        local tokenCount = patternTokens.count
        local maxStart = tokens.count - tokenCount + 1

        if maxStart >= 1 do
        (
            for start = 1 to maxStart do
            (
                local ok = true
                for j = 1 to tokenCount while ok do
                (
                    if tokens[start + j - 1] != patternTokens[j] do ok = false
                )
                if ok do
                (
                    local atEnd = (start + tokenCount - 1) == tokens.count
                    local singleLetterPenalty = if patternCompact.count == 1 then 80 else 0
                    local score = (tokenCount * 100) + patternCompact.count + (if atEnd then 25 else 0) - singleLetterPenalty
                    return #(score, start, start + tokenCount - 1)
                )
            )
        )

        local stemCompact = joinTokens tokens sep:""
        if patternCompact.count >= 4 and endsWith stemCompact patternCompact do return #(patternCompact.count, 0, 0)
        undefined
    ),

    fn detectTextureChannel filepath =
    (
        local stem = getFilenameFile filepath
        local tokens = makeTokens stem
        local bestScore = -999999
        local bestPriority = -999999
        local bestChannel = undefined
        local bestAlias = undefined
        local bestStart = 0
        local bestEnd = 0

        for p = 1 to channelPatterns.count do
        (
            local channel = channelPatterns[p][1]
            local aliases = channelPatterns[p][2]
            for alias in aliases do
            (
                local scored = patternMatchScore stem alias tokens
                if scored != undefined do
                (
                    local score = scored[1]
                    local priority = -p
                    if score > bestScore or (score == bestScore and priority > bestPriority) do
                    (
                        bestScore = score
                        bestPriority = priority
                        bestChannel = channel
                        bestAlias = alias
                        bestStart = scored[2]
                        bestEnd = scored[3]
                    )
                )
            )
        )

        if bestChannel == undefined then return undefined

        local keyTokens = #()
        if bestStart > 0 then
        (
            for i = 1 to tokens.count do
            (
                if i < bestStart or i > bestEnd do
                (
                    if findItem commonVariantTokens tokens[i] == 0 do append keyTokens tokens[i]
                )
            )
        )
        else
        (
            for t in tokens where findItem commonVariantTokens t == 0 do append keyTokens t
        )

        local materialKey = joinTokens keyTokens sep:"_"
        if materialKey.count == 0 do materialKey = toLower stem
        #(bestChannel, materialKey, bestAlias)
    ),

    fn findGroup groups key =
    (
        for g in groups where g[1] == key do return g
        undefined
    ),

    fn channelExists channels channel =
    (
        for p in channels where p[1] == channel do return true
        false
    ),

    fn addChannel channels channel filepath =
    (
        if channelExists channels channel then false else
        (
            append channels #(channel, filepath)
            true
        )
    ),

    fn getChannelFile channels channel =
    (
        for p in channels where p[1] == channel do return p[2]
        undefined
    ),

    fn setMapPair mapPairs channel tex =
    (
        for p in mapPairs where p[1] == channel do
        (
            p[2] = tex
            return tex
        )
        append mapPairs #(channel, tex)
        tex
    ),

    fn getMapPair mapPairs channel =
    (
        for p in mapPairs where p[1] == channel do return p[2]
        undefined
    ),

    fn groupTextureFiles files =
    (
        local groups = #()
        local unmatched = #()
        local duplicates = #()

        for f in files do
        (
            local detected = detectTextureChannel f
            if detected == undefined then
            (
                append unmatched f
            )
            else
            (
                local channel = detected[1]
                local key = detected[2]
                local group = findGroup groups key
                if group == undefined do
                (
                    group = #(key, #())
                    append groups group
                )
                if not (addChannel group[2] channel f) do append duplicates f
            )
        )

        #(groups, unmatched, duplicates)
    ),

    fn slotCandidates renderer channel =
    (
        case renderer of
        (
            #physical:
            (
                case channel of
                (
                    #diffuse: #("base_color_map")
                    #ao: #("base_color_map")
                    #roughness: #("roughness_map")
                    #glossiness: #("roughness_map")
                    #metallic: #("metalness_map")
                    #normal: #("bump_map")
                    #bump: #("bump_map")
                    #displacement: #("displacement_map")
                    #opacity: #("cutout_map")
                    #emission: #("emit_color_map", "emission_map")
                    #translucency: #("trans_color_map", "transparency_map")
                    #specular: #("refl_color_map")
                    default: #()
                )
            )
            #arnold:
            (
                case channel of
                (
                    #diffuse: #("base_color_shader")
                    #ao: #("base_color_shader")
                    #roughness: #("specular_roughness_shader")
                    #glossiness: #("specular_roughness_shader")
                    #metallic: #("metalness_shader")
                    #normal: #("normal_shader")
                    #bump: #("normal_shader")
                    #opacity: #("opacity_shader")
                    #emission: #("emission_color_shader")
                    #translucency: #("transmission_shader")
                    #specular: #("specular_color_shader")
                    default: #()
                )
            )
            #redshift:
            (
                case channel of
                (
                    #diffuse: #("base_color_map")
                    #ao: #("base_color_map")
                    #roughness: #("refl_roughness_map")
                    #glossiness: #("refl_roughness_map")
                    #metallic: #("metalness_map")
                    #normal: #("bump_input")
                    #bump: #("bump_input")
                    #displacement: #("displacement_input")
                    #opacity: #("opacity_color_map")
                    #emission: #("emission_color_map")
                    #translucency: #("refr_color_map")
                    #specular: #("refl_color_map")
                    default: #()
                )
            )
            #vray:
            (
                case channel of
                (
                    #diffuse: #("texmap_diffuse", "diffuse_texmap", "diffuseMap")
                    #ao: #("texmap_diffuse", "diffuse_texmap", "diffuseMap")
                    #roughness: #("texmap_roughness", "roughness_texmap", "texmap_reflectionRoughness", "reflectionRoughness_texmap", "reflection_roughness_texmap")
                    #glossiness: #("texmap_reflectionGlossiness", "reflectionGlossiness_texmap", "reflection_glossiness_texmap")
                    #metallic: #("texmap_metalness", "metalness_texmap", "texmap_metallic", "metallic_texmap")
                    #normal: #("texmap_bump", "bump_texmap", "bumpMap")
                    #bump: #("texmap_bump", "bump_texmap", "bumpMap")
                    #displacement: #("texmap_displacement", "displacement_texmap", "displacementMap")
                    #opacity: #("texmap_opacity", "opacity_texmap", "opacityMap")
                    #emission: #("texmap_self_illumination", "selfIllumination_texmap", "self_illumination_texmap")
                    #translucency: #("texmap_translucent", "translucent_texmap", "texmap_translucency")
                    #specular: #("texmap_reflection", "reflection_texmap", "reflectionMap")
                    default: #()
                )
            )
            #octaneStandard:
            (
                case channel of
                (
                    #diffuse: #("baseColor_tex", "albedo_tex")
                    #ao: #("baseColor_tex", "albedo_tex")
                    #roughness: #("roughness_tex")
                    #glossiness: #("roughness_tex")
                    #metallic: #("metallic_tex")
                    #normal: #("normal_tex")
                    #bump: #("bump_tex")
                    #displacement: #("displacement")
                    #opacity: #("opacity_tex")
                    #emission: #("emissionColor_tex", "emission")
                    #translucency: #("transmissionColor_tex", "transmission_tex")
                    #specular: #("specularColor_tex", "specular_tex")
                    default: #()
                )
            )
            #octanePbr:
            (
                case channel of
                (
                    #diffuse: #("baseColor_tex")
                    #ao: #("baseColor_tex")
                    #roughness: #("roughness_tex")
                    #glossiness: #("roughness_tex")
                    #metallic: #("metallic_tex")
                    #normal: #("normal_tex")
                    #bump: #("bump_tex")
                    #displacement: #("displacement")
                    #opacity: #("opacity_tex")
                    #emission: #("emissionColor_tex", "emission")
                    #translucency: #("transmissionColor_tex")
                    #specular: #("specularColor_tex", "specular_tex")
                    default: #()
                )
            )
            #octaneUniversal:
            (
                case channel of
                (
                    #diffuse: #("albedo_tex")
                    #ao: #("albedo_tex")
                    #roughness: #("roughness_tex")
                    #glossiness: #("roughness_tex")
                    #metallic: #("metallic_tex")
                    #normal: #("normal_tex")
                    #bump: #("bump_tex")
                    #displacement: #("displacement")
                    #opacity: #("opacity_tex")
                    #emission: #("emission")
                    #translucency: #("transmission_tex")
                    #specular: #("specular_tex")
                    default: #()
                )
            )
            default:
            (
                case channel of
                (
                    #diffuse: #("base_color_map", "baseColor_map", "basecolor_map", "base_map", "diffuse_map")
                    #ao: #("base_color_map", "baseColor_map", "basecolor_map", "base_map", "diffuse_map")
                    #roughness: #("roughness_map", "specular_roughness_map", "base_roughness_map")
                    #glossiness: #("roughness_map", "specular_roughness_map", "base_roughness_map")
                    #metallic: #("metalness_map", "metallic_map", "base_metalness_map")
                    #normal: #("bump_map", "normal_map")
                    #bump: #("bump_map", "normal_map")
                    #displacement: #("displacement_map")
                    #opacity: #("opacity_map", "cutout_map", "transparency_map")
                    #emission: #("emission_color_map", "emit_color_map", "emission_map")
                    #translucency: #("transmission_color_map", "trans_color_map", "transmission_map")
                    #specular: #("specular_color_map", "refl_color_map")
                    default: #()
                )
            )
        )
    ),

    fn wireMap mat channel channelLabel tex renderer =
    (
        local slotName = setFirstMap mat (slotCandidates renderer channel) tex
        enableMapSlot mat slotName
        if slotName != undefined then (channelLabel + "->" + slotName + ", ") else ""
    ),

    fn makeMaterialXExtract sourceMap channelIndex nodeName =
    (
        local extract = makeMaterialXOslMap "extract_color3.osl" nodeName
        extract.In_map = sourceMap
        extract.index = channelIndex
        extract
    ),

    fn addMaterialXOrmSplit mapPairs filepath =
    (
        local stem = getFilenameFile filepath
        local orm = makeMaterialXOslMap "tiledimage_color3.osl" stem
        orm.file = filepath
        orm.file_colorspace = ""
        setMapPair mapPairs #ao (makeMaterialXExtract orm 0 (stem + "_AO_R"))
        setMapPair mapPairs #roughness (makeMaterialXExtract orm 1 (stem + "_Roughness_G"))
        setMapPair mapPairs #metallic (makeMaterialXExtract orm 2 (stem + "_Metallic_B"))
        true
    ),

    fn addOctaneChannelPick sourceImg colorChannelIndex nodeName =
    (
        local picker = Channel_picker()
        picker.name = nodeName
        picker.texture_tex = sourceImg
        picker.texture_input_type = 2
        picker.colorChannel = colorChannelIndex
        picker
    ),

    fn addOctaneOrmSplit mapPairs filepath =
    (
        local stem = getFilenameFile filepath
        try
        (
            local img = Image_MTX()
            img.name = stem
            img.filename = filepath
            -- Leave colorSpace at default; the Channel_picker downstream sets per-channel handling.
            setMapPair mapPairs #ao (addOctaneChannelPick img 0 (stem + "_AO_R"))
            setMapPair mapPairs #roughness (addOctaneChannelPick img 1 (stem + "_Roughness_G"))
            setMapPair mapPairs #metallic (addOctaneChannelPick img 2 (stem + "_Metallic_B"))
            true
        )
        catch false
    ),

    fn addOrmSplit mapPairs filepath renderer:#openpbr =
    (
        if renderer == #materialx do return (addMaterialXOrmSplit mapPairs filepath)
        if isOctaneRenderer renderer do return (addOctaneOrmSplit mapPairs filepath)

        local stem = getFilenameFile filepath
        local oslPath = (getDir #maxRoot) + "OSL\\UberBitmap2.osl"
        try
        (
            local uber = OSLMap()
            uber.name = stem
            uber.OSLPath = oslPath
            uber.OSLAutoUpdate = true
            uber.filename = filepath

            local outR = MultiOutputChannelTexmapToTexmap()
            outR.sourceMap = uber
            outR.outputChannelIndex = 2
            setMapPair mapPairs #ao outR

            local outG = MultiOutputChannelTexmapToTexmap()
            outG.sourceMap = uber
            outG.outputChannelIndex = 3
            setMapPair mapPairs #roughness outG

            local outB = MultiOutputChannelTexmapToTexmap()
            outB.sourceMap = uber
            outB.outputChannelIndex = 4
            setMapPair mapPairs #metallic outB
            true
        )
        catch false
    ),

    fn makeAoComposite diffuseMap aoMap renderer =
    (
        if renderer == #materialx then
        (
            local mult = makeMaterialXOslMap "multiply_color3FA.osl" "Diffuse_AO"
            mult.in1_map = diffuseMap
            mult.in2_map = aoMap
            mult
        )
        else if renderer == #arnold then
        (
            local mult = undefined
            try
            (
                mult = ai_multiply name:"Diffuse_AO"
                mult.input1_shader = diffuseMap
                mult.input2_shader = aoMap
            )
            catch ()
            if mult != undefined then mult else diffuseMap
        )
        else if isOctaneRenderer renderer then
        (
            -- Multiply_MTX collapses color to greyscale regardless of textureValueType.
            -- Multiply_texture preserves RGB across both inputs.
            local mult = undefined
            try
            (
                mult = Multiply_texture()
                mult.name = "Diffuse_AO"
                mult.texture1_tex = diffuseMap
                mult.texture1_input_type = 2
                mult.texture2_tex = aoMap
                mult.texture2_input_type = 2
            )
            catch ()
            if mult != undefined then mult else diffuseMap
        )
        else
        (
            local comp = CompositeTexturemap()
            comp.name = "Diffuse_AO"
            comp.mapList[1] = diffuseMap
            comp.mapList[2] = aoMap
            comp.blendMode[2] = 5
            comp
        )
    ),

    fn makeGlossToRough glossMap renderer =
    (
        if renderer == #materialx then
        (
            local inv = makeMaterialXOslMap "invert_float.osl" "GlossToRough"
            inv.In_map = glossMap
            inv.amount = 1.0
            inv
        )
        else if isOctaneRenderer renderer then
        (
            local inv = undefined
            try
            (
                inv = Invert_MTX()
                inv.name = "GlossToRough"
                inv.input_tex = glossMap
                inv.input_input_type = 2
            )
            catch ()
            if inv != undefined then inv else glossMap
        )
        else
        (
            local inv = Output name:"GlossToRough"
            inv.map1 = glossMap
            inv.output.invert = true
            inv
        )
    ),

    fn makeNormalNode normalMap bumpMap renderer =
    (
        if renderer == #materialx then
        (
            local normalNode = makeMaterialXOslMap "normalmap.osl" "NormalMap"
            normalNode.In_map = normalMap
            normalNode.space = "tangent"
            normalNode.scale = 1.0
            normalNode
        )
        else if renderer == #arnold then
        (
            local normalNode = undefined
            try (normalNode = ai_normal_map name:"NormalMap" input_shader:normalMap) catch ()
            if normalNode == undefined do normalNode = normalMap
            if bumpMap != undefined then
            (
                local bumpNode = undefined
                try
                (
                    bumpNode = ai_bump2d name:"NormalBump"
                    bumpNode.bump_map_shader = bumpMap
                    bumpNode.normal_shader = normalNode
                )
                catch ()
                if bumpNode != undefined then bumpNode else normalNode
            )
            else normalNode
        )
        else if renderer == #redshift then
        (
            local bumpNode = RS_BumpMap name:"NormalMap"
            bumpNode.input_map = normalMap
            bumpNode.inputType = 1
            bumpNode
        )
        else if renderer == #vray then
        (
            local normalNode = undefined
            try
            (
                normalNode = VRayNormalMap name:"NormalMap"
                normalNode.normal_map = normalMap
                if bumpMap != undefined do normalNode.bump_map = bumpMap
            )
            catch ()
            if normalNode != undefined then normalNode else normalMap
        )
        else if isOctaneRenderer renderer then
        (
            -- Octane materials have BOTH normal_tex AND bump_tex slots; no wrapper needed.
            -- The bump map (if any) is wired separately to bump_tex by makeGroupedPbrMaterial.
            normalMap
        )
        else
        (
            local bumpNode = Normal_Bump name:"NormalBump"
            bumpNode.normal_map = normalMap
            if bumpMap != undefined do bumpNode.bump_map = bumpMap
            bumpNode
        )
    ),

    fn makeBumpNode bumpMap renderer =
    (
        if renderer == #materialx then
        (
            local heightToNormal = makeMaterialXOslMap "heighttonormal_vector3.osl" "BumpHeightToNormal"
            heightToNormal.In_map = bumpMap
            heightToNormal.scale = 1.0
            local normalNode = makeMaterialXOslMap "normalmap.osl" "BumpNormalMap"
            normalNode.In_map = heightToNormal
            normalNode.space = "tangent"
            normalNode.scale = 1.0
            normalNode
        )
        else if renderer == #arnold then
        (
            local bumpNode = ai_bump2d name:"Bump"
            bumpNode.bump_map_shader = bumpMap
            bumpNode
        )
        else if renderer == #redshift then
        (
            local bumpNode = RS_BumpMap name:"Bump"
            bumpNode.input_map = bumpMap
            bumpNode.inputType = 0
            bumpNode
        )
        else if renderer == #vray then
        (
            bumpMap
        )
        else if isOctaneRenderer renderer then
        (
            bumpMap
        )
        else
        (
            local bumpNode = Normal_Bump name:"Bump"
            bumpNode.bump_map = bumpMap
            bumpNode
        )
    ),

    fn makeGroupedPbrMaterial group renderer materialPrefix:"tex_" includeDisplacement:true =
    (
        local matName = materialPrefix + group[1]
        local mat = createRendererMaterial renderer matName
        local channels = group[2]
        local mapPairs = #()
        local channelList = ""

        if renderer == #vray do try (mat.brdf_useRoughness = true) catch ()
        setFirstValue mat #("specular_color", "specularColor", "specular", "refl_color", "reflection") (color 255 255 255)

        for pair in channels do
        (
            local channel = pair[1]
            local filepath = pair[2]
            if channel == #orm then
            (
                addOrmSplit mapPairs filepath renderer:renderer
            )
            else
            (
                setMapPair mapPairs channel (makeRendererBitmap filepath channel renderer)
            )
        )

        local diffuseMap = getMapPair mapPairs #diffuse
        local aoMap = getMapPair mapPairs #ao
        if diffuseMap != undefined then
        (
            if aoMap != undefined then
            (
                channelList += wireMap mat #diffuse "diffuse(+ao)" (makeAoComposite diffuseMap aoMap renderer) renderer
            )
            else
            (
                channelList += wireMap mat #diffuse "diffuse" diffuseMap renderer
            )
        )

        local roughMap = getMapPair mapPairs #roughness
        local glossMap = getMapPair mapPairs #glossiness
        if roughMap != undefined then
        (
            channelList += wireMap mat #roughness "roughness" roughMap renderer
        )
        else if glossMap != undefined then
        (
            channelList += wireMap mat #glossiness "glossiness(inverted)" (makeGlossToRough glossMap renderer) renderer
        )

        local metalMap = getMapPair mapPairs #metallic
        if metalMap != undefined do channelList += wireMap mat #metallic "metallic" metalMap renderer

        local normalMap = getMapPair mapPairs #normal
        local bumpMap = getMapPair mapPairs #bump
        if normalMap != undefined then
        (
            channelList += wireMap mat #normal "normal" (makeNormalNode normalMap bumpMap renderer) renderer
            -- Octane materials expose both normal_tex and bump_tex; wire bump separately too.
            if isOctaneRenderer renderer and bumpMap != undefined do
            (
                channelList += wireMap mat #bump "bump" bumpMap renderer
            )
        )
        else if bumpMap != undefined then
        (
            channelList += wireMap mat #bump "bump" (makeBumpNode bumpMap renderer) renderer
        )

        local optionalChannels = if includeDisplacement then #(#displacement, #opacity, #emission, #translucency, #specular) else #(#opacity, #emission, #translucency, #specular)
        for channel in optionalChannels do
        (
            local tex = getMapPair mapPairs channel
            if tex != undefined do
            (
                -- Octane's displacement slot only accepts Texture_displacement; raw Image_MTX is rejected.
                if channel == #displacement and isOctaneRenderer renderer do
                (
                    local td = Texture_displacement()
                    td.name = "Displacement"
                    td.texture_tex = tex
                    td.texture_input_type = 2
                    tex = td
                )
                channelList += wireMap mat channel (channel as string) tex renderer
            )
        )

        #(mat, channelList)
    ),

    fn loadFolder folder mode:#material startSlot:1 maxSlots:24 recursive:false materialPrefix:"tex_" openEditor:true renderer:#openpbr includeDisplacement:true =
    (
        local root = normalizedFolder folder
        if root.count == 0 do throw "Folder path is empty."

        local slotStart = amax 1 (amin 24 (startSlot as integer))
        local slotMax = amax 1 (amin (24 - slotStart + 1) (maxSlots as integer))
        local files = getImageFiles root recursive:recursive

        if files.count == 0 then
        (
            local msg = "No image files found in: " + root
            format "%\n" msg
            return msg
        )

        if openEditor do
        (
            try (MatEditor.mode = #basic) catch ()
            try (MatEditor.Open()) catch ()
        )

        local loaded = #()
        local classes = #()
        local slotIndex = slotStart
        local slotMode = if mode == #bitmap then #bitmap else if mode == #pbr then #pbr else #material

        if slotMode == #pbr then
        (
            local grouped = groupTextureFiles files
            local groups = grouped[1]
            local unmatched = grouped[2]
            local duplicates = grouped[3]
            local limit = amin groups.count slotMax

            if groups.count == 0 then
            (
                local msg = "No texture sets matched any PBR channel pattern."
                format "%\n" msg
                return msg
            )

            for i = 1 to limit do
            (
                local made = makeGroupedPbrMaterial groups[i] renderer materialPrefix:materialPrefix includeDisplacement:includeDisplacement
                local mat = made[1]
                putInMaterialEditor mat slotIndex
                append loaded ((slotIndex as string) + ": " + mat.name + " [" + made[2] + "]")
                appendIfUnique classes ((classOf mat) as string)
                slotIndex += 1
            )

            local msg = "Loaded " + (loaded.count as string) + " grouped PBR material(s) into Material Editor slots using " + (rendererLabel renderer)
            if loaded.count > 0 do msg += " [" + loaded[1] + " .. " + loaded[loaded.count] + "]"
            if classes.count > 0 do msg += " | Classes: " + (classes as string)
            if unmatched.count > 0 do msg += " | Unmatched image(s) skipped: " + (unmatched.count as string)
            if duplicates.count > 0 do msg += " | Duplicate channel file(s) skipped: " + (duplicates.count as string)
            format "%\n" msg
            return msg
        )

        local limit = amin files.count slotMax
        for i = 1 to limit do
        (
            local item = if slotMode == #bitmap then makeBitmap files[i] else makePreviewMaterial files[i] materialPrefix:materialPrefix
            putInMaterialEditor item slotIndex
            append loaded ((slotIndex as string) + ": " + (getFilenameFile files[i]) + " -> " + ((classOf item) as string))
            appendIfUnique classes ((classOf item) as string)
            slotIndex += 1
        )

        local label = if slotMode == #bitmap then "bitmap texture map" else "OpenPBR-first texture material"
        local msg = "Loaded " + (loaded.count as string) + " " + label + "(s) into Material Editor slots"
        if loaded.count > 0 do msg += " [" + loaded[1] + " .. " + loaded[loaded.count] + "]"
        if classes.count > 0 do msg += " | Classes: " + (classes as string)
        format "%\n" msg
        msg
    )
)

CloneTextureFolderPalette = CloneTextureFolderPaletteStruct()
global CloneTextureFolderPalette_Form
global CloneTextureFolderPalette_rbGrouped
global CloneTextureFolderPalette_rbBitmap
global CloneTextureFolderPalette_ddlRenderer
global CloneTextureFolderPalette_chkDisplacement
global CloneTextureFolderPalette_edtFolder
global CloneTextureFolderPalette_spnStart
global CloneTextureFolderPalette_spnMax
global CloneTextureFolderPalette_chkRecursive
global CloneTextureFolderPalette_chkOpenEditor
global CloneTextureFolderPalette_edtPrefix
global CloneTextureFolderPalette_lblStatus
global CloneTextureFolderPalette_Handlers

fn CloneTextureFolderPalette_OpenDialog =
(
    try(if CloneUI == undefined do fileIn ((getDir #userScripts) + "\\CloneTools\\CloneUI.ms"))catch(try(fileIn ((getFilenamePath (getSourceFileName())) + "..\\Utilities\\CloneUI.ms"))catch())
    try(CloneTextureFolderPalette_Form.Close())catch()
    try(CloneTextureFolderPalette_Form.Dispose())catch()
    CloneTextureFolderPalette_Form = dotNetObject "System.Windows.Forms.Form"

    local frm = CloneUI.skinForm CloneTextureFolderPalette_Form "Texture Folder Palette" 420 620
    local shell = CloneUI.addShell frm "Texture Folder Palette" version:"v1.0"
    local pad = shell[1]
    local iW = shell[2]
    local Y = shell[3]

    frm.controls.add (CloneUI.mkLabel "Folder" (pad+4) Y 70 18 fObj:CloneUI.fSmall cObj:CloneUI.cDim)
    Y += 22
    CloneTextureFolderPalette_edtFolder = CloneUI.mkText pad Y (iW - 72) 22
    local btn_browse = CloneUI.mkBtn "Browse" (pad + iW - 64) (Y-1) 64 24
    frm.controls.add CloneTextureFolderPalette_edtFolder
    frm.controls.add btn_browse
    Y += 42

    frm.controls.add (CloneUI.mkSep pad Y iW)
    Y += 12
    frm.controls.add (CloneUI.mkLabel "SLOT CONTENT" pad Y iW 18 fObj:CloneUI.fBold cObj:CloneUI.cHead)
    Y += 24

    local rbPreview = dotNetObject "System.Windows.Forms.RadioButton"
    rbPreview.Text = "OpenPBR Preview"
    rbPreview.Checked = true
    CloneTextureFolderPalette_rbBitmap = dotNetObject "System.Windows.Forms.RadioButton"
    CloneTextureFolderPalette_rbBitmap.Text = "Raw Bitmaps"
    CloneTextureFolderPalette_rbGrouped = dotNetObject "System.Windows.Forms.RadioButton"
    CloneTextureFolderPalette_rbGrouped.Text = "Grouped PBR"
    local radios = #(rbPreview, CloneTextureFolderPalette_rbBitmap, CloneTextureFolderPalette_rbGrouped)
    for rb in radios do
    (
        rb.Location = dotNetObject CloneUI.ptC (pad+4) Y
        rb.Size = dotNetObject CloneUI.szC (iW-8) 22
        rb.ForeColor = CloneUI.cText
        rb.BackColor = CloneUI.cBg
        rb.Font = CloneUI.fNorm
        frm.controls.add rb
        Y += 24
    )
    Y += 8

    frm.controls.add (CloneUI.mkSep pad Y iW)
    Y += 12
    frm.controls.add (CloneUI.mkLabel "GROUPED PBR" pad Y iW 18 fObj:CloneUI.fBold cObj:CloneUI.cHead)
    Y += 26

    frm.controls.add (CloneUI.mkLabel "Renderer" (pad+4) Y 90 18 fObj:CloneUI.fSmall cObj:CloneUI.cDim)
    CloneTextureFolderPalette_ddlRenderer = dotNetObject "System.Windows.Forms.ComboBox"
    CloneTextureFolderPalette_ddlRenderer.Location = dotNetObject CloneUI.ptC (pad+112) (Y-2)
    CloneTextureFolderPalette_ddlRenderer.Size = dotNetObject CloneUI.szC 160 22
    CloneTextureFolderPalette_ddlRenderer.DropDownStyle = (dotNetClass "System.Windows.Forms.ComboBoxStyle").DropDownList
    CloneTextureFolderPalette_ddlRenderer.BackColor = CloneUI.clr.FromArgb 38 38 38
    CloneTextureFolderPalette_ddlRenderer.ForeColor = CloneUI.cText
    for item in #("OpenPBR", "Physical", "Arnold", "Redshift", "V-Ray", "MaterialX", "Octane Std", "Octane PBR", "Octane Universal") do CloneTextureFolderPalette_ddlRenderer.Items.Add item
    CloneTextureFolderPalette_ddlRenderer.SelectedIndex = 0
    frm.controls.add CloneTextureFolderPalette_ddlRenderer
    Y += 32
    CloneTextureFolderPalette_chkDisplacement = CloneUI.mkCheck "Wire displacement maps" (pad+4) Y (iW-8) chk:true
    frm.controls.add CloneTextureFolderPalette_chkDisplacement
    Y += 36

    frm.controls.add (CloneUI.mkSep pad Y iW)
    Y += 12
    frm.controls.add (CloneUI.mkLabel "PALETTE SLOTS" pad Y iW 18 fObj:CloneUI.fBold cObj:CloneUI.cHead)
    Y += 26

    frm.controls.add (CloneUI.mkLabel "Start Slot" (pad+4) Y 90 18 fObj:CloneUI.fSmall cObj:CloneUI.cDim)
    CloneTextureFolderPalette_spnStart = CloneUI.mkNumeric (pad+112) (Y-2) 70 1 24 1
    frm.controls.add CloneTextureFolderPalette_spnStart
    frm.controls.add (CloneUI.mkLabel "Max Slots" (pad+205) Y 80 18 fObj:CloneUI.fSmall cObj:CloneUI.cDim)
    CloneTextureFolderPalette_spnMax = CloneUI.mkNumeric (pad+292) (Y-2) 70 1 24 24
    frm.controls.add CloneTextureFolderPalette_spnMax
    Y += 38

    frm.controls.add (CloneUI.mkSep pad Y iW)
    Y += 12
    frm.controls.add (CloneUI.mkLabel "OPTIONS" pad Y iW 18 fObj:CloneUI.fBold cObj:CloneUI.cHead)
    Y += 26

    CloneTextureFolderPalette_chkRecursive = CloneUI.mkCheck "Include subfolders" (pad+4) Y 160 chk:false
    CloneTextureFolderPalette_chkOpenEditor = CloneUI.mkCheck "Open Compact Material Editor" (pad+190) Y 200 chk:true
    frm.controls.add CloneTextureFolderPalette_chkRecursive
    frm.controls.add CloneTextureFolderPalette_chkOpenEditor
    Y += 30

    frm.controls.add (CloneUI.mkLabel "Material Prefix" (pad+4) Y 100 18 fObj:CloneUI.fSmall cObj:CloneUI.cDim)
    CloneTextureFolderPalette_edtPrefix = CloneUI.mkText (pad+112) (Y-2) 160 22 text:"tex_"
    frm.controls.add CloneTextureFolderPalette_edtPrefix
    Y += 42

    local btn_load = CloneUI.mkBtn "Load Folder To Palette" pad Y iW 32
    frm.controls.add btn_load
    Y += 40
    CloneTextureFolderPalette_lblStatus = CloneUI.mkLabel "" pad Y iW 36 fObj:CloneUI.fSmall cObj:CloneUI.cDim
    frm.controls.add CloneTextureFolderPalette_lblStatus
    Y += 42

    local credit = CloneUI.mkLabel "clone" 0 Y 420 16 fObj:CloneUI.fSmall cObj:(CloneUI.clr.FromArgb 55 55 55)
    credit.TextAlign = CloneUI.alC.MiddleCenter
    frm.controls.add credit
    frm.Size = dotNetObject CloneUI.szC 420 (Y + 24)

    fn updateRendererUi s e =
    (
        local isGrouped = CloneTextureFolderPalette_rbGrouped.Checked
        CloneTextureFolderPalette_ddlRenderer.Enabled = isGrouped
        CloneTextureFolderPalette_chkDisplacement.Enabled = isGrouped
    )

    fn onBrowseTextureFolder s e =
    (
        local picked = getSavePath caption:"Choose texture folder"
        if picked != undefined do CloneTextureFolderPalette_edtFolder.Text = picked
    )

    fn onLoadTextureFolder s e =
    (
        try
        (
            local mode = if CloneTextureFolderPalette_rbBitmap.Checked then #bitmap else if CloneTextureFolderPalette_rbGrouped.Checked then #pbr else #material
            local renderer = CloneTextureFolderPalette.rendererFromSelection (CloneTextureFolderPalette_ddlRenderer.SelectedIndex + 1)
            local result = CloneTextureFolderPalette.loadFolder CloneTextureFolderPalette_edtFolder.Text mode:mode startSlot:(CloneTextureFolderPalette_spnStart.Value as integer) maxSlots:(CloneTextureFolderPalette_spnMax.Value as integer) recursive:CloneTextureFolderPalette_chkRecursive.Checked materialPrefix:CloneTextureFolderPalette_edtPrefix.Text openEditor:CloneTextureFolderPalette_chkOpenEditor.Checked renderer:renderer includeDisplacement:CloneTextureFolderPalette_chkDisplacement.Checked
            CloneTextureFolderPalette_lblStatus.Text = result
        )
        catch
        (
            CloneTextureFolderPalette_lblStatus.Text = "Error: " + (getCurrentException())
            format "%\n" CloneTextureFolderPalette_lblStatus.Text
        )
    )

    dotNet.addEventHandler rbPreview "CheckedChanged" updateRendererUi
    dotNet.addEventHandler CloneTextureFolderPalette_rbBitmap "CheckedChanged" updateRendererUi
    dotNet.addEventHandler CloneTextureFolderPalette_rbGrouped "CheckedChanged" updateRendererUi
    dotNet.addEventHandler btn_browse "Click" onBrowseTextureFolder
    dotNet.addEventHandler btn_load "Click" onLoadTextureFolder
    -- Keep handlers alive across the dialog's lifetime. Replace (not append) so the
    -- list does not grow unbounded across open/close cycles. Also resilient when
    -- CloneUI_handlers is undefined because CloneUI.ms failed to load first.
    CloneTextureFolderPalette_Handlers = #(updateRendererUi, onBrowseTextureFolder, onLoadTextureFolder)
    updateRendererUi undefined undefined
    frm.Show()
)

macroScript TextureFolderPalette
category:"CloneTools"
tooltip:"Texture Folder Palette"
buttonText:"Texture Palette"
(
    -- Max persists this macroScript body across sessions, but not the struct/
    -- function definitions above. After a restart fileIn the source so the
    -- globals exist; the source's trailing auto-open then shows the dialog.
    on execute do
    (
        if CloneTextureFolderPalette_OpenDialog == undefined then
        (
            local sourcePath = (getDir #userScripts) + "\\CloneTools\\TextureFolderPalette.ms"
            if doesFileExist sourcePath then
                fileIn sourcePath
            else
                messageBox ("TextureFolderPalette.ms not found at:\n" + sourcePath) title:"Texture Folder Palette"
        )
        else CloneTextureFolderPalette_OpenDialog()
    )
)

CloneTextureFolderPalette_OpenDialog()
