macroScript RotationAxisSnap
category: "CloneTools"
tooltip: "Switch active viewport to the view closely aligned to the screen axis"
(
	global sType;

	fn alignViewportToObjectZ obj =
	(
		local objTM = obj.transform
		local selTM = matrix3 (normalize objTM.row1) (normalize objTM.row2) (normalize objTM.row3) objTM.row4
		-- Lock grid roll to local X so the result is deterministic.
		local selX = -normalize selTM.row1
		local selY = normalize (cross selX selTM.row3)
		local theMatrix
		local coordSysTM = inverse (getViewTM())
		local viewPos = coordSysTM.row4
		local theDistance = distance viewPos obj.pos
		theMatrix = matrix3 selX selY (-selTM.row3) selTM.row4
		preRotateY theMatrix 180
		preTranslate theMatrix [0,0,theDistance]

		viewport.setTM (inverse theMatrix)
	)

	local vpType = viewport.getType()
	local selectedGrid = (selection.count == 1 and classOf selection[1] == Grid)

	if (selectedGrid and (vpType == #view_persp_user or vpType == #view_iso_user)) then
	(
		alignViewportToObjectZ selection[1]
	)
	else if (vpType==#view_left or vpType==#view_right or vpType==#view_front or vpType==#view_back or vpType==#view_bottom or vpType==#view_top) 
	then(
			try(
				viewport.setType sType
				actionMan.executeAction 0 "40228"  -- Views: Restore Active View
			)catch()
	)	
	else (
			local temp = viewport.getTM() as EulerAngles
			
			sType = viewport.getType()
			actionMan.executeAction 0 "40227"  -- Views: Save Active View
			
			case of
				(
					(45<=temp.y and temp.y<=135): viewport.setType #view_left
					(-45>=temp.y and temp.y>=-135): viewport.setType #view_right
					((-45>=temp.x and temp.x>=-135) and (-45<=temp.y and temp.y<=45)): viewport.setType #view_front
					((45<=temp.x and temp.x<=135) and (-45<=temp.y and temp.y<=45)): viewport.setType #view_back
					((135<=temp.x and temp.x<=180) or (-135>=temp.x and temp.x>=-180)): viewport.setType #view_bottom
					default: viewport.setType #view_top
				)	 
			max zoomext sel
	)
	completeredraw()
)
