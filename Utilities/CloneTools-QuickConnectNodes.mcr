macroScript QuickConnectNodes
category: "CloneTools"
tooltip: "Slate Material Editor: auto-connect selected texture maps to material slots using connector_rules.json"
(
	local scriptPath = (getDir #userScripts) + @"\CloneTools\connector.ms"
	if doesFileExist scriptPath then
		fileIn scriptPath
	else
		messageBox ("Script not found:\n" + scriptPath) title:"Quick Connect Nodes"
)
