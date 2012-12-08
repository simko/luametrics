
local pairs, print, table= pairs, print, table

local utils = require 'metrics.utils'
local HG = require 'hypergraph'
local keys = (require 'metrics.rules').rules

module ('metrics.captures.hypergraph')

graph = HG.H{}

function getHyperGraphNodeFromNode(node)
	if node.hypergraphnode then return node.hypergraphnode end

	local hypergraphnode = HG.N(node.tag)
	hypergraphnode.nodeid = node.nodeid;
	
	node.hypergraphnode = hypergraphnode

	return hypergraphnode
end

function getCallerCalee(masterNode, functionName)

	local returnValues = {}

	for k,v in pairs(masterNode.metrics.functionExecutions[functionName] or {}) do
		--print ('Call node', v.tag, v.nodeid, v.text)

		-- find caller function

		local parent = v.parent

		while (parent ~= nil and parent.tag ~= 'GlobalFunction' and parent.tag ~= 'LocalFunction' and parent.tag ~= 'Function') do
			--print ('', parent.tag)
			parent = parent.parent
		end

		if (parent ~= nil) then
			-- found enclosing function
			--print ('Caller function', parent.tag, parent.nodeid,  parent.name)
		end


		local calee 

		for i,j in pairs(masterNode.metrics.functionDefinitions) do
			if (j.name == functionName) then
				calee = j
			end		
		end

		if (calee ~= nil) then
			--print ('Callee function', calee.tag, calee.nodeid,  calee.name)
		end
	
		table.insert(returnValues, {v, parent, calee})

	end
	return returnValues
end

function getVariableCommonPoint(node, name)
--	print ('looking for', node.nodeid, name)
	local parent = node.parent
	
	while true do 
		if parent == nill or parent.parent == nil then return node end
		parent = parent.parent 
		
		if parent.tag == 'Block' then
			for localname, occurences in pairs(parent.metrics.blockdata.locals) do
--				print ('', occurences[1])
				if occurences[1] == name then
--					print ('', 'found', occurences[2][1], occurences[2][1].nodeid, occurences[2][1].text)
					for k,v in pairs(occurences[2][1]) do
--						print ('','',k,v)
					end
					return occurences[2][1]
				end
			end
		end
	end
	
end

captures = (function()
	local key,value
	local new_table = {}
	for key,value in pairs(keys) do
		new_table[key] = function (data) 

			local currentHyperNode = getHyperGraphNodeFromNode(data);
			for _, child in pairs(data.data or {}) do
				graph[HG.E'treerelation'] = { [HG.I'parent'] = currentHyperNode, [HG.I'child'] = getHyperGraphNodeFromNode(child) }
			end

			return data 
		end
	end
	
	new_table[1] = function (node) 

		local currentHyperNode = getHyperGraphNodeFromNode(node);
		local	codeblock = utils.searchForTagItem_recursive('Block', node, 2)
				
		for _, child in pairs(node.data or {}) do
			graph[HG.E'treerelation'] = { [HG.I'parent'] = currentHyperNode, [HG.I'child'] = getHyperGraphNodeFromNode(child) }
		end


		for _, functionNode in pairs(node.metrics.functionDefinitions) do
			if functionNode.name then 
				local calleevalues = getCallerCalee(node, functionNode.name) 
				for _, value in pairs(calleevalues) do
					--[[
					print ('-----------')
					print ('Call node', value[1].tag, value[1].nodeid, value[1].text)
					print ('Caller function', value[2].tag, value[2].nodeid,  value[2].name)
					print ('Callee function', value[3].tag, value[3].nodeid,  value[3].name)
					print ('-----------')
					]]--
					local callnode = getHyperGraphNodeFromNode(value[1])
					callnode.shortname = value[1].text

					local caller = getHyperGraphNodeFromNode(value[2])
					caller.shortname = value[2].name

					local callee = getHyperGraphNodeFromNode(value[3])
					callee.shortname = value[3].name

					graph[HG.E'calls'] = { [HG.I'caller'] = caller, [HG.I'callee'] = callee, [HG.I'callnode'] = callnode }
				end

			end
		end

		for _, functionNode in pairs(node.metrics.functionDefinitions) do
			
			if functionNode.name then 
				local functionHyperNode = getHyperGraphNodeFromNode(functionNode)				
				local block = utils.getBlockFromFunction(functionNode)
	
				if (block) then -- should always be true but to be sure
					
					for _ , variable in pairs(block.metrics.blockdata.locals_total) do
							local edge = HG.E'uses'
							graph[edge] = { [HG.I'user'] = functionHyperNode, [HG.I'local_variable'] = getHyperGraphNodeFromNode(variable[2][1]) }
							for _ , occurence in pairs(variable[2]) do
								graph[edge][HG.I'point'] = getHyperGraphNodeFromNode(occurence)
							end
					end
					
					for name, occurences in pairs(block.metrics.blockdata.remotes) do
						local edge = HG.E'uses'
						graph[edge] = { [HG.I'user'] = functionHyperNode, [HG.I'remote_variable'] = getHyperGraphNodeFromNode(getVariableCommonPoint(occurences[1],name)) }
						for _ , occurence in pairs(occurences) do
							graph[edge][HG.I'point'] = getHyperGraphNodeFromNode(occurence)
						end
					end
					
				end
			end
		end

		node.hypergraph = graph

		graph:CreateNodes()

		return node
	end
	
	return new_table
end)()

