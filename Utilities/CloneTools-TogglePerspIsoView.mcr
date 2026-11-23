macroScript TogglePerspIsoView
category: "CloneTools"
tooltip: "Toggle Perspective/Isometric User View"
buttonText: "Toggle Persp/Iso"
(
	on execute do viewport.setType (if viewport.getType() == #view_persp_user then #view_iso_user else #view_persp_user)
)
